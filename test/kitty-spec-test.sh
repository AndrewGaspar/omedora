#!/bin/bash
#
# L1 static guard for omedora/packaging/copr/kitty.spec (+ .sources).
#
# kitty is Fedora's spec moved to a newer release. COPR builds offline, so the
# Go modules come from a vendor tarball generated in the SRPM step, and the
# built-in shaders need a build-only Slang compiler. This audits the spec text
# so a bump keeps the pins, the signature check, the vendor wiring and the
# "slangc is not shipped" check. Pure bash + grep; no build.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

COPR="$ROOT/omedora/packaging/copr"
SPEC="$COPR/kitty.spec"
SOURCES="$COPR/kitty.spec.sources"

assert_file_exists "kitty.spec exists" "$SPEC"
assert_file_exists "kitty.spec.sources exists" "$SOURCES"
assert_file_exists "go-vendor-tools config exists" "$COPR/kitty-go-vendor-tools.toml"
assert_file_exists "DeprecationWarnings test patch exists" \
  "$COPR/kitty-do-not-treat-DeprecationWarnings-as-errors-in-tests.patch"
assert_file_exists "Python 3.15 refcount test patch exists" \
  "$COPR/kitty-test-refcount-python-3.15.patch"

version=$(sed -n 's/^Version:[[:space:]]*//p' "$SPEC")
slang=$(sed -n 's/^%global slang_version //p' "$SPEC")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  && pass "Version is a release ($version)" || fail "Version is a release"
[[ $slang =~ ^[0-9]{4}\.[0-9]+(\.[0-9]+)?$ ]] \
  && pass "Slang version is pinned ($slang)" || fail "Slang version is pinned"

# --- every remote source is pinned ---------------------------------------------------
awk 'NF { if ($1 !~ /^[0-9a-f]{64}$/ || NF != 2) exit 1 }' "$SOURCES" \
  && pass ".sources has immutable SHA-256 pins" || fail ".sources has immutable SHA-256 pins"
for file in "kitty-$version.tar.xz" "kitty-$version.tar.xz.sig" kovid.gpg kitty.appdata.xml \
  NerdFontsSymbolsOnly.tar.xz "slang-$slang-linux-x86_64-glibc-2.28.tar.gz"; do
  awk -v f="$file" '$2 == f { found = 1 } END { exit !found }' "$SOURCES" \
    && pass "$file is pinned" || fail "$file is pinned"
done
(( $(grep -cE '^Source[0-9]+:[[:space:]]+https?://' "$SPEC") == $(grep -c . "$SOURCES") )) \
  && pass "one pin per remote source" || fail "one pin per remote source"

# --- signature, vendoring, licensing ----------------------------------------------------
grep -qF "%{gpgverify} --keyring='%{SOURCE2}' --signature='%{SOURCE1}' --data='%{SOURCE0}'" "$SPEC" \
  && pass "%prep verifies the tarball signature" || fail "%prep verifies the tarball signature"
grep -qE '^Source3:[[:space:]]+%\{name\}-%\{version\}-go-vendor\.tar\.zst$' "$SPEC" \
  && pass "Source3 is the generated Go vendor tarball" || fail "Source3 is the generated Go vendor tarball"
grep -qF '%autosetup -p1 -a3' "$SPEC" \
  && pass "%prep unpacks the vendor tarball" || fail "%prep unpacks the vendor tarball"
for script in "$ROOT/.copr/srpm.sh" "$COPR/build-local.sh"; do
  grep -qF -- '-go-vendor.tar.*)' "$script" && grep -qF 'go mod vendor' "$script" \
    && pass "${script#$ROOT/} generates Go vendor tarballs" \
    || fail "${script#$ROOT/} generates Go vendor tarballs"
done
grep -qF '%go_vendor_license_check -c %{S:4} %{kitten_license}' "$SPEC" \
  && pass "kitten's license expression is checked" || fail "kitten's license expression is checked"

# --- Slang is build-only --------------------------------------------------------------------
grep -qF 'export SLANGC=%{slang_dir}/bin/slangc' "$SPEC" \
  && grep -qE '^%global slang_dir %\{_builddir\}/' "$SPEC" \
  && pass "the build uses the bundled slangc" || fail "the build uses the bundled slangc"
grep -qF "slang build tool leaked into the payload" "$SPEC" \
  && pass "%check keeps slangc out of the payload" || fail "%check keeps slangc out of the payload"
grep -qE '^ExclusiveArch:[[:space:]]+x86_64$' "$SPEC" \
  && pass "x86_64 only (the prebuilt slangc is)" || fail "x86_64 only"

# --- packaging layout stays Fedora's ----------------------------------------------------------
for sub in terminfo shell-integration kitten doc; do
  grep -qE "^%package[[:space:]]+$sub$" "$SPEC" \
    && pass "ships the $sub subpackage" || fail "ships the $sub subpackage"
done
grep -qF 'Requires:       %{name}-kitten%{?_isa} = %{version}-%{release}' "$SPEC" \
  && pass "kitty requires its own kitten build" || fail "kitty requires its own kitten build"

# --- wiring -------------------------------------------------------------------------------
order=$(sed -n '/^SPECS=(/,/^)/p' "$COPR/build-repo.sh" | sed 's/#.*//' | tr '\n' ' ')
[[ $order == *"kitty.spec"* ]] \
  && pass "build-repo.sh builds kitty" || fail "build-repo.sh builds kitty"
grep -qF '| `kitty` |' "$ROOT/omedora/packages.md" \
  && pass "packages.md documents kitty" || fail "packages.md documents kitty"

echo "# all kitty spec tests passed"
