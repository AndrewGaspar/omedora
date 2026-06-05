#!/bin/bash

# Coexistence foreign-package REPLACEMENT tests.
#
# Proves the replacement engine (omedora-replace-foreign, also `omedora doctor
# --fix`) and the install gate's Replace/Keep/Abort choice
# (install/preflight/fedora-plan.sh):
#
#   PART 1 — owned_packages.py --map: base -> omedora target(s)
#              rename (hyprland -> hyprland-omedora) vs same-name (waybar).
#
#   PART 2 — omarchy-doctor --list: machine-readable conflicts (name<TAB>repo).
#
#   PART 3 — engine builds the right dnf transaction per case:
#              rename   -> `dnf swap`     (foreign repo disabled)
#              samename -> `dnf distro-sync` (foreign repo disabled)
#              --dry-run changes nothing; non-interactive without --yes refuses;
#              --yes applies; clean system is a no-op.
#
#   PART 4 — gate Replace/Keep/Abort: Replace exports the consent flag and
#            fedora-swap.sh then applies; Keep/Abort do not.
#
# Distro-agnostic: detection is driven by a mocked repoquery
# (OMEDORA_REPOQUERY_CMD) and dnf by a fake logger (OMEDORA_DNF_CMD), so no real
# packages are touched and it runs on the Arch host or in a Fedora container.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
export OMARCHY_DISTRO=fedora
export OMARCHY_PATH="$ROOT"
export OMARCHY_INSTALL="$ROOT/install"
export PATH="$ROOT/bin:$PATH"

. "$ROOT/test/helpers.sh"

SCRATCH="$(mktemp -d)"
cleanup() { [[ -n $SCRATCH && -d $SCRATCH ]] && rm -rf "$SCRATCH"; }
trap cleanup EXIT

# A fake dnf that logs transactions to $DNF_LOG and exits 0 (or $FAKE_DNF_RC).
# `repolist` is a query, not a transaction: it answers with $FAKE_ENABLED_REPOS
# (so the engine knows which foreign repos are enabled and may be --disablerepo'd)
# and is NOT logged.
FAKE_BIN="$SCRATCH/bin"; mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/dnf" <<'EOF'
#!/bin/bash
for a in "$@"; do
  if [[ $a == repolist ]]; then
    printf '%s\n' ${FAKE_ENABLED_REPOS:-}
    exit 0
  fi
done
printf '%s\n' "$*" >>"$DNF_LOG"
exit ${FAKE_DNF_RC:-0}
EOF
chmod +x "$FAKE_BIN/dnf"
export OMEDORA_DNF_CMD="$FAKE_BIN/dnf"

FOREIGN_REPO="copr:copr.fedorainfracloud.org:solopasha:hyprland"
# The engine only --disablerepo's repos that are actually enabled; in these
# scenarios the foreign COPR is enabled.
export FAKE_ENABLED_REPOS="$FOREIGN_REPO"
# Detection mock: a renamed conflict (hyprland) + a same-name conflict (waybar).
both_conflicts() {
  export OMEDORA_REPOQUERY_CMD="printf '%s\n' 'hyprland 0.56.0 $FOREIGN_REPO' 'waybar 0.11 $FOREIGN_REPO'"
}
no_conflicts() { export OMEDORA_REPOQUERY_CMD="printf ''"; }

fresh_log() { DNF_LOG="$SCRATCH/dnf.$1.log"; : >"$DNF_LOG"; export DNF_LOG; }

# ===========================================================================
echo "# --- PART 1: owned_packages.py --map ---"
# ===========================================================================
map="$(python3 "$ROOT/bin/fedora/owned_packages.py" --map)"
assert_output_contains "map: hyprland renames to hyprland-omedora" "$map" $'hyprland\thyprland-omedora'
assert_output_contains "map: waybar stays waybar (same name)"      "$map" $'waybar\twaybar'

