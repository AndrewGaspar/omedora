#!/bin/bash
# L1 (hypedora, PR upstream): pipeline-ul L4-VM e portat la Omedora 4 și are grafica parametrizabilă.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"
VM="$ROOT/omedora/test/fedora/vm"

for f in run-vm-test.sh in-vm/assert-install.sh in-vm/run-suite-in-session.sh; do
  bash -n "$VM/$f" && pass "bash -n $f" || fail "bash -n $f"
done

src=$(cat "$VM/run-vm-test.sh")
assert_output_contains "install stage rulează omedora/install-4.sh" "$src" "omedora/install-4.sh"
assert_output_lacks   "install stage nu mai rulează install.sh de la rădăcină" "$src" 'omarchy/install.sh 2>&1'
assert_output_contains "install stage trece OMEDORA_PLAN_AUTOCONFIRM=1" "$src" "OMEDORA_PLAN_AUTOCONFIRM=1"
assert_output_contains "grafica e parametrizabilă (OMEDORA_VM_GRAPHICS)" "$src" 'OMEDORA_VM_GRAPHICS'
assert_output_contains "video e parametrizabil (OMEDORA_VM_VIDEO)" "$src" 'OMEDORA_VM_VIDEO'
assert_output_contains "geometry-skip e transmis în VM" "$src" 'OMEDORA_VM_GEOMETRY_SKIP'

asrt=$(cat "$VM/in-vm/assert-install.sh")
assert_output_lacks   "assert-install nu mai cere hyprland-omedora ca keystone" "$asrt" 'rpm -q hyprland-omedora'
assert_output_contains "assert-install cere omedora-settings" "$asrt" 'omedora-settings'

suite=$(cat "$VM/in-vm/run-suite-in-session.sh")
assert_output_contains "SCREENSHOT_GEOMETRY_SKIP e configurabil" "$suite" 'SCREENSHOT_GEOMETRY_SKIP="${SCREENSHOT_GEOMETRY_SKIP:-1}"'

grep -qxF 'omedora/test/fedora/vm/run-vm-test.sh' "$ROOT/hypedora/upstream-patches.txt" \
  && pass "run-vm-test.sh e în upstream-patches.txt" || fail "run-vm-test.sh e în upstream-patches.txt"
