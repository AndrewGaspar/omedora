#!/bin/bash
# L1 (hypedora): boot.sh face preflight → omedora/boot.sh → post-install, în ordinea asta,
# și post-install scrie tweak-ul de VM doar când systemd-detect-virt raportează VM. Totul cu stub-uri.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"
[[ -f "$ROOT/hypedora/boot.sh" && -f "$ROOT/hypedora/post-install.sh" ]] || fail "boot.sh și post-install.sh există"
pass "boot.sh și post-install.sh există"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"; LOG="$TMP/calls.log"; : > "$LOG"
# checkout fals: omedora/boot.sh e un stub care loghează; hypedora/ e cel real
CO="$TMP/checkout"; mkdir -p "$CO/omedora" "$CO/hypedora"
cp "$ROOT/hypedora/boot.sh" "$ROOT/hypedora/post-install.sh" "$CO/hypedora/"
printf '#!/bin/bash\necho "omedora-boot REPO=$OMEDORA_REPO REF=$OMEDORA_REF" >> "%s"\n' "$LOG" > "$CO/omedora/boot.sh"
# stub-uri de sistem
for c in flatpak gdm; do printf '#!/bin/bash\nexit 0\n' > "$BIN/$c"; chmod +x "$BIN/$c"; done
printf '#!/bin/bash\necho "sudo $*" >> "%s"\n' "$LOG" > "$BIN/sudo"; chmod +x "$BIN/sudo"
printf '#!/bin/bash\nexit 0\n' > "$BIN/systemctl"; chmod +x "$BIN/systemctl"
printf '#!/bin/bash\n[[ "$1" == "--quiet" ]] && exit ${VIRT_RC:-1}; echo ${VIRT_NAME:-none}\n' > "$BIN/systemd-detect-virt"; chmod +x "$BIN/systemd-detect-virt"
cat > "$TMP/os-release" <<'EOF'
ID=fedora
VERSION_ID=44
EOF
HOME_T="$TMP/home"; mkdir -p "$HOME_T/.config/hypr"

# PATH strict la stub-uri: pe host-ul real flatpak/gdm există în /usr/bin și ar masca testul 3
# (cf. test/hypedora-preflight-host-test.sh); uneltele reale necesare primesc symlink-uri.
for t in bash grep dirname mkdir touch cat find cp cmp date; do ln -s "$(command -v "$t")" "$BIN/$t"; done
runboot() { ( export PATH="$BIN" HOME="$HOME_T" HYPEDORA_BOOT_DIR="$CO" HYPEDORA_OS_RELEASE="$TMP/os-release" HYPEDORA_ARCH=x86_64 HYPEDORA_UID=1000 "$@"; bash "$CO/hypedora/boot.sh" ) >"$TMP/out" 2>&1; echo $?; }

# 1) pe bare metal: ordinea apelurilor, fără tweak de VM
: > "$LOG"; rc=$(runboot VIRT_RC=1)
assert_equals "boot.sh exit 0 (bare metal)" "$rc" "0"
assert_output_contains "a rulat omedora/boot.sh cu fork-ul nostru" "$(cat "$LOG")" "omedora-boot REPO=bsorescu/hypedora REF=hypedora"
[[ ! -f "$HOME_T/.config/hypr/looknfeel.lua" ]] || ! grep -q no_hardware_cursors "$HOME_T/.config/hypr/looknfeel.lua" \
  && pass "fără tweak de cursor pe bare metal" || fail "fără tweak de cursor pe bare metal"

# 2) în VM: tweak-ul de cursor, idempotent
: > "$LOG"; rc=$(runboot VIRT_RC=0 VIRT_NAME=kvm); rc2=$(runboot VIRT_RC=0 VIRT_NAME=kvm)
assert_equals "boot.sh exit 0 (VM)" "$rc" "0"
n=$(grep -c 'no_hardware_cursors = true' "$HOME_T/.config/hypr/looknfeel.lua")
assert_equals "tweak-ul de cursor scris o singură dată după două rulări" "$n" "1"

# 3) preflight: fără flatpak → exit 1 cu mesaj
rm -f "$BIN/flatpak"; rc=$(runboot VIRT_RC=1)
assert_equals "fără flatpak → exit 1" "$rc" "1"
assert_output_contains "explică grupul Workstation" "$(cat "$TMP/out")" "workstation-product-environment"
