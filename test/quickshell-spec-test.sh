#!/bin/bash
#
# L1 static guard for the vendored Quickshell release Omarchy ships.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SPEC="$ROOT/omedora/packaging/copr/quickshell.spec"
SOURCES="$ROOT/omedora/packaging/copr/quickshell.spec.sources"
TAG_COMMIT=4f508be500dea6e5732cc3d50382a0048b17e7b1
VERSION=0.3.2
SHA256=946a27e2a276917a03c1079e5c60971af84ece73088c3661dee455d92eb420f7

assert_file_exists "quickshell.spec exists" "$SPEC"
assert_file_exists "quickshell.spec.sources exists" "$SOURCES"

grep -qF "%global tag_commit $TAG_COMMIT" "$SPEC" \
  && pass "spec records the exact release tag commit" \
  || fail "spec records the exact release tag commit"
actual_version=$(awk '/^Version:/ {print $2; exit}' "$SPEC")
assert_equals "release RPM version is exact" "$actual_version" "$VERSION"
grep -qF 'Source0:            https://codeload.github.com/quickshell-mirror/quickshell/tar.gz/refs/tags/v%{version}#/%{name}-%{version}.tar.gz' "$SPEC" \
  && pass "Source0 is the immutable tag archive" \
  || fail "Source0 is the immutable tag archive"
grep -qF '%autosetup -p1' "$SPEC" \
  && pass "archive root follows the release tag" \
  || fail "archive root follows the release tag"
grep -qF -- '-DGIT_REVISION=%{tag_commit}' "$SPEC" \
  && pass "binary revision reports the tag commit" \
  || fail "binary revision reports the tag commit"
grep -qF -- '-DCRASH_HANDLER=OFF' "$SPEC" \
  && pass "unavailable cpptrace crash handler stays disabled" \
  || fail "unavailable cpptrace crash handler stays disabled"
if grep -qF -- '-DVENDOR_CPPTRACE=ON' "$SPEC"; then
  fail "spec does not enable network-fetching cpptrace vendoring"
else
  pass "spec does not enable network-fetching cpptrace vendoring"
fi

pin_hash=$(awk 'NF && $1 !~ /^#/ {print $1; exit}' "$SOURCES")
pin_file=$(awk 'NF && $1 !~ /^#/ {print $2; exit}' "$SOURCES")
assert_equals "release archive has the verified checksum" "$pin_hash" "$SHA256"
assert_equals "source pin matches the renamed archive" "$pin_file" "quickshell-$VERSION.tar.gz"
if grep -qF '5229069b0f1d375f34b0a04a4e6a69156e2f010995d9ec5a943793424e589b5d' "$SOURCES"; then
  fail "stale 0.3.0 release checksum is absent"
else
  pass "stale 0.3.0 release checksum is absent"
fi

echo "# all quickshell-spec tests passed"
