#!/bin/bash
#
# L4 Fedora release-upgrade gate: take the Fedora <from> session image, run the
# real dnf5 offline upgrade to <from>+1 under systemd, boot the result, run
# `omarchy update`, and commit it as a session image the headless suite can
# boot.
#
#   omedora/test/fedora/build-upgraded-session.sh          # 44 -> 45
#   omedora/test/fedora/build-upgraded-session.sh --run    # ...then run the
#                                                          #   headless suite
#   omedora/test/fedora/build-upgraded-session.sh --installed
#                                                          # update with the
#                                                          #   COPR's omedora
#                                                          #   payload, not the
#                                                          #   checkout
#   OMEDORA_FEDORA_RELEASE=45 ...                          # 45 -> 46
#
# Input:  omedora-test:fedora<from>-session-4 (built by build-session.sh if
#         missing; override with OMEDORA_UPGRADE_FROM_IMAGE)
# Output: omedora-test:fedora<to>-session-4-upgraded
#         (override with OMEDORA_UPGRADE_TO_IMAGE)
#
# The offline transaction ends by asking logind to reboot, which stops the
# container; starting it again boots the upgraded system, as a real reboot
# would. Needs network (live COPR + Fedora mirrors).

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
. "$REPO/omedora/test/fedora/lib/release.sh"

code_mode=checkout
run_tests=false
for arg in "$@"; do
  case "$arg" in
    --installed) code_mode=installed ;;
    --run)       run_tests=true ;;
    --help|-h)   grep '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

FROM_RELEASE=$OMEDORA_FEDORA_RELEASE
TO_RELEASE="${OMEDORA_UPGRADE_TO:-$((FROM_RELEASE + 1))}"
FROM_IMAGE="${OMEDORA_UPGRADE_FROM_IMAGE:-$OMEDORA_TEST_TAG-session-4}"
TO_IMAGE="${OMEDORA_UPGRADE_TO_IMAGE:-omedora-test:fedora$TO_RELEASE-session-4-upgraded}"
CTR="omedora-upgrade-session-f$FROM_RELEASE-f$TO_RELEASE"
DNF_CACHE_VOL="omedora-dnf-cache$OMEDORA_RELEASE_SUFFIX"
LOG_DIR="${OMEDORA_UPGRADE_LOG_DIR:-${TMPDIR:-/tmp}/omedora-upgrade-session-f$FROM_RELEASE-f$TO_RELEASE}"
OFFLINE_DIR=/usr/lib/sysimage/libdnf5/offline
# Checkout mode links a container-local snapshot of the checkout, never the
# read-only bind mount: `omarchy update` runs `git pull` on a dev-linked
# checkout, and the host's repo is not the test's to change. The snapshot is
# its own git repo with no upstream, so the update skips the pull.
CHECKOUT=/opt/omedora-checkout
mkdir -p "$LOG_DIR"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() {
  printf '\033[1;31m!! %s\033[0m\n' "$1" >&2
  [[ -n ${2:-} && -f $2 ]] && tail -40 "$2" >&2
  echo "Container '$CTR' left for inspection: podman exec -it $CTR bash" >&2
  exit 1
}

wait_for_systemd() {
  local i state
  for i in $(seq 1 120); do
    state=$(podman exec "$CTR" systemctl is-system-running 2>/dev/null || true)
    [[ $state == "running" || $state == "degraded" ]] && break
    (( i == 120 )) && die "systemd never settled (last: ${state:-none})"
    sleep 1
  done
  for i in $(seq 1 60); do
    [[ $(podman exec "$CTR" systemctl is-active user@1000.service 2>/dev/null || true) == "active" ]] && return 0
    sleep 1
  done
  die "user@1000.service never became active"
}

# as_user <log> <command> — run in the omedora user's logind session, like
# build-session.sh's run_phase; machinectl swallows the exit code, so it is
# written to a file and read back. The session has a pty, so any timeout(1)
# in <command> needs --foreground: otherwise its child runs in a background
# process group and omarchy-update's script(1) is stopped by SIGTTOU.
as_user() {
  local log_file="$1" command="$2" env_prefix="" rc
  [[ $code_mode == "checkout" ]] && env_prefix="export OMARCHY_PATH=$CHECKOUT PATH=$CHECKOUT/bin:\$PATH;"
  podman exec "$CTR" rm -f /tmp/as-user.exit
  podman exec "$CTR" machinectl shell omedora@.host /usr/bin/bash -lc \
    "$env_prefix $command >/tmp/as-user.log 2>&1; echo \$? >/tmp/as-user.exit" >/dev/null 2>&1 || true
  podman exec "$CTR" cat /tmp/as-user.log >"$log_file" 2>/dev/null || true
  rc=$(podman exec "$CTR" cat /tmp/as-user.exit 2>/dev/null || echo missing)
  [[ $rc == "0" ]]
}

if ! podman image exists "$FROM_IMAGE"; then
  log "Building the Fedora $FROM_RELEASE session image first"
  OMEDORA_SYSTEMD_SESSION_IMAGE="$FROM_IMAGE" "$REPO/omedora/test/fedora/build-session.sh"
