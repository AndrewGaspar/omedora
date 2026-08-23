#!/bin/bash
#
# L4-VM automated test pipeline — host orchestrator.
#
# The highest-fidelity Omedora test tier: provisions a REAL Fedora Workstation
# (GNOME + GDM) virtual machine under libvirt+KVM, installs Omedora the way a
# user would (boot.sh -> COPR -> install.sh), boots the Omedora/Hyprland session
# from a real GDM seat (real DRM master, real systemd --user, real session bus),
# and runs the SAME TAP assertion suite the L4-headless podman tier runs
# (omedora/test/fedora/headless/{lib,tests}) — plus a real-framebuffer
# screenshot via `virsh screenshot` that no container can produce.
#
# This is what closes #86: the launch-gate item only ever proven in podman.
#
# DESIGN (see omedora/test/fedora/vm/README.md for the full rationale):
#   * Provisioning  : Fedora 44 Cloud Base qcow2 + cloud-init (NoCloud cidata
#                     ISO built with xorriso). cloud-init lays the real
#                     Workstation comps group on top -> faithful coexistence
#                     base. Fully unattended/scriptable.
#   * Hypervisor    : qemu:///session (ROOTLESS — no host sudo) with passt
#                     user-mode networking (NAT to the host, no bridge/root).
#   * Session check : GDM autologin into omedora.desktop, then reuse
#                     headless/lib.sh + tests/*.sh over the real user session via
#                     XDG_RUNTIME_DIR (session-attach), AND a virsh screenshot of
#                     the live framebuffer as a coarse "it rendered" artifact.
#
# Everything is named omedora-vmtest-* and self-cleaning (virsh destroy/undefine
# + rm the overlay disk). The user's existing VMs/networks/pools are never
# touched. TMPDIR/disk images live under /var/tmp (host /tmp has a tiny quota).
#
# Usage:
#   omedora/test/fedora/vm/run-vm-test.sh                 # full run (provision+install+session+tests)
#   omedora/test/fedora/vm/run-vm-test.sh --fast          # skip flatpaks/webapps (OMEDORA_VM_FAST) — faster install
#   omedora/test/fedora/vm/run-vm-test.sh --keep          # leave the VM running for inspection
#   omedora/test/fedora/vm/run-vm-test.sh --provision-only # stop after a booted Workstation+SSH (no install)
#   omedora/test/fedora/vm/run-vm-test.sh --stage <name>  # resume at a stage (provision|install|session|tests)
#   omedora/test/fedora/vm/run-vm-test.sh --ref <gitref>  # OMEDORA_REF channel/branch/tag (default: this branch)
#   omedora/test/fedora/vm/run-vm-test.sh --cleanup       # destroy+undefine any omedora-vmtest-* and exit
#
# Requirements (host): virt-install, virsh, qemu-system-x86_64, xorriso, qemu-img,
#   ssh, /dev/kvm, passt. All present on the Arch dev host; none need sudo for
#   qemu:///session. See README.md "Host privilege" for the one bridged-network
#   alternative that would.

set -uo pipefail

# ---------------------------------------------------------------------------
# paths + constants
# ---------------------------------------------------------------------------
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd -- "$HERE/../../../.." && pwd)
HEADLESS_DIR="$REPO/omedora/test/fedora/headless"

export LIBVIRT_DEFAULT_URI="qemu:///session"
URI="qemu:///session"

# Disk-heavy work goes under /var/tmp (host /tmp is a tiny tmpfs quota).
WORK="${OMEDORA_VM_WORK:-/var/tmp/omedora-vmtest}"
IMAGES="$WORK/images"
RUN="$WORK/run"
mkdir -p "$IMAGES" "$RUN"

BASE_IMG_NAME="Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2"
BASE_IMG="$IMAGES/$BASE_IMG_NAME"
BASE_IMG_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/$BASE_IMG_NAME"

