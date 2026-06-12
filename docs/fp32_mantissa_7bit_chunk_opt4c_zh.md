# FP32 尾数 7-bit Chunk 复用 OPT4C 技术方案

## 目标

本文档描述一种较保守、易验证的多精度扩展方案：复用现有 OPT4C 的 signed INT8 PE 数据通路，完成 FP32 乘法中的尾数乘法部分。

核心思路是：

```text
不把 FP32 尾数直接拆成 unsigned 8-bit chunk 送入 signed INT8 PE；
而是把 24-bit 尾数拆成不会触发 signed 负数解释的 7-bit chunk。
```

每个 7-bit chunk 在进入现有 INT8/OPT4C 数据通路前补 0 扩展到 8 bit。由于最高位固定为 0，该 chunk 在 unsigned 语义和 signed INT8 语义下表示的数值相同。

这样可以尽量保持 OPT4C PE 内部数据通路不变，把浮点相关的拆分、调度、移位、归约、规格化和舍入放在 PE 外部 wrapper 中完成。

## 背景

对于规格化 FP32 数：

```text
X = (-1)^sign * 1.fraction * 2^(exponent - 127)
```

硬件做乘法时，通常把尾数表示成一个 24-bit 无符号整数：

```text
M = {1'b1, fraction[22:0]}
```

因此：

```text
M 的范围是 [2^23, 2^24 - 1]
```

两个 FP32 数相乘时，尾数部分需要计算：

```text
P = M_A * M_B
```

其中 `P` 最多为 48 bit。得到 `P` 之后，浮点单元仍然需要完成符号计算、指数计算、规格化、舍入、指数修正、结果打包以及特殊值处理。

## 为什么不优先采用 8-bit Chunk

如果把 24-bit 尾数拆成三个 8-bit chunk：

```text
M = C0 + (C1 << 8) + (C2 << 16)
```

那么每个 chunk 是无符号数：

```text
0..255
```

但是现有 OPT4C PE 会把 8-bit 操作数解释为 signed two's-complement。例如：

```text
8'hC8 = 200   // unsigned
8'hC8 = -56   // signed
```

如果直接送入现有 signed INT8 PE，当 chunk 大于 127 时，硬件会把它当成负数，乘法结果会错误。

8-bit chunk 方案并非不可行，但需要额外处理：

```text
1. 修改 PE，使其支持 signed/unsigned 模式；
2. 在 signed PE 结果外加入 unsigned 修正项；
3. 引入类似 BADA 的乘法前表示转换。
```

这些方法都会增加 PE 内部或 PE 周围的修正逻辑。考虑到现有 OPT4C N=32 的综合结果已经显示关键路径主要位于 PE 内部 mux/compressor/accumulation 路径，第一版设计更适合避免继续加重 PE 内部关键路径。

## 7-bit Chunk 表示方式

将 24-bit 尾数拆成 4 个 chunk：

```text
M = C0 + (C1 << 7) + (C2 << 14) + (C3 << 21)
```

其中：

```text
C0 = M[6:0]
C1 = M[13:7]
C2 = M[20:14]
C3 = M[23:21]
```

各 chunk 的范围为：

```text
C0, C1, C2 in [0, 127]
C3 in [0, 7]
```

进入 OPT4C PE 前，将其补 0 到 8 bit：

```text
chunk8 = {1'b0, chunk7}
```

对于最高 3-bit chunk：

```text
chunk8 = {5'b0, chunk3}
```

这样 PE 看到的仍然是 signed INT8 操作数，但数值范围固定为：

```text
0..127
```

因此 signed 解释和 unsigned 解释完全一致，不需要 unsigned 修正项。

## 尾数乘法展开

对于两个 FP32 尾数：

```text
M_A = A0 + (A1 << 7) + (A2 << 14) + (A3 << 21)
M_B = B0 + (B1 << 7) + (B2 << 14) + (B3 << 21)
```

它们的乘积为：

```text
P = M_A * M_B
  = sum_i sum_j (Ai * Bj) << (7 * (i + j))
```

一共有 16 个 chunk product：

