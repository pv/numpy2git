#!/bin/bash
#
# Show merge status of all branches in a Git repo vs. master branch
#

set -e

REPO="$1"
SKIPLIST="$2"

pushd `dirname "$SKIPLIST"` > /dev/null
SKIPLIST="`pwd`/`basename "$SKIPLIST"`"
popd > /dev/null

if test ! -d "$REPO"; then
    echo "Repository $REPO not found!"
    exit 1
fi

cd "$REPO"

MASTER_PARENT=`git rev-list --parents master | grep -v ' ' | tail -n1`
PARENTLESS=`git rev-list --parents --all | grep -v ' '`

echo ""
echo "Parentless commits"
echo "------------------"

for commit in $PARENTLESS; do
    BRANCHES=""
    if test "$commit" != "$MASTER_PARENT"; then
        echo "- $commit"
    else
	echo "- $commit (master root)"
    fi
done

echo ""
echo "Unmerged (vs master) commits in branches"
echo "----------------------------------------"

ALLOK=1
for branch in `git for-each-ref --format="%(refname)" refs|sort`; do
    if test "$branch" = "refs/heads/master"; then
	continue
    fi
    if expr "$branch" : ".*/maintenance/.*" > /dev/null; then
	continue
    elif expr "$branch" : ".*/svntags/.*" > /dev/null; then
	continue
    else
	true
    fi
    AHEAD=`git log --oneline master..$branch|wc -l`
    if test -f "$SKIPLIST" && grep -q "^$AHEAD[ \t]*$branch" "$SKIPLIST"; then
	# skipped
	continue
    fi
    if test "$AHEAD" != "0"; then
	echo -e "$AHEAD\t$branch"
	ALLOK=0
    fi
done


if test "$ALLOK" = "1"; then
    echo "All branches fully merged (or skipped)."
fi

exit 0
