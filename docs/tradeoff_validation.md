# Tradeoff and Dataflow Validation Plan

This project has already passed RTL functional simulation for OPT1-OPT4. The next goal is to prove where each optimization helps, where it pays cost, and whether the dataflow can still be mapped without control, fanout, or bandwidth becoming the new bottleneck.

## Evidence Targets

The minimum useful evidence set is:

| Question | Evidence | How to collect |
| --- | --- | --- |
| Does the design still compute correctly? | Existing RTL simulation pass logs for OPT1-OPT4 | Keep representative `SUCCESS`/matched logs from each sim directory |
| What is the best achievable frequency? | Smallest clock period with non-negative slack | Run `sweep.sh`, summarize `*_timing_report_*.txt` |
| What area is paid at that period? | Total cell area at the tightest MET period | Use matching `*_area_report_*.txt` |
| Did the critical path move as expected? | Top 10 timing paths with nets, transition, capacitance | Inspect `*_timing_top10_*.txt` |
| Does shared control become a problem? | Fanout, transition, capacitance, all violators | Inspect OPT3/4 net reports and `*_constraint_violators_*.txt` |
| Can the mapped dataflow feed the array? | A/B/control bandwidth table and schedule invariants | Manually derive from RTL ports and testbench dimensions |

## Design Hypotheses

| Design | Intended benefit | Likely cost or limitation | What would confirm it |
| --- | --- | --- | --- |
| OPT1 PE | Shorter MAC critical path by keeping accumulation in compressed `acc_sum`/`acc_carry` form | More state, wider intermediate/result exposure, final sum/carry fusion still needed | Higher Fmax than MAC PE; critical path in compressor/CSA logic; area/register growth visible |
| OPT1 OS/WS array | Reuses compressed accumulation inside systolic PE arrays | Output bandwidth or final reduction can become awkward if every PE exposes sum/carry | Array Fmax improves, but output/result width and final fusion cost must be discussed |
| OPT2 array | Converts A into bit-weight enable/select signals and reduces same-bit-weight partial products | B bandwidth scales with number of PE tiles; K is structurally tied to encoder/reduction design | Critical path in low-width reduction tree; area grows with N; B input width is `8*N` |
| OPT3 PE | Skips zero partial products under sparse/low-magnitude operands | Variable number of cycles per operand; gain depends on input distribution | Simulation reports lower average `cal_cycle`; timing path may include sparse encoder/mux |
| OPT4C column | Shares one sparse encoder across N PEs to reduce duplicated encoder logic | `partial_product_index`, `position`, `cal_cycle`, and valid/sync-like control may fan out or force slow-column synchronization | Fanout reports show whether shared select broadcast becomes a new bottleneck |

## Dataflow Mapping Checks

Use these invariants to argue that the dataflow is mapped correctly, beyond simply saying the testbench passed.

| Design | A mapping | B mapping | Output mapping | Critical invariant |
| --- | --- | --- | --- | --- |
| OPT1 OS | One A lane enters each row and moves horizontally through `row[i][j]` | One B lane enters each column and moves vertically through `col[i][j]` | Each PE accumulates one C element in compressed sum/carry form | C index must match PE coordinate `(row i, col j)` after the systolic fill/drain schedule |
| OPT1 WS | B/weight stays or streams in the WS pattern depending on the local PE design | A streams across active rows | Accumulator width may be dynamic or local to PE | Software-configurable M/K cannot violate hardware N/array dimension |
| OPT2 | `operand_a[127:0]` is encoded once into 16 groups of `bit_enable` and `partial_product_select` | `weight_din[8*N-1:0]` feeds N PE tiles, one byte per tile | `result[20*N-1:0]` produces one result per tile | Pipeline forwarding of encoded A signals between tiles must stay aligned with corresponding B tiles |
| OPT3 PE | Encoded A selects only non-zero partial-product positions | B is prefetched according to `position` | One vector inner product is accumulated over `cal_cycle` active steps | `cal_cycle` must match the number of active partial products selected by `sparse_encoder` |
| OPT4C column | One shared `sparse_encoder` drives all N PEs | `operand_b[8*N-1:0]` provides one B per column PE | `pe_result[52*N-1:0]` returns all column PE results | Shared `partial_product_index` must reach every PE in the same intended cycle, or fanout/routing breaks the mapping |

## Sweep Workflow

Three synthesis directories have been prepared for clock-period sweep:

