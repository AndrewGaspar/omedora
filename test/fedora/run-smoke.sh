#!/bin/bash
#
# Host-side runner for the L3 Fedora smoke test.
# Builds the image if needed, then runs test/fedora/smoke.sh inside it.
#
# Usage:
#   test/fedora/run-smoke.sh
#   test/fedora/run-smoke.sh --rebuild

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
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
  docker build -t "$IMAGE" -f "$REPO/test/fedora/Dockerfile" "$REPO/test/fedora/"
fi

exec docker run --rm \
  -v "$REPO:/repo" \
  "$IMAGE" bash /repo/test/fedora/smoke.sh
