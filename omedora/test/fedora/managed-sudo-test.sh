#!/bin/bash
#
# L2 managed/hardened-sudo test — runs INSIDE the fedora:44 test image (or any
# Fedora-like box) as root. See omedora/testing.md.
#
# Emulates a corporate-managed Fedora laptop where `/etc/sudoers.d/` does not
# exist (the box that crashed omedora's install: `tee /etc/sudoers.d/first-run:
# No such file or directory`). Proves the Fedora install path now:
#   1. survives a missing /etc/sudoers.d (preflight first-run-mode.sh no longer
#      writes a sudoers drop-in), and
#   2. needs ZERO sudo for first-run — the Arch-only privileged finalizers
#      (dns-resolver/firewall/cleanup-reboot-sudoers + gnome-theme's icon cache)
#      all early-return on Fedora and never touch /etc/resolv.conf.
#   3. tightens the chromium/brave theme-policy dirs (user-owned 755, not a+rw).
#
# The repo is expected at /repo (bind-mounted). Runnable standalone or chained
# from integration.sh.

set -uo pipefail

REPO="${REPO:-/repo}"
if [[ ! -d $REPO/bin ]]; then
  echo "expected repo at $REPO; bind-mount via -v \$PWD:/repo" >&2
  exit 1
fi
cd "$REPO"

. "$REPO/test/helpers.sh"

# Put repo bin on PATH so omarchy-distro + helpers resolve.
export PATH="$REPO/bin:$PATH"
export OMARCHY_PATH="$REPO"

# Force the Fedora code paths regardless of the host distro, so this test is
# meaningful even when run on Arch / in CI.
export OMARCHY_DISTRO=fedora

# Scratch HOME so the first-run marker doesn't pollute the caller's $HOME.
WORK=$(mktemp -d)
export HOME="$WORK/home"
mkdir -p "$HOME"
# `$USER` is referenced by the install scripts (sudoers entries, install -o);
# in a bare `docker run` it may be unset.
export USER="${USER:-root}"

# A `sudo` shim on PATH that records every invocation and FAILS — so any
# privileged call from a Fedora code path is both detected and surfaced (the
# scripts must not depend on it).
SUDO_LOG="$WORK/sudo.log"
BIN="$WORK/bin"
mkdir -p "$BIN"
cat >"$BIN/sudo" <<EOF
#!/bin/bash
echo "SUDO CALLED: \$*" >>"$SUDO_LOG"
exit 99
EOF
chmod +x "$BIN/sudo"

sudo_was_called() { [[ -s $SUDO_LOG ]]; }
reset_sudo_log() { : >"$SUDO_LOG"; }

