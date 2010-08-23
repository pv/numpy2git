SVN=$(CURDIR)/../numpy-svn

help:
	@echo "Targets:"
	@echo ""
	@echo "  make clean"
	@echo "  make export SVN=...  -- svn-all-fast-export"
	@echo "  make postprocess     -- postprocess"
	@echo "  make final-cleanup   -- final cleanup"
	@echo "  make gc              -- git-gc"
	@echo ""
	@echo "  make graft           -- (re-)do merge grafting"
	@echo "  make branchstat      -- show branch status"
	@echo ""

all: clean export postprocess final-cleanup gc

clean:
	rm -rf numpy numpy.save f2py-research vendor log-*

svn2git:
	git clone git://gitorious.org/svn2git/svn2git.git svn2git

svn2git/svn-all-fast-export: svn2git
	cd svn2git && git checkout -f 80d1c990 && git clean -f -x
	cd svn2git && qmake
	make -C svn2git

export: svn2git/svn-all-fast-export
	./svn2git/svn-all-fast-export \
	  --identity-map authors.map \
	  --rules numpy.rules \
	  --add-metadata \
	  --commit-interval 500 \
	  $(SVN) \
	2>&1 | tee log-numpy-export
	rm -rf numpy.save
	cp -a numpy numpy.save

graft:
	./postprocess.sh numpy numpy.grafts graft-only
	./branchstat.sh numpy numpy.branchskip

branchstat:
	./branchstat.sh numpy numpy.branchskip

postprocess:
	./postprocess.sh numpy numpy.grafts

final-cleanup:
	mv numpy/refs/heads/maintenance/1.1.x_5227 \
	   numpy/refs/heads/master_1460 \
	   numpy/refs/svn/
	cd numpy && git tag -d v0.9.6.2236
	cd numpy && git tag -d v0.4.2b1.1250
	rm -rf numpy/refs/original

gc:
	for repo in numpy vendor f2py-research; do \
	    (cd $$repo && \
	     git repack -f -a -d --depth=500 --window=250 && \
	     git gc --prune=0); \
	done

.PHONY: help all clean export graft final-cleanup postprocess gc
