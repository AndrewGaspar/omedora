# Fedora config seeding — coexistence-safe variant of install/config/config.sh.
#
# Why this exists: the Arch body (cp -R config/* into ~/.config; cp default
# bashrc over ~/.bashrc) silently destroys user data on a lived-in machine — it
# overwrites ~60 colliding configs with no backup (worst: ~/.config/git/config,
# the user's git identity) and replaces the user's entire ~/.bashrc with a
# 9-line stub. On Fedora, omedora installs onto an existing Fedora Workstation,
# so destructive seeding is unacceptable.
#
# This variant:
#   - Seeds config/* with backup-then-write semantics (omedora-seed-config):
#     identical files are skipped, differing files are backed up to
#     <path>.pre-omedora-<ts> before being overwritten, and ~/.config/git/config
#     (the user's git identity) is never touched.
#   - Appends a sentinel-guarded sourcing block to ~/.bashrc instead of
#     overwriting it. Idempotent: the block is only added if absent.
#
# Dispatched from install/config/config.sh's Fedora guard. The Arch body there
# is unchanged.

set -euo pipefail

# --- Seed config/* (backup-then-write; skips the user's git/config) ---------

# Build the seed skip-list. The user's git identity is always protected.
seed_skip="git/config"

# fcitx IME env vars: config/environment.d/fcitx.conf points QT/SDL/X input
# modules at fcitx. But fcitx is NOT in omedora's Fedora package set, so seeding
# it on Fedora aims IME env vars at uninstalled software and can break Qt/SDL
# text input. Skip seeding it unless fcitx is actually installed on this machine.
# (Arch installs fcitx upstream, so this only applies to the Fedora path, which
# is the only path that reaches config-fedora.sh.)
#
# fcitx_installed: true if fcitx is present. Wrapped in a function so tests can
# force either branch via OMEDORA_FCITX_INSTALLED (1/0) without depending on
# whatever the test host happens to have installed.
fcitx_installed() {
  case "${OMEDORA_FCITX_INSTALLED:-}" in
    1) return 0 ;;
    0) return 1 ;;
  esac
  command -v fcitx5 >/dev/null 2>&1 || command -v fcitx >/dev/null 2>&1
}

if fcitx_installed; then
  echo -e "\033[32momedora: fcitx detected; seeding environment.d/fcitx.conf\033[0m"
else
  echo -e "\033[33momedora: fcitx not installed; skipping environment.d/fcitx.conf (would point IME env vars at uninstalled software)\033[0m"
  seed_skip+=$'\n'"environment.d/fcitx.conf"
fi

OMEDORA_SEED_SKIP="$seed_skip" \
  omedora-seed-config --source ~/.local/share/omarchy/config --dest ~/.config

# --- ~/.bashrc: append a sentinel-guarded sourcing block, never overwrite ----
#
# The omarchy default bashrc sources ~/.local/share/omarchy/default/bash/rc
# (after an early non-interactive return). We reproduce that wiring inside a
# guarded block appended to whatever ~/.bashrc the user already has, so their
# customizations survive. If ~/.bashrc is absent, we create a minimal one with
# just the block.

bashrc="${HOME}/.bashrc"
sentinel_open="# >>> omedora >>>"
sentinel_close="# <<< omedora <<<"

read -r -d '' omedora_block <<'BLOCK' || true
# >>> omedora >>>
# Managed by omedora. Sources the omarchy default bash configuration
# (aliases, functions, exports). Edit your own additions OUTSIDE this block.
if [[ $- == *i* && -r ~/.local/share/omarchy/default/bash/rc ]]; then
  source ~/.local/share/omarchy/default/bash/rc
fi
# <<< omedora <<<
BLOCK

if [[ -f $bashrc ]] && grep -qF "$sentinel_open" "$bashrc"; then
  echo -e "\033[32momedora: ~/.bashrc already has the omedora block; leaving it untouched\033[0m"
else
  {
    # Separate from any preceding content.
    [[ -s $bashrc ]] && printf '\n'
    printf '%s\n' "$omedora_block"
  } >>"$bashrc"
  echo -e "\033[32momedora: appended omedora sourcing block to ~/.bashrc (your existing ~/.bashrc was preserved)\033[0m"
fi
