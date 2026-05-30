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

# --- Incremental build selection -------------------------------------------
# By default, only (re)build "dirty" specs: ones with no prior build stamp, a
# spec file newer than its stamp, or built by an older build-local.sh. Pass
# --force to rebuild everything, or name specs to build just those.
#   build-repo.sh                 # build dirty specs, then assemble the repo
#   build-repo.sh --force         # rebuild all specs
#   build-repo.sh walker.spec     # build just walker.spec if dirty (--force to force)
# Stamps live in output/.stamps/ (gitignored with the rest of output/). The
# first run after adopting this rebuilds everything once to establish stamps.
force=false
requested=()
for arg in "$@"; do
  case "$arg" in
    -f|--force) force=true ;;
    -h|--help)  echo "usage: build-repo.sh [--force] [<name>.spec ...]  (default: build only dirty specs)"; exit 0 ;;
    *.spec)     requested+=("$arg") ;;
    *) echo "unknown argument: $arg (expected --force or a <name>.spec)" >&2; exit 2 ;;
  esac
done

STAMP_DIR="$COPR_DIR/output/.stamps"
BUILDER="$COPR_DIR/build-local.sh"
mkdir -p "$STAMP_DIR"

if (( ${#requested[@]} )); then
  candidates=("${requested[@]}")
else
  candidates=("${SPECS[@]}")
fi

to_build=()
for s in "${candidates[@]}"; do
  [[ -f "$COPR_DIR/$s" ]] || { echo "spec not found: $COPR_DIR/$s" >&2; exit 1; }
  stamp="$STAMP_DIR/$s"
  if $force || [[ ! -e $stamp || "$COPR_DIR/$s" -nt $stamp || "$BUILDER" -nt $stamp ]]; then
    to_build+=("$s")
  else
    echo "  up-to-date, skipping: $s"
  fi
done

if (( ${#to_build[@]} )); then
  echo "==> Building ${#to_build[@]} spec(s): ${to_build[*]}"
  for s in "${to_build[@]}"; do
    "$BUILDER" "$s"
    touch "$STAMP_DIR/$s"   # stamp only after a successful build (set -e aborts on failure)
  done
else
  echo "==> All specs up-to-date (use --force to rebuild all)"
fi

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
