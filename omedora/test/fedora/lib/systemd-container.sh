# shellcheck shell=bash
# Host-side helper: boot an L3 update gate in a real systemd container.
#
# Sourced (never executed) by run-smoke.sh --update-verify and
# run-release-upgrade.sh, after lib/release.sh, with $REPO set to the checkout
# root. Those gates run `omarchy update`, and since Omarchy 4.5 the update holds
# a logind sleep inhibitor (omarchy-update-stay-awake → systemd-inhibit) that
# needs a system bus and logind. The plain L3 image has neither, so the gates
# boot the L4 base image (omedora-session/Dockerfile.base: Fedora, PID 1
# systemd, dbus-broker, logind, polkit and the omedora user) the way
# build-session.sh does, and run their in-container script with `podman exec`.
# The fresh-install smoke needs no bus and keeps the cheaper plain image.
#
# The base image is the L4 one, so the gates share it with build-session.sh:
# omedora-test:fedora<N>-session-4-sysbase (OMEDORA_SYSTEMD_BASE_IMAGE
# overrides). It holds no checkout; the gates bind-mount the repo at /repo.

SYSTEMD_BASE_IMAGE="${OMEDORA_SYSTEMD_BASE_IMAGE:-$OMEDORA_TEST_TAG-session-4-sysbase}"

# systemd_base_ensure — build the base image when it is missing (as
# build-session.sh does; ~3 min, no Omedora packages).
systemd_base_ensure() {
  podman image exists "$SYSTEMD_BASE_IMAGE" && return 0
  echo "Building $SYSTEMD_BASE_IMAGE..."
  podman build -t "$SYSTEMD_BASE_IMAGE" --build-arg "FEDORA_RELEASE=$OMEDORA_FEDORA_RELEASE" \
    -f "$REPO/omedora/test/fedora/omedora-session/Dockerfile.base" \
    "$REPO/omedora/test/fedora/omedora-session"
}

# systemd_container_run <name> [podman run args...] — replace any container of
# that name with a fresh boot of the base image. SELinux confinement is
# disabled as in build-session.sh: confined, systemd's sandboxed services
# cannot mount their /proc and cgroupfs namespaces.
systemd_container_run() {
  local name="$1"
  shift
  podman rm -f "$name" >/dev/null 2>&1 || true
  podman run -d --name "$name" --systemd=always --security-opt label=disable \
    "$@" "$SYSTEMD_BASE_IMAGE" >/dev/null
}

# systemd_container_wait <name> — block until systemd settles and the omedora
# user manager is up (it starts at boot through lingering).
systemd_container_wait() {
  local name="$1" i state=""
  for (( i = 0; i < 120; i++ )); do
    state=$(podman exec "$name" systemctl is-system-running 2>/dev/null || true)
    [[ $state == "running" || $state == "degraded" ]] && break
    sleep 1
  done
  if [[ $state != "running" && $state != "degraded" ]]; then
    echo "systemd never settled in $name (last: ${state:-none})" >&2
    return 1
  fi
  for (( i = 0; i < 60; i++ )); do
    [[ $(podman exec "$name" systemctl is-active user@1000.service 2>/dev/null || true) == "active" ]] &&
      return 0
    sleep 1
  done
  echo "user@1000.service never became active in $name" >&2
  return 1
}

# systemd_container_wait_stopped <name> — block until the container's PID 1 has
# exited (a reboot requested inside it stops the container).
systemd_container_wait_stopped() {
  local name="$1" i
  for (( i = 0; i < 120; i++ )); do
    [[ $(podman inspect -f '{{.State.Running}}' "$name" 2>/dev/null) == "false" ]] && return 0
    sleep 1
  done
  echo "$name did not stop after the reboot request" >&2
  return 1
}
