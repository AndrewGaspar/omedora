#!/bin/bash
# L1 (hypedora): preflight-host.sh raportează corect uneltele lipsă și trece când totul e prezent.
# Rulează cu un PATH controlat (stub-uri) și /dev/kvm + /dev/dri simulate prin HYPEDORA_DEV_ROOT.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"
SCRIPT="$ROOT/hypedora/vm/preflight-host.sh"
[[ -x "$SCRIPT" ]] || fail "hypedora/vm/preflight-host.sh există și e executabil"
pass "hypedora/vm/preflight-host.sh există și e executabil"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN" "$TMP/dev/dri"
: > "$TMP/dev/kvm"; : > "$TMP/dev/dri/renderD128"

mkstub() { printf '#!/bin/bash\nexit 0\n' > "$BIN/$1"; chmod +x "$BIN/$1"; }
for t in virt-install virsh qemu-system-x86_64 qemu-img xorriso ssh openssl passt podman; do mkstub "$t"; done
# df/free stub-uri: spațiu și RAM mari
printf '#!/bin/bash\necho "Filesystem 1G-blocks Used Available Use%% Mounted"\necho "/dev/x 500 100 400 20%% /var/tmp"\n' > "$BIN/df"; chmod +x "$BIN/df"
printf '#!/bin/bash\necho "              total        used        free"\necho "Mem:       16000000     1000000    15000000"\n' > "$BIN/free"; chmod +x "$BIN/free"

# PATH strict la stub-uri: pe host-ul real passt & co. există în /usr/bin și ar masca testul.
for t in bash ls head tail tr awk; do ln -s "$(command -v "$t")" "$BIN/$t"; done
run() { PATH="$BIN" HYPEDORA_DEV_ROOT="$TMP/dev" bash "$SCRIPT" >"$TMP/out" 2>&1; echo $?; }

rc=$(run)
assert_equals "toate prezente → exit 0" "$rc" "0"

rm -f "$BIN/passt"
rc=$(run)
assert_equals "passt lipsă → exit 1" "$rc" "1"
assert_output_contains "raportează passt" "$(cat "$TMP/out")" "passt"
assert_output_contains "sugerează dnf install" "$(cat "$TMP/out")" "sudo dnf install"
mkstub passt

rm -f "$TMP/dev/kvm"
rc=$(run)
assert_equals "/dev/kvm lipsă → exit 1" "$rc" "1"
assert_output_contains "raportează /dev/kvm" "$(cat "$TMP/out")" "/dev/kvm"
