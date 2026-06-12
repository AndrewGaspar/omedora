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

# SELF-SOURCE MODE: a spec that declares `Source0: omedora-self.tar.gz` (a
# marker filename, not a URL) is sourced from THIS repo checkout — the
# omedora/omedora-settings specs package the repo itself. Generate the tarball
# here on the host with git archive (the build container only sees /copr); the
# in-container "local Source siblings" copy below then stages it into SOURCES/
# like any other bare-filename Source. The sha256-pin INTEGRITY GATE does not
# apply to it: the tarball is produced from the local tree, not fetched from a
# remote (these specs ship no .sources pin file). Remote-source specs keep the
# pin verification untouched. NOTE: archives HEAD — uncommitted payload changes
# are not picked up (the spec itself IS, since it's staged straight from /copr).
SELF_STAMP=""
if grep -qE '^Source0:[[:space:]]*omedora-self\.tar\.gz[[:space:]]*$' "$COPR_DIR/$spec"; then
  self_version=$(grep -E '^Version:' "$COPR_DIR/$spec" | head -n1 | awk '{print $2}')
  echo "==> Self-source spec: git archive HEAD -> omedora-self.tar.gz (prefix omedora-$self_version/)"
  git -C "$REPO" archive --format=tar.gz --prefix="omedora-${self_version}/" \
    -o "$COPR_DIR/omedora-self.tar.gz" HEAD
  # Release stamp (commit date + sha): keeps every payload rebuild a higher
  # NEVRA. Mirrors .copr/srpm.sh — keep the two in sync.
  SELF_STAMP="$(git -C "$REPO" log -1 --format=%cd --date=format:%Y%m%d%H%M HEAD)git$(git -C "$REPO" rev-parse --short=7 HEAD)"
