#!/bin/bash
# hypedora: verifică dacă ACEST host (laptopul Fedora) poate rula tier-ele L4
# (podman nested + VM KVM rootless cu GL). Transformă presupunerile din design
# (secțiunea 6) în fapte verificate. exit 0 = ok; exit 1 = lipsuri listate.
set -uo pipefail

DEV="${HYPEDORA_DEV_ROOT:-/dev}"
WORK="${HYPEDORA_WORK:-/var/tmp}"
MIN_FREE_GB="${HYPEDORA_MIN_FREE_GB:-40}"
MIN_RAM_KB=$((8 * 1000 * 1000))

missing=()
note() { printf '  [ok] %s\n' "$*"; }
miss() { printf '  [LIPSĂ] %s\n' "$*" >&2; missing+=("$1"); }

echo "hypedora preflight-host"
for t in virt-install virsh qemu-system-x86_64 qemu-img xorriso ssh openssl passt podman; do
  if command -v "$t" >/dev/null 2>&1; then note "$t"; else miss "$t"; fi
done

if [[ -e "$DEV/kvm" ]]; then note "$DEV/kvm"; else miss "/dev/kvm (KVM activ în BIOS? modul kvm_intel/kvm_amd?)"; fi
if ls "$DEV"/dri/renderD* >/dev/null 2>&1; then note "render node: $(ls "$DEV"/dri/renderD* | head -1)"; else miss "/dev/dri/renderD* (GPU + mesa)"; fi

free_gb=$(df -BG --output=avail "$WORK" 2>/dev/null | tail -1 | tr -dc 0-9)
[[ -z "$free_gb" ]] && free_gb=$(df -BG "$WORK" 2>/dev/null | awk 'NR==2{gsub("G","",$4); print $4}')
if [[ -n "$free_gb" && "$free_gb" -ge "$MIN_FREE_GB" ]]; then note "spațiu liber în $WORK: ${free_gb}G (≥ ${MIN_FREE_GB}G)"; else miss "spațiu liber în $WORK: ${free_gb:-?}G (< ${MIN_FREE_GB}G)"; fi

ram_kb=$(free 2>/dev/null | awk '/^Mem:/{print $2}')
if [[ -n "$ram_kb" && "$ram_kb" -ge "$MIN_RAM_KB" ]]; then note "RAM: $((ram_kb/1000/1000)) GB"; else miss "RAM ≥ 8 GB (găsit: ${ram_kb:-?} kB)"; fi

if (( ${#missing[@]} )); then
  echo
  echo "Lipsesc: ${missing[*]}" >&2
  echo "Remediere tipică (Fedora 44):" >&2
  echo "  sudo dnf install -y virt-install libvirt-daemon-kvm qemu-kvm qemu-img xorriso passt podman openssl openssh-clients" >&2
  echo "  sudo systemctl enable --now libvirtd   # pentru qemu:///session nu e strict necesar, dar e inofensiv" >&2
  exit 1
fi
echo "host OK pentru L4 nested + L4 VM"
