#!/bin/bash
#
# L1 unit tests for bin/omedora-adopt-user (+ the omarchy-reinstall-configs
# Fedora gate).
#
# Adoption is the Fedora replacement for /etc/skel-at-useradd AND for the
# destructive omarchy-reinstall-configs resync: replay a skel tree over $HOME
# with the backup-then-write contract (create / backup / identical /
# protected). The classification engine itself (omedora-seed-config) has its
# own suite in coexistence-test.sh — here we verify the adopt orchestration:
# skel sourcing, $HOME targeting, the protected-by-default git identity, plan
# mode writing nothing, and the reinstall-configs dispatch.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

export PATH="$ROOT/bin:$PATH"

# --- fixture: a fake omedora-settings /etc/skel payload -----------------------
SKEL="$TMPDIR/skel"
mkdir -p "$SKEL/.config/hypr" "$SKEL/.config/git" "$SKEL/.local/share/applications"
echo "shipped hyprland.lua" >"$SKEL/.config/hypr/hyprland.lua"
echo "shipped git config" >"$SKEL/.config/git/config"
echo "shipped desktop entry" >"$SKEL/.local/share/applications/omarchy.desktop"

fresh_home() {
  local home="$TMPDIR/home-$1"
  rm -rf "$home"
  mkdir -p "$home"
  printf '%s' "$home"
}

# --- fresh $HOME: everything (except protected) is created --------------------
H=$(fresh_home fresh)
HOME="$H" omedora-adopt-user --skel "$SKEL" >/dev/null 2>&1

[[ -f "$H/.config/hypr/hyprland.lua" ]] && pass "fresh home: config file created" \
  || fail "fresh home: config file created"
[[ -f "$H/.local/share/applications/omarchy.desktop" ]] && pass "fresh home: non-.config skel file created" \
  || fail "fresh home: non-.config skel file created"
[[ ! -e "$H/.config/git/config" ]] && pass "protected git identity is never written, even when absent" \
  || fail "protected git identity is never written, even when absent"

# --- lived-in $HOME: differing file backed up, identical untouched ------------
H=$(fresh_home livedin)
mkdir -p "$H/.config/hypr" "$H/.config/git"
echo "the user's own hypr config" >"$H/.config/hypr/hyprland.lua"
echo "the user's git identity" >"$H/.config/git/config"
echo "shipped desktop entry" >"$H/.local-placeholder" # noise; ignored

HOME="$H" omedora-adopt-user --skel "$SKEL" >/dev/null 2>&1

grep -q "shipped hyprland.lua" "$H/.config/hypr/hyprland.lua" \
  && pass "differing file replaced with shipped default" \
  || fail "differing file replaced with shipped default"
backup=$(ls "$H/.config/hypr/"hyprland.lua.pre-omedora-* 2>/dev/null | head -1)
[[ -n $backup ]] && grep -q "the user's own hypr config" "$backup" \
  && pass "differing file's original content preserved in a backup" \
  || fail "differing file's original content preserved in a backup"
grep -q "the user's git identity" "$H/.config/git/config" \
  && pass "protected git identity untouched on a lived-in home" \
  || fail "protected git identity untouched on a lived-in home"

# --- idempotency: second run makes no new backups ------------------------------
HOME="$H" omedora-adopt-user --skel "$SKEL" >/dev/null 2>&1
n_backups=$(ls "$H/.config/hypr/"hyprland.lua.pre-omedora-* 2>/dev/null | wc -l)
assert_equals "re-run is idempotent (no second backup)" "1" "$n_backups"

# --- --plan: classifies but writes nothing -------------------------------------
H=$(fresh_home plan)
mkdir -p "$H/.config/hypr"
echo "user file" >"$H/.config/hypr/hyprland.lua"

plan_out=$(HOME="$H" omedora-adopt-user --plan --skel "$SKEL" 2>/dev/null)
assert_output_contains "plan classifies the differing file as backup" "$plan_out" \
  "backup	.config/hypr/hyprland.lua"
assert_output_contains "plan classifies the missing file as create" "$plan_out" \
  "create	.local/share/applications/omarchy.desktop"
assert_output_contains "plan classifies the git identity as protected" "$plan_out" \
  "protected	.config/git/config"
grep -q "user file" "$H/.config/hypr/hyprland.lua" \
  && [[ ! -e "$H/.local/share/applications/omarchy.desktop" ]] \
  && pass "plan mode writes nothing" \
  || fail "plan mode writes nothing"

# --- missing skel fails loudly --------------------------------------------------
if HOME="$H" omedora-adopt-user --skel "$TMPDIR/does-not-exist" >/dev/null 2>&1; then
  fail "missing skel tree exits non-zero"
else
  pass "missing skel tree exits non-zero"
fi

# --- omarchy-reinstall-configs gate: Fedora dispatches, no cp -af ---------------
# Stub omedora-adopt-user + the nvim helpers onto PATH and verify dispatch.
BIN="$TMPDIR/bin"; mkdir -p "$BIN"
cat >"$BIN/omedora-adopt-user" <<'EOF'
#!/bin/bash
printf 'omedora-adopt-user %s\n' "$*" >>"$MOCK_LOG"
EOF
cat >"$BIN/omarchy-cmd-present" <<'EOF'
#!/bin/bash
exit 1
EOF
cat >"$BIN/cp" <<'EOF'
#!/bin/bash
printf 'cp %s\n' "$*" >>"$MOCK_LOG"
EOF
chmod +x "$BIN"/*
export MOCK_LOG="$TMPDIR/mock.log"
: >"$MOCK_LOG"

H=$(fresh_home gate)
HOME="$H" OMARCHY_DISTRO=fedora PATH="$BIN:$PATH" bash "$ROOT/bin/omarchy-reinstall-configs" >/dev/null 2>&1
grep -q "omedora-adopt-user --reset" "$MOCK_LOG" \
  && pass "reinstall-configs on Fedora dispatches to omedora-adopt-user --reset" \
  || { cat "$MOCK_LOG" >&2; fail "reinstall-configs on Fedora dispatches to omedora-adopt-user --reset"; }
grep -q "^cp " "$MOCK_LOG" \
  && fail "reinstall-configs on Fedora must not run the destructive cp -af" \
  || pass "reinstall-configs on Fedora must not run the destructive cp -af"

echo "# all adopt-user tests passed"
