#!/bin/bash
#
# Build an omedora RPM spec locally, inside a fedora:44 container.
#
# Our dev host is Arch (no rpmbuild), so we build in a throwaway Fedora
# container. This is exactly what a COPR does on Fedora's servers — same spec,
# same toolchain — so a spec that builds here will build there.
#
# Usage:
#   packaging/copr/build-local.sh walker.spec
#   packaging/copr/build-local.sh elephant.spec
#
# Output: built .rpm (and .src.rpm) land in packaging/copr/output/.

set -euo pipefail

spec="${1:?usage: build-local.sh <name.spec>}"
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
COPR_DIR="$REPO/packaging/copr"
IMAGE="${OMEDORA_RPMBUILD_IMAGE:-registry.fedoraproject.org/fedora:44}"

[[ -f "$COPR_DIR/$spec" ]] || { echo "spec not found: $COPR_DIR/$spec" >&2; exit 1; }

mkdir -p "$COPR_DIR/output"

echo "Building $spec in $IMAGE ..."
podman run --rm \
  -v "$COPR_DIR:/copr:z" \
  "$IMAGE" bash -euo pipefail -c '
    # rpm-build gives rpmbuild; rpmdevtools gives rpmdev-setuptree + spectool.
    dnf install -y --setopt=install_weak_deps=False rpm-build rpmdevtools >/dev/null

    # Standard ~/rpmbuild/{SPECS,SOURCES,RPMS,SRPMS,BUILD} tree.
    rpmdev-setuptree
    cp "/copr/'"$spec"'" ~/rpmbuild/SPECS/

    # Download every Source0/SourceN URL declared in the spec into SOURCES/.
    spectool -g -R ~/rpmbuild/SPECS/'"$spec"'

    # -ba = build Both the binary RPM and the source RPM.
    rpmbuild -ba ~/rpmbuild/SPECS/'"$spec"'

    # Hand the artifacts back to the host via the bind mount.
    cp -v ~/rpmbuild/RPMS/*/*.rpm /copr/output/ 2>/dev/null || true
    cp -v ~/rpmbuild/SRPMS/*.rpm  /copr/output/ 2>/dev/null || true
  '

echo ""
echo "Done. Artifacts in packaging/copr/output/:"
ls -1 "$COPR_DIR/output/" | sed 's/^/  /'
