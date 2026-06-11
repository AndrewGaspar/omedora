#!/bin/bash
#
# L4-VM btrfs snapshot/rollback test — host orchestrator.
#
# Validates bin/omedora-snapshot (create/list/delete/rollback) against a REAL
# btrfs root on a real libvirt/KVM VM. This is the ONE tier that can: rootless
# podman has no loop-device access, so btrfs can't be exercised in a container —
# the unit test (test/snapshot-test.sh) mocks `btrfs`/`findmnt` and runs the
# command LOGIC against a plain dir, but never the actual subvolume surgery. Here
# the surgery runs for real, on a rebooted system.
#
# It reuses the L4-VM harness's plumbing exactly (run-vm-test.sh):
#   * rootless qemu:///session  (NO host sudo)
#   * passt user-mode networking with a hostfwd  (host 127.0.0.1:$SSH_PORT -> 22)
#   * the cached Fedora 44 Cloud Base qcow2 + cloud-init NoCloud cidata ISO
#     (built with xorriso) under /var/tmp/omedora-vmtest/
#
# KEY FACT (verified, see README): the Fedora 44 Cloud Base image is ALREADY
# btrfs-root — top-level subvols root/boot/home/var, fstab pinning subvol=root —
# the EXACT layout omedora-snapshot expects. So we test against the VM's real /,
# no second disk needed. (`require_btrfs` would exit 127 otherwise.)
#
# Flow (split across a reboot, the part a container can't do):
#   provision : overlay + cidata + virt-install + wait for SSH  (no Workstation
#               groupinstall — this tier doesn't need a desktop, just btrfs/)
#   prepare   : in-VM, as root: `create preinstall`, write /PROOF-marker (+ a
#               /home marker), `rollback <name> --apply` (auto-confirm). Asserts
#               the snapshot, the listing, and the pre-reboot subvol swap.
#   reboot    : the VM reboots onto the restored `root` subvolume.
#   assert    : in-VM, as root: /PROOF-marker is GONE, /home marker SURVIVED,
#               root.broken-<ts> exists and still holds the marker (reversible).
#
# Everything is named omedora-snaptest-* and self-cleaning (virsh destroy/undefine
# + rm the overlay/seed). The user's existing VMs and the omedora-vmtest-* pipeline
# resources are NEVER touched. Disk images live under /var/tmp (home has a quota).
#
# Usage:
#   run-snapshot-vm-test.sh                 # full run
#   run-snapshot-vm-test.sh --keep          # leave the VM up for inspection
#   run-snapshot-vm-test.sh --cleanup       # destroy+undefine any omedora-snaptest-* and exit
#
# Host requirements: virt-install, virsh, qemu-img, xorriso, ssh, openssl,
# /dev/kvm, passt. None need sudo for qemu:///session.

set -uo pipefail

# ---------------------------------------------------------------------------
# paths + constants  (mirror run-vm-test.sh)
# ---------------------------------------------------------------------------
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd -- "$HERE/../../../.." && pwd)

export TMPDIR="${TMPDIR:-/var/tmp/podman-tmp}"; mkdir -p "$TMPDIR"
export LIBVIRT_DEFAULT_URI="qemu:///session"
URI="qemu:///session"

# Reuse the L4-VM work tree + cached image (do NOT re-download).
WORK="${OMEDORA_VM_WORK:-/var/tmp/omedora-vmtest}"
IMAGES="$WORK/images"
RUN="$WORK/run"
mkdir -p "$IMAGES" "$RUN"

BASE_IMG_NAME="Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2"
BASE_IMG="$IMAGES/$BASE_IMG_NAME"
BASE_IMG_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/$BASE_IMG_NAME"

VM="${OMEDORA_SNAPTEST_VM_NAME:-omedora-snaptest}"   # libvirt domain (omedora-snaptest-*)
VM_USER="${OMEDORA_VM_USER:-omedora}"
VM_RAM_MB="${OMEDORA_SNAPTEST_RAM_MB:-2048}"
VM_VCPUS="${OMEDORA_SNAPTEST_VCPUS:-2}"
VM_DISK_GB="${OMEDORA_SNAPTEST_DISK_GB:-8}"
SSH_PORT="${OMEDORA_SNAPTEST_SSH_PORT:-2298}"        # distinct from run-vm-test.sh's 2222
SSH_KEY="$RUN/id_omedora_snaptest"
OVERLAY="$IMAGES/${VM}-overlay.qcow2"
SEED_ISO="$IMAGES/${VM}-seed.iso"

