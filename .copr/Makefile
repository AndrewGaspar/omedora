# COPR SRPM-generation entrypoint for the omedora package set.
#
# COPR's "make" SRPM source method runs, per configured package:
#     make -f .copr/Makefile srpm outdir="<dir>" spec="<spec>"
# where $(spec) is that package's "Spec File" and $(outdir) is where the produced
# .src.rpm must land. We delegate to .copr/srpm.sh (plain bash, kept in sync with
# omedora/packaging/copr/build-local.sh's SRPM-gen flow). The mock BUILD phase
# that follows is OFFLINE, so source fetching + Rust cargo-vendor happen in the
# SRPM step (inside srpm.sh), not at build time.

.PHONY: srpm
srpm:
	bash "$(dir $(lastword $(MAKEFILE_LIST)))srpm.sh" "$(spec)" "$(outdir)"
