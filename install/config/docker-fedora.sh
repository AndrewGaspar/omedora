# Fedora sibling of install/config/docker.sh (dispatched from its top gate;
# runs as root under omarchy-setup-system).
#
# Mirrors upstream's docker-group add, plus applies omedora's docker daemon
# defaults (log rotation etc.) ONLY IF the user has no /etc/docker/daemon.json
# yet. The omedora-settings RPM deliberately does NOT package that file — a
# pre-existing daemon.json (registry mirrors, cgroup opts...) is user config we
# must never clobber; the shipped copy lives as a reference at
# /usr/share/omarchy/etc-overrides/docker/daemon.json. Disclosed at the plan
# gate.

# moby-engine's RPM creates the docker group, but don't depend on package
# install order — the group add must hold regardless.
getent group docker >/dev/null 2>&1 || groupadd -r docker
usermod -aG docker "$OMARCHY_INSTALL_USER"

daemon_ref="${OMARCHY_PATH:-/usr/share/omarchy}/etc-overrides/docker/daemon.json"
if [[ -f $daemon_ref && ! -e /etc/docker/daemon.json ]]; then
  install -Dpm644 "$daemon_ref" /etc/docker/daemon.json
  echo "Applied omedora's /etc/docker/daemon.json (none existed)."
elif [[ -e /etc/docker/daemon.json ]]; then
  echo "Keeping your existing /etc/docker/daemon.json (omedora's reference copy: $daemon_ref)."
fi
