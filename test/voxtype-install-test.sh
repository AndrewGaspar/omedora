#!/bin/bash
#
# L1 unit test for on-demand Voxtype dictation on Fedora.
#
# Omarchy 4.5 replaced omarchy-voxtype-install/-remove with the dictation
# backends (omarchy-install-dictation-voxtype, omarchy-remove-dictation-voxtype,
# omarchy-dictation-voxtype). Omedora carries no patch on them: upstream's
# `omarchy-pkg-add wtype voxtype-bin` / `omarchy-pkg-drop voxtype-bin` resolve
# through install/packages/fedora.toml to the single from-source `voxtype` RPM
# in the omedora COPR (omedora/packaging/copr/voxtype.spec).
#
#   PART 1 — the package map: `wtype voxtype-bin` resolves to the dnf names
#            `wtype voxtype` (bin/fedora/pkg.py dry run), never to the retired
#            voxtype-cuda / voxtype-migraphx add-ons.
#   PART 2 — omarchy-install-dictation-voxtype on Fedora installs exactly
#            `wtype voxtype-bin` through omarchy-pkg-add, then runs the shared
#            setup and selects voxtype as the dictation backend.
#   PART 3 — omarchy-remove-dictation-voxtype drops `voxtype-bin` through
#            omarchy-pkg-drop on both distros and never shells out to dnf.
#
# Everything external is stubbed on PATH; no network, no real dnf. A voxtype the
# host has installed must never run: the PATH is the stubs plus system
# directories only, and omarchy-cmd-missing is stubbed so only the stub voxtype
# (created by the stubbed install) counts as installed.

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

BASE_PATH="/usr/bin:/bin"

# ===========================================================================
echo "# --- PART 1: the package map resolves voxtype-bin to the COPR RPM ---"
# ===========================================================================
out=$(OMARCHY_DISTRO=fedora OMARCHY_PKG_DRY_RUN=1 OMARCHY_PATH="$ROOT" \
  PATH="$ROOT/bin:$BASE_PATH" "$ROOT/bin/omarchy-pkg-add" wtype voxtype-bin 2>&1) || true
# The map entry itself, then the live resolution. On a Fedora host where wtype
# or voxtype is already installed, pkg.py only lists what is missing.
block=$(awk '$0 == "[voxtype-bin]" {on=1; next} /^\[/ {on=0} on' "$ROOT/install/packages/fedora.toml")
grep -qx 'source = "dnf"' <<<"$block" && grep -qx 'names = \["voxtype"\]' <<<"$block" \
  && pass "fedora.toml maps voxtype-bin to the voxtype RPM" \
  || fail "fedora.toml maps voxtype-bin to the voxtype RPM"
install_line=$(sed -E 's/\x1b\[[0-9;]*m//g' <<<"$out" | grep 'dnf install' || true)
if [[ -z $install_line ]] || grep -qE ' (wtype )?voxtype$' <<<"$install_line"; then
  pass "wtype voxtype-bin resolves to dnf names 'wtype voxtype' (minus installed ones)"
else
  echo "$out" >&2; fail "wtype voxtype-bin resolves to dnf names 'wtype voxtype' (minus installed ones)"
fi
grep -qE 'voxtype-(cuda|migraphx)' <<<"$out" \
  && { echo "$out" >&2; fail "map never resolves to the retired GPU add-ons"; } \
  || pass "map never resolves to the retired GPU add-ons"

# ===========================================================================
echo "# --- PART 2: omarchy-install-dictation-voxtype on Fedora ---"
# ===========================================================================
stub omarchy-cmd-missing        '[[ -x "$(dirname "$0")/$1" ]] && exit 1; exit 0'
stub omarchy-cmd-present        '[[ -x "$(dirname "$0")/$1" ]]'
stub omarchy-pkg-add            'printf "omarchy-pkg-add %s\n" "$*" >>"$MOCK_LOG"; ln -sf "$(dirname "$0")/voxtype-installed" "$(dirname "$0")/voxtype"'
stub voxtype-installed          'printf "voxtype %s\n" "$*" >>"$MOCK_LOG"; exit 0'
stub gum                        'exit 0'   # confirm yes
stub omarchy-i18n               'echo "$1"'
stub omarchy-hw-vulkan          'exit 1'
stub systemctl                  'printf "systemctl %s\n" "$*" >>"$MOCK_LOG"'
stub hyprctl                    ':'
stub omarchy-notification-send  ':'
stub omarchy-dictation-use      'printf "dictation-use %s\n" "$*" >>"$MOCK_LOG"'

