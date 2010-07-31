#!/bin/bash
set -e
cd /home/pauli/wrk/external/numpy2git
rm -rf numpy f2py-research vendor

# Convert
svn-all-fast-export --identity-map authors.map --rules numpy.rules $PWD/../numpy-svn

# Postprocess
./postprocess.sh numpy

# Some manual cleanup
(cd numpy && git branch -D maintenance/1.1.x_5227)
(cd numpy && git tag -d v0.9.6.2236)

# Finalize
cd numpy && git gc --aggressive
