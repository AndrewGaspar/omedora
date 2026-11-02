# Host-side container engine for the L2/L3 runners (run-integration.sh,
# run-smoke.sh, run-release-upgrade.sh). Sourced, not executed.
#
# OMEDORA_CONTAINER_ENGINE wins when set. Otherwise use Docker when its daemon
# answers (CI), and rootless Podman when it does not: a docker CLI whose socket
# the user cannot reach would otherwise fail every runner with "permission
# denied". The runners' docker arguments work unchanged under Podman.

if [[ -z ${OMEDORA_CONTAINER_ENGINE:-} ]]; then
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    OMEDORA_CONTAINER_ENGINE=docker
  elif command -v podman >/dev/null 2>&1; then
    OMEDORA_CONTAINER_ENGINE=podman
  else
    OMEDORA_CONTAINER_ENGINE=docker
  fi
fi
