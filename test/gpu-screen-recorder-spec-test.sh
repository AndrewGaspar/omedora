#!/bin/bash
#
# L1 static guard for omedora/packaging/copr/gpu-screen-recorder.spec (+ .sources).
#
# gpu-screen-recorder (git.dec05eba.com/gpu-screen-recorder, GPL-3.0-only) is the
# GPU-accelerated screen recorder omarchy's screenrecord flow is hardcoded to:
# bin/omarchy-capture-screenrecording launches `gpu-screen-recorder` and pkills
# `^gpu-screen-recorder`, and the Quickshell bar indicator pgreps the same name.
# omedora builds it FROM SOURCE in the COPR as a plain Meson C/C++ build — no
# vendoring (the %build phase only needs BuildRequires, never the network) — and,
# crucially, against Fedora main's ffmpeg-free-devel (NOT RPM Fusion), since gsr
# encodes via VAAPI/NVENC/Vulkan rather than libx264. This audits the spec text so
# a rebase / edit can't silently drop the /usr/bin/gpu-screen-recorder binary,
# reintroduce an RPM-Fusion ffmpeg build dep, lose the gsr-kms-server capability
# grant, or desync the source pin. Pure bash + grep; no build.
#
# Asserts:
#   - spec + .sources exist
#   - it is a from-source Meson build (Source0 upstream tarball; %build runs meson)
#   - it builds against ffmpeg-free-devel (Fedora main) and does NOT BuildRequire
#     RPM Fusion's ffmpeg-devel
#   - %files owns /usr/bin/gpu-screen-recorder (the exact pgrep/exec name) and the
#     gsr-kms-server helper
#   - %post grants gsr-kms-server the CAP_SYS_ADMIN file capability (setcap)
#   - License is GPL-3.0-only
#   - ExclusiveArch x86_64 (the only arch omedora targets)
#   - gpu-screen-recorder.spec.sources pins the sha for exactly Source0's basename

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SPEC="$ROOT/omedora/packaging/copr/gpu-screen-recorder.spec"
SOURCES="$ROOT/omedora/packaging/copr/gpu-screen-recorder.spec.sources"

assert_file_exists "gpu-screen-recorder.spec exists" "$SPEC"
assert_file_exists "gpu-screen-recorder.spec.sources exists" "$SOURCES"

# --- from-source Meson build -------------------------------------------------
grep -qE '^Source0:.*dec05eba\.com/snapshot/' "$SPEC" \
  && pass "Source0 is an upstream dec05eba snapshot tarball" \
  || fail "Source0 is an upstream dec05eba snapshot tarball"
grep -qE '^%meson_build\b' "$SPEC" \
  && pass "%build runs the Meson build (%meson_build)" \
  || fail "%build runs the Meson build (%meson_build)"

# --- ffmpeg-free (Fedora main), NOT RPM Fusion -------------------------------
grep -qE '^BuildRequires:[[:space:]]+ffmpeg-free-devel\b' "$SPEC" \
  && pass "BuildRequires: ffmpeg-free-devel (Fedora main, no RPM Fusion)" \
  || fail "BuildRequires: ffmpeg-free-devel (Fedora main, no RPM Fusion)"
if grep -qE '^BuildRequires:[[:space:]]+ffmpeg-devel\b' "$SPEC"; then
  fail "spec must NOT BuildRequire RPM Fusion's ffmpeg-devel (ffmpeg-free-devel suffices)"
else
  pass "spec does not BuildRequire RPM Fusion's ffmpeg-devel"
fi

# --- %files owns the binaries ------------------------------------------------
# The exact name omarchy's capture script exec's and the QML indicator pgreps.
grep -qE '^%\{_bindir\}/gpu-screen-recorder[[:space:]]*$' "$SPEC" \
  && pass "%files owns /usr/bin/gpu-screen-recorder" \
  || fail "%files owns /usr/bin/gpu-screen-recorder"
grep -qE '^%\{_bindir\}/gsr-kms-server[[:space:]]*$' "$SPEC" \
  && pass "%files owns /usr/bin/gsr-kms-server (KMS capture helper)" \
  || fail "%files owns /usr/bin/gsr-kms-server (KMS capture helper)"

# --- %post grants the KMS capability -----------------------------------------
grep -qE '^setcap[[:space:]]+cap_sys_admin\+ep[[:space:]]+%\{_bindir\}/gsr-kms-server' "$SPEC" \
  && pass "%post setcap cap_sys_admin+ep on gsr-kms-server" \
  || fail "%post setcap cap_sys_admin+ep on gsr-kms-server"

# --- License -----------------------------------------------------------------
grep -qE '^License:[[:space:]]+GPL-3\.0-only\b' "$SPEC" \
  && pass "License: GPL-3.0-only" \
  || fail "License: GPL-3.0-only"

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
# Source0 uses a `#/<renamed>` fragment: the fetched basename is the part after #/.
src0_expanded="${src0//%\{version\}/$ver}"
src0_expanded="${src0_expanded//%\{name\}/$name}"
src0_base="$(basename "$src0_expanded")"
pin_file="$(awk 'NF && $1 !~ /^#/ {print $2; exit}' "$SOURCES")"
pin_hash="$(awk 'NF && $1 !~ /^#/ {print $1; exit}' "$SOURCES")"
assert_equals ".sources pins exactly Source0's basename ($src0_base)" "$pin_file" "$src0_base"
[[ $pin_hash =~ ^[0-9a-f]{64}$ ]] \
  && pass ".sources pin is a 64-hex sha256" \
  || fail ".sources pin is a 64-hex sha256 (got: $pin_hash)"

echo "# all gpu-screen-recorder-spec tests passed"
