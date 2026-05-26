#!/bin/bash
#
# Host-side runner for the L4-nested Omedora session image.
#
# Usage:
#   test/fedora/run-session.sh                # build, then drop into a shell
#   test/fedora/run-session.sh --build-only   # build the image, then exit
#   test/fedora/run-session.sh --rebuild      # force a clean rebuild
#   test/fedora/run-session.sh --shell        # post-install interactive shell
#
# Logs: full uncapped build log is tee'd to /tmp/omedora-session-build.log.
#
# BuildKit caps each step's stdout buffer at ~2MB by default and there's no
# clean way to lift it from the host side (the cap is in the dockerd-embedded
# buildkit daemon; the env var would need to live in dockerd's environment,
# and a separate `docker-container` buildkit builder can't see locally-built
# base images). Instead, the Dockerfile uses a two-RUN pattern: install.sh
# always succeeds and writes the result + log to /tmp/, then a separate RUN
# reads the result and fails-with-tail. The "tail" RUN gets its own fresh
# 2MB log budget — enough to show the last ~1.5MB of install.log on failure.
#
# Output is piped through sed to strip ANSI escape sequences for readability.
#
# Image dependency: omedora-test:fedora44 must be built first. The runner
# builds it for you if missing.

set -euo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
BASE_IMAGE="${OMEDORA_TEST_IMAGE:-omedora-test:fedora44}"
SESSION_IMAGE="${OMEDORA_TEST_SESSION_IMAGE:-omedora-test:fedora44-session}"
LOG="${OMEDORA_SESSION_BUILD_LOG:-/tmp/omedora-session-build.log}"

rebuild=false
build_only=false
shell=false

for arg in "$@"; do
  case "$arg" in
    --rebuild)    rebuild=true ;;
    --build-only) build_only=true ;;
    --shell)      shell=true ;;
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

# Strip ANSI escape sequences from a stream so the build log stays readable
# (dnf and gum emit a lot of \x1b[...m chrome).
strip_ansi() {
  sed -u '
    s/\x1b\[[0-9;?]*[mGKsuHJh]//g
    s/\x1b\][^\x07]*\x07//g
    s/\r/\n/g
  '
}

build() {
  local image="$1" dockerfile="$2" context="$3"
  echo "Building $image (full log → $LOG)..."
  : >"$LOG"
  docker build --progress=plain -t "$image" -f "$dockerfile" "$context" 2>&1 \
    | strip_ansi | tee -a "$LOG"
}

if $rebuild || ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
  build "$BASE_IMAGE" "$REPO/test/fedora/Dockerfile" "$REPO/test/fedora/"
fi

if $rebuild || ! docker image inspect "$SESSION_IMAGE" >/dev/null 2>&1; then
  build "$SESSION_IMAGE" "$REPO/test/fedora/omedora-session/Dockerfile" "$REPO"
fi

$build_only && exit 0

if $shell; then
  exec docker run --rm -it "$SESSION_IMAGE" bash
fi

# Default: drop into bash inside the built session image.
exec docker run --rm -it "$SESSION_IMAGE"
