#!/bin/bash
#
# Host-side runner for the L3 Fedora smoke test.
# Builds the image if needed, then runs omedora/test/fedora/smoke.sh inside it.
#
# Usage:
#   omedora/test/fedora/run-smoke.sh
#   omedora/test/fedora/run-smoke.sh --rebuild
#   omedora/test/fedora/run-smoke.sh --local-repo     # install the locally-built core RPMs
#   omedora/test/fedora/run-smoke.sh --local-repo --rebuild-repo
#   omedora/test/fedora/run-smoke.sh --update-verify  # run the L3 update gate
#                                                     #   (update-verify.sh) instead
#   omedora/test/fedora/run-smoke.sh --update-verify --keep  # keep its container
#   OMEDORA_FEDORA_RELEASE=45 omedora/test/fedora/run-smoke.sh   # default 44
#
# --update-verify runs update-verify.sh (fresh install, then two `omarchy
# update` runs and the migration path) with the same repo mounts and
# --local-repo plumbing, plus the release's dnf cache volume. It runs under
# podman in a real PID 1 systemd container booted from the L4 base image
# (omedora-test:fedora<N>-session-4-sysbase), not the plain smoke image: 4.5's
# `omarchy update` holds a logind sleep inhibitor, which needs a system bus.
# See lib/systemd-container.sh. The container is removed afterwards unless
# --keep is given.
#
# --local-repo (or OMEDORA_LOCAL_REPO=1) overlays the local RPM repo that
# build-repo.sh builds from this checkout (omedora/packaging/copr/repo, or
# repo-f<N> for OMEDORA_FEDORA_RELEASE=<N>) on the live COPR, exactly like
# build-session.sh --local-repo: priority=1, so the omedora and
# omedora-settings RPMs come from it and the rest of the stack from the COPR.
# The core RPMs package `git archive HEAD`; when the repo does not hold HEAD's
# build they are built first (noarch, ~2 min; --rebuild-repo forces it). The
# smoke then asserts both come from the local repo with HEAD's release stamp.
# See lib/local-repo.sh.

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
. "$REPO/omedora/test/fedora/lib/release.sh"
. "$REPO/omedora/test/fedora/lib/local-repo.sh"
. "$REPO/omedora/test/fedora/lib/systemd-container.sh"
IMAGE="${OMEDORA_TEST_IMAGE:-$OMEDORA_TEST_TAG}"

rebuild=false
rebuild_repo=false
local_repo=false
keep=false
script=smoke.sh
[[ ${OMEDORA_LOCAL_REPO:-} == "1" ]] && local_repo=true
for arg in "$@"; do
  case "$arg" in
    --rebuild) rebuild=true ;;
    --local-repo) local_repo=true ;;
    --rebuild-repo) rebuild_repo=true ;;
    --update-verify) script=update-verify.sh ;;
    --keep) keep=true ;;
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
if $keep && [[ $script != "update-verify.sh" ]]; then
  echo "--keep only applies with --update-verify" >&2
  exit 2
fi

mounts=(-v "$REPO:/repo")
env_args=()
if [[ $script == "update-verify.sh" ]]; then
  mounts+=(-v "omedora-dnf-cache$OMEDORA_RELEASE_SUFFIX:/var/cache/libdnf5")
fi
if $local_repo; then
  if $rebuild_repo; then
    echo "Rebuilding the local core RPMs from HEAD (--rebuild-repo)..."
    local_repo_build_core --force
  elif ! stale_reason=$(local_repo_core_status); then
    echo "Building the local core RPMs from HEAD ($stale_reason)..."
    local_repo_build_core
  fi
  if ! stale_reason=$(local_repo_core_status); then
    echo "The local repo does not hold HEAD's core RPMs: $stale_reason" >&2
    exit 1
  fi
  local_repo_warn_dirty
  echo "Local-repo mode: overlaying $OMEDORA_LOCAL_REPO_DIR ($(local_repo_head_tag)) on the COPR"
  mounts+=(-v "$OMEDORA_LOCAL_REPO_DIR:/opt/omedora-repo:ro")
  env_args+=(
    -e OMEDORA_TEST_LOCAL_REPO=/opt/omedora-repo
    -e "OMEDORA_TEST_EXPECT_TAG=$(local_repo_head_tag)"
    -e "OMEDORA_LOCAL_REPO_ONLY=${OMEDORA_LOCAL_REPO_ONLY:-}"
  )
fi

if [[ $script == "update-verify.sh" ]]; then
  if $rebuild; then
    echo "--rebuild rebuilds the plain smoke image; the update gate boots $SYSTEMD_BASE_IMAGE" >&2
    echo "(rebuild that with omedora/test/fedora/build-session.sh --rebuild)" >&2
    exit 2
  fi
  systemd_base_ensure
  ctr="omedora-l3-update-verify$OMEDORA_RELEASE_SUFFIX"
  if ! $keep; then
    trap 'podman rm -f "$ctr" >/dev/null 2>&1 || true' EXIT
  fi
  echo "Booting $SYSTEMD_BASE_IMAGE under systemd as $ctr..."
  podman volume exists "omedora-dnf-cache$OMEDORA_RELEASE_SUFFIX" ||
    podman volume create "omedora-dnf-cache$OMEDORA_RELEASE_SUFFIX" >/dev/null
  systemd_container_run "$ctr" "${mounts[@]}"
  systemd_container_wait "$ctr"
  rc=0
  podman exec "${env_args[@]}" "$ctr" bash "/repo/omedora/test/fedora/$script" || rc=$?
  ! $keep || echo "Container $ctr kept: podman exec -it $ctr bash"
  exit "$rc"
fi

if $rebuild || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Building $IMAGE..."
  docker build -t "$IMAGE" --build-arg "FEDORA_RELEASE=$OMEDORA_FEDORA_RELEASE" \
    -f "$REPO/omedora/test/fedora/Dockerfile" "$REPO/omedora/test/fedora/"
fi

exec docker run --rm "${mounts[@]}" "${env_args[@]}" \
  "$IMAGE" bash "/repo/omedora/test/fedora/$script"
