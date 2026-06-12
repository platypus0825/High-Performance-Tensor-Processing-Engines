# FP32 Mantissa 7-bit Chunk Mapping on OPT4C

## Goal

This document describes a conservative multi-precision extension path for reusing the existing OPT4C signed INT8 PE datapath to compute the mantissa multiplication part of FP32 operations.

The key idea is:

```text
Do not feed unsigned 8-bit mantissa chunks directly into a signed INT8 PE.
Instead, split the 24-bit FP32 mantissa into sign-safe 7-bit chunks.
```

Each 7-bit chunk is zero-extended to 8 bits before entering the existing INT8/OPT4C datapath. Because the MSB of every 7-bit chunk is zero, the chunk is interpreted identically by unsigned arithmetic and signed INT8 hardware.

This keeps the PE datapath close to the current OPT4C implementation and moves the floating-point-specific work to a wrapper/front-end and a post-processing unit.

## Background

For a normalized FP32 number:

```text
X = (-1)^sign * 1.fraction * 2^(exponent - 127)
```

The mantissa used by hardware multiplication is usually represented as a 24-bit unsigned integer:

```text
M = {1'b1, fraction[22:0]}
```

So:

```text
M in [2^23, 2^24 - 1]
```

The mantissa product is:

```text
P = M_A * M_B
```

where `P` is up to 48 bits. After obtaining `P`, the FP unit still needs normalization, rounding, exponent adjustment, sign generation, and special-case handling.

## Why Not 8-bit Chunks

If the 24-bit mantissa is split into three 8-bit chunks:

```text
M = C0 + (C1 << 8) + (C2 << 16)
```

then each chunk is an unsigned value in:

```text
0..255
```

However, the existing OPT4C PE treats 8-bit operands as signed two's-complement values. Therefore:

```text
8'hC8 = 200 unsigned
8'hC8 = -56 signed
```

Direct reuse would compute the wrong product when any chunk is greater than 127.

Using 8-bit chunks is still possible, but it requires one of the following:

```text
1. signed/unsigned PE mode support
2. unsigned correction terms around the signed PE
3. a new front-end representation similar in spirit to signed bit-slice conversion
```

All three options modify the arithmetic path or add correction logic. Since the current OPT4C timing bottleneck is already inside the PE mux/compressor/accumulation path, the safer first design is to avoid adding this complexity inside the PE.

## 7-bit Chunk Representation

Split the 24-bit mantissa into four chunks:

```text
M = C0 + (C1 << 7) + (C2 << 14) + (C3 << 21)
```

with:

```text
C0 = M[6:0]
C1 = M[13:7]
C2 = M[20:14]
C3 = M[23:21]
```

The chunk ranges are:

```text
C0, C1, C2 in [0, 127]
C3 in [0, 7]
```

Each chunk can be zero-extended to signed INT8 safely:

```text
chunk8 = {1'b0, chunk7}
```

or for the top 3-bit chunk:

```text
chunk8 = {5'b0, chunk3}
```

Thus the existing signed PE sees a non-negative signed INT8 operand:

```text
0..127
```

No unsigned correction term is needed.

## Mantissa Product Expansion

For two mantissas:

```text
M_A = A0 + (A1 << 7) + (A2 << 14) + (A3 << 21)
M_B = B0 + (B1 << 7) + (B2 << 14) + (B3 << 21)
```

the product is:

```text
P = M_A * M_B
  = sum_i sum_j (Ai * Bj) << (7 * (i + j))
```

There are 16 chunk products:

```text
A0B0
A1B0 A0B1
A2B0 A1B1 A0B2
A3B0 A2B1 A1B2 A0B3
A3B1 A2B2 A1B3
A3B2 A2B3
A3B3
```

Grouped by global weight:

| Group | Shift | Chunk products |
| --- | ---: | --- |
| G0 | 0 | A0B0 |
| G1 | 7 | A1B0, A0B1 |
| G2 | 14 | A2B0, A1B1, A0B2 |
| G3 | 21 | A3B0, A2B1, A1B2, A0B3 |
| G4 | 28 | A3B1, A2B2, A1B3 |
| G5 | 35 | A3B2, A2B3 |
| G6 | 42 | A3B3 |

This diagonal grouping is useful because all products in the same group share the same external global shift.

## Mapping to OPT4C

The existing OPT4C `top_pe_column` contains:

```text
one shared sparse_encoder
N sparse_pe instances
one 8-bit B operand per PE
shared partial_product_index broadcast to all PEs
```

The PE does not consume a full `A * B` operation directly. Instead:

```text
A side: encoded into partial-product control
B side: supplied as the raw 8-bit operand
PE: selects B, 2B, -B, or -2B and accumulates compressed sum/carry
```

For the 7-bit mantissa scheme:

```text
Ai is a non-negative 7-bit chunk.
Bj is a non-negative 7-bit chunk.
```

A-side mapping:

```text
Ai -> zero-extend to 8 bits -> existing A encoder / sparse_encoder path
```

B-side mapping:

```text
Bj -> zero-extend to 8 bits -> operand_b_ins
```

Because both operands are less than 128, the signed INT8 interpretation is correct.

The OPT4C PE computes each `Ai * Bj` contribution through its existing partial-product flow. The FP wrapper is responsible for selecting which pair `(Ai, Bj)` is active and for applying the global shift `7 * (i + j)` outside the PE.

## Wrapper-Level Dataflow

The proposed FP mantissa wrapper has five stages.

### 1. Unpack

Extract FP32 fields:

```text
sign
exponent
fraction
```

For normalized numbers:

```text
mantissa = {1'b1, fraction}
```

For subnormal numbers, either:

```text
mantissa = {1'b0, fraction}
```

or handle them in a slower special-case path.

### 2. Chunk

Generate four chunks per operand:

```text
A0, A1, A2, A3
B0, B1, B2, B3
```

Also generate zero flags:

```text
A_valid[i] = (Ai != 0)
B_valid[j] = (Bj != 0)
pair_valid[i][j] = A_valid[i] & B_valid[j]
```

### 3. Schedule

Issue chunk products by diagonal group:

```text
for g in 0..6:
    for all i,j such that i+j == g:
        if pair_valid[i][j]:
            compute Ai * Bj
```

This schedule exposes slice-level sparsity:

```text
if Ai == 0 or Bj == 0, skip Ai * Bj
```

It also keeps the external shift constant within a group:

```text
group_shift = 7 * g
```

### 4. Compute

For each valid pair:

```text
Ai -> A-side encoder
Bj -> B-side operand_b
OPT4C PE -> partial product accumulation
```

The PE output represents the unshifted chunk product contribution. The wrapper then performs:

```text
aligned_product = chunk_product << group_shift
```

### 5. Reduce

Accumulate all aligned products into a 48-bit or wider mantissa-product accumulator:

```text
P = sum aligned_product
```

The accumulator should keep enough guard bits for rounding and for possible internal carry propagation. A practical implementation may keep the result in carry-save form until the final FP normalization stage.

## Time Multiplexing

The design reuses the same OPT4C PE resources over multiple cycles.

Worst-case chunk products:

```text
4 * 4 = 16
```

Worst-case diagonal groups:

```text
7 groups
```

If one PE computes one chunk pair at a time, the mantissa product requires up to 16 pair computations before final reduction.

If the existing OPT4C column has multiple PEs available, products within the same diagonal group can be mapped spatially across PEs. For example:

```text
G3 = A3B0, A2B1, A1B2, A0B3
```

contains four independent products with the same shift `21`, so it maps naturally to four parallel lanes.

Lane utilization by diagonal group is:

| Group | Products | Four-lane utilization |
| --- | ---: | ---: |
| G0 | 1 | 25% |
| G1 | 2 | 50% |
| G2 | 3 | 75% |
| G3 | 4 | 100% |
| G4 | 3 | 75% |
| G5 | 2 | 50% |
| G6 | 1 | 25% |

Average utilization across a four-lane group is:

```text
16 / (7 * 4) = 57.1%
```

This is the main cost of diagonal scheduling. The benefit is that all products in the same cycle group share the same global shift and use the existing signed PE safely.

## Floating-Point Post-Processing

After obtaining the 48-bit mantissa product `P`, the FP32 unit still needs:

```text
result_sign = sign_A ^ sign_B
raw_exponent = exponent_A + exponent_B - 127
normalization
rounding
exponent correction
packing
special-case handling
```

For normalized mantissas:

```text
M_A, M_B in [1.0, 2.0)
P in [1.0, 4.0)
```

Therefore:

```text
if P[47] == 1:
    normalized_mantissa = P >> 24
    exponent += 1
else:
    normalized_mantissa = P >> 23
```