# ===========================================================================
echo "# --- PART 2: omarchy-doctor --list (machine-readable) ---"
# ===========================================================================
both_conflicts
set +e; list="$(omarchy-doctor --list 2>/dev/null)"; list_rc=$?; set -e
assert_equals "doctor --list exits 1 when conflicts exist" "$list_rc" "1"
assert_output_contains "doctor --list emits hyprland<TAB>repo" "$list" $'hyprland\t'"$FOREIGN_REPO"
assert_output_contains "doctor --list emits waybar<TAB>repo"   "$list" $'waybar\t'"$FOREIGN_REPO"
# --list must NOT print the human warning prose.
assert_output_lacks "doctor --list is machine-only (no prose)" "$list" "WARNING"

no_conflicts
set +e; clean_list="$(omarchy-doctor --list 2>/dev/null)"; clean_rc=$?; set -e
assert_equals "doctor --list exits 0 when clean" "$clean_rc" "0"
assert_equals "doctor --list emits nothing when clean" "$clean_list" ""

# ===========================================================================
echo "# --- PART 3: engine builds the right transaction ---"
# ===========================================================================
both_conflicts

# 3a) --dry-run: shows the plan, runs NO dnf.
fresh_log dryrun
out="$(omedora-replace-foreign --dry-run 2>&1)"
assert_output_contains "dry-run plans a swap for the renamed pkg"   "$out" "swap"
assert_output_contains "dry-run plans distro-sync for same-name"    "$out" "distro-sync"
assert_output_contains "dry-run names the omedora target"           "$out" "hyprland-omedora"
assert_equals "dry-run runs no dnf" "$(wc -l <"$DNF_LOG")" "0"

# 3b) --yes: applies the real transaction (captured by the fake dnf).
fresh_log apply
omedora-replace-foreign --yes >/dev/null 2>&1
swap_line="$(grep -E '(^| )swap hyprland hyprland-omedora( |$)' "$DNF_LOG" || true)"
sync_line="$(grep -E 'distro-sync waybar' "$DNF_LOG" || true)"
assert_output_contains "apply runs: dnf swap hyprland hyprland-omedora" "$swap_line" "swap hyprland hyprland-omedora"
assert_output_contains "apply runs: dnf distro-sync waybar"             "$sync_line" "distro-sync waybar"
assert_output_contains "apply disables the foreign repo (swap)"  "$swap_line" "--disablerepo=$FOREIGN_REPO"
assert_output_contains "apply disables the foreign repo (sync)"  "$sync_line" "--disablerepo=$FOREIGN_REPO"

# 3c) non-interactive WITHOUT --yes: refuse, change nothing (exit 3).
fresh_log refuse
set +e
omedora-replace-foreign </dev/null >/dev/null 2>&1
refuse_rc=$?
set -e
assert_equals "non-interactive without --yes refuses (exit 3)" "$refuse_rc" "3"
assert_equals "refused run touches no dnf" "$(wc -l <"$DNF_LOG")" "0"

# 3d) --ensure-copr: enables the COPR before the swap.
fresh_log copr
omedora-replace-foreign --yes --ensure-copr agaspar/omedora-3 >/dev/null 2>&1
assert_output_contains "ensure-copr runs: dnf copr enable" "$(cat "$DNF_LOG")" "copr enable agaspar/omedora-3"

# 3e) clean system: no-op, exit 0, no dnf.
no_conflicts
fresh_log clean
set +e
omedora-replace-foreign --yes >/dev/null 2>&1
clean_apply_rc=$?
set -e
assert_equals "clean system replacement exits 0" "$clean_apply_rc" "0"
assert_equals "clean system runs no dnf" "$(wc -l <"$DNF_LOG")" "0"

# 3f) `omedora doctor --fix` delegates to the engine (dry-run path).
both_conflicts
fix_out="$(omarchy-doctor --fix --dry-run 2>&1)"
assert_output_contains "doctor --fix delegates to the engine" "$fix_out" "replacement plan"

