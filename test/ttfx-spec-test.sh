#!/bin/bash
#
# L1 static guard for omedora/packaging/copr/ttfx.spec (+ .sources).
#
# ttfx is Quattro's native Rust terminal-text-effects engine (the screensaver
# and first-boot presentation drive it; github.com/omacom-io/ttfx, MIT). omedora
# builds it FROM SOURCE in the COPR as a HERMETIC, VENDORED cargo build —
# modelled on tensaku.spec — so it compiles in COPR's OFFLINE mock (crates come
# from a `cargo vendor` tarball generated at SRPM time, never crates.io at
# %build). This audits the spec text so a rebase / edit can't silently regress
# the packaged version (AndrewGaspar/omedora#8 needs >= 0.3.2, which stops the
# SIGABRT when the terminal goes away at idle-lock), break the offline seal, or
# desync the source pin. Pure bash + grep; no build.
#
# Asserts:
#   - spec + .sources exist
#   - Version is 0.3.2 and Release is 1%{?dist}; the top %changelog entry
#     carries the same version-release
#   - Source0 is the GitHub codeload tag tarball renamed to
#     %{name}-%{version}.tar.gz (the exact form the .sources pin names)
#   - the build is vendored/offline: Source1 is %{name}-%{version}-vendor.tar.zst
#     (the exact filename .copr/srpm.sh regenerates), unpacked by %setup -a 1,
#     sealed by `%cargo_prep -v vendor`, and NO crate fetch at %build
#   - %files owns /usr/bin/ttfx plus the bash and zsh completions
#   - it Obsoletes python3-terminaltexteffects (the runtime it replaces)
#   - ExclusiveArch x86_64 (the only arch omedora targets)
#   - ttfx.spec.sources pins the sha for exactly Source0's basename and nothing
#     else (the generated vendor tarball is deliberately unpinned)

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SPEC="$ROOT/omedora/packaging/copr/ttfx.spec"
SOURCES="$ROOT/omedora/packaging/copr/ttfx.spec.sources"

assert_file_exists "ttfx.spec exists" "$SPEC"
assert_file_exists "ttfx.spec.sources exists" "$SOURCES"

# --- Version / Release / %changelog agree ------------------------------------
name="$(grep -E '^Name:' "$SPEC" | head -1 | awk '{print $2}')"
[[ -n $name ]] || fail "spec declares Name:"
assert_equals "Name: ttfx" "$name" "ttfx"
ver="$(grep -E '^Version:' "$SPEC" | head -1 | awk '{print $2}')"
[[ -n $ver ]] || fail "spec declares Version:"
assert_equals "Version: 0.3.2 (omedora#8: the terminal-went-away SIGABRT fix)" "$ver" "0.3.2"
rel="$(grep -E '^Release:' "$SPEC" | head -1 | awk '{print $2}')"
assert_equals "Release: 1%{?dist}" "$rel" '1%{?dist}'
top_changelog="$(sed -n '/^%changelog/,$p' "$SPEC" | grep -E '^\* ' | head -1)"
[[ $top_changelog == *"- ${ver}-${rel%\%\{?dist\}}" ]] \
  && pass "top %changelog entry is ${ver}-${rel%\%\{?dist\}}" \
  || fail "top %changelog entry is ${ver}-${rel%\%\{?dist\}} (got: $top_changelog)"

# --- Source0: codeload tag tarball renamed to %{name}-%{version}.tar.gz ------
grep -qE '^Source0:[[:space:]]+https://codeload\.github\.com/omacom-io/ttfx/tar\.gz/refs/tags/v%\{version\}#/%\{name\}-%\{version\}\.tar\.gz[[:space:]]*$' "$SPEC" \
  && pass "Source0 is the codeload refs/tags/v%{version} tarball renamed to %{name}-%{version}.tar.gz" \
  || fail "Source0 is the codeload refs/tags/v%{version} tarball renamed to %{name}-%{version}.tar.gz"