```bash
cd /home/chenhao/work/High-Performance-Tensor-Processing-Engines

cd OPT1/systolic_array_os/opt1_pe/syn
bash sweep.sh

cd /home/chenhao/work/High-Performance-Tensor-Processing-Engines/OPT2/syn
bash sweep.sh

cd /home/chenhao/work/High-Performance-Tensor-Processing-Engines/OPT3_OPT4C/array/syn
bash sweep.sh
```

To customize periods without editing the script:

```bash
PERIODS="1.2 1.1 1.0 0.9 0.8" bash sweep.sh
```

FP32 wrapper sweeps:

```bash
cd /home/chenhao/work/High-Performance-Tensor-Processing-Engines/OPT3_OPT4C/fp/syn
bash sweep_fp32.sh
bash sweep_fp32_pipe.sh
bash sweep_fp32_pipe3.sh
bash sweep_fp32_pipe4.sh
```

Summarize the generated reports from the project root:

```bash
python3 tools/summarize_sweep.py --csv sweep_summary.csv
```

For each design, the key row is the smallest period marked `MET`. Approximate:

```text
Fmax MHz = 1000 / period_ns
```

## Critical Path Reading Guide

For the tightest MET period and first VIOLATED period, compare top paths:

| Design | Expected path if optimization works | Warning sign |
| --- | --- | --- |
| OPT1 PE | Booth partial product or CSA/compressor accumulation around `acc_sum`/`acc_carry` | Final full adder or output fusion dominates, weakening the compressed-accumulation argument |
| OPT2 array | `partial_product_select` into small reduction trees, then bit-weight result combine | Encoded A pipeline or B distribution dominates instead of reduction logic |
| OPT3/4 column | Sparse select/mux into PE compressor | `partial_product_index` or shared select broadcast dominates, meaning column-level sharing costs timing |

## OPT4 Fanout Checks

For OPT4C, inspect these files at the tightest MET period and first VIOLATED period:

```text
OPT3_OPT4C/array/syn/outputs_array/saed32rvt_tt0p85v25c/net_partial_product_index_<period>.txt
OPT3_OPT4C/array/syn/outputs_array/saed32rvt_tt0p85v25c/net_encoder_position_<period>.txt
OPT3_OPT4C/array/syn/outputs_array/saed32rvt_tt0p85v25c/net_position_<period>.txt
OPT3_OPT4C/array/syn/outputs_array/saed32rvt_tt0p85v25c/net_cal_cycle_<period>.txt
OPT3_OPT4C/array/syn/outputs_array/saed32rvt_tt0p85v25c/net_encode_valid_<period>.txt
OPT3_OPT4C/array/syn/outputs_array/saed32rvt_tt0p85v25c/net_sync_<period>.txt
OPT3_OPT4C/array/syn/outputs_array/saed32rvt_tt0p85v25c/top_pe_column_n32_constraint_violators_<period>.txt
```

The tradeoff is real if shared encoder area is lower but the select/control nets show high fanout, bad transition, high capacitance, or many inserted buffers.

## OPT4C N=32 Result

This subsection records the completed OPT4C N=32 column analysis. In this configuration, `top_pe_column` instantiates 32 `sparse_pe` modules. The B input width is `8*N = 256` bits, the output width is `52*N = 1664` bits, and one shared `sparse_encoder` drives the 32 PEs.

| Item | Result |
| --- | --- |
| Tightest observed MET period | 0.59 ns, slack = 0.00 |
| Approximate Fmax | 1694.9 MHz |
| First tested violating point | 0.58 ns, slack = -0.01 |
| Area at 0.59 ns | 31943.105888 |
| Area at 0.58 ns | 32865.394483 |
| Area increase from 0.59 ns to 0.58 ns | About 2.89%, while timing still violates |
| `partial_product_index[1]` fanout | 2 loads |
| `partial_product_index[0]` fanout | 4 loads |
| `cal_cycle` fanout | Mostly output-port use |
| `position` fanout | Some local combinational loads, no obvious large array-level fanout |

The top timing paths at 0.59 ns and 0.58 ns mainly terminate around `genblk1[x].sparse_pe/U1/INPUT`, `U1/n2`, and carry-related nodes. `U1` is the `DW02_tree #(3, ACC_WIDTH, 1)` compressor inside `pe.v`. This means the current critical path is dominated by local sparse PE mux/compressor/`acc_carry` logic, not by shared `sparse_encoder` control broadcast to the 32 PEs.

Current conclusion: under the N=32 configuration, DC synthesis flow, and wire-load model used here, OPT4C's dataflow mapping has been functionally validated by simulation and is not obviously blocked by shared-control fanout. The main tradeoff is that pushing beyond the 0.59 ns timing boundary increases area but gives limited timing benefit; the bottleneck remains inside the PE compression-accumulation path.

