#!/bin/bash
#
# L4-VM in-guest: POST-REBOOT half of the omedora-snapshot rollback test.
#
# Runs as root inside the VM AFTER the reboot that follows snapshot-prepare.sh's
# `rollback --apply`. The system has now booted the restored `root` subvolume, so
# this asserts the rollback actually took effect on a live, rebooted system —
# the thing only a real VM (not a container) can prove:
#
#   * /PROOF-marker is GONE        -> the post-snapshot live root was replaced by
#                                     the (pre-marker) snapshot.
#   * /home/HOME-marker SURVIVES   -> /home is a separate subvolume, untouched.
#   * root.broken-<ts> EXISTS at the btrfs top level, and still HOLDS the marker
#                                  -> the previous system was preserved and the
#                                     swap is reversible.
#
# Reads /var/tmp/snaptest-state (written by snapshot-prepare.sh). TAP-ish out.

set -uo pipefail

STATE=/var/tmp/snaptest-state
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; FAILED=1; }
FAILED=0

echo "# snapshot-assert: post-reboot rollback verification"

[[ -r "$STATE" ]] || { echo "not ok - state file $STATE present" >&2; exit 1; }
# shellcheck disable=SC1090
. "$STATE"
echo "# snapshot: ${SNAP_NAME:-?}  marker: ${MARKER:-?}  home_marker: ${HOME_MARKER:-?}"

# Confirm we actually rebooted onto the restored root (still subvol=root).
echo "# root now: $(findmnt -no SOURCE /)"

# --- 1. the marker is gone (rollback took effect) --------------------------
if [[ -e "$MARKER" ]]; then
  fail "post-snapshot marker $MARKER is GONE after rollback (still present!)"
else
  pass "post-snapshot marker $MARKER is GONE — rollback took effect"
fi

# --- 2. /home survived (separate subvol, never touched) --------------------
if [[ -e "$HOME_MARKER" ]]; then
  pass "/home marker $HOME_MARKER survived — /home subvolume untouched"
else
  fail "/home marker $HOME_MARKER survived the rollback"
fi

# --- 3. the old root is preserved + reversible -----------------------------
TOP=$(mktemp -d /var/tmp/snaptest-top.XXXXXX)
ROOT_DEV="${ROOT_DEV:-$(findmnt -no SOURCE / | sed 's/\[.*\]//')}"
mount -o subvolid=5 "$ROOT_DEV" "$TOP"
broken=$(ls -d "$TOP"/root.broken-* 2>/dev/null | head -1)
if [[ -n "$broken" ]]; then
  pass "previous system preserved as $(basename "$broken")"
  if [[ -e "$TOP/$(basename "$broken")$MARKER" ]]; then
    pass "the post-snapshot marker lives inside $(basename "$broken") — rollback is reversible"
  else
    fail "the preserved root.broken-* still contains $MARKER (reversibility)"
  fi
else
  fail "root.broken-* exists at the btrfs top level"
fi
echo "# top-level subvols/dirs:"; ls -1 "$TOP" | sed 's/^/#   /'
umount "$TOP"; rmdir "$TOP" 2>/dev/null || true

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "# snapshot-assert: ALL post-reboot assertions passed"
  exit 0
else
  echo "# snapshot-assert: some assertions FAILED"
  exit 1
fi
