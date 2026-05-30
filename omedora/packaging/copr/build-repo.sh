#!/bin/bash
#
# Build all omedora RPMs and assemble them into a local dnf repository.
#
# This local repo is the stand-in for a published COPR: a directory of RPMs
# with `createrepo_c` metadata that dnf can install from. The L4 session build
# (build-session.sh) drops it into the container and points dnf at it, so
# install.sh resolves walker/elephant/fonts + their dependencies exactly as it
# would from a real COPR. When you publish the COPR, the only change is swapping
# the repo URL (or flipping fedora.toml entries to source = "copr").
#
# Output: packaging/copr/repo/ (a ready-to-serve dnf repo; gitignored).

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
COPR_DIR="$REPO/omedora/packaging/copr"
IMAGE="${OMEDORA_RPMBUILD_IMAGE:-registry.fedoraproject.org/fedora:44}"

SPECS=(
  walker.spec elephant.spec omedora-nerd-fonts.spec swayosd.spec terminaltexteffects.spec
  # task #59 back-fill (all build-tested):
  lazygit.spec lazydocker.spec mise.spec starship.spec usage.spec
  satty.spec bluetui.spec hyprland-preview-share-picker.spec omarchy-nvim.spec
  # claude-code.spec is intentionally NOT built here — parked pending a
  # redistribution-licensing decision before any public COPR (proprietary binary).
)

echo "==> Building RPMs"
for s in "${SPECS[@]}"; do
  "$COPR_DIR/build-local.sh" "$s"
done

echo ""
echo "==> Assembling local repo (createrepo_c)"
podman run --rm -v "$COPR_DIR:/copr:z" "$IMAGE" bash -euo pipefail -c '
  dnf install -y --setopt=install_weak_deps=False createrepo_c >/dev/null
  rm -rf /copr/repo
  mkdir -p /copr/repo
  # Binary RPMs only (skip the .src.rpm — not needed to install from).
  cp /copr/output/*.x86_64.rpm /copr/output/*.noarch.rpm /copr/repo/ 2>/dev/null || true
  createrepo_c --quiet /copr/repo
  echo "repo contents:"
  ls -1 /copr/repo/*.rpm | sed "s#.*/#  #"
'
echo ""
echo "Local repo ready: $COPR_DIR/repo/  (baseurl file:///opt/omedora-repo in-container)"
