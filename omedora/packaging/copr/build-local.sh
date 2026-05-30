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
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
COPR_DIR="$REPO/omedora/packaging/copr"
IMAGE="${OMEDORA_RPMBUILD_IMAGE:-registry.fedoraproject.org/fedora:44}"
# Persist dnf's package + metadata cache across builds. fedora:44 ships dnf5,
# whose cache lives under /var/cache/libdnf5 (NOT the dnf4 path /var/cache/dnf).
# With `--rm` each spec builds in a throwaway container, so without this volume
# EVERY build re-downloads the rpm-build/rpmdevtools/builddep tooling AND each
# spec's BuildRequires from scratch (most painful in build-repo.sh's 14-spec
# loop, where the common tooling is fetched 14 times). The named volume is
# auto-created on first use; keepcache=1 makes the downloaded RPMs stick.
CACHE_VOL="${OMEDORA_RPMBUILD_DNF_CACHE:-omedora-rpmbuild-dnf-cache}"

[[ -f "$COPR_DIR/$spec" ]] || { echo "spec not found: $COPR_DIR/$spec" >&2; exit 1; }

mkdir -p "$COPR_DIR/output"

echo "Building $spec in $IMAGE ..."
podman run --rm \
  -v "$COPR_DIR:/copr:z" \
  -v "$CACHE_VOL:/var/cache/libdnf5" \
  "$IMAGE" bash -euo pipefail -c '
    # rpm-build gives rpmbuild; rpmdevtools gives rpmdev-setuptree + spectool;
    # the builddep plugin installs a spec'\''s BuildRequires. keepcache=1 keeps
    # the downloaded RPMs in the mounted /var/cache/libdnf5 volume so the next
    # spec (next throwaway container) reuses them instead of re-downloading.
    dnf install -y --setopt=keepcache=1 --setopt=install_weak_deps=False \
      rpm-build rpmdevtools "dnf-command(builddep)" createrepo_c >/dev/null

    # Expose ALREADY-BUILT sibling RPMs to this build as a local dnf repo. The
    # Hyprland stack has deep intra-stack BuildRequires (e.g. hyprland BR
    # hyprutils-devel, aquamarine-devel, ...). build-repo.sh copies each freshly
    # built RPM into /copr/repo before invoking the next spec, so dnf builddep
    # below resolves just-built siblings. We (re)generate repodata here so the
    # repo is always valid even if an external caller only dropped RPMs in.
    # The repo is mounted read-write via /copr; createrepo_c needs the metadata
    # to exist for dnf to consume it.
    if compgen -G "/copr/repo/*.rpm" >/dev/null 2>&1; then
      [[ -d /copr/repo/repodata ]] || createrepo_c --quiet /copr/repo
      cat > /etc/yum.repos.d/omedora-local.repo <<EOF
[omedora-local]
name=omedora local build repo
baseurl=file:///copr/repo
enabled=1
gpgcheck=0
priority=1
EOF
    fi

    # Standard ~/rpmbuild/{SPECS,SOURCES,RPMS,SRPMS,BUILD} tree.
    rpmdev-setuptree
    cp "/copr/'"$spec"'" ~/rpmbuild/SPECS/

    # Install the spec'\''s BuildRequires (e.g. systemd-rpm-macros for
    # %%{_userunitdir}, or just-built sibling -devel packages). A COPR does this
    # step for you.
    dnf builddep -y --setopt=keepcache=1 ~/rpmbuild/SPECS/'"$spec"' >/dev/null

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
