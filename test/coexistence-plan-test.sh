#!/bin/bash

# Coexistence plan-then-confirm gate tests (Omarchy 4 flow).
#
# Proves the up-front "here's everything this install will do — proceed?" gate
# (omedora/install/plan.sh, the first step of omedora/install-4.sh) and the
# dry-run classifier it consumes (omedora-seed-config --plan). Ported from the
# 3.8.2 suite, which targeted install/preflight/fedora-plan.sh.
#
#   PART 1 — omedora-seed-config --plan classifies every per-file STATE and
#            writes NOTHING:
#              create     destination missing
#              identical  byte-identical destination
#              backup     destination exists & differs
#              protected  on the skip list (git/config)
#
#   PART 2 — plan.sh takes the right PATH for each state:
#              A  interactive + proceed       -> exit 0, gum asked, nothing written
#              B  interactive + abort         -> exit 1, nothing written
#              C  OMEDORA_PLAN_AUTOCONFIRM=1  -> exit 0, NOT prompted (CI seam)
#              C2 non-interactive + foreign   -> exit 1 (would file-conflict)
#              C3 non-interactive, no autoconfirm -> warn + proceed
#              D  clean machine               -> still prompts (the dnf
#                 transaction itself needs consent in v4), discloses "no
#                 backups"
#              E  foreign-repo pkg, interactive -> 3-way choose; Abort -> exit 1
#
#   PART 3 — disclosure: the plan surfaces the repos, the package transaction
#            (pkg.py dry-run), the /etc drop-ins, the only-if-unset default-app
#            policy, and the never-touch list.
#
#   PART 4 — proceed -> apply: the seeding engine the adopt step uses actually
#            performs backup-then-write after the gate's dry-run touched nothing.
#
#   PART 5 — btrfs root -> opt-in pre-install snapshot offer.
#
# Distro-agnostic: omarchy-doctor is driven by a mocked repoquery
# (OMEDORA_REPOQUERY_CMD), interactivity is forced via OMEDORA_PLAN_FORCE_*,
# and gum/findmnt are shimmed on PATH — so this runs identically on the Arch
# host, in CI, and inside a Fedora container.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export OMARCHY_DISTRO=fedora
export OMARCHY_PATH="$ROOT"
export OMARCHY_INSTALL="$ROOT/install"
export OMEDORA_REPO_ROOT="$ROOT"

PLAN="$ROOT/omedora/install/plan.sh"

. "$ROOT/test/helpers.sh"

SCRATCH=""
SHIM=""
cleanup() { [[ -n $SCRATCH && -d $SCRATCH ]] && rm -rf "$SCRATCH"; }
trap cleanup EXIT

# A fake `gum` whose `confirm` exit code is FAKE_GUM_CONFIRM (0=yes default) and
# which records each invocation by touching $GUM_CALLED.
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
  PLAN_OUT="$(bash "$PLAN" 2>&1)"
  PLAN_RC=$?
  set -e
}

SCRATCH="$(mktemp -d)"
make_shim
export PATH="$ROOT/bin:$SHIM:$PATH"
# Hermetic by default: skip the pkg.py dry-run except where PART 3 opts in.
export OMEDORA_PLAN_SKIP_PKGS=1

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

assert_output_contains "plan: missing dest -> create"        "$plan" $'create\thypr/new.conf'
assert_output_contains "plan: identical dest -> identical"   "$plan" $'identical\thypr/same.conf'
assert_output_contains "plan: differing dest -> backup"      "$plan" $'backup\thypr/diff.conf'
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
echo "# --- PART 2: plan.sh gate paths ---"
# ===========================================================================

# Shared setup: a lived-in machine with one conflicting config file, and a
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

# --- C: OMEDORA_PLAN_AUTOCONFIRM=1 -> exit 0, no prompt (the CI seam) --------
gate_home C
unset OMEDORA_PLAN_FORCE_INTERACTIVE
export OMEDORA_PLAN_AUTOCONFIRM=1
export GUM_CALLED="$SCRATCH/C.gum"; rm -f "$GUM_CALLED"
run_gate
assert_equals "C: autoconfirm proceeds (exit 0)" "$PLAN_RC" "0"
assert_output_contains "C: autoconfirm says it is proceeding" \
  "$PLAN_OUT" "OMEDORA_PLAN_AUTOCONFIRM set; proceeding"
assert_equals "C: autoconfirm did NOT prompt (no gum)" \
  "$([[ -e $GUM_CALLED ]] && echo called || echo not)" "not"
assert_output_contains "C: plan still disclosed the backup" "$PLAN_OUT" "hypr/diff.conf"
unset OMEDORA_PLAN_AUTOCONFIRM