log()  { printf '\033[1;36m[snaptest]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[snaptest]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[snaptest]\033[0m %s\n' "$*" >&2; exit 1; }

vmssh() {
  ssh -p "$SSH_PORT" \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR -o ConnectTimeout=10 \
      -i "$SSH_KEY" "$VM_USER@127.0.0.1" "$@"
}
vmscp() {
  scp -P "$SSH_PORT" \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR -o ConnectTimeout=10 \
      -i "$SSH_KEY" "$@"
}

# ---------------------------------------------------------------------------
# args
# ---------------------------------------------------------------------------
keep=false; cleanup_only=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep)    keep=true ;;
    --cleanup) cleanup_only=true ;;
    --help|-h) grep '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# cleanup  (only ever touch omedora-snaptest-*)
# ---------------------------------------------------------------------------
destroy_vm() {
  virsh -c "$URI" destroy  "$VM"         >/dev/null 2>&1 || true
  virsh -c "$URI" undefine "$VM" --nvram >/dev/null 2>&1 || true
}
cleanup_disks() { rm -f "$OVERLAY" "$SEED_ISO"; }

full_cleanup() {
  for d in $(virsh -c "$URI" list --all --name 2>/dev/null | grep '^omedora-snaptest'); do
    log "destroying $d"
    virsh -c "$URI" destroy  "$d"         >/dev/null 2>&1 || true
    virsh -c "$URI" undefine "$d" --nvram >/dev/null 2>&1 || true
  done
  rm -f "$IMAGES"/omedora-snaptest*-overlay.qcow2 "$IMAGES"/omedora-snaptest*-seed.iso
  log "cleanup done"
}

if $cleanup_only; then full_cleanup; exit 0; fi

trap '[[ $keep == true ]] && warn "VM $VM left running (--keep): ssh -p $SSH_PORT -i $SSH_KEY $VM_USER@127.0.0.1" || { log "tearing down $VM"; destroy_vm; cleanup_disks; }' EXIT

# ---------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------
preflight() {
  for t in virt-install virsh qemu-img xorriso ssh openssl; do
    command -v "$t" >/dev/null || die "missing host tool: $t"
  done
  [[ -e /dev/kvm ]] || die "/dev/kvm not present — KVM acceleration required"
  command -v passt >/dev/null || warn "passt not found — qemu:///session user networking may fail"

  if [[ ! -f "$BASE_IMG" ]]; then
    log "base image not cached; downloading Fedora 44 Cloud Base (~560MB)..."
    curl -fSL -o "$BASE_IMG.part" "$BASE_IMG_URL" || die "base image download failed"
    mv "$BASE_IMG.part" "$BASE_IMG"
  fi
  log "base image: $BASE_IMG"

  if [[ ! -f "$SSH_KEY" ]]; then
    log "generating throwaway ssh keypair"
    ssh-keygen -t ed25519 -N '' -f "$SSH_KEY" -C omedora-snaptest >/dev/null
  fi
}

# ---------------------------------------------------------------------------
# provision — overlay + minimal cidata + virt-install + wait for SSH
# ---------------------------------------------------------------------------
build_seed_iso() {
  local seeddir; seeddir=$(mktemp -d "$RUN/snaptest-seed.XXXXXX")
  local pubkey; pubkey=$(cat "$SSH_KEY.pub")
  cat >"$seeddir/meta-data" <<EOF
instance-id: iid-$VM-$(date +%s)
local-hostname: $VM
EOF
  # No Workstation groupinstall here: this tier only needs a btrfs root + sshd.
  # growpart so the overlay's extra space lands on the btrfs root (snapshots need
  # headroom for the writable staged copy).
  cat >"$seeddir/user-data" <<EOF
#cloud-config
hostname: $VM
fqdn: $VM.omedora-snaptest.local
users:
  - name: $VM_USER
    groups: [wheel]
    sudo: "ALL=(ALL) NOPASSWD:ALL"
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys:
      - $pubkey
ssh_pwauth: false
growpart:
  mode: auto
  devices: ["/"]
resize_rootfs: true
EOF
  xorriso -as mkisofs -output "$SEED_ISO" -volid cidata -joliet -rock \
      "$seeddir/user-data" "$seeddir/meta-data" >/dev/null 2>&1 \
    || die "xorriso failed to build the cidata seed ISO"
  rm -rf "$seeddir"
  log "cidata seed ISO: $SEED_ISO"
}

