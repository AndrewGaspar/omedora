#!/bin/bash
#
# L1 static guard for the Quickshell snapshot required by Omarchy 4 beta.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SPEC="$ROOT/omedora/packaging/copr/quickshell.spec"
SOURCES="$ROOT/omedora/packaging/copr/quickshell.spec.sources"
COMMIT=28771c7c74b42e20afca0b1b63980cb46515537c
VERSION=0.3.0^20.git28771c7
SHA256=dd938be236aab261597dd2fcf416aa09f16a285ca45dd19e80216695f787f907

assert_file_exists "quickshell.spec exists" "$SPEC"
assert_file_exists "quickshell.spec.sources exists" "$SOURCES"

grep -qF "%global commit $COMMIT" "$SPEC" \
  && pass "spec pins Omarchy beta's exact Quickshell commit" \
  || fail "spec pins Omarchy beta's exact Quickshell commit"
actual_version=$(awk '/^Version:/ {print $2; exit}' "$SPEC")
assert_equals "snapshot RPM version is exact" "$actual_version" "$VERSION"
grep -qF 'Source0:            https://codeload.github.com/quickshell-mirror/quickshell/tar.gz/%{commit}#/%{name}-%{version}.tar.gz' "$SPEC" \
  && pass "Source0 is the immutable commit archive" \
  || fail "Source0 is the immutable commit archive"
grep -qF '%autosetup -n %{name}-%{commit} -p1' "$SPEC" \
  && pass "archive root follows the pinned commit" \
  || fail "archive root follows the pinned commit"
grep -qF -- '-DGIT_REVISION=%{commit}' "$SPEC" \
  && pass "binary revision reports the pinned commit" \
  || fail "binary revision reports the pinned commit"
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
assert_equals "snapshot archive has the verified checksum" "$pin_hash" "$SHA256"
assert_equals "source pin matches the renamed archive" "$pin_file" "quickshell-$VERSION.tar.gz"
if grep -qF '5229069b0f1d375f34b0a04a4e6a69156e2f010995d9ec5a943793424e589b5d' "$SOURCES"; then
  fail "stale 0.3.0 release checksum is absent"
else
  pass "stale 0.3.0 release checksum is absent"
fi

echo "# all quickshell-spec tests passed"