# --- C2: non-interactive + a FOREIGN Hyprland -> ABORT (would file-conflict) --
gate_home C2
export OMEDORA_PLAN_FORCE_NONINTERACTIVE=1
export OMEDORA_REPOQUERY_CMD="printf '%s\n' 'hyprland 0.55.1 copr:copr.fedorainfracloud.org:solopasha:hyprland'"
run_gate
assert_equals "C2: non-interactive + foreign Hyprland aborts (exit 1)" "$PLAN_RC" "1"
assert_output_contains "C2: abort explains the conflict" "$PLAN_OUT" "Aborting"
assert_output_contains "C2: abort points at the pre-set seams" \
  "$PLAN_OUT" "OMEDORA_REPLACE_FOREIGN=1"
export OMEDORA_REPOQUERY_CMD="printf ''"   # restore clean doctor

# --- C3: non-interactive without autoconfirm -> warn + proceed ---------------
gate_home C3
export GUM_CALLED="$SCRATCH/C3.gum"; rm -f "$GUM_CALLED"
run_gate
assert_equals "C3: non-interactive proceeds (exit 0)" "$PLAN_RC" "0"
assert_output_contains "C3: warns it is proceeding non-interactively" \
  "$PLAN_OUT" "proceeding non-interactively"
assert_equals "C3: non-interactive did NOT prompt (no gum)" \
  "$([[ -e $GUM_CALLED ]] && echo called || echo not)" "not"
unset OMEDORA_PLAN_FORCE_NONINTERACTIVE

# --- D: clean machine -> still prompts (v4: the dnf transaction needs consent)
#        but discloses there is nothing to back up.
gate_home D
cp -f "$OMEDORA_PLAN_SOURCE/hypr/diff.conf" "$HOME/.config/hypr/diff.conf"  # identical
export OMEDORA_PLAN_FORCE_INTERACTIVE=1
export GUM_CALLED="$SCRATCH/D.gum"; rm -f "$GUM_CALLED"
FAKE_GUM_CONFIRM=0 run_gate
assert_equals "D: clean machine proceeds after confirm (exit 0)" "$PLAN_RC" "0"
assert_file_exists "D: clean machine still prompted (package transaction)" "$GUM_CALLED"
assert_output_contains "D: clean machine discloses no config conflicts" \
  "$PLAN_OUT" "No existing config files conflict"

# --- E: foreign-repo package, interactive -> 3-way choose; Abort -> exit 1 ---
gate_home E
export OMEDORA_PLAN_SOURCE="$SCRATCH/E/empty"; mkdir -p "$OMEDORA_PLAN_SOURCE"
export OMEDORA_REPOQUERY_CMD="printf '%s\n' 'hyprland 0.56.0 copr:copr.fedorainfracloud.org:solopasha:hyprland'"
export OMEDORA_DNF_CMD="echo dnf"            # replace-foreign --dry-run driver
export GUM_CALLED="$SCRATCH/E.gum"; rm -f "$GUM_CALLED"
FAKE_GUM_CHOOSE=Abort run_gate
assert_equals "E: foreign-repo conflict forces a choice -> Abort exits 1" "$PLAN_RC" "1"
assert_file_exists "E: gum choose was invoked despite zero config backups" "$GUM_CALLED"
assert_output_contains "E: plan surfaces the foreign-repo package" "$PLAN_OUT" "solopasha"
unset OMEDORA_PLAN_FORCE_INTERACTIVE OMEDORA_REPOQUERY_CMD OMEDORA_DNF_CMD

# ===========================================================================
echo "# --- PART 3: disclosure content ---"
# ===========================================================================
# One full run WITHOUT OMEDORA_PLAN_SKIP_PKGS: the real pkg.py dry-run resolves
# install/omarchy-base.packages through install/packages/fedora.toml.
# Hermetic installed-state: stub rpm so NO package counts as installed —
# otherwise the disclosed transaction shrinks on hosts that already have base
# packages (the post-install L3 smoke re-runs this suite on a fully installed
# system, where the btop assertion below would go empty).
P3_BIN="$SCRATCH/P3-bin"; mkdir -p "$P3_BIN"
printf '#!/bin/bash\nexit 1\n' >"$P3_BIN/rpm"; chmod +x "$P3_BIN/rpm"
gate_home P3d
unset OMEDORA_PLAN_SKIP_PKGS
export OMEDORA_PLAN_FORCE_NONINTERACTIVE=1 OMEDORA_PLAN_AUTOCONFIRM=1
_SAVED_PATH="$PATH"; export PATH="$P3_BIN:$PATH"
run_gate
export PATH="$_SAVED_PATH"
export OMEDORA_PLAN_SKIP_PKGS=1
unset OMEDORA_PLAN_FORCE_NONINTERACTIVE OMEDORA_PLAN_AUTOCONFIRM
assert_equals "P3: autoconfirmed disclosure run proceeds" "$PLAN_RC" "0"
assert_output_contains "P3: dnf transaction disclosed" "$PLAN_OUT" "dnf install"
assert_output_contains "P3: a real base package is in the transaction" "$PLAN_OUT" "btop"
assert_output_contains "P3: skip-mapped packages disclosed" "$PLAN_OUT" "ufw"
assert_output_contains "P3: omedora COPR disclosed" "$PLAN_OUT" "omedora-4"
assert_output_contains "P3: RPM Fusion disclosed" "$PLAN_OUT" "RPM Fusion"
assert_output_contains "P3: /etc drop-ins disclosed" "$PLAN_OUT" "ignore power button"
assert_output_contains "P3: docker daemon.json only-if-absent disclosed" "$PLAN_OUT" "ONLY"
assert_output_contains "P3: browser only-if-unset disclosed" \
  "$PLAN_OUT" "default browser + http(s) handlers — only if you have none set"
