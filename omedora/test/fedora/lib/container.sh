# Container-side test helpers — sourced by omedora/test/fedora/integration.sh.
# Run only inside the fedora:44 test image; assume /repo is the bind-mounted
# repo and we have real dnf/rpm/flatpak available.
#
# Adds a couple of container-specific assertions on top of test/helpers.sh.

assert_dnf_installed() {
  local description="$1"
  local package="$2"

  if ! rpm -q "$package" >/dev/null 2>&1; then
    rpm -q "$package" >&2 || true
    fail "$description"
  fi

  pass "$description"
}

assert_dnf_not_installed() {
  local description="$1"
  local package="$2"

  if rpm -q "$package" >/dev/null 2>&1; then
    rpm -q "$package" >&2 || true
    fail "$description"
  fi

  pass "$description"
}

assert_copr_enabled() {
  local description="$1"
  local copr="$2"

  # dnf copr list shows enabled COPRs. The repo file at
  # /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:<owner>:<repo>.repo
  # is the on-disk artifact.
  local owner="${copr%/*}"
  local repo="${copr#*/}"
  local repo_file="/etc/yum.repos.d/_copr:copr.fedorainfracloud.org:${owner}:${repo}.repo"

  if [[ ! -f $repo_file ]]; then
    echo "Expected COPR repo file: $repo_file" >&2
    ls /etc/yum.repos.d/ >&2 || true
    fail "$description"
  fi

  pass "$description"
}

ensure_running_as_root() {
  if (( EUID != 0 )); then
    echo "This test must run as root inside the container (got uid $EUID)" >&2
    exit 1
  fi
}
