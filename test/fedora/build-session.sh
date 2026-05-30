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
# Usage:
#   test/fedora/build-session.sh            # build base if needed, install, commit
#   test/fedora/build-session.sh --rebuild  # force a clean base rebuild first
#
# Products:
#   omedora-test:fedora44-session-base     (Fedora + systemd + tree; CMD /sbin/init)
#   omedora-test:fedora44-session  (the above, after install.sh; ready to run)
#
# Full install log is also copied out to /tmp/omedora-session-build.log.

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
BASE_IMAGE="${OMEDORA_SYSTEMD_BASE_IMAGE:-omedora-test:fedora44-session-base}"
SESSION_IMAGE="${OMEDORA_SYSTEMD_SESSION_IMAGE:-omedora-test:fedora44-session}"
BUILD_CTR="${OMEDORA_BUILD_CTR:-omedora-session-build}"
DNF_CACHE_VOL="${OMEDORA_DNF_CACHE_VOL:-omedora-dnf-cache}"
HOST_LOG="${OMEDORA_SYSTEMD_BUILD_LOG:-/tmp/omedora-session-build.log}"
DOCKERFILE="$REPO/test/fedora/omedora-session/Dockerfile.base"
COPR_DIR="$REPO/omedora/packaging/copr"

rebuild=false
[[ "${1:-}" == "--rebuild" ]] && rebuild=true

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# --- 0. Build the local omedora RPM repo (COPR stand-in) ---------------------
# walker/elephant/fonts aren't in Fedora repos; we serve them as RPMs from a
# local repo injected into the build container (§ step 2.5 below). install.sh's
# dnf calls then resolve them + their deps. Skip if the repo already exists and
# we're not rebuilding.
if $rebuild || [[ ! -f "$COPR_DIR/repo/repodata/repomd.xml" ]]; then
  log "Building local omedora RPM repo"
  "$COPR_DIR/build-repo.sh"
fi

# --- 1. Build the base image -------------------------------------------------
if $rebuild || ! podman image exists "$BASE_IMAGE"; then
  log "Building base image $BASE_IMAGE"
  podman build -t "$BASE_IMAGE" -f "$DOCKERFILE" "$REPO"
else
  log "Base image $BASE_IMAGE already present (use --rebuild to force)"
fi

# --- 2. Boot the base under systemd -----------------------------------------
log "Booting $BASE_IMAGE under systemd"
podman rm -f "$BUILD_CTR" >/dev/null 2>&1 || true
podman volume exists "$DNF_CACHE_VOL" >/dev/null 2>&1 || podman volume create "$DNF_CACHE_VOL" >/dev/null
# Mount the dnf cache volume so install.sh's dnf downloads persist across builds
# (the base image set keepcache=True in dnf.conf so rpms actually stick).
podman run -d --name "$BUILD_CTR" --systemd=always \
  -v "$DNF_CACHE_VOL:/var/cache/dnf" \
  "$BASE_IMAGE" >/dev/null

log "Waiting for systemd to reach running/degraded"
for i in $(seq 1 60); do
  state=$(podman exec "$BUILD_CTR" systemctl is-system-running 2>/dev/null || true)
  case "$state" in
    running|degraded) echo "  systemd: $state (after ${i}s)"; break ;;
  esac
  [[ $i -eq 60 ]] && { echo "systemd never settled (last: ${state:-none})"; podman logs "$BUILD_CTR" | tail -30; exit 1; }
  sleep 1
done

# Confirm the omedora user manager is up (linger + drop-in should have started it).
for i in $(seq 1 30); do
  [[ "$(podman exec "$BUILD_CTR" systemctl is-active user@1000.service 2>/dev/null || true)" == "active" ]] && break
  [[ $i -eq 30 ]] && { echo "user@1000.service never became active"; exit 1; }
  sleep 1
done
echo "  user@1000.service: active"

# --- 2.5 Inject the local omedora RPM repo ----------------------------------
# Copy the createrepo'd RPMs into the container and drop a .repo pointing at
# them, so install.sh's `dnf install walker/elephant/omedora-nerd-fonts`
# resolves from here (with dependencies). This is exactly what enabling a COPR
# would do; swapping to a published COPR later means deleting this block and
# flipping the fedora.toml entries to source = "copr".
log "Injecting local omedora RPM repo"
podman cp "$COPR_DIR/repo" "$BUILD_CTR:/opt/omedora-repo"
podman exec "$BUILD_CTR" bash -c \
  'printf "[omedora-local]\nname=Omedora local packages\nbaseurl=file:///opt/omedora-repo\nenabled=1\ngpgcheck=0\n" >/etc/yum.repos.d/omedora-local.repo'

# --- 3. Run install.sh inside the live logind session -----------------------
# machinectl shell gives omedora a real PAM/logind session: XDG_RUNTIME_DIR,
# the user D-Bus, a PTY (no `script` hack needed). It does NOT propagate the
# command's exit code, so the install writes its own exit code to a marker
# file we read back afterward.
log "Running install.sh as omedora in a logind session (this takes a while)"
podman exec "$BUILD_CTR" rm -f /tmp/install.exit
podman exec "$BUILD_CTR" machinectl shell \
  --setenv=OMARCHY_NONINTERACTIVE=1 \
  omedora@.host /usr/bin/bash -lc \
  'bash "$HOME/.local/share/omarchy/install.sh"; echo $? > /tmp/install.exit' \
  || true

# machinectl shell returned; read the real install exit code.
install_exit=$(podman exec "$BUILD_CTR" cat /tmp/install.exit 2>/dev/null || echo "missing")

# Copy the clean per-script log out regardless of outcome.
podman exec "$BUILD_CTR" cat /var/log/omarchy-install.log >"$HOST_LOG" 2>/dev/null || true

if [[ "$install_exit" != "0" ]]; then
  log "install.sh FAILED (exit $install_exit)"
  echo "--- last 60 lifecycle events ---"
  grep -aE '^\[20[0-9]{2}-[0-9]{2}-[0-9]{2} [0-9:]+\] (Starting|Completed|Failed):' "$HOST_LOG" | tail -60 || true
  echo ""
  echo "--- last 200 lines of clean install log ($HOST_LOG) ---"
  tail -200 "$HOST_LOG" | sed -E 's/\x1b\[[0-9;?]*[mGKsuHJh]//g; s/\r/\n/g' || true
  echo ""
  echo "Build container left running as '$BUILD_CTR' for inspection:"
  echo "  podman exec -it $BUILD_CTR machinectl shell omedora@.host"
  exit "$install_exit" 2>/dev/null || exit 1
fi

log "install.sh succeeded"

# --- 4. Commit the finished container ---------------------------------------
log "Committing $BUILD_CTR -> $SESSION_IMAGE"
# Preserve the systemd CMD so the committed image still boots /sbin/init.
podman commit \
  --change 'CMD ["/sbin/init"]' \
  --change 'STOPSIGNAL SIGRTMIN+3' \
  "$BUILD_CTR" "$SESSION_IMAGE" >/dev/null
podman rm -f "$BUILD_CTR" >/dev/null

log "Done. Session image: $SESSION_IMAGE"
echo "Launch it with: test/fedora/run-session.sh"
