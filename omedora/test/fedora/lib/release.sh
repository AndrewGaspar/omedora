# shellcheck shell=bash disable=SC2034  # sourced: the caller uses these
# Host-side helper: which Fedora release the test/build harness targets.
#
# Sourced (never executed) by the host-side runners under omedora/test/fedora/
# and by omedora/packaging/copr/build-{local,repo}.sh. One knob drives every
# layer:
#
#   OMEDORA_FEDORA_RELEASE=45 omedora/test/fedora/run-integration.sh
#
# Default 44. Fedora 44 keeps the exact names the harness used before the knob
# existed (omedora-test:fedora44, the omedora-dnf-cache volume, the unsuffixed
# packaging/copr/output + repo dirs), so cached images, volumes and locally
# built repos stay valid. Every other release gets a "-f<N>" suffix on the
# shared names; image tags already carry the release ("fedora<N>").

OMEDORA_FEDORA_RELEASE="${OMEDORA_FEDORA_RELEASE:-44}"
if [[ ! $OMEDORA_FEDORA_RELEASE =~ ^[0-9]+$ ]]; then
  echo "OMEDORA_FEDORA_RELEASE must be a Fedora release number (got '$OMEDORA_FEDORA_RELEASE')" >&2
  exit 2
fi
export OMEDORA_FEDORA_RELEASE

# Upstream Fedora container image (Dockerfile FROM / throwaway build containers).
OMEDORA_FEDORA_IMAGE="registry.fedoraproject.org/fedora:$OMEDORA_FEDORA_RELEASE"
# Prefix of every omedora test image tag: omedora-test:fedora<N>[-session-4...].
OMEDORA_TEST_TAG="omedora-test:fedora$OMEDORA_FEDORA_RELEASE"
# Suffix for release-agnostic legacy names (volumes, containers, output dirs):
# empty on 44, "-f<N>" otherwise.
if (( OMEDORA_FEDORA_RELEASE == 44 )); then
  OMEDORA_RELEASE_SUFFIX=""
else
  OMEDORA_RELEASE_SUFFIX="-f$OMEDORA_FEDORA_RELEASE"
fi
