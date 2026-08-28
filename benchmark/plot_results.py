#!/usr/bin/env python3

import csv
import html
import math
import statistics
import sys
from collections import defaultdict
from pathlib import Path


STAGE_ORDER = [
    "clone_original",
    "blobexec",
    "reflog_expire",
    "git_gc",
    "git_log_original",
    "git_log_cregit",
    "persons",
    "clone_work_original",
    "clone_work_cregit",
    "blame",
    "remap_commits",
    "pretty_print",
    "dataset",
]

COLORS = {
    "clone_original": "#a8a8a8",
    "blobexec": "#4c78a8",
    "reflog_expire": "#bab0ac",
    "git_gc": "#f58518",
    "git_log_original": "#e45756",
    "git_log_cregit": "#ff9da6",
    "persons": "#72b7b2",
    "clone_work_original": "#b279a2",
    "clone_work_cregit": "#d4a6c8",
    "blame": "#54a24b",
    "remap_commits": "#eeca3b",
    "pretty_print": "#8c6d31",
    "dataset": "#439894",
}


def load_metrics(root: Path):
    values = defaultdict(lambda: defaultdict(list))
    revisions = defaultdict(set)
    for path in sorted(root.rglob("metrics.csv")):
        with path.open(newline="", encoding="utf-8") as handle:
            for row in csv.DictReader(handle):
                if int(row["exit_code"]) != 0:
                    continue
                repo = row["repository"]
                stage = row["stage"]
                values[repo][stage].append(float(row["elapsed_seconds"]))
                revisions[repo].add(row["revision"])
    return values, revisions


def median_values(values):
    return {
        repo: {stage: statistics.median(samples) for stage, samples in stages.items()}
        for repo, stages in values.items()
    }


def nice_ceiling(value):
    if value <= 0:
        return 1
    exponent = 10 ** math.floor(math.log10(value))
    normalized = value / exponent
    step = 1 if normalized <= 1 else 2 if normalized <= 2 else 5 if normalized <= 5 else 10
    return step * exponent


def write_summary(output: Path, medians):
    with output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["repository", "stage", "median_elapsed_seconds", "share_percent", "rank"])
        for repo, stages in sorted(medians.items()):
            compute = {k: v for k, v in stages.items() if k != "clone_original"}
            total = sum(compute.values())
            ranked = sorted(compute.items(), key=lambda item: item[1], reverse=True)
            for rank, (stage, elapsed) in enumerate(ranked, 1):
                share = 100 * elapsed / total if total else 0
                writer.writerow([repo, stage, f"{elapsed:.3f}", f"{share:.2f}", rank])


