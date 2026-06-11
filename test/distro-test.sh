#!/bin/bash
#
# L1 unit tests for bin/omarchy-distro.
#
# Tests distro detection against fixture os-release files via the
# OMARCHY_OS_RELEASE_PATH env hook, plus the OMARCHY_DISTRO escape hatch.
# No /etc/os-release reads (the host's distro is irrelevant to these tests).

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

DISTRO="$ROOT/bin/omarchy-distro"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

write_fixture() {
  local name="$1"
  local content="$2"
  local path="$TMPDIR/$name"
  printf '%s\n' "$content" >"$path"
  printf '%s' "$path"
}

# --- Fixture: vanilla Arch ---
arch_release=$(write_fixture arch-release 'NAME="Arch Linux"
ID=arch
PRETTY_NAME="Arch Linux"')

actual=$(OMARCHY_OS_RELEASE_PATH="$arch_release" "$DISTRO")
assert_equals "ID=arch is detected as arch" "$actual" "arch"

# --- Fixture: vanilla Fedora 44 ---
fedora_release=$(write_fixture fedora-release 'NAME="Fedora Linux"
VERSION="44 (Workstation Edition)"
ID=fedora
VERSION_ID="44"
PRETTY_NAME="Fedora Linux 44 (Workstation Edition)"')

actual=$(OMARCHY_OS_RELEASE_PATH="$fedora_release" "$DISTRO")
assert_equals "ID=fedora is detected as fedora" "$actual" "fedora"

# --- ID_LIKE fallback: AlmaLinux ish (ID_LIKE=fedora) ---
almalinux_release=$(write_fixture almalinux-release 'NAME="AlmaLinux"
ID=almalinux
ID_LIKE="rhel centos fedora"
PRETTY_NAME="AlmaLinux 9"')

actual=$(OMARCHY_OS_RELEASE_PATH="$almalinux_release" "$DISTRO")
assert_equals "ID_LIKE=...fedora... falls back to fedora" "$actual" "fedora"

# --- ID_LIKE fallback: Manjaro (ID_LIKE=arch) ---
manjaro_release=$(write_fixture manjaro-release 'NAME="Manjaro Linux"
ID=manjaro
ID_LIKE=arch
PRETTY_NAME="Manjaro Linux"')

actual=$(OMARCHY_OS_RELEASE_PATH="$manjaro_release" "$DISTRO")
assert_equals "ID_LIKE=arch falls back to arch" "$actual" "arch"

# --- OMARCHY_DISTRO env override beats os-release ---
actual=$(OMARCHY_DISTRO=fedora OMARCHY_OS_RELEASE_PATH="$arch_release" "$DISTRO")
assert_equals "OMARCHY_DISTRO=fedora overrides arch fixture" "$actual" "fedora"

actual=$(OMARCHY_DISTRO=arch OMARCHY_OS_RELEASE_PATH="$fedora_release" "$DISTRO")
assert_equals "OMARCHY_DISTRO=arch overrides fedora fixture" "$actual" "arch"

# --- Unsupported distro exits non-zero ---
unsupported_release=$(write_fixture unsupported-release 'NAME="Some Other Distro"
ID=other
PRETTY_NAME="Some Other Distro"')

assert_exit_code "unsupported distro exits 1" 1 \
  env OMARCHY_OS_RELEASE_PATH="$unsupported_release" "$DISTRO"

# --- Missing os-release file exits non-zero ---
assert_exit_code "missing os-release exits 1" 1 \
  env OMARCHY_OS_RELEASE_PATH="$TMPDIR/does-not-exist" "$DISTRO"

# --- Quoted values are unquoted correctly ---
quoted_release=$(write_fixture quoted-release 'ID="fedora"
PRETTY_NAME="Fedora Linux 44"')

actual=$(OMARCHY_OS_RELEASE_PATH="$quoted_release" "$DISTRO")
assert_equals "quoted ID values are unquoted" "$actual" "fedora"
