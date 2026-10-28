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
#   omedora/test/fedora/run-release-upgrade.sh --local-repo # core RPMs from
#                                                           #   HEAD, both releases
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
# --local-repo (or OMEDORA_LOCAL_REPO=1) installs the omedora and
# omedora-settings RPMs built from HEAD instead of the COPR's, as
# run-smoke.sh --local-repo does, and keeps them through the upgrade: it
# builds them into both releases' local repos (repo[-f<from>] and repo-f<to>;
# --rebuild-repo forces), mounts them at /opt/omedora-repo/<release>, and the
# overlay's baseurl names $releasever, so the offline upgrade swaps in the
# target release's build. Checkout mode needs it whenever the checkout's code
# expects a settings payload the COPR does not serve yet (a new Omarchy line
# before its first release): the code comes from the checkout, but the
# packages it reads come from the RPMs. See lib/local-repo.sh.
#
# Needs network (live COPR, Fedora mirrors) and ~25 minutes.

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
. "$REPO/omedora/test/fedora/lib/release.sh"
. "$REPO/omedora/test/fedora/lib/systemd-container.sh"

code_mode=checkout
keep=false
local_repo=false
rebuild_repo=false
[[ ${OMEDORA_LOCAL_REPO:-} == "1" ]] && local_repo=true
for arg in "$@"; do
  case "$arg" in
    --installed) code_mode=installed ;;
    --keep)      keep=true ;;
    --local-repo) local_repo=true ;;
    --rebuild-repo) rebuild_repo=true ;;
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

if $rebuild_repo && ! $local_repo; then
  echo "--rebuild-repo only applies with --local-repo" >&2
  exit 2
fi

FROM_RELEASE=$OMEDORA_FEDORA_RELEASE
TO_RELEASE="${OMEDORA_UPGRADE_TO:-$((FROM_RELEASE + 1))}"
DNF_CACHE_VOL="omedora-dnf-cache$OMEDORA_RELEASE_SUFFIX"
CTR="omedora-l3-release-upgrade-f$FROM_RELEASE"
VERIFY=/repo/omedora/test/fedora/release-upgrade-verify.sh
mounts=(-v "$REPO:/repo" -v "$DNF_CACHE_VOL:/var/cache/libdnf5")
exec_env=(-e "OMEDORA_UPGRADE_CODE=$code_mode")
[[ -z ${OMEDORA_UPGRADE_TO:-} ]] || exec_env+=(-e "OMEDORA_UPGRADE_TO=$OMEDORA_UPGRADE_TO")

# local_repo_dir <release> — make <release>'s local repo hold HEAD's core RPMs
# (building them when it does not) and print its directory.
local_repo_dir() (
  export OMEDORA_FEDORA_RELEASE=$1
  unset OMEDORA_LOCAL_REPO_DIR
  . "$REPO/omedora/test/fedora/lib/release.sh"
  . "$REPO/omedora/test/fedora/lib/local-repo.sh"
  if $rebuild_repo; then
    echo "Rebuilding the Fedora $1 core RPMs from HEAD (--rebuild-repo)..." >&2
    local_repo_build_core --force >&2
  elif ! stale_reason=$(local_repo_core_status); then
    echo "Building the Fedora $1 core RPMs from HEAD ($stale_reason)..." >&2
    local_repo_build_core >&2
  fi
  if ! stale_reason=$(local_repo_core_status); then
    echo "The Fedora $1 local repo does not hold HEAD's core RPMs: $stale_reason" >&2
    exit 1
  fi
  printf '%s\n' "$OMEDORA_LOCAL_REPO_DIR"
)

if $local_repo; then
  . "$REPO/omedora/test/fedora/lib/local-repo.sh"
  for release in "$FROM_RELEASE" "$TO_RELEASE"; do
    dir=$(local_repo_dir "$release")
    mounts+=(-v "$dir:/opt/omedora-repo/$release:ro")
  done
  local_repo_warn_dirty
  echo "Local-repo mode: core RPMs $(local_repo_head_tag) for Fedora $FROM_RELEASE and $TO_RELEASE"
  exec_env+=(
    -e OMEDORA_TEST_LOCAL_REPO=/opt/omedora-repo
    -e "OMEDORA_TEST_EXPECT_TAG=$(local_repo_head_tag)"
  )
fi

systemd_base_ensure
if $keep; then
  trap 'echo "Container $CTR kept: podman exec -it $CTR bash"' EXIT
else
  trap 'podman rm -f "$CTR" >/dev/null 2>&1 || true' EXIT
fi

echo "Booting $SYSTEMD_BASE_IMAGE under systemd as $CTR..."
podman volume exists "$DNF_CACHE_VOL" || podman volume create "$DNF_CACHE_VOL" >/dev/null
systemd_container_run "$CTR" "${mounts[@]}"
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
