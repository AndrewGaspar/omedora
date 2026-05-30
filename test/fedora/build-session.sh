#!/bin/bash
#
# Build the L4-nested Omedora session image by running install.sh inside a
# LIVE systemd+logind session, then committing the result. This is the
# "boot Fedora, log in, run the installer" path — the most faithful way to
# reproduce a bare-metal Fedora 44 omedora install in a container.
#
# Why not a Dockerfile RUN? A `podman build` step has no PID-1 systemd, so
# `systemctl --user`, the session D-Bus, and `flatpak install --user` don't
# work — exactly the gap the old shim stack papered over. Here we boot the
# base image (test/fedora/omedora-session/Dockerfile.base) with
# `podman run --systemd=always`, wait for systemd to settle, run the install
# as the omedora user through `machinectl shell` (a real logind session), and
# `podman commit` the finished container.
#
# --- Two-stage build (incremental-rebuild speedup) ---------------------------
# Profiling showed the install wall-time is dominated by the packaging stage
# (base.sh = `dnf install` of the whole package set): ~14 min cold (full network
# download) and a few minutes even warm, while the config stages you actually
# iterate on are ~10 s combined (measured: a --fast config rebuild is ~9-16 s
# end-to-end including boot + commit). To stop paying the package cost every time
# you tweak a config script, the install runs in two committed layers:
#
#   1. PACKAGES image (omedora-test:fedora44-session-pkgs) — preflight +
#      packaging stages. Built once; only needs rebuilding when packages change.
#   2. SESSION  image (omedora-test:fedora44-session)      — the packages image
#      with the config stages applied on top. This is the runnable session.
#
# The phases are sourced from the SAME real install all.sh files in the SAME
# order as install.sh (see omedora-session/staged-install.sh) — full fidelity,
# no install.sh patch.
#
# Usage:
#   test/fedora/build-session.sh             # build pkgs image if needed, then config → session
#   test/fedora/build-session.sh --rebuild   # force clean: base + pkgs + session (rebuilds the
#                                            #   local RPM repo only if a spec changed; see below)
#   test/fedora/build-session.sh --rebuild-repo  # also force-rebuild the local RPM repo (~3-4 min)
#   test/fedora/build-session.sh --fast      # config-only: reuse the existing pkgs image,
#                                            #   re-run ONLY the config stages → session
#                                            #   (alias: --config-only). ~10 s + boot, not ~14 min.
#   test/fedora/build-session.sh --packages-only   # build/refresh just the pkgs image, no session
#
# The local omedora RPM repo (walker/elephant/fonts/…) is rebuilt only when a
# *.spec or build-repo.sh/build-local.sh is newer than the built repomd.xml, so
# editing a config script or even a clean --rebuild no longer pays the ~3-4 min
# RPM rebuild for nothing. Force it with --rebuild-repo.
#
# The dnf package cache persists across builds via the OMEDORA_DNF_CACHE_VOL
# volume, mounted at the dnf5 cache path (/var/cache/libdnf5) — so a cold/
# --rebuild packages phase re-uses ~1.9 GB of already-downloaded RPMs instead of
# re-fetching them.
#
# Products:
#   omedora-test:fedora44-session-base   (Fedora + systemd + tree; CMD /sbin/init)
#   omedora-test:fedora44-session-pkgs   (the above, after preflight+packaging)
#   omedora-test:fedora44-session        (the above, after config; ready to run)
#
# Full install log is also copied out to /tmp/omedora-session-build.log.

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
BASE_IMAGE="${OMEDORA_SYSTEMD_BASE_IMAGE:-omedora-test:fedora44-session-base}"
SESSION_IMAGE="${OMEDORA_SYSTEMD_SESSION_IMAGE:-omedora-test:fedora44-session}"
# Intermediate "packages installed" image; derived from SESSION_IMAGE's name so
# a custom OMEDORA_SYSTEMD_SESSION_IMAGE gets a matching pkgs image, but can be
# overridden directly.
PKGS_IMAGE="${OMEDORA_SYSTEMD_PKGS_IMAGE:-${SESSION_IMAGE%%:*}:${SESSION_IMAGE##*:}-pkgs}"
BUILD_CTR="${OMEDORA_BUILD_CTR:-omedora-session-build}"
DNF_CACHE_VOL="${OMEDORA_DNF_CACHE_VOL:-omedora-dnf-cache}"
# Fedora 44 ships dnf5, whose package cache lives under /var/cache/libdnf5 (NOT
# the dnf4 path /var/cache/dnf). Mounting the persistent volume at the dnf4 path
# leaves it empty and re-downloads the whole ~1.9 GB package set on every cold /
# --rebuild packages phase. Mount at the dnf5 path so keepcache=True actually
# persists the RPMs across builds.
DNF_CACHE_DIR="/var/cache/libdnf5"
HOST_LOG="${OMEDORA_SYSTEMD_BUILD_LOG:-/tmp/omedora-session-build.log}"
DOCKERFILE="$REPO/test/fedora/omedora-session/Dockerfile.base"
COPR_DIR="$REPO/omedora/packaging/copr"
SESSION_DIR="$REPO/test/fedora/omedora-session"
STAGED_IN_IMAGE=/home/omedora/.local/share/omarchy/test/fedora/omedora-session/staged-install.sh

