#!/bin/bash
#
# L3 package-backed beta.1 -> beta.2 upgrade verification. Run inside the
# Fedora 44 test image after beta.2 is available from the Omedora 4 COPR (or an
# injected repo with the same repo ID).
#
# beta.1's installed `omedora update` still contains the old unscoped dnf
# transaction. This test deliberately never invokes it. It first upgrades only
# the two core RPMs, proves beta.2 code is installed, and only then invokes the
# new managed-package updater.
#
# Optional seams:
#   OMEDORA_BETA1_PACKAGES  beta.1 package specs available from the Omedora COPR
#   OMEDORA_BETA1_VERSION   expected installed RPM version
#   OMEDORA_TARGET_VERSION  expected beta.2 RPM version

set -euo pipefail

REPO=${REPO:-/repo}
BETA1_VERSION=${OMEDORA_BETA1_VERSION:-0.2.0~beta.1}
TARGET_VERSION=${OMEDORA_TARGET_VERSION:-0.2.0~beta.2}
read -r -a beta1_packages <<<"${OMEDORA_BETA1_PACKAGES:-omedora-$BETA1_VERSION omedora-settings-$BETA1_VERSION}"

copr_project=$(OMARCHY_PATH="$REPO" "$REPO/bin/omedora-copr")
copr_repo_id=$(OMARCHY_PATH="$REPO" "$REPO/bin/omedora-copr" --repo-id)

dnf -y copr enable "$copr_project"
dnf install -y --setopt=install_weak_deps=False --from-repo="$copr_repo_id" \
  "${beta1_packages[@]}"

for package in omedora omedora-settings; do
  actual=$(rpm -q --qf '%{VERSION}' "$package")
  [[ $actual == "$BETA1_VERSION" ]] || {
    echo "expected $package beta.1 version $BETA1_VERSION, got $actual" >&2
    exit 1
  }
  from_repo=$(dnf repoquery --installed --qf '%{from_repo}\n' "$package")
  [[ $from_repo == "$copr_repo_id" ]] || {
    echo "expected installed beta.1 $package from $copr_repo_id, got $from_repo" >&2
    exit 1
  }
done
installed_beta_identity=$(rpm -q --qf '%{NAME} %{EVR} %{ARCH}\n' omedora omedora-settings)
echo "installed beta.1 identity:"
printf '%s\n' "$installed_beta_identity"

# Hold a deterministic Fedora-release RPM below its updates-repo candidate.
# This proves neither the scoped bootstrap nor the new managed updater broadens
# into a whole-system update.
unrelated_package=3proxy
unrelated_old_spec=$(dnf repoquery --available --repo fedora --arch=x86_64 \
  --latest-limit=1 --qf '%{full_nevra}\n' "$unrelated_package")
unrelated_new_evr=$(dnf repoquery --available --repo updates --arch=x86_64 \
  --latest-limit=1 --qf '%{evr}\n' "$unrelated_package")
[[ -n $unrelated_old_spec && -n $unrelated_new_evr ]] || {
  echo "could not resolve old/new $unrelated_package fixtures" >&2
  exit 1
}
dnf install -y --from-repo=fedora "$unrelated_old_spec"
unrelated_old_evr=$(rpm -q --qf '%{EVR}' "$unrelated_package")
[[ $unrelated_old_evr != "$unrelated_new_evr" ]] || {
  echo "$unrelated_package fixture is not outdated" >&2
  exit 1
}
dnf repoquery --upgrades --qf '%{name} %{evr}\n' "$unrelated_package" \
  | grep -qx "$unrelated_package $unrelated_new_evr"

for package in omedora omedora-settings; do
  if ! dnf repoquery --available --repo "$copr_repo_id" --qf '%{name} %{version}\n' "$package" \
    | awk -v package="$package" -v version="$TARGET_VERSION" \
      '$1 == package && $2 == version { found = 1 } END { exit !found }'; then
    echo "$package $TARGET_VERSION is unavailable from $copr_repo_id" >&2
    exit 1
  fi
done

# This is the one-time bootstrap users must run before their first beta.2
# `omedora update`. It is scoped to the core RPMs, never the whole Fedora host.
dnf upgrade --refresh -y --setopt=install_weak_deps=False \
  --from-repo="$copr_repo_id" omedora omedora-settings

for package in omedora omedora-settings; do
  actual=$(rpm -q --qf '%{VERSION}' "$package")
  from_repo=$(dnf repoquery --installed --qf '%{from_repo}\n' "$package")
  [[ $actual == "$TARGET_VERSION" && $from_repo == "$copr_repo_id" ]] || {
    echo "scoped bootstrap did not install $package $TARGET_VERSION from $copr_repo_id (got $actual from $from_repo)" >&2
    exit 1
  }
done
[[ $(rpm -q --qf '%{EVR}' "$unrelated_package") == "$unrelated_old_evr" ]] || {
  echo "scoped core bootstrap unexpectedly updated $unrelated_package" >&2
  exit 1
}
echo "scoped core bootstrap installed beta.2 before the normal updater"

su omedora -c "timeout 1800 omedora update -y" >/tmp/beta1-to-beta2-update.log 2>&1 || {
  tail -40 /tmp/beta1-to-beta2-update.log >&2
  exit 1
}

for package in omedora omedora-settings; do
  actual=$(rpm -q --qf '%{VERSION}' "$package")
  from_repo=$(dnf repoquery --installed --qf '%{from_repo}\n' "$package")
  [[ $actual == "$TARGET_VERSION" && $from_repo == "$copr_repo_id" ]] || {
    echo "post-update $package identity mismatch: $actual from $from_repo" >&2
    exit 1
  }
done
[[ $(rpm -q --qf '%{EVR}' "$unrelated_package") == "$unrelated_old_evr" ]] || {
  echo "managed updater unexpectedly updated unrelated $unrelated_package" >&2
  exit 1
}
dnf repoquery --upgrades --qf '%{name} %{evr}\n' "$unrelated_package" \
  | grep -qx "$unrelated_package $unrelated_new_evr"

echo "# beta.1 -> beta.2 scoped bootstrap verification: ALL GREEN"
