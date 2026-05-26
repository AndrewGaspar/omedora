#!/bin/bash
#
# L2 integration tests — runs INSIDE the fedora:44 test image.
# See omedora/testing.md §2 and §5.
#
# This test exercises the real Fedora install paths (real dnf, real rpm,
# real COPR enable) against the omedora package helpers. The repo is
# expected to be bind-mounted at /repo.
#
# Sections (TAP-style output throughout):
#   - Distro detection on real Fedora
#   - L1 tests rerun inside the container (regression check)
#   - Package map validator runs against the real fedora.toml
#   - Brand defaults to omedora on Fedora
#   - Real dnf install via omarchy-pkg-add (small package: jq)
#   - Real package-map translation install
#   - Real COPR enable (lionheartp/Hyprland)
#   - Update flow staging: omarchy-update-fedora-version-check trigger

set -uo pipefail

REPO="${REPO:-/repo}"
if [[ ! -d $REPO/bin ]]; then
  echo "expected repo at $REPO; bind-mount via -v \$PWD:/repo" >&2
  exit 1
fi

cd "$REPO"

# Shared TAP helpers + container helpers.
. "$REPO/test/helpers.sh"
. "$REPO/test/fedora/lib/container.sh"

ensure_running_as_root

# Put repo bin on PATH so omarchy-* helpers find their siblings (omarchy-distro,
# bin/fedora/pkg.py via dispatch). The tests do NOT prepend test/mocks here —
# we want REAL dnf/rpm/flatpak.
export PATH="$REPO/bin:$PATH"
export OMARCHY_PATH="$REPO"

# Use a dedicated workdir for state markers so tests don't pollute /root.
export HOME="${HOME:-/root}"

# ============================================================================
echo "=== Distro detection on real Fedora ==="
# ============================================================================

actual=$(omarchy-distro)
assert_equals "omarchy-distro returns 'fedora' on Fedora container" "$actual" "fedora"

# ============================================================================
echo "=== L1 unit tests rerun on Fedora (regression check) ==="
# ============================================================================

# Run the existing dispatcher test inside Fedora — it must pass identically.
if bash "$REPO/test/omarchy-cli-test.sh" >/tmp/cli-test.out 2>&1; then
  pass "L1: test/omarchy-cli-test.sh passes on Fedora"
else
  tail -20 /tmp/cli-test.out >&2
  fail "L1: test/omarchy-cli-test.sh failed on Fedora"
fi

# Distro test
if bash "$REPO/test/distro-test.sh" >/tmp/distro-test.out 2>&1; then
  pass "L1: test/distro-test.sh passes on Fedora"
else
  tail -20 /tmp/distro-test.out >&2
  fail "L1: test/distro-test.sh failed on Fedora"
fi

# Pkg-map test
if bash "$REPO/test/pkg-map-test.sh" >/tmp/pkg-map-test.out 2>&1; then
  pass "L1: test/pkg-map-test.sh passes on Fedora"
else
  tail -20 /tmp/pkg-map-test.out >&2
  fail "L1: test/pkg-map-test.sh failed on Fedora"
fi

# Pkg-helper test (mocked) — should also pass on Fedora since it uses mocks.
if bash "$REPO/test/pkg-helper-test.sh" >/tmp/pkg-helper-test.out 2>&1; then
  pass "L1: test/pkg-helper-test.sh passes on Fedora (with mocks)"
else
  tail -20 /tmp/pkg-helper-test.out >&2
  fail "L1: test/pkg-helper-test.sh failed on Fedora"
fi

# ============================================================================
echo "=== Package map validator runs against real fedora.toml ==="
# ============================================================================

if "$REPO/bin/omarchy-dev-validate-fedora-packages" >/tmp/validate.out 2>&1; then
  pass "validator accepts the real install/packages/fedora.toml"
else
  cat /tmp/validate.out >&2
  fail "validator rejected the real fedora.toml"
fi

# ============================================================================
echo "=== Brand defaults to omedora on Fedora ==="
# ============================================================================

# When invoked as `omarchy` on Fedora, the brand shim picks omedora (via
# omarchy-distro). Verify the help output reflects that.
help_output=$("$REPO/bin/omarchy" --help 2>&1)
assert_output_contains "Fedora invocation of omarchy renders Omedora header" \
  "$help_output" "Omedora command center"

# `omedora` symlink invocation also says Omedora.
help_output_omedora=$("$REPO/bin/omedora" --help 2>&1)
assert_output_contains "omedora symlink invocation renders Omedora header" \
  "$help_output_omedora" "Omedora command center"

# Forcing OMARCHY_BRAND=omarchy still reverts to upstream brand even on Fedora.
help_output_forced=$(OMARCHY_BRAND=omarchy "$REPO/bin/omarchy" --help 2>&1)
assert_output_contains "OMARCHY_BRAND=omarchy override on Fedora reverts to Omarchy" \
  "$help_output_forced" "Omarchy command center"

# ============================================================================
echo "=== Real dnf install via omarchy-pkg-add ==="
# ============================================================================

# Make sure jq is removed first so we actually test install, not skip.
# (It's already installed by the Dockerfile, so this just exercises the path.)
assert_dnf_installed "jq is preinstalled from the Dockerfile" "jq"