FAKE_OMARCHY="$SCRATCH/omarchy"
mkdir -p "$FAKE_OMARCHY/default/voxtype"
printf 'cfg\n' >"$FAKE_OMARCHY/default/voxtype/config.toml"

: >"$MOCK_LOG"
( export OMARCHY_DISTRO=fedora OMARCHY_PATH="$FAKE_OMARCHY" HOME="$SCRATCH/home-fed"
  export XDG_CONFIG_HOME="$HOME/.config" PATH="$SHIM:$ROOT/bin:$BASE_PATH"
  mkdir -p "$HOME"
  bash "$ROOT/bin/omarchy-install-dictation-voxtype" ) >/dev/null 2>&1 || true
grep -q "^omarchy-pkg-add wtype voxtype-bin$" "$MOCK_LOG" \
  && pass "Fedora install adds exactly 'wtype voxtype-bin'" \
  || { cat "$MOCK_LOG" >&2; fail "Fedora install adds exactly 'wtype voxtype-bin'"; }
[[ $(grep -c "^omarchy-pkg-add " "$MOCK_LOG") == 1 ]] \
  && pass "Fedora install makes one pkg-add call" \
  || { cat "$MOCK_LOG" >&2; fail "Fedora install makes one pkg-add call"; }
grep -q "^voxtype setup --download --no-post-install$" "$MOCK_LOG" \
  && pass "Fedora install runs the shared voxtype setup" \
  || { cat "$MOCK_LOG" >&2; fail "Fedora install runs the shared voxtype setup"; }
grep -q "^dictation-use voxtype$" "$MOCK_LOG" \
  && pass "Fedora install selects voxtype as the dictation backend" \
  || { cat "$MOCK_LOG" >&2; fail "Fedora install selects voxtype as the dictation backend"; }

# ===========================================================================
echo "# --- PART 3: omarchy-remove-dictation-voxtype (byte-identical) ---"
# ===========================================================================
stub omarchy-pkg-drop 'printf "omarchy-pkg-drop %s\n" "$*" >>"$MOCK_LOG"'
stub voxtype          'exit 0'  # omarchy-cmd-present voxtype -> true

for distro in fedora arch; do
  : >"$MOCK_LOG"
  ( export OMARCHY_DISTRO=$distro HOME="$SCRATCH/home-rm-$distro"
    export XDG_CONFIG_HOME="$HOME/.config" PATH="$SHIM:$ROOT/bin:$BASE_PATH"
    mkdir -p "$HOME"
    bash "$ROOT/bin/omarchy-remove-dictation-voxtype" ) >/dev/null 2>&1 || true
  grep -q "^omarchy-pkg-drop voxtype-bin$" "$MOCK_LOG" \
    && pass "$distro remove runs omarchy-pkg-drop voxtype-bin" \
    || { cat "$MOCK_LOG" >&2; fail "$distro remove runs omarchy-pkg-drop voxtype-bin"; }
  grep -qE "^dnf |^sudo dnf " "$MOCK_LOG" \
    && fail "$distro remove never shells out to dnf directly" \
    || pass "$distro remove never shells out to dnf directly"
done

# ===========================================================================
echo "# --- PART 4: Voxtype is Fedora's default dictation backend ---"
# ===========================================================================
# Upstream seeds superwhisper (proprietary, skip-mapped). omedora-settings
# overrides the seeded file in both payload copies; upstream's config/ path
# must still exist for that override to land on a real file.
SETTINGS="$ROOT/omedora/packaging/copr/omedora-settings.spec"
[[ -f $ROOT/config/omarchy/defaults/dictation ]] \
  && pass "upstream still seeds config/omarchy/defaults/dictation" \
  || fail "upstream still seeds config/omarchy/defaults/dictation"
for dest in '%{buildroot}%{_datadir}/omarchy/config/omarchy/defaults/dictation' \
  '%{buildroot}/etc/skel/.config/omarchy/defaults/dictation'; do
  grep -qF "printf 'voxtype\\n' >$dest" "$SETTINGS" \
    && pass "omedora-settings seeds voxtype at $dest" \
    || fail "omedora-settings seeds voxtype at $dest"
done

echo "# all voxtype-install tests passed"
