#!/bin/bash
# L1 (hypedora): run-l4-vm.sh compune corect mediul GL pentru run-vm-test.sh (HYPEDORA_DRY_RUN=1 → doar afișează).
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"
S="$ROOT/hypedora/vm/run-l4-vm.sh"
[[ -x "$S" ]] || fail "run-l4-vm.sh există și e executabil"; pass "run-l4-vm.sh există și e executabil"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/dev/dri"; : > "$TMP/dev/dri/renderD128"
out=$(HYPEDORA_DRY_RUN=1 HYPEDORA_DEV_ROOT="$TMP/dev" HYPEDORA_SKIP_PREFLIGHT=1 bash "$S" --keep 2>&1)
assert_output_contains "egl-headless cu rendernode" "$out" "OMEDORA_VM_GRAPHICS=egl-headless,rendernode=$TMP/dev/dri/renderD128"
assert_output_contains "virtio accel3d"             "$out" "OMEDORA_VM_VIDEO=model.type=virtio,model.acceleration.accel3d=yes"
assert_output_contains "1920x1080"                  "$out" "OMEDORA_VM_RES=1920x1080"
assert_output_contains "geometry skip off"          "$out" "OMEDORA_VM_GEOMETRY_SKIP=0"
assert_output_contains "RAM 6144"                   "$out" "OMEDORA_VM_RAM_MB=6144"
assert_output_contains "argumentele trec mai departe" "$out" "run-vm-test.sh --keep"
