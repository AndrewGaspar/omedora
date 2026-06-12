#!/bin/bash
#
# Update-flow unit tests for the Omarchy-4 (package-backed) line.
#
#   PART 1 — per-step Fedora dispatch in the omarchy-update pipeline:
#            keyring/aur/orphans are clean no-ops (no pacman/yay reached),
#            system-pkgs runs `dnf upgrade --refresh -y`, update-time restarts
#            chronyd (and never aborts when it's absent), snapshot `create`
#            routes to omedora-snapshot.
#   PART 2 — bin/fedora/update-available writes the same state files the shell
#            widget reads and honors the upstream exit contract
#            (0 = updates listed on stdout, 1 = "System is up to date"),
#            driven through the $OMEDORA_DNF_CMD seam.
#   PART 3 — bin/omarchy-update-restart attributes kernels via rpm on Fedora
#            (pacman is absent there; a bare pacman probe would always prompt
#            for a reboot).
#   PART 4 — the Arch path of every gated step emits NO dnf calls
#            (dual-distro contract).
#
# Everything external is stubbed on PATH; no network, no real package manager.

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

stub sudo             'printf "sudo %s\n" "$*" >>"$MOCK_LOG"; "$@"'
stub dnf              'printf "dnf %s\n" "$*" >>"$MOCK_LOG"'
stub pacman           'printf "pacman %s\n" "$*" >>"$MOCK_LOG"'
stub pacman-key       'printf "pacman-key %s\n" "$*" >>"$MOCK_LOG"'
stub yay              'printf "yay %s\n" "$*" >>"$MOCK_LOG"'
stub systemctl        'printf "systemctl %s\n" "$*" >>"$MOCK_LOG"'
stub rpm              'printf "rpm %s\n" "$*" >>"$MOCK_LOG"; exit 0'
stub omedora-snapshot 'printf "omedora-snapshot %s\n" "$*" >>"$MOCK_LOG"'
stub omarchy-pkg-missing 'exit 1'
stub gum              'exit 0'

export PATH="$SHIM:$ROOT/bin:$PATH"

run_fedora() { ( export OMARCHY_DISTRO=fedora; : >"$MOCK_LOG"; "$@" ); }

# ===========================================================================
echo "# --- PART 1: per-step Fedora dispatch ---"
# ===========================================================================

run_fedora bash "$ROOT/bin/omarchy-update-keyring" >/dev/null
grep -qE "pacman" "$MOCK_LOG" \
  && fail "keyring on Fedora is a no-op (no pacman)" \
  || pass "keyring on Fedora is a no-op (no pacman)"

run_fedora bash "$ROOT/bin/omarchy-update-system-pkgs" >/dev/null
grep -q "dnf upgrade --refresh -y" "$MOCK_LOG" \
  && pass "system-pkgs on Fedora runs dnf upgrade --refresh -y" \
  || { cat "$MOCK_LOG" >&2; fail "system-pkgs on Fedora runs dnf upgrade --refresh -y"; }
grep -q "pacman" "$MOCK_LOG" \
  && fail "system-pkgs on Fedora never reaches pacman" \
  || pass "system-pkgs on Fedora never reaches pacman"

run_fedora bash "$ROOT/bin/omarchy-update-aur-pkgs" >/dev/null
grep -qE "yay|pacman" "$MOCK_LOG" \
  && fail "aur-pkgs on Fedora is a no-op" \
  || pass "aur-pkgs on Fedora is a no-op"

run_fedora bash "$ROOT/bin/omarchy-update-orphan-pkgs" >/dev/null
grep -qE "pacman|dnf" "$MOCK_LOG" \
  && fail "orphan-pkgs on Fedora is a no-op" \
  || pass "orphan-pkgs on Fedora is a no-op"

run_fedora bash "$ROOT/bin/omarchy-update-time" >/dev/null
grep -q "systemctl restart chronyd" "$MOCK_LOG" \
  && pass "update-time on Fedora restarts chronyd" \
  || { cat "$MOCK_LOG" >&2; fail "update-time on Fedora restarts chronyd"; }
grep -q "timesyncd" "$MOCK_LOG" \
  && fail "update-time on Fedora never touches systemd-timesyncd" \
  || pass "update-time on Fedora never touches systemd-timesyncd"

run_fedora bash "$ROOT/bin/omarchy-snapshot" create >/dev/null
grep -q "omedora-snapshot create pre-update" "$MOCK_LOG" \
  && pass "snapshot create on Fedora routes to omedora-snapshot" \
  || { cat "$MOCK_LOG" >&2; fail "snapshot create on Fedora routes to omedora-snapshot"; }

