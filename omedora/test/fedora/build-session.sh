#!/bin/bash
#
# Build the L4-nested Omedora v4 session image by running the v4 bootstrap
# (omedora/install-4.sh's steps) inside a LIVE systemd+logind session, then
# committing the result. This is the "boot Fedora, log in, run the installer"
# path — the most faithful way to reproduce a bare-metal Fedora omedora
# install in a container.
#
# Fedora release: OMEDORA_FEDORA_RELEASE (default 44) selects the base Fedora
# image and the image lineage — omedora-test:fedora<N>-session-4* — plus a
# per-release dnf cache volume and local repo dir (see lib/release.sh). The
# names below are the Fedora 44 defaults.
#
# Why not a Dockerfile RUN? A `podman build` step has no PID-1 systemd, so
# `systemctl --user`, the session D-Bus, and `flatpak install --user` don't
# work. Here we boot the base image (omedora-session/Dockerfile.base) with
# `podman run --systemd=always`, wait for systemd to settle, run the bootstrap
# as the omedora user through `machinectl shell` (a real logind session), and
# `podman commit` the finished container.
#
# --- Two-stage build (incremental-rebuild speedup) ---------------------------
# The install wall-time is dominated by the packaging stage (COPR enable + dnf
# install of omedora + the whole mapped base set + Flatpaks), while the
# system/adopt/finalize stages you actually iterate on are seconds. So the
# bootstrap runs in two committed layers:
#
#   1. PACKAGES image (omedora-test:fedora44-session-4-pkgs) — plan + repos +
#      package payload. Built once; rebuild only when packages change.
#   2. SESSION  image (omedora-test:fedora44-session-4)      — the packages
#      image with system/adopt/finalize/first-run applied. The runnable session.
#
# The phases source the SAME omedora/install/*.sh steps in the SAME order as
# install-4.sh (see omedora-session/staged-install-4.sh) — full fidelity, no
# install-4.sh patch.
#
# --- The checkout is copied in per phase, never baked into an image ----------
# The bootstrap runs from a checkout at ~omedora/.local/share/omarchy. Right
# before EVERY phase (packages, config, --fast) this script replaces that tree
# in the build container with the current checkout (tracked + untracked,
# non-ignored files, uncommitted edits included; see lib/checkout.sh), so a
# phase always runs this checkout's install scripts, whichever older pkgs
# image it boots. The base image (Dockerfile.base) holds no tree at all. The
# committed images carry the copied tree and an `omedora.tree` label naming
# it; run-session.sh and headless/run-tests.sh warn when that label is not
# the checkout they run from.
#
# The pkgs image is reused only while its inputs are unchanged: it carries an
# `omedora.pkgs-key` label hashing the base image id, the package source (COPR,
# or the local repo's repomd.xml) and the files the packages phase reads
# (PKGS_INPUTS below). A mismatch rebuilds it; --fast warns and reuses it.
#
# Package source: by default the install resolves omedora's packages from the
# LIVE omedora COPR (bin/omedora-copr → agaspar/omedora-4 on this line) — the
# real from-COPR install path a user gets. --local-repo instead overlays the
# locally-built RPM repo (omedora/packaging/copr/repo[-f<N>], built by
# build-repo.sh from THIS checkout) on the COPR: lib/local-repo-overlay.sh
# writes /etc/yum.repos.d/omedora-local.repo at priority=1 and enables the COPR
# for everything the local repo does not hold. The bootstrap's repos.sh then
# skips its own COPR enable, and every package in the local repo wins — the way
# to test unpublished payload (RPM) changes on this branch. Building the two
# core specs is enough; see lib/local-repo.sh.
#
# Usage:
#   omedora/test/fedora/build-session.sh             # build pkgs image if needed, then config → session
#   omedora/test/fedora/build-session.sh --rebuild   # force clean: base + pkgs + session
#   omedora/test/fedora/build-session.sh --fast      # config-only: reuse the existing pkgs image,
#                                            #   re-run ONLY system/adopt/finalize/first-run → session
#                                            #   (alias: --config-only). Seconds, not ~15 min.
#   omedora/test/fedora/build-session.sh --packages-only   # build/refresh just the pkgs image, no session
#   omedora/test/fedora/build-session.sh --local-repo  # overlay the locally-built RPM repo on the
#                                            #   live COPR (first builds the core omedora +
#                                            #   omedora-settings RPMs from HEAD when the repo
#                                            #   lacks them; --rebuild-repo forces). Produces a
#                                            #   separate "-local" image lineage.
#   omedora/test/fedora/build-session.sh --rebuild-repo  # with --local-repo: force-rebuild the core RPMs
#   omedora/test/fedora/build-session.sh --workstation  # build on a Fedora Workstation base
#                                            #   (standard base + workstation-product-environment);
#                                            #   separate omedora-test:fedora44-session-4-workstation*
#                                            #   lineage. Combine with --fast/--rebuild/etc. as usual.
#
# The dnf package cache persists across builds via the OMEDORA_DNF_CACHE_VOL
# volume, mounted at the dnf5 cache path (/var/cache/libdnf5) — so a cold/
# --rebuild packages phase re-uses already-downloaded RPMs.
#
# Products:
#   omedora-test:fedora44-session-4-sysbase  (Fedora + systemd + deps, no tree; CMD /sbin/init)
#   omedora-test:fedora44-session-4-pkgs     (the above + checkout, after plan+repos+packages)
#   omedora-test:fedora44-session-4          (the above, after system/adopt/finalize; ready to run)
# The "-sysbase" names replace the "-base" ones, whose images baked a checkout in.
#
# Full install log is also copied out to /tmp/omedora-session-build.log.

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
. "$REPO/omedora/test/fedora/lib/release.sh"
. "$REPO/omedora/test/fedora/lib/checkout.sh"
. "$REPO/omedora/test/fedora/lib/local-repo.sh"
# Image/container names are resolved AFTER arg parsing so --workstation /
# --local-repo can apply their infixes (see the resolution block below).
# DNF_CACHE_VOL is shared by every variant on purpose — they pull mostly the
# same RPMs, so they warm each other's cache. Releases get separate volumes
# (omedora-dnf-cache on 44, omedora-dnf-cache-f<N> otherwise) so one release's
# metadata and RPMs never shadow another's.
DNF_CACHE_VOL="${OMEDORA_DNF_CACHE_VOL:-omedora-dnf-cache$OMEDORA_RELEASE_SUFFIX}"
# Fedora 44+ ships dnf5, whose package cache lives under /var/cache/libdnf5 (NOT
# the dnf4 path /var/cache/dnf). Mount the persistent volume at the dnf5 path
# so keepcache=True actually persists the RPMs across builds.
DNF_CACHE_DIR="/var/cache/libdnf5"
HOST_LOG="${OMEDORA_SYSTEMD_BUILD_LOG:-/tmp/omedora-session-build$OMEDORA_RELEASE_SUFFIX.log}"
DOCKERFILE_BASE="$REPO/omedora/test/fedora/omedora-session/Dockerfile.base"
DOCKERFILE_WORKSTATION="$REPO/omedora/test/fedora/omedora-session/Dockerfile.workstation"
# The standard base image name is fixed (it's what the Workstation tier FROMs);
# --workstation does NOT rename it.
STD_BASE_IMAGE="$OMEDORA_TEST_TAG-session-4-sysbase"
SESSION_DIR="$REPO/omedora/test/fedora/omedora-session"
# Where the bootstrap's checkout lives in the image (OMEDORA_REPO_ROOT).
TREE_IN_IMAGE=/home/omedora/.local/share/omarchy
STAGED_IN_IMAGE=$TREE_IN_IMAGE/omedora/test/fedora/omedora-session/staged-install-4.sh
# Every file the packages phase (plan + snapshot + repos + packages) reads to
# decide what it installs. A change to any of them rebuilds the pkgs image;
# config-phase files (system/adopt/finalize/first-run, install/, config/) do
# not, because the config phase re-runs from the fresh checkout every build.
PKGS_INPUTS=(
  omedora/install/plan.sh omedora/install/release.sh omedora/install/snapshot.sh
  omedora/install/repos.sh omedora/install/packages.sh
  omedora/install/fedora-baseline.packages install/omarchy-base.packages
  install/packages bin/fedora bin/omedora-copr bin/omedora-replace-foreign
  bin/omedora-snapshot version omedora/version
  omedora/test/fedora/omedora-session/staged-install-4.sh
  omedora/test/fedora/lib/local-repo-overlay.sh
)
# SELinux-enforcing hosts (default Fedora): the build container runs systemd.
# Confined (container_t), systemd's sandboxed services cannot set up their /proc + cgroupfs mount namespaces (AVC mounton
# proc_t/cgroup_t) — logind crashloops, user@1000 never starts and the phase
# dies with "Permission denied". This is test scaffolding, not the product:
# run the build container unconfined. No-op where SELinux is off.
SELINUX_OPT=(--security-opt label=disable)