rebuild=false
rebuild_repo=false
fast=false
packages_only=false
for arg in "$@"; do
  case "$arg" in
    --rebuild)                 rebuild=true ;;
    --rebuild-repo)            rebuild_repo=true ;;
    --fast|--config-only)      fast=true ;;
    --packages-only)           packages_only=true ;;
    --help|-h) grep '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

if $fast && $rebuild; then
  echo "--fast and --rebuild are mutually exclusive (--fast reuses the pkgs image)" >&2
  exit 2
fi

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

# inject_local_repo <container> — copy the createrepo'd RPMs in + drop a .repo.
# Needed before the packaging phase (config doesn't dnf-install our RPMs).
inject_local_repo() {
  local ctr="$1"
  log "Injecting local omedora RPM repo"
  podman cp "$COPR_DIR/repo" "$ctr:/opt/omedora-repo"
  podman exec "$ctr" bash -c \
    'printf "[omedora-local]\nname=Omedora local packages\nbaseurl=file:///opt/omedora-repo\nenabled=1\ngpgcheck=0\n" >/etc/yum.repos.d/omedora-local.repo'
}

# run_phase <container> <packages|config|all> <human-label> — run a staged
# install phase as omedora in the logind session; read back the real exit code
# (machinectl shell swallows it), copy the clean log out, fail loudly on error.
run_phase() {
  local ctr="$1" phase="$2" label="$3"
  log "Running install phase '$phase' as omedora in a logind session ($label)"
  podman exec "$ctr" rm -f /tmp/install.exit
  podman exec "$ctr" machinectl shell \
    --setenv=OMARCHY_NONINTERACTIVE=1 \
    omedora@.host /usr/bin/bash -lc \
    "bash '$STAGED_IN_IMAGE' '$phase'" \
    || true

  local install_exit
  install_exit=$(podman exec "$ctr" cat /tmp/install.exit 2>/dev/null || echo "missing")
  podman exec "$ctr" cat /var/log/omarchy-install.log >"$HOST_LOG" 2>/dev/null || true

  if [[ "$install_exit" != "0" ]]; then
    log "install phase '$phase' FAILED (exit $install_exit)"
    echo "--- last 60 lifecycle events ---"
    grep -aE '^\[20[0-9]{2}-[0-9]{2}-[0-9]{2} [0-9:]+\] (Starting|Completed|Failed):' "$HOST_LOG" | tail -60 || true
    echo ""
    echo "--- last 200 lines of clean install log ($HOST_LOG) ---"
    tail -200 "$HOST_LOG" | sed -E 's/\x1b\[[0-9;?]*[mGKsuHJh]//g; s/\r/\n/g' || true
    echo ""
    echo "Build container left running as '$ctr' for inspection:"
    echo "  podman exec -it $ctr machinectl shell omedora@.host"
    exit "$install_exit" 2>/dev/null || exit 1
  fi
  log "install phase '$phase' succeeded"
}

# commit_systemd <container> <image> — commit preserving the systemd CMD so the
# image still boots /sbin/init.
commit_systemd() {
  local ctr="$1" image="$2"
  log "Committing $ctr -> $image"
  podman commit \
    --change 'CMD ["/sbin/init"]' \
    --change 'STOPSIGNAL SIGRTMIN+3' \
    "$ctr" "$image" >/dev/null
}

