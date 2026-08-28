#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <perf.data> <output-prefix>" >&2
    exit 1
fi

PERF_DATA=$1
OUTPUT_PREFIX=$2
MAX_PERF_BYTES=${MAX_PERF_BYTES:-1073741824}

[ -f "$PERF_DATA" ] || { echo "perf data not found: $PERF_DATA" >&2; exit 1; }
PERF_BYTES=$(stat -c %s "$PERF_DATA")
if [ "$PERF_BYTES" -gt "$MAX_PERF_BYTES" ]; then
    echo "Refusing to render ${PERF_BYTES}-byte perf.data (safety limit: ${MAX_PERF_BYTES})." >&2
    echo "Collect a bounded profile or explicitly raise MAX_PERF_BYTES on a machine with enough RAM." >&2
    exit 1
fi
command -v perf >/dev/null 2>&1 || { echo "perf not found" >&2; exit 1; }
command -v inferno-collapse-perf >/dev/null 2>&1 || { echo "inferno-collapse-perf not found" >&2; exit 1; }
command -v inferno-flamegraph >/dev/null 2>&1 || { echo "inferno-flamegraph not found" >&2; exit 1; }

mkdir -p "$(dirname -- "$OUTPUT_PREFIX")"

perf report --stdio --input="$PERF_DATA" \
    --sort=comm,dso,symbol > "${OUTPUT_PREFIX}.report.txt"
perf script --input="$PERF_DATA" | \
    inferno-collapse-perf > "${OUTPUT_PREFIX}.folded"
inferno-flamegraph \
    --title "Cregit profiler: $(basename -- "$OUTPUT_PREFIX")" \
    --count-name samples \
    "${OUTPUT_PREFIX}.folded" > "${OUTPUT_PREFIX}.flamegraph.svg"