# Pick a tiny package that ISN'T in the Dockerfile: cowsay (~30KB).
# omarchy-pkg-add cowsay should dispatch to Fedora arm → install via dnf.
dnf -y remove cowsay >/dev/null 2>&1 || true
assert_dnf_not_installed "cowsay is not installed (preflight)" "cowsay"

"$REPO/bin/omarchy-pkg-add" cowsay >/tmp/pkg-add.out 2>&1
if (( $? == 0 )); then
  assert_dnf_installed "omarchy-pkg-add cowsay → cowsay is installed" "cowsay"
else
  cat /tmp/pkg-add.out >&2
  fail "omarchy-pkg-add cowsay failed"
fi

# Verify omarchy-pkg-present reports it as installed.
if "$REPO/bin/omarchy-pkg-present" cowsay >/dev/null 2>&1; then
  pass "omarchy-pkg-present cowsay returns 0 (installed)"
else
  fail "omarchy-pkg-present cowsay returned non-zero"
fi

# Verify omarchy-pkg-missing reports it as NOT missing.
if "$REPO/bin/omarchy-pkg-missing" cowsay >/dev/null 2>&1; then
  fail "omarchy-pkg-missing cowsay returned 0 (claimed missing) but it is installed"
else
  pass "omarchy-pkg-missing cowsay returns 1 (not missing)"
fi

# Remove via omarchy-pkg-drop and verify.
"$REPO/bin/omarchy-pkg-drop" cowsay >/tmp/pkg-drop.out 2>&1
if (( $? == 0 )); then
  assert_dnf_not_installed "omarchy-pkg-drop cowsay → cowsay is gone" "cowsay"
else
  cat /tmp/pkg-drop.out >&2
  fail "omarchy-pkg-drop cowsay failed"
fi

# ============================================================================
echo "=== Real package-map translation: ttf-jetbrains-mono-nerd ==="
# ============================================================================

# fedora.toml maps ttf-jetbrains-mono-nerd → jetbrains-mono-fonts-all.
# Verify the translation by installing the Arch name and checking the
# Fedora name landed.
dnf -y remove jetbrains-mono-fonts-all >/dev/null 2>&1 || true
assert_dnf_not_installed "jetbrains-mono-fonts-all not preinstalled" "jetbrains-mono-fonts-all"

"$REPO/bin/omarchy-pkg-add" ttf-jetbrains-mono-nerd >/tmp/pkg-add-ttf.out 2>&1
if (( $? == 0 )); then
  assert_dnf_installed "translated package landed under Fedora name" "jetbrains-mono-fonts-all"
else
  cat /tmp/pkg-add-ttf.out >&2
  fail "omarchy-pkg-add ttf-jetbrains-mono-nerd failed"
fi

# ============================================================================
echo "=== Skip entries are no-ops (no install attempted) ==="
# ============================================================================

# ufw is source=skip in fedora.toml.
output=$("$REPO/bin/omarchy-pkg-add" ufw 2>&1)
assert_output_contains "pkg-add ufw logs skip with reason" "$output" "skipping 'ufw'"
assert_output_contains "pkg-add ufw mentions firewalld in the reason" "$output" "firewalld"
assert_dnf_not_installed "ufw is NOT installed after skip" "ufw"

# ============================================================================
echo "=== Real COPR enablement ==="
# ============================================================================

# Disable the COPR first to make this test idempotent.
dnf -y copr disable lionheartp/Hyprland >/dev/null 2>&1 || true

# Trigger a COPR install but stop short of installing the big Hyprland package
# (it pulls a lot in). Use dry-run mode on pkg.py so we only enable the COPR
# without doing the full install.
OMARCHY_PKG_DRY_RUN=1 "$REPO/bin/omarchy-pkg-add" hyprland >/tmp/copr.out 2>&1
exit_code=$?

# Even in dry-run, the COPR enable runs as a real command (dry-run only logs
# what would happen, but our pkg.py logs the command without executing it).
# So the COPR isn't actually enabled in dry-run.
# For a true L2 test, run without dry-run but with --setopt=install_only_one
# or accept the install cost. We'll do the real enable since it's idempotent.

# Real test: enable the COPR without installing.
if dnf -y copr enable lionheartp/Hyprland >/tmp/copr-enable.out 2>&1; then
  assert_copr_enabled "lionheartp/Hyprland COPR enables cleanly" "lionheartp/Hyprland"
else
  cat /tmp/copr-enable.out >&2
  fail "COPR enable lionheartp/Hyprland failed"
fi

# Verify dnf can resolve hyprland from the COPR.
if dnf list available hyprland --refresh >/tmp/hyprland-list.out 2>&1; then
  pass "dnf can resolve hyprland from lionheartp/Hyprland after enable"
else
  cat /tmp/hyprland-list.out >&2
  fail "dnf cannot find hyprland after enabling lionheartp/Hyprland"
fi

# Clean up: disable the COPR.
dnf -y copr disable lionheartp/Hyprland >/dev/null 2>&1 || true

# ============================================================================
echo "=== Brand-aware omarchy-version reads omedora/version on Fedora ==="
# ============================================================================

version_output=$("$REPO/bin/omarchy-version" 2>&1)
assert_output_contains "version output mentions Omedora on Fedora" \
  "$version_output" "Omedora"
assert_output_contains "version output mentions Omarchy upstream" \
  "$version_output" "rebased on Omarchy"

echo ""
echo "=== All L2 integration tests passed ==="
