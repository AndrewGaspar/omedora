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
#   omedora/test/fedora/run-release-upgrade.sh --rebuild    # rebuild the image
#   OMEDORA_FEDORA_RELEASE=45 omedora/test/fedora/run-release-upgrade.sh
#                                                           # 45 -> 46
#
# Needs network (live COPR, Fedora mirrors) and ~25 minutes.

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
. "$REPO/omedora/test/fedora/lib/release.sh"
IMAGE="${OMEDORA_TEST_IMAGE:-$OMEDORA_TEST_TAG}"

code_mode=checkout
rebuild=false
for arg in "$@"; do
  case "$arg" in
    --installed) code_mode=installed ;;
    --rebuild)   rebuild=true ;;
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

if $rebuild || ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "Building $IMAGE..."
  docker build -t "$IMAGE" --build-arg "FEDORA_RELEASE=$OMEDORA_FEDORA_RELEASE" \
    -f "$REPO/omedora/test/fedora/Dockerfile" "$REPO/omedora/test/fedora/"
fi

exec docker run --rm \
  -v "$REPO:/repo" \
  -v "omedora-dnf-cache$OMEDORA_RELEASE_SUFFIX:/var/cache/libdnf5" \
  -e "OMEDORA_UPGRADE_CODE=$code_mode" \
  ${OMEDORA_UPGRADE_TO:+-e "OMEDORA_UPGRADE_TO=$OMEDORA_UPGRADE_TO"} \
  "$IMAGE" bash /repo/omedora/test/fedora/release-upgrade-verify.sh