```text
A0B0
A1B0 A0B1
A2B0 A1B1 A0B2
A3B0 A2B1 A1B2 A0B3
A3B1 A2B2 A1B3
A3B2 A2B3
A3B3
```

可以按照 `i+j` 分成 7 个 diagonal group：

| Group | 左移位数 | Chunk product |
| --- | ---: | --- |
| G0 | 0 | A0B0 |
| G1 | 7 | A1B0, A0B1 |
| G2 | 14 | A2B0, A1B1, A0B2 |
| G3 | 21 | A3B0, A2B1, A1B2, A0B3 |
| G4 | 28 | A3B1, A2B2, A1B3 |
| G5 | 35 | A3B2, A2B3 |
| G6 | 42 | A3B3 |

这种 diagonal group 的好处是：同一组内所有 chunk product 具有相同的外部 global shift。

## 映射到 OPT4C

现有 OPT4C `top_pe_column` 的结构可以概括为：

```text
一个 shared sparse_encoder
N 个 sparse_pe
每个 PE 输入一个 8-bit B operand
shared partial_product_index 广播到所有 PE
```

OPT4C PE 并不是直接接收完整的 `A * B`。它的计算方式是：

```text
A 侧：经过 EN-T / sparse_encoder，生成 partial-product 控制
B 侧：作为原始 8-bit operand 输入 PE
PE：根据控制信号选择 B、2B、-B 或 -2B，并累加到 compressed sum/carry
```

对于 7-bit 尾数方案：

```text
Ai 是非负 7-bit chunk
Bj 是非负 7-bit chunk
```

A 侧映射：

```text
Ai -> zero-extend 到 8 bit -> 进入现有 A encoder / sparse_encoder 路径
```

B 侧映射：

```text
Bj -> zero-extend 到 8 bit -> 作为 operand_b_ins 输入 PE
```

因为 `Ai` 和 `Bj` 都小于 128，所以现有 signed INT8 PE 对它们的解释是正确的。

OPT4C PE 负责计算每个 `Ai * Bj` 的 chunk product。FP wrapper 负责选择当前要计算的 `(Ai, Bj)`，并在 PE 外部施加 global shift：

```text
aligned_product = chunk_product << (7 * (i + j))
```

## Wrapper 数据流

FP mantissa wrapper 可以分为五个阶段。

### 1. 解包

从 FP32 输入中提取：

```text
sign
exponent
fraction
```

对于规格化数：

```text
mantissa = {1'b1, fraction}
```

对于非规格化数，可以选择：

```text
mantissa = {1'b0, fraction}
```

或者先在第一版设计中只支持 normal finite 输入，把 subnormal 放到慢速或特殊路径中处理。

### 2. Chunk 拆分

生成两个操作数的 chunk：

```text
A0, A1, A2, A3
B0, B1, B2, B3
```

同时生成零值标志：

```text
A_valid[i] = (Ai != 0)
B_valid[j] = (Bj != 0)
pair_valid[i][j] = A_valid[i] & B_valid[j]
```

### 3. 调度

按照 diagonal group 发射 chunk product：

```text
for g in 0..6:
    for all i,j such that i+j == g:
        if pair_valid[i][j]:
            compute Ai * Bj
```

这样可以自然利用 slice-level sparsity：

```text
如果 Ai == 0 或 Bj == 0，则跳过 Ai * Bj
```

同时，同一 group 内的 global shift 固定：

```text
group_shift = 7 * g
```

### 4. 计算

对于每个有效 `(Ai, Bj)`：

```text
Ai -> A-side encoder
Bj -> B-side operand_b
OPT4C PE -> chunk product accumulation
```

PE 输出未施加 global shift 的 chunk product。wrapper 再执行：

```text
aligned_product = chunk_product << group_shift
```

### 5. 归约

将所有 aligned product 加到 48-bit 或更宽的尾数乘积累加器中：

```text
P = sum aligned_product
```

实现上可以保留若干 guard bits，用于后续舍入。更高效的实现可以在最终规格化之前继续使用 carry-save 形式，避免过早进行完整进位传播加法。

