#!/bin/bash
#
# L1 unit tests for install/config/xcompose.sh backup-before-overwrite behavior.
#
# Upstream omarchy writes ~/.XCompose wholesale (tee), discarding any user
# Compose customizations. On Fedora (a lived-in machine) omedora backs up an
# existing ~/.XCompose to ~/.XCompose.pre-omedora-<ts> before overwriting it,
# but only when it exists AND differs. The Arch path is byte-identical to
# upstream (unconditional tee, no backup).
#
# Verified here (offline, distro selected via OMARCHY_DISTRO):
#   - Fedora, existing DIFFERING ~/.XCompose -> backup created, then overwritten.
#   - Fedora, no existing ~/.XCompose        -> no backup, file written.
#   - Fedora, existing IDENTICAL ~/.XCompose -> no backup (nothing to preserve).
#   - Arch,   existing DIFFERING ~/.XCompose -> NO backup (upstream parity).
#
# omarchy-distro (real, from bin/) is selected via OMARCHY_DISTRO. $HOME is a
# throwaway dir so the real ~/.XCompose is never touched.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SCRIPT="$ROOT/install/config/xcompose.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export PATH="$ROOT/bin:$PATH"
export OMARCHY_USER_NAME="Ada Lovelace"
export OMARCHY_USER_EMAIL="ada@example.com"

backups_in() { ls "$1"/.XCompose.pre-omedora-* 2>/dev/null; }
backup_count() { backups_in "$1" | wc -l | tr -d ' '; }

# Run xcompose.sh under a fresh $HOME with the given distro. Echoes the HOME.
run_xcompose() {
  local distro="$1" preset="${2-}"
  local home="$TMPDIR/home-$distro-$RANDOM"
  mkdir -p "$home"
  [[ -n $preset ]] && printf '%s' "$preset" >"$home/.XCompose"
  (
    export HOME="$home"
    export OMARCHY_DISTRO="$distro"
    bash "$SCRIPT"
  ) >/dev/null 2>&1
  printf '%s\n' "$home"
}

# --- Fedora, existing differing ~/.XCompose -> backed up --------------------
home=$(run_xcompose fedora $'# my own compose rules\n<Multi_key> <x> : "custom"\n')
assert_equals "Fedora differing: exactly one backup created" "$(backup_count "$home")" "1"
backup=$(backups_in "$home" | head -n1)
assert_output_contains "Fedora differing: backup holds the user's original" \
  "$(cat "$backup")" 'my own compose rules'
assert_output_contains "Fedora differing: ~/.XCompose now has omedora's identity line" \
  "$(cat "$home/.XCompose")" "ada@example.com"

# --- Fedora, no existing ~/.XCompose -> no backup ---------------------------
home=$(run_xcompose fedora "")
assert_equals "Fedora absent: no backup created" "$(backup_count "$home")" "0"
assert_file_exists "Fedora absent: ~/.XCompose written" "$home/.XCompose"

# --- Fedora, existing IDENTICAL ~/.XCompose -> no backup ---------------------
# Build the exact payload the script writes, then pre-seed it.
identical=$(cat <<EOF
# Run omarchy-restart-xcompose to apply changes

# Include fast emoji access
include "%H/.local/share/omarchy/default/xcompose"

# Identification
<Multi_key> <space> <n> : "$OMARCHY_USER_NAME"
<Multi_key> <space> <e> : "$OMARCHY_USER_EMAIL"
EOF
)
home=$(run_xcompose fedora "$identical"$'\n')
assert_equals "Fedora identical: no backup created (nothing to preserve)" \
  "$(backup_count "$home")" "0"

# --- Arch, existing differing ~/.XCompose -> NO backup (upstream parity) -----
home=$(run_xcompose arch $'# arch user rules\n<Multi_key> <a> : "arch"\n')
assert_equals "Arch differing: NO backup (byte-identical to upstream)" \
  "$(backup_count "$home")" "0"
assert_output_contains "Arch differing: ~/.XCompose overwritten with omedora's" \
  "$(cat "$home/.XCompose")" "ada@example.com"

echo "# all xcompose-backup tests passed"
