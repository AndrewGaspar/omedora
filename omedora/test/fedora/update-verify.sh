#!/bin/bash
#
# P5 update-pipeline verification — runs INSIDE the fedora:44 test image.
#
# Proves the dnf-backed update path on a REAL installed system (not a
# checkout):
#   1. fresh bootstrap from the live COPR
#   2. `omarchy-update -y` twice (the full pipeline; hard timeout so a
#      regression hangs fast, not forever)
#   3. no pacman leakage into the Fedora update path
#   4. the migration path: upstream unified migrations into the per-user
#      bin/omarchy-migrate that `omarchy update` runs (there is no system
#      runner and the RPM %post applies nothing), so a pending migration
#      dropped into the installed payload runs and is recorded for the user
#   5. omarchy-update-available writes the shell widget's state files
#
# Run: omedora/test/fedora/run-smoke.sh --update-verify [--local-repo]
#  or: podman run --rm -v "$PWD:/repo" -v <dnf-cache>:/var/cache/libdnf5 \
#        omedora-test:fedora44 bash /repo/omedora/test/fedora/update-verify.sh
#
# Local-repo mode (run-smoke.sh --update-verify --local-repo): as in smoke.sh,
# OMEDORA_TEST_LOCAL_REPO is overlaid on the COPR before the install, and the
# core RPMs must come from it with OMEDORA_TEST_EXPECT_TAG before and after
# both updates (the managed update must not swap them for the COPR's).

set -e

REPO="${REPO:-/repo}"
LOCAL_REPO="${OMEDORA_TEST_LOCAL_REPO:-}"
EXPECT_TAG="${OMEDORA_TEST_EXPECT_TAG:-}"

# assert_local_core <when> — local-repo mode: the core RPMs are HEAD's build
# from the local repo.
assert_local_core() {
  [[ -n $LOCAL_REPO ]] || return 0
  local pkg from_repo
  for pkg in omedora omedora-settings; do
    from_repo=$(dnf repoquery --installed --qf '%{from_repo}\n' "$pkg" | head -n1)
    if [[ $from_repo != "omedora-local" ]] || ! rpm -q "$pkg" | grep -qF "$EXPECT_TAG."; then
      echo "LOCAL CORE RPM CHECK FAILED $1: $(rpm -q "$pkg") from $from_repo (want $EXPECT_TAG from omedora-local)"
      exit 1
    fi
  done
  echo "core RPMs are the local $EXPECT_TAG build $1"
}

if [[ -n $LOCAL_REPO ]]; then
  bash "$REPO/omedora/test/fedora/lib/local-repo-overlay.sh" "$LOCAL_REPO"
fi

su omedora -c "OMEDORA_PLAN_AUTOCONFIRM=1 bash $REPO/omedora/install-4.sh" >/tmp/install.log 2>&1 \
  || { echo "INSTALL FAILED"; tail -5 /tmp/install.log; exit 1; }
echo "install ok ($(rpm -q omedora))"
assert_local_core "after install"

# omarchy-update re-execs itself under script(1) to log the run, so inside it
# stdin is a pty and omarchy-update-stay-awake runs `sudo -v` to cache the
# user's credentials up front. On a real Fedora box that is where the user
# types their password once. In this image Fedora's stock `%wheel ALL=(ALL) ALL`
# still matches alongside the NOPASSWD drop-in, and sudo's validate mode asks
# for a password whenever any matching rule wants one, so the prompt blocks
# with nobody to answer it. Give the test user the same outcome a typed
# password would: never authenticate.
printf 'Defaults:omedora !authenticate\n' >/etc/sudoers.d/zz-omedora-test-noauth
chmod 0440 /etc/sudoers.d/zz-omedora-test-noauth

# `su -c` starts a non-login, non-interactive shell, so /etc/profile.d/omarchy.sh
# never sets OMARCHY_PATH. Since 4.5 omarchy-update refuses to run unless
# OMARCHY_PATH names the code it runs from; a session or terminal always has it.
OMARCHY_ENV="OMARCHY_PATH=/usr/share/omarchy"

su omedora -c "$OMARCHY_ENV timeout 900 omarchy-update -y" >/tmp/up1.log 2>&1 \
  && echo "update run 1 ok" \
  || { echo "UPDATE 1 FAILED rc=$?"; tail -20 /tmp/up1.log; exit 1; }
su omedora -c "$OMARCHY_ENV timeout 900 omarchy-update -y" >/tmp/up2.log 2>&1 \
  && echo "update run 2 ok" \
  || { echo "UPDATE 2 FAILED rc=$?"; tail -20 /tmp/up2.log; exit 1; }

if grep -q "pacman" /tmp/up1.log; then
  echo "PACMAN LEAKED INTO THE FEDORA UPDATE PATH"
  grep pacman /tmp/up1.log | head -3
  exit 1
fi
echo "no pacman in the Fedora update path"
assert_local_core "after both updates"

# Per-user migration path. Upstream unified migrations on 2026-06-12: there is
# no system runner any more and the omedora RPM's %post applies nothing, so
# the only path a migration takes is bin/omarchy-migrate, run per user by
# `omarchy update`. Drop a marker migration into the installed payload, run
# the migrator as the user, assert it ran and was recorded in the user's state.
cat >/usr/share/omarchy/migrations/9999999999.sh <<'EOF'
echo "L3 marker migration"
mkdir -p "$HOME/.local/state/omarchy"
touch "$HOME/.local/state/omarchy/migration-ran-marker"
EOF
su omedora -c "$OMARCHY_ENV omarchy-migrate" >/tmp/migrate.log 2>&1 \
  || { echo "MIGRATE FAILED"; tail -20 /tmp/migrate.log; exit 1; }
if su omedora -c 'test -f ~/.local/state/omarchy/migration-ran-marker && test -f ~/.local/state/omarchy/migrations/9999999999.sh'; then
  echo "omarchy-migrate applied the pending migration and recorded it for the user"
else
  echo "MIGRATION PATH FAILED"
  tail -20 /tmp/migrate.log
  exit 1
fi
rm -f /usr/share/omarchy/migrations/9999999999.sh

su omedora -c 'omarchy-update-available >/tmp/avail.out 2>&1; echo "avail-rc=$?"; test -f ~/.local/state/omarchy/updates/checked-at && echo "state-files-written"'

echo "# P5 update verification: ALL GREEN"
