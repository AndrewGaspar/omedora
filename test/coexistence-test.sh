#!/bin/bash

# Coexistence tests (Omarchy 4 flow): prove omedora's Fedora install path is
# non-destructive on a lived-in machine. Ported from the 3.8.2 suite, which
# targeted install/config/config-fedora.sh (retired — the v4 flow seeds via
# omedora-adopt-user/omedora-seed-config and never touches ~/.bashrc).
#
# Covers:
#   - omedora-seed-config backup-then-write semantics + idempotent re-runs
#   - install/user/xcompose.sh: Fedora backs up a differing ~/.XCompose first;
#     re-run with identical content makes no new backup; Arch path untouched
#   - the finalize-user GTK bookmark dedup loop
#   - omarchy-doctor foreign-repo conflict detection (mocked repoquery)
#
# Distro-agnostic: forces OMARCHY_DISTRO and mocks dnf repoquery, so it runs
# on the Arch host and inside a Fedora container identically.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export PATH="$ROOT/bin:$PATH"
export OMARCHY_DISTRO=fedora
export OMARCHY_PATH="$ROOT"
export OMARCHY_INSTALL="$ROOT/install"

. "$ROOT/test/helpers.sh"

SCRATCH=""
cleanup() { [[ -n $SCRATCH && -d $SCRATCH ]] && rm -rf "$SCRATCH"; }
trap cleanup EXIT

new_scratch_home() {
  SCRATCH="${SCRATCH:-$(mktemp -d)}"
  export HOME="$SCRATCH/home-$1"
  rm -rf "$HOME"
  mkdir -p "$HOME"
}

# ===========================================================================
echo "# --- config seeding: backup-then-write ---"
# ===========================================================================
new_scratch_home seed

mkdir -p "$HOME/.config/git" "$HOME/.config/hypr"
printf '[user]\n\tname = Real User\n' >"$HOME/.config/git/config"
printf '%s\n' '-- my custom hyprland override' >"$HOME/.config/hypr/hyprland.lua"

git_config_before="$(cat "$HOME/.config/git/config")"
hypr_custom_before="$(cat "$HOME/.config/hypr/hyprland.lua")"

# First seeding pass (what omedora-adopt-user execs, against the repo payload).
omedora-seed-config --source "$ROOT/config" --dest "$HOME/.config" >/tmp/seed1.log 2>&1 || {
  cat /tmp/seed1.log >&2; fail "seed-config first run exited non-zero"
}

# --- git/config NOT clobbered ---
assert_equals "~/.config/git/config left untouched" \
  "$(cat "$HOME/.config/git/config")" "$git_config_before"

# --- custom hyprland.lua backed up + omedora's installed ---
backup="$(ls "$HOME"/.config/hypr/hyprland.lua.pre-omedora-* 2>/dev/null | head -1 || true)"
assert_file_exists "hyprland.lua backed up to .pre-omedora-<ts>" "$backup"
assert_equals "backup holds the user's original hyprland.lua" \
  "$(cat "$backup")" "$hypr_custom_before"
assert_equals "omedora's hyprland.lua now installed" \
  "$(cat "$HOME/.config/hypr/hyprland.lua")" "$(cat "$ROOT/config/hypr/hyprland.lua")"

# --- second run is a no-op for identical files (no new backups) ---
backups_before_rerun="$(ls "$HOME"/.config/hypr/*.pre-omedora-* 2>/dev/null | wc -l)"
sleep 1  # a different timestamp would be used if a backup were made
omedora-seed-config --source "$ROOT/config" --dest "$HOME/.config" >/tmp/seed2.log 2>&1 || {
  cat /tmp/seed2.log >&2; fail "seed-config second run exited non-zero"
}
backups_after_rerun="$(ls "$HOME"/.config/hypr/*.pre-omedora-* 2>/dev/null | wc -l)"
assert_equals "re-run makes no new backup for now-identical files" \
  "$backups_after_rerun" "$backups_before_rerun"

# ===========================================================================
echo "# --- install/user/xcompose.sh: Fedora backup-then-write ---"
# ===========================================================================
new_scratch_home xcompose
export OMARCHY_USER_NAME="Test User" OMARCHY_USER_EMAIL="test@example.com"

printf '<Multi_key> <o> <k> : "MY CUSTOM COMPOSE"\n' >"$HOME/.XCompose"
custom_compose="$(cat "$HOME/.XCompose")"

bash "$ROOT/install/user/xcompose.sh" >/dev/null
xbackup="$(ls "$HOME"/.XCompose.pre-omedora-* 2>/dev/null | head -1 || true)"
assert_file_exists "existing ~/.XCompose backed up before overwrite" "$xbackup"
assert_equals "XCompose backup holds the user's original" "$(cat "$xbackup")" "$custom_compose"
assert_output_contains "omedora's XCompose now installed (identification line)" \
  "$(cat "$HOME/.XCompose")" 'Test User'
assert_output_contains "omedora's XCompose includes the shared compose payload" \
  "$(cat "$HOME/.XCompose")" 'include "/usr/share/omarchy/default/xcompose"'

