#!/bin/bash
#
# Point dnf at a locally built Omedora RPM repo — runs as root INSIDE a Fedora
# test container, before the Omedora bootstrap. Shared by the --local-repo
# modes of the L3 smoke (smoke.sh, update-verify.sh) and the L4 session build
# (build-session.sh); the host side lives in lib/local-repo.sh.
#
#   local-repo-overlay.sh <repo-dir> [<copr-project>]
#
# Writes /etc/yum.repos.d/omedora-local.repo at priority=1, so every package in
# <repo-dir> wins over any other repo whatever its version, then enables the
# live Omedora COPR for the packages the local repo does not hold.
# <copr-project> defaults to bin/omedora-copr of the tree this script is in;
# pass it when the script is piped in (`bash -s -- <dir> <project>`).
#
# The bootstrap then sees omedora-local.repo, so plan.sh discloses "omedora
# local test repo", release.sh skips the COPR release probe and repos.sh skips
# its own COPR enable.
#
# OMEDORA_LOCAL_REPO_ONLY=1 skips the COPR enable: the local repo then has to
# hold the whole published set.

set -euo pipefail

repo_dir="${1:?usage: local-repo-overlay.sh <repo-dir> [<copr-project>]}"
copr="${2:-}"

if [[ ! -f $repo_dir/repodata/repomd.xml ]]; then
  echo "local-repo-overlay: no repo metadata at $repo_dir/repodata/repomd.xml" >&2
  exit 1
fi

cat >/etc/yum.repos.d/omedora-local.repo <<EOF
[omedora-local]
name=Omedora local packages (test overlay)
baseurl=file://$repo_dir
enabled=1
gpgcheck=0
priority=1
EOF
echo "local-repo-overlay: omedora-local -> $repo_dir (priority 1):"
find "$repo_dir" -maxdepth 1 -name '*.rpm' -printf '  %f\n' | sort

if [[ ${OMEDORA_LOCAL_REPO_ONLY:-} == "1" ]]; then
  echo "local-repo-overlay: OMEDORA_LOCAL_REPO_ONLY=1, not enabling the COPR"
else
  if [[ -z $copr ]]; then
    copr=$(OMARCHY_PATH='' "$(dirname -- "${BASH_SOURCE[0]}")/../../../../bin/omedora-copr")
  fi
  echo "local-repo-overlay: enabling $copr for everything else"
  dnf -y copr enable "$copr" >/dev/null
fi
