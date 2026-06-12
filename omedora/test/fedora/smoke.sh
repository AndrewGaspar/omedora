#!/bin/bash
#
# L3 smoke test — runs INSIDE the fedora:44 test image (omedora-test:fedora44).
#
# Drives the REAL Omarchy-4-line bootstrap end-to-end against the LIVE
# agaspar/omedora-4 COPR: plan gate (autoconfirmed) -> repos -> dnf install
# omedora + the full mapped base set -> setup-system (Fedora-gated) -> adopt ->
# finalize. Then asserts the result and re-runs the adopt step to prove
# idempotency (no second round of backups).
#
# Container realities this test embraces (and the bootstrap must tolerate):
#   - no systemd PID 1 -> systemctl enables degrade gracefully
#   - no graphical session / user bus -> first-run is skipped by design
#   - not btrfs -> the snapshot offer degrades to a notice
#
# Invoked by run-smoke.sh (or CI) as container root; re-execs as the uid-1000
# `omedora` user (wheel, NOPASSWD sudo) because the installer refuses root.

set -uo pipefail

REPO="${REPO:-/repo}"
if [[ ! -d $REPO/bin ]]; then
  echo "expected repo at $REPO; bind-mount via -v \$PWD:/repo" >&2
  exit 1
fi

# --- re-exec as the test user -------------------------------------------------
if (( EUID == 0 )); then
  echo "==> smoke: re-running as the omedora user"
  exec su omedora -c "REPO=$REPO bash $REPO/omedora/test/fedora/smoke.sh"
fi

cd "$REPO"

fails=0
ok()   { echo "ok - $1"; }
bad()  { echo "not ok - $1" >&2; fails=1; }
check() { # check <desc> <cmd...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

# --- the full bootstrap ---------------------------------------------------------
echo "==> smoke: running the omedora bootstrap (plan autoconfirmed)"
if OMEDORA_PLAN_AUTOCONFIRM=1 bash "$REPO/omedora/install-4.sh"; then
  ok "omedora/install-4.sh completed end-to-end"
else
  bad "omedora/install-4.sh completed end-to-end"
  echo "==> bootstrap failed; aborting smoke early" >&2
  exit 1
fi

# --- package layer ---------------------------------------------------------------
check "omedora RPM installed" rpm -q omedora
check "omedora-settings RPM installed" rpm -q omedora-settings
check "hyprland compositor installed from the omedora COPR" rpm -q hyprland-no-session
check "quickshell installed" rpm -q quickshell
check "foot installed" rpm -q foot
check "uwsm installed" rpm -q uwsm
check "omarchy CLI runs" omarchy --help
check "GDM session entry present" test -f /usr/share/wayland-sessions/omedora.desktop
check "quickshell payload present" test -f /usr/share/omarchy/shell/shell.qml

# Forbidden-surface spot checks (coexistence contract)
check "/etc/os-release still owned by Fedora" \
  bash -c 'rpm -qf /etc/os-release | grep -qv omedora'
check "no omedora ownership of /etc/nsswitch.conf" \
  bash -c '! rpm -qf /etc/nsswitch.conf 2>/dev/null | grep -q omedora'

# --- user layer (adopt) ----------------------------------------------------------
check "hyprland.lua seeded into ~/.config" test -f "$HOME/.config/hypr/hyprland.lua"
check "omarchy user config dir seeded" test -d "$HOME/.config/omarchy"

# --- idempotency: a second adopt pass makes NO new backups ------------------------
before=$(find "$HOME/.config" -name '*.pre-omedora-*' 2>/dev/null | wc -l)
if omedora-adopt-user >/dev/null 2>&1; then
  after=$(find "$HOME/.config" -name '*.pre-omedora-*' 2>/dev/null | wc -l)
  if [[ $before == "$after" ]]; then
    ok "second adopt pass is idempotent ($before backups before and after)"
  else
    bad "second adopt pass is idempotent (backups grew $before -> $after)"
  fi
else
  bad "second adopt pass exits zero"
fi

# --- the L1 suite still passes on the installed system ----------------------------
l1_fails=0
for t in "$REPO"/test/*.sh; do
  case "$t" in */helpers.sh) continue ;; esac
  bash "$t" >/dev/null 2>&1 || { echo "  L1 failed: $t" >&2; l1_fails=1; }
done
[[ $l1_fails == 0 ]] && ok "full L1 suite green post-install" || bad "full L1 suite green post-install"

if [[ $fails == 0 ]]; then
  echo "# L3 smoke: ALL GREEN"
else
  echo "# L3 smoke: FAILURES (see 'not ok' lines)" >&2
fi
exit $fails