# ===========================================================================
echo "# --- PART 4: gate Replace / Keep / Abort + deferred swap ---"
# ===========================================================================
# Fake gum: `choose` prints $FAKE_GUM_CHOOSE; `confirm` exits $FAKE_GUM_CONFIRM.
GATE_SHIM="$SCRATCH/gate-shim"; mkdir -p "$GATE_SHIM"
cat >"$GATE_SHIM/gum" <<'EOF'
#!/bin/bash
case "$1" in
  choose)  printf '%s\n' "${FAKE_GUM_CHOOSE:-Abort}" ;;
  confirm) exit "${FAKE_GUM_CONFIRM:-0}" ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$GATE_SHIM/gum"

# Lived-in home with one config conflict + a foreign-repo package.
gate_home() {
  local d="$SCRATCH/gate-$1"; rm -rf "$d"
  mkdir -p "$d/src/hypr" "$d/home/.config/hypr"
  printf 'omedora\n' >"$d/src/hypr/diff.conf"
  printf 'user\n'    >"$d/home/.config/hypr/diff.conf"
  export HOME="$d/home"
  export OMEDORA_PLAN_SOURCE="$d/src"
  export OMEDORA_PLAN_DEST="$d/home/.config"
}

# Run the gate interactively and report exit code + whether the consent flag
# was exported, by having the gate print it on success.
run_gate_capture() {  # $1 = gum choose value
  local d; d="$(dirname "$OMEDORA_PLAN_DEST")"
  set +e
  FAKE_GUM_CHOOSE="$1" PATH="$ROOT/bin:$GATE_SHIM:$PATH" \
    bash -c '
      set -eo pipefail
      source "'"$ROOT"'/install/preflight/fedora-plan.sh"
      # Only reached on PROCEED; report the consent flag for the test.
      echo "GATE_PROCEEDED replace=${OMEDORA_REPLACE_FOREIGN:-0}"
    ' >"$SCRATCH/gate.out" 2>&1
  echo $? >"$SCRATCH/gate.rc"
}

both_conflicts
export OMEDORA_PLAN_FORCE_INTERACTIVE=1

# 4a) Replace -> proceeds AND sets the consent flag.
gate_home replace; run_gate_capture "Replace"
assert_equals "Replace: gate proceeds (exit 0)" "$(cat "$SCRATCH/gate.rc")" "0"
assert_output_contains "Replace: consent flag exported" "$(cat "$SCRATCH/gate.out")" "GATE_PROCEEDED replace=1"

# 4b) Keep -> proceeds WITHOUT the consent flag.
gate_home keep; run_gate_capture "Keep"
assert_equals "Keep: gate proceeds (exit 0)" "$(cat "$SCRATCH/gate.rc")" "0"
assert_output_contains "Keep: consent flag NOT set" "$(cat "$SCRATCH/gate.out")" "GATE_PROCEEDED replace=0"

# 4c) Abort -> exit 1, no proceed line.
gate_home abort; run_gate_capture "Abort"
assert_equals "Abort: gate exits 1" "$(cat "$SCRATCH/gate.rc")" "1"
assert_output_lacks "Abort: did not proceed" "$(cat "$SCRATCH/gate.out")" "GATE_PROCEEDED"

# 4d) fedora-swap.sh: applies iff the consent flag is set.
both_conflicts
fresh_log swapstep_off
OMEDORA_REPLACE_FOREIGN="" bash "$ROOT/install/preflight/fedora-swap.sh" >/dev/null 2>&1 || true
assert_equals "fedora-swap.sh is a no-op without consent" "$(wc -l <"$DNF_LOG")" "0"

fresh_log swapstep_on
OMEDORA_REPLACE_FOREIGN=1 bash "$ROOT/install/preflight/fedora-swap.sh" >/dev/null 2>&1 || true
assert_output_contains "fedora-swap.sh applies the swap with consent" "$(cat "$DNF_LOG")" "swap hyprland hyprland-omedora"

echo "# All coexistence replacement tests passed."
