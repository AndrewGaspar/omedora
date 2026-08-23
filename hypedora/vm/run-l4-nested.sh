#!/bin/bash
# hypedora: rulează tier-ul L4-nested al omedora (podman rootless + labwc + Hyprland
# nested + shell-ul Quickshell pe un render node REAL) și păstrează raportul TAP.
# Prima rulare construiește imaginea de sesiune din COPR-ul live (20–40 min).
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
RESULTS="${HYPEDORA_RESULTS:-/var/tmp/hypedora-results}"
mkdir -p "$RESULTS"
stamp=$(date +%Y%m%d-%H%M%S)

bash "$ROOT/hypedora/vm/preflight-host.sh"

# Upstream bind-montează scripturile de sesiune fără etichetă SELinux (:z), deci pe
# un host Fedora cu SELinux Enforcing containerul primește „Permission denied".
# Etichetăm fișierele montate aici, în stratul nostru (candidat de PR upstream: `,z`).
if command -v getenforce >/dev/null 2>&1 && [[ $(getenforce) == "Enforcing" ]]; then
  chcon -t container_file_t \
    "$ROOT/omedora/test/fedora/omedora-session/staged-install-4.sh" \
    "$ROOT/omedora/test/fedora/omedora-session/session-launch.sh" \
    "$ROOT/omedora/test/fedora/omedora-session/session-launch-headless.sh" \
    "$ROOT/omedora/test/fedora/omedora-session/session-launch-common.sh"
fi

export TMPDIR="${TMPDIR:-/var/tmp/podman-tmp}"; mkdir -p "$TMPDIR"
set +e
bash "$ROOT/omedora/test/fedora/headless/run-tests.sh" "$@" 2>&1 | tee "$RESULTS/nested-$stamp.log"
rc=${PIPESTATUS[0]}
set -e
cp -r "$ROOT/omedora/test/fedora/headless/artifacts" "$RESULTS/nested-$stamp-artifacts" 2>/dev/null || true
echo "L4-nested exit=$rc — log: $RESULTS/nested-$stamp.log"
exit "$rc"