VM="${OMEDORA_VM_NAME:-omedora-vmtest}"        # libvirt domain name (omedora-vmtest-*)
VM_USER="${OMEDORA_VM_USER:-omedora}"
VM_RAM_MB="${OMEDORA_VM_RAM_MB:-4096}"
VM_VCPUS="${OMEDORA_VM_VCPUS:-4}"
VM_DISK_GB="${OMEDORA_VM_DISK_GB:-24}"
SSH_PORT="${OMEDORA_VM_SSH_PORT:-2222}"        # host-forwarded port (passt) -> VM:22
VM_GRAPHICS="${OMEDORA_VM_GRAPHICS:-vnc,listen=127.0.0.1}"   # ex.: egl-headless,rendernode=/dev/dri/renderD128
VM_VIDEO="${OMEDORA_VM_VIDEO:-virtio}"                        # ex.: model.type=virtio,model.acceleration.accel3d=yes
VM_GEOMETRY_SKIP="${OMEDORA_VM_GEOMETRY_SKIP:-1}"             # 0 când OMEDORA_VM_RES=1920x1080 (goldens reale)
SSH_KEY="$RUN/id_omedora_vmtest"
OVERLAY="$IMAGES/${VM}-overlay.qcow2"
SEED_ISO="$IMAGES/${VM}-seed.iso"
ARTIFACTS="$HERE/artifacts"

# OMEDORA_REF channel/branch/tag the in-VM install uses. Default: the branch this
# checkout is on, so a dev iterating on a branch tests THAT code.
DEFAULT_REF=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null || echo stable)

log()  { printf '\033[1;35m[vmtest]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[vmtest]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[vmtest]\033[0m %s\n' "$*" >&2; exit 1; }

# ssh into the VM (passt-forwarded localhost:$SSH_PORT). Quiet, no host-key churn.
vmssh() {
  ssh -p "$SSH_PORT" \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -o LogLevel=ERROR -o ConnectTimeout=10 \
      -i "$SSH_KEY" "$VM_USER@127.0.0.1" "$@"
}
# Like vmssh but allocates a PTY (-tt). install.sh's presentation.sh reads the
# terminal via `stty size </dev/tty`, and under `set -eEo pipefail` that
# command-substitution returns non-zero on a TTY-less SSH login and aborts the
# whole install with NO output. A real install and the podman tier's
# `machinectl shell` both run with a PTY; -tt gives the install the same. (-tt
# merges stderr into the PTY stream; fine here — we tee everything anyway.)
vmssh_tty() {
  ssh -tt -p "$SSH_PORT" \
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
keep=false; fast=false; provision_only=false; cleanup_only=false
stage_from="provision"; ref="$DEFAULT_REF"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep)            keep=true ;;
    --fast)            fast=true ;;
    --provision-only)  provision_only=true ;;
    --stage)           shift; stage_from="${1:?--stage needs a name}" ;;
    --ref)             shift; ref="${1:?--ref needs a value}" ;;
    --cleanup)         cleanup_only=true ;;
    --help|-h) grep '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# cleanup
# ---------------------------------------------------------------------------
destroy_vm() {
  virsh -c "$URI" destroy  "$VM"            >/dev/null 2>&1 || true
  virsh -c "$URI" undefine "$VM" --nvram    >/dev/null 2>&1 || true
}
cleanup_disks() { rm -f "$OVERLAY" "$SEED_ISO"; }

full_cleanup() {
  # Only ever touch omedora-vmtest-* — never the user's VMs.
  for d in $(virsh -c "$URI" list --all --name 2>/dev/null | grep '^omedora-vmtest'); do
    log "destroying $d"
    virsh -c "$URI" destroy  "$d"         >/dev/null 2>&1 || true
    virsh -c "$URI" undefine "$d" --nvram >/dev/null 2>&1 || true
  done
  rm -f "$IMAGES"/omedora-vmtest*-overlay.qcow2 "$IMAGES"/omedora-vmtest*-seed.iso
  log "cleanup done"
}

if $cleanup_only; then full_cleanup; exit 0; fi

trap '[[ $keep == true ]] && warn "VM $VM left running (--keep): ssh -p $SSH_PORT -i $SSH_KEY $VM_USER@127.0.0.1" || { log "tearing down $VM"; destroy_vm; cleanup_disks; }' EXIT

# ---------------------------------------------------------------------------
# preflight: tools + base image + keypair
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
  log "base image: $(qemu-img info "$BASE_IMG" 2>/dev/null | grep 'virtual size' | sed 's/^/  /')"

  if [[ ! -f "$SSH_KEY" ]]; then
    log "generating throwaway ssh keypair"
    ssh-keygen -t ed25519 -N '' -f "$SSH_KEY" -C omedora-vmtest >/dev/null
  fi
}

