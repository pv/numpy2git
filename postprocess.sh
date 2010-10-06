#!/bin/bash
set -e

REPO="$1"
REPOBASE=`basename "$REPO"`
GRAFTS="$2"
GRAFT_ONLY="$3"
LOG="$PWD/log-$REPOBASE-postprocess"

if test -d "$REPO/.git"; then
    REPOGIT=".git"
else
    REPOGIT="."
fi

if test ! -d "$REPO"; then
    echo "Repository $REPO not found!"
    exit 1
fi

if test ! -f "$GRAFTS"; then
    echo "Graft file $GRAFTS not found!"
    exit 1
fi

# get absolute path
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

#
# 1) Inject graft points for merges
#

rm -f "$REPOGIT"/info/grafts
> "$REPOGIT"/info/grafts.new

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
	exit 123
    fi
    BASE_PARENT_HASH=`git rev-parse $BASE_HASH^ 2>/dev/null || true`
    if test "$BASE_PARENT_HASH" = "$BASE_HASH^"; then
	msg "Reparenting: $BRANCH -> $BASE"
	echo "$BASE_HASH $BRANCH_HASH" >> "$REPOGIT"/info/grafts.new
    else
	msg "Grafting $BRANCH -> $BASE"
	echo "$BASE_HASH $BASE_PARENT_HASH $BRANCH_HASH" >> "$REPOGIT"/info/grafts.new
    fi
done

if test "$?" = "123"; then
    msg "Failure in grafting!"
    exit 1
fi

mv -f "$REPOGIT"/info/grafts.new "$REPOGIT"/info/grafts

if test "$GRAFT_ONLY" = "graft-only"; then
    exit 0;
fi


#
# 2) Hide crud branches
#

mkdir -p "$REPOGIT"/refs/svn
if test -d "$REPOGIT"/refs/heads/crud; then
    mv "$REPOGIT"/refs/heads/crud/* "$REPOGIT"/refs/svn/
    rmdir "$REPOGIT"/refs/heads/crud
fi

for crud in `git branch|grep "^  crud/"`; do
    run git branch -D "$crud"
done

#
# 3) Convert SVN tag branches to real tags, and hide the SVN branches
#

for branch in `git branch|grep "^  svntags/"`; do
    tag=`echo -n "$branch"|sed -e 's@svntags/v*@@'|sed -e 's/_/./g'`
    tag="v$tag"
    run git tag "$tag" "$branch"
done

if test -d "$REPOGIT"/refs/heads/svntags; then
    mkdir -p "$REPOGIT"/refs/svn/svntags
    mv "$REPOGIT"/refs/heads/svntags/* "$REPOGIT"/refs/svn/svntags/
    rmdir "$REPOGIT"/refs/heads/svntags
fi

#
# 4) Collect garbage
#
MAX_REVISION=`git log --all | sed -n -e '/^    svn path/{s/.*revision=//;p}'|sort -n|tail -n1`

run git reflog expire --expire=0 --all
run git prune


#
# 5) Strip SVN metadata, and make the grafts permanent
#

run git filter-branch --msg-filter 'head -n-2' -- --all
rm -f info/grafts
