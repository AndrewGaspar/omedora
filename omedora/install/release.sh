# Omedora release-support gate — the FIRST thing plan.sh does, so an install
# on a Fedora release Omedora doesn't build for stops before the plan is
# computed and before anything is changed (no repo enabled, no package
# installed, no config written).
#
# Supported releases are the ones the version-scoped Omedora COPR has a
# chroot for (Fedora N and N-1; see omedora/versioning.md). Without a chroot,
# repos.sh's `dnf copr enable` fails AFTER the plan gate, half-way through the
# install — this gate turns that into a clear refusal up front.
#
# Outcomes of `omedora-copr --chroot-available` (running VERSION_ID):
#   0  supported                  -> continue
#   1  no chroot for this release -> refuse (exit 1), nothing changed
#   2  couldn't check             -> warn and continue. The probe is a
#      courtesy, not the authority: an unreachable COPR API (or a host without
#      curl/python3) must not become a new hard install requirement, and if
#      the COPR really is unreachable, repos.sh's `dnf copr enable` fails next
#      with dnf's own error — before any Omedora package lands.
#
# Skipped when the harness injected /etc/yum.repos.d/omedora-local.repo (the
# same precedent repos.sh follows: the local overlay replaces the COPR).
#
# Env:
#   OMEDORA_ALLOW_UNSUPPORTED_RELEASE=1  warn instead of refusing (testing a
#                                        pre-release Fedora with your own repos)
# Test seams:
#   OMEDORA_COPR_CMD         probe command (default bin/omedora-copr)
#   OMEDORA_OS_RELEASE       os-release file (default /etc/os-release)
#   OMEDORA_LOCAL_REPO_FILE  injected local repo (default
#                            /etc/yum.repos.d/omedora-local.repo)
#
# Sourced (by plan.sh, into install-4.sh's `set -eEo pipefail` shell):
# deliberately no set -e/+e here, and every command is written not to abort.

OMEDORA_REPO_ROOT="${OMEDORA_REPO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}"

release_os_file="${OMEDORA_OS_RELEASE:-/etc/os-release}"
release_version="$( . "$release_os_file" 2>/dev/null && printf '%s' "${VERSION_ID:-}" || true)"
release_local_repo="${OMEDORA_LOCAL_REPO_FILE:-/etc/yum.repos.d/omedora-local.repo}"
if [[ -n ${OMEDORA_COPR_CMD:-} ]]; then
  read -r -a release_copr_cmd <<<"$OMEDORA_COPR_CMD"
else
  release_copr_cmd=("$OMEDORA_REPO_ROOT/bin/omedora-copr")
fi

# Relay the probe's own explanation (e.g. which releases ARE supported).
release_relay_err() {
  if [[ -n $release_err ]]; then printf '  %s\n' "$release_err" >&2; fi
  return 0
}

if [[ -f $release_local_repo ]]; then
  echo "Omedora: local test repo present ($release_local_repo); skipping the COPR release check."
else
  release_rc=0
  release_err="$("${release_copr_cmd[@]}" --chroot-available 2>&1 >/dev/null)" || release_rc=$?
  release_project="$("${release_copr_cmd[@]}" 2>/dev/null || true)"
  [[ -n $release_project ]] || release_project="the Omedora COPR"

  case "$release_rc" in
    0)
      echo "Omedora: Fedora ${release_version:-?} is supported ($release_project builds for it)."
      ;;
    1)
      if [[ -n ${OMEDORA_ALLOW_UNSUPPORTED_RELEASE:-} ]]; then
        echo -e "\e[33mOmedora: Fedora ${release_version:-?} is not supported ($release_project has no builds for it), but OMEDORA_ALLOW_UNSUPPORTED_RELEASE is set; continuing. Expect the COPR step to fail unless you provide the packages yourself.\e[0m" >&2
        release_relay_err
      else
        echo -e "\e[31mOmedora doesn't support Fedora ${release_version:-?} yet: $release_project has no packages built for it.\e[0m" >&2
        release_relay_err
        echo "  Omedora supports the Fedora releases its COPR builds for (normally the" >&2
        echo "  current release and the one before it). Install on one of those releases," >&2
        echo "  or wait until Omedora adds Fedora ${release_version:-?} and re-run the installer." >&2
        echo "  (Testing a pre-release Fedora with your own repos? Set" >&2
        echo "  OMEDORA_ALLOW_UNSUPPORTED_RELEASE=1 to skip this check.)" >&2
        echo -e "\e[31mAborting; nothing was changed.\e[0m" >&2
        exit 1
      fi
      ;;
    *)
      echo -e "\e[33mOmedora: couldn't verify that $release_project builds for Fedora ${release_version:-?}; continuing. If it doesn't, enabling the COPR will fail before any Omedora package is installed.\e[0m" >&2
      release_relay_err
      ;;
  esac
fi

# Leave a zero status for the sourcing shell (set -e there).
true