Rounding should use guard, round, and sticky bits. For round-to-nearest-even:

```text
round_up = guard & (round | sticky | lsb)
```

If rounding overflows the mantissa, increment the exponent again.

Special cases include:

```text
zero
subnormal
infinity
NaN
overflow
underflow
```

The first implementation can choose to handle normal finite operands first, then add special-case support.

## Required New Logic

The minimum additional hardware around OPT4C is:

| Block | Function |
| --- | --- |
| FP unpacker | Extract sign, exponent, fraction, hidden bit |
| 7-bit chunker | Generate A0-A3 and B0-B3 |
| zero detector | Skip zero chunk pairs |
| pair scheduler | Select `(Ai, Bj)` according to diagonal group |
| A-side adapter | Feed selected `Ai` into the existing OPT4C encoder path |
| B-side adapter | Feed selected `Bj` as zero-extended signed-safe INT8 |
| global shifter | Apply `<< 7*(i+j)` outside the PE |
| product reducer | Sum aligned chunk products |
| FP normalizer | Normalize 48-bit product |
| rounder | Generate final FP32 mantissa |
| packer | Combine sign, exponent, fraction |

The OPT4C PE itself does not need unsigned mode support in this 7-bit scheme.

## Correctness Argument

The method is exact for mantissa multiplication because:

```text
M = C0 + C1*2^7 + C2*2^14 + C3*2^21
```

is an exact decomposition of the 24-bit mantissa, and multiplication distributes:

```text
M_A * M_B
= sum_i sum_j Ai*Bj*2^(7i + 7j)
= sum_i sum_j Ai*Bj*2^(7*(i+j))
```

Each chunk product `Ai*Bj` is exact because:

```text
Ai, Bj <= 127
```

and the signed INT8 PE interprets them as the same non-negative values.

Therefore the only approximation, if any, comes from optional pruning, rounding policy, or unsupported FP special cases, not from the 7-bit chunk decomposition itself.

## Tradeoff

Compared with 8-bit chunks:

| Item | 8-bit chunk | 7-bit chunk |
| --- | ---: | ---: |
| Chunks per 24-bit mantissa | 3 | 4 |
| Chunk products | 9 | 16 |
| Direct signed INT8 reuse | No | Yes |
| Unsigned correction needed | Yes, unless PE is modified | No |
| PE modification risk | Higher | Lower |
| Scheduler/reduction cost | Lower | Higher |
| Best use case | Performance-oriented design with PE changes | Conservative reuse-oriented design |

The 7-bit design pays more cycles and more external accumulation work, but it avoids changing the critical PE datapath. This makes it a better first prototype for proving that FP mantissa multiplication can reuse the OPT4C INT datapath.

## Validation Plan

### Functional Simulation

Start with normal finite FP32 operands only.

Test levels:

```text
1. chunk decomposition and reconstruction
2. one chunk product Ai*Bj
3. full 4x4 chunk product accumulation
4. mantissa normalization and rounding
5. packed FP32 multiplication result
```

Golden models:

```text
integer model for 24-bit mantissa product
software FP32 model for final packed result
```

Suggested corner cases:

```text
M = 2^23
M = 2^24 - 1
chunks with zero values
chunks with value 127
top chunk A3/B3 = 7
products that normalize with P[47] = 0
products that normalize with P[47] = 1
rounding carry into exponent
```

### Synthesis Checks

Compare at least:

```text
baseline OPT4C PE/column
OPT4C + 7-bit FP mantissa wrapper
```

Report:

```text
area
Fmax
critical path
fanout of scheduler/control signals
global shifter/reducer timing
```

The expected result is:

```text
PE critical path remains similar to existing OPT4C
new timing pressure appears in wrapper shifter/reducer/control
```

If the PE critical path grows significantly, then the wrapper has accidentally pushed FP-specific logic into the PE boundary and should be re-partitioned.

## Recommended Positioning

This design should be presented as a conservative reuse-first path:

```text
The proposed FP mantissa datapath decomposes a 24-bit mantissa into four sign-safe 7-bit chunks. Each chunk is zero-extended to INT8 and mapped to the existing OPT4C signed PE without unsigned correction. The wrapper schedules chunk-pair products, skips zero pairs, applies the global weight shift outside the PE, and reduces the aligned products before FP normalization and rounding. This trades more time-multiplexed chunk products for minimal changes to the PE critical path.
```

