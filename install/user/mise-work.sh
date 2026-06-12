# omedora: Fedora dispatches to the mise-work-fedora.sh sibling. The Arch
# iso-chroot branch below expects the ISO's bundled Node tarball under
# /opt/packages, which doesn't exist on a Fedora install (finalize-user runs
# with --first-install there too) — it would hard-fail the whole finalize. The
# Arch body below is byte-identical to upstream. See omedora/architecture.md
# §"Omarchy 4 setup-system gating map".
if [[ "${OMARCHY_DISTRO:-$(omarchy-distro 2>/dev/null || echo arch)}" == "fedora" ]]; then
  source "${BASH_SOURCE[0]%/*}/mise-work-fedora.sh"
  return 0 2>/dev/null || exit 0
fi

# Setup default work directory (and tries)
mkdir -p "$HOME/Work"
mkdir -p "$HOME/Work/tries"
