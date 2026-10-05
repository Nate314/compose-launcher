#!/usr/bin/env bash
# Copies the launcher into project folders, or checks that their copies are identical.
#   ./sync.sh <project-dir>...           copy run.sh and run.ps1, record this commit in run.version
#   ./sync.sh --check <project-dir>...   exit 1 if a vendored copy differs from this repository
set -eu
SRC=$(cd "$(dirname "$0")" && pwd)
FILES="run.sh run.ps1"

die() { echo "sync.sh: $*" >&2; exit 2; }

MODE=sync
if [ "${1:-}" = --check ]; then MODE=check; shift; fi
[ $# -gt 0 ] || die "usage: sync.sh [--check] <project-dir>..."
for dir in "$@"; do [ -d "$dir" ] || die "not a folder: $dir"; done

if [ "$MODE" = sync ]; then
  # run.version must name a commit that really contains the copied files.
  git -C "$SRC" diff --quiet HEAD -- $FILES || die "commit the changes to run.sh and run.ps1 before syncing"
  commit=$(git -C "$SRC" rev-parse HEAD)
fi

drift=0
for dir in "$@"; do
  if [ "$MODE" = sync ]; then
    for f in $FILES; do cp "$SRC/$f" "$dir/$f"; done
    printf '%s\n' "$commit" > "$dir/run.version"
    echo "synced $dir at $commit"
    continue
  fi
  version=$(cat "$dir/run.version" 2>/dev/null || echo "no run.version")
  for f in $FILES; do
    if cmp -s "$SRC/$f" "$dir/$f"; then
      echo "ok    $dir/$f"
    else
      echo "DRIFT $dir/$f differs from $SRC/$f (vendored from: $version)"
      drift=1
    fi
  done
done
exit $drift
