# INT 主线优先的浮点扩展设计约束

## 最高优先级

本项目的目标不是重新设计一个独立的 FP32 乘法器，而是在原有 INT/OPT4C 架构基础上额外支持浮点运算。

最高优先级是：

```text
以 INT 计算为主线，保持原架构的 INT 路径、INT 频率和 INT 功能不受影响。
FP32 作为额外模式加入，尾数乘法必须复用现有 INT PE 的中间计算路径。
```

## 设计约束

1. INT 模式必须保持现有 OPT4C/INT PE 的数据通路和时序目标。
2. 为支持 FP32 新增的逻辑不能进入 INT PE 的关键路径。
3. FP32 的尾数乘法不能绕过 INT PE 另做一套完整乘法器作为最终方案。
4. 浮点相关逻辑应放在 PE 外部，包括 unpack、7-bit chunk 拆分、pair scheduler、裁剪控制、global shift、归约、normalize、round 和 pack。
5. 新增 pipeline 只服务于 FP 模式的时序/吞吐，不应降低 INT 模式 Fmax。
6. 面积开销应尽量集中在 wrapper 和少量控制/寄存器/归约逻辑中，避免大规模复制 PE 内部乘法压缩路径。

## 为什么这样定义

当前 OPT4C 的价值在于 INT 路径已经完成仿真验证，并且综合结果显示 N=32 column 的瓶颈主要在 PE 内部 mux/compressor/accumulation 路径，而不是 shared encoder fanout。

因此，如果为了 FP32 支持把 unsigned 修正、normalize、round、mode mux 或复杂选择逻辑塞进 PE 内部，就可能破坏原本最重要的 INT 性能。这样的方案即使 FP 功能正确，也不满足本项目的主目标。

## 当前 7-bit chunk 方案的定位

7-bit chunk 方案的意义是把 FP32 24-bit 尾数拆成 signed-safe 的 8-bit 输入：

```text
M = C0 + (C1 << 7) + (C2 << 14) + (C3 << 21)
C0, C1, C2 in [0,127]
C3 in [0,7]
```

每个 chunk 补 0 后进入 signed INT8 PE，不需要 unsigned 修正项：

```text
chunk8 = {1'b0, chunk7}
```

这样 PE 看到的是合法的非负 signed INT8 操作数，FP wrapper 只负责决定每个周期送哪一对 `(Ai, Bj)`，并在 PE 外做：

```text
aligned_pair = PE(Ai, Bj) << (7 * (i + j))
mantissa_product = sum(aligned_pair)
```

## 正确的最终数据流

推荐最终结构：

```text
mode == INT:
    原始 INT/OPT4C 输入 -> 原始 encoder / sparse_encoder / PE / array -> INT 输出

mode == FP32:
    FP32 unpack
      -> sign/exponent 旁路处理
      -> mantissa 7-bit chunk
      -> pair scheduler / pruning control
      -> 复用 INT encoder / sparse_encoder / PE 得到 chunk product
      -> PE 外 global shift 与归约
      -> normalize / round / pack
      -> FP32 输出
```

模式切换应发生在 PE 边界或更外层 wrapper，而不是插入 PE 内部 compressor/accumulator 关键路径。

## 评估标准

后续所有优化都按以下顺序判断：

1. INT 模式功能是否完全保持。
2. INT 模式 Fmax 是否不下降。
3. FP32 尾数 chunk product 是否真实复用 INT PE。
4. FP32 模式功能是否正确，包括裁剪模式的 pruned golden。
5. FP wrapper 面积、latency、吞吐是否在可接受范围。
6. 裁剪带来的精度损失是否可量化、可配置。

其中 1、2、3 是硬约束；4、5、6 是在满足硬约束之后再优化的 tradeoff。
