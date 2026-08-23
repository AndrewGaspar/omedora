#!/bin/bash
# L1 (hypedora, PR upstream): tier-ul L4-nested rulează containerul de sesiune
# neconfinat de SELinux — pe un host Enforcing, systemd-ul din container (logind,
# polkit, upower) nu-și poate face mount namespacing și user@1000 nu pornește.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"
RT="$ROOT/omedora/test/fedora/headless/run-tests.sh"

bash -n "$RT" && pass "bash -n run-tests.sh" || fail "bash -n run-tests.sh"

src=$(cat "$RT")
assert_output_contains "containerul htest rulează cu label=disable" "$src" 'security-opt label=disable'

grep -qxF 'omedora/test/fedora/headless/run-tests.sh' "$ROOT/hypedora/upstream-patches.txt" \
  && pass "run-tests.sh e în upstream-patches.txt" || fail "run-tests.sh e în upstream-patches.txt"
