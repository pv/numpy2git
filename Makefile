SVN=$(CURDIR)/../numpy-svn

help:
	@echo "Targets:"
	@echo "  make clean"
	@echo "  make export          -- svn-all-fast-export"
	@echo "  make graft           -- graft merges"
	@echo "  make postprocess     -- postprocess (irreversible)"
	@echo "  make final-cleanup   -- final cleanup (irreversible)"
	@echo "  make gc              -- git-gc"

all: clean export postprocess gc

clean:
	rm -rf numpy f2py-research vendor

export:
	svn-all-fast-export \
	  --identity-map authors.map \
	  --rules numpy.rules \
	  --commit-interval 1000 \
	  --add-metadata \
	  $(SVN) \
	2>&1 | tee numpy-export.log

graft:
	./postprocess.sh numpy numpy.graft graft-only

postprocess:
	./postprocess.sh numpy numpy.graft

final-cleanup:
	cd numpy && git branch -D maintenance/1.1.x_5227
	cd numpy && git branch -D master_1460
	cd numpy && git tag -d v0.9.6.2236
	cd numpy && git filter-branch --prune-empty \
	 --index-filter 'git update-index --force-remove -- weave scipy/weave' \
	 -- --all

gc:
	cd numpy && git gc --aggressive
	cd vendor && git gc --aggressive
	cd f2py-research && git gc --aggressive

.PHONY: help all clean export graft final-cleanup postprocess gc
