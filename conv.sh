#!/bin/bash
set -e
cd /home/pauli/wrk/external/numpy2git
rm -rf numpy f2py-research vendor

# Convert
svn-all-fast-export \
    --identity-map authors.map \
    --rules numpy.rules \
    --commit-interval 1000 \
    --add-metadata \
    $PWD/../numpy-svn \
2>&1 | tee numpy-export.log

# Postprocess
./postprocess.sh numpy numpy.grafts

# Some manual cleanup
(cd numpy && git branch -D maintenance/1.1.x_5227)
(cd numpy && git branch -D master_1460)
(cd numpy && git tag -d v0.9.6.2236)

# Finalize
cd numpy && git gc --aggressive
