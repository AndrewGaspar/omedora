#!/bin/bash

# Coexistence plan-then-confirm gate tests.
#
# Proves the up-front "here's what I'll back up — proceed?" gate
# (install/preflight/fedora-plan.sh) and the dry-run classifier it consumes
# (omedora-seed-config --plan):
#
#   PART 1 — omedora-seed-config --plan classifies every per-file STATE and
#            writes NOTHING:
#              create     destination missing
#              identical  byte-identical destination
#              backup     destination exists & differs
#              protected  on the skip list (git/config)
#
#   PART 2 — fedora-plan.sh takes the right PATH for each user state:
#              A  interactive + proceed       -> exit 0, gum asked, nothing written
#              B  interactive + abort         -> exit 1, nothing written
#              C  non-interactive + conflicts -> exit 0 (warn + proceed)
#              D  clean (no backups/foreign)  -> exit 0, NOT prompted
#              E  foreign-repo pkg, no config -> still prompts (abort -> exit 1)
#
#   PART 3 — proceed -> apply: once the gate proceeds, the config phase
#            (config-fedora.sh) actually performs the backup-then-write.
#
# Distro-agnostic: omarchy-doctor is driven by a mocked repoquery
# (OMEDORA_REPOQUERY_CMD), and the gate's interactivity + confirm are forced via
# OMEDORA_PLAN_FORCE_* and a fake `gum` shim, so this runs identically on the
# Arch host and inside a Fedora container. The gate is dry-run only, so every
# case asserts the filesystem is untouched.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export OMARCHY_DISTRO=fedora
export OMARCHY_PATH="$ROOT"
export OMARCHY_INSTALL="$ROOT/install"

. "$ROOT/test/helpers.sh"

SCRATCH=""
SHIM=""
cleanup() { [[ -n $SCRATCH && -d $SCRATCH ]] && rm -rf "$SCRATCH"; }
trap cleanup EXIT

# A fake `gum` whose `confirm` exit code is FAKE_GUM_CONFIRM (0=yes default) and
# which records each invocation by touching $GUM_CALLED — lets a test assert the
# gate did (or did NOT) prompt.
make_shim() {
  SHIM="$SCRATCH/shim"
  mkdir -p "$SHIM"
  cat >"$SHIM/gum" <<'EOF'
#!/bin/bash
case "$1" in
  confirm)
    [[ -n ${GUM_CALLED:-} ]] && touch "$GUM_CALLED"
    exit ${FAKE_GUM_CONFIRM:-0} ;;
  choose)
    [[ -n ${GUM_CALLED:-} ]] && touch "$GUM_CALLED"
    printf '%s\n' "${FAKE_GUM_CHOOSE:-Abort}" ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$SHIM/gum"
  # Fake findmnt: report root fstype as $FAKE_FSTYPE (default ext4 so the btrfs
  # snapshot offer is OFF unless a test opts in).
  cat >"$SHIM/findmnt" <<'EOF'
#!/bin/bash
case "$*" in *FSTYPE*) printf '%s\n' "${FAKE_FSTYPE:-ext4}" ;; esac
EOF
  chmod +x "$SHIM/findmnt"
}

# Run the gate with the current environment; capture combined output + rc.
PLAN_OUT=""; PLAN_RC=0
run_gate() {
  set +e
  PLAN_OUT="$(bash "$ROOT/install/preflight/fedora-plan.sh" 2>&1)"
  PLAN_RC=$?
  set -e
}

SCRATCH="$(mktemp -d)"
make_shim
export PATH="$ROOT/bin:$SHIM:$PATH"

# ===========================================================================
echo "# --- PART 1: omedora-seed-config --plan classifies each state, writes nothing ---"
# ===========================================================================
SRC="$SCRATCH/p1/src"; DST="$SCRATCH/p1/dst"
mkdir -p "$SRC/hypr" "$SRC/git" "$DST/hypr" "$DST/git"
printf 'new\n'        >"$SRC/hypr/new.conf"                               # create
printf 'same\n'       >"$SRC/hypr/same.conf"; cp "$SRC/hypr/same.conf" "$DST/hypr/same.conf"  # identical
printf 'omedora\n'    >"$SRC/hypr/diff.conf"; printf 'user\n' >"$DST/hypr/diff.conf"          # backup
printf 'omedora-git\n'>"$SRC/git/config";     printf 'user-git\n' >"$DST/git/config"          # protected

