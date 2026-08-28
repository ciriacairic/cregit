#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CREGIT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

REPOSITORIES_FILE=${1:-"${SCRIPT_DIR}/repositories.tsv"}
RESULTS_ROOT=${2:-"${CREGIT}/../cregit-performance"}
REPETITIONS=${REPETITIONS:-1}
GC_MODE=${GC_MODE:-aggressive}
BLOBEXEC_STRATEGY=${BLOBEXEC_STRATEGY:-commit-local}

[ -f "$REPOSITORIES_FILE" ] || { echo "Repository matrix not found: $REPOSITORIES_FILE" >&2; exit 1; }
case "$REPETITIONS" in
    ''|*[!0-9]*) echo "REPETITIONS must be a positive integer" >&2; exit 1 ;;
esac
[ "$REPETITIONS" -ge 1 ] || { echo "REPETITIONS must be at least 1" >&2; exit 1; }

mkdir -p "$RESULTS_ROOT"

while IFS=$'\t' read -r name url revision commit_url; do
    [ -n "$name" ] || continue
    case "$name" in \#*) continue ;; esac

    for repetition in $(seq 1 "$REPETITIONS"); do
        run_id="${name}-run-${repetition}"
        work_dir="${RESULTS_ROOT}/${run_id}"
        [ ! -e "$work_dir" ] || {
            echo "Refusing to overwrite existing benchmark: $work_dir" >&2
            exit 1
        }

        "$CREGIT/run_pipeline_process.sh" \
            --repo-url "$url" \
            --repo-name "$name" \
            --repo-rev "$revision" \
            --commit-url "$commit_url" \
            --file-mask '\.[ch]$' \
            --work-dir "$work_dir" \
            --run-id "$run_id" \
            --blobexec-strategy "$BLOBEXEC_STRATEGY" \
            --gc-mode "$GC_MODE"

        resolved_revision=$(sed -n 's/^resolved_revision=//p' "$work_dir/manifest.txt")
        "$SCRIPT_DIR/inventory_repo.sh" \
            "$work_dir/${name}-original.git" "$name" "$resolved_revision" \
            > "$work_dir/inventory.csv"
    done
done < "$REPOSITORIES_FILE"

"$SCRIPT_DIR/plot_results.py" "$RESULTS_ROOT" "$RESULTS_ROOT/charts"