rebuild=false
rebuild_repo=false
fast=false
packages_only=false
workstation=false
# --local-repo / OMEDORA_LOCAL_REPO=1: overlay the local RPM repo on the COPR
# (lib/local-repo-overlay.sh); repos.sh then skips its own COPR enable.
local_repo=false
[[ "${OMEDORA_LOCAL_REPO:-}" == "1" ]] && local_repo=true
for arg in "$@"; do
  case "$arg" in
    --rebuild)                 rebuild=true ;;
    --rebuild-repo)            rebuild_repo=true ;;
    --fast|--config-only)      fast=true ;;
    --packages-only)           packages_only=true ;;
    --workstation)             workstation=true ;;
    --local-repo)              local_repo=true ;;
    --help|-h) grep '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

if $fast && $rebuild; then
  echo "--fast and --rebuild are mutually exclusive (--fast reuses the pkgs image)" >&2
  exit 2
fi

# --- resolve image/container names (after parsing, so the flags apply) --------
# --workstation builds/runs on a SECOND-tier base = the standard base + the Fedora
# Workstation package set (Dockerfile.workstation), under its own "-workstation"
# lineage. --local-repo gets a "-local" infix on the pkgs/session images (the
# packages come from the local repo, not the live COPR) but shares the
# repo-agnostic base. Explicit OMEDORA_SYSTEMD_* env overrides still win.
variant=""; $workstation && variant="-workstation"
local_variant=""; $local_repo && local_variant="-local"
BASE_IMAGE="${OMEDORA_SYSTEMD_BASE_IMAGE:-$OMEDORA_TEST_TAG-session-4${variant}-sysbase}"
SESSION_IMAGE="${OMEDORA_SYSTEMD_SESSION_IMAGE:-$OMEDORA_TEST_TAG-session-4${variant}${local_variant}}"
# Intermediate "packages installed" image; derived from SESSION_IMAGE's name so a
# custom OMEDORA_SYSTEMD_SESSION_IMAGE gets a matching pkgs image, but can be
# overridden directly.
PKGS_IMAGE="${OMEDORA_SYSTEMD_PKGS_IMAGE:-${SESSION_IMAGE%%:*}:${SESSION_IMAGE##*:}-pkgs}"
BUILD_CTR="${OMEDORA_BUILD_CTR:-omedora-session-4$OMEDORA_RELEASE_SUFFIX${variant}${local_variant}-build}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# wait_for_systemd <container> — block until systemd settles + the omedora user
# manager is active. Shared by every boot below.
wait_for_systemd() {
  local ctr="$1" i state
  log "Waiting for systemd to reach running/degraded"
  for i in $(seq 1 60); do
    state=$(podman exec "$ctr" systemctl is-system-running 2>/dev/null || true)
    case "$state" in
      running|degraded) echo "  systemd: $state (after ${i}s)"; break ;;
    esac
    [[ $i -eq 60 ]] && { echo "systemd never settled (last: ${state:-none})"; podman logs "$ctr" | tail -30; exit 1; }
    sleep 1
  done
  for i in $(seq 1 30); do
    [[ "$(podman exec "$ctr" systemctl is-active user@1000.service 2>/dev/null || true)" == "active" ]] && break
    [[ $i -eq 30 ]] && { echo "user@1000.service never became active"; exit 1; }
    sleep 1
  done
  echo "  user@1000.service: active"
}

