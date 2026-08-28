#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 4 ]; then
    echo "Usage: $0 <bare-repository> <name> [revision] [file-mask]" >&2
    exit 1
fi

REPOSITORY=$1
NAME=$2
REVISION=${3:-HEAD}
FILE_MASK=${4:-'\.[ch]$'}

[ -d "$REPOSITORY" ] || { echo "Repository not found: $REPOSITORY" >&2; exit 1; }

RESOLVED_REV=$(git --git-dir="$REPOSITORY" rev-parse --verify "${REVISION}^{commit}")
COMMITS=$(git --git-dir="$REPOSITORY" rev-list --count "$RESOLVED_REV")
AUTHORS=$(git --git-dir="$REPOSITORY" log --format='%aN <%aE>' "$RESOLVED_REV" | LC_ALL=C sort -u | wc -l)
CURRENT_FILES=$(git --git-dir="$REPOSITORY" ls-tree -r --name-only "$RESOLVED_REV" |
    perl -e 'my $p = shift; while (<STDIN>) { chomp; $n++ if /$p/ } print 0 + $n' "$FILE_MASK")
REPOSITORY_KB=$(du -sk "$REPOSITORY" | awk '{print $1}')

OBJECT_STATS=$(
    git --git-dir="$REPOSITORY" rev-list --objects "$RESOLVED_REV" |
    git --git-dir="$REPOSITORY" cat-file \
        --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' |
    perl -e '
        my $pattern = shift;
        my ($count, $bytes, $max) = (0, 0, 0);
        while (<STDIN>) {
            chomp;
            my ($type, $oid, $size, $path) = split(/ /, $_, 4);
            next unless defined($path) && $type eq "blob" && $path =~ /$pattern/;
            $count++;
            $bytes += $size;
            $max = $size if $size > $max;
        }
        print join(",", $count, $bytes, $max);
    ' "$FILE_MASK"
)

printf '%s\n' 'repository,revision,commits,authors,current_matching_files,unique_historical_matching_blobs,historical_matching_bytes,max_matching_blob_bytes,bare_repository_kb'
printf '%s,%s,%s,%s,%s,%s,%s\n' \
    "$NAME" "$RESOLVED_REV" "$COMMITS" "$AUTHORS" "$CURRENT_FILES" \
    "$OBJECT_STATS" "$REPOSITORY_KB"
