#!/bin/bash
#
# Host-side runner for the L3 Fedora release-upgrade test: installs Omedora on
# Fedora <from> from the live COPR, runs the real dnf5 offline upgrade to
# <from>+1, and checks the Omedora packages and updater on the new release.
# See release-upgrade-verify.sh for the assertions.
#
# Usage:
#   omedora/test/fedora/run-release-upgrade.sh              # 44 -> 45
#   omedora/test/fedora/run-release-upgrade.sh --installed  # drive the COPR's
#                                                           #   omedora payload,
#                                                           #   not the checkout
#   omedora/test/fedora/run-release-upgrade.sh --keep       # keep the container
#   OMEDORA_FEDORA_RELEASE=45 omedora/test/fedora/run-release-upgrade.sh
#                                                           # 45 -> 46
#
# Runs under podman in a real PID 1 systemd container booted from the L4 base
# image (omedora-test:fedora<from>-session-4-sysbase, built when missing):
# 4.5's `omarchy update` holds a logind sleep inhibitor, which needs a system
# bus. See lib/systemd-container.sh. The offline transaction's reboot stops the
# container; starting it again boots the new release, as a real reboot would,
# and the verify phase runs there. The container is removed afterwards unless
# --keep is given.
#
# Needs network (live COPR, Fedora mirrors) and ~25 minutes.

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
. "$REPO/omedora/test/fedora/lib/release.sh"
. "$REPO/omedora/test/fedora/lib/systemd-container.sh"

code_mode=checkout
keep=false
for arg in "$@"; do
  case "$arg" in
    --installed) code_mode=installed ;;
    --keep)      keep=true ;;
    --help|-h)
      grep '^# ' "$0" | sed 's/^# //'
      exit 0
      ;;
    *)
      echo "unknown arg: $arg" >&2
      exit 2
      ;;
  esac
done

DNF_CACHE_VOL="omedora-dnf-cache$OMEDORA_RELEASE_SUFFIX"
CTR="omedora-l3-release-upgrade-f$OMEDORA_FEDORA_RELEASE"
VERIFY=/repo/omedora/test/fedora/release-upgrade-verify.sh
exec_env=(-e "OMEDORA_UPGRADE_CODE=$code_mode")
[[ -z ${OMEDORA_UPGRADE_TO:-} ]] || exec_env+=(-e "OMEDORA_UPGRADE_TO=$OMEDORA_UPGRADE_TO")

systemd_base_ensure
if $keep; then
  trap 'echo "Container $CTR kept: podman exec -it $CTR bash"' EXIT
else
  trap 'podman rm -f "$CTR" >/dev/null 2>&1 || true' EXIT
fi

echo "Booting $SYSTEMD_BASE_IMAGE under systemd as $CTR..."
podman volume exists "$DNF_CACHE_VOL" || podman volume create "$DNF_CACHE_VOL" >/dev/null
systemd_container_run "$CTR" -v "$REPO:/repo" -v "$DNF_CACHE_VOL:/var/cache/libdnf5"
systemd_container_wait "$CTR"

# The offline transaction reboots the container, which ends this exec. The
# phase drops a marker right before the transaction starts, so a container
# that still runs without it failed before getting there.
rc=0
podman exec "${exec_env[@]}" "$CTR" bash "$VERIFY" upgrade || rc=$?
if (( rc != 0 )) &&
  podman exec "$CTR" test ! -e /var/tmp/release-upgrade/executing >/dev/null 2>&1; then
  echo "The upgrade phase failed before the offline transaction (rc=$rc)" >&2
  exit "$rc"
fi
if ! systemd_container_wait_stopped "$CTR"; then
  podman exec "$CTR" tail -40 /var/tmp/release-upgrade/execute.log >&2 || true
  exit 1
fi

echo "Booting the upgraded system..."
podman start "$CTR" >/dev/null
systemd_container_wait "$CTR"
podman exec "${exec_env[@]}" "$CTR" bash "$VERIFY" verify