# sync_tree <container> — replace the container's checkout with this one, so
# the next phase runs the current install scripts (see the header).
sync_tree() {
  local ctr="$1"
  log "Copying this checkout ($TREE_ID) into $ctr:$TREE_IN_IMAGE"
  podman exec "$ctr" rm -rf "$TREE_IN_IMAGE"
  podman exec "$ctr" install -d -o omedora -g omedora "$TREE_IN_IMAGE"
  checkout_stream | podman exec -i "$ctr" tar -C "$TREE_IN_IMAGE" --no-same-owner -xf -
  podman exec "$ctr" chown -R omedora:omedora "$TREE_IN_IMAGE"
}

# inject_local_repo <container> — copy the createrepo'd RPMs in and overlay
# them on the COPR (lib/local-repo-overlay.sh, piped in from this checkout).
# The .repo file's presence makes the bootstrap's repos.sh skip its COPR enable.
inject_local_repo() {
  local ctr="$1"
  log "Overlaying the local omedora RPM repo on the COPR (repos.sh will skip its COPR enable)"
  podman exec "$ctr" rm -rf /opt/omedora-repo
  podman cp "$OMEDORA_LOCAL_REPO_DIR" "$ctr:/opt/omedora-repo"
  podman exec -i -e "OMEDORA_LOCAL_REPO_ONLY=${OMEDORA_LOCAL_REPO_ONLY:-}" "$ctr" \
    bash -s -- /opt/omedora-repo "$(OMARCHY_PATH='' "$REPO/bin/omedora-copr")" \
    <"$REPO/omedora/test/fedora/lib/local-repo-overlay.sh"
}

