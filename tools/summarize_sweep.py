#!/usr/bin/env python3
import argparse
import csv
import re
from pathlib import Path


DEFAULT_DESIGNS = [
    ("OPT1 PE", "OPT1/systolic_array_os/opt1_pe/syn/outputs/saed32rvt_tt0p85v25c", "opt1_mac"),
    ("OPT2 array", "OPT2/syn/outputs_array/saed32rvt_tt0p85v25c", "top_tpe_n16"),
    ("OPT4C col N16", "OPT3_OPT4C/array/syn/outputs_array/saed32rvt_tt0p85v25c", "top_pe_column_n16"),
    ("OPT3/4 col", "OPT3_OPT4C/array/syn/outputs_array/saed32rvt_tt0p85v25c", "top_pe_column_n32"),
    ("OPT4C col N64", "OPT3_OPT4C/array/syn/outputs_array/saed32rvt_tt0p85v25c", "top_pe_column_n64"),
    ("OPT4C col N128", "OPT3_OPT4C/array/syn/outputs_array/saed32rvt_tt0p85v25c", "top_pe_column_n128"),
    ("FP32 7b comb", "OPT3_OPT4C/fp/syn/outputs_fp32/saed32rvt_tt0p85v25c", "fp32_mul_7bit_chunk"),
    ("FP32 7b pipe", "OPT3_OPT4C/fp/syn/outputs_fp32/saed32rvt_tt0p85v25c", "fp32_mul_7bit_chunk_pipe"),
    ("FP32 7b pipe3", "OPT3_OPT4C/fp/syn/outputs_fp32/saed32rvt_tt0p85v25c", "fp32_mul_7bit_chunk_pipe3"),
]

SLACK_RE = re.compile(r"slack\s*\((MET|VIOLATED)\)\s+(-?\d+(?:\.\d+)?)", re.IGNORECASE)
AREA_RE = re.compile(r"Total cell area:\s*([0-9]+(?:\.[0-9]+)?)", re.IGNORECASE)
PERIOD_RE = re.compile(r"_([0-9]+(?:\.[0-9]+)?)\.txt$")


def parse_slack(path):
    text = path.read_text(errors="ignore")
    matches = SLACK_RE.findall(text)
    if not matches:
        return "", "UNKNOWN"
    status, slack = matches[-1]
    return slack, status.upper()


def parse_area(path):
    if not path.exists():
        return ""
    text = path.read_text(errors="ignore")
    matches = AREA_RE.findall(text)
    return matches[-1] if matches else ""


def period_from_path(path):
    match = PERIOD_RE.search(path.name)
    return match.group(1) if match else ""


def rows_for_design(label, output_dir, file_prefix):
    output_path = Path(output_dir)
    timing_files = sorted(output_path.glob(f"{file_prefix}_timing_report_*.txt"), key=lambda p: float(period_from_path(p) or 9999))
    for timing_path in timing_files:
        period = period_from_path(timing_path)
        if not period:
            continue
        slack, status = parse_slack(timing_path)
        area_path = output_path / f"{file_prefix}_area_report_{period}.txt"
        area = parse_area(area_path)
        fmax = ""
        if status == "MET":
            fmax = f"{1000.0 / float(period):.2f}"
        yield {
            "Design": label,
            "Period(ns)": period,
            "Slack(ns)": slack,
            "MET/VIOLATED": status,
            "Fmax_if_MET(MHz)": fmax,
            "Area": area,
            "TimingReport": str(timing_path),
            "AreaReport": str(area_path) if area_path.exists() else "",
        }


def main():
    parser = argparse.ArgumentParser(description="Summarize Synopsys DC sweep reports.")
    parser.add_argument("--csv", default="sweep_summary.csv", help="Output CSV path.")
    parser.add_argument(
        "--design",
        action="append",
        help="Extra design as LABEL:OUTPUT_DIR:FILE_PREFIX. Can be repeated.",
    )
    args = parser.parse_args()

    designs = list(DEFAULT_DESIGNS)
    for item in args.design or []:
        parts = item.split(":", 2)
        if len(parts) != 3:
            raise SystemExit(f"Bad --design value: {item}")
        designs.append(tuple(parts))

    rows = []
    for label, output_dir, file_prefix in designs:
        rows.extend(rows_for_design(label, output_dir, file_prefix))

    fields = ["Design", "Period(ns)", "Slack(ns)", "MET/VIOLATED", "Fmax_if_MET(MHz)", "Area", "TimingReport", "AreaReport"]
    with open(args.csv, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    for row in rows:
        print(
            f"{row['Design']:12s} period={row['Period(ns)']:>5s} "
            f"slack={row['Slack(ns)']:>8s} {row['MET/VIOLATED']:>8s} "
            f"fmax={row['Fmax_if_MET(MHz)']:>8s} area={row['Area']}"
        )
    print(f"Wrote {args.csv}")


if __name__ == "__main__":
    main()
