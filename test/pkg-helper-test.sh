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
INSTALLERS_DIR="$TMPDIR/installers"
mkdir -p "$INSTALLERS_DIR"
echo '#!/bin/bash' >"$INSTALLERS_DIR/install-walker.sh"
chmod +x "$INSTALLERS_DIR/install-walker.sh"

# Fixture map exercising each tier
FIXTURE_MAP="$TMPDIR/fedora.toml"
cat >"$FIXTURE_MAP" <<'EOF'
[ttf-jetbrains-mono-nerd]
source = "dnf"
names = ["jetbrains-mono-fonts-all"]

[hyprland]
source = "copr"
copr = "lionheartp/Hyprland"
names = ["hyprland"]

[obsidian]
source = "flathub"
app_id = "md.obsidian.Obsidian"

[walker]
source = "source"
installer = "install-walker.sh"

[ufw]
source = "skip"
reason = "Fedora ships firewalld"
EOF

# Prepend our mocks to PATH so the dispatch lands in them, not the real binaries.
# Also include the omarchy bin/ so omarchy-distro is reachable from the shim.
export PATH="$ROOT/test/mocks:$ROOT/bin:$PATH"
export OMARCHY_DISTRO=fedora
export OMARCHY_FEDORA_MAP="$FIXTURE_MAP"
export OMARCHY_FEDORA_INSTALLERS="$INSTALLERS_DIR"
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
"$ROOT/bin/omarchy-pkg-add" hyprland >/dev/null 2>&1 || true
if log_contains "sudo dnf copr enable -y lionheartp/Hyprland"; then
  pass "pkg-add hyprland enables lionheartp/Hyprland COPR"
else
  cat "$MOCK_LOG" >&2
  fail "pkg-add hyprland → expected COPR enable call"
fi
if log_contains "sudo dnf install -y --setopt=install_weak_deps=False hyprland"; then
  pass "pkg-add hyprland → install after COPR enable"
else
  cat "$MOCK_LOG" >&2
  fail "pkg-add hyprland → expected dnf install after COPR enable"
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

# --- omarchy-pkg-add: source installer ---

reset_log
walker_installer_marker="$TMPDIR/walker-was-run"
cat >"$INSTALLERS_DIR/install-walker.sh" <<EOF
#!/bin/bash
touch "$walker_installer_marker"
EOF
chmod +x "$INSTALLERS_DIR/install-walker.sh"

"$ROOT/bin/omarchy-pkg-add" walker >/dev/null 2>&1 || true
assert_file_exists "pkg-add walker → runs install-walker.sh installer" "$walker_installer_marker"

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
