#!/bin/bash
#
# L1 static guard for omedora/packaging/copr/tensaku.spec (+ .sources).
#
# tensaku is the quattro line's screenshot/clipboard annotation editor (a Satty
# fork; dev.tensaku.Tensaku). omedora builds it FROM SOURCE in the COPR as a
# HERMETIC, VENDORED cargo build — modelled on satty.spec — so it compiles in
# COPR's OFFLINE mock (crates come from a `cargo vendor` tarball, never crates.io
# at %build time). This audits the spec text so a rebase / edit can't silently
# break the offline seal, drop the tensaku-edit wrapper omarchy's capture scripts
# invoke, or desync the source pin. Pure bash + grep; no build.
#
# Asserts:
#   - spec + .sources exist
#   - the build is vendored/offline: a Source1 *-vendor.tar.* + `%cargo_prep -v
#     vendor` (the offline .cargo/config.toml seal) and NO crate fetch at %build
#   - it builds with the ci-release feature (generates completions + man page)
#   - %files owns BOTH /usr/bin/tensaku and /usr/bin/tensaku-edit
#   - it Requires wl-clipboard (the tensaku-edit wrapper execs wl-copy)
#   - ExclusiveArch x86_64 (the only arch omedora targets)
#   - tensaku.spec.sources pins the sha for exactly Source0's basename

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SPEC="$ROOT/omedora/packaging/copr/tensaku.spec"
SOURCES="$ROOT/omedora/packaging/copr/tensaku.spec.sources"

assert_file_exists "tensaku.spec exists" "$SPEC"
assert_file_exists "tensaku.spec.sources exists" "$SOURCES"

# --- hermetic vendored / offline build (COPR mock has no network at %build) ---
grep -qE '^Source1:.*-vendor\.tar\.' "$SPEC" \
  && pass "spec declares a Source1 *-vendor.tar.* (cargo-vendor tarball)" \
  || fail "spec declares a Source1 *-vendor.tar.* (cargo-vendor tarball)"
grep -qE '^%cargo_prep[[:space:]].*-v[[:space:]]+vendor' "$SPEC" \
  && pass "%cargo_prep -v vendor writes the offline .cargo/config.toml seal" \
  || fail "%cargo_prep -v vendor writes the offline .cargo/config.toml seal"
# No online crate fetch may sneak into the build phase.
if grep -qE '^[[:space:]]*cargo[[:space:]]+(fetch|update|vendor)\b' "$SPEC"; then
  fail "spec must not run cargo fetch/update/vendor at %build (offline mock)"
else
  pass "no cargo fetch/update/vendor at %build (offline mock safe)"
fi

# --- builds with the ci-release feature (completions + man generation) -------
grep -qE '^%cargo_build[[:space:]].*-f[[:space:]]+ci-release' "$SPEC" \
  && pass "builds with -f ci-release (build.rs emits completions/ + man/)" \
  || fail "builds with -f ci-release (build.rs emits completions/ + man/)"

# --- %files owns BOTH binaries -----------------------------------------------
# The tensaku-edit wrapper is what omarchy-capture-screenshot / -clipboard-open /
# imv invoke; the whole point of packaging tensaku is to ship it natively.
grep -qE '^%\{_bindir\}/tensaku[[:space:]]*$' "$SPEC" \
  && pass "%files owns /usr/bin/tensaku" \
  || fail "%files owns /usr/bin/tensaku"
grep -qE '^%\{_bindir\}/tensaku-edit[[:space:]]*$' "$SPEC" \
  && pass "%files owns /usr/bin/tensaku-edit (omarchy's capture-script entrypoint)" \
  || fail "%files owns /usr/bin/tensaku-edit (omarchy's capture-script entrypoint)"

# --- Requires: wl-clipboard (tensaku-edit execs wl-copy) ---------------------
grep -qE '^Requires:[[:space:]]+wl-clipboard\b' "$SPEC" \
  && pass "Requires: wl-clipboard (the tensaku-edit wrapper execs wl-copy)" \
  || fail "Requires: wl-clipboard (the tensaku-edit wrapper execs wl-copy)"

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

echo "# all tensaku-spec tests passed"
