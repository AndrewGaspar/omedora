#!/bin/bash
#
# L1 static guard for omedora/packaging/copr/voxtype.spec (+ .sources).
#
# voxtype is hosted in the omedora COPR as a SINGLE from-source RPM built from
# the AndrewGaspar/voxtype fork branch feat/muse-stack-v1.0.1 (v1.0.1 + Muse
# streaming-transcribe engine + OSD states), compiled fully offline against a
# `cargo vendor` tarball of the fork's pinned Cargo.lock (satty.spec shape).
# CPU-only dep set: the old 0.7.5 binary-repackage's voxtype-cuda /
# voxtype-migraphx subpackages and the ONNX-CPU engine variants are GONE (ort
# prebuilts + CUDA/ROCm toolchains aren't available to offline COPR builds);
# GPU users keep the Vulkan whisper tier. This audits the spec text so a rebase
# / edit can't silently reintroduce the subpackage split, break the offline
# seal, drop the tiered binaries or OSD helpers, or desync the source pin.
# Pure bash + grep; no build.
#
# Asserts:
#   - spec + .sources exist
#   - NO `%package cuda` / `%package migraphx` (the split stays dead)
#   - the build is vendored/offline: a Source1 *-vendor.tar.* + `%cargo_prep -v
#     vendor` (the offline .cargo/config.toml seal) and NO crate fetch at %build
#   - the fork pin is coherent: %global fork_commit matches the commit baked
#     into the .sources-pinned Source0 basename
#   - %files owns the tiered whisper binaries (avx2/avx512/vulkan) + the
#     %ghost /usr/bin/voxtype symlink + the OSD helpers + quickshell tree +
#     config + service + man pages
#   - the base Requires curl + pipewire-alsa (HARD deps — pkg.py installs with
#     weak-deps off) and carries vulkan-loader for the Vulkan tier
#   - ExclusiveArch x86_64 (the tiered binaries are x86_64-only)
#   - voxtype.spec.sources pins the sha for exactly Source0's basename, and the
#     generated vendor tarball is NOT pinned there (build-local.sh regenerates
#     it deterministically at SRPM-gen time)

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SPEC="$ROOT/omedora/packaging/copr/voxtype.spec"
SOURCES="$ROOT/omedora/packaging/copr/voxtype.spec.sources"

assert_file_exists "voxtype.spec exists" "$SPEC"
assert_file_exists "voxtype.spec.sources exists" "$SOURCES"

# --- the subpackage split stays dead -----------------------------------------
# The 0.7.5 binary-repackage emitted voxtype-cuda / voxtype-migraphx; the
# from-source build must not resurrect them (nothing in fedora.toml or the
# installer references them anymore).
if grep -qE '^%package[[:space:]]+(cuda|migraphx)\b' "$SPEC"; then
  fail "spec declares NO %package cuda/migraphx (single-package build)"
else
  pass "spec declares NO %package cuda/migraphx (single-package build)"
fi

# --- hermetic vendored / offline build (COPR mock has no network at %build) --
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
# The offline flag must ride every build invocation (3 whisper tiers + helpers).
build_lines="$(grep -cE 'cargo build --release --offline --locked' "$SPEC")"
if (( build_lines >= 4 )); then
  pass "tiered cargo builds run --offline --locked ($build_lines invocations)"
else
  fail "tiered cargo builds run --offline --locked (got $build_lines invocations)"
fi

# --- comments must not break rpm parsing ---------------------------------------
# rpm macro-expands preamble comments while resolving tags, so a comment naming
# a macro that isn't loaded yet (%cargo_prep before cargo-rpm-macros,
# %fork_commit before its %global, systemd macros before systemd-rpm-macros)
# aborts the parse with "Unknown tag". Those names must be %%-escaped in
# comments (satty.spec shape); builtins (%post, %bcond_without) are fine bare.
if grep -E '^#' "$SPEC" | grep -E '(^|[^%])%(cargo|fork_commit|systemd|_userunitdir)' >/dev/null; then
  grep -E '^#' "$SPEC" | grep -E '(^|[^%])%(cargo|fork_commit|systemd|_userunitdir)' >&2
  fail "comments %%-escape parse-unknown macros (%cargo*, %fork_commit, %systemd*, %{_userunitdir})"
else
  pass "comments %%-escape parse-unknown macros (rpm-parse safe)"
fi

# --- fork pin coherence --------------------------------------------------------
fork_commit="$(grep -E '^%global[[:space:]]+fork_commit[[:space:]]' "$SPEC" | head -1 | awk '{print $3}')"
[[ -n $fork_commit ]] || fail "spec declares %global fork_commit"
[[ $fork_commit =~ ^[0-9a-f]{40}$ ]] \
  && pass "%global fork_commit is a full 40-hex sha ($fork_commit)" \
  || fail "%global fork_commit is a full 40-hex sha (got: $fork_commit)"
# Source0 must be the commit-pinned fork archive for that sha.
grep -qE '^Source0:.*github\.com/AndrewGaspar/voxtype/archive/%\{fork_commit\}' "$SPEC" \
  && pass "Source0 is the fork-commit-pinned GitHub archive" \
  || fail "Source0 is the fork-commit-pinned GitHub archive"
