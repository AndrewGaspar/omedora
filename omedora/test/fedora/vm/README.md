# L4-VM: the real-VM Omedora test tier

The highest-fidelity tier in the [test pyramid](../../../testing.md). Everything
below it (L1–L3, L4-nested/headless) runs in podman containers; this tier boots
a **real Fedora Workstation virtual machine** under libvirt+KVM, installs
Omedora **from the live COPR** the way a user would, brings up the
Omedora/Hyprland session on a **real GDM seat** (real DRM master, real
`systemd --user`, real session bus), and runs the **same** TAP assertion suite
the L4-headless tier runs — over the real session.

This is the launch-gate item (#86) that containers structurally cannot prove:
display-manager session pickup, a real seat/DRM master, and `systemctl --user`
against a real login session.

## Quick start

```sh
# Full run: provision Workstation VM -> install Omedora from COPR -> boot session -> assert
omedora/test/fedora/vm/run-vm-test.sh

# Fast mode: skip the multi-GB Flatpaks (keeps the dnf/COPR install)
omedora/test/fedora/vm/run-vm-test.sh --fast

# Just stand up a booted Workstation + SSH, then stop (for manual poking)
omedora/test/fedora/vm/run-vm-test.sh --provision-only

# Resume at a later stage against an already-provisioned VM
omedora/test/fedora/vm/run-vm-test.sh --stage install
omedora/test/fedora/vm/run-vm-test.sh --stage tests

# Test a specific channel/branch/tag (default: the branch this checkout is on)
omedora/test/fedora/vm/run-vm-test.sh --ref stable

# Leave the VM up for inspection; tear everything down later
omedora/test/fedora/vm/run-vm-test.sh --keep
omedora/test/fedora/vm/run-vm-test.sh --cleanup   # destroy+undefine any omedora-vmtest-*
```

## Architecture and why

### Provisioning: Fedora 44 Cloud Base qcow2 + cloud-init, layered up to Workstation

We download the **Fedora 44 Cloud Base** qcow2 once (cached under
`/var/tmp/omedora-vmtest/images/`), make a copy-on-write **overlay** per run, and
seed first boot with **cloud-init** via a **NoCloud `cidata` ISO**.

- **Why Cloud Base, not the Workstation Live ISO:** the Cloud Base is the only
  Fedora deliverable that is cloud-init-seedable, so it's the only one that
  provisions **fully unattended/scriptable** (no Anaconda kickstart wrangling,
  no interactive installer). The Cloud Base ships *headless* though — no GNOME.
- **Getting the real Workstation baseline:** cloud-init's `runcmd` runs
  `dnf group install workstation-product-environment` — the **same comps group**
  the Workstation Live install lays down (GNOME Shell, GDM,
  `xdg-desktop-portal-gnome`, `tuned-ppd`, the lot). So the end state is a
  genuine Workstation package set with GDM as the DM: the faithful **coexistence
  baseline** a real user installs Omedora onto. This is the scenario the
  `--workstation` podman tier approximates but can't fully be (no real DM/seat).
- **Why not Vagrant+libvirt:** another dependency and another box format to
  trust; cloud-init on the official qcow2 is fewer moving parts and is the same
  primitive CI systems use.
- **Why not kickstart netinstall:** ~2–3× slower (full netinstall) and the
  kickstart `%post` is clumsier to template than cloud-init for the
  user/SSH/autologin setup we need.

cloud-init also creates the `omedora` user (wheel, passwordless sudo), installs
our SSH key, sets GDM **autologin**, and the boot-prereqs (`git gum
dnf-plugins-core`). `cloud-localds`/`genisoimage` are **absent** on the dev
host, so the seed ISO is built with **`xorriso`** (`-volid cidata`).

### Hypervisor: `qemu:///session` (rootless) + passt networking — no host sudo

We use **rootless user-session libvirt** (`qemu:///session`). The dev host's
user is in `kvm`/`libvirt`, `/dev/kvm` is world-RW, so KVM acceleration works
without sudo. Networking is **passt** user-mode (`<interface type='user'>
<backend type='passt'/>`), the modern SLIRP replacement (QEMU 11 dropped
built-in SLIRP) — NAT to the host with **no bridge and no root**. A libvirt
**`portForward`** maps host `127.0.0.1:2222 -> VM:22`, so the orchestrator drives
the whole VM over SSH without any privileged network setup.

> **No host sudo is required for the default path.** The one thing that would
> need privilege is a *bridged* network (for the VM to be a first-class LAN
> host); we deliberately don't need that — passt NAT + portForward is enough to
> SSH in and let the VM reach the COPR/RPM Fusion/Flathub.

### Session validation: session-attach (primary) + framebuffer screenshot (artifact)

Two complementary approaches; we run **both**.

1. **Session-attach (primary, the real signal).** GDM autologins the user into
   `omedora.desktop` (we pin it as the user's AccountsService session). The
   Hyprland session then runs under `/run/user/1000` with a real
   `systemd --user` + session bus. The orchestrator SSHes in and runs the
   **exact** `omedora/test/fedora/headless/{lib.sh,tests/*.sh}` suite — the same
   TAP assertions the podman L4 tier uses (Hyprland IPC, a monitor, waybar/mako/
   swaybg autostart, walker render, portals, the 30/40/50 golden-image visual
   diffs, the 90-workstation coexistence checks). The only adaptation is the
   **attach**: an SSH login isn't the graphical session, so
   `run-suite-in-session.sh` reconstructs the env `machinectl shell` would set
   (`XDG_RUNTIME_DIR=/run/user/$UID`, `DBUS_SESSION_BUS_ADDRESS`); `lib.sh`'s
   `headless_session_env` then attaches identically. **No test is modified** —
   the assertion library is reused verbatim, which is the whole point.

   *Why this over screenshot-diff as the primary:* the assertions are precise
   and already maintained; the visual diff (30/40/50) is *included* in that
   suite, so we get golden-image coverage too — but driven by the same harness,
   not a separate host-side pixel pipeline.

2. **Real-framebuffer screenshot (artifact).** `virsh screenshot` grabs the
   **actual VM framebuffer** (converted to PNG) into `artifacts/`. No container
   can produce this — it's the literal scanout of the GDM-launched session on a
   real DRM master. It's a coarse "did it render at all" artifact for a human /
   CI to eyeball, complementary to the precise in-session grim diffs.

   *Tradeoff:* `virsh screenshot` is whole-framebuffer at the VM's resolution,
   which won't be pixel-identical to the 1920×1080 headless golden fixtures
   (different scanout path, cursor, resolution), so we don't byte-diff it against
   the L4 goldens — the in-session grim-based `30-visual` already does the
   tolerance diff against those fixtures from *inside* the session.

   **Resolution + the visual goldens.** The committed visual goldens (30/40/50)
   were captured at the headless tier's 1920×1080. The VM renders at whatever
   mode the virtio-gpu advertises (its default EDID is 1280×800), so a pixel-diff
   against the golden is a *geometry mismatch*, not a regression. Two mechanisms
   handle this: (1) the runner exports `SCREENSHOT_GEOMETRY_SKIP=1`, which makes
   `lib.sh` downgrade a geometry mismatch to a TAP **SKIP** (off in the podman
   tier, which stays strict) — **this is the verified default path**; and (2) an
   **opt-in** `OMEDORA_VM_RES` (e.g. `1920x1080`) that pins the virtio-gpu's
   advertised mode via QEMU `xres/yres` so the goldens can diff for real. It is
   **off by default**: the `-set device.<alias>.xres` lever needs the exact
   libvirt-assigned video alias (not a stable `video0` — a wrong alias makes QEMU
   refuse to boot), so to use it you pass both `OMEDORA_VM_RES=1920x1080` and
   `OMEDORA_VM_RES_ALIAS=<alias>` (find it in `virsh dumpxml <vm>` → `<video>
   <alias name='…'/>`).

   **GPU acceleration.** By default the VM gets `--graphics vnc,listen=127.0.0.1
   --video virtio` (software rendering; the VNC display is what `virsh
   screenshot` scans out). `OMEDORA_VM_GRAPHICS` and `OMEDORA_VM_VIDEO` override
   the two virt-install arguments verbatim, e.g.
   `OMEDORA_VM_GRAPHICS=egl-headless,rendernode=/dev/dri/renderD128
   OMEDORA_VM_VIDEO=model.type=virtio,model.acceleration.accel3d=yes` gives the
   session real GL through virgl on a host render node the session user can open.
   Caveat: `virsh screenshot` reports `no surface` on `egl-headless` (there is
   no display to scan out), so the host-side framebuffer artifact is skipped
   with a warning; the in-session grim captures still land in the artifacts.

## Install path exercised

The orchestrator syncs **this checkout** into the VM at
`~/.local/share/omarchy` (via `git archive`, so the VM tests *this branch*'s
code, not just a remote clone), then runs `install.sh` with
`OMARCHY_NONINTERACTIVE=1 OMEDORA_REF=<branch>`. That drives:
`preflight/all.sh` (incl. `fedora-repos.sh` → **`dnf copr enable agaspar/omedora-3`**
since no local repo is injected — real COPR resolution) → `packaging/all.sh`
(the dnf/COPR install, Flatpaks unless `--fast`) → `config/all.sh` (seed config
with backups). `assert-install.sh` then proves the packages came **from the
COPR** (`dnf repoquery --installed --qf '%{from_repo}'`), the session entry is
owned by `hyprland-omedora`, GNOME stays selectable, and the install log is
clean.

## Verified end-to-end (what actually ran)

This pipeline was executed against a real VM on the Arch dev host
(`qemu:///session`, passt, no host sudo):

- **Provision:** Fedora 44 Cloud Base → cloud-init → `dnf group install
  workstation-product-environment` landed **gnome-shell 50.2 + gdm 50.1**,
  default `graphical.target`; SSH reachable on `127.0.0.1:2222` via passt
  portForward. cloud-init reached `status: done`.
- **Install:** `install.sh` (NONINTERACTIVE, `--fast`) **exited 0**. The COPR was
  enabled live (`_copr:…:agaspar:omedora-3.repo`) and **30 packages installed
  from the COPR**, incl. `hyprland-omedora-1.0.0-1.fc44`,
  `hyprland-no-session`, `aquamarine`, `walker`/`elephant`, `swayosd`, the
  `hypr*` stack, the TUIs.
- **Install assertions: 12/12 pass** — COPR provenance
  (`%{from_repo}=copr:…:agaspar:omedora-3`), `omedora.desktop` owned by
  `hyprland-omedora`, GNOME still selectable, config seeded + bashrc block, clean
  install log.
- **Session:** GDM **autologged into the Omedora session** (`Hyprland
  --watchdog-fd` under `gdm-wayland-session … uwsm start … start-hyprland` on
  seat0/tty2) after `select-session.sh` pinned AccountsService `Session=omedora`
  and rebooted. The `virsh screenshot` shows the real Omedora session rendered
  (deer wallpaper + waybar + first-run notifications).
- **Session-attach suite: 8/8 pass** — `00-session` (Hyprland IPC + monitor +
  waybar/mako/swaybg autostart), `10-walker`, `20-portals` (hyprland portal wins,
  document portal FUSE mount), `60-wifi`, and **`90-workstation`** (GDM lists
  GNOME+Omedora, GNOME Shell 50.2 launchable, **powerprofilesctl via tuned-ppd
  shim**, gnome portal competitor present). `30/40/50` visual goldens reported
  **SKIP** (golden 1920×1080 vs VM 1280×800 — see Resolution above), not fail.

## Runtime budget

| phase | ~time | notes |
| --- | --- | --- |
| base image download | one-time ~1–2min | cached afterwards |
| provision (cloud-init + Workstation groupinstall + reboot) | ~6–12min | dominated by the comps-group dnf download |
| install (COPR enable + dnf + config) | ~10–25min | `--fast` skips Flatpaks (saves ~10–20min) |
| session bring-up + attach tests | ~2–4min | GDM autologin + the TAP suite |

A full cold run is roughly **25–45min**; a warm `--fast` re-run against a cached
base is faster. This is a **before-each-release / on DM-or-seat-or-SELinux
patches** gate, not a per-PR gate.

## CI assessment

**Local-only, by design.** Nested virtualization on GitHub-hosted runners is
unavailable/unreliable (no `/dev/kvm`); without KVM the VM falls back to TCG
emulation, which is ~10–20× slower — a 30min run becomes hours, impractical per
push. Options if a CI gate is ever wanted:

- A **self-hosted runner** on a bare-metal box with nested virt (or this dev
  host). The pipeline already runs unattended end-to-end, so wiring it to a
  self-hosted runner is mostly a `runs-on:` change + the host having
  libvirt/passt. **This is the realistic path.**
- GitHub's larger/bare-metal runner tiers *may* expose KVM in future; revisit
  then.

For now this sits alongside the documented expectation in `testing.md` that
"L4-VM operates manually" — except it's now **scripted and unattended**, so
"manually" means "a human kicks off one command before a release," not "a human
clicks through Anaconda."

## Cleanup + safety

Every resource is named `omedora-vmtest-*`. The orchestrator tears down its VM +
overlay + seed on exit (unless `--keep`); `--cleanup` destroys/undefines any
stray `omedora-vmtest-*` domain and removes its disks. **The user's existing VMs,
networks, and pools are never touched** — we only ever match the `omedora-vmtest`
prefix and only ever talk to `qemu:///session` (the user's `fedora44-dev` lives
under `qemu:///system` and is out of reach of this tier entirely).

## btrfs snapshot/rollback tier (`run-snapshot-vm-test.sh`)

A second, independent L4-VM entrypoint validates `bin/omedora-snapshot`
(create/list/delete/rollback) against a **real btrfs root on a rebooted VM** —
the one thing a container structurally cannot do: rootless podman has no
loop-device access, so btrfs can't be exercised in a container. The unit test
(`test/snapshot-test.sh`) mocks `btrfs`/`findmnt` and runs the command *logic*
against a plain directory; this tier runs the actual subvolume surgery for real.

```bash
omedora/test/fedora/vm/run-snapshot-vm-test.sh            # full run
omedora/test/fedora/vm/run-snapshot-vm-test.sh --keep     # leave the VM up
omedora/test/fedora/vm/run-snapshot-vm-test.sh --cleanup  # destroy omedora-snaptest-*
```

**Why no second disk:** the cached **Fedora 44 Cloud Base** qcow2 is *already*
btrfs-root — verified empirically (boot + `findmnt -no FSTYPE /` = `btrfs`).
Its top level (subvolid=5) holds `root` (mounted `/`), `boot`, `home`, `var`,
with fstab pinning `subvol=root` — the **exact layout `omedora-snapshot`
expects**. So the test runs against the VM's real `/`, no extra disk needed.
(`require_btrfs` would `exit 127` otherwise; that guard is asserted too.)

It reuses this directory's plumbing exactly (rootless `qemu:///session`, passt
NAT + hostfwd, the cached Cloud Base image, an xorriso-built NoCloud cidata ISO),
but provisions a **headless** VM (no Workstation groupinstall — it only needs
btrfs + sshd, so it's fast: ~1–2 min). The flow is split across a reboot:

1. **prepare** (in-VM, as root, `OMEDORA_SNAPSHOT_SUDO=""`):
   `omedora-snapshot create preinstall` → assert the read-only snapshot appears
   under `omedora-snapshots/` and `list` shows it; write `/PROOF-marker` into the
   live root and `/home/HOME-marker` into the home subvol; then
   `omedora-snapshot rollback <name> --apply`, auto-confirming the prompt by
   piping `rollback` to its `read` fallback (the base has no `gum`).
2. **reboot** onto the swapped-in `root` subvolume.
3. **assert** (in-VM, post-reboot): `/PROOF-marker` is **GONE** (rollback took
   effect), `/home/HOME-marker` **survived** (separate subvol untouched), and
   `root.broken-<ts>` exists at the top level and still holds the marker (the
   swap is reversible).

Resources are named `omedora-snaptest-*` (distinct hostfwd port 2298, distinct
overlay/seed) and self-cleaning on exit. The `omedora-vmtest-*` pipeline and the
user's own VMs are never touched.

## Known gaps / follow-ups

- **Interactive install path.** The default run uses `OMARCHY_NONINTERACTIVE=1`
  (the coexistence gate's non-interactive branch). An `expect`/PTY-driven run
  that exercises the *interactive* `fedora-plan.sh` gate (gum confirm /
  foreign-repo choose) over SSH is designed-for but not yet wired
  (`run-vm-test.sh` TODO). The gate's logic itself is unit-tested at L1
  (`test/coexistence-plan-test.sh`).
- **GNOME-side coexistence UX** (logging out of Hyprland *into* GNOME via the
  GDM greeter) is provable here but not yet a scripted assertion — the
  `90-workstation` test confirms both session entries are registered and GDM is
  unmasked, which is the package-level invariant.