plan="$(OMEDORA_SEED_SKIP='git/config' \
  omedora-seed-config --plan --source "$SRC" --dest "$DST" 2>/dev/null)"

assert_output_contains "plan: missing dest -> create"       "$plan" $'create\thypr/new.conf'
assert_output_contains "plan: identical dest -> identical"  "$plan" $'identical\thypr/same.conf'
assert_output_contains "plan: differing dest -> backup"     "$plan" $'backup\thypr/diff.conf'
assert_output_contains "plan: skip-listed dest -> protected" "$plan" $'protected\tgit/config'

# Dry run must not write: no backups created, no destination mutated.
assert_equals "plan made no .pre-omedora backups" \
  "$(ls "$DST"/hypr/*.pre-omedora-* 2>/dev/null | wc -l)" "0"
assert_equals "plan left the differing file untouched" "$(cat "$DST/hypr/diff.conf")" "user"
assert_equals "plan left the protected git/config untouched" "$(cat "$DST/git/config")" "user-git"
assert_equals "plan did not create the missing file" \
  "$([[ -e $DST/hypr/new.conf ]] && echo exists || echo absent)" "absent"

# Plan summary (stderr) reports the counts.
plan_err="$(OMEDORA_SEED_SKIP='git/config' \
  omedora-seed-config --plan --source "$SRC" --dest "$DST" 2>&1 >/dev/null)"
assert_output_contains "plan summary reports 1 create / 1 backup" \
  "$plan_err" "would create 1, back up 1"

# ===========================================================================
echo "# --- PART 2: fedora-plan.sh gate paths ---"
# ===========================================================================