## FP32 7-bit Chunk Pipeline Result

This subsection records the first FP32 wrapper timing result for the 7-bit chunk design. The combinational baseline is `fp32_mul_7bit_chunk`; the pipelined version is `fp32_mul_7bit_chunk_pipe`, which inserts one register boundary after `mantissa_product` and the associated FP metadata. The functionality of the pipelined version has been checked against the combinational reference:

```text
SUCCESS: fp32 7-bit chunk pipelined multiply tests passed.
```

The combinational FP32 baseline closed at 5.3 ns with area 12321.917662. Its top path started from `operand_b[10]`, passed through full-adder based mantissa product accumulation and FP32 normalization/rounding/packing logic, and ended at `result` fraction bits.

Pipeline synthesis results:

| Period | Slack | Total cell area |
| ---: | ---: | ---: |
| 3.0 ns | 0.00 | 12136.900811 |
| 2.8 ns | 0.00 | 12452.547678 |
| 2.7 ns | 0.00 | 12510.238374 |
| 2.65 ns | 0.00 | 12455.089121 |
| 2.6 ns | -0.03 | 12874.426731 |
| 2.4 ns | -0.26 | not recorded |
| 2.0 ns, pipe3 | -0.31 | 13531.134837 |
| 2.0 ns, pipe4 | -0.01 | 15198.573704 |
| 2.05 ns, pipe4 | 0.00 | 15158.927235 |

The tightest observed MET point is 2.65 ns, corresponding to about 377.4 MHz. Compared with the combinational 5.3 ns baseline, this is a 2.0x shorter clock period for roughly 1.08% area increase at the tightest MET point:

```text
5.3 ns -> 188.7 MHz, area = 12321.917662
2.65 ns -> 377.4 MHz, area = 12455.089121
```

The result confirms the intended pipeline tradeoff: one extra cycle of latency and extra sequential state substantially shorten the single-cycle timing path. The remaining boundary appears to be between 2.6 ns and 2.65 ns; a finer sweep around 2.62-2.64 ns can locate the practical closing point more accurately.

The deeper pipeline experiments refine this conclusion. `pipe3` split the FP post-processing path but still violated at 2.0 ns by -0.31 ns. Its top path started from `operand_b[3]` and ended at `mantissa_product_s1_reg`, showing that the first mantissa-product stage still combined chunk multiplication and shifted accumulation. `pipe4` then inserted a boundary between the 16 chunk-product registers and the shifted reduction into `mantissa_product`. At 2.0 ns, `pipe4` improves the violation to -0.01 ns with area 15198.573704, and it closes at 2.05 ns with area 15158.927235. This corresponds to about 487.8 MHz, a 2.59x speedup over the 5.3 ns combinational baseline and a 1.29x speedup over the 2.65 ns one-boundary pipeline. The cost is a larger FP-only wrapper area and extra latency. The top paths are now distributed across chunk-product generation, shifted reduction, and normalize/round preparation, which indicates a much more balanced FP wrapper pipeline.

## Bandwidth Table Template

Fill this table using the exact configuration used in synthesis and simulation.

| Design | A input per cycle | B input per cycle | Control per cycle | Main mapping risk |
| --- | --- | --- | --- | --- |
| OPT1 | One A vector/lane group into systolic rows | One B vector/lane group into systolic columns | `clc`, compressed `acc_sum/acc_carry` local state | Wider internal state and final sum/carry fusion |
| OPT2 | Encoded 128-bit A block to 16 bit-weight groups | `8*N` bits of B/weights for N tiles | `bit_enable`, `partial_product_select`, weight write enable | B bandwidth and encoded-control alignment across tiles |
| OPT3 | Sparse encoded A, variable active partial products | B selected/prefetched by position | `position`, `cal_cycle`, `encode_valid` | Variable latency and waiting for slow operands |
| OPT4C | One shared sparse A encoder for N column PEs | `8*N` bits of B, one byte per PE | Shared `partial_product_index`, `position`, `cal_cycle` | Select broadcast fanout/routing and synchronization |

## Conclusion Structure

When presenting results, use this order:

1. Functional correctness is already established by RTL simulation.
2. Sweep shows the smallest MET period and area for each design.
3. Top10 timing shows whether the bottleneck is inside the intended arithmetic block or has moved to control/data distribution.
4. OPT4 fanout reports show whether shared encoder control remains scalable.
5. Bandwidth table explains whether the dataflow can feed the optimized PE without erasing the arithmetic gain.