## 时分复用体现

该方案通过多周期复用同一组 OPT4C PE 资源。

最坏情况下 chunk product 数量为：

```text
4 * 4 = 16
```

diagonal group 数量为：

```text
7
```

如果一个 PE 一次只计算一个 chunk pair，那么一个 FP32 尾数乘法最多需要 16 次 chunk pair 计算。

如果 OPT4C column 中有多个 PE 可用，同一 diagonal group 内的多个 product 可以并行映射到多个 PE。例如：

```text
G3 = A3B0, A2B1, A1B2, A0B3
```

这一组包含 4 个独立 product，且它们都需要左移 21 bit，因此天然适合映射到 4 个并行 lane。

对于 4-lane 调度，各 group 的利用率为：

| Group | Product 数量 | 4-lane 利用率 |
| --- | ---: | ---: |
| G0 | 1 | 25% |
| G1 | 2 | 50% |
| G2 | 3 | 75% |
| G3 | 4 | 100% |
| G4 | 3 | 75% |
| G5 | 2 | 50% |
| G6 | 1 | 25% |

平均利用率为：

```text
16 / (7 * 4) = 57.1%
```

这是 diagonal scheduling 的主要代价。它的好处是同组 product 共享同一个 global shift，同时完全避免 unsigned/signed 语义冲突。

## 浮点后处理

得到 48-bit 尾数乘积 `P` 之后，还需要完成完整 FP32 乘法的后处理：

```text
result_sign = sign_A ^ sign_B
raw_exponent = exponent_A + exponent_B - 127
normalization
rounding
exponent correction
packing
special-case handling
```

对于规格化尾数：

```text
M_A, M_B in [1.0, 2.0)
P in [1.0, 4.0)
```

因此：

```text
if P[47] == 1:
    normalized_mantissa = P >> 24
    exponent += 1
else:
    normalized_mantissa = P >> 23
```

舍入可使用 guard、round、sticky bits。以 round-to-nearest-even 为例：

```text
round_up = guard & (round | sticky | lsb)
```

如果舍入导致 mantissa 溢出，则 exponent 还需要再加 1。

需要处理的特殊情况包括：

```text
zero
subnormal
infinity
NaN
overflow
underflow
```

第一版原型可以先支持 normal finite operand，再逐步补齐特殊情况。

## 需要新增的硬件逻辑

该方案最少需要在 OPT4C 外部新增以下模块：

| 模块 | 功能 |
| --- | --- |
| FP unpacker | 提取 sign、exponent、fraction、hidden bit |
| 7-bit chunker | 生成 A0-A3 和 B0-B3 |
| zero detector | 检测零 chunk，跳过无效 pair |
| pair scheduler | 按 diagonal group 选择 `(Ai, Bj)` |
| A-side adapter | 将选中的 `Ai` 输入现有 OPT4C encoder 路径 |
| B-side adapter | 将选中的 `Bj` zero-extend 后作为 signed-safe INT8 输入 |
| global shifter | 在 PE 外部执行 `<< 7*(i+j)` |
| product reducer | 累加所有 aligned product |
| FP normalizer | 对 48-bit product 规格化 |
| rounder | 生成最终 FP32 mantissa |
| packer | 合并 sign、exponent、fraction |

在 7-bit 方案中，OPT4C PE 本身不需要支持 unsigned mode。

## 正确性说明

该方法对尾数乘法是精确的，因为：

```text
M = C0 + C1*2^7 + C2*2^14 + C3*2^21
```

是 24-bit 尾数的精确分解。根据乘法分配律：

```text
M_A * M_B
= sum_i sum_j Ai*Bj*2^(7i + 7j)
= sum_i sum_j Ai*Bj*2^(7*(i+j))
```

每个 chunk product `Ai*Bj` 也是精确的，因为：

```text
Ai, Bj <= 127
```

它们在 signed INT8 PE 中会被解释为相同的非负数。

因此，如果不做额外 pruning，该方案本身不会引入尾数乘法近似误差。误差只来自后续 FP 舍入策略，或来自可选的低位裁剪/pruning。