# ===========================================================================
echo "# --- PART 2: bin/fedora/update-available state contract ---"
# ===========================================================================
export XDG_STATE_HOME="$SCRATCH/state"

# A dnf whose check-upgrade reports two updates (dnf exit 100).
FAKE_DNF="$SCRATCH/fake-dnf-updates"
cat >"$FAKE_DNF" <<'EOF'
#!/bin/bash
printf 'omedora.noarch 0.2.0~alpha.1 copr:...:omedora-4\nfoo.x86_64 1.2-3.fc44 updates\n'
exit 100
EOF
chmod +x "$FAKE_DNF"

out=$(OMARCHY_DISTRO=fedora OMEDORA_DNF_CMD="$FAKE_DNF" bash "$ROOT/bin/omarchy-update-available") \
  && rc=0 || rc=$?
assert_equals "updates available -> exit 0" "0" "$rc"
assert_output_contains "stdout lists the updates" "$out" "omedora.noarch"
assert_file_exists "packages state file written" "$XDG_STATE_HOME/omarchy/updates/packages"
assert_file_exists "available state file written" "$XDG_STATE_HOME/omarchy/updates/available"
assert_file_exists "checked-at state file written" "$XDG_STATE_HOME/omarchy/updates/checked-at"
[[ -f "$XDG_STATE_HOME/omarchy/updates/aur" && ! -s "$XDG_STATE_HOME/omarchy/updates/aur" ]] \
  && pass "aur state file exists and is empty on Fedora" \
  || fail "aur state file exists and is empty on Fedora"
[[ ! -e "$XDG_STATE_HOME/omarchy/updates/error" ]] \
  && pass "no error state file on success" \
  || fail "no error state file on success"

# A dnf that reports no updates (exit 0).
stub_uptodate="$SCRATCH/fake-dnf-current"
printf '#!/bin/bash\nexit 0\n' >"$stub_uptodate"; chmod +x "$stub_uptodate"
out=$(OMARCHY_DISTRO=fedora OMEDORA_DNF_CMD="$stub_uptodate" bash "$ROOT/bin/omarchy-update-available") \
  && rc=0 || rc=$?
assert_equals "up to date -> exit 1" "1" "$rc"
assert_output_contains "up-to-date message" "$out" "System is up to date"
[[ ! -s "$XDG_STATE_HOME/omarchy/updates/available" ]] \
  && pass "available state cleared when current" \
  || fail "available state cleared when current"

# ===========================================================================
echo "# --- PART 3: update-restart kernel attribution via rpm ---"
# ===========================================================================
# Build a fake /usr/lib/modules with one kernel that "rpm owns" and matches
# uname -r, so NO reboot prompt is needed; pacman must never be called.
# update-restart inspects /usr/lib/modules directly, so run it in a mount-free
# way: stub uname + point the loop via a chroot-like PATH... the script
# hardcodes /usr/lib/modules; instead verify the probe dispatch by behavior:
# on Fedora with rpm stubbed exit 0 and a real /usr/lib/modules (if any), the
# script must not call pacman. (Kernel-state assertions live in the L2 suite.)
stub gum 'printf "gum %s\n" "$*" >>"$MOCK_LOG"; exit 1'  # decline any prompt
run_fedora bash "$ROOT/bin/omarchy-update-restart" >/dev/null 2>&1 || true
grep -q "pacman" "$MOCK_LOG" \
  && fail "update-restart on Fedora never calls pacman" \
  || pass "update-restart on Fedora never calls pacman"

# ===========================================================================
echo "# --- PART 4: Arch paths emit no dnf (dual-distro contract) ---"
# ===========================================================================
for cmd in omarchy-update-keyring omarchy-update-system-pkgs omarchy-update-aur-pkgs \
           omarchy-update-orphan-pkgs omarchy-update-time; do
  : >"$MOCK_LOG"
  ( export OMARCHY_DISTRO=arch; bash "$ROOT/bin/$cmd" >/dev/null 2>&1 ) || true
  if grep -q "^dnf\|omedora-snapshot" "$MOCK_LOG"; then
    cat "$MOCK_LOG" >&2
    fail "Arch path of $cmd emits no dnf/omedora calls"
  else
    pass "Arch path of $cmd emits no dnf/omedora calls"
  fi
done

echo "# all update-flow tests passed"
