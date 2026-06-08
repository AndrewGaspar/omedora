#!/bin/bash
#
# L1 unit tests for install/config/config-fedora.sh fcitx IME seeding.
#
# fcitx is NOT in omedora's Fedora package set, so seeding
# config/environment.d/fcitx.conf points QT/SDL/X input-method env vars at
# uninstalled software and can break text input. config-fedora.sh therefore
# adds environment.d/fcitx.conf to the omedora-seed-config skip-list UNLESS
# fcitx is actually installed.
#
# Verified here (offline, distro selected via OMARCHY_DISTRO):
#   - Fedora, no fcitx on PATH   -> fcitx.conf NOT seeded into ~/.config.
#   - Fedora, fcitx5 on PATH     -> fcitx.conf seeded.
#   - Fedora, an existing user fcitx.conf is never clobbered without backup
#     (omedora-seed-config backs up to .pre-omedora-<ts>).
#
# The Arch path never reaches config-fedora.sh (config.sh dispatches to it only
# on Fedora), so there is no Arch case here — the Arch seeding body in config.sh
# is byte-identical to upstream and exercised nowhere in this script.
#
# omedora-seed-config (real, from bin/) does the actual seeding. ~/.bashrc and
# ~/.config live under a throwaway $HOME. fcitx presence is forced via the
# OMEDORA_FCITX_INSTALLED seam (1/0) so the result is independent of whatever
# the test host happens to have installed.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SCRIPT="$ROOT/install/config/config-fedora.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# real bin/ provides omedora-seed-config and omarchy-distro.
export PATH="$ROOT/bin:$PATH"

# A source config tree the script seeds from. config-fedora.sh hardcodes
# ~/.local/share/omarchy/config as the source, so we plant it under $HOME.
seed_source() {
  local home="$1"
  mkdir -p "$home/.local/share/omarchy/config/environment.d"
  printf 'INPUT_METHOD=fcitx\nQT_IM_MODULE=fcitx\n' \
    >"$home/.local/share/omarchy/config/environment.d/fcitx.conf"
  # A second, unrelated file so we can prove general seeding still happens.
  mkdir -p "$home/.local/share/omarchy/config/hypr"
  printf 'misc { vfr = true }\n' >"$home/.local/share/omarchy/config/hypr/hyprland.conf"
}

# Run config-fedora.sh in a clean subshell under a fresh $HOME. $1 = "with-fcitx"
# or "no-fcitx" forces the fcitx-installed branch via OMEDORA_FCITX_INSTALLED.
# Echoes the HOME used.
run_config() {
  local mode="$1"
  local home="$TMPDIR/home-$mode-$RANDOM"
  mkdir -p "$home/.config"
  seed_source "$home"

  local fcitx=0
  [[ $mode == with-fcitx ]] && fcitx=1

  (
    export HOME="$home"
    export OMARCHY_DISTRO=fedora
    export OMEDORA_FCITX_INSTALLED="$fcitx"
    bash "$SCRIPT"
  ) >/dev/null 2>&1

  printf '%s\n' "$home"
}

# --- Fedora, no fcitx: fcitx.conf is skipped --------------------------------
home=$(run_config no-fcitx)
if [[ -e "$home/.config/environment.d/fcitx.conf" ]]; then
  fail "Fedora w/o fcitx: environment.d/fcitx.conf should NOT be seeded"
fi
pass "Fedora w/o fcitx: environment.d/fcitx.conf is skipped"
assert_file_exists "Fedora w/o fcitx: unrelated config (hypr) is still seeded" \
  "$home/.config/hypr/hyprland.conf"

# --- Fedora, fcitx installed: fcitx.conf is seeded --------------------------
home=$(run_config with-fcitx)
assert_file_exists "Fedora w/ fcitx: environment.d/fcitx.conf IS seeded" \
  "$home/.config/environment.d/fcitx.conf"

# --- Fedora, fcitx installed + user already has their own fcitx.conf --------
# It must be backed up (never clobbered) before omedora's is written.
home="$TMPDIR/home-existing-$RANDOM"
mkdir -p "$home/.config/environment.d"
seed_source "$home"
printf '# my own fcitx tweaks\nGTK_IM_MODULE=fcitx\n' \
  >"$home/.config/environment.d/fcitx.conf"
(
  export HOME="$home"
  export OMARCHY_DISTRO=fedora
  export OMEDORA_FCITX_INSTALLED=1
  bash "$SCRIPT"
) >/dev/null 2>&1
backup=$(ls "$home/.config/environment.d/"fcitx.conf.pre-omedora-* 2>/dev/null | head -n1 || true)
assert_file_exists "Fedora w/ fcitx: existing user fcitx.conf is backed up before overwrite" \
  "$backup"
assert_output_contains "backup preserves the user's original content" \
  "$(cat "$backup")" "GTK_IM_MODULE=fcitx"

echo "# all config-fcitx-seed tests passed"