# ---------------------------------------------------------------------------
# stage: provision — overlay disk + cidata ISO + virt-install + wait for SSH
# ---------------------------------------------------------------------------
build_seed_iso() {
  local seeddir; seeddir=$(mktemp -d "$RUN/seed.XXXXXX")
  local pubkey passwd_hash instance_id
  pubkey=$(cat "$SSH_KEY.pub")
  passwd_hash=$(openssl passwd -6 omedora 2>/dev/null || echo '!')
  instance_id="iid-$VM-$(date +%s)"

  sed -e "s|@@SSH_PUBKEY@@|$pubkey|" \
      -e "s|@@VM_USER@@|$VM_USER|g" \
      -e "s|@@HOSTNAME@@|$VM|g" \
      -e "s|@@PASSWD_HASH@@|$passwd_hash|" \
      "$HERE/cloud-init/user-data" > "$seeddir/user-data"
  sed -e "s|@@INSTANCE_ID@@|$instance_id|" \
      -e "s|@@HOSTNAME@@|$VM|g" \
      "$HERE/cloud-init/meta-data" > "$seeddir/meta-data"

  # NoCloud needs a filesystem labelled "cidata" holding user-data + meta-data.
  # cloud-localds/genisoimage are absent here; xorriso builds the same ISO.
  xorriso -as mkisofs -output "$SEED_ISO" -volid cidata -joliet -rock \
      "$seeddir/user-data" "$seeddir/meta-data" >/dev/null 2>&1 \
    || die "xorriso failed to build the cidata seed ISO"
  rm -rf "$seeddir"
  log "cidata seed ISO: $SEED_ISO"
}

