#!/bin/bash
#
# L1 unit test for on-demand voxtype install on Fedora.
#
# voxtype is hosted in the omedora COPR as a single from-source RPM (tiered
# whisper CPU + Vulkan binaries + OSD helpers; no GPU add-on subpackages — the
# old voxtype-cuda / voxtype-migraphx split died with the 0.7.5
# binary-repackage). The Fedora installer (bin/fedora/voxtype-install-pkg)
# installs the base and nothing else; GPU users get acceleration from the
# Vulkan tier. This covers that sibling + the Fedora/Arch dispatch in
# bin/omarchy-voxtype-install and bin/omarchy-voxtype-remove.
#
#   PART 1 — voxtype-install-pkg: always adds exactly `wtype voxtype-bin` (base,
#            mapped to voxtype) via omarchy-pkg-add on EVERY GPU profile
#            (NVIDIA / AMD / Intel / none / hybrid) and NEVER adds the retired
#            voxtype-cuda / voxtype-migraphx names. Honors OMARCHY_PKG_DRY_RUN
#            (no-op here since omarchy-pkg-add is stubbed, but the script never
#            shells out to dnf directly).
#   PART 2 — omarchy-voxtype-install dispatches to the sibling on Fedora and runs
#            `omarchy-pkg-add wtype voxtype-bin` VERBATIM on Arch.
#   PART 3 — omarchy-voxtype-remove runs `omarchy-pkg-drop voxtype-bin` on BOTH
#            distros (the script is byte-identical to upstream; on Fedora pkg.py
#            maps that to `dnf remove voxtype`).
#   PART 4 — omarchy-voxtype-config (the bar mic click): on Fedora, OFFERS THE
#            INSTALL (launches omarchy-voxtype-install) when voxtype is absent, and
#            runs `voxtype configure` once it's installed.
#
# Everything external is stubbed on PATH; no network, no real dnf, no real
# package manager.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SCRATCH="$(mktemp -d)"
trap '[[ -n $SCRATCH && -d $SCRATCH ]] && rm -rf "$SCRATCH"' EXIT

SHIM="$SCRATCH/shim"
mkdir -p "$SHIM"
MOCK_LOG="$SCRATCH/mock.log"
export MOCK_LOG

stub() { printf '#!/bin/bash\n%s\n' "$2" >"$SHIM/$1"; chmod +x "$SHIM/$1"; }

# Record every traced action to $MOCK_LOG so assertions can grep it.
stub omarchy-pkg-add     'printf "omarchy-pkg-add %s\n" "$*" >>"$MOCK_LOG"'
stub omarchy-pkg-drop    'printf "omarchy-pkg-drop %s\n" "$*" >>"$MOCK_LOG"'
# The installer takes no GPU branch at all (no lspci probe); the stub exists so
# PART 1 can prove GPU-flavored lspci output is ignored. Default: no GPU.
stub lspci               'exit 0'   # prints nothing -> no GPU match by default

export PATH="$SHIM:$ROOT/bin:$PATH"

PKG="$ROOT/bin/fedora/voxtype-install-pkg"

# ===========================================================================
echo "# --- PART 1: voxtype-install-pkg installs the base on every GPU ---"
# ===========================================================================
# The installer takes NO GPU branch (no lspci probe, no add-on subpackages):
# every profile below must produce exactly one pkg-add line and never the
# retired voxtype-cuda / voxtype-migraphx names.

# Helper: run the installer and assert the base-only transaction.
assert_base_only() { # $1 = profile label
  : >"$MOCK_LOG"
  ( export OMARCHY_DISTRO=fedora; bash "$PKG" ) >/dev/null 2>&1
  grep -q "^omarchy-pkg-add wtype voxtype-bin$" "$MOCK_LOG" \
    && pass "$1: installs the base (wtype voxtype-bin)" \
    || { cat "$MOCK_LOG" >&2; fail "$1: installs the base (wtype voxtype-bin)"; }
  grep -qE "voxtype-(cuda|migraphx)" "$MOCK_LOG" \
    && { cat "$MOCK_LOG" >&2; fail "$1: never adds the retired GPU add-ons"; } \
    || pass "$1: never adds the retired GPU add-ons"
  [[ $(grep -c "^omarchy-pkg-add " "$MOCK_LOG") == 1 ]] \
    && pass "$1: exactly one pkg-add call" \
    || { cat "$MOCK_LOG" >&2; fail "$1: exactly one pkg-add call"; }
}