# The .sources pin must name exactly voxtype-<fork_commit>.tar.gz ...
pin_file="$(awk 'NF && $1 !~ /^#/ {print $2; exit}' "$SOURCES")"
pin_hash="$(awk 'NF && $1 !~ /^#/ {print $1; exit}' "$SOURCES")"
assert_equals ".sources pins voxtype-<fork_commit>.tar.gz" "$pin_file" "voxtype-${fork_commit}.tar.gz"
[[ $pin_hash =~ ^[0-9a-f]{64}$ ]] \
  && pass ".sources pin is a 64-hex sha256" \
  || fail ".sources pin is a 64-hex sha256 (got: $pin_hash)"
# ... and must NOT pin the generated vendor tarball (regenerated at SRPM-gen).
if grep -qE 'vendor\.tar\.' "$SOURCES"; then
  fail ".sources must NOT pin the generated vendor tarball"
else
  pass ".sources does NOT pin the generated vendor tarball"
fi

# --- %files owns the tiers + symlink + OSD helpers -----------------------------
# Single %files section (no subpackages to carve).
if grep -qE '^%files[[:space:]]+\S' "$SPEC"; then
  fail "spec has a single %files section (no subpackage %files)"
else
  pass "spec has a single %files section (no subpackage %files)"
fi
FILES="$(awk '/^%files([[:space:]]|$)/ {cur=1; next} /^%changelog/ {cur=0} cur {print}' "$SPEC")"
[[ -n $FILES ]] || fail "could not locate the %files section"
for tier in avx2 avx512 vulkan; do
  grep -qE "voxtype/voxtype-$tier\b" <<<"$FILES" \
    && pass "%files owns the voxtype-$tier whisper binary" \
    || fail "%files owns the voxtype-$tier whisper binary"
done
grep -qE '^%ghost[[:space:]]+%\{_bindir\}/voxtype[[:space:]]*$' <<<"$FILES" \
  && pass "%files marks the %post-managed /usr/bin/voxtype symlink %ghost" \
  || fail "%files marks the %post-managed /usr/bin/voxtype symlink %ghost"
for helper in voxtype-osd voxtype-audio-bridge voxtype-osd-quickshell; do
  grep -qE "%\\{_bindir\\}/$helper[[:space:]]*$" <<<"$FILES" \
    && pass "%files owns /usr/bin/$helper" \
    || fail "%files owns /usr/bin/$helper"
done
grep -qE '%\{_datadir\}/voxtype/quickshell' <<<"$FILES" \
  && pass "%files owns the quickshell OSD tree" \
  || fail "%files owns the quickshell OSD tree"
grep -qE '%config\(noreplace\)[[:space:]]+%\{_sysconfdir\}/voxtype/config\.toml' <<<"$FILES" \
  && pass "%files owns the noreplace voxtype config" \
  || fail "%files owns the noreplace voxtype config"
grep -qE '%\{_userunitdir\}/voxtype\.service' <<<"$FILES" \
  && pass "%files owns the user systemd service" \
  || fail "%files owns the user systemd service"
grep -qE '%\{_mandir\}/man1/voxtype' <<<"$FILES" \
  && pass "%files owns the man pages" \
  || fail "%files owns the man pages"
# The dead GPU trees must not leak back into the payload.
if grep -qiE 'cuda|migraphx|rocm|onnx' <<<"$FILES"; then
  printf '%s\n' "$FILES" >&2
  fail "%files carries no cuda/migraphx/rocm/onnx trees"
else
  pass "%files carries no cuda/migraphx/rocm/onnx trees"
fi

# --- install/files path + shell hygiene (local-build lessons) -------------------
# %install stages the tiers under %{_libdir} (/usr/lib64); %files must name the
# SAME dir (%{_prefix}/lib = /usr/lib there — a different directory).
grep -qE '%\{_libdir\}/voxtype/voxtype-avx2' "$SPEC" \
  && pass "%files tiers live under %{_libdir} (matches %install)" \
  || fail "%files tiers live under %{_libdir} (matches %install)"
if grep -qE '%\{_prefix\}/lib/voxtype' "$SPEC"; then
  fail "%files must NOT use %{_prefix}/lib/voxtype (/usr/lib != /usr/lib64)"
else
  pass "%files has no %{_prefix}/lib/voxtype mismatch"
fi
# No `$$` shell vars anywhere: rpm expands $$ to its own PID, so `$$m`
# silently tests/installs garbage (this shipped zero man pages once).
if grep -qE '\$\$' "$SPEC"; then
  grep -nE '\$\$' "$SPEC" >&2
  fail "spec contains no \$\$ (rpm PID-expansion trap)"
else
  pass "spec contains no \$\$ (rpm PID-expansion trap)"
fi

# --- hard runtime Requires ------------------------------------------------------
# Anchored at the top-level preamble (before any %description). pkg.py installs
# with weak deps OFF, so these MUST be Requires, not Recommends.
PREAMBLE="$(awk '/^%description/ {exit} {print}' "$SPEC")"
for dep in curl pipewire-alsa vulkan-loader; do
  grep -qE "^Requires:[[:space:]]+$dep\b" <<<"$PREAMBLE" \
    && pass "Requires: $dep (hard dep, weak-deps-off safe)" \
    || fail "Requires: $dep (hard dep, weak-deps-off safe)"
done

# --- arch -----------------------------------------------------------------------
grep -qE '^ExclusiveArch:[[:space:]]+x86_64[[:space:]]*$' "$SPEC" \
  && pass "ExclusiveArch x86_64 (tiered binaries are x86_64-only)" \
  || fail "ExclusiveArch x86_64 (tiered binaries are x86_64-only)"

echo "# all voxtype-spec tests passed"