provision() {
  destroy_vm                       # in case a stale same-name VM exists (ours)
  cleanup_disks
  rm -rf "$IMAGES/${VM}-meta" 2>/dev/null || true

  # Overlay (copy-on-write) disk on top of the pristine base, grown to VM_DISK_GB.
  log "creating ${VM_DISK_GB}G overlay disk on the base image"
  qemu-img create -f qcow2 -F qcow2 -b "$BASE_IMG" "$OVERLAY" "${VM_DISK_GB}G" >/dev/null \
    || die "overlay create failed"

  build_seed_iso

  # passt user networking with a hostfwd: host 127.0.0.1:$SSH_PORT -> VM:22.
  # type=user + backend.type=passt is the rootless, sudo-free NAT path on
  # libvirt 12.x; portForward maps the SSH port back to the host so the
  # orchestrator can drive the VM without a bridge or root. (Verified the XML
  # this produces: <interface type=user><backend type=passt><portForward ...>.)
  local netopt="type=user,backend.type=passt,portForward0.proto=tcp,portForward0.address=127.0.0.1,portForward0.range0.start=$SSH_PORT,portForward0.range0.to=22"

  # OMEDORA_VM_RES (OPT-IN; empty by default): pin the virtio-gpu's advertised
  # mode so the session renders at the SAME geometry as the committed visual
  # goldens (30/40/50), letting those pixel-diffs run instead of skipping on a
  # geometry mismatch. Off by default because the QEMU `-set device.<alias>.xres`
  # lever needs the EXACT device alias libvirt assigned (it is NOT a stable
  # "video0" — a wrong alias makes QEMU refuse to boot), which varies by
  # libvirt/QEMU version. When unset, the guest picks its own mode (1280x800
  # here) and SCREENSHOT_GEOMETRY_SKIP turns the golden diffs into SKIPs — the
  # verified-working path. To use it, find the alias in `virsh dumpxml <vm>`
  # (the <video> <alias name='…'/>) and pass e.g.
  #   OMEDORA_VM_RES=1920x1080 OMEDORA_VM_RES_ALIAS=video0 ...
  local res="${OMEDORA_VM_RES:-}"
  local res_alias="${OMEDORA_VM_RES_ALIAS:-video0}"
  local qemu_cmdline_args=()
  if [[ -n "$res" ]]; then
    local xres="${res%x*}" yres="${res#*x}"
    qemu_cmdline_args=(--qemu-commandline="-set device.${res_alias}.xres=$xres -set device.${res_alias}.yres=$yres")
  fi

  log "virt-install $VM (rootless qemu:///session, passt NAT, hostfwd $SSH_PORT->22${res:+, ${res} display})"
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
    --graphics "$VM_GRAPHICS" \
    --video "$VM_VIDEO" \
    "${qemu_cmdline_args[@]}" \
    --noautoconsole \
    || die "virt-install failed"

  # Wait for SSH, then for cloud-init to finish its heavy runcmd (the Workstation
  # comps groupinstall). No guest-reboot dance: cloud-init does NOT power_state
  # here, so the domain just keeps running; the graphical (GDM) seat is brought
  # up later by the session stage (select-session.sh isolates graphical.target +
  # restarts gdm). Polling `cloud-init status` over SSH is race-free, unlike
  # watching domstate for a transient power-off.
  local i
  log "waiting for SSH on 127.0.0.1:$SSH_PORT ..."
  for i in $(seq 1 60); do
    vmssh true 2>/dev/null && { log "SSH up"; break; }
    [[ $i -eq 60 ]] && die "SSH never came up (see VNC: virsh -c $URI domdisplay $VM)"
    sleep 10
  done

  log "waiting for cloud-init to finish (Workstation groupinstall, ~6-12min)..."
  # Run `cloud-init status` via sudo: as the unprivileged user it can hit a
  # PermissionError on /run/cloud-init/cloud.cfg mid-run (a CLI quirk, not a
  # provisioning failure), which would make the poll see no status. The user has
  # passwordless sudo.
  for i in $(seq 1 120); do
    local st; st=$(vmssh 'sudo cloud-init status 2>/dev/null' 2>/dev/null | awk -F': ' '/status/{print $2}')
    case "$st" in
      done)  log "cloud-init done"; return 0 ;;
      error) warn "cloud-init reported error; provisioning may be incomplete:"
             vmssh 'sudo cloud-init status --long 2>/dev/null' 2>/dev/null | sed 's/^/  /' >&2 || true
             return 0 ;;  # continue — partial base is often still installable
    esac
    # Fallback signal: gnome-shell present + dnf idle => the Workstation
    # groupinstall finished even if `cloud-init status` is momentarily unhappy.
    if [[ -z "$st" ]] && vmssh 'rpm -q gnome-shell >/dev/null 2>&1 && ! pgrep -x dnf5 >/dev/null && ! pgrep -x dnf >/dev/null' 2>/dev/null; then
      log "cloud-init status unavailable but gnome-shell installed + dnf idle — treating provisioning as complete"
      return 0
    fi
    [[ $i -eq 120 ]] && { warn "cloud-init did not reach done within ~20min; continuing"; return 0; }
    sleep 10
  done
}

