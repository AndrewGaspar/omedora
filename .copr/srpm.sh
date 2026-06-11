#!/bin/bash
#
# COPR SRPM-generation for the omedora package set. Invoked by .copr/Makefile's
# `srpm` target, which COPR runs per configured package:
#     make -f .copr/Makefile srpm outdir="<dir>" spec="<spec>"
# $1 = the package's "Spec File", $2 = where the produced .src.rpm must land.
#
# The mock BUILD phase that follows on COPR is OFFLINE, so everything that needs
# the network happens HERE, in the SRPM step: fetching the declared sources and
# regenerating the Rust cargo-vendor tarball. This mirrors the SRPM-gen flow in
# omedora/packaging/copr/build-local.sh (the local stand-in) but stops at the
# source RPM (rpmbuild -bs). build-local.sh is the source of truth for the
# spectool -> pin-verify -> cargo-vendor sequence; keep the two in sync.

set -euo pipefail

spec="${1:?usage: srpm.sh <spec-path> <outdir>}"
outdir="${2:?usage: srpm.sh <spec-path> <outdir>}"

# $spec may be a bare basename (COPR Subdirectory = the spec dir) or a
# repo-relative/absolute path. Resolve the directory holding the spec, its
# <spec>.sources pin file, and any local (non-URL) Source siblings.
spec_dir=$(cd -- "$(dirname -- "$spec")" && pwd)
spec_base=$(basename -- "$spec")

# Toolchain. COPR's SRPM step starts from a bare chroot. rpm-build gives
# rpmbuild; rpmdevtools gives spectool. No BuildRequires are needed here:
# `rpmbuild -bs` packages the sources, it does not compile. cargo is installed on
# demand below only for Rust (vendored) specs. keepcache=1 keeps the downloaded
# tooling RPMs in /var/cache/libdnf5 so repeat runs reuse them.
dnf install -y --setopt=keepcache=1 --setopt=install_weak_deps=False \
  rpm-build rpmdevtools >/dev/null

# Use the AMBIENT %_topdir, not a hardcoded ~/rpmbuild: COPR's source build runs
# in mock, which redefines %_topdir (e.g. /builddir/build). build-local.sh can
# assume ~/rpmbuild because a plain container leaves %_topdir at $HOME/rpmbuild;
# here we must honor whatever the chroot set. Create the tree at that location.
TOPDIR=$(rpm --eval %_topdir)
mkdir -p "$TOPDIR"/{SPECS,SOURCES,SRPMS,BUILD}
cp "$spec_dir/$spec_base" "$TOPDIR/SPECS/"

# Stage local (non-URL) Source siblings — spectool -g only fetches URL sources,
# so plain filenames (e.g. hyprland's macros.hyprland) are copied in by hand.
grep -iE '^Source[0-9]*:' "$spec_dir/$spec_base" | sed -E 's/^[^:]+:[[:space:]]*//' | while read -r src; do
  case "$src" in
    *://*) : ;;                                   # URL — spectool fetches it
    *) [[ -f "$spec_dir/$src" ]] && cp "$spec_dir/$src" "$TOPDIR/SOURCES/" ;;
  esac
done || true   # never trip set -e on a URL-only spec

# Fetch every URL SourceN declared in the spec into SOURCES/.
spectool -g -R "$TOPDIR/SPECS/$spec_base"

# INTEGRITY GATE: verify each fetched remote source against its committed sha256
# pin BEFORE packaging, so an upstream source that changed underneath the pin
# aborts here rather than silently flowing into the SRPM. Pins live in
# <spec>.sources ("<hash>  <fetched-basename>", `sha256sum -c` format). We do not
# pin the locally generated *-vendor.tar.* (cargo's per-crate checksums anchor it
# to the pinned Source0's Cargo.lock). See OMEDORA-SOURCES.md.
sources_pin="$spec_dir/$spec_base.sources"
if [[ -f "$sources_pin" ]]; then
  echo "==> Verifying fetched sources against $(basename "$sources_pin")"
  while read -r want_hash want_file; do
    [[ -z "$want_hash" || "$want_hash" == \#* ]] && continue
    got_path="$TOPDIR/SOURCES/$want_file"
    if [[ ! -f "$got_path" ]]; then
      echo "SOURCE PIN ERROR: pinned source not fetched: $want_file" >&2
      echo "  (declared in $(basename "$sources_pin") but missing from SOURCES/)" >&2
      exit 1
    fi
    got_hash=$(sha256sum "$got_path" | awk '{print $1}')
    if [[ "$got_hash" != "$want_hash" ]]; then
      echo "SOURCE PIN MISMATCH: $want_file" >&2
      echo "  expected sha256: $want_hash" >&2
      echo "  got sha256:      $got_hash" >&2
      echo "  Upstream changed since pinned; verify + re-pin (OMEDORA-SOURCES.md). Aborting." >&2
      exit 1
    fi
    echo "    ok: $want_file"
  done < "$sources_pin"
else
  echo "==> No sources pin file ($(basename "$sources_pin")); skipping source verification" >&2
fi

# Regenerate the Rust cargo-vendor tarball for any *-vendor.tar.* SourceN, so
# COPR's offline build phase has the crate set. Deterministic from the pinned
# Source0 tarball's committed Cargo.lock (crates.io content is immutable). cargo
# isn't in the bare SRPM chroot, so install it on demand. Generic + guarded: act
# only for a *-vendor.tar.* SourceN not already in SOURCES/; non-Rust specs are
# untouched.
grep -iE '^Source[0-9]*:' "$spec_dir/$spec_base" | sed -E 's/^[^:]+:[[:space:]]*//' | while read -r src; do
  case "$src" in
    *-vendor.tar.*)
      command -v cargo >/dev/null 2>&1 || \
        dnf install -y --setopt=keepcache=1 --setopt=install_weak_deps=False cargo >/dev/null
      read -r nv_name nv_version < <(rpmspec -q --srpm --qf '%{name} %{version}\n' "$spec_dir/$spec_base")
      vendor_tar="$TOPDIR/SOURCES/${nv_name}-${nv_version}-vendor.tar.zst"
      [[ -f "$vendor_tar" ]] && continue   # already present
      echo "==> Generating vendor tarball: $(basename "$vendor_tar")"
      work=$(mktemp -d)
      # Source0 lives in SOURCES/ under its URL basename (what spectool fetched).
      src0=$(rpmspec -P "$spec_dir/$spec_base" | sed -nE 's/^Source0:[[:space:]]*//p' | head -n1)
      src0_file="$TOPDIR/SOURCES/$(basename "$src0")"
      tar -C "$work" -xf "$src0_file"
      crate_top=$(find "$work" -mindepth 1 -maxdepth 1 -type d | head -n1)
      # No --locked: swayosd's lock pins its own root version below its Cargo.toml,
      # which --locked rejects; the lock still governs the dependency set.
      ( cd "$crate_top" && cargo vendor vendor >/dev/null )
      # Reproducible tar (normalized metadata) so re-runs are byte-identical.
      tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
        -C "$crate_top" -caf "$vendor_tar" vendor
      rm -rf "$work"
      ;;
  esac
done

# Build the source RPM and hand it to COPR.
mkdir -p "$outdir"
rpmbuild -bs "$TOPDIR/SPECS/$spec_base"
cp -v "$TOPDIR"/SRPMS/*.src.rpm "$outdir"/
