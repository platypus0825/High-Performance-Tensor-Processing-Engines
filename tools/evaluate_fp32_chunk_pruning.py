#!/usr/bin/env python3
import argparse
import csv
import math
import random


GROUPS = {
    0: [(0, 0)],
    1: [(1, 0), (0, 1)],
    2: [(2, 0), (1, 1), (0, 2)],
    3: [(3, 0), (2, 1), (1, 2), (0, 3)],
    4: [(3, 1), (2, 2), (1, 3)],
    5: [(3, 2), (2, 3)],
    6: [(3, 3)],
}

PAIR_INDEX = {(i, j): i * 4 + j for i in range(4) for j in range(4)}
PAIR_GROUP = {(i, j): i + j for i in range(4) for j in range(4)}


def chunks_7bit(mantissa):
    return [
        mantissa & 0x7F,
        (mantissa >> 7) & 0x7F,
        (mantissa >> 14) & 0x7F,
        (mantissa >> 21) & 0x7,
    ]


def full_product(a_chunks, b_chunks):
    acc = 0
    for i in range(4):
        for j in range(4):
            acc += (a_chunks[i] * b_chunks[j]) << (7 * (i + j))
    return acc


def pruned_product(a_chunks, b_chunks, keep_pair):
    acc = 0
    active_pairs = 0
    for i in range(4):
        for j in range(4):
            pp = a_chunks[i] * b_chunks[j]
            group = PAIR_GROUP[(i, j)]
            aligned = pp << (7 * group)
            if pp != 0 and keep_pair(i, j, pp, aligned):
                active_pairs += 1
                acc += aligned
    return acc, active_pairs


def make_strategy(name):
    if name == "full":
        return lambda i, j, pp, aligned: True

    if name.startswith("keep_g"):
        groups = {int(ch) for ch in name.removeprefix("keep_g")}
        return lambda i, j, pp, aligned: PAIR_GROUP[(i, j)] in groups

    if name.startswith("drop_low_groups_"):
        n = int(name.removeprefix("drop_low_groups_"))
        return lambda i, j, pp, aligned: PAIR_GROUP[(i, j)] >= n

    if name.startswith("top_chunks_"):
        n = int(name.removeprefix("top_chunks_"))
        first = 4 - n
        return lambda i, j, pp, aligned: i >= first and j >= first

    if name.startswith("min_pp_"):
        threshold = int(name.removeprefix("min_pp_"))
        return lambda i, j, pp, aligned: pp >= threshold

    if name.startswith("min_aligned_bit_"):
        bit = int(name.removeprefix("min_aligned_bit_"))
        threshold = 1 << bit
        return lambda i, j, pp, aligned: aligned >= threshold

    raise ValueError(f"unknown strategy: {name}")


def percentile(sorted_values, pct):
    if not sorted_values:
        return 0.0
    pos = (len(sorted_values) - 1) * pct / 100.0
    lower = int(math.floor(pos))
    upper = int(math.ceil(pos))
    if lower == upper:
        return sorted_values[lower]
    weight = pos - lower
    return sorted_values[lower] * (1.0 - weight) + sorted_values[upper] * weight


def accuracy_bits(rel_error):
    if rel_error <= 0.0:
        return "inf"
    return f"{-math.log2(rel_error):.2f}"


def evaluate_strategy(strategy_name, samples, rng):
    keep_pair = make_strategy(strategy_name)
    rel_errors = []
    abs_errors = []
    active_pair_sum = 0
    exact_matches = 0

    for _ in range(samples):
        mantissa_a = rng.randrange(1 << 23, 1 << 24)
        mantissa_b = rng.randrange(1 << 23, 1 << 24)
        a_chunks = chunks_7bit(mantissa_a)
        b_chunks = chunks_7bit(mantissa_b)
        exact = full_product(a_chunks, b_chunks)
        approx, active_pairs = pruned_product(a_chunks, b_chunks, keep_pair)
        abs_err = abs(exact - approx)
        rel_err = abs_err / exact
        active_pair_sum += active_pairs
        abs_errors.append(abs_err)
        rel_errors.append(rel_err)
        if abs_err == 0:
            exact_matches += 1

    rel_errors.sort()
    abs_errors.sort()
    mean_rel = sum(rel_errors) / samples
    mean_abs = sum(abs_errors) / samples
    p99_rel = percentile(rel_errors, 99.0)
    max_rel = rel_errors[-1]

    return {
        "strategy": strategy_name,
        "samples": samples,
        "mean_active_pairs": f"{active_pair_sum / samples:.2f}",
        "exact_match_pct": f"{100.0 * exact_matches / samples:.3f}",
        "mean_rel_error": f"{mean_rel:.8e}",
        "p50_rel_error": f"{percentile(rel_errors, 50.0):.8e}",
        "p90_rel_error": f"{percentile(rel_errors, 90.0):.8e}",
        "p99_rel_error": f"{p99_rel:.8e}",
        "max_rel_error": f"{max_rel:.8e}",
        "mean_accuracy_bits": accuracy_bits(mean_rel),
        "p99_accuracy_bits": accuracy_bits(p99_rel),
        "mean_abs_product_error": f"{mean_abs:.2f}",
    }


def default_strategies():
    return [
        "full",
        "drop_low_groups_1",
        "drop_low_groups_2",
        "drop_low_groups_3",
        "drop_low_groups_4",
        "drop_low_groups_5",
        "drop_low_groups_6",
        "top_chunks_3",
        "top_chunks_2",
        "min_aligned_bit_14",
        "min_aligned_bit_21",
        "min_aligned_bit_28",
        "min_aligned_bit_35",
    ]


def main():
    parser = argparse.ArgumentParser(
        description="Evaluate precision loss from pruning 7-bit FP32 mantissa chunk products."
    )
    parser.add_argument("--samples", type=int, default=100000, help="Number of random normal mantissa pairs.")
    parser.add_argument("--seed", type=int, default=1, help="Random seed.")
    parser.add_argument("--csv", default="", help="Optional CSV output path.")
    parser.add_argument(
        "--strategy",
        action="append",
        help=(
            "Strategy to evaluate. Can be repeated. Built-ins: full, drop_low_groups_N, "
            "keep_g0123456 subset strings, top_chunks_N, min_pp_T."
        ),
    )
    args = parser.parse_args()

    strategies = args.strategy or default_strategies()
    rows = []
    for idx, strategy in enumerate(strategies):
        rng = random.Random(args.seed)
        rows.append(evaluate_strategy(strategy, args.samples, rng))

    fields = [
        "strategy",
        "samples",
        "mean_active_pairs",
        "exact_match_pct",
        "mean_rel_error",
        "p50_rel_error",
        "p90_rel_error",
        "p99_rel_error",
        "max_rel_error",
        "mean_accuracy_bits",
        "p99_accuracy_bits",
        "mean_abs_product_error",
    ]

    for row in rows:
        print(
            f"{row['strategy']:18s} active={row['mean_active_pairs']:>5s} "
            f"mean_rel={row['mean_rel_error']:>13s} "
            f"p99_rel={row['p99_rel_error']:>13s} "
            f"max_rel={row['max_rel_error']:>13s} "
            f"p99_bits={row['p99_accuracy_bits']:>6s}"
        )

    if args.csv:
        with open(args.csv, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fields)
            writer.writeheader()
            writer.writerows(rows)
        print(f"Wrote {args.csv}")


if __name__ == "__main__":
    main()