# ---------------------------------------------------------------------------
# stage: install — run the Omedora bootstrap the user way (boot.sh -> omedora/install-4.sh)
# ---------------------------------------------------------------------------
do_install() {
  log "syncing this omedora checkout into the VM (so the in-VM install uses THIS code, not just a remote clone)"
  # Pack the working tree (tracked files) and unpack at the path
  # omedora/install-4.sh hardcodes (~/.local/share/omarchy). This makes the VM
  # test THIS branch.
  local tar="$RUN/omedora-src.tar.gz"
  git -C "$REPO" archive --format=tar.gz -o "$tar" HEAD || die "git archive failed"
  vmssh 'rm -rf ~/.local/share/omarchy && mkdir -p ~/.local/share/omarchy' || die "prep dest failed"
  vmscp "$tar" "$VM_USER@127.0.0.1:/tmp/omedora-src.tar.gz" || die "scp src failed"
  vmssh 'tar -xzf /tmp/omedora-src.tar.gz -C ~/.local/share/omarchy' || die "untar src failed"

  local fastenv=""
  $fast && fastenv="OMEDORA_VM_FAST=1"

  log "running omedora/install-4.sh in the VM (NONINTERACTIVE; ref=$ref; fast=$fast)"
  # OMARCHY_NONINTERACTIVE: drive the fedora-plan coexistence gate's
  # non-interactive branch (it warns + proceeds; backup-then-write is
  # non-destructive). This is the unattended path. The interactive/expect path
  # is exercised separately by run-vm-test.sh's --stage install with a PTY (TODO,
  # see README "Interactive path").
  # -tt PTY: omedora/install-4.sh aborts silently without a terminal (see vmssh_tty). The
  # in-VM `tee` keeps the full transcript at /tmp/omedora-install.out so the rc
  # we read is the install's, not ssh's PTY-forwarding rc.
  set +e
  vmssh_tty "set -o pipefail; \
    export OMARCHY_NONINTERACTIVE=1 OMEDORA_PLAN_AUTOCONFIRM=1 OMEDORA_REF='$ref' $fastenv; \
    bash ~/.local/share/omarchy/omedora/install-4.sh 2>&1 | tee /tmp/omedora-install.out; \
    echo \"INSTALL_RC=\${PIPESTATUS[0]}\" | tee /tmp/omedora-install.rc"
  local rc=$?
  # Prefer the in-VM sentinel rc over ssh's (ssh -tt rc can reflect the PTY).
  local vm_rc; vm_rc=$(vmssh 'sed -n "s/^INSTALL_RC=//p" /tmp/omedora-install.rc 2>/dev/null' 2>/dev/null | tr -dc 0-9)
  [[ -n "$vm_rc" ]] && rc="$vm_rc"
  # NOTE: do not re-enable errexit here — this script runs without `set -e`
  # on purpose (stages capture $? and continue); a stray `set -e` would abort
  # the whole run on the first non-zero stage rc (e.g. a failing assert).
  set +o errexit 2>/dev/null || true
  log "omedora/install-4.sh exit: $rc"
  return $rc
}

# ---------------------------------------------------------------------------
# stage: assert-install — packages from COPR, session entry, config backups
# ---------------------------------------------------------------------------
assert_install() {
  log "asserting the install landed (run in-VM)"
  vmscp "$HERE/in-vm/assert-install.sh" "$VM_USER@127.0.0.1:/tmp/assert-install.sh" || die "scp assert failed"
  vmssh 'bash /tmp/assert-install.sh'
}

# ---------------------------------------------------------------------------
# stage: session — pick omedora.desktop as the seat session, bring up GDM, attach
# ---------------------------------------------------------------------------
start_session() {
  log "selecting omedora.desktop as the autologin session + (re)starting the graphical seat"
  vmscp "$HERE/in-vm/select-session.sh" "$VM_USER@127.0.0.1:/tmp/select-session.sh" || die "scp select failed"
  vmssh 'bash /tmp/select-session.sh' || warn "select-session reported issues (continuing)"

  # select-session.sh reboots the VM (so GDM autologins into the omedora session
  # on a fresh seat). SSH drops during the reboot; wait for it to come back, then
  # poll for the Hyprland IPC socket. The SSH login IS the omedora user (uid
  # 1000), so /run/user/1000/hypr is directly readable — no runuser (which is
  # root-only and was failing).
  local i
  log "waiting for SSH to recover after the session reboot..."
  for i in $(seq 1 30); do
    vmssh true 2>/dev/null && break
    sleep 5
  done

  log "waiting for the Omedora/Hyprland session to come up on the real seat..."
  local up=false
  for i in $(seq 1 40); do
    if vmssh 'ls /run/user/1000/hypr 2>/dev/null | grep -q .' 2>/dev/null; then
      up=true; break
    fi
    sleep 5
  done
  if $up; then
    log "Hyprland IPC socket present under /run/user/1000/hypr"
  else
    warn "no Hyprland instance under /run/user/1000/hypr after ~3min — capturing diagnostics"
    vmssh 'loginctl list-sessions --no-legend; echo "--- failed user units ---"; systemctl --user list-units --failed --no-legend 2>/dev/null; echo "--- uwsm log ---"; tail -30 /run/user/1000/uwsm-start.log 2>/dev/null' 2>/dev/null | sed 's/^/  /' >&2 || true
  fi

  # Real-framebuffer screenshot — the artifact no container can produce.
  mkdir -p "$ARTIFACTS"
  if virsh -c "$URI" screenshot "$VM" "$ARTIFACTS/session-framebuffer.ppm" >/dev/null 2>&1; then
    if command -v magick >/dev/null 2>&1; then
      magick "$ARTIFACTS/session-framebuffer.ppm" "$ARTIFACTS/session-framebuffer.png" 2>/dev/null \
        && rm -f "$ARTIFACTS/session-framebuffer.ppm"
      log "framebuffer screenshot -> $ARTIFACTS/session-framebuffer.png"
    else
      log "framebuffer screenshot -> $ARTIFACTS/session-framebuffer.ppm"
    fi
  else
    warn "virsh screenshot failed (no graphics? check: virsh -c $URI domdisplay $VM)"
  fi
}