# Re-run: content identical -> NO new backup.
n_before="$(ls "$HOME"/.XCompose.pre-omedora-* 2>/dev/null | wc -l)"
sleep 1
bash "$ROOT/install/user/xcompose.sh" >/dev/null
n_after="$(ls "$HOME"/.XCompose.pre-omedora-* 2>/dev/null | wc -l)"
assert_equals "XCompose re-run makes no new backup (identical content)" "$n_after" "$n_before"

# Arch path: unconditional tee, NO backup (upstream parity).
new_scratch_home xcompose-arch
printf 'custom\n' >"$HOME/.XCompose"
OMARCHY_DISTRO=arch bash "$ROOT/install/user/xcompose.sh" >/dev/null
assert_equals "Arch path makes no backup (upstream parity)" \
  "$(ls "$HOME"/.XCompose.pre-omedora-* 2>/dev/null | wc -l)" "0"
assert_output_contains "Arch path still wrote omarchy's XCompose" \
  "$(cat "$HOME/.XCompose")" 'omarchy-restart-xcompose'

# ===========================================================================
echo "# --- GTK bookmark dedup (finalize-user loop) ---"
# ===========================================================================
new_scratch_home bookmarks
run_bookmarks() {
  mkdir -p "$HOME/.config/gtk-3.0"
  touch "$HOME/.config/gtk-3.0/bookmarks"
  for dir in Downloads Projects Pictures Videos; do
    bookmark="$(printf 'file://%s/%s %s' "$HOME" "$dir" "$dir")"
    grep -qxF "$bookmark" "$HOME/.config/gtk-3.0/bookmarks" ||
      printf '%s\n' "$bookmark" >>"$HOME/.config/gtk-3.0/bookmarks"
  done
}
run_bookmarks
run_bookmarks
lines="$(wc -l <"$HOME/.config/gtk-3.0/bookmarks")"
assert_equals "bookmarks file has exactly 4 lines after two runs (no dupes)" "$lines" "4"

# ===========================================================================
echo "# --- conflict detection (mocked repoquery) ---"
# ===========================================================================
new_scratch_home doctor

doctor_with_repoquery() {
  local lines="" l
  for l in "$@"; do lines+="$l"$'\n'; done
  OMEDORA_REPOQUERY_CMD="printf '%s' $(printf '%q' "$lines")" \
    "$ROOT/bin/omarchy-doctor"
}

assert_exit_code "doctor flags foreign-repo hyprland (exit 1)" 1 \
  doctor_with_repoquery \
    "hyprland 0.56.0 copr:copr.fedorainfracloud.org:solopasha:hyprland" \
    "waybar 0.11 fedora"

doctor_err="$(doctor_with_repoquery "hyprland 0.56.0 copr:copr.fedorainfracloud.org:solopasha:hyprland" 2>&1 || true)"
assert_output_contains "warning names the package" "$doctor_err" "hyprland"
assert_output_contains "warning names the foreign repo" "$doctor_err" "solopasha"

assert_exit_code "doctor is clean when all repos friendly (exit 0)" 0 \
  doctor_with_repoquery \
    "hyprland 0.55.2 omedora" "btop 1.4 fedora" "hyprlock 0.9.5 omedora"

assert_exit_code "doctor ignores foreign-repo non-owned packages (exit 0)" 0 \
  doctor_with_repoquery "some-random-thing 1.0 copr:copr.fedorainfracloud.org:foo:bar"

assert_exit_code "doctor treats the omedora COPR as friendly (exit 0)" 0 \
  doctor_with_repoquery "hyprland 0.55.2 copr:copr.fedorainfracloud.org:agaspar:omedora-4"

# Regression: an owned package whose provenance is an OPAQUE hash id (image-base
# build, or a removed repo definition — NOT a foreign COPR) must be treated as
# benign, not flagged. Previously every unrecognized repo id was called foreign,
# so a lived-in machine's stock packages carrying a hash from_repo spammed the
# install plan with bogus "foreign Hyprland stack" warnings for jq/tmux/cups/etc.
assert_exit_code "doctor ignores opaque hash-id provenance for a compositor pkg (exit 0)" 0 \
  doctor_with_repoquery "hyprland 0.55.2 19278be6a81040f5b6cbc7bacea5148e"
assert_exit_code "doctor ignores opaque hash-id provenance for a base pkg (exit 0)" 0 \
  doctor_with_repoquery "tmux 3.6a 19278be6a81040f5b6cbc7bacea5148e"

# But a genuine foreign COPR mixed in with opaque-provenance packages is still
# caught (only the COPR package is the conflict).
assert_exit_code "doctor still flags a foreign COPR alongside opaque-id pkgs (exit 1)" 1 \
  doctor_with_repoquery \
    "tmux 3.6a 19278be6a81040f5b6cbc7bacea5148e" \
    "hyprland 0.56.0 copr:copr.fedorainfracloud.org:solopasha:hyprland"

echo "# all coexistence tests passed"
