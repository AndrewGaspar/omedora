#!/bin/bash
#
# L1 static guard for the vendored Quickshell snapshot Omarchy ships.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SPEC="$ROOT/omedora/packaging/copr/quickshell.spec"
SOURCES="$ROOT/omedora/packaging/copr/quickshell.spec.sources"
PATCH="$ROOT/omedora/packaging/copr/quickshell-load-qtquick-611.patch"
# The upstream commit Omarchy's quickshell package pins (0.3.2.r7.g2b4501a).
COMMIT=2b4501a282689792b62e94f3fb30d8f512324fe6
VERSION='0.3.2^%{snapshot}.git%{shortcommit}'
SHA256=e09495c73f8bfbb8637a28e6d73bf84063631b49bb3cb6d3c9702c80dfa78f31
# omarchy-pkgs pkgbuilds/quickshell/load_qtquick_611.patch
PATCH_SHA256=23b65d205d825f11a1cd8501acbc6e50250d09a6ce607e2ff8b3cf5d438bd0ce

assert_file_exists "quickshell.spec exists" "$SPEC"
assert_file_exists "quickshell.spec.sources exists" "$SOURCES"
assert_file_exists "Omarchy's Qt 6.11 load patch is shipped" "$PATCH"

grep -qF "%global commit $COMMIT" "$SPEC" \
  && pass "spec records Omarchy's exact upstream commit" \
  || fail "spec records Omarchy's exact upstream commit"
actual_version=$(awk '/^Version:/ {print $2; exit}' "$SPEC")
assert_equals "snapshot RPM version sorts after the 0.3.2 release" "$actual_version" "$VERSION"
grep -qF 'Source0:            https://codeload.github.com/quickshell-mirror/quickshell/tar.gz/%{commit}#/%{name}-%{commit}.tar.gz' "$SPEC" \
  && pass "Source0 is the immutable commit archive" \
  || fail "Source0 is the immutable commit archive"
grep -qF '%autosetup -p1 -n %{name}-%{commit}' "$SPEC" \
  && pass "archive root follows the commit" \
  || fail "archive root follows the commit"
grep -qxF 'Patch0:             quickshell-load-qtquick-611.patch' "$SPEC" \
  && pass "spec applies the load patch by its literal name" \
  || fail "spec applies the load patch by its literal name"
assert_equals "load patch is byte-identical to Omarchy's" "$(sha256sum "$PATCH" | cut -d' ' -f1)" "$PATCH_SHA256"
if grep -qxF '//@ pragma OmarchyLoadPatch' "$ROOT/shell/shell.qml"; then
  pass "shell.qml still declares the pragma the patch acts on"
else
  fail "shell.qml still declares the pragma the patch acts on (drop the patch if Omarchy did)"
fi
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
assert_equals "commit archive has the verified checksum" "$pin_hash" "$SHA256"
assert_equals "source pin matches the renamed archive" "$pin_file" "quickshell-$COMMIT.tar.gz"
if grep -qF '946a27e2a276917a03c1079e5c60971af84ece73088c3661dee455d92eb420f7' "$SOURCES"; then
  fail "stale 0.3.2 release checksum is absent"
else
  pass "stale 0.3.2 release checksum is absent"
fi

echo "# all quickshell-spec tests passed"
