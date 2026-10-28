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
#
# Local-repo mode (run-smoke.sh --local-repo): OMEDORA_TEST_LOCAL_REPO names a
# locally built RPM repo inside the container. As root, before the re-exec,
# lib/local-repo-overlay.sh overlays it on the live COPR (priority=1), so the
# bootstrap installs omedora + omedora-settings from it and everything else
# from the COPR. The disclosure check then expects the plan's "omedora local
# test repo" line instead of the COPR line, and the core RPMs must come from
# omedora-local carrying OMEDORA_TEST_EXPECT_TAG (git<HEAD sha7>).

set -uo pipefail

REPO="${REPO:-/repo}"
if [[ ! -d $REPO/bin ]]; then
  echo "expected repo at $REPO; bind-mount via -v \$PWD:/repo" >&2
  exit 1
fi

LOCAL_REPO="${OMEDORA_TEST_LOCAL_REPO:-}"
EXPECT_TAG="${OMEDORA_TEST_EXPECT_TAG:-}"

# --- re-exec as the test user -------------------------------------------------
if (( EUID == 0 )); then
  if [[ -n $LOCAL_REPO ]]; then
    echo "==> smoke: local-repo mode, overlaying $LOCAL_REPO on the COPR"
    bash "$REPO/omedora/test/fedora/lib/local-repo-overlay.sh" "$LOCAL_REPO" || exit 1
  fi
  echo "==> smoke: re-running as the omedora user"
  exec su omedora -c "REPO=$REPO OMEDORA_TEST_LOCAL_REPO=$LOCAL_REPO OMEDORA_TEST_EXPECT_TAG=$EXPECT_TAG bash $REPO/omedora/test/fedora/smoke.sh"
fi

cd "$REPO"

fails=0
ok()   { echo "ok - $1"; }
bad()  { echo "not ok - $1" >&2; fails=1; }
check() { # check <desc> <cmd...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

from_repo() { dnf repoquery --installed --qf '%{from_repo}\n' "$1" 2>/dev/null | head -n1; }
copr_project=$(OMARCHY_PATH='' "$REPO/bin/omedora-copr")
copr_repo_id=$(OMARCHY_PATH='' "$REPO/bin/omedora-copr" --repo-id)

# --- the full bootstrap ---------------------------------------------------------
echo "==> smoke: running the omedora bootstrap (plan autoconfirmed)"
INSTALL_LOG=$(mktemp)
OMEDORA_PLAN_AUTOCONFIRM=1 bash "$REPO/omedora/install-4.sh" 2>&1 | tee "$INSTALL_LOG"
if (( PIPESTATUS[0] == 0 )); then
  ok "omedora/install-4.sh completed end-to-end"
else
  bad "omedora/install-4.sh completed end-to-end"
  echo "==> bootstrap failed; aborting smoke early" >&2
  exit 1
fi

# --- package source: disclosed at the plan gate, then actually used ------------
if [[ -n $LOCAL_REPO ]]; then
  check "plan disclosed the omedora package source (the local test repo)" \
    grep -qF "omedora local test repo already present" "$INSTALL_LOG"
  for pkg in omedora omedora-settings; do
    check "$pkg installed from the local repo" \
      test "$(from_repo "$pkg")" == "omedora-local"
    check "$pkg is HEAD's build ($EXPECT_TAG)" \
      bash -c "rpm -q $pkg | grep -qF '$EXPECT_TAG.'"
  done
else
  check "plan disclosed the omedora package source ($copr_project)" \
    grep -qF "enable the omedora COPR: $copr_project" "$INSTALL_LOG"
  check "omedora installed from the omedora COPR" test "$(from_repo omedora)" == "$copr_repo_id"
fi

# --- package layer ---------------------------------------------------------------
check "omedora RPM installed" rpm -q omedora
check "omedora-settings RPM installed" rpm -q omedora-settings
# (In local-repo mode a hyprland built into the local repo overlays the COPR's.)
hypr_repo=$(from_repo hyprland-no-session)
[[ -n $LOCAL_REPO && $hypr_repo == "omedora-local" ]] && hypr_repo=$copr_repo_id
check "hyprland compositor installed from the omedora COPR" test "$hypr_repo" == "$copr_repo_id"
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
  if ! out=$(bash "$t" 2>&1); then
    echo "  L1 failed: $t — output tail:" >&2
    printf '%s\n' "$out" | tail -30 >&2
    l1_fails=1
  fi
done
[[ $l1_fails == 0 ]] && ok "full L1 suite green post-install" || bad "full L1 suite green post-install"

rm -f "$INSTALL_LOG"
if [[ $fails == 0 ]]; then
  echo "# L3 smoke: ALL GREEN"
else
  echo "# L3 smoke: FAILURES (see 'not ok' lines)" >&2
fi
exit $fails