# Helper: stub lspci to print a given line (the installer must ignore it).
lspci_prints() { stub lspci 'cat <<'"'"'EOF'"'"'
'"$1"'
EOF'; }

# --- (a) NVIDIA present -> base only ------------------------------------------
lspci_prints '01:00.0 VGA compatible controller: NVIDIA Corporation GA104 [GeForce RTX 3070]'
assert_base_only "NVIDIA"

# --- (b) AMD present -> base only ---------------------------------------------
lspci_prints '0a:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Navi 31 [Radeon RX 7900 XTX]'
assert_base_only "AMD"

# --- (c) Intel/none -> base only ----------------------------------------------
lspci_prints '00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-S UHD Graphics'
assert_base_only "Intel/none"

# --- (d) hybrid NVIDIA+AMD laptop -> base only --------------------------------
lspci_prints $'c1:00.0 VGA compatible controller: NVIDIA Corporation GB206M [GeForce RTX 5070]\nc2:00.0 Display controller: Advanced Micro Devices, Inc. [AMD/ATI] Strix [Radeon 890M]'
assert_base_only "hybrid NVIDIA+AMD"

# restore defaults
stub lspci 'exit 0'

# ===========================================================================
echo "# --- PART 2: omarchy-voxtype-install dispatch ---"
# ===========================================================================
# Stub the shared setup tools so the script runs past the dispatch hermetically.
stub gum                       'exit 0'   # confirm yes
stub voxtype                   'printf "voxtype %s\n" "$*" >>"$MOCK_LOG"; exit 0'
stub omarchy-hyprland-toggle   'printf "toggle %s\n" "$*" >>"$MOCK_LOG"'
stub omarchy-restart-shell     ':'
stub omarchy-notification-send ':'

FAKE_OMARCHY="$SCRATCH/omarchy"
mkdir -p "$FAKE_OMARCHY/default/voxtype"
printf 'cfg\n' >"$FAKE_OMARCHY/default/voxtype/config.toml"

# --- Fedora: dispatches to the sibling (omarchy-pkg-add wtype voxtype-bin) ----
: >"$MOCK_LOG"
( export OMARCHY_DISTRO=fedora OMARCHY_PATH="$FAKE_OMARCHY" HOME="$SCRATCH/home-fed"
  mkdir -p "$HOME"
  bash "$ROOT/bin/omarchy-voxtype-install" ) >/dev/null 2>&1 || true
grep -q "^omarchy-pkg-add wtype voxtype-bin$" "$MOCK_LOG" \
  && pass "Fedora install dispatches to the sibling (adds wtype voxtype-bin base)" \
  || { cat "$MOCK_LOG" >&2; fail "Fedora install dispatches to the sibling (adds wtype voxtype-bin base)"; }
# The single-package build adds nothing beyond the base, whatever the GPU.
grep -qE "voxtype-(cuda|migraphx)" "$MOCK_LOG" \
  && { cat "$MOCK_LOG" >&2; fail "Fedora install never adds the retired GPU add-ons"; } \
  || pass "Fedora install never adds the retired GPU add-ons"

# --- Arch path: verbatim omarchy-pkg-add wtype voxtype-bin -------------------
: >"$MOCK_LOG"
( export OMARCHY_DISTRO=arch OMARCHY_PATH="$FAKE_OMARCHY" HOME="$SCRATCH/home-arch"
  mkdir -p "$HOME"
  bash "$ROOT/bin/omarchy-voxtype-install" ) >/dev/null 2>&1 || true
grep -q "^omarchy-pkg-add wtype voxtype-bin$" "$MOCK_LOG" \
  && pass "Arch install runs omarchy-pkg-add wtype voxtype-bin verbatim" \
  || { cat "$MOCK_LOG" >&2; fail "Arch install runs omarchy-pkg-add wtype voxtype-bin verbatim"; }
grep -qE "voxtype-(cuda|migraphx)" "$MOCK_LOG" \
  && fail "Arch install never touches the retired GPU add-on names" \
  || pass "Arch install never touches the retired GPU add-on names"

# ===========================================================================
echo "# --- PART 3: omarchy-voxtype-remove dispatch (byte-identical) ---"
# ===========================================================================
stub voxtype 'exit 0'  # omarchy-cmd-present voxtype -> true
stub systemctl ':'

# Both distros run `omarchy-pkg-drop voxtype-bin` — the script is byte-identical
# to upstream. On Fedora pkg.py maps voxtype-bin -> `dnf remove voxtype`, which
# cascades to the installed -cuda/-migraphx subpackages.
for distro in fedora arch; do
  : >"$MOCK_LOG"
  ( export OMARCHY_DISTRO=$distro HOME="$SCRATCH/home-rm-$distro"
    mkdir -p "$HOME"
    bash "$ROOT/bin/omarchy-voxtype-remove" ) >/dev/null 2>&1 || true
  grep -q "^omarchy-pkg-drop voxtype-bin$" "$MOCK_LOG" \
    && pass "$distro remove runs omarchy-pkg-drop voxtype-bin" \
    || { cat "$MOCK_LOG" >&2; fail "$distro remove runs omarchy-pkg-drop voxtype-bin"; }
  grep -qE "^dnf |^sudo dnf " "$MOCK_LOG" \
    && fail "$distro remove never shells out to dnf directly" \
    || pass "$distro remove never shells out to dnf directly"
done

# ===========================================================================
echo "# --- PART 4: omarchy-voxtype-config mic-click dispatch ---"
# ===========================================================================
stub omarchy-launch-floating-terminal-with-presentation 'printf "launch %s\n" "$*" >>"$MOCK_LOG"'
stub omarchy-restart-shell ':'

# --- (a) Fedora + voxtype MISSING -> offers the install ----------------------
rm -f "$SHIM/voxtype"   # voxtype absent from PATH
: >"$MOCK_LOG"
( export OMARCHY_DISTRO=fedora
  bash "$ROOT/bin/omarchy-voxtype-config" ) >/dev/null 2>&1 || true
grep -q "^launch omarchy-voxtype-install$" "$MOCK_LOG" \
  && pass "Fedora mic-click offers the install when voxtype is missing" \
  || { cat "$MOCK_LOG" >&2; fail "Fedora mic-click offers the install when voxtype is missing"; }
grep -q "voxtype configure" "$MOCK_LOG" \
  && fail "Fedora mic-click does NOT run 'voxtype configure' when voxtype missing" \
  || pass "Fedora mic-click does NOT run 'voxtype configure' when voxtype missing"

# --- (b) Fedora + voxtype PRESENT -> runs voxtype configure ------------------
stub voxtype 'exit 0'   # voxtype now on PATH
: >"$MOCK_LOG"
( export OMARCHY_DISTRO=fedora
  bash "$ROOT/bin/omarchy-voxtype-config" ) >/dev/null 2>&1 || true
grep -q "^launch voxtype configure$" "$MOCK_LOG" \
  && pass "Fedora mic-click runs 'voxtype configure' once voxtype is installed" \
  || { cat "$MOCK_LOG" >&2; fail "Fedora mic-click runs 'voxtype configure' once installed"; }
grep -q "omarchy-voxtype-install" "$MOCK_LOG" \
  && fail "Fedora mic-click does NOT re-offer install when voxtype present" \
  || pass "Fedora mic-click does NOT re-offer install when voxtype present"

echo "# all voxtype-install tests passed"
