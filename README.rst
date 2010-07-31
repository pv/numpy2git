Numpy SVN to Git conversion
===========================

We do Numpy SVN -> GIT conversion as listed below.

All of this is driven by a Makefile, whose targets we list below.
Quick usage:

    svnsync http://...  numpy-svn
    make all SVN=numpy-svn

You also need an ``authors.map`` in the format

    svnaccount          Real Name <real@email.foo>

mapping SVN users to Git users.  (We don't add it into this repository.)


export (step 1)
---------------

Use ``svn-all-fast-export`` to produce a Git repository.

We move all "undesired" crap under ``crud/`` -- we don't drop anything
in this stage.

We also include SVN metadata into the commit messages. This will be
rewritten later on.

Valid SVN tags go, as branches, under ``svntags/``.


postprocess (step 2)
--------------------

Generic postprocessing (``postprocess.sh``)

This entails a couple of things:

1. Merge point grafting.

   As is well-known, SVN history contains no merge information.
   So, we have to list the relevant info manually. This goes into
   ``numpy.grafts`` -- there we list the merge commits, and the
   extra parent of the merge commit.

   The point here is that the branches under ``crud/`` will be dropped
   in the end. However, some of them were topic branches once in a time,
   so this would drop some relevant history. So here we aim to stitch
   the history manually together, by connecting the topical work
   to the trunk by manually inserting merge parents.

   What ``postprocess.sh`` essentially does here, is that it looks
   up the hash corresponding to the SVN revisions in the
   ``.grafts`` file, and dumps that information to Git via the text
   file ``info/grafts``.

2. Remove all branches under ``crud/``

3. Convert all branches under ``svntags/`` to real Git tags.
   The branches are removed, leaving only the tags.

4. ``git prune`` is called to get rid of unwanted stuff.

5. We check which SVN commits didn't make it into the Git repo,
   and dump that information to ``postprocess-REPONAME.droplist``.

6. SVN metadata is stripped from the commit messages.

   At the same time, this step makes the grafts permanent, and we can
   remove the ``info/grafts`` file.

final-cleanup (step 3)
----------------------

We remove a couple of leftover branches and tags, and strip all
Weave-related stuff out from Numpy.

gc (step 4)
-----------

Simply run ``git gc``

graft (diagnostic)
------------------

When playing around with grafting, it's useful to just run
``make clean export`` first, and then do

- edit ``numpy.grafts``
- run ``make graft``

until the result is satisfactory.

branchstat (diagnostic)
-----------------------

The ``branchstat.sh`` script checks all remaining branches,
and reports those with dangling unmerged commits.

It ignores the branches listed in ``numpy.branchskip``
