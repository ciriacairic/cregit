#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CREGIT=$SCRIPT_DIR

FROM_STEP=1
REPO_GIT_URL="https://github.com/jqlang/jq.git"
REPO_COMMIT_URL="https://github.com/jqlang/jq/commit/"
REPO_NAME="jq"
REPO_REV="HEAD"
FILE_MASK='\.[ch]$'
WORK="${CREGIT}/../cregit-files"
RUN_ID="manual"
METRICS_FILE=""
WITH_DATASET=0
GC_MODE="aggressive"
BLOBEXEC_STRATEGY="commit-local"
PROFILE_STAGE=${CREGIT_PROFILE_STAGE:-}
PROFILE_DIR=${CREGIT_PROFILE_DIR:-}
PROFILE_FREQUENCY=${CREGIT_PROFILE_FREQUENCY:-19}
JFR_FILE=${CREGIT_JFR_FILE:-}

usage() {
    cat <<'EOF'
Usage: ./run_pipeline_process.sh [options]

Options:
  --from-step N         Resume from pipeline step N (default: 1)
  --repo-url URL        Source Git repository
  --repo-name NAME      Short name used for generated artifacts
  --repo-rev REV        Commit/tag to process after cloning (default: HEAD)
  --commit-url URL      Commit URL prefix used by the HTML renderer
  --file-mask REGEX     Source path regex (default: \.[ch]$)
  --work-dir DIR        Output directory
  --run-id ID           Identifier written to the metrics file
  --metrics FILE        CSV metrics path (default: WORK/metrics.csv)
  --gc-mode MODE        aggressive, normal, or skip (default: aggressive)
  --blobexec-strategy S commit-local or prepare-first (default: commit-local)
  --with-dataset        Run generate_dataset.py after HTML generation
  -h, --help            Show this help

For compatibility, a single positional integer is accepted as --from-step.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --from-step) FROM_STEP=$2; shift 2 ;;
        --repo-url) REPO_GIT_URL=$2; shift 2 ;;
        --repo-name) REPO_NAME=$2; shift 2 ;;
        --repo-rev) REPO_REV=$2; shift 2 ;;
        --commit-url) REPO_COMMIT_URL=$2; shift 2 ;;
        --file-mask) FILE_MASK=$2; shift 2 ;;
        --work-dir) WORK=$2; shift 2 ;;
        --run-id) RUN_ID=$2; shift 2 ;;
        --metrics) METRICS_FILE=$2; shift 2 ;;
        --gc-mode) GC_MODE=$2; shift 2 ;;
        --blobexec-strategy) BLOBEXEC_STRATEGY=$2; shift 2 ;;
        --with-dataset) WITH_DATASET=1; shift ;;
        -h|--help) usage; exit 0 ;;
        ''|*[!0-9]*) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
        *) FROM_STEP=$1; shift ;;
    esac
done

case "$FROM_STEP" in
    ''|*[!0-9]*) echo "--from-step must be a positive integer" >&2; exit 1 ;;
esac
[ "$FROM_STEP" -ge 1 ] || { echo "--from-step must be at least 1" >&2; exit 1; }

case "$GC_MODE" in
    aggressive|normal|skip) ;;
    *) echo "--gc-mode must be aggressive, normal, or skip" >&2; exit 1 ;;
esac

case "$BLOBEXEC_STRATEGY" in
    commit-local|prepare-first) ;;
    *) echo "--blobexec-strategy must be commit-local or prepare-first" >&2; exit 1 ;;
esac

case "$WORK" in
    ''|/|"$CREGIT") echo "Refusing unsafe work directory [$WORK]" >&2; exit 1 ;;
esac

[ -x /usr/bin/time ] || {
    echo "GNU /usr/bin/time is required for pipeline metrics" >&2
    exit 1
}

BLOBEXEC_JAR="${CREGIT}/blobExec/target/scala-2.13/blobExec-0.1.0-assembly.jar"
SLICK_GIT_LOG_JAR="${CREGIT}/slickGitLog/target/scala-2.10/slickgitlog_2.10-0.1-SNAPSHOT-one-jar.jar"
PERSONS_JAR="${CREGIT}/persons/target/scala-2.10/persons_2.10-0.1-SNAPSHOT-one-jar.jar"
REMAP_COMMITS_JAR="${CREGIT}/remapCommits/target/scala-2.10/remapcommits_2.10-0.1-SNAPSHOT-one-jar.jar"

REPO_PATH_ORIGINAL="${WORK}/${REPO_NAME}-original"
REPO_PATH_CREGIT="${WORK}/${REPO_NAME}-cregit"
REPO_PATH_ORIGINAL_BARE="${REPO_PATH_ORIGINAL}.git"
REPO_PATH_CREGIT_BARE="${REPO_PATH_CREGIT}.git"