assert_output_contains "P3: mailto only-if-unset disclosed" \
  "$PLAN_OUT" "mailto handler — only if you have none set"
assert_output_contains "P3: XCompose backup disclosed" "$PLAN_OUT" "XCompose"
assert_output_contains "P3: lock-screen PAM addition disclosed" \
  "$PLAN_OUT" "omarchy-lock-password"
assert_output_contains "P3: never-touch list disclosed" "$PLAN_OUT" "NEVER touched"
assert_output_contains "P3: git identity protection disclosed" \
  "$PLAN_OUT" "git/config: never touched"

# ===========================================================================
echo "# --- PART 4: proceed -> apply actually backs up ---"
# ===========================================================================
# The gate is dry-run only; the adopt step's engine (omedora-seed-config,
# what omedora-adopt-user execs) then performs the backup-then-write.
APPLY="$SCRATCH/p4/home"
mkdir -p "$APPLY/.config/hypr"
printf '# my custom hyprland\n' >"$APPLY/.config/hypr/hyprland.lua"
custom_before="$(cat "$APPLY/.config/hypr/hyprland.lua")"

export HOME="$APPLY"
export OMEDORA_PLAN_SOURCE="$ROOT/config" OMEDORA_PLAN_DEST="$APPLY/.config"
export OMEDORA_PLAN_FORCE_NONINTERACTIVE=1 OMEDORA_PLAN_AUTOCONFIRM=1
export OMEDORA_REPOQUERY_CMD="printf ''"
run_gate
assert_equals "P4: gate proceeds (exit 0)" "$PLAN_RC" "0"
assert_equals "P4: gate itself wrote no backup" \
  "$(ls "$APPLY"/.config/hypr/hyprland.lua.pre-omedora-* 2>/dev/null | wc -l)" "0"
unset OMEDORA_PLAN_FORCE_NONINTERACTIVE OMEDORA_PLAN_AUTOCONFIRM OMEDORA_REPOQUERY_CMD

omedora-seed-config --source "$ROOT/config" --dest "$APPLY/.config" >/dev/null 2>&1 ||
  fail "P4: seed apply exited non-zero"
backup="$(ls "$APPLY"/.config/hypr/hyprland.lua.pre-omedora-* 2>/dev/null | head -1 || true)"
assert_file_exists "P4: apply backed up the user's hyprland.conf" "$backup"
assert_equals "P4: backup holds the user's original" "$(cat "$backup")" "$custom_before"
assert_equals "P4: omedora's hyprland.conf is now installed" \
  "$(cat "$APPLY/.config/hypr/hyprland.lua")" "$(cat "$ROOT/config/hypr/hyprland.lua")"

# ===========================================================================
echo "# --- PART 5: btrfs root -> opt-in pre-install snapshot ---"
# ===========================================================================
gate_home S
cp -f "$OMEDORA_PLAN_SOURCE/hypr/diff.conf" "$HOME/.config/hypr/diff.conf"
export OMEDORA_PLAN_FORCE_INTERACTIVE=1
export OMEDORA_REPOQUERY_CMD="printf ''"
unset OMEDORA_SNAPSHOT 2>/dev/null || true

# ext4 root -> NO snapshot offer at all.
FAKE_FSTYPE=ext4 FAKE_GUM_CONFIRM=0 run_gate
assert_equals "S: ext4 root never offers a snapshot" \
  "$(grep -c 'Pre-install snapshot' <<<"$PLAN_OUT" || true)" "0"

# btrfs root -> offer shown.
FAKE_FSTYPE=btrfs FAKE_GUM_CONFIRM=0 run_gate
assert_output_contains "S: btrfs root offers the snapshot" "$PLAN_OUT" "Pre-install snapshot"
assert_output_contains "S: opting in announces the snapshot" \
  "$PLAN_OUT" "A snapshot will be taken before any changes"

unset OMEDORA_PLAN_FORCE_INTERACTIVE OMEDORA_REPOQUERY_CMD

echo "# all coexistence-plan tests passed"
