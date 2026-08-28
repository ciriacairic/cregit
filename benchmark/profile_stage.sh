#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 7 ]; then
    echo "Usage: $0 <stage> <name> <url> <revision> <commit-url> <work-dir> <profile-dir>" >&2
    exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CREGIT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
STAGE=$1
NAME=$2
URL=$3
REVISION=$4
COMMIT_URL=$5
WORK_DIR=$6
PROFILE_DIR=$7

[ ! -e "$WORK_DIR" ] || { echo "Refusing to overwrite: $WORK_DIR" >&2; exit 1; }
mkdir -p "$PROFILE_DIR"

PROFILE_ENV=(
    env
    "CREGIT_PROFILE_STAGE=$STAGE"
    "CREGIT_PROFILE_DIR=$PROFILE_DIR"
)
if [ "$STAGE" = blobexec ]; then
    PROFILE_ENV+=("CREGIT_JFR_FILE=$PROFILE_DIR/${NAME}-${STAGE}.jfr")
fi

"${PROFILE_ENV[@]}" "$CREGIT/run_pipeline_process.sh" \
        --repo-url "$URL" \
        --repo-name "$NAME" \
        --repo-rev "$REVISION" \
        --commit-url "$COMMIT_URL" \
        --file-mask '\.[ch]$' \
        --work-dir "$WORK_DIR" \
        --run-id "${NAME}-${STAGE}-profile" \
        --gc-mode aggressive

"$SCRIPT_DIR/render_perf.sh" \
    "$PROFILE_DIR/${STAGE}.perf.data" \
    "$PROFILE_DIR/${NAME}-${STAGE}"

if [ "$STAGE" = blobexec ]; then
    JFR_FILE="$PROFILE_DIR/${NAME}-${STAGE}.jfr"
    command -v jfr >/dev/null 2>&1 || { echo "jfr not found" >&2; exit 1; }
    jfr summary "$JFR_FILE" > "$PROFILE_DIR/${NAME}-${STAGE}.jfr-summary.txt"
    jfr view hot-methods "$JFR_FILE" > "$PROFILE_DIR/${NAME}-${STAGE}.jfr-hot-methods.txt"
    jfr view thread-cpu-load "$JFR_FILE" > "$PROFILE_DIR/${NAME}-${STAGE}.jfr-thread-cpu-load.txt"
fi
