#!/usr/bin/env python3

import csv
import html
import sys
from pathlib import Path


COLORS = {
    "baseline": "#9c9c9c",
    "prepare-first": "#4c78a8",
    "discovery": "#f2cf5b",
    "tokenization": "#4c78a8",
    "reconstruction": "#e45756",
}


def load(path: Path):
    with path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    numeric = [
        "baseline_wall_seconds",
        "prepared_wall_seconds",
        "discovery_seconds",
        "tokenization_seconds",
        "reconstruction_seconds",
    ]
    for row in rows:
        for key in numeric:
            row[key] = float(row[key])
    return rows


def duration(seconds: float) -> str:
    minutes, remaining = divmod(seconds, 60)
    if minutes:
        return f"{int(minutes)}m{remaining:04.1f}s"
    return f"{remaining:.1f}s"


def wall_chart(path: Path, rows):
    left, top, plot_width = 150, 90, 920
    group_height = 92
    max_value = max(row["baseline_wall_seconds"] for row in rows)
    width = left + plot_width + 150
    height = top + group_height * len(rows) + 85
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="white"/>',
        '<style>text{font-family:system-ui,sans-serif;fill:#222}.title{font-size:22px;font-weight:700}.label{font-size:14px}.small{font-size:12px;fill:#555}</style>',
        f'<text x="{left}" y="32" class="title">blobExec scheduling strategies: wall-clock time</text>',
        f'<text x="{left}" y="55" class="small">Fresh destination, SQLite database, and tokenizer memo; lower is better</text>',
    ]
    for tick in range(6):
        value = max_value * tick / 5
        x = left + plot_width * tick / 5
        parts.append(f'<line x1="{x:.1f}" y1="{top - 12}" x2="{x:.1f}" y2="{height - 55}" stroke="#e5e5e5"/>')
        parts.append(f'<text x="{x:.1f}" y="{top - 20}" text-anchor="middle" class="small">{value / 60:.0f} min</text>')

    for index, row in enumerate(rows):
        base_y = top + index * group_height
        repo = html.escape(row["repository"])
        parts.append(f'<text x="{left - 12}" y="{base_y + 35}" text-anchor="end" class="label">{repo}</text>')
        for offset, (label, key) in enumerate([
            ("commit-local", "baseline_wall_seconds"),
            ("prepare-first", "prepared_wall_seconds"),
        ]):
            value = row[key]
            y = base_y + offset * 32
            bar_width = plot_width * value / max_value
            color = COLORS["baseline" if label == "commit-local" else "prepare-first"]
            parts.append(f'<rect x="{left}" y="{y}" width="{bar_width:.2f}" height="23" fill="{color}"/>')
            parts.append(f'<text x="{left + bar_width + 8:.1f}" y="{y + 17}" class="label">{label}: {duration(value)}</text>')
    parts.append('</svg>')
    path.write_text("\n".join(parts), encoding="utf-8")


def phase_chart(path: Path, rows):
    left, top, plot_width = 150, 85, 920
    row_height = 68
    max_value = max(row["prepared_wall_seconds"] for row in rows)
    width = left + plot_width + 145
    height = top + row_height * len(rows) + 120
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="white"/>',
        '<style>text{font-family:system-ui,sans-serif;fill:#222}.title{font-size:22px;font-weight:700}.label{font-size:14px}.small{font-size:12px;fill:#555}</style>',
        f'<text x="{left}" y="32" class="title">prepare-first phase breakdown</text>',
        f'<text x="{left}" y="55" class="small">Internal phase timers; process startup and final bookkeeping explain the small gap to total wall time</text>',
    ]
    phase_keys = [
        ("discovery", "discovery_seconds"),
        ("tokenization", "tokenization_seconds"),
        ("reconstruction", "reconstruction_seconds"),
    ]
    for index, row in enumerate(rows):
        y = top + index * row_height
        parts.append(f'<text x="{left - 12}" y="{y + 25}" text-anchor="end" class="label">{html.escape(row["repository"])}</text>')
        x = left
        for label, key in phase_keys:
            value = row[key]
            segment = plot_width * value / max_value
            parts.append(f'<rect x="{x:.2f}" y="{y + 5}" width="{segment:.2f}" height="28" fill="{COLORS[label]}"><title>{label}: {duration(value)}</title></rect>')
            x += segment
        parts.append(f'<text x="{x + 8:.1f}" y="{y + 25}" class="label">{duration(row["prepared_wall_seconds"])}</text>')

    legend_y = top + row_height * len(rows) + 40
    for index, (label, _) in enumerate(phase_keys):
        x = left + index * 210
        parts.append(f'<rect x="{x}" y="{legend_y}" width="16" height="16" fill="{COLORS[label]}"/>')
        parts.append(f'<text x="{x + 23}" y="{legend_y + 13}" class="label">{label}</text>')
    parts.append('</svg>')
    path.write_text("\n".join(parts), encoding="utf-8")


def main():
    if len(sys.argv) != 3:
        raise SystemExit(f"Usage: {sys.argv[0]} <results.csv> <output-directory>")
    rows = load(Path(sys.argv[1]))
    output = Path(sys.argv[2])
    output.mkdir(parents=True, exist_ok=True)
    wall_chart(output / "prepare_first_wall.svg", rows)
    phase_chart(output / "prepare_first_phases.svg", rows)


if __name__ == "__main__":
    main()