## Tradeoff

与 8-bit chunk 方案相比：

| 项目 | 8-bit chunk | 7-bit chunk |
| --- | ---: | ---: |
| 每个 24-bit mantissa 的 chunk 数 | 3 | 4 |
| chunk product 数 | 9 | 16 |
| 能否直接复用 signed INT8 PE | 否 | 是 |
| 是否需要 unsigned 修正 | 需要，除非修改 PE | 不需要 |
| PE 修改风险 | 较高 | 较低 |
| 调度/归约成本 | 较低 | 较高 |
| 更适合的定位 | 性能优先、允许改 PE | 复用优先、验证风险低 |

7-bit 方案的代价是周期数更多、外部归约工作更多；优势是避免修改 OPT4C PE 内部关键路径。因此它适合作为第一版原型，用来证明 FP 尾数乘法可以复用现有 OPT4C INT 数据通路。

## 验证计划

### 功能仿真

第一阶段只考虑 normal finite FP32 输入。

建议按以下层级验证：

```text
1. chunk 拆分和重构
2. 单个 chunk product Ai*Bj
3. 完整 4x4 chunk product 累加
4. mantissa normalization 和 rounding
5. packed FP32 multiplication result
```

Golden model：

```text
24-bit mantissa integer product model
software FP32 result model
```

建议覆盖的 corner case：

```text
M = 2^23
M = 2^24 - 1
包含 zero chunk 的 mantissa
chunk 值为 127
top chunk A3/B3 = 7
P[47] = 0 的规格化情况
P[47] = 1 的规格化情况
rounding carry 进入 exponent 的情况
```

当前已加入第一版 RTL 验证入口：

| 文件 | 作用 |
| --- | --- |
| `OPT3_OPT4C/fp/fp32_mantissa_7bit_chunk_mul.sv` | 组合形式的 7-bit chunk 乘法参考实现，输出 48-bit mantissa product |
| `OPT3_OPT4C/fp/fp32_mantissa_7bit_pair_scheduler.sv` | 逐 pair 发射 `(Ai, Bj, shift)` 的调度器，后续可接 OPT4C A-side encoder 和 B-side operand |
| `OPT3_OPT4C/fp/sim/test_fp32_mantissa_7bit_chunk.sv` | 基础 testbench，对组合 product 和 scheduler 累加结果做 golden check |
| `OPT3_OPT4C/fp/sim/filelist.f` | 仿真 filelist |
| `OPT3_OPT4C/fp/sim/run.sh` | VCS 仿真脚本 |

服务器运行：

```bash
cd /home/chenhao/work/High-Performance-Tensor-Processing-Engines/OPT3_OPT4C/fp/sim
bash run.sh
```

预期输出：

```text
SUCCESS: fp32 mantissa 7-bit chunk tests passed.
```

### 综合检查

至少比较：

```text
baseline OPT4C PE/column
OPT4C + 7-bit FP mantissa wrapper
```

需要报告：

```text
area
Fmax
critical path
scheduler/control fanout
global shifter/reducer timing
```

预期现象是：

```text
PE 内部 critical path 与原 OPT4C 接近；
新的 timing pressure 主要出现在 wrapper 的 shifter/reducer/control。
```

如果 PE 内部 critical path 明显变差，说明 wrapper 边界划分不合理，可能把浮点相关逻辑推到了 PE 内部，需要重新切分。

## 推荐表述

可以将该方案表述为一种“复用优先”的 FP/INT 统一计算路径：

```text
本设计将 FP32 的 24-bit 尾数拆分为四个 signed-safe 7-bit chunk。
每个 chunk 通过 zero-extension 映射到 INT8 操作数空间，从而可直接复用现有 OPT4C signed PE，而无需 unsigned 修正项。
PE 外部 wrapper 负责 chunk pair 调度、零值跳过、global weight shift、aligned product 归约以及后续 FP normalization 和 rounding。
该方案以更多时分复用周期为代价，降低了对 PE 关键路径的侵入，是一种适合早期验证的定点/浮点统一接口设计。
```
