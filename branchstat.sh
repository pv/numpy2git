#!/bin/bash
#
# Show merge status of all branches in a Git repo vs. master branch
#

set -e

REPO="$1"
if test ! -d "$REPO"; then
    echo "Repository $REPO not found!"
    exit 1
fi

cd "$REPO"

echo "Unmerged (vs master) commits in branches"
echo "----------------------------------------"

ALLOK=1
for branch in `git branch|sort|sed -e s/^..//`; do
    if test "$branch" = "master"; then
	continue
    fi
    if expr "$branch" : "crud/.*" > /dev/null; then
	true
    else
	continue
    fi
    AHEAD=`git log --oneline master..$branch|wc -l`
    if test "$AHEAD" != "0"; then
	echo -e "$AHEAD\t$branch"
	ALLOK=0
    fi
done

if test "$ALLOK" = "1"; then
    echo "All branches fully merged."
fi

exit 0
