#!/bin/bash
set -e

REPO="$1"
REPOBASE=`basename "$REPO"`
GRAFTS="$2"
LOG="$PWD/postprocess-$REPOBASE.log"

if test -d "$REPO/.git"; then
    REPO="$REPO/.git"
fi

if test ! -d "$REPO"; then
    echo "Repository $REPO not found!"
    exit 1
fi

if test ! -f "$GRAFTS"; then
    echo "Graft file $GRAFTS not found!"
    exit 1
fi

# how can getting an absolute path be this hard?
pushd `dirname "$GRAFTS"` > /dev/null
GRAFTS="`pwd`/`basename "$GRAFTS"`"
popd > /dev/null

cd "$REPO"
date -R > "$LOG"

run() {
    echo "\$" "$@"
    echo "\$" "$@" >> "$LOG"
    "$@" 2>&1 | tee -a "$LOG"
}

msg() {
    echo "$@" 2>&1 | tee -a "$LOG"
}


# 1) Inject graft points for merges

> info/grafts

cat "$GRAFTS" | while read BASE BRANCH; do
    if test -z "$BASE" -a -z "$BRANCH"; then
	continue
    fi
    if expr "$BASE" : "^#.*" > /dev/null; then
	continue
    fi
    if test -z "$BASE" -a -z "$BRANCH"; then
	msg "Incomplete graft point <$BASE>:<$BRANCH>"
    fi
    BASE_GREP=`echo "$BASE" | sed -e 's@^\(.*\):\(.*\)$@svn path=/\1/; revision=\2$@'|sed -e 's/\./\\./g'`
    BRANCH_GREP=`echo "$BRANCH" | sed -e 's@^\(.*\):\(.*\)$@svn path=/\1/; revision=\2$@'|sed -e 's/\./\\./g'`
    BASE_HASH=`git log --grep="$BASE_GREP" --format=format:%H --all`
    BRANCH_HASH=`git log --grep="$BRANCH_GREP" --format=format:%H --all`
    if test -z "$BASE_HASH" -o -z "$BRANCH_HASH"; then
	msg "ERROR: Graft point <$BASE>:<$BRANCH> not found: <$BASE_HASH>:<$BRANCH_HASH>"
	exit 1
    fi
    BASE_PARENT_HASH=`git rev-parse $BASE_HASH^`
    msg "Grafting $BRANCH -> $BASE"
    #msg "    base: $BASE_HASH"
    #msg "    parent: $BASE_PARENT_HASH"
    #msg "    added parent: $BRANCH_HASH"
    echo "$BASE_HASH $BASE_PARENT_HASH $BRANCH_HASH" >> info/grafts
done

if test "$?" != 0; then
    echo "Failure!"
    exit 1
fi

exit 0

# 2) Strip SVN metadata, and make the grafts permanent

run git filter-branch --msg-filter 'head -n-2' -- --all
rm -f info/grafts

# 3) Remove crud branches

for crud in `git branch|grep "^  crud/"`; do
    run git branch -D "$crud"
done

# 4) Convert SVN tag branches to real tags

for branch in `git branch|grep "^  svntags/"`; do
    tag=`echo -n "$branch"|sed -e 's@svntags/v*@@'|sed -e 's/_/./g'`
    tag="v$tag"
    run git tag "$tag" "$branch"
    run git branch -D "$branch"
done

# 4) Collect garbage
run git prune
