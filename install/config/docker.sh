# omedora: Fedora dispatches to the docker-fedora.sh sibling (group add +
# only-if-absent daemon.json apply); the Arch body below is byte-identical to
# upstream. See omedora/architecture.md §"Omarchy 4 setup-system gating map".
if [[ "${OMARCHY_DISTRO:-$(omarchy-distro 2>/dev/null || echo arch)}" == "fedora" ]]; then
  source "${BASH_SOURCE[0]%/*}/docker-fedora.sh"
  return 0 2>/dev/null || exit 0
fi

# The Docker daemon runs as root and its socket is root-owned, so membership in
# the docker group is equivalent to passwordless root: any process in it can
# `docker run -v /:/host` and rewrite the host as root. We therefore do NOT add
# the install user to the docker group by default, so a single rogue process
# running as the user cannot silently escalate to root.
#
# The daemon is still enabled (docker.socket, in enable-services.sh) for system
# use. The Docker TUI (Super + Shift + D) and the Windows VM reach it through a
# polkit prompt, and the plain `docker` CLI runs under sudo. Users who want the
# convenience back can opt in, behind a warning, with:
#
#   omarchy-setup-security-sudoless-docker   (Setup > Security > Sudoless Docker)
#
# Nothing to do here now that the group is no longer granted, but the file stays
# as the recorded home of this decision and a hook for future daemon config.
:
