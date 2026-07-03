# Fedora: Omedora hosts satty in its COPR (omedora/packaging/copr/satty.spec) and
# does not yet package tensaku. Skip on Omedora so satty is kept and not dropped;
# adopting tensaku is a separate packaging task. (Do NOT skip-map tensaku instead
# — that would let omarchy-pkg-drop satty run and remove a working tool.)
[[ "${OMARCHY_DISTRO:-$(omarchy-distro 2>/dev/null || echo arch)}" == "fedora" ]] && exit 0

echo "Replace Satty with Tensaku"

omarchy-pkg-add tensaku
omarchy-pkg-drop satty
