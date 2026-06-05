#!/bin/bash

# Unit tests for bin/omedora-snapshot (the Fedora btrfs snapshot tool).
#
# btrfs subvolume ops can't run in this sandbox (no loop devices), so we mock
# `btrfs`/`findmnt` on PATH and use the OMEDORA_SNAPSHOT_TOP test seam to run
# create/list/delete/rollback against a plain directory. The fake `btrfs`
# materializes/removes directories so list/delete/rollback see real state. This
# verifies the COMMAND LOGIC + safety behavior; the real subvolume surgery is
# validated separately on btrfs hardware (rollback is --dry-run by default for
# exactly that reason).

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SCRATCH="$(mktemp -d)"
cleanup() { [[ -n $SCRATCH && -d $SCRATCH ]] && rm -rf "$SCRATCH"; }
trap cleanup EXIT

MOCK="$SCRATCH/bin"; mkdir -p "$MOCK"
BTRFS_LOG="$SCRATCH/btrfs.log"

# Fake findmnt: FSTYPE -> $FAKE_FSTYPE, SOURCE -> a fake device.
cat >"$MOCK/findmnt" <<'EOF'
#!/bin/bash
case "$*" in
  *FSTYPE*) printf '%s\n' "${FAKE_FSTYPE:-btrfs}" ;;
  *SOURCE*) printf '%s\n' "/dev/fake[/root]" ;;
esac
EOF
# Fake btrfs: log every call; materialize/remove dirs so state is observable.
cat >"$MOCK/btrfs" <<'EOF'
#!/bin/bash
printf '%s\n' "$*" >>"$BTRFS_LOG"
case "$1 $2" in
  "subvolume snapshot")
    dest="${@: -1}"; mkdir -p "$dest/etc" "$dest/usr" ;;   # look like a root
  "subvolume delete")
    rm -rf "${@: -1}" ;;
esac
exit 0
EOF
# Fake gum so `rollback --apply`'s confirm path is deterministic (yes).
cat >"$MOCK/gum" <<'EOF'
#!/bin/bash
[[ "$1" == confirm ]] && exit "${FAKE_GUM_CONFIRM:-0}"
exit 0
EOF
chmod +x "$MOCK/findmnt" "$MOCK/btrfs" "$MOCK/gum"
export PATH="$MOCK:$ROOT/bin:$PATH"
export OMEDORA_SNAPSHOT_SUDO=""          # call mocked btrfs/findmnt directly
export OMEDORA_SNAPSHOT_TOP="$SCRATCH/top"  # use a dir instead of mounting
export BTRFS_LOG

snap() { "$ROOT/bin/omedora-snapshot" "$@"; }
fresh() { rm -rf "$SCRATCH/top" "$BTRFS_LOG"; mkdir -p "$SCRATCH/top"; }

# ===========================================================================
echo "# --- guard: non-btrfs root ---"
# ===========================================================================
fresh
assert_exit_code "exits 127 when root is not btrfs" 127 \
  env FAKE_FSTYPE=ext4 "$ROOT/bin/omedora-snapshot" create

# ===========================================================================
echo "# --- create ---"
# ===========================================================================
fresh
out="$(snap create preinstall 2>&1)"
assert_output_contains "create takes a read-only snapshot of /" \
  "$(cat "$BTRFS_LOG")" "subvolume snapshot -r /"
assert_output_contains "create stores it under omedora-snapshots/" \
  "$(cat "$BTRFS_LOG")" "/omedora-snapshots/preinstall-"
created="$(ls "$SCRATCH/top/omedora-snapshots" 2>/dev/null | head -1)"
assert_equals "snapshot directory exists" \
  "$([[ -d "$SCRATCH/top/omedora-snapshots/$created" ]] && echo yes)" "yes"

# ===========================================================================
echo "# --- list ---"
# ===========================================================================
assert_output_contains "list shows the created snapshot" "$(snap list 2>&1)" "preinstall-"
fresh
assert_output_contains "list says none when empty" "$(snap list 2>&1)" "no snapshots"

# ===========================================================================
echo "# --- rollback: dry run is the default (NO changes) ---"
# ===========================================================================
fresh
snap create base >/dev/null 2>&1
name="$(ls "$SCRATCH/top/omedora-snapshots" | head -1)"
: >"$BTRFS_LOG"   # clear the create log
out="$(snap rollback "$name" 2>&1)"
assert_output_contains "dry run prints the plan" "$out" "Rollback plan"
assert_output_contains "dry run says it changed nothing" "$out" "Dry run"
assert_equals "dry run created no root.broken (no swap)" \
  "$(ls -d "$SCRATCH"/top/root.broken-* 2>/dev/null | wc -l)" "0"
assert_equals "dry run ran no destructive btrfs ops" \
  "$(grep -cE 'subvolume (snapshot|delete)' "$BTRFS_LOG" 2>/dev/null || true)" "0"

# ===========================================================================
echo "# --- rollback --apply performs the swap (confirmed via stdin) ---"
# ===========================================================================
fresh
snap create base >/dev/null 2>&1
name="$(ls "$SCRATCH/top/omedora-snapshots" | head -1)"
mkdir -p "$SCRATCH/top/root/etc"   # a current root to be moved aside
echo rollback | snap rollback "$name" --apply >/dev/null 2>&1 || true
assert_equals "apply preserved the old root as root.broken-*" \
  "$(ls -d "$SCRATCH"/top/root.broken-* 2>/dev/null | wc -l)" "1"
assert_equals "apply put a restored root in place" \
  "$([[ -d "$SCRATCH/top/root/etc" ]] && echo yes)" "yes"

# ===========================================================================
echo "# --- rollback safety: missing / non-root snapshot ---"
# ===========================================================================
fresh; mkdir -p "$SCRATCH/top/omedora-snapshots"
assert_exit_code "rollback of a missing snapshot fails" 1 \
  bash -c "echo rollback | '$ROOT/bin/omedora-snapshot' rollback nope --apply"
# A snapshot dir lacking etc/usr must be refused.
mkdir -p "$SCRATCH/top/omedora-snapshots/notaroot"
assert_exit_code "rollback refuses a non-root-looking snapshot" 1 \
  bash -c "echo rollback | '$ROOT/bin/omedora-snapshot' rollback notaroot --apply"

echo "# All snapshot tests passed."