# Shared setup for a "lived-in machine with one conflicting config file" and a
# CLEAN doctor (no foreign-repo packages). Each case overrides as needed.
gate_home() {  # $1 = case dir
  local d="$SCRATCH/$1"
  rm -rf "$d"; mkdir -p "$d/src/hypr" "$d/home/.config/hypr"
  printf 'omedora\n' >"$d/src/hypr/diff.conf"
  printf 'user\n'    >"$d/home/.config/hypr/diff.conf"
  export HOME="$d/home"
  export OMEDORA_PLAN_SOURCE="$d/src"
  export OMEDORA_PLAN_DEST="$d/home/.config"
}
# Snapshot helper: count backups under a case's config tree.
backup_count() { ls "$HOME"/.config/hypr/*.pre-omedora-* 2>/dev/null | wc -l; }

# --- A: interactive + PROCEED -> exit 0, gum was asked, nothing written ------
gate_home A
export OMEDORA_REPOQUERY_CMD="printf ''"     # doctor clean
export OMEDORA_PLAN_FORCE_INTERACTIVE=1
export GUM_CALLED="$SCRATCH/A.gum"; rm -f "$GUM_CALLED"
FAKE_GUM_CONFIRM=0 run_gate
assert_equals "A: interactive proceed exits 0" "$PLAN_RC" "0"
assert_file_exists "A: gum confirm was invoked" "$GUM_CALLED"
assert_output_contains "A: plan listed the file to back up" "$PLAN_OUT" "hypr/diff.conf"
assert_output_contains "A: proceed message shown" "$PLAN_OUT" "proceeding"
assert_equals "A: gate (dry run) wrote no backups" "$(backup_count)" "0"
assert_equals "A: gate left the user's file untouched" "$(cat "$HOME/.config/hypr/diff.conf")" "user"

# --- B: interactive + ABORT -> exit 1, nothing written ----------------------
gate_home B
export GUM_CALLED="$SCRATCH/B.gum"; rm -f "$GUM_CALLED"
FAKE_GUM_CONFIRM=1 run_gate                  # gum confirm says "no"
assert_equals "B: interactive abort exits 1" "$PLAN_RC" "1"
assert_file_exists "B: gum confirm was invoked" "$GUM_CALLED"
assert_output_contains "B: abort message shown" "$PLAN_OUT" "aborted at your request"
assert_equals "B: abort wrote no backups" "$(backup_count)" "0"
assert_equals "B: abort left the user's file untouched" "$(cat "$HOME/.config/hypr/diff.conf")" "user"

# --- C: non-interactive + conflicts -> exit 0 (warn + proceed) --------------
gate_home C
unset OMEDORA_PLAN_FORCE_INTERACTIVE
export OMEDORA_PLAN_FORCE_NONINTERACTIVE=1
export GUM_CALLED="$SCRATCH/C.gum"; rm -f "$GUM_CALLED"
run_gate
assert_equals "C: non-interactive proceeds (exit 0)" "$PLAN_RC" "0"
assert_output_contains "C: warns it is proceeding non-interactively" \
  "$PLAN_OUT" "proceeding non-interactively"
assert_equals "C: non-interactive did NOT prompt (no gum)" \
  "$([[ -e $GUM_CALLED ]] && echo called || echo not)" "not"

# --- C2: non-interactive + a FOREIGN Hyprland -> ABORT (would file-conflict) --
# Can't ask whether to replace, and installing over it is a guaranteed conflict,
# so the gate must abort with guidance rather than proceed into failure.
gate_home C2
export OMEDORA_REPOQUERY_CMD="printf '%s\n' 'hyprland 0.55.1 copr:copr.fedorainfracloud.org:solopasha:hyprland'"
run_gate
assert_equals "C2: non-interactive + foreign Hyprland aborts (exit 1)" "$PLAN_RC" "1"
assert_output_contains "C2: abort explains the file conflict + the fix" \
  "$PLAN_OUT" "Aborting"
assert_output_contains "C2: abort points at omedora doctor --fix" \
  "$PLAN_OUT" "omedora doctor --fix"
export OMEDORA_REPOQUERY_CMD="printf ''"   # restore clean doctor for later cases
unset OMEDORA_PLAN_FORCE_NONINTERACTIVE

# --- D: clean machine (no backups, no foreign pkgs) -> proceed WITHOUT prompt -
#        source == dest contents, so every file is identical (no create/backup).
gate_home D
cp -f "$OMEDORA_PLAN_SOURCE/hypr/diff.conf" "$HOME/.config/hypr/diff.conf"  # make identical
export OMEDORA_PLAN_FORCE_INTERACTIVE=1
export OMEDORA_REPOQUERY_CMD="printf ''"     # doctor clean
export GUM_CALLED="$SCRATCH/D.gum"; rm -f "$GUM_CALLED"
FAKE_GUM_CONFIRM=1 run_gate                  # gum would say "no" IF asked
assert_equals "D: clean machine proceeds (exit 0)" "$PLAN_RC" "0"
assert_equals "D: clean machine did NOT prompt (no gum)" \
  "$([[ -e $GUM_CALLED ]] && echo called || echo not)" "not"
assert_output_contains "D: clean machine says nothing to back up" \
  "$PLAN_OUT" "no existing config files conflict"

# --- E: foreign-repo package present, but NO config backups -> still prompts -
#        empty source => no create/backup; doctor flags a foreign hyprland, so
#        the gate shows the 3-way Replace/Keep/Abort choose (the Replace/Keep
#        paths are covered in coexistence-replace-test.sh). Here: Abort -> exit 1.
gate_home E
export OMEDORA_PLAN_SOURCE="$SCRATCH/E/empty"; mkdir -p "$OMEDORA_PLAN_SOURCE"
export OMEDORA_REPOQUERY_CMD="printf '%s\n' 'hyprland 0.56.0 copr:copr.fedorainfracloud.org:solopasha:hyprland'"
export OMEDORA_PLAN_FORCE_INTERACTIVE=1
export GUM_CALLED="$SCRATCH/E.gum"; rm -f "$GUM_CALLED"
FAKE_GUM_CHOOSE=Abort run_gate
assert_equals "E: foreign-repo conflict forces a choice -> Abort exits 1" "$PLAN_RC" "1"
assert_file_exists "E: gum choose was invoked despite zero config backups" "$GUM_CALLED"
assert_output_contains "E: plan surfaces the foreign-repo package" "$PLAN_OUT" "solopasha"
unset OMEDORA_PLAN_FORCE_INTERACTIVE OMEDORA_REPOQUERY_CMD

# ===========================================================================
echo "# --- PART 3: proceed -> apply actually backs up ---"
# ===========================================================================
# Use the full installed-payload layout so config-fedora.sh's apply runs as in
# the real install, and confirm the gate's "proceed" leads to a real backup.
APPLY="$SCRATCH/p3/home"
mkdir -p "$APPLY/.local/share/omarchy" "$APPLY/.config/hypr"
cp -R "$ROOT/config"  "$APPLY/.local/share/omarchy/config"
cp -R "$ROOT/default" "$APPLY/.local/share/omarchy/default"
printf '# my custom hyprland\nbind = SUPER, X, exit\n' >"$APPLY/.config/hypr/hyprland.conf"
custom_before="$(cat "$APPLY/.config/hypr/hyprland.conf")"

export HOME="$APPLY"
unset OMEDORA_PLAN_SOURCE OMEDORA_PLAN_DEST

# 1) Gate sees the conflict and (non-interactively) proceeds, touching nothing.
export OMEDORA_PLAN_FORCE_NONINTERACTIVE=1
export OMEDORA_REPOQUERY_CMD="printf ''"
run_gate
assert_equals "P3: gate proceeds (exit 0)" "$PLAN_RC" "0"
assert_equals "P3: gate itself wrote no backup" \
  "$(ls "$APPLY"/.config/hypr/hyprland.conf.pre-omedora-* 2>/dev/null | wc -l)" "0"
unset OMEDORA_PLAN_FORCE_NONINTERACTIVE OMEDORA_REPOQUERY_CMD

# 2) The config phase then applies backup-then-write.
bash "$ROOT/install/config/config-fedora.sh" >/tmp/p3-apply.log 2>&1 || {
  cat /tmp/p3-apply.log >&2; fail "P3: config-fedora.sh apply exited non-zero"
}
backup="$(ls "$APPLY"/.config/hypr/hyprland.conf.pre-omedora-* 2>/dev/null | head -1 || true)"
assert_file_exists "P3: apply backed up the user's hyprland.conf" "$backup"
assert_equals "P3: backup holds the user's original" "$(cat "$backup")" "$custom_before"
assert_equals "P3: omedora's hyprland.conf is now installed" \
  "$(cat "$APPLY/.config/hypr/hyprland.conf")" "$(cat "$ROOT/config/hypr/hyprland.conf")"

# ===========================================================================
echo "# --- PART 4: btrfs root -> opt-in pre-install snapshot ---"
# ===========================================================================
# Clean config (no backups) so the snapshot offer is the only prompt.
gate_home S
cp -f "$OMEDORA_PLAN_SOURCE/hypr/diff.conf" "$HOME/.config/hypr/diff.conf"
export OMEDORA_PLAN_FORCE_INTERACTIVE=1
export OMEDORA_REPOQUERY_CMD="printf ''"   # doctor clean
unset OMEDORA_SNAPSHOT

# ext4 root -> NO snapshot offer at all.
FAKE_FSTYPE=ext4 run_gate
assert_output_lacks "non-btrfs root: no snapshot offer" "$PLAN_OUT" "Pre-install snapshot"

# btrfs root + yes -> offered and consented.
unset OMEDORA_SNAPSHOT
FAKE_FSTYPE=btrfs FAKE_GUM_CONFIRM=0 run_gate
assert_output_contains "btrfs root: offers a pre-install snapshot" "$PLAN_OUT" "Pre-install snapshot"
assert_output_contains "snapshot consented -> announced" "$PLAN_OUT" "A snapshot will be taken"

# btrfs root + no -> declining is honored.
unset OMEDORA_SNAPSHOT
FAKE_FSTYPE=btrfs FAKE_GUM_CONFIRM=1 run_gate
assert_output_contains "declining the snapshot is honored" "$PLAN_OUT" "Skipping the snapshot"

echo "# All coexistence plan-then-confirm tests passed."