# ---------------------------------------------------------------------------
# stage: tests — reuse headless/lib.sh + tests/*.sh over the REAL user session
# ---------------------------------------------------------------------------
run_session_tests() {
  log "running the L4-headless TAP suite over the REAL VM session (session-attach)"
  # Ship lib.sh + tests/ + fixtures + the shared TAP helpers into the VM, then
  # run each test inside the user's graphical session (real XDG_RUNTIME_DIR/bus).
  vmssh 'rm -rf ~/vm-suite && mkdir -p ~/vm-suite/tests ~/vm-suite/fixtures' || die "mk suite dir failed"
  vmscp "$HEADLESS_DIR/lib.sh"          "$VM_USER@127.0.0.1:vm-suite/lib.sh"
  vmscp -r "$HEADLESS_DIR/tests/."      "$VM_USER@127.0.0.1:vm-suite/tests/"
  [[ -d "$HEADLESS_DIR/fixtures" ]] && vmscp -r "$HEADLESS_DIR/fixtures/." "$VM_USER@127.0.0.1:vm-suite/fixtures/"
  vmscp "$HERE/in-vm/run-suite-in-session.sh" "$VM_USER@127.0.0.1:vm-suite/run-suite-in-session.sh"

  mkdir -p "$ARTIFACTS"
  # The in-VM runner enters the user's graphical session, runs each test with the
  # right env, and prints a TAP report. It copies per-test artifacts under
  # ~/vm-suite/artifacts which we pull back on the host.
  set +e
  vmssh "SCREENSHOT_GEOMETRY_SKIP='$VM_GEOMETRY_SKIP' bash ~/vm-suite/run-suite-in-session.sh"
  local rc=$?
  # NOTE: do not re-enable errexit here — this script runs without `set -e`
  # on purpose (stages capture $? and continue); a stray `set -e` would abort
  # the whole run on the first non-zero stage rc (e.g. a failing assert).
  set +o errexit 2>/dev/null || true
  vmscp -r "$VM_USER@127.0.0.1:vm-suite/artifacts/." "$ARTIFACTS/" 2>/dev/null || true
  return $rc
}

# ---------------------------------------------------------------------------
# stage dispatch
# ---------------------------------------------------------------------------
order=(provision install session tests)
should_run() {
  local target="$1"; local from_idx=-1 tgt_idx=-1 i
  for i in "${!order[@]}"; do
    [[ "${order[$i]}" == "$stage_from" ]] && from_idx=$i
    [[ "${order[$i]}" == "$target"     ]] && tgt_idx=$i
  done
  (( tgt_idx >= from_idx ))
}

main() {
  preflight

  if should_run provision; then
    log "=== STAGE: provision ==="
    provision
  fi
  if $provision_only; then
    log "provision-only: VM is up. ssh -p $SSH_PORT -i $SSH_KEY $VM_USER@127.0.0.1"
    keep=true
    return 0
  fi

  local install_rc=0 assert_rc=0 tests_rc=0
  if should_run install; then
    log "=== STAGE: install ==="
    do_install; install_rc=$?
    log "=== STAGE: assert-install ==="
    assert_install; assert_rc=$?
  fi
  if should_run session; then
    log "=== STAGE: session ==="
    start_session
  fi
  if should_run tests; then
    log "=== STAGE: session tests ==="
    run_session_tests; tests_rc=$?
  fi

  echo
  log "================= L4-VM SUMMARY ================="
  log "omedora/install-4.sh exit ... $install_rc"
  log "install asserts ... $assert_rc"
  log "session tests  ... $tests_rc"
  log "artifacts      ... $ARTIFACTS/"
  log "================================================"
  (( install_rc == 0 && assert_rc == 0 && tests_rc == 0 ))
}

main
