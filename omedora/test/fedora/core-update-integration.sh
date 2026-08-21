#!/bin/bash

# Real dnf5 regression coverage for exact core candidate selection and
# provenance repair. Run as root inside the Fedora 44 L2 image.

set -euo pipefail

REPO=${REPO:-/repo}
. "$REPO/test/helpers.sh"

work_dir=$(mktemp -d /tmp/omedora-core-update.XXXXXX)
expected_repo=omedora-test-expected
foreign_high_repo=omedora-test-foreign-high
foreign_same_repo=omedora-test-foreign-same

cleanup() {
  rm -f \
    "/etc/yum.repos.d/$expected_repo.repo" \
    "/etc/yum.repos.d/$foreign_high_repo.repo" \
    "/etc/yum.repos.d/$foreign_same_repo.repo"
  dnf remove -y omedora-test-managed omedora-settings omedora >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

build_rpm() {
  local name=$1 version=$2 destination=$3 requirement=${4:-}
  local topdir="$work_dir/build-$name-$version-${destination##*/}"
  mkdir -p "$topdir"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

  cat >"$topdir/SPECS/$name.spec" <<EOF
Name: $name
Version: $version
Release: 1
Summary: Omedora core update integration fixture
License: MIT
BuildArch: noarch
${requirement:+Requires: $requirement}

%description
Omedora core update integration fixture.

%install
mkdir -p %{buildroot}/usr/share/omedora-test-rpms
printf '%s\n' '$destination' >%{buildroot}/usr/share/omedora-test-rpms/$name.txt

%files
/usr/share/omedora-test-rpms/$name.txt
EOF

  rpmbuild -bb --define "_topdir $topdir" "$topdir/SPECS/$name.spec" \
    >/dev/null 2>&1
  cp "$topdir"/RPMS/noarch/*.rpm "$destination/"
}

write_repo() {
  local repo_id=$1 path=$2 enabled=$3
  cat >"/etc/yum.repos.d/$repo_id.repo" <<EOF
[$repo_id]
name=$repo_id
baseurl=file://$path
enabled=$enabled
gpgcheck=0
EOF
}

set_repo_enabled() {
  local repo_id=$1 enabled=$2
  sed -i "s/^enabled=.*/enabled=$enabled/" "/etc/yum.repos.d/$repo_id.repo"
}

installed_evr() {
  rpm -q --qf '%{EVR}' "$1"
}

installed_repo() {
  dnf repoquery --installed --qf '%{from_repo}\n' "$1"
}

assert_core_identity() {
  local description=$1
  assert_equals "$description: omedora EVR" "$(installed_evr omedora)" "2.0-1"
  assert_equals "$description: omedora-settings EVR" \
    "$(installed_evr omedora-settings)" "2.0-1"
  assert_equals "$description: omedora provenance" \
    "$(installed_repo omedora)" "$expected_repo"
  assert_equals "$description: omedora-settings provenance" \
    "$(installed_repo omedora-settings)" "$expected_repo"
}

expected_dir="$work_dir/$expected_repo"
foreign_high_dir="$work_dir/$foreign_high_repo"
foreign_same_dir="$work_dir/$foreign_same_repo"
local_dir="$work_dir/local"
mkdir -p "$expected_dir" "$foreign_high_dir" "$foreign_same_dir" "$local_dir"

for version in 1.0 2.0; do
  build_rpm omedora "$version" "$expected_dir"
  build_rpm omedora-settings "$version" "$expected_dir"
done
build_rpm omedora-test-managed 1.0 "$expected_dir" "omedora >= 2.0"

build_rpm omedora 3.0 "$foreign_high_dir"
build_rpm omedora-settings 3.0 "$foreign_high_dir"
build_rpm omedora-test-managed 2.0 "$foreign_high_dir" "omedora >= 3.0"

build_rpm omedora 2.0 "$foreign_same_dir"
build_rpm omedora-settings 2.0 "$foreign_same_dir"
build_rpm omedora 4.0 "$local_dir"
build_rpm omedora-settings 4.0 "$local_dir"

createrepo_c "$expected_dir" >/dev/null
createrepo_c "$foreign_high_dir" >/dev/null
createrepo_c "$foreign_same_dir" >/dev/null
write_repo "$expected_repo" "$expected_dir" 1
write_repo "$foreign_high_repo" "$foreign_high_dir" 1
write_repo "$foreign_same_repo" "$foreign_same_dir" 0

cat >"$work_dir/resolver-core" <<'EOF'
#!/bin/bash
printf 'omedora\nomedora-settings\n'
EOF
cat >"$work_dir/resolver-managed" <<'EOF'
#!/bin/bash
printf 'omedora\nomedora-settings\nomedora-test-managed\n'
EOF
cat >"$work_dir/dnf" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >>'$work_dir/dnf.log'
if [[ \${1:-} == "copr" && \${2:-} == "enable" ]]; then
  exit 0
fi
exec /usr/bin/dnf "\$@"
EOF
chmod +x "$work_dir/resolver-core" "$work_dir/resolver-managed" "$work_dir/dnf"

run_updater() {
  OMEDORA_MANAGED_RESOLVER="$1" \
    OMEDORA_DNF_CMD="$work_dir/dnf" \
    OMEDORA_COPR_PROJECT="fixture/expected" \
    OMEDORA_COPR_REPO_ID="$expected_repo" \
    "$REPO/bin/fedora/update-system-pkgs"
}

echo "=== Real dnf5 exact core selection ==="
dnf install -y --from-repo="$expected_repo" \
  omedora-0:1.0-1.noarch omedora-settings-0:1.0-1.noarch >/dev/null
assert_equals "historical expected omedora build installed" "$(installed_evr omedora)" "1.0-1"
assert_equals "higher foreign omedora candidate is available" \
  "$(dnf repoquery --available --repo "$foreign_high_repo" --latest-limit=1 --qf '%{evr}\n' omedora)" \
  "3.0-1"
: >"$work_dir/dnf.log"
run_updater "$work_dir/resolver-core" >/tmp/core-update-old.out 2>&1
assert_core_identity "old expected build plus higher foreign candidate"
core_transaction=$(grep '^install .*omedora-0:2.0-1.noarch' "$work_dir/dnf.log")
assert_output_contains "real core transaction selects exact expected NEVRA" \
  "$core_transaction" "omedora-0:2.0-1.noarch"
assert_output_contains "real core transaction uses dnf5 source constraint" \
  "$core_transaction" "--from-repo=$expected_repo"

echo "=== Real dnf5 same-EVR provenance repair ==="
set_repo_enabled "$foreign_high_repo" 0
set_repo_enabled "$foreign_same_repo" 1
dnf reinstall -y --from-repo="$foreign_same_repo" \
  omedora-0:2.0-1.noarch omedora-settings-0:2.0-1.noarch >/dev/null
assert_equals "same-EVR foreign omedora provenance installed" \
  "$(installed_repo omedora)" "$foreign_same_repo"
: >"$work_dir/dnf.log"
run_updater "$work_dir/resolver-core" >/tmp/core-update-same.out 2>&1
assert_core_identity "same-EVR foreign repair"
assert_output_contains "same-EVR foreign package uses constrained reinstall" \
  "$(grep '^reinstall ' "$work_dir/dnf.log")" "--from-repo=$expected_repo"

echo "=== Real dnf5 locally newer downgrade ==="
dnf install -y "$local_dir"/omedora-4.0-1.noarch.rpm \
  "$local_dir"/omedora-settings-4.0-1.noarch.rpm >/dev/null
assert_equals "locally newer omedora build installed" "$(installed_evr omedora)" "4.0-1"
if [[ $(installed_repo omedora) == "$expected_repo" ]]; then
  fail "locally newer fixture has non-expected provenance"
else
  pass "locally newer fixture has non-expected provenance"
fi
: >"$work_dir/dnf.log"
run_updater "$work_dir/resolver-core" >/tmp/core-update-local.out 2>&1
assert_core_identity "locally newer build reconciliation"
assert_output_contains "locally newer core transaction explicitly allows downgrade" \
  "$(grep '^install .*omedora-0:2.0-1.noarch' "$work_dir/dnf.log")" \
  "--allow-downgrade"

echo "=== Real dnf5 broad transaction cannot replace core ==="
dnf install -y --from-repo="$expected_repo" omedora-test-managed-0:1.0-1.noarch >/dev/null
set_repo_enabled "$foreign_same_repo" 0
set_repo_enabled "$foreign_high_repo" 1
: >"$work_dir/dnf.log"
run_updater "$work_dir/resolver-managed" >/tmp/core-update-managed.out 2>&1 || true
assert_core_identity "broad managed transaction protection"
broad_transaction=$(grep '^install .*omedora-test-managed' "$work_dir/dnf.log" | tail -1)
assert_output_contains "real broad transaction excludes omedora" \
  "$broad_transaction" "--exclude=omedora"
assert_output_contains "real broad transaction excludes omedora-settings" \
  "$broad_transaction" "--exclude=omedora-settings"
assert_equals "foreign managed dependency cannot replace expected core" \
  "$(installed_evr omedora)" "2.0-1"

echo "=== Real dnf5 core update integration passed ==="