provision() {
  destroy_vm
  cleanup_disks

  log "creating ${VM_DISK_GB}G overlay disk on the cached base image"
  qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMG" "$OVERLAY" "${VM_DISK_GB}G" >/dev/null \
    || die "overlay create failed"

  build_seed_iso

  local netopt="type=user,backend.type=passt,portForward0.proto=tcp,portForward0.address=127.0.0.1,portForward0.range0.start=$SSH_PORT,portForward0.range0.to=22"

  log "virt-install $VM (rootless qemu:///session, passt NAT, hostfwd $SSH_PORT->22, headless)"
  virt-install \
    --connect "$URI" \
    --name "$VM" \
    --memory "$VM_RAM_MB" \
    --vcpus "$VM_VCPUS" \
    --cpu host-passthrough \
    --machine q35 \
    --import \
    --disk "path=$OVERLAY,format=qcow2,bus=virtio" \
    --disk "path=$SEED_ISO,device=cdrom" \
    --os-variant fedora-unknown \
    --network "$netopt" \
    --graphics none \
    --noautoconsole \
    || die "virt-install failed"

  local i
  log "waiting for SSH on 127.0.0.1:$SSH_PORT ..."
  for i in $(seq 1 40); do
    vmssh true 2>/dev/null && { log "SSH up"; return 0; }
    [[ $i -eq 40 ]] && die "SSH never came up"
    sleep 6
  done
}

# ---------------------------------------------------------------------------
# wait for SSH to recover (after a guest reboot)
# ---------------------------------------------------------------------------
wait_ssh() {
  local i
  for i in $(seq 1 40); do
    vmssh true 2>/dev/null && return 0
    sleep 5
  done
  return 1
}

# ---------------------------------------------------------------------------
# install the tool under test into the VM
# ---------------------------------------------------------------------------
install_tool() {
  log "shipping bin/omedora-snapshot (THIS checkout) into the VM"
  vmscp "$REPO/bin/omedora-snapshot" "$VM_USER@127.0.0.1:/tmp/omedora-snapshot" || die "scp tool failed"
  vmssh 'sudo install -m 0755 /tmp/omedora-snapshot /usr/local/bin/omedora-snapshot' || die "install tool failed"
}

# ---------------------------------------------------------------------------
# prepare (pre-reboot) + assert (post-reboot)
# ---------------------------------------------------------------------------
prepare() {
  log "in-VM: create snapshot + write markers + rollback --apply (pre-reboot)"
  vmscp "$HERE/in-vm/snapshot-prepare.sh" "$VM_USER@127.0.0.1:/tmp/snapshot-prepare.sh" || die "scp prepare failed"
  vmssh 'sudo bash /tmp/snapshot-prepare.sh'
}

reboot_vm() {
  log "rebooting the VM onto the restored root subvolume"
  vmssh 'sudo systemctl reboot' 2>/dev/null || true
  sleep 12
  wait_ssh || die "SSH never recovered after the rollback reboot"
  log "VM back up after reboot"
}

assert() {
  log "in-VM: post-reboot rollback assertions"
  vmscp "$HERE/in-vm/snapshot-assert.sh" "$VM_USER@127.0.0.1:/tmp/snapshot-assert.sh" || die "scp assert failed"
  vmssh 'sudo bash /tmp/snapshot-assert.sh'
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------
main() {
  preflight

  log "=== STAGE: provision ==="
  provision

  log "=== STAGE: install tool ==="
  install_tool

  log "=== STAGE: prepare (create + marker + rollback --apply) ==="
  set +e
  prepare; local prep_rc=$?
  set +o errexit 2>/dev/null || true

  if [[ $prep_rc -ne 0 ]]; then
    warn "prepare stage failed (rc=$prep_rc) — NOT rebooting (nothing safe to assert)"
  else
    log "=== STAGE: reboot ==="
    reboot_vm
  fi

  log "=== STAGE: assert (post-reboot) ==="
  local assert_rc=1
  if [[ $prep_rc -eq 0 ]]; then
    set +e
    assert; assert_rc=$?
    set +o errexit 2>/dev/null || true
  else
    warn "skipping post-reboot assertions because prepare failed"
  fi

  echo
  log "================= L4-VM SNAPSHOT SUMMARY ================="
  log "prepare (create+marker+rollback) ... $prep_rc"
  log "assert  (post-reboot rollback)   ... $assert_rc"
  log "========================================================="
  (( prep_rc == 0 && assert_rc == 0 ))
}

main
