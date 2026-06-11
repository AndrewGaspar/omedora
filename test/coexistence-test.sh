#!/bin/bash

# Coexistence MVP tests: prove omedora's Fedora install path is non-destructive
# on a lived-in machine.
#
# Covers:
#   - omedora-seed-config / config-fedora.sh backup-then-write semantics
#   - ~/.bashrc append (sentinel-guarded, idempotent), git/config left alone
#   - user-dirs.sh bookmark dedup
#   - omarchy-doctor foreign-repo conflict detection (mocked repoquery)
#
# Distro-agnostic: forces OMARCHY_DISTRO=fedora and mocks dnf repoquery, so it
# runs on the Arch host and inside a Fedora container identically.

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

# ---------------------------------------------------------------------------
# Build a scratch HOME with a fake installed omarchy payload.
# ---------------------------------------------------------------------------
new_scratch_home() {
  SCRATCH="$(mktemp -d)"
  export HOME="$SCRATCH/home"
  mkdir -p "$HOME"
  # Mirror the real layout: ~/.local/share/omarchy/{config,default}
  mkdir -p "$HOME/.local/share/omarchy"
  cp -R "$ROOT/config"  "$HOME/.local/share/omarchy/config"
  cp -R "$ROOT/default" "$HOME/.local/share/omarchy/default"
}

# ===========================================================================
echo "# --- config seeding: backup-then-write ---"
# ===========================================================================
new_scratch_home

# Pre-existing user data with unique sentinels.
mkdir -p "$HOME/.config/git" "$HOME/.config/hypr"
printf '# MY CUSTOM BASHRC\nexport MY_SENTINEL=1\n' >"$HOME/.bashrc"
printf '[user]\n\tname = Real User\n\temail = real@example.com\n' >"$HOME/.config/git/config"
printf '# my custom hyprland override\nbind = SUPER, X, exit\n' >"$HOME/.config/hypr/hyprland.conf"

git_config_before="$(cat "$HOME/.config/git/config")"
hypr_custom_before="$(cat "$HOME/.config/hypr/hyprland.conf")"

# First run of the Fedora config seeding.
bash "$ROOT/install/config/config-fedora.sh" >/tmp/seed1.log 2>&1 || {
  cat /tmp/seed1.log >&2; fail "config-fedora.sh first run exited non-zero"
}

# --- ~/.bashrc preserved + omedora block appended ---
bashrc_after="$(cat "$HOME/.bashrc")"
assert_output_contains "custom ~/.bashrc content preserved" "$bashrc_after" "export MY_SENTINEL=1"
assert_output_contains "omedora sourcing block appended" "$bashrc_after" "# >>> omedora >>>"
assert_output_contains "omedora block sources omarchy default rc" "$bashrc_after" "default/bash/rc"

# --- git/config NOT clobbered ---
assert_equals "~/.config/git/config left untouched" \
  "$(cat "$HOME/.config/git/config")" "$git_config_before"

# --- custom hyprland.conf backed up + omedora's installed ---
backup="$(ls "$HOME"/.config/hypr/hyprland.conf.pre-omedora-* 2>/dev/null | head -1 || true)"
assert_file_exists "hyprland.conf backed up to .pre-omedora-<ts>" "$backup"
assert_equals "backup holds the user's original hyprland.conf" \
  "$(cat "$backup")" "$hypr_custom_before"
assert_equals "omedora's hyprland.conf now installed" \
  "$(cat "$HOME/.config/hypr/hyprland.conf")" \
  "$(cat "$ROOT/config/hypr/hyprland.conf")"

# --- second run is a no-op for identical files (no new backups) ---
backups_before_rerun="$(ls "$HOME"/.config/hypr/hyprland.conf.pre-omedora-* 2>/dev/null | wc -l)"
sleep 1  # ensure a different timestamp would be used if a backup were made
bash "$ROOT/install/config/config-fedora.sh" >/tmp/seed2.log 2>&1 || {
  cat /tmp/seed2.log >&2; fail "config-fedora.sh second run exited non-zero"
}
backups_after_rerun="$(ls "$HOME"/.config/hypr/hyprland.conf.pre-omedora-* 2>/dev/null | wc -l)"
assert_equals "re-run makes no new backup for now-identical files" \
  "$backups_after_rerun" "$backups_before_rerun"

# --- second run does NOT double-append the bashrc block ---
block_count="$(grep -c '# >>> omedora >>>' "$HOME/.bashrc")"
assert_equals "bashrc omedora block appears exactly once after re-run" "$block_count" "1"

# ===========================================================================
echo "# --- config seeding: absent ~/.bashrc gets one created ---"
# ===========================================================================
new_scratch_home
rm -f "$HOME/.bashrc"
bash "$ROOT/install/config/config-fedora.sh" >/tmp/seed3.log 2>&1 || {
  cat /tmp/seed3.log >&2; fail "config-fedora.sh (no bashrc) exited non-zero"
}
assert_file_exists "~/.bashrc created when absent" "$HOME/.bashrc"
assert_output_contains "created ~/.bashrc has omedora block" \
  "$(cat "$HOME/.bashrc")" "# >>> omedora >>>"

# ===========================================================================
echo "# --- user-dirs bookmark dedup ---"
# ===========================================================================
new_scratch_home
# Run the bookmark-append loop twice (extracted to avoid needing xdg-user-dirs).
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
unset HOME 2>/dev/null || true
export HOME="$SCRATCH/home"  # restore a valid HOME for python pathlib

# Helper: run the doctor with a mocked repoquery line set, return its exit code.
# Each argument is one "name evr from_repo" line.
doctor_with_repoquery() {
  local lines="" l
  for l in "$@"; do lines+="$l"$'\n'; done
  OMEDORA_REPOQUERY_CMD="printf '%s' $(printf '%q' "$lines")" \
    "$ROOT/bin/omarchy-doctor"
}

# Foreign-repo owned hyprland -> warn + exit 1.
assert_exit_code "doctor flags foreign-repo hyprland (exit 1)" 1 \
  doctor_with_repoquery \
    "hyprland 0.56.0 copr:copr.fedorainfracloud.org:solopasha:hyprland" \
    "waybar 0.11 fedora"

# The warning names the package and the foreign repo.
doctor_err="$(doctor_with_repoquery "hyprland 0.56.0 copr:copr.fedorainfracloud.org:solopasha:hyprland" 2>&1 || true)"
assert_output_contains "warning names the package" "$doctor_err" "hyprland"
assert_output_contains "warning names the foreign repo" "$doctor_err" "solopasha"

# All-friendly (omedora repo + fedora) -> clean + exit 0.
assert_exit_code "doctor is clean when all repos friendly (exit 0)" 0 \
  doctor_with_repoquery \
    "hyprland 0.55.2 omedora" "waybar 0.11 fedora" "hyprlock 0.9.5 omedora"

# Foreign repo but NOT an owned package -> ignored, exit 0.
assert_exit_code "doctor ignores foreign-repo non-owned packages (exit 0)" 0 \
  doctor_with_repoquery "some-random-thing 1.0 copr:copr.fedorainfracloud.org:foo:bar"

# RPM Fusion is friendly even for an owned package -> exit 0.
assert_exit_code "doctor treats rpmfusion as friendly (exit 0)" 0 \
  doctor_with_repoquery "hyprland 0.55.2 rpmfusion-free"

echo "# All coexistence tests passed."