DB_PATH_ORIGINAL="${REPO_PATH_ORIGINAL}.db"
DB_PATH_CREGIT="${REPO_PATH_CREGIT}.db"
DB_PATH_BLOB_MAP="${WORK}/${REPO_NAME}-blob-map.db"
DB_PATH_PERSONS="${WORK}/${REPO_NAME}-persons.db"
XLS_PATH_PERSONS="${WORK}/${REPO_NAME}-persons.xls"
DATASET_PATH="${WORK}/${REPO_NAME}-dataset.parquet"

METRICS_FILE=${METRICS_FILE:-"${WORK}/metrics.csv"}
LOG_FILE="${WORK}/pipeline.log"
MANIFEST_FILE="${WORK}/manifest.txt"
TIME_DIR="${WORK}/time"

die() {
    log "ERROR: $1"
    exit 1
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

require_file() {
    [ -f "$1" ] || die "required file not found: $1 (build the project first)"
}

require_executable() {
    [ -x "$1" ] || die "required executable not found: $1 (build the project first)"
}

append_metric() {
    local stage=$1
    local time_file=$2
    local fallback_status=$3
    local line

    line=$(tail -n 1 "$time_file" 2>/dev/null || true)
    if [[ "$line" != TIME,* ]]; then
        line="TIME,0,0,0,0%,0,0,0,0,0,${fallback_status}"
    fi
    line=${line#TIME,}
    printf '%s,%s,%s,%s,%s\n' \
        "$RUN_ID" "$REPO_NAME" "$RESOLVED_REV" "$stage" "$line" >> "$METRICS_FILE"
}

run_timed() {
    local stage=$1
    shift
    local time_file="${TIME_DIR}/${stage}.time"
    local status
    local -a measured_command=("$@")

    if [ -n "$PROFILE_STAGE" ] && [ "$stage" = "$PROFILE_STAGE" ]; then
        command -v perf >/dev/null 2>&1 || die "perf is required to profile stage [$stage]"
        PROFILE_DIR=${PROFILE_DIR:-"${WORK}/profile"}
        mkdir -p "$PROFILE_DIR"
        measured_command=(
            perf record
            --event=cpu-clock
            --freq="$PROFILE_FREQUENCY"
            --call-graph=dwarf
            --output="${PROFILE_DIR}/${stage}.perf.data"
            --
            "$@"
        )
        log "Profiling stage [$stage] into ${PROFILE_DIR}/${stage}.perf.data"
    fi

    log "Running stage [$stage]"
    set +e
    /usr/bin/time --quiet \
        --format='TIME,%e,%U,%S,%P,%M,%F,%R,%I,%O,%x' \
        --output="$time_file" \
        -- "${measured_command[@]}"
    status=$?
    set -e
    append_metric "$stage" "$time_file" "$status"
    [ "$status" -eq 0 ] || die "stage [$stage] failed with exit code $status"
}

STEP_NUM=0
STEP_START=0
RESOLVED_REV=$REPO_REV

step() {
    STEP_NUM=$((STEP_NUM + 1))
    STEP_START=$(date +%s)
    [ "$STEP_NUM" -lt "$FROM_STEP" ] && return 0
    echo ""
    echo "==================================================================="
    echo "  Step $STEP_NUM -- $1"
    echo "==================================================================="
}

end_step() {
    [ "$STEP_NUM" -lt "$FROM_STEP" ] && return 0
    local elapsed=$(( $(date +%s) - STEP_START ))
    echo "  completed in ${elapsed}s"
}

mkdir -p "$WORK" "$WORK/memo" "$WORK/blame" "$WORK/html" "$TIME_DIR"
if [ ! -f "$METRICS_FILE" ]; then
    printf '%s\n' 'run_id,repository,revision,stage,elapsed_seconds,user_seconds,system_seconds,cpu_percent,max_rss_kb,major_page_faults,minor_page_faults,fs_inputs,fs_outputs,exit_code' > "$METRICS_FILE"
fi

exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo "=========================================================================="
echo "  Cregit Pipeline -- $REPO_NAME@$REPO_REV"
echo "  Work: $WORK"
echo "  Metrics: $METRICS_FILE"
echo "=========================================================================="
echo ""

# Step 1 -- clone and pin the original repository.
step "clone and pin original repository"
if [ "$STEP_NUM" -ge "$FROM_STEP" ]; then
    [ ! -e "$REPO_PATH_ORIGINAL_BARE" ] || die "destination already exists: $REPO_PATH_ORIGINAL_BARE"
    run_timed clone_original git clone --bare --single-branch --no-tags \
        "$REPO_GIT_URL" "$REPO_PATH_ORIGINAL_BARE"
else
    [ -d "$REPO_PATH_ORIGINAL_BARE" ] || die "step 1 output missing: $REPO_PATH_ORIGINAL_BARE"
fi

RESOLVED_REV=$(git --git-dir="$REPO_PATH_ORIGINAL_BARE" rev-parse --verify "${REPO_REV}^{commit}") \
    || die "revision [$REPO_REV] is not available in the single-branch clone"
SOURCE_HEAD_REF=$(git --git-dir="$REPO_PATH_ORIGINAL_BARE" symbolic-ref HEAD)
git --git-dir="$REPO_PATH_ORIGINAL_BARE" update-ref "$SOURCE_HEAD_REF" "$RESOLVED_REV"

{
    printf 'repository=%s\n' "$REPO_NAME"
    printf 'url=%s\n' "$REPO_GIT_URL"
    printf 'requested_revision=%s\n' "$REPO_REV"
    printf 'resolved_revision=%s\n' "$RESOLVED_REV"
    printf 'file_mask=%s\n' "$FILE_MASK"
    printf 'run_id=%s\n' "$RUN_ID"
    printf 'blobexec_strategy=%s\n' "$BLOBEXEC_STRATEGY"
    printf 'started_at=%s\n' "$(date --iso-8601=seconds)"
} > "$MANIFEST_FILE"
end_step

# Step 2 -- rewrite history and tokenize matching blobs.
step "rewrite history and tokenize blobs"
if [ "$STEP_NUM" -ge "$FROM_STEP" ]; then
    require_file "$BLOBEXEC_JAR"
    require_executable "${CREGIT}/tokenizeByBlobId/tokenBySha.pl"
    require_executable "${CREGIT}/tokenize/tokenize.pl"
    require_executable "${CREGIT}/tokenize/srcMLtoken/srcml2token"

    export BFG_MEMO_DIR="${WORK}/memo"
    export BFG_TOKENIZE_CMD="${CREGIT}/tokenize/tokenize.pl \
--srcml2token=${CREGIT}/tokenize/srcMLtoken/srcml2token \
--srcml=$(command -v srcml) \
--ctags=$(command -v ctags)"

    BLOBEXEC_JAVA_ARGS=()
    if [ -n "$JFR_FILE" ]; then
        mkdir -p "$(dirname -- "$JFR_FILE")"
        BLOBEXEC_JAVA_ARGS+=(
            "-XX:StartFlightRecording=filename=${JFR_FILE},settings=profile,dumponexit=true"
        )
        log "Recording blobExec JVM events into $JFR_FILE"
    fi

    BLOBEXEC_FLAGS=(--abort-on-error)
    if [ "$BLOBEXEC_STRATEGY" = prepare-first ]; then
        BLOBEXEC_FLAGS+=(--prepare-first)
    fi

    run_timed blobexec \
        java "${BLOBEXEC_JAVA_ARGS[@]}" -jar "$BLOBEXEC_JAR" "${BLOBEXEC_FLAGS[@]}" \
        "$REPO_PATH_ORIGINAL_BARE" \
        "$REPO_PATH_CREGIT_BARE" \
        "$DB_PATH_BLOB_MAP" \
        "${CREGIT}/tokenizeByBlobId/tokenBySha.pl" \
        "$FILE_MASK"
fi
end_step

# Step 3 -- repository maintenance, measured independently from blobExec.
step "maintain rewritten repository"
if [ "$STEP_NUM" -ge "$FROM_STEP" ]; then
    [ -d "$REPO_PATH_CREGIT_BARE" ] || die "step 2 output missing: $REPO_PATH_CREGIT_BARE"
    if [ "$GC_MODE" != skip ]; then
        run_timed reflog_expire git --git-dir="$REPO_PATH_CREGIT_BARE" \
            reflog expire --expire=now --all
        if [ "$GC_MODE" = aggressive ]; then
            run_timed git_gc git --git-dir="$REPO_PATH_CREGIT_BARE" \
                gc --prune=now --aggressive
        else
            run_timed git_gc git --git-dir="$REPO_PATH_CREGIT_BARE" \
                gc --prune=now
        fi
    fi
fi
end_step

# Step 4 -- Git metadata database for the original repository.
step "git log database for original repository"
if [ "$STEP_NUM" -ge "$FROM_STEP" ]; then
    require_file "$SLICK_GIT_LOG_JAR"
    run_timed git_log_original \
        "${LEGACY_JAVA_HOME:-/usr}/bin/java" -jar "$SLICK_GIT_LOG_JAR" \
        "$DB_PATH_ORIGINAL" "$REPO_PATH_ORIGINAL_BARE"
fi
end_step

# Step 5 -- Git metadata database for the rewritten repository.
step "git log database for rewritten repository"
if [ "$STEP_NUM" -ge "$FROM_STEP" ]; then
    [ -f "$DB_PATH_ORIGINAL" ] || die "step 4 output missing: $DB_PATH_ORIGINAL"
    run_timed git_log_cregit \
        "${LEGACY_JAVA_HOME:-/usr}/bin/java" -jar "$SLICK_GIT_LOG_JAR" \
        "$DB_PATH_CREGIT" "$REPO_PATH_CREGIT_BARE"
fi
end_step

# Step 6 -- unified people database.
step "persons database"
if [ "$STEP_NUM" -ge "$FROM_STEP" ]; then
    [ -f "$DB_PATH_CREGIT" ] || die "step 5 output missing: $DB_PATH_CREGIT"
    require_file "$PERSONS_JAR"
    run_timed persons \
        "${LEGACY_JAVA_HOME:-/usr}/bin/java" -jar "$PERSONS_JAR" \
        "$REPO_PATH_ORIGINAL_BARE" "$XLS_PATH_PERSONS" "$DB_PATH_PERSONS"
fi
end_step

# Step 7 -- working clones used by blame and HTML generation.
step "working clones"
if [ "$STEP_NUM" -ge "$FROM_STEP" ]; then
    [ -f "$DB_PATH_PERSONS" ] || die "step 6 output missing: $DB_PATH_PERSONS"
    run_timed clone_work_original git clone --no-local \
        "$REPO_PATH_ORIGINAL_BARE" "$REPO_PATH_ORIGINAL"
    run_timed clone_work_cregit git clone --no-local \
        "$REPO_PATH_CREGIT_BARE" "$REPO_PATH_CREGIT"
fi
end_step

# Step 8 -- blame each tokenized file.
step "token-level blame"
if [ "$STEP_NUM" -ge "$FROM_STEP" ]; then
    [ -d "$REPO_PATH_CREGIT" ] || die "step 7 output missing: $REPO_PATH_CREGIT"
    run_timed blame \
        perl "${CREGIT}/blameRepo/blameRepoFiles.pl" --verbose \
        --formatBlame="${CREGIT}/blameRepo/formatBlame.pl" \
        "$REPO_PATH_CREGIT" "$WORK/blame" "$FILE_MASK"
fi
end_step

# Step 9 -- map rewritten commit IDs back to original IDs.
step "remap commits"
if [ "$STEP_NUM" -ge "$FROM_STEP" ]; then
    [ -d "$WORK/blame" ] || die "step 8 output missing: $WORK/blame"
    require_file "$REMAP_COMMITS_JAR"
    run_timed remap_commits \
        "${LEGACY_JAVA_HOME:-/usr}/bin/java" -jar "$REMAP_COMMITS_JAR" \
        "$DB_PATH_CREGIT" "$REPO_PATH_CREGIT_BARE"
fi
end_step

# Step 10 -- render per-file HTML.
step "generate HTML views"
if [ "$STEP_NUM" -ge "$FROM_STEP" ]; then
    [ -f "$DB_PATH_CREGIT" ] || die "step 9 output missing: $DB_PATH_CREGIT"
    run_timed pretty_print \
        perl "${CREGIT}/prettyPrint/prettyPrintFiles.pl" --verbose \
        "$DB_PATH_CREGIT" "$DB_PATH_PERSONS" \
        "$REPO_PATH_ORIGINAL" "$WORK/blame" "$WORK/html" \
        "$REPO_COMMIT_URL" "$FILE_MASK"
fi
end_step

# Optional dataset stage; its implementation is developed on another branch.
if [ "$WITH_DATASET" -eq 1 ]; then
    step "generate Parquet dataset"
    if [ "$STEP_NUM" -ge "$FROM_STEP" ]; then
        require_file "${CREGIT}/generate_dataset.py"
        run_timed dataset python3 "${CREGIT}/generate_dataset.py" \
            --blame-dir "$WORK/blame" \
            --source-dir "$REPO_PATH_ORIGINAL" \
            --cregit-db "$DB_PATH_CREGIT" \
            --persons-db "$DB_PATH_PERSONS" \
            --output "$DATASET_PATH" \
            --repo-name "$REPO_NAME" \
            --verbose
    fi
    end_step
fi

printf 'finished_at=%s\n' "$(date --iso-8601=seconds)" >> "$MANIFEST_FILE"
log "Pipeline completed successfully for $REPO_NAME@$RESOLVED_REV"
