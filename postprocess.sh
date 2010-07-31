#!/bin/bash
set -e

REPO="$1"
REPOBASE=`basename "$REPO"`
LOG="$PWD/postprocess-$REPOBASE.log"

if test ! -d "$REPO"; then
    echo "Repository $REPO not found!"
    exit 1
fi

cd "$REPO"
date -R > "$LOG"

run() {
    echo "\$" "$@"
    echo "\$" "$@" >> "$LOG"
    $@ 2>&1 | tee -a "$LOG"
}

# 1) Remove crud branches

for crud in `git branch|grep "^  crud/"`; do
    run git branch -D "$crud"
done

# 2) Convert SVN tag branches to real tags

for branch in `git branch|grep "^  svntags/"`; do
    tag=`echo -n "$branch"|sed -e 's@svntags/v*@@'|sed -e 's/_/./g'`
    tag="v$tag"
    run git tag "$tag" "$branch"
    run git branch -D "$branch"
done

# 3) Collect garbage
run git prune
