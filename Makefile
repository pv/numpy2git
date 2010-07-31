SVN=$(CURDIR)/../numpy-svn

help:
	@echo "Targets:"
	@echo "  make clean"
	@echo "  make export          -- svn-all-fast-export"
	@echo "  make postprocess     -- postprocess"
	@echo "  make final-cleanup   -- final cleanup"
	@echo "  make gc              -- git-gc"
	@echo ""
	@echo "  make graft           -- (re-)do merge grafting"
	@echo "  make branchstat      -- show branch status"

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
	./postprocess.sh numpy numpy.grafts graft-only
	./branchstat.sh numpy numpy.branchskip

branchstat:
	./branchstat.sh numpy numpy.branchskip

postprocess:
	./postprocess.sh numpy numpy.grafts
	./branchstat.sh numpy

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
