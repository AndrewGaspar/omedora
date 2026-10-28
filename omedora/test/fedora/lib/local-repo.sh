# shellcheck shell=bash disable=SC2034  # sourced: the caller uses these
# Host-side helper: the locally built RPM repo that the --local-repo modes of
# the L3 smoke and the L4 session build install Omedora from.
#
# Sourced (never executed) after lib/release.sh, with $REPO set to the
# checkout root. The repo is build-repo.sh's per-release output:
#
#   omedora/packaging/copr/repo/       Fedora 44
#   omedora/packaging/copr/repo-f<N>/  any other OMEDORA_FEDORA_RELEASE
#
# OMEDORA_LOCAL_REPO_DIR overrides the directory outright.
#
# The repo OVERLAYS the live COPR: lib/local-repo-overlay.sh (run as root in
# the test container) writes /etc/yum.repos.d/omedora-local.repo at
# priority=1, so every package the local repo holds wins over the COPR, and
# enables the COPR itself for the rest of the stack (Hyprland, Quickshell,
# uwsm, ...). That is why building only the two core specs is enough:
#
#   omedora/packaging/copr/build-repo.sh omedora-settings.spec omedora.spec
#
# OMEDORA_LOCAL_REPO_ONLY=1 skips the COPR enable, so the local repo must hold
# the whole published set (a Fedora release the COPR does not build yet).
#
# The core RPMs package `git archive HEAD` (build-local.sh's self-source mode),
# so they are current only while they carry HEAD's release stamp
# (...git<sha7>.fc<N>). local_repo_core_status checks exactly that.

OMEDORA_LOCAL_REPO_DIR="${OMEDORA_LOCAL_REPO_DIR:-$REPO/omedora/packaging/copr/repo$OMEDORA_RELEASE_SUFFIX}"
# The self-source specs, in build-repo.sh's order (settings first: omedora
# Requires it).
OMEDORA_LOCAL_REPO_CORE_SPECS=(omedora-settings.spec omedora.spec)

# local_repo_head_tag — the "git<sha7>" part of HEAD's self-source Release
# stamp (computed exactly as build-local.sh and .copr/srpm.sh do).
local_repo_head_tag() {
  printf 'git%s\n' "$(git -C "$REPO" rev-parse --short=7 HEAD)"
}

# local_repo_core_status — succeed when the local repo has metadata and exactly
# one omedora and one omedora-settings RPM, both built from HEAD. Otherwise
# print why to stdout and fail.
local_repo_core_status() {
  local tag pkg rpms
  tag=$(local_repo_head_tag)
  if [[ ! -f $OMEDORA_LOCAL_REPO_DIR/repodata/repomd.xml ]]; then
    echo "no local repo at $OMEDORA_LOCAL_REPO_DIR"
    return 1
  fi
  for pkg in omedora omedora-settings; do
    rpms=()
    for rpm in "$OMEDORA_LOCAL_REPO_DIR/$pkg"-[0-9]*.rpm; do
      [[ -e $rpm ]] && rpms+=("${rpm##*/}")
    done
    if (( ${#rpms[@]} == 0 )); then
      echo "$pkg is not in $OMEDORA_LOCAL_REPO_DIR"
      return 1
    fi
    if (( ${#rpms[@]} > 1 )); then
      echo "$OMEDORA_LOCAL_REPO_DIR holds ${#rpms[@]} $pkg builds (${rpms[*]})"
      return 1
    fi
    if [[ ${rpms[0]} != *"$tag".* ]]; then
      echo "${rpms[0]} was not built from HEAD ($tag)"
      return 1
    fi
  done
}

# local_repo_build_core [--force] — build the core RPMs from HEAD into the
# local repo (noarch, about two minutes; never the C++ stack).
local_repo_build_core() {
  "$REPO/omedora/packaging/copr/build-repo.sh" "$@" "${OMEDORA_LOCAL_REPO_CORE_SPECS[@]}"
}

# local_repo_warn_dirty — the core RPMs package HEAD, so uncommitted changes
# never reach them. Say so instead of letting a run look like it tested them.
local_repo_warn_dirty() {
  if [[ -n $(git -C "$REPO" status --porcelain --untracked-files=no 2>/dev/null) ]]; then
    echo "warning: the checkout has uncommitted changes; the local core RPMs package HEAD ($(local_repo_head_tag)), not the working tree" >&2
  fi
}
