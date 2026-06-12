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
#   4. the no-guard justification: a raw dnf transaction applies pending
#      system migrations via the omedora RPM's %post
#   5. omarchy-update-available writes the shell widget's state files
#
# Run: podman run --rm -v "$PWD:/repo" -v <dnf-cache>:/var/cache/libdnf5 \
#        omedora-test:fedora44 bash /repo/omedora/test/fedora/update-verify.sh

set -e

REPO="${REPO:-/repo}"

su omedora -c "OMEDORA_PLAN_AUTOCONFIRM=1 bash $REPO/omedora/install-4.sh" >/tmp/install.log 2>&1 \
  || { echo "INSTALL FAILED"; tail -5 /tmp/install.log; exit 1; }
echo "install ok ($(rpm -q omedora))"

su omedora -c "timeout 900 omarchy-update -y" >/tmp/up1.log 2>&1 \
  && echo "update run 1 ok" \
  || { echo "UPDATE 1 FAILED rc=$?"; tail -20 /tmp/up1.log; exit 1; }
su omedora -c "timeout 900 omarchy-update -y" >/tmp/up2.log 2>&1 \
  && echo "update run 2 ok" \
  || { echo "UPDATE 2 FAILED rc=$?"; tail -20 /tmp/up2.log; exit 1; }

if grep -q "pacman" /tmp/up1.log; then
  echo "PACMAN LEAKED INTO THE FEDORA UPDATE PATH"
  grep pacman /tmp/up1.log | head -3
  exit 1
fi
echo "no pacman in the Fedora update path"

# Raw-dnf path: pending system migrations apply via %post (the guard-free
# protection). Drop a marker migration, reinstall, assert it ran + recorded.
cat >/usr/share/omarchy/migrations/system/9999999999.sh <<'EOF'
#!/bin/bash
touch /var/tmp/migration-ran-marker
EOF
dnf -y reinstall omedora >/dev/null 2>&1
if [[ -f /var/tmp/migration-ran-marker && -f /var/lib/omarchy/migrations/system/9999999999.sh ]]; then
  echo "raw dnf transaction applied the system migration via %post"
else
  echo "MIGRATION HOOK FAILED"
  ls /var/lib/omarchy/migrations/system/ 2>/dev/null
  exit 1
fi

su omedora -c 'omarchy-update-available >/tmp/avail.out 2>&1; echo "avail-rc=$?"; test -f ~/.local/state/omarchy/updates/checked-at && echo "state-files-written"'

echo "# P5 update verification: ALL GREEN"