# pkgs_key — hash of everything the pkgs image depends on (see the header).
pkgs_key() {
  local f
  {
    printf 'base %s\n' "$(podman image inspect -f '{{.Id}}' "$BASE_IMAGE")"
    if $local_repo; then
      printf 'local-repo %s only=%s\n' \
        "$(sha256sum <"$OMEDORA_LOCAL_REPO_DIR/repodata/repomd.xml" | cut -d' ' -f1)" \
        "${OMEDORA_LOCAL_REPO_ONLY:-}"
    else
      printf 'copr\n'
    fi
    git -C "$REPO" ls-files -z --cached --others --exclude-standard -- "${PKGS_INPUTS[@]}" |
      sort -z | while IFS= read -r -d '' f; do
        [[ -f $REPO/$f ]] && printf '%s %s\n' "$(sha256sum <"$REPO/$f" | cut -d' ' -f1)" "$f"
      done
  } | sha256sum | cut -c1-16
}

# image_label <image> <label> — the label's value, "" when unset.
image_label() {
  podman image inspect -f "{{index .Labels \"$2\"}}" "$1" 2>/dev/null | sed 's/^<no value>$//'
}

# run_phase <container> <packages|config|all> <human-label> — run a staged
# install phase as omedora in the logind session; read back the real exit code
# (machinectl shell swallows it), copy the clean log out, fail loudly on error.
run_phase() {
  local ctr="$1" phase="$2" label="$3"
  log "Running install phase '$phase' as omedora in a logind session ($label)"
  podman exec "$ctr" rm -f /tmp/install.exit
  podman exec "$ctr" machinectl shell \
    omedora@.host /usr/bin/bash -lc \
    "bash '$STAGED_IN_IMAGE' '$phase'" \
    || true

  local install_exit
  install_exit=$(podman exec "$ctr" cat /tmp/install.exit 2>/dev/null || echo "missing")
  podman exec "$ctr" cat /var/log/omarchy-install.log >"$HOST_LOG" 2>/dev/null || true

  if [[ "$install_exit" != "0" ]]; then
    log "install phase '$phase' FAILED (exit $install_exit)"
    echo "--- last 200 lines of install log ($HOST_LOG) ---"
    tail -200 "$HOST_LOG" | sed -E 's/\x1b\[[0-9;?]*[mGKsuHJh]//g; s/\r/\n/g' || true
    echo ""
    echo "Build container left running as '$ctr' for inspection:"
    echo "  podman exec -it $ctr machinectl shell omedora@.host"
    exit "$install_exit" 2>/dev/null || exit 1
  fi
  log "install phase '$phase' succeeded"
}

# commit_systemd <container> <image> [label=value...] — commit preserving the
# systemd CMD so the image still boots /sbin/init, labelled with the checkout
# it was built from plus any extra labels.
commit_systemd() {
  local ctr="$1" image="$2" label changes=()
  shift 2
  for label in "$CHECKOUT_TREE_LABEL=$TREE_ID" "$@"; do
    changes+=(--change "LABEL $label")
  done
  log "Committing $ctr -> $image"
  podman commit \
    --change 'CMD ["/sbin/init"]' \
    --change 'STOPSIGNAL SIGRTMIN+3' \
    "${changes[@]}" \
    "$ctr" "$image" >/dev/null
}

TREE_ID=$(checkout_tree_id)