def write_stacked_svg(output: Path, medians):
    repos = sorted(medians)
    totals = {
        repo: sum(value for stage, value in medians[repo].items() if stage != "clone_original")
        for repo in repos
    }
    max_total = nice_ceiling(max(totals.values(), default=1))
    left, right, top, row_height = 155, 50, 80, 58
    plot_width = 980
    legend_stages = [s for s in STAGE_ORDER if s != "clone_original" and any(s in medians[r] for r in repos)]
    legend_rows = math.ceil(len(legend_stages) / 3)
    height = top + row_height * len(repos) + 90 + legend_rows * 25
    width = left + plot_width + right

    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="white"/>',
        '<style>text{font-family:system-ui,sans-serif;fill:#222}.title{font-size:22px;font-weight:700}.label{font-size:14px}.small{font-size:12px;fill:#555}</style>',
        f'<text x="{left}" y="32" class="title">Cregit wall-clock time by stage</text>',
        f'<text x="{left}" y="55" class="small">Median by repository; network clone excluded</text>',
    ]

    for tick in range(6):
        value = max_total * tick / 5
        x = left + plot_width * tick / 5
        parts.append(f'<line x1="{x:.1f}" y1="{top - 8}" x2="{x:.1f}" y2="{top + row_height * len(repos)}" stroke="#e5e5e5"/>')
        parts.append(f'<text x="{x:.1f}" y="{top - 15}" text-anchor="middle" class="small">{value:.0f}s</text>')

    for row, repo in enumerate(repos):
        y = top + row * row_height
        parts.append(f'<text x="{left - 12}" y="{y + 23}" text-anchor="end" class="label">{html.escape(repo)}</text>')
        x = left
        for stage in STAGE_ORDER:
            if stage == "clone_original":
                continue
            elapsed = medians[repo].get(stage, 0)
            segment = plot_width * elapsed / max_total
            if segment <= 0:
                continue
            parts.append(
                f'<rect x="{x:.2f}" y="{y + 5}" width="{segment:.2f}" height="28" '
                f'fill="{COLORS.get(stage, "#777")}"><title>{html.escape(stage)}: {elapsed:.2f}s</title></rect>'
            )
            x += segment
        parts.append(f'<text x="{x + 8:.1f}" y="{y + 24}" class="label">{totals[repo]:.1f}s</text>')

    legend_y = top + row_height * len(repos) + 45
    for index, stage in enumerate(legend_stages):
        column = index % 3
        row = index // 3
        x = left + column * 330
        y = legend_y + row * 25
        parts.append(f'<rect x="{x}" y="{y - 11}" width="15" height="15" fill="{COLORS.get(stage, "#777")}"/>')
        parts.append(f'<text x="{x + 22}" y="{y + 1}" class="small">{html.escape(stage)}</text>')

    parts.append('</svg>')
    output.write_text("\n".join(parts), encoding="utf-8")


def write_top_svg(output: Path, medians):
    rows = []
    for repo, stages in sorted(medians.items()):
        compute = {k: v for k, v in stages.items() if k != "clone_original"}
        total = sum(compute.values())
        for stage, elapsed in sorted(compute.items(), key=lambda item: item[1], reverse=True)[:5]:
            rows.append((repo, stage, elapsed, 100 * elapsed / total if total else 0))

    left, right, top, row_height, plot_width = 250, 60, 75, 28, 850
    width = left + plot_width + right
    height = top + row_height * len(rows) + 55
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="white"/>',
        '<style>text{font-family:system-ui,sans-serif;fill:#222}.title{font-size:22px;font-weight:700}.label{font-size:13px}.small{font-size:12px;fill:#555}</style>',
        f'<text x="{left}" y="32" class="title">Five slowest stages by repository</text>',
        f'<text x="{left}" y="54" class="small">Share of compute wall-clock time</text>',
    ]
    for index, (repo, stage, elapsed, share) in enumerate(rows):
        y = top + index * row_height
        width_px = plot_width * share / 100
        label = f"{repo} / {stage}"
        parts.append(f'<text x="{left - 10}" y="{y + 16}" text-anchor="end" class="label">{html.escape(label)}</text>')
        parts.append(f'<rect x="{left}" y="{y}" width="{width_px:.2f}" height="19" fill="{COLORS.get(stage, "#777")}"/>')
        parts.append(f'<text x="{left + width_px + 7:.1f}" y="{y + 15}" class="label">{share:.1f}% ({elapsed:.1f}s)</text>')
    parts.append('</svg>')
    output.write_text("\n".join(parts), encoding="utf-8")


def main():
    if len(sys.argv) != 3:
        raise SystemExit(f"Usage: {sys.argv[0]} <results-root> <output-directory>")
    root = Path(sys.argv[1])
    output = Path(sys.argv[2])
    output.mkdir(parents=True, exist_ok=True)
    values, _ = load_metrics(root)
    if not values:
        raise SystemExit(f"No metrics.csv files found below {root}")
    medians = median_values(values)
    write_summary(output / "stage_summary.csv", medians)
    write_stacked_svg(output / "pipeline_stages.svg", medians)
    write_top_svg(output / "top_stages.svg", medians)


if __name__ == "__main__":
    main()
