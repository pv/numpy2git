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
	rm -rf numpy numpy.save f2py-research vendor log-* \
	    revisions-numpy revisions-f2py-research \
	    revisions-vendor verify-numpy.git

svn2git:
	git clone git://gitorious.org/svn2git/svn2git.git svn2git

svn2git/svn-all-fast-export: svn2git
	cd svn2git && git checkout -f e1bebdeb4 && git clean -f -x
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

verify-numpy.git:
	./tree-checksum.py --all-git numpy.save | tee $@

verify-numpy.svn:
	./tree-checksum.py --all-svn $(SVN) | tee $@

verify: verify-numpy.git verify-numpy.svn
	./tree-checksum.py --compare verify-numpy.svn verify-numpy.git

graft:
	./postprocess.sh numpy numpy.grafts graft-only
	./branchstat.sh numpy numpy.branchskip

branchstat:
	./branchstat.sh numpy numpy.branchskip

postprocess:
	./postprocess.sh numpy numpy.grafts

final-cleanup:
	for f in numpy/refs/backups/*; do \
	    install -d "$$f"/tags; \
	    mv -f "$$f"/heads/svntags/* "$$f"/tags || true; \
	    mv -f "$$f"/heads/crud/* "$$f"/heads || true; \
	    rmdir -p --ignore-fail-on-non-empty "$$f"/heads/crud || true; \
	    rmdir -p --ignore-fail-on-non-empty "$$f"/heads/svntags || true; \
	done
	mv -f numpy/refs/backups numpy/refs/svn/
	rm -rf numpy/refs/original

gc:
	for repo in numpy vendor f2py-research; do \
	    (cd $$repo && \
	     git repack -f -a -d --depth=500 --window=250 && \
	     git gc --prune=0); \
	done

.PHONY: help all clean export graft final-cleanup postprocess gc verify
