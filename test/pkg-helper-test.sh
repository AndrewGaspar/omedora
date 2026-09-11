#!/bin/bash
#
# L1 unit tests for bin/omarchy-pkg-* helpers' Fedora dispatch.
#
# Mocks dnf/rpm/flatpak/sudo via PATH manipulation, sets OMARCHY_DISTRO=fedora,
# and asserts the helpers route through bin/fedora/pkg.py with the right
# package-map resolution. No real package installation occurs.
#
# Tests can run from any host (Arch, Fedora, CI on Ubuntu).

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

MOCK_LOG="$TMPDIR/mock.log"
# Fixture map exercising each tier
FIXTURE_MAP="$TMPDIR/fedora.toml"
cat >"$FIXTURE_MAP" <<'EOF'
[ttf-jetbrains-mono-nerd]
source = "dnf"
names = ["jetbrains-mono-fonts-all"]

[ghostty]
source = "copr"
copr = "scottames/ghostty"
names = ["ghostty"]

[obsidian]
source = "flathub"
app_id = "md.obsidian.Obsidian"

[ufw]
source = "skip"
reason = "Fedora ships firewalld"

[future-name]
source = "dnf"
names = ["future-name-fedora"]
since = "45"

[former-name]
source = "dnf"
names = ["former-name-fedora"]
until = "45"
EOF

# Prepend our mocks to PATH so the dispatch lands in them, not the real binaries.
# Also include the omarchy bin/ so omarchy-distro is reachable from the shim.
export PATH="$ROOT/test/mocks:$ROOT/bin:$PATH"
export OMARCHY_DISTRO=fedora
export OMARCHY_FEDORA_MAP="$FIXTURE_MAP"
export OMEDORA_FEDORA_VERSION=44
export MOCK_LOG
# pkg.py skips Flatpak installs when there's no DBus session bus (correct on a
# bare container/TTY). These tests verify the flatpak *routing* via the mock, so
# simulate a session bus; otherwise the assertions fail inside the L2 Fedora
# container (no bus) while passing on the L1 Ubuntu runner (bus present).
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/$(id -u)/bus}"
# Ensure VM-fast mode (another flatpak-skip path) is never inherited from CI env.
unset OMEDORA_VM_FAST

reset_log() { : >"$MOCK_LOG"; }
log_contains() { grep -qF "$1" "$MOCK_LOG"; }
log_lacks()    { ! grep -qF "$1" "$MOCK_LOG"; }

# --- omarchy-pkg-add: simple dnf install ---

reset_log
"$ROOT/bin/omarchy-pkg-add" jq >/dev/null 2>&1 || true
if log_contains "sudo dnf install -y --setopt=install_weak_deps=False jq"; then
  pass "pkg-add jq → sudo dnf install -y jq"
else
  cat "$MOCK_LOG" >&2
  fail "pkg-add jq → expected dnf install call"
fi

# --- omarchy-pkg-add: name translation via map ---

reset_log
"$ROOT/bin/omarchy-pkg-add" ttf-jetbrains-mono-nerd >/dev/null 2>&1 || true
if log_contains "sudo dnf install -y --setopt=install_weak_deps=False jetbrains-mono-fonts-all"; then
  pass "pkg-add translates ttf-jetbrains-mono-nerd → jetbrains-mono-fonts-all"
else
  cat "$MOCK_LOG" >&2
  fail "pkg-add → expected translated install call"
fi

# --- omarchy-pkg-add: COPR enable + install ---

reset_log
"$ROOT/bin/omarchy-pkg-add" ghostty >/dev/null 2>&1 || true
if log_contains "sudo dnf copr enable -y scottames/ghostty"; then
  pass "pkg-add ghostty enables scottames/ghostty COPR"
else
  cat "$MOCK_LOG" >&2
  fail "pkg-add ghostty → expected COPR enable call"
fi
if log_contains "sudo dnf install -y --setopt=install_weak_deps=False ghostty"; then
  pass "pkg-add ghostty → install after COPR enable"
else
  cat "$MOCK_LOG" >&2
  fail "pkg-add ghostty → expected dnf install after COPR enable"
fi

# --- omarchy-pkg-add: flathub install ---

reset_log
"$ROOT/bin/omarchy-pkg-add" obsidian >/dev/null 2>&1 || true
if log_contains "flatpak install --user -y flathub md.obsidian.Obsidian"; then
  pass "pkg-add obsidian → flatpak install flathub md.obsidian.Obsidian"
else
  cat "$MOCK_LOG" >&2
  fail "pkg-add obsidian → expected flatpak install call"
fi

# --- omarchy-pkg-add: skip is a no-op (and not a dnf install) ---

reset_log
"$ROOT/bin/omarchy-pkg-add" ufw >/dev/null 2>&1 || true
if log_lacks "sudo dnf install -y --setopt=install_weak_deps=False ufw"; then
  pass "pkg-add ufw (skip=true) → no dnf install"
else
  cat "$MOCK_LOG" >&2
  fail "pkg-add ufw → unexpectedly tried to install"
fi

# --- omarchy-pkg-missing: skip entry is always "present" ---

reset_log
set +e
"$ROOT/bin/omarchy-pkg-missing" ufw >/dev/null 2>&1
exit_code=$?
set -e
assert_equals "pkg-missing ufw (skip) → exit 1 (not missing)" "$exit_code" "1"

# --- omarchy-pkg-missing: returns 0 (missing) for unknown package on empty mock ---

reset_log
set +e
"$ROOT/bin/omarchy-pkg-missing" some-random-package >/dev/null 2>&1
exit_code=$?
set -e
assert_equals "pkg-missing some-random-package → exit 0 (missing)" "$exit_code" "0"

# --- omarchy-pkg-missing: returns 1 when MOCK_RPM_INSTALLED includes the package ---

reset_log
set +e
MOCK_RPM_INSTALLED="installed-pkg" "$ROOT/bin/omarchy-pkg-missing" installed-pkg >/dev/null 2>&1
exit_code=$?
set -e
assert_equals "pkg-missing installed-pkg → exit 1 (all present)" "$exit_code" "1"

# --- omarchy-pkg-present: inverse of missing ---

reset_log
set +e
"$ROOT/bin/omarchy-pkg-present" ufw >/dev/null 2>&1
exit_code=$?
set -e
assert_equals "pkg-present ufw (skip) → exit 0 (present)" "$exit_code" "0"

reset_log
set +e
"$ROOT/bin/omarchy-pkg-present" not-installed >/dev/null 2>&1
exit_code=$?
set -e
assert_equals "pkg-present not-installed → exit 1 (missing)" "$exit_code" "1"

# --- since/until: inactive entries are treated as intentional no-ops ---

reset_log
output=$("$ROOT/bin/omarchy-pkg-add" future-name former-name 2>&1 || true)
if log_contains "sudo dnf install -y --setopt=install_weak_deps=False former-name-fedora" &&
  log_lacks "future-name"; then
  pass "Fedora 44 installs active mappings and skips future mappings"
else
  cat "$MOCK_LOG" >&2
  fail "Fedora 44 applies since/until package-map bounds"
fi
assert_output_contains "inactive future mapping reports why it was skipped" \
  "$output" "mapping does not apply"

set +e
OMEDORA_FEDORA_VERSION=44 "$ROOT/bin/omarchy-pkg-present" future-name >/dev/null 2>&1
present_rc=$?
OMEDORA_FEDORA_VERSION=44 "$ROOT/bin/omarchy-pkg-missing" future-name >/dev/null 2>&1
missing_rc=$?
set -e
assert_equals "inactive mapping is present for guard semantics" "$present_rc" "0"
assert_equals "inactive mapping is not missing for guard semantics" "$missing_rc" "1"
reset_log
OMEDORA_FEDORA_VERSION=44 "$ROOT/bin/omarchy-pkg-drop" future-name >/dev/null 2>&1
log_lacks "dnf remove" && pass "inactive mapping removal is a no-op" \
  || fail "inactive mapping removal is a no-op"

reset_log
OMEDORA_FEDORA_VERSION=45 "$ROOT/bin/omarchy-pkg-add" future-name former-name >/dev/null 2>&1 || true
if log_contains "sudo dnf install -y --setopt=install_weak_deps=False future-name-fedora" &&
  log_lacks "former-name"; then
  pass "Fedora 45 installs active mappings and skips expired mappings"
else
  cat "$MOCK_LOG" >&2
  fail "Fedora 45 applies since/until package-map bounds"
fi

# --- real map: sof-firmware translates to alsa-sof-firmware (issue #10) ---
# migrations/1784401744.sh, install/hardware/intel/sof-firmware.sh and
# bin/omarchy-upgrade-to-quattro all reach `omarchy-pkg-add sof-firmware`.
# Fedora has no package by that name; the map must translate it so the
# migration installs alsa-sof-firmware, and sees it as present once installed.

REAL_MAP="$ROOT/install/packages/fedora.toml"

set +e
MOCK_RPM_INSTALLED="alsa-sof-firmware" OMARCHY_FEDORA_MAP="$REAL_MAP" \
  "$ROOT/bin/omarchy-pkg-missing" sof-firmware >/dev/null 2>&1
exit_code=$?
set -e
assert_equals "pkg-missing sof-firmware → exit 1 when alsa-sof-firmware is installed" "$exit_code" "1"

reset_log
MOCK_RPM_INSTALLED="alsa-sof-firmware" OMARCHY_FEDORA_MAP="$REAL_MAP" \
  "$ROOT/bin/omarchy-pkg-add" sof-firmware >/dev/null 2>&1 || true
if log_lacks "dnf install"; then
  pass "pkg-add sof-firmware → no dnf install when alsa-sof-firmware is installed"
else
  cat "$MOCK_LOG" >&2
  fail "pkg-add sof-firmware → unexpectedly tried to install"
fi

set +e
OMARCHY_FEDORA_MAP="$REAL_MAP" "$ROOT/bin/omarchy-pkg-missing" sof-firmware >/dev/null 2>&1
exit_code=$?
set -e
assert_equals "pkg-missing sof-firmware → exit 0 when alsa-sof-firmware is absent" "$exit_code" "0"

reset_log
output=$(OMARCHY_PKG_DRY_RUN=1 OMARCHY_FEDORA_MAP="$REAL_MAP" \
  "$ROOT/bin/omarchy-pkg-add" sof-firmware 2>&1 || true)
assert_output_contains "pkg-add sof-firmware dry-run installs alsa-sof-firmware" \
  "$output" "sudo dnf install -y --setopt=install_weak_deps=False alsa-sof-firmware"
assert_output_lacks "pkg-add sof-firmware dry-run never passes the Arch name to dnf" \
  "$output" "install_weak_deps=False sof-firmware"

# --- omarchy-pkg-drop: dnf remove for installed dnf package ---

reset_log
MOCK_RPM_INSTALLED="jq" "$ROOT/bin/omarchy-pkg-drop" jq >/dev/null 2>&1 || true
if log_contains "sudo dnf remove -y jq"; then
  pass "pkg-drop jq (installed) → sudo dnf remove -y jq"
else
  cat "$MOCK_LOG" >&2
  fail "pkg-drop jq → expected dnf remove call"
fi

# --- omarchy-pkg-drop: not-installed package does nothing ---

reset_log
"$ROOT/bin/omarchy-pkg-drop" not-installed >/dev/null 2>&1 || true
if log_lacks "sudo dnf remove"; then
  pass "pkg-drop not-installed → no remove call"
else
  cat "$MOCK_LOG" >&2
  fail "pkg-drop not-installed → unexpectedly tried to remove"
fi

# --- omarchy-pkg-aur-add: behaves identically to pkg-add on Fedora ---

reset_log
"$ROOT/bin/omarchy-pkg-aur-add" obsidian >/dev/null 2>&1 || true
if log_contains "flatpak install --user -y flathub md.obsidian.Obsidian"; then
  pass "pkg-aur-add obsidian → flatpak install (tier fallback)"
else
  cat "$MOCK_LOG" >&2
  fail "pkg-aur-add obsidian → expected tier-fallback flatpak install"
fi

# --- OMARCHY_DISTRO env override: even on real arch hosts the env wins ---

unset OMARCHY_DISTRO
reset_log
set +e
OMARCHY_DISTRO=fedora "$ROOT/bin/omarchy-pkg-add" jq >/dev/null 2>&1
set -e
if log_contains "sudo dnf install -y --setopt=install_weak_deps=False jq"; then
  pass "OMARCHY_DISTRO=fedora env override forces dnf dispatch"
else
  cat "$MOCK_LOG" >&2
  fail "OMARCHY_DISTRO=fedora env override should have forced dnf dispatch"
fi

# Re-export for any remaining test logic
export OMARCHY_DISTRO=fedora

# --- Arch path is byte-for-byte preserved: OMARCHY_DISTRO=arch routes to pacman ---

reset_log
# Don't pre-stage jq as installed; we want omarchy-pkg-missing to report
# "missing" so the install branch runs. The post-install verification will
# fail (we didn't actually install jq), but we only care that pacman -S
# was attempted — tolerate the non-zero exit with || true.
OMARCHY_DISTRO=arch "$ROOT/bin/omarchy-pkg-add" jq >/dev/null 2>&1 || true
if log_contains "pacman -S --noconfirm --needed jq"; then
  pass "OMARCHY_DISTRO=arch dispatches to pacman (Arch path preserved)"
else
  cat "$MOCK_LOG" >&2
  fail "OMARCHY_DISTRO=arch should route to pacman, not dnf"
fi
if log_lacks "dnf install"; then
  pass "Arch path emits NO dnf calls (dual-distro contract)"
else
  cat "$MOCK_LOG" >&2
  fail "Arch path leaked a dnf call"
fi
