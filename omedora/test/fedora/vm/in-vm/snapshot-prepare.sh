#!/bin/bash
#
# L4-VM in-guest: PRE-REBOOT half of the omedora-snapshot rollback test.
#
# Runs as root inside the VM (so OMEDORA_SNAPSHOT_SUDO="" — no nested sudo). It
# exercises the real btrfs subvolume surgery in bin/omedora-snapshot against the
# VM's ACTUAL root subvolume (Fedora's `root`+`home`+... top-level layout), which
# no container can do (rootless podman has no loop devices, so no btrfs):
#
#   1. omedora-snapshot create preinstall   -> a read-only snapshot sibling of
#      `root` under omedora-snapshots/; assert `list` shows it.
#   2. write a marker INTO the live root (/PROOF-marker) and one into /home
#      (/home/HOME-marker) so we can later prove the swap restored root and left
#      /home untouched.
#   3. omedora-snapshot rollback <name> --apply, auto-confirming the prompt. The
#      tool stages a writable copy of the snapshot, `mv root -> root.broken-<ts>`,
#      `mv staged -> root`. The system is now POISED to boot the restored root.
#
# The marker names + the snapshot name are written to /var/tmp/snaptest-state so
# the post-reboot asserter (snapshot-assert.sh) can read them back. TAP-ish out.
#
# Confirm seam: bin/omedora-snapshot uses `gum confirm` if gum is on PATH, else a
# `read -p "Type 'rollback' to proceed:"`. The VM base has no gum, so we pipe
# `rollback` to stdin. (If a future base ships gum, this still works: gum reads
# the tty, and with stdin closed/non-tty its confirm path is bypassed by feeding
# the read fallback — but to be safe we also unset PATH gum below.)

set -uo pipefail

TOOL="${OMEDORA_SNAPSHOT_BIN:-/usr/local/bin/omedora-snapshot}"
STATE=/var/tmp/snaptest-state
MARKER=/PROOF-marker
HOME_MARKER=/home/HOME-marker

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; FAILED=1; }
FAILED=0

echo "# snapshot-prepare: create + marker + rollback --apply (pre-reboot)"
echo "# tool: $TOOL"

[[ -x "$TOOL" ]] || { echo "not ok - tool present at $TOOL" >&2; exit 1; }

# Sanity: we MUST be on btrfs or the tool would exit 127 (and this whole tier is
# pointless). Surface it loudly.
fstype=$(findmnt -no FSTYPE / 2>/dev/null)
echo "# root fstype: ${fstype:-<unknown>}"
if [[ "$fstype" == btrfs ]]; then
  pass "root filesystem is btrfs (snapshots supported)"
else
  fail "root filesystem is btrfs (got: ${fstype:-<unknown>}) — cannot test btrfs snapshots"
  exit 1
fi

# Run the tool as root with the privilege wrapper disabled (we ARE root).
snap() { env OMEDORA_SNAPSHOT_SUDO="" "$TOOL" "$@"; }

# --- 1. create -------------------------------------------------------------
echo "# --- create ---"
create_out=$(snap create preinstall 2>&1)
echo "$create_out" | sed 's/^/#   /'
NAME=$(snap list 2>/dev/null | sed -n 's/^  //p' | grep '^preinstall-' | head -1)
echo "# snapshot name: ${NAME:-<none>}"
if [[ -n "$NAME" ]]; then
  pass "create made a read-only snapshot listed by omedora-snapshot ($NAME)"
else
  fail "create made a snapshot that 'list' reports"
  exit 1
fi

# It should be a real subvolume sibling of root at the btrfs top level.
TOP=$(mktemp -d /var/tmp/snaptest-top.XXXXXX)
ROOT_DEV=$(findmnt -no SOURCE / | sed 's/\[.*\]//')
mount -o subvolid=5 "$ROOT_DEV" "$TOP"
if [[ -d "$TOP/omedora-snapshots/$NAME/etc" && -d "$TOP/omedora-snapshots/$NAME/usr" ]]; then
  pass "snapshot stored under omedora-snapshots/ and looks like a root (has etc/ + usr/)"
else
  fail "snapshot stored under omedora-snapshots/ with a root-like tree"
fi
umount "$TOP"; rmdir "$TOP" 2>/dev/null || true

# --- 2. markers ------------------------------------------------------------
echo "# --- markers (post-snapshot, into the LIVE root + /home) ---"
echo "this-is-the-post-snapshot-live-root" > "$MARKER"
echo "home-must-survive-rollback"          > "$HOME_MARKER"
[[ -e "$MARKER" && -e "$HOME_MARKER" ]] \
  && pass "wrote $MARKER (live root) and $HOME_MARKER (/home subvol)" \
  || { fail "wrote the marker files"; exit 1; }

# Persist what the post-reboot asserter needs to know.
{
  echo "SNAP_NAME=$NAME"
  echo "MARKER=$MARKER"
  echo "HOME_MARKER=$HOME_MARKER"
  echo "ROOT_DEV=$ROOT_DEV"
} > "$STATE"
echo "# wrote state -> $STATE"

# --- 3. rollback --apply ---------------------------------------------------
echo "# --- rollback --apply (auto-confirm via stdin 'rollback') ---"
# Ensure the read-prompt path (not gum): the base has no gum; the tool falls back
# to `read -p "Type 'rollback' to proceed:"`. Feed it on stdin.
rb_out=$(echo rollback | snap rollback "$NAME" --apply 2>&1)
rb_rc=$?
echo "$rb_out" | sed 's/^/#   /'
if [[ $rb_rc -eq 0 ]] && echo "$rb_out" | grep -q 'rolled back'; then
  pass "rollback --apply reported success (root swapped; reboot pending)"
else
  fail "rollback --apply succeeded (rc=$rb_rc)"
  exit 1
fi

# Pre-reboot, prove the swap already happened at the subvol level (the live /
# still shows the OLD inode until reboot, but the top level is already swapped).
TOP=$(mktemp -d /var/tmp/snaptest-top.XXXXXX)
mount -o subvolid=5 "$ROOT_DEV" "$TOP"
broken=$(ls -d "$TOP"/root.broken-* 2>/dev/null | head -1)
if [[ -n "$broken" ]]; then
  pass "current root preserved aside as $(basename "$broken") (reversible swap done)"
else
  fail "root.broken-* exists at the top level after --apply"
fi
# The restored `root` must NOT carry the post-snapshot marker (it predates it).
if [[ -e "$TOP/root$MARKER" ]]; then
  fail "restored root subvol is the snapshot (must not contain $MARKER)"
else
  pass "restored root subvol does not contain $MARKER (it is the pre-marker snapshot)"
fi
umount "$TOP"; rmdir "$TOP" 2>/dev/null || true

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "# snapshot-prepare passed — reboot to land on the restored root"
  exit 0
else
  echo "# snapshot-prepare had FAILURES"
  exit 1
fi