# --- hermetic vendored / offline build (COPR mock has no network at %build) ---
# .copr/srpm.sh and build-local.sh regenerate exactly
# ${name}-${version}-vendor.tar.zst into SOURCES/; Source1 must name that file
# or rpmbuild -bs fails with a missing source.
src1="$(grep -E '^Source1:' "$SPEC" | head -1 | sed -E 's/^[^:]+:[[:space:]]*//')"
[[ -n $src1 ]] || fail "spec declares Source1:"
src1_expanded="${src1//%\{version\}/$ver}"
src1_expanded="${src1_expanded//%\{name\}/$name}"
assert_equals "Source1 is the srpm.sh-generated ${name}-${ver}-vendor.tar.zst" \
  "$src1_expanded" "${name}-${ver}-vendor.tar.zst"
grep -qE '^%setup[[:space:]].*-a[[:space:]]+1\b' "$SPEC" \
  && pass "%setup -a 1 unpacks the vendor tarball into the source tree" \
  || fail "%setup -a 1 unpacks the vendor tarball into the source tree"
grep -qE '^%cargo_prep[[:space:]].*-v[[:space:]]+vendor' "$SPEC" \
  && pass "%cargo_prep -v vendor writes the offline .cargo/config.toml seal" \
  || fail "%cargo_prep -v vendor writes the offline .cargo/config.toml seal"
if grep -qE '^[[:space:]]*cargo[[:space:]]+(fetch|update|vendor)\b' "$SPEC"; then
  fail "spec must not run cargo fetch/update/vendor at %build (offline mock)"
else
  pass "no cargo fetch/update/vendor at %build (offline mock safe)"
fi

# --- %files owns the binary + completions ------------------------------------
grep -qE '^%\{_bindir\}/ttfx[[:space:]]*$' "$SPEC" \
  && pass "%files owns /usr/bin/ttfx" \
  || fail "%files owns /usr/bin/ttfx"
grep -qE '^%\{_datadir\}/bash-completion/completions/ttfx[[:space:]]*$' "$SPEC" \
  && pass "%files owns the bash completion" \
  || fail "%files owns the bash completion"
grep -qE '^%\{_datadir\}/zsh/site-functions/_ttfx[[:space:]]*$' "$SPEC" \
  && pass "%files owns the zsh completion" \
  || fail "%files owns the zsh completion"

# --- Obsoletes the Python runtime it replaces --------------------------------
grep -qE '^Obsoletes:[[:space:]]+python3-terminaltexteffects\b' "$SPEC" \
  && pass "Obsoletes: python3-terminaltexteffects (the replaced Omedora 3 runtime)" \
  || fail "Obsoletes: python3-terminaltexteffects (the replaced Omedora 3 runtime)"

# --- ExclusiveArch x86_64 ----------------------------------------------------
grep -qE '^ExclusiveArch:[[:space:]]+x86_64\b' "$SPEC" \
  && pass "ExclusiveArch: x86_64" \
  || fail "ExclusiveArch: x86_64"

# --- .sources pins exactly Source0's basename, and nothing else --------------
src0="$(grep -E '^Source0:' "$SPEC" | head -1)"
src0_expanded="${src0//%\{version\}/$ver}"
src0_expanded="${src0_expanded//%\{name\}/$name}"
src0_base="$(basename "$src0_expanded")"
assert_equals "Source0 basename is ${name}-${ver}.tar.gz" "$src0_base" "${name}-${ver}.tar.gz"
pin_file="$(awk 'NF && $1 !~ /^#/ {print $2; exit}' "$SOURCES")"
pin_hash="$(awk 'NF && $1 !~ /^#/ {print $1; exit}' "$SOURCES")"
assert_equals ".sources pins exactly Source0's basename ($src0_base)" "$pin_file" "$src0_base"
[[ $pin_hash =~ ^[0-9a-f]{64}$ ]] \
  && pass ".sources pin is a 64-hex sha256" \
  || fail ".sources pin is a 64-hex sha256 (got: $pin_hash)"
pin_count="$(awk 'NF && $1 !~ /^#/ {n++} END {print n+0}' "$SOURCES")"
assert_equals ".sources holds exactly one pin (the vendor tarball is generated, never pinned)" "$pin_count" "1"

echo "# all ttfx-spec tests passed"