# --- 0. (--local-repo only) build the local core RPMs --------------------------
# The core omedora + omedora-settings RPMs package `git archive HEAD`, so they
# are rebuilt (noarch, ~2 min) whenever the local repo lacks HEAD's build.
# Other specs are never built here (the C++ stack takes hours and the COPR
# serves it); build one yourself with build-repo.sh <name>.spec to overlay it.
if $local_repo && ! $fast; then
  if $rebuild_repo; then
    log "Rebuilding the local core RPMs from HEAD (--rebuild-repo)"
    local_repo_build_core --force
  elif stale_reason=$(local_repo_core_status); then
    log "Local core RPMs are HEAD's build ($(local_repo_head_tag)); --rebuild-repo to force"
  else
    log "Building the local core RPMs from HEAD ($stale_reason)"
    local_repo_build_core
  fi
  if ! stale_reason=$(local_repo_core_status); then
    echo "The local repo still does not hold HEAD's core RPMs: $stale_reason" >&2
    exit 1
  fi
  local_repo_warn_dirty
elif ! $local_repo; then
  # OMARCHY_PATH is cleared so a dev host's own omarchy install can't shadow
  # this checkout's version file (omedora-copr prefers $OMARCHY_PATH/version).
  log "Live-COPR mode (default): the bootstrap's repos.sh will enable $(OMARCHY_PATH= "$REPO/bin/omedora-copr" 2>/dev/null || echo 'the omedora COPR') and pull from it (--local-repo overlays the locally-built RPM repo on it)"
fi

# =============================================================================
# FAST PATH: config-only. Reuse the existing pkgs image, re-run just the
# system/adopt/finalize/first-run steps, recommit the session image.
# =============================================================================
if $fast; then
  if ! podman image exists "$PKGS_IMAGE"; then
    echo "--fast needs a packages image ($PKGS_IMAGE) but it doesn't exist." >&2
    echo "Run a normal build first (omedora/test/fedora/build-session.sh) to create it." >&2
    exit 1
  fi
  if podman image exists "$BASE_IMAGE" &&
    [[ $(image_label "$PKGS_IMAGE" omedora.pkgs-key) != "$(pkgs_key)" ]]; then
    printf '\033[1;33mwarning:\033[0m the packages-phase inputs changed since %s was built; --fast reuses it anyway (drop --fast to rebuild it).\n' "$PKGS_IMAGE" >&2
  fi
  log "Fast (config-only) build: booting packages image $PKGS_IMAGE"
  podman rm -f "$BUILD_CTR" >/dev/null 2>&1 || true
  podman volume exists "$DNF_CACHE_VOL" >/dev/null 2>&1 || podman volume create "$DNF_CACHE_VOL" >/dev/null
  podman run -d --name "$BUILD_CTR" --systemd=always "${SELINUX_OPT[@]}" \
    -v "$DNF_CACHE_VOL:$DNF_CACHE_DIR" \
    "$PKGS_IMAGE" >/dev/null
  wait_for_systemd "$BUILD_CTR"
  sync_tree "$BUILD_CTR"
  run_phase "$BUILD_CTR" config "config-only"
  commit_systemd "$BUILD_CTR" "$SESSION_IMAGE"
  podman rm -f "$BUILD_CTR" >/dev/null
  log "Done (fast). Session image: $SESSION_IMAGE"
  echo "Launch it with: omedora/test/fedora/run-session.sh"
  exit 0
fi

# =============================================================================
# FULL PATH (default / --rebuild / --packages-only).
# =============================================================================

# --- 1. Build the base image -------------------------------------------------
# Standard build: one base from Dockerfile.base. --workstation build: the SAME
# standard base, then a second tier (Dockerfile.workstation) FROM it that adds the
# Fedora Workstation package set — so the install phases below run on a realistic
# Workstation layering instead of the minimal base.
if $workstation; then
  # The Workstation tier FROMs the standard base, so that must exist first.
  if $rebuild || ! podman image exists "$STD_BASE_IMAGE"; then
    log "Building standard base image $STD_BASE_IMAGE (Workstation tier builds FROM it)"
    podman build -t "$STD_BASE_IMAGE" --build-arg "FEDORA_RELEASE=$OMEDORA_FEDORA_RELEASE" \
      -f "$DOCKERFILE_BASE" "$SESSION_DIR"
  else
    log "Standard base image $STD_BASE_IMAGE already present (use --rebuild to force)"
  fi
  if $rebuild || ! podman image exists "$BASE_IMAGE"; then
    log "Building Workstation base image $BASE_IMAGE (standard base + workstation-product-environment)"
    podman build -t "$BASE_IMAGE" --build-arg "BASE=$STD_BASE_IMAGE" \
      -f "$DOCKERFILE_WORKSTATION" "$SESSION_DIR"
  else
    log "Workstation base image $BASE_IMAGE already present (use --rebuild to force)"
  fi