fi

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
    # Self-source Release stamping (see host-side SELF_STAMP above).
    if [[ -n "'"$SELF_STAMP"'" ]]; then
      sed -i -E "s/^(Release:[[:space:]]*[0-9]+)(%\{\?dist\})/\1.'"$SELF_STAMP"'\2/" ~/rpmbuild/SPECS/'"$spec"'
    fi

    # Stage any LOCAL (non-URL) Source files the spec references — e.g.
    # hyprland.spec ships macros.hyprland as a sibling Source. spectool -g only
    # fetches URL sources, so these plain filenames must be copied in by hand
    # (a COPR uploads them alongside the spec). We match SourceN: lines whose
    # value has no "://" and copy the matching sibling file from /copr.
    grep -iE "^Source[0-9]*:" /copr/'"$spec"' | sed -E "s/^[^:]+:[[:space:]]*//" | while read -r src; do
      case "$src" in
        *://*) : ;;                                  # URL — spectool fetches it
        *) if [[ -f "/copr/$src" ]]; then cp "/copr/$src" ~/rpmbuild/SOURCES/; fi ;;
      esac
    done || true   # the loop must never trip set -e (a URL-only spec is normal)

    # Install the spec'\''s BuildRequires (e.g. systemd-rpm-macros for
    # %%{_userunitdir}, or just-built sibling -devel packages). A COPR does this
    # step for you.
    dnf builddep -y --setopt=keepcache=1 ~/rpmbuild/SPECS/'"$spec"' >/dev/null

    # Download every Source0/SourceN URL declared in the spec into SOURCES/.
    spectool -g -R ~/rpmbuild/SPECS/'"$spec"'

    # INTEGRITY GATE: verify each just-fetched remote source against its
    # committed sha256 pin BEFORE we build, so an upstream tarball/binary that
    # changed underneath us aborts the build here (with a clear message) rather
    # than silently flowing into the RPM. Pins live in /copr/<spec>.sources, one
    # per remote SourceN, in `sha256sum -c` format: "<hash>  <fetched-basename>".
    # The basename is exactly what spectool -g wrote into SOURCES/ (the part
    # after #/ for renamed sources, else the URL basename). We do NOT pin the
    # locally generated *-vendor.tar.* (built below, not fetched) — cargo'\''s
    # per-crate checksums already anchor it to this pinned Source0'\''s Cargo.lock.
    # A spec with no .sources file is skipped (safety net; all remote-source
    # specs ship one). See OMEDORA-SOURCES.md for the format + re-pin workflow.
    sources_pin="/copr/'"$spec"'.sources"
    if [[ -f "$sources_pin" ]]; then
      echo "==> Verifying fetched sources against $(basename "$sources_pin")"
      while read -r want_hash want_file; do
        [[ -z "$want_hash" || "$want_hash" == \#* ]] && continue
        got_path="$HOME/rpmbuild/SOURCES/$want_file"
        if [[ ! -f "$got_path" ]]; then
          echo "SOURCE PIN ERROR: pinned source not fetched: $want_file" >&2
          echo "  (declared in $(basename "$sources_pin") but missing from SOURCES/)" >&2
          exit 1
        fi
        got_hash=$(sha256sum "$got_path" | awk "{print \$1}")
        if [[ "$got_hash" != "$want_hash" ]]; then
          echo "SOURCE PIN MISMATCH: $want_file" >&2
          echo "  expected sha256: $want_hash" >&2
          echo "  got sha256:      $got_hash" >&2
          echo "  The upstream source changed since it was pinned. If this is a" >&2
          echo "  legitimate upstream change, verify the new content and re-pin" >&2
          echo "  $(basename "$sources_pin") (see OMEDORA-SOURCES.md). Aborting." >&2
          exit 1
        fi
        echo "    ok: $want_file"
      done < "$sources_pin"
    else
      echo "==> No sources pin file ($(basename "$sources_pin")); skipping source verification" >&2
    fi

    # GENERATE the Rust vendor tarball at SRPM-gen time (was: committed in Git
    # LFS). The from-source Rust specs (swayosd/satty/bluetui) declare a local
    # SourceN named <name>-<version>-vendor.tar.zst (a bare filename, not a URL,
    # so spectool can'\''t fetch it). Rather than commit a ~64 MB tarball, we
    # regenerate it deterministically from the upstream release tarball'\''s
    # committed Cargo.lock: Source0 is a version-pinned GitHub tag tarball, the
    # lock pins every transitive dep, and crates.io (name,version) content is
    # immutable, so `cargo vendor` produces a bit-identical crate set every time.
    # The rpmbuild (build) phase stays fully offline against this dir; only this
    # source-prep step needs network (this container has it). A future COPR
    # .copr/Makefile (#60) must run the same `cargo vendor` in its SRPM step so
    # COPR'\''s offline build phase has the vendor dir.
    #
    # Generic + guarded: act only for a *-vendor.tar.* SourceN that is NOT
    # already in SOURCES/, so non-Rust specs are untouched.
    grep -iE "^Source[0-9]*:" /copr/'"$spec"' | sed -E "s/^[^:]+:[[:space:]]*//" | while read -r src; do
      case "$src" in
        *-vendor.tar.*)
          # Resolve %{name}/%{version} macros in the SourceN value.
          read -r nv_name nv_version < <(rpmspec -q --srpm --qf "%{name} %{version}\n" /copr/'"$spec"')
          vendor_tar="$HOME/rpmbuild/SOURCES/${nv_name}-${nv_version}-vendor.tar.zst"
          [[ -f "$vendor_tar" ]] && continue   # already present — nothing to do
          echo "==> Generating vendor tarball: $(basename "$vendor_tar")"
          # Extract the already-fetched Source0 upstream tarball to a temp dir
          # and cd into its single top-level directory.
          work=$(mktemp -d)
          # Resolve Source0 from the macro-expanded spec; SOURCES/ holds it under
          # its URL basename (what spectool -g fetched it as).
          src0=$(rpmspec -P /copr/'"$spec"' | sed -nE "s/^Source0:[[:space:]]*//p" | head -n1)
          src0_file="$HOME/rpmbuild/SOURCES/$(basename "$src0")"
          tar -C "$work" -xf "$src0_file"
          topdir=$(find "$work" -mindepth 1 -maxdepth 1 -type d | head -n1)
          # `cargo vendor` reads the committed Cargo.lock. We do NOT pass
          # --locked: swayosd'\''s lock pins its own root version (0.3.0) below its
          # Cargo.toml (0.3.1), which --locked rejects; the lock still governs
          # the dependency set (the self-version rewrite is a dep-set no-op).
          ( cd "$topdir" && cargo vendor vendor >/dev/null )
          # Tar reproducibly (normalized metadata) so re-runs are byte-identical.
          tar --sort=name --mtime="@0" --owner=0 --group=0 --numeric-owner \
            -C "$topdir" -caf "$vendor_tar" vendor
          rm -rf "$work"
          ;;
      esac
    done

    # -ba = build Both the binary RPM and the source RPM.
    rpmbuild -ba ~/rpmbuild/SPECS/'"$spec"'

    # Hand the artifacts back to the host via the bind mount.
    cp -v ~/rpmbuild/RPMS/*/*.rpm /copr/output/ 2>/dev/null || true
    cp -v ~/rpmbuild/SRPMS/*.rpm  /copr/output/ 2>/dev/null || true
  '

echo ""
echo "Done. Artifacts in packaging/copr/output/:"
ls -1 "$COPR_DIR/output/" | sed 's/^/  /'
