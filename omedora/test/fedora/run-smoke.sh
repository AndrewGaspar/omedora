#!/bin/bash
#
# Host-side runner for the L3 Fedora smoke test.
# Builds the image if needed, then runs omedora/test/fedora/smoke.sh inside it.
#
# Usage:
#   omedora/test/fedora/run-smoke.sh
#   omedora/test/fedora/run-smoke.sh --rebuild

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
IMAGE="${OMEDORA_TEST_IMAGE:-omedora-test:fedora44}"

rebuild=false
for arg in "$@"; do
  case "$arg" in
    --rebuild) rebuild=true ;;
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
  docker build -t "$IMAGE" -f "$REPO/omedora/test/fedora/Dockerfile" "$REPO/omedora/test/fedora/"
fi

exec docker run --rm \
  -v "$REPO:/repo" \
  "$IMAGE" bash /repo/omedora/test/fedora/smoke.sh