else
  if $rebuild || ! podman image exists "$BASE_IMAGE"; then
    log "Building base image $BASE_IMAGE"
    podman build -t "$BASE_IMAGE" --build-arg "FEDORA_RELEASE=$OMEDORA_FEDORA_RELEASE" \
      -f "$DOCKERFILE_BASE" "$SESSION_DIR"
  else
    log "Base image $BASE_IMAGE already present (use --rebuild to force)"
  fi
fi

# Decide whether to rebuild the PACKAGES image. It's the expensive layer; reuse
# it when it exists, its inputs are unchanged (the pkgs-key label) and we're
# not doing a clean --rebuild. (Editing a setup/adopt/finalize script and
# re-running the default build skips straight to the config phase below,
# against the existing pkgs image — same as --fast.)
PKGS_KEY=$(pkgs_key)
build_packages=true
if ! $rebuild && podman image exists "$PKGS_IMAGE"; then
  if [[ $(image_label "$PKGS_IMAGE" omedora.pkgs-key) == "$PKGS_KEY" ]]; then
    build_packages=false
    log "Packages image $PKGS_IMAGE is current (use --rebuild to force a clean repackage)"
  else
    log "Packages image $PKGS_IMAGE is out of date (base image, package source or packages-phase files changed); rebuilding it"
  fi
fi

# --- 2. PACKAGES phase: boot base, (overlay repo), install packages, commit ---
if $build_packages; then
  log "Booting $BASE_IMAGE under systemd (packages phase)"
  podman rm -f "$BUILD_CTR" >/dev/null 2>&1 || true
  podman volume exists "$DNF_CACHE_VOL" >/dev/null 2>&1 || podman volume create "$DNF_CACHE_VOL" >/dev/null
  # Mount the dnf cache volume so the bootstrap's dnf downloads persist across
  # builds (the base image set keepcache=True so rpms actually stick).
  podman run -d --name "$BUILD_CTR" --systemd=always "${SELINUX_OPT[@]}" \
    -v "$DNF_CACHE_VOL:$DNF_CACHE_DIR" \
    "$BASE_IMAGE" >/dev/null
  wait_for_systemd "$BUILD_CTR"
  sync_tree "$BUILD_CTR"
  if $local_repo; then
    inject_local_repo "$BUILD_CTR"
  else
    log "Live-COPR mode: no local repo injected — repos.sh enables the live COPR"
  fi
  run_phase "$BUILD_CTR" packages "this takes a while"
  commit_systemd "$BUILD_CTR" "$PKGS_IMAGE" "omedora.pkgs-key=$PKGS_KEY"
  podman rm -f "$BUILD_CTR" >/dev/null
fi

if $packages_only; then
  log "Done (packages-only). Packages image: $PKGS_IMAGE"
  echo "Apply config + build the session image with: omedora/test/fedora/build-session.sh --fast"
  exit 0
fi

# --- 3. CONFIG phase: boot the packages image, apply config, commit session ---
log "Booting $PKGS_IMAGE under systemd (config phase)"
podman rm -f "$BUILD_CTR" >/dev/null 2>&1 || true
podman volume exists "$DNF_CACHE_VOL" >/dev/null 2>&1 || podman volume create "$DNF_CACHE_VOL" >/dev/null
podman run -d --name "$BUILD_CTR" --systemd=always "${SELINUX_OPT[@]}" \
  -v "$DNF_CACHE_VOL:$DNF_CACHE_DIR" \
  "$PKGS_IMAGE" >/dev/null
wait_for_systemd "$BUILD_CTR"
sync_tree "$BUILD_CTR"
run_phase "$BUILD_CTR" config "config stages"
commit_systemd "$BUILD_CTR" "$SESSION_IMAGE"
podman rm -f "$BUILD_CTR" >/dev/null

log "Done. Session image: $SESSION_IMAGE"
echo "Launch it with: omedora/test/fedora/run-session.sh"
echo "Iterate on setup/adopt/finalize fast with: omedora/test/fedora/build-session.sh --fast"
