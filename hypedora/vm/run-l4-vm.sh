#!/bin/bash
# hypedora: rulează tier-ul L4-VM al omedora CU accelerare 3D (egl-headless + virtio
# accel3d) la 1920x1080, ca goldens vizuale să dea pass/fail real. Argumentele merg
# nemodificate la omedora/test/fedora/vm/run-vm-test.sh (--provision-only, --keep,
# --fast, --stage, --cleanup). HYPEDORA_DRY_RUN=1 afișează mediul și iese.
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
RESULTS="${HYPEDORA_RESULTS:-/var/tmp/hypedora-results}"
DEV="${HYPEDORA_DEV_ROOT:-/dev}"
RENDER="${HYPEDORA_RENDER_NODE:-$(ls "$DEV"/dri/renderD* 2>/dev/null | head -1)}"
[[ -n "$RENDER" ]] || { echo "niciun render node în $DEV/dri — fără GL nu rulăm" >&2; exit 1; }

# Rezoluția intră prin <video><model><resolution> (libvirt nativ, injectat cu
# xpath.set — virt-install 5.1 nu are model.resolution.*). Lever-ul upstream
# OMEDORA_VM_RES (qemu -set device.video0.xres) e RUPT pe libvirt 12: -device e
# pasat ca JSON și -set nu-l mai vede → îl dezactivăm explicit cu string gol.
RES="${HYPEDORA_VM_RES:-1920x1080}"
XRES="${RES%x*}" YRES="${RES#*x}"

export OMEDORA_VM_GRAPHICS="egl-headless,rendernode=$RENDER"
export OMEDORA_VM_VIDEO="model.type=virtio,model.acceleration.accel3d=yes,xpath0.set=./model/resolution/@x=$XRES,xpath1.set=./model/resolution/@y=$YRES"
export OMEDORA_VM_RES=""
export OMEDORA_VM_GEOMETRY_SKIP="${OMEDORA_VM_GEOMETRY_SKIP:-0}"
export OMEDORA_VM_RAM_MB="${OMEDORA_VM_RAM_MB:-6144}"
export OMEDORA_VM_VCPUS="${OMEDORA_VM_VCPUS:-4}"

echo "hypedora L4-VM env:"
echo "  HYPEDORA_VM_RES=$RES"
for v in OMEDORA_VM_GRAPHICS OMEDORA_VM_VIDEO OMEDORA_VM_RES OMEDORA_VM_GEOMETRY_SKIP OMEDORA_VM_RAM_MB OMEDORA_VM_VCPUS; do
  printf '  %s=%s\n' "$v" "${!v}"
done
echo "  cmd: omedora/test/fedora/vm/run-vm-test.sh $*"
[[ "${HYPEDORA_DRY_RUN:-0}" == "1" ]] && exit 0

[[ "${HYPEDORA_SKIP_PREFLIGHT:-0}" == "1" ]] || bash "$ROOT/hypedora/vm/preflight-host.sh"
stamp=$(date +%Y%m%d-%H%M%S); out="$RESULTS/vm-$stamp"; mkdir -p "$out"
set +e
bash "$ROOT/omedora/test/fedora/vm/run-vm-test.sh" "$@" 2>&1 | tee "$out/run.log"
rc=${PIPESTATUS[0]}
set -e
cp -r "$ROOT/omedora/test/fedora/vm/artifacts/." "$out/" 2>/dev/null || true
echo "L4-VM exit=$rc — artefacte: $out"
exit "$rc"
