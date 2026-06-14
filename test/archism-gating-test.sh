#!/bin/bash
#
# L1: the menu-reachable Arch-ism bins gate cleanly on Fedora.
#
# Several upstream bins hard-errored on Fedora (pacman / mkinitcpio / AUR names)
# when reached from the menu. Each now has an additive top-of-file Fedora arm;
# the Arch path stays byte-identical (byte-identity-test enforces that). Here we
# check the Fedora behavior: the no-op gates exit 0 and emit NO pacman/mkinitcpio
# calls, and the install gates dispatch to dnf (not pacman). pacman, mkinitcpio,
# dracut, sudo, gum are stubbed as tracers; OMARCHY_DISTRO selects the path.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
MOCK_LOG="$TMP/mock.log"; export MOCK_LOG

for c in pacman mkinitcpio limine-mkinitcpio dracut plymouth-set-default-theme \
         fprintd-enroll fprintd-verify authselect expac retroarch; do
  printf '#!/bin/bash\nprintf "%s %%s\\n" "$*" >>"%s"\nexit 0\n' "$c" "$MOCK_LOG" >"$BIN/$c"
done
# sudo: log + run the rest (so a sudo'd pacman still hits the pacman tracer).
printf '#!/bin/bash\nprintf "sudo %%s\\n" "$*" >>"%s"\n"$@"\n' "$MOCK_LOG" >"$BIN/sudo"
# pkg helpers: tracer (so fingerprint/retroarch dnf installs are observable).
for c in omarchy-pkg-add omarchy-pkg-present omarchy-pkg-drop; do
  printf '#!/bin/bash\nprintf "%s %%s\\n" "$*" >>"%s"\nexit 1\n' "$c" "$MOCK_LOG" >"$BIN/$c"
done
chmod +x "$BIN"/*
export PATH="$BIN:$ROOT/bin:$PATH"

run() { : >"$MOCK_LOG"; ( export OMARCHY_DISTRO="$1"; shift; bash "$@" ) >"$TMP/out" 2>&1; echo $?; }
log_has() { grep -qF "$1" "$MOCK_LOG"; }

# --- no-op gates: Fedora exits 0, emits NO pacman/mkinitcpio -----------------
for bin in omarchy-channel-set omarchy-refresh-pacman omarchy-refresh-plymouth \
           omarchy-plymouth-reset; do
  rc=$(run fedora "$ROOT/bin/$bin")
  assert_equals "$bin: Fedora exits 0" "0" "$rc"
  if log_has pacman || log_has mkinitcpio; then
    cat "$MOCK_LOG" >&2; fail "$bin: Fedora path makes no pacman/mkinitcpio call"
  else
    pass "$bin: Fedora path makes no pacman/mkinitcpio call"
  fi
done

# omarchy-plymouth-set is the silent no-op (called during theme switch).
rc=$(run fedora "$ROOT/bin/omarchy-plymouth-set" '#fff' '#000' /tmp/logo.png)
assert_equals "omarchy-plymouth-set: Fedora exits 0" "0" "$rc"
log_has mkinitcpio && fail "omarchy-plymouth-set: no mkinitcpio on Fedora" \
  || pass "omarchy-plymouth-set: no mkinitcpio on Fedora"

# --- install gates: Fedora dispatches to dnf names, not pacman --------------
run fedora "$ROOT/bin/omarchy-setup-security-fingerprint" >/dev/null || true
log_has 'pacman -Rdd' && { cat "$MOCK_LOG" >&2; fail "fingerprint: no pacman -Rdd on Fedora"; } \
  || pass "fingerprint: no pacman -Rdd on Fedora"
log_has 'omarchy-pkg-add fprintd fprintd-pam libfprint usbutils' \
  && pass "fingerprint: installs the Fedora package set" \
  || { cat "$MOCK_LOG" >&2; fail "fingerprint: installs the Fedora package set"; }

# --- Arch path preserved: Fedora arm is additive, Arch still calls pacman ----
# (byte-identity proves byte-equality; here just confirm the Arch path is live.)
rc=$(run arch "$ROOT/bin/omarchy-refresh-pacman" || true)
log_has pacman && pass "omarchy-refresh-pacman: Arch path still runs pacman" \
  || { cat "$MOCK_LOG" >&2; fail "omarchy-refresh-pacman: Arch path still runs pacman"; }

# --- debug: Fedora package list uses rpm/dnf, not the expac/pacman pipeline --
grep -q 'rpm -q omedora omedora-settings' "$ROOT/bin/omarchy-debug" \
  && pass "omarchy-debug: Fedora arm queries packages via rpm/dnf" \
  || fail "omarchy-debug: Fedora arm queries packages via rpm/dnf"

echo "# all archism-gating tests passed"