# Restore /etc/sudoers.d (we physically remove it below to reproduce the exact
# managed-box condition) on any exit.
SUDOERS_D_BAK="$WORK/sudoers.d.bak"
cleanup() {
  if [[ -e $SUDOERS_D_BAK && ! -e /etc/sudoers.d ]]; then
    mv "$SUDOERS_D_BAK" /etc/sudoers.d 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "=== Managed-sudo (no /etc/sudoers.d) Fedora install path ==="

# ---------------------------------------------------------------------------
# 1. Preflight survives a missing /etc/sudoers.d and writes no drop-in.
# ---------------------------------------------------------------------------
# Reproduce the reported crash condition exactly: remove the directory whose
# absence made `sudo tee /etc/sudoers.d/first-run` fail with ENOENT.
if [[ -e /etc/sudoers.d ]]; then
  cp -a /etc/sudoers.d "$SUDOERS_D_BAK"
  rm -rf /etc/sudoers.d
fi

reset_sudo_log
if PATH="$BIN:$PATH" bash "$REPO/install/preflight/first-run-mode.sh" >"$WORK/frm.out" 2>&1; then
  pass "preflight/first-run-mode.sh succeeds with no /etc/sudoers.d (managed box)"
else
  cat "$WORK/frm.out" >&2
  fail "preflight/first-run-mode.sh aborted on a box without /etc/sudoers.d"
fi

if sudo_was_called; then
  cat "$SUDO_LOG" >&2
  fail "first-run-mode.sh invoked sudo on Fedora (should write no sudoers drop-in)"
else
  pass "first-run-mode.sh invoked no sudo on Fedora"
fi

if [[ ! -e /etc/sudoers.d/first-run ]]; then
  pass "no /etc/sudoers.d/first-run drop-in created on Fedora"
else
  fail "first-run-mode.sh created /etc/sudoers.d/first-run on Fedora"
fi

assert_file_exists "first-run marker created (~/.local/state/omarchy/first-run.mode)" \
  "$HOME/.local/state/omarchy/first-run.mode"

# ---------------------------------------------------------------------------
# 2. First-run needs zero sudo on Fedora: the Arch-only privileged finalizers
#    early-return and leave system state (resolv.conf) untouched.
# ---------------------------------------------------------------------------
# Snapshot resolv.conf so we can prove dns-resolver.sh did not clobber it.
RESOLV_BEFORE="$WORK/resolv.before"
if [[ -e /etc/resolv.conf ]]; then
  readlink -f /etc/resolv.conf >"$RESOLV_BEFORE" 2>/dev/null || echo "PLAINFILE" >"$RESOLV_BEFORE"
  ls -l /etc/resolv.conf >>"$RESOLV_BEFORE" 2>/dev/null || true
else
  echo "ABSENT" >"$RESOLV_BEFORE"
fi

for script in dns-resolver firewall cleanup-reboot-sudoers gnome-theme; do
  reset_sudo_log
  if PATH="$BIN:$PATH" bash "$REPO/install/first-run/$script.sh" >"$WORK/$script.out" 2>&1; then
    pass "first-run/$script.sh exits 0 on Fedora"
  else
    cat "$WORK/$script.out" >&2
    fail "first-run/$script.sh failed on Fedora (should be gated/no-op)"
  fi
  if sudo_was_called; then
    cat "$SUDO_LOG" >&2
    fail "first-run/$script.sh invoked sudo on Fedora"
  else
    pass "first-run/$script.sh invoked no sudo on Fedora"
  fi
done

RESOLV_AFTER="$WORK/resolv.after"
if [[ -e /etc/resolv.conf ]]; then
  readlink -f /etc/resolv.conf >"$RESOLV_AFTER" 2>/dev/null || echo "PLAINFILE" >"$RESOLV_AFTER"
  ls -l /etc/resolv.conf >>"$RESOLV_AFTER" 2>/dev/null || true
else
  echo "ABSENT" >"$RESOLV_AFTER"
fi
if [[ "$(cat "$RESOLV_BEFORE")" == "$(cat "$RESOLV_AFTER")" ]]; then
  pass "/etc/resolv.conf unchanged (dns-resolver.sh did not run on Fedora)"
else
  { echo "before:"; cat "$RESOLV_BEFORE"; echo "after:"; cat "$RESOLV_AFTER"; } >&2
  fail "/etc/resolv.conf was modified on Fedora"
fi

# ---------------------------------------------------------------------------
# 3. The chromium/brave theme-policy dirs are created user-owned 755, not the
#    world-writable a+rw used on Arch. Needs to actually create dirs under /etc;
#    skip unless we're root (e.g. running standalone as an unprivileged user).
# ---------------------------------------------------------------------------
if [[ $(id -u) -eq 0 ]]; then
  # Passthrough `sudo` shim so the migration's `sudo install -d` works whether or
  # not the (often minimal) base image actually ships sudo — we are already root.
  PASS_BIN="$WORK/passbin"
  mkdir -p "$PASS_BIN"
  printf '#!/bin/bash\nexec "$@"\n' >"$PASS_BIN/sudo"
  chmod +x "$PASS_BIN/sudo"

  rm -rf /etc/chromium/policies /etc/brave/policies
  if PATH="$PASS_BIN:$PATH" bash "$REPO/migrations/1757147211.sh" >"$WORK/migration.out" 2>&1; then
    pass "migrations/1757147211.sh succeeds on Fedora"
  else
    cat "$WORK/migration.out" >&2
    fail "migrations/1757147211.sh failed on Fedora"
  fi
  for dir in /etc/chromium/policies/managed /etc/brave/policies/managed; do
    mode=$(stat -c %a "$dir" 2>/dev/null || echo MISSING)
    if [[ $mode == "755" ]]; then
      pass "$dir is mode 755 (not world-writable) on Fedora"
    else
      fail "$dir is mode $mode on Fedora (expected 755, not a+rw)"
    fi
  done
else
  pass "# SKIP chromium/brave policy-perms check: not root"
fi

echo ""
echo "=== All managed-sudo tests passed ==="
