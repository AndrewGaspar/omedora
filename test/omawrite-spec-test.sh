#!/bin/bash
#
# L1 static guard for omedora/packaging/copr/omawrite.spec (+ .sources).
#
# omawrite is a quattro-line omarchy-family app: a Qt6/QML distraction-free
# Markdown writing app bound to SUPER+SHIFT+W (github.com/omacom-io/omawrite,
# MIT). omedora builds it FROM SOURCE in the COPR as a plain qmake6/Qt6 build —
# no vendoring needed (the %build phase only needs BuildRequires, never the
# network). This audits the spec text so a rebase / edit can't silently drop the
# /usr/bin/omawrite binary, RE-ADD the proprietary iA Writer font dep, or desync
# the source pin. Pure bash + grep; no build.
#
# Asserts:
#   - spec + .sources exist
#   - it is a from-source build (Source0 tag tarball; %build runs bin/build)
#   - %files owns /usr/bin/omawrite (the exact name the SUPER+SHIFT+W keybind runs)
#   - it does NOT Require the proprietary ttf-ia-writer font (skip-mapped in
#     omedora; Qt substitutes a fallback monospace by family name)
#   - ExclusiveArch x86_64 (the only arch omedora targets)
#   - omawrite.spec.sources pins the sha for exactly Source0's basename

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SPEC="$ROOT/omedora/packaging/copr/omawrite.spec"
SOURCES="$ROOT/omedora/packaging/copr/omawrite.spec.sources"

assert_file_exists "omawrite.spec exists" "$SPEC"
assert_file_exists "omawrite.spec.sources exists" "$SOURCES"

# --- from-source build (Source0 tarball + bin/build) -------------------------
grep -qE '^Source0:.*/archive/refs/tags/' "$SPEC" \
  && pass "Source0 is an upstream tag tarball" \
  || fail "Source0 is an upstream tag tarball"
grep -qE '^\./bin/build\b' "$SPEC" \
  && pass "%build runs upstream's ./bin/build (qmake6 + make)" \
  || fail "%build runs upstream's ./bin/build (qmake6 + make)"

# --- %files owns the binary (the SUPER+SHIFT+W keybind entrypoint) -----------
grep -qE '^%\{_bindir\}/omawrite[[:space:]]*$' "$SPEC" \
  && pass "%files owns /usr/bin/omawrite (the SUPER+SHIFT+W target)" \
  || fail "%files owns /usr/bin/omawrite (the SUPER+SHIFT+W target)"

# --- must NOT require the proprietary iA Writer font -------------------------
# The font is skip-mapped in omedora; omawrite degrades to a fallback monospace,
# so a Requires would make the whole package uninstallable on Fedora.
if grep -qiE '^Requires:.*ia[-_ ]?writer' "$SPEC"; then
  fail "spec must NOT Require ttf-ia-writer (proprietary; skip-mapped in omedora)"
else
  pass "spec does not Require the proprietary iA Writer font (fallback monospace)"
fi

# --- ExclusiveArch x86_64 ----------------------------------------------------
grep -qE '^ExclusiveArch:[[:space:]]+x86_64\b' "$SPEC" \
  && pass "ExclusiveArch: x86_64" \
  || fail "ExclusiveArch: x86_64"

# --- .sources pins exactly Source0's basename --------------------------------
src0="$(grep -E '^Source0:' "$SPEC" | head -1)"
[[ -n $src0 ]] || fail "spec declares Source0:"
ver="$(grep -E '^Version:' "$SPEC" | head -1 | awk '{print $2}')"
[[ -n $ver ]] || fail "spec declares Version:"
name="$(grep -E '^Name:' "$SPEC" | head -1 | awk '{print $2}')"
[[ -n $name ]] || fail "spec declares Name:"
src0_expanded="${src0//%\{version\}/$ver}"
src0_expanded="${src0_expanded//%\{name\}/$name}"
src0_base="$(basename "$src0_expanded")"
pin_file="$(awk 'NF && $1 !~ /^#/ {print $2; exit}' "$SOURCES")"
pin_hash="$(awk 'NF && $1 !~ /^#/ {print $1; exit}' "$SOURCES")"
assert_equals ".sources pins exactly Source0's basename ($src0_base)" "$pin_file" "$src0_base"
[[ $pin_hash =~ ^[0-9a-f]{64}$ ]] \
  && pass ".sources pin is a 64-hex sha256" \
  || fail ".sources pin is a 64-hex sha256 (got: $pin_hash)"

echo "# all omawrite-spec tests passed"