fi

log "Booting $FROM_IMAGE (Fedora $FROM_RELEASE) under systemd"
podman rm -f "$CTR" >/dev/null 2>&1 || true
podman volume exists "$DNF_CACHE_VOL" >/dev/null 2>&1 || podman volume create "$DNF_CACHE_VOL" >/dev/null
podman run -d --name "$CTR" --systemd=always --security-opt label=disable \
  -v "$DNF_CACHE_VOL:/var/cache/libdnf5" \
  -v "$REPO:/repo:ro" \
  "$FROM_IMAGE" >/dev/null
wait_for_systemd

# Same scaffolding as update-verify.sh: sudo -v under a pty would otherwise
# prompt; and in checkout mode root resolves omarchy-* from the checkout, as
# `omarchy dev link` arranges.
podman exec "$CTR" bash -c \
  "printf 'Defaults:omedora !authenticate\n' >/etc/sudoers.d/zz-omedora-test-noauth && chmod 0440 /etc/sudoers.d/zz-omedora-test-noauth"
if [[ $code_mode == "checkout" ]]; then
  podman exec "$CTR" bash -c "mkdir -p $CHECKOUT && tar -C /repo --exclude=./.git \
      --exclude='./omedora/packaging/copr/repo*' --exclude='./omedora/packaging/copr/output*' \
      --exclude=./omedora/test/fedora/headless/artifacts --exclude='./omedora/test/fedora/vm/artifacts*' \
      -cf - . | tar -C $CHECKOUT -xf - && chown -R omedora:omedora $CHECKOUT && \
    runuser -u omedora -- bash -c 'cd $CHECKOUT && git init -q && git add -A && \
      git -c user.name=test -c user.email=test@localhost commit -qm \"checkout snapshot\"'" \
    || die "snapshot the checkout into $CHECKOUT"
  podman exec "$CTR" bash -c \
    "printf 'Defaults secure_path=\"$CHECKOUT/bin:/usr/local/sbin:/usr/local/bin:/usr/bin\"\n' >/etc/sudoers.d/omarchy-dev-path && chmod 0440 /etc/sudoers.d/omarchy-dev-path"
fi

log "Preflight: omedora-upgrade-fedora --check --releasever $TO_RELEASE"
as_user "$LOG_DIR/check.log" "omedora-upgrade-fedora --check --releasever $TO_RELEASE" \
  || die "preflight refused Fedora $TO_RELEASE" "$LOG_DIR/check.log"

log "Downloading the Fedora $TO_RELEASE upgrade"
podman exec "$CTR" dnf -y system-upgrade download --releasever="$TO_RELEASE" \
  >"$LOG_DIR/download.log" 2>&1 || die "system-upgrade download failed" "$LOG_DIR/download.log"

log "Running the offline transaction (it reboots the container when done)"
podman exec "$CTR" bash -c \
  "sed -i 's/^status = .*/status = \"ready\"/' $OFFLINE_DIR/offline-transaction-state.toml && ln -sfn $OFFLINE_DIR /system-update"
podman exec "$CTR" dnf5 offline _execute >"$LOG_DIR/execute.log" 2>&1 || true
grep -qE '^Error:|Transaction failed' "$LOG_DIR/execute.log" \
  && die "offline transaction failed" "$LOG_DIR/execute.log"

for _ in $(seq 1 60); do
  [[ $(podman inspect -f '{{.State.Running}}' "$CTR" 2>/dev/null) == "false" ]] && break
  sleep 1
done
log "Booting the upgraded system"
podman start "$CTR" >/dev/null
wait_for_systemd
now=$(podman exec "$CTR" bash -c '. /etc/os-release && echo "$VERSION_ID"')
[[ $now == "$TO_RELEASE" ]] || die "expected Fedora $TO_RELEASE after the upgrade, os-release says $now" "$LOG_DIR/execute.log"
log "Upgraded to Fedora $now"

log "omarchy update on Fedora $TO_RELEASE"
as_user "$LOG_DIR/update.log" "timeout --foreground 1800 omarchy-update -y" \
  || die "omarchy update failed on Fedora $TO_RELEASE" "$LOG_DIR/update.log"

podman exec "$CTR" rm -rf /etc/sudoers.d/zz-omedora-test-noauth /etc/sudoers.d/omarchy-dev-path "$CHECKOUT"
log "Committing $CTR -> $TO_IMAGE"
podman stop "$CTR" >/dev/null
podman commit --change 'CMD ["/sbin/init"]' --change 'STOPSIGNAL SIGRTMIN+3' \
  "$CTR" "$TO_IMAGE" >/dev/null
podman rm -f "$CTR" >/dev/null
log "Done. Upgraded session image: $TO_IMAGE (logs: $LOG_DIR)"

if $run_tests; then
  OMEDORA_FEDORA_RELEASE="$TO_RELEASE" OMEDORA_SYSTEMD_SESSION_IMAGE="$TO_IMAGE" \
    exec "$REPO/omedora/test/fedora/headless/run-tests.sh"
fi