# --- 0. Build the local omedora RPM repo (COPR stand-in) ---------------------
# walker/elephant/fonts aren't in Fedora repos; we serve them as RPMs from a
# local repo injected into the build container. install.sh's dnf calls then
# resolve them + their deps. Only needed by the packaging phase, so skip it in
# --fast (config-only) mode.
#
# The repo build is expensive (~3-4 min: 5 throwaway Fedora containers each run
# dnf install + builddep + source download + rpmbuild). It only depends on the
# specs and the two build scripts, so rebuild it only when one of those is newer
# than the built repomd.xml — i.e. a spec actually changed. This makes a plain
# --rebuild (clean image repackage) skip the redundant RPM rebuild when no spec
# changed, instead of paying it unconditionally. Force a full repo rebuild with
# --rebuild-repo (or just run build-repo.sh yourself).
repo_is_stale() {
  local repomd="$COPR_DIR/repo/repodata/repomd.xml" f
  [[ -f "$repomd" ]] || return 0   # missing → stale
  for f in "$COPR_DIR"/*.spec "$COPR_DIR/build-repo.sh" "$COPR_DIR/build-local.sh"; do
    [[ -e "$f" && "$f" -nt "$repomd" ]] && return 0
  done
  return 1
}
if ! $fast; then
  if $rebuild_repo || repo_is_stale; then
    log "Building local omedora RPM repo (spec changed or repo missing)"
    "$COPR_DIR/build-repo.sh"
  else
    log "Local omedora RPM repo up to date (no spec newer than repomd.xml; --rebuild-repo to force)"
  fi
fi

# =============================================================================
# FAST PATH: config-only. Reuse the existing pkgs image, re-run just the config
# stages, recommit the session image. No repo build, no package install.
# =============================================================================
if $fast; then
  if ! podman image exists "$PKGS_IMAGE"; then
    echo "--fast needs a packages image ($PKGS_IMAGE) but it doesn't exist." >&2
    echo "Run a normal build first (test/fedora/build-session.sh) to create it." >&2
    exit 1
  fi
  log "Fast (config-only) build: booting packages image $PKGS_IMAGE"
  podman rm -f "$BUILD_CTR" >/dev/null 2>&1 || true
  podman volume exists "$DNF_CACHE_VOL" >/dev/null 2>&1 || podman volume create "$DNF_CACHE_VOL" >/dev/null
  podman run -d --name "$BUILD_CTR" --systemd=always \
    -v "$DNF_CACHE_VOL:$DNF_CACHE_DIR" \
    -v "$SESSION_DIR/staged-install.sh:$STAGED_IN_IMAGE:ro" \
    "$PKGS_IMAGE" >/dev/null
  wait_for_systemd "$BUILD_CTR"
  run_phase "$BUILD_CTR" config "config-only"
  commit_systemd "$BUILD_CTR" "$SESSION_IMAGE"
  podman rm -f "$BUILD_CTR" >/dev/null
  log "Done (fast). Session image: $SESSION_IMAGE"
  echo "Launch it with: test/fedora/run-session.sh"
  exit 0
fi

# =============================================================================
# FULL PATH (default / --rebuild / --packages-only).
# =============================================================================

# --- 1. Build the base image -------------------------------------------------
if $rebuild || ! podman image exists "$BASE_IMAGE"; then
  log "Building base image $BASE_IMAGE"
  podman build -t "$BASE_IMAGE" -f "$DOCKERFILE" "$REPO"
else
  log "Base image $BASE_IMAGE already present (use --rebuild to force)"
fi

# Decide whether to rebuild the PACKAGES image. It's the expensive layer; reuse
# it when it already exists and we're not doing a clean --rebuild. (Editing a
# config script and re-running the default build will skip straight to the
# config phase below, against the existing pkgs image — same speed as --fast.)
build_packages=true
if ! $rebuild && podman image exists "$PKGS_IMAGE"; then
  build_packages=false
  log "Packages image $PKGS_IMAGE already present (use --rebuild to force a clean repackage)"
fi

# --- 2. PACKAGES phase: boot base, inject repo, install packages, commit ------
if $build_packages; then
  log "Booting $BASE_IMAGE under systemd (packages phase)"
  podman rm -f "$BUILD_CTR" >/dev/null 2>&1 || true
  podman volume exists "$DNF_CACHE_VOL" >/dev/null 2>&1 || podman volume create "$DNF_CACHE_VOL" >/dev/null
  # Mount the dnf cache volume so install.sh's dnf downloads persist across
  # builds (the base image set keepcache=True so rpms actually stick).
  podman run -d --name "$BUILD_CTR" --systemd=always \
    -v "$DNF_CACHE_VOL:$DNF_CACHE_DIR" \
    -v "$SESSION_DIR/staged-install.sh:$STAGED_IN_IMAGE:ro" \
    "$BASE_IMAGE" >/dev/null
  wait_for_systemd "$BUILD_CTR"
  inject_local_repo "$BUILD_CTR"
  run_phase "$BUILD_CTR" packages "this takes a while"
  commit_systemd "$BUILD_CTR" "$PKGS_IMAGE"
  podman rm -f "$BUILD_CTR" >/dev/null
fi

if $packages_only; then
  log "Done (packages-only). Packages image: $PKGS_IMAGE"
  echo "Apply config + build the session image with: test/fedora/build-session.sh --fast"
  exit 0
fi

# --- 3. CONFIG phase: boot the packages image, apply config, commit session ---
log "Booting $PKGS_IMAGE under systemd (config phase)"
podman rm -f "$BUILD_CTR" >/dev/null 2>&1 || true
podman volume exists "$DNF_CACHE_VOL" >/dev/null 2>&1 || podman volume create "$DNF_CACHE_VOL" >/dev/null
podman run -d --name "$BUILD_CTR" --systemd=always \
  -v "$DNF_CACHE_VOL:$DNF_CACHE_DIR" \
  -v "$SESSION_DIR/staged-install.sh:$STAGED_IN_IMAGE:ro" \
  "$PKGS_IMAGE" >/dev/null
wait_for_systemd "$BUILD_CTR"
run_phase "$BUILD_CTR" config "config stages"
commit_systemd "$BUILD_CTR" "$SESSION_IMAGE"
podman rm -f "$BUILD_CTR" >/dev/null

log "Done. Session image: $SESSION_IMAGE"
echo "Launch it with: test/fedora/run-session.sh"
echo "Iterate on config scripts fast with: test/fedora/build-session.sh --fast"
