#!/bin/bash
#
# Host-side runner for the L2 Fedora integration tests.
# Builds the test image if needed, then runs test/fedora/integration.sh
# inside it with the repo bind-mounted.
#
# Usage:
#   test/fedora/run-integration.sh
#   test/fedora/run-integration.sh --shell   # drop into a shell instead
#   test/fedora/run-integration.sh --rebuild # force image rebuild
#
# Requires: docker (or compatible runtime; tested with docker 29+).

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
IMAGE="${OMEDORA_TEST_IMAGE:-omedora-test:fedora44}"

cmd="bash /repo/test/fedora/integration.sh"
rebuild=false
shell=false

for arg in "$@"; do
  case "$arg" in
    --shell)   shell=true ;;
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

if $shell; then
  exec docker run --rm -it \
    -v "$REPO:/repo" \
    "$IMAGE" bash
fi

exec docker run --rm \
  -v "$REPO:/repo" \
  "$IMAGE" $cmd
