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

## 当前拼接原型状态

当前新增的拼接原型是：

```text
OPT3_OPT4C/fp/opt4c_int_fp_mode_wrapper.sv
```

它不修改原始 `top_pe.v` 和 `pe.v`。在最初的单实例共享 wrapper 中，`mode_fp` mux 直接放在同一个 `top_pe` 输入前；综合显示裸 `top_pe_baseline` 在 0.59 ns 可以收敛，而 shared wrapper 的 `MODE=int` 不能收敛。因此当前先尝试 registered-mux 结构：

```text
mode_fp = 0:
    INT 输入 -> mode mux -> pe_issue_reg -> shared_top_pe -> INT PE 结果。

mode_fp = 1:
    FP32 mantissa -> 7-bit chunk scheduler
      -> encoder_multi_bit
      -> mode mux -> pe_issue_reg -> shared_top_pe / pe
      -> PE 外 global shift / accumulate
      -> FP mantissa product
```

这里的“复用 INT PE”指 FP 尾数 chunk product 仍然使用原始 `top_pe/pe` 这种 INT PE 数据通路，而不是新写一套普通乘法器。registered-mux 的目的不是完全消除 mux，而是把 mux 从 `top_pe` 输入边界前移到 issue/register 边界，使 mux 路径终止在 `pe_issue_reg`，不直接贴住 PE 内部 compressor 路径。

当前仿真：

```bash
cd /home/chenhao/work/High-Performance-Tensor-Processing-Engines/OPT3_OPT4C/fp/sim
bash run_int_fp_wrapper.sh
```

已通过：

```text
SUCCESS: OPT4C INT/FP mode wrapper tests passed.
```

该仿真包含两层含义：

1. INT 模式下，wrapper 输出与裸 `top_pe` cycle-by-cycle 对比一致，说明 wrapper 没有破坏 INT 功能。
2. FP 模式下，尾数 full/pruned chunk product 真实经过 `encoder_multi_bit + top_pe` 路径，并与 golden 对齐。

下一步综合脚本：

```text
OPT3_OPT4C/fp/syn/dc_int_fp_wrapper.tcl
OPT3_OPT4C/fp/syn/sweep_int_fp_wrapper.sh
```

综合时应重点比较 `MODE=int` 报告和原始 OPT4C INT 报告，确认新增 mode wrapper 没有降低 INT 目标频率；`MODE=fp` 报告用于观察 FP 外围控制和累加路径的代价。

注意：`MODE=int` 报告应只解释 INT 激活模式下的时序。脚本会在完整双模式 wrapper 综合后，对 FP 输入/输出设置 false path，再报告 INT mode timing；否则 `fp_busy`、`fp_done`、`fp_mantissa_product` 等非激活模式输出可能污染 INT 报告。`MODE=fp` 同理会 false-path INT 输入/输出。

综合脚本使用 `compile_ultra -retime`，与原始 OPT4C array 综合脚本保持一致。这个口径很重要：当前 INT mode 的 top path 位于 `shared_top_pe/sparse_pe/operand_b_reg -> shared_top_pe/sparse_pe/acc_carry_reg`，属于 PE 内部路径，而不是 mode mux 或 FP scheduler 路径。如果不用 retiming，单 PE wrapper 的 PE 内部路径会明显慢于此前 `top_pe_column` 的结果，不能直接作为“FP wrapper 降低了 INT 频率”的证据。

为了区分“wrapper 真的拖慢 INT”和“单 PE 综合口径本身不同”，新增裸 `top_pe` baseline 综合脚本：

```text
OPT3_OPT4C/fp/syn/dc_top_pe_baseline.tcl
OPT3_OPT4C/fp/syn/sweep_top_pe_baseline.sh
```

判断方法：

```text
如果 top_pe_baseline 在 0.59 ns 也违例，且 top path 同样在 PE 内部，
说明当前单 PE 综合结果不能直接和 N=32 column 的 0.59 ns 结论比较。

如果 top_pe_baseline 能过，但 opt4c_int_fp_mode_wrapper_int 不能过，
说明 wrapper 边界确实引入了 INT timing cost，需要重构模式切换边界。
```

当前采用的重构方式是把原本贴在 `top_pe` 输入前的组合 mode mux 前移到 `pe_issue_reg` 前。如果 registered-mux 仍然不能让 `MODE=int` 收敛，则说明单实例共享方案的时序代价仍然过高，需要回到 INT-protected 双实例结构：INT mode 走独立 `int_top_pe`，FP mode 走独立 `fp_top_pe`，以面积换取 INT Fmax 隔离。
