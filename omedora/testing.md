# Testing

This doc is the canonical strategy for testing omedora. It defines a four-layer pyramid (shell unit → Fedora container integration → Fedora container smoke → VM full desktop), what's testable where, the conventions for writing new tests, the container design, the CI workflow shape, the manual VM checklist, and the implementation roadmap for the test infra itself.

For the higher-level architecture this strategy serves, see [`architecture.md`](architecture.md). For agent-facing rules that reference this doc, see [`AGENTS.md`](AGENTS.md).

> **Status:** L1, L2, L3 (audit-only), the CI workflow, install-pipeline gating, and L4-nested are **shipped** — see roadmap [§10](#10-implementation-roadmap) for the per-step status. L4-nested boots a real Omedora session inside `fedora:44` under **real PID-1 systemd** (`podman --systemd=always`): the install runs end-to-end in a logind session (Flatpaks and all), and launching Hyprland brings up the full autostart chain (waybar, mako, swaybg, hypridle, fcitx5) nested under the host compositor. Follow-ups: bulk-fill the package map (step 10) and a scripted `smoke-assertions.sh`. L4-VM is documented but operates manually.

---

## 1. Why omedora needs more testing than upstream

Upstream Omarchy ships dispatcher tests only — `test/omarchy-cli-test.sh` (266 lines, TAP-style) covers routing, metadata, help rendering, and JSON output. No CI workflows. No coverage for install scripts, package helpers, migrations, update flow, or anything that touches `pacman`.

That posture is appropriate for them: single distro, rolling release, trust-the-PR-author. The patches land on real Arch boxes and break loudly if they're wrong.

Omedora is different in three ways that change the calculus:

1. **Dual-distro contract.** The same tree must work on both Arch and Fedora. Inside shared helpers, the Arch code path must remain byte-for-byte identical to upstream's behavior (see [`architecture.md` §1](architecture.md#1-dual-distro-patch-model)). The only mechanical way to enforce that is to *run* the Arch path and assert it didn't drift.
2. **Rebased onto upstream stable.** Every Omarchy release prompts a rebase ([`rebase-workflow.md`](rebase-workflow.md)). Conflicts get resolved by humans or agents; sometimes a resolution looks plausible but introduces a regression. Tests are the safety net.
3. **Downstream + opinionated stack.** When users hit issues, "did Omarchy break?" and "did omedora break?" need separate answers. A test suite that fails on a specific behavioral regression — instead of a vague "Hyprland won't start on my Fedora 44 box" — is the difference between a 10-minute fix and a 10-hour bisect.

The testing investment is therefore *larger* than upstream's, but the pyramid below keeps it bounded.

---

## 2. The five-layer pyramid

| Layer | Where | Runtime | What it covers | When it runs |
| --- | --- | --- | --- | --- |
| **L1 Shell unit** | Any host (Arch, Fedora, Linux CI) | < 5s total | Dispatcher rendering with brand shim, `omarchy-distro` detection with mocked `/etc/os-release`, package-helper dispatch with mocked `dnf`/`rpm`, `install/packages/fedora.toml` schema validation | Every PR (CI) + pre-commit |
| **L2 Fedora container integration** | `fedora:44` container | 30s–5min per test | Real `dnf install` of small package sets, COPR enable, package-map name translation against real `rpm -q`, update-flow staging with fixture markers, migration runner with fixture migrations, kernel-detection on real Fedora kernels | Every PR (CI) |
| **L2 Arch regression** | `archlinux:latest` container | ~30s | Upstream's `test/omarchy-cli-test.sh` passes unchanged; brand shim defaults to "omarchy" on Arch; helpers' Arch arms behave exactly like upstream | Every PR (CI) — **dual-distro contract enforcement** |
| **L3 Fedora smoke** | `fedora:44` container | 10–30min | Full install pipeline from a fresh container; all `omarchy-base.packages` resolve; all COPRs enable; source installers complete; configs land in `$HOME` | Nightly + `smoke` label on PR |
| **L4-nested Omedora session** | `fedora:44`-based image with full omedora install + Hyprland nested via Wayland-on-Wayland (see [§6](#6-l4-nested-container-design)) | ~15–30min one-time build + ~30s per run | **Real running omedora session inside a container** — Hyprland boot from the actual config payload, waybar render, walker open, mako notifications, theme switching with live components, keybindings driven via `hyprctl`, hyprlock invocation, screenshot via `grim`. Drives the actual session a user would see. | Local dev iterations; pre-release smoke |
| **L4-VM residue** | `fedora44-dev` libvirt VM, revert to `baseline-clean` snapshot | ~10min install + manual checklist | Only the bits L4-nested can't reach: display-manager session pickup (real GDM/SDDM), real hardware enumeration (`/sys/class/dmi/`, real `lspci`), SELinux `user_t` behavior, `systemctl --user` units against a real session bus | Before each omedora release; on hardware/DM/SELinux-specific patches |

**Critical: the L2 Arch regression job is non-negotiable.** Without it, the additive abstraction in [`architecture.md`](architecture.md) leaks silently — a contributor edits a shared helper, the Fedora arm gets tested, the Arch arm rots, and we don't find out until an Arch user files a bug. Run it every PR.

**Note on L4-nested vs L4-VM.** Earlier revisions of this doc assumed L4 had to be a VM because "you need real hardware + a real DM to run a Wayland compositor end-to-end." That turns out to be wrong: Hyprland's `AQ_BACKENDS=wayland` lets it run as a *Wayland client* of the host compositor (Wayland-on-Wayland nesting). With `/dev/dri` and render/video group propagation it gets hardware accel too. So most of the visual / compositor-level verification that used to require booting a VM now happens in a container, with a docker-run measured in seconds. The VM stays in the pyramid for the residue — primarily DM session pickup, real hardware enumeration, SELinux `user_t`, and `systemctl --user`.

---

## 3. What's testable where

### Fits cleanly into L1 or L2

| Surface | Layer | How |
| --- | --- | --- |
| `bin/omarchy-distro` | L1 | Mock `/etc/os-release` via tmpfile + an internal env hook |
| Brand shim in `bin/omarchy` | L1 | `OMARCHY_BRAND=omedora omarchy --help` and grep |
| `omarchy-pkg-add` / `pkg-missing` / `pkg-present` / `pkg-drop` dispatch | L1 | `PATH=test/mocks:$PATH` shadowing of `dnf` / `rpm` / `pacman`; assert against mock log |
| `omarchy-pkg-aur-add` tier fallback | L1 | Same, plus mock `flatpak`; fixture `fedora.toml` exercises each tier |
| Package-map TOML schema | L1 | Wrap `bin/omarchy-dev-validate-fedora-packages` (new) with fixture maps |
| Install-pipeline gating in `install.sh` | L1 | Run with `OMARCHY_DISTRO=arch` vs `=fedora`, assert which stages are sourced (via traced source) |
| `install/preflight/guard.sh` Fedora arm | L1 | Same env override |
| Hardware-config 1-line guards | L1 | Source the script with `OMARCHY_DISTRO=fedora` and assert early-return |
| `bin/omarchy-migrate` runner | L1+L2 | L1: drop fixture migrations, run, check state markers. L2: include a fixture that calls `omarchy-pkg-add` and verify it actually installed |
| Real `dnf install` of package-map entries | L2 | Container with real dnf; install `jq` (small, fast), verify `rpm -q jq` |
| Real `dnf copr enable lionheartp/Hyprland` | L2 | Container; verify `dnf info hyprland` succeeds afterward |
| `omarchy-update-perform-fedora` orchestration | L2 | Seed `~/.local/state/omedora/last-fedora-version`, run, assert which `update-fedora-*` siblings were called |
| `omarchy-update-fedora-version-check` | L2 | Seed marker file, assert `fedora-upgrade.sh` runs on mismatch and not on match |
| `omarchy-update-restart` kernel detection on Fedora | L2 | Container has `/usr/lib/modules/*/vmlinuz` and real `rpm -qf`; assert no crash on absent `pacman` |
| `omarchy-show-logo` / `omarchy-branding-screensaver` path swap | L1 | `OMARCHY_DISTRO=fedora` + grep output for the omedora logo path |
| `omedora --version` banner | L1 | Run, grep for "Omedora ... (rebased on Omarchy ...)" |
| `bin/omedora` symlink | L1 | Assert `[[ -L bin/omedora ]]` and `readlink bin/omedora == omarchy` |

### Fits at L4-nested (full omedora session inside a container)

| Surface | Layer | How |
| --- | --- | --- |
| Hyprland actually starting from omedora's real config | L4-nested | Container image has the full omedora install; launches Hyprland with `AQ_BACKENDS=wayland` against the host compositor socket |
| Live theme switching with running waybar/mako/walker | L4-nested | All components installed and started by the session; drive `omarchy theme set …` via `hyprctl dispatch exec` and assert via grep against waybar/mako sockets |
| Keybindings | L4-nested | `hyprctl dispatch …` exercises every bind; the smoke harness asserts on the resulting state |
| Screenshot via `grim` against the framebuffer | L4-nested | `grim -` to stdout; smoke either asserts on PNG headers or compares against a golden image |
| `hyprlock` interactive | L4-nested | `hyprctl dispatch exec hyprlock` in the nested session; assert lock state via hyprctl |
| Reboot / kernel-update prompts (`omarchy-update-restart` heuristic) | L4-nested | Real Fedora kernel available; runs the heuristic against `/usr/lib/modules/*/vmlinuz` and real `rpm -qf` |

### Needs L4-VM (genuinely VM-only)

| Surface | Why VM-only |
| --- | --- |
| Display-manager session pickup ("Omedora" in GDM/SDDM) | Needs a real DM running and reading `/usr/share/wayland-sessions/`; no container does this |
| Real hardware enumeration | `lspci` / `/sys/class/dmi/` in a container reflect the container view, not real hardware |
| SELinux `user_t` interactions | Containers run `container_t`; user_t policy differs |
| `systemctl --user` services | Containers don't run a user session bus by default; needs the real systemd-on-login chain |
| The actual login experience | Self-evident — needs greetd/GDM/SDDM driving Hyprland from a real seat |

The point of this split is to **prevent contributors from dumping L4-VM tests into L2** (the container can't show real hardware) **or L4-nested tests into L2** (the container without omedora installed can't run the session). When in doubt: if you need a running compositor + omedora components but not real hardware, you're at L4-nested. If you need real hardware or DM, you're at L4-VM. Everything else fits in L1–L3.

---

## 4. Test-style conventions

### TAP-style shell only

- **`pass` / `fail` / `assert_output_contains`** — the helpers upstream uses in `test/omarchy-cli-test.sh`. We extract them into a shared `test/helpers.sh` (planned) and source from each new test file.
- **No frameworks.** No Bats. No Pytest. The trade-off is intentional: matching upstream's style means brand-shim tests we add to `omarchy-cli-test.sh` could be upstreamable; new test files feel like the same project; contributors don't need to learn a framework.

### File layout

```
test/
├── helpers.sh                       # shared TAP helpers (planned)
├── omarchy-cli-test.sh              # upstream + brand-shim assertions (edited)
├── distro-test.sh                   # L1 distro detection (planned)
├── pkg-helper-test.sh               # L1 package helper dispatch (planned)
├── pkg-map-test.sh                  # L1 package map schema (planned)
├── mocks/                           # PATH-shadowed shell mocks (planned)
│   ├── dnf
│   ├── rpm
│   ├── pacman
│   └── flatpak
└── fedora/                          # L2/L3 container infra (planned)
    ├── Dockerfile
    ├── integration.sh               # L2 orchestrator
    ├── smoke.sh                     # L3 full-install
    ├── lib/                         # shared container test helpers
    └── fixtures/                    # fixture TOML maps, migrations, os-release files
```

Each L1 test is independently runnable: `bash test/distro-test.sh` produces TAP output and exits non-zero on failure. The L2/L3 orchestrators are also self-contained but require a built `test/fedora/` container image.

### Mocking

No mocking framework. Pattern: shell scripts under `test/mocks/` that record their invocation into `$MOCK_LOG` and exit 0:

```bash
# test/mocks/dnf
#!/bin/bash
printf 'dnf %s\n' "$*" >>"${MOCK_LOG:-/tmp/mock.log}"
exit 0
```

Tests prepend `test/mocks` to `$PATH`, set `$MOCK_LOG` to a temp file, run the code under test, then `grep` the log for expected calls. If a test needs a mock to *fail* (e.g., to test error handling), it sets `MOCK_DNF_EXIT=1` in the environment and the mock reads it.

This pattern is invisible to the code under test — the helpers just see `dnf` on `$PATH` like usual.

### Dev helper precedent

The new `bin/omarchy-dev-validate-fedora-packages` (planned) mirrors `bin/omarchy-dev-bin-metadata`: a single command that parses a data file (`install/packages/fedora.toml`), reports diagnostics, and supports `--json` for programmatic consumption. The `pkg-map-test.sh` test invokes the helper and asserts on its output. Humans run the same command for ad-hoc checks.

---

## 5. L2 and L3 container design

### Base image

`registry.fedoraproject.org/fedora:44` — the official Fedora image from the Fedora registry, **not** the Docker Hub mirror. Pinned to the major version; we bump explicitly when Fedora N+1 ships and we've validated.

### Preinstalled tools

In `test/fedora/Dockerfile`:

- `dnf-plugins-core` — provides the `dnf copr` subcommand
- `git` — for cloning omedora and exercising `omarchy-update-git`
- `gum` — required by ~45 omedora scripts for prompts
- `jq` — used by the dispatcher tests and JSON-asserting integration tests
- `python3` — for TOML parsing (3.11+ has `tomllib` built in; F44 ships Python 3.13)
- `flatpak` — even if we mock most of the time, having it present means the helper dispatch logic exercises the real binary
- `shellcheck` — runs against `bin/omarchy-*` and `install/**/*.sh` as part of the suite
- `findutils`, `which`, `procps-ng` — small utilities the install scripts depend on

`dnf makecache` runs at image build time so first cold-run isn't a full network fetch.

### Caching

- **GitHub Actions:** `actions/cache` keyed on `Dockerfile` SHA + a manual cache version. Caches `/var/cache/dnf` between runs. Warm runs are 10–20× faster.
- **Local:** mount `~/.cache/omedora-dnf` into the container at `/var/cache/dnf`. First run populates; subsequent runs are fast.
- **COPR metadata:** lives in `/var/cache/dnf` once enabled, so it caches alongside the rest. Avoid re-running `dnf copr enable` unnecessarily.

### Root vs non-root

- **L2 tests run as root inside the container.** Sudo is a no-op (root is root). This catches most regressions and keeps tests fast. The trade-off: bugs that only surface when sudo actually elevates won't be caught here.
- **L3 smoke runs as a non-root user** with sudoers preconfigured (`oman ALL=(ALL) NOPASSWD: ALL` style, scoped to commands the install needs). This exercises the real sudo path end-to-end.
- The container Dockerfile creates the non-root user but L2 tests don't `su` to it.

### gum-prompt handling

Omedora's codebase calls `gum` ~45 times (23× `gum confirm`, 15× `gum choose`, 6× `gum input`, 1× `gum spin`). In tests:

- **`gum confirm`** with no auto-answer wedges. Strategies:
  - Set `OMARCHY_UPDATE_LOGGED=1` (existing upstream env hook) to skip the update-flow confirm.
  - For other confirms: pipe `yes` to stdin, or introduce `OMARCHY_NONINTERACTIVE=1` and gate the prompts at the call sites we patch (additive; doesn't affect Arch).
- **`gum choose`** in tests: bypass by setting the env var the consumer reads (e.g., theme tests pre-set `OMARCHY_THEME=tokyo-night`).
- **`gum input`** in tests: same pattern — provide the value via env or fixture.
- **`gum spin`** is non-interactive output only; harmless.

Most L1 package-helper tests don't trigger any gum call. The L3 smoke test is where prompt handling matters most.

### No systemd in container

By default, Fedora containers don't run systemd as PID 1. Anything that needs `systemctl --user` (e.g., the swayosd / battery-monitor user services) is **out of scope for L2/L3** — deferred to L4. If a future test genuinely needs systemd in container, use `podman run --systemd=true` rather than baking it into the default image.

---

## 6. L4-nested container design

The L4-nested image runs a full Omedora session inside a Fedora container **booting real PID-1 systemd**, so the container has a real system D-Bus, `systemd-logind`, and a per-user `systemd --user` manager. That's the environment Omarchy/Omedora actually assumes — and the reason this layer earns "L4." It runs `install.sh` end-to-end against `fedora:44` and then boots Hyprland the way a bare-metal user would.

**Why systemd, not shims.** An earlier iteration used a plain `fedora:44` rootfs with no init and papered over the gap with shims: a no-op `systemctl`, a `uwsm-app` passthrough, and `dbus-run-session`. They drifted from reality and broke the session: **0 of 13 autostart entries fired** (the `uwsm-app -- <cmd>` wrappers had no user systemd to hand off to) and **waybar segfaulted** (no system bus). Booting real systemd fixes all of it at the root instead of one symptom at a time. The shims are gone.

**Runtime: podman, not docker.** L1/L2/L3 stay on docker, but L4 uses `podman run --systemd=always` — podman is built for systemd-in-container (cgroup + tmpfs scaffolding, `SIGRTMIN+3` stop signal, rootless) with no `--privileged`. Docker would need `--privileged` (or hand-tuned caps + cgroup mounts).

### Build: boot-then-install-then-commit

A `podman build` RUN has no PID-1 systemd, so the install can't run at build time without re-introducing the shims. Instead the build is two pieces:

1. **`Dockerfile.base`** — `FROM fedora:44`, installs systemd + `systemd-container` (for `machinectl`) + `systemd-pam` + dbus-broker + polkit + the install toolchain, creates the `omedora` user (wheel, NOPASSWD, password `omedora`, lingering enabled), copies the omedora tree to `~/.local/share/omarchy`, `CMD ["/sbin/init"]`. Build product: `omedora-test:fedora44-session-base`.
2. **`build-session.sh`** — boots the base under `--systemd=always`, waits for systemd + the `omedora` user manager, then runs `install.sh` **as omedora through `machinectl shell`** (a real PAM/logind session: `XDG_RUNTIME_DIR`, user D-Bus, a PTY — no `script` hack), and `podman commit`s the finished container to `omedora-test:fedora44-session`.

This is the most faithful path — literally "boot Fedora, log in, run the installer." Concrete wins over the old build-time install: **Flatpaks actually install** (real session bus; Typora/Obsidian/Signal/localsend + the freedesktop runtimes) instead of being skipped, the install runs under a real PTY, and there's no `OMARCHY_CHROOT_INSTALL`, no systemctl shim, no uwsm-app shim.

Two non-obvious bring-up fixes live in `Dockerfile.base`: install `systemd-pam` (the minimal Fedora image omits `pam_systemd.so`, without which `machinectl shell` gets no session or `XDG_RUNTIME_DIR`), and a `user@.service` drop-in pinning `XDG_RUNTIME_DIR=/run/user/%i` (so the lingering user manager starts at boot instead of dying with exit 49).

### Booting the session: Wayland-on-Wayland nesting

Hyprland normally drives KMS/DRM directly — impossible in a container (needs seat + DRM master). The `wayland` backend (`AQ_BACKENDS=wayland`) instead makes Hyprland a *Wayland client* of the host compositor: it opens a window on the host and renders into it. `run-session.sh` handles the host side; `session-launch.sh` (inside the container, run via `machinectl shell` as omedora) sets the nesting env and launches the compositor.

| Need | How |
| --- | --- |
| Host Wayland socket reachable as omedora | Bind-mount `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY` → `/tmp/host-wayland`; `session-launch.sh` sets `WAYLAND_DISPLAY=/tmp/host-wayland` (an absolute value libwayland uses verbatim) |
| omedora (a subuid under rootless podman) can connect to that socket | The runner — which owns the socket — widens it to `0777` for the session and restores the original mode on exit. The render node is world-rw, so GPU needs no group juggling |
| `XDG_RUNTIME_DIR` + user D-Bus + `systemd --user` | Provided by the real logind session `machinectl shell` enters — not faked |
| Hardware-accelerated rendering | `--device /dev/dri` (render node is `crw-rw-rw-`); `--device /dev/rfkill` keeps waybar's rfkill module quiet |
| Hyprland refuses to run as root | Runs as omedora (uid 1000) inside the logind session, never container root |

**Why not `uwsm start`?** Upstream's `omarchy.desktop` launches via `uwsm start … Hyprland hyprland.desktop`, but uwsm's environment preloader is seat/VT-aware: it asks `loginctl` for the session on the foreground VT and aborts ("Could not determine session on foreground VT") when there isn't one — and a container has no seat0 and no VTs. So `session-launch.sh` launches `Hyprland` directly. This is still faithful where it counts: the autostart chain in `default/hypr/autostart.lua` wraps each app in `uwsm-app -- <cmd>`, and the real `uwsm-app` hands those off to the running `systemd --user` exactly as on bare metal. Verified: the full autostart chain — waybar, mako, swaybg, hypridle, fcitx5 — comes up and waybar is stable.

### Run modes

`test/fedora/run-session.sh` (default: interactive):

- **(default)** boots the session image under systemd and `machinectl shell`s into `session-launch.sh`, opening a nested Hyprland window on your desktop with the full Omedora session. Close the window to exit; the runner removes the container and restores the host socket mode. **Working — verified.**
- **`--shell`** — boots systemd and drops you into a `machinectl shell` as omedora (no compositor) for poking around a real logind session.
- **`--rebuild`** — rebuilds the session image (re-runs `build-session.sh`) first.
- **`--keep`** — leaves the container running on exit for inspection.

A scripted `--smoke` mode driving `hyprctl` (theme switch, walker open, screenshot) is a follow-up — see `smoke-assertions.sh` in [§10](#10-implementation-roadmap) step 13.

### Headless mode (`--headless`): self-contained, parallelizable, CI-able

The default run mode nests Hyprland into the **developer's own desktop compositor** (the host Wayland socket bind-mounted at `/tmp/host-wayland`). That has three structural problems: it needs a logged-in Wayland desktop (useless on CI / headless servers), there's only **one** host socket (parallel runs collide — container-name clashes, fights over the socket, chmod races), and the host desktop's locking interferes with screenshots.

**`run-session.sh --headless` fixes all three.** Each container stands up its **own** headless Wayland compositor (`labwc`) internally and nests Omedora's Hyprland into *that*. No host desktop, no socket bind-mount, no shared state — so many containers run in parallel without conflict, and it works on a headless box. The in-container launcher is `session-launch-headless.sh` (run via `machinectl shell` as omedora, same as the default path).

```
run-session.sh --headless
   └─ podman run --systemd=always (NO host-socket mount)
        └─ machinectl shell omedora@.host → session-launch-headless.sh
             ├─ systemd-run --user labwc   (WLR_BACKENDS=headless)  → wayland-0
             └─ systemd-run --user Hyprland (nests into wayland-0)   → wayland-1 + IPC
```

**Why labwc (and not weston / sway / cage / Hyprland's own headless backend)?** Hyprland 0.55.2 uses **Aquamarine 0.12**, whose nested (`wayland`) backend hard-requires the host compositor to advertise **both**:

| Requirement | weston 15 headless | sway 1.11 | **labwc 0.9.6** |
| --- | --- | --- | --- |
| `xdg_wm_base` **version 6** | ✗ (v5 → *"invalid version for global xdg_wm_base"*) | ✗ (v5) | ✓ |
| `zwp_linux_dmabuf_v1` | ✗ (headless backend never exports it, any renderer → *"Missing protocols"*) | ✓ | ✓ |

labwc (wlroots 0.19) is the lightest Fedora 44 compositor that satisfies both: it runs its GLES2 renderer over a DRM render node and exports linux-dmabuf + xdg-shell v6. (Hyprland's *own* headless backend `AQ_BACKENDS=headless` is absent from the lionheartp build — `CBackend::create() failed!` — so a separate nesting host is required regardless.)

**The recipe** (all proven empirically):

1. **labwc**, transient user unit: `WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER_ALLOW_SOFTWARE=1 labwc` → creates `wayland-0`.
2. **Hyprland**, transient user unit, `WAYLAND_DISPLAY=wayland-0` → aquamarine's wayland backend connects, binds dmabuf, creates the nested output, and IPC comes up.
3. **`hyprctl output create headless`** — the nested aquamarine output doesn't always auto-promote to a Hyprland monitor under this build, so create an explicit 1920×1080 headless output. (`hyprctl keyword monitor …` is rejected by the Lua-config parser; `output create` works.)
4. Drive via `hyprctl` and screenshot with `grim -o <MON>` against `WAYLAND_DISPLAY=<Hyprland's wl_socket>`.

The full autostart chain (waybar, mako, swaybg, hypridle, fcitx5) comes up exactly as in the host-nested path, and `grim` captures a non-blank PNG of the live Omedora desktop. Two `--headless` containers run side-by-side with independent state (verified).

**GPU vs software rendering.** Aquamarine's GBM allocator needs a DRM **render node** (`/dev/dri/renderD*`) — it has *no* shm/pixman fallback for nesting, so a pure-software (`--renderer=pixman`, no render node) path does **not** work.

- **Local dev (has a GPU):** the runner passes `--device /dev/dri`; labwc/wlroots picks a node automatically. On **multi-GPU** hosts one node's GBM allocator can fail (observed: NVIDIA `renderD128` → *"Couldn't allocate a gbm buffer … format XR24"*, while AMD `renderD129` works). Pin the good one with `OMEDORA_RENDER_NODE=/dev/dri/renderD129` — it's forwarded to both labwc (`WLR_RENDER_DRM_DEVICE`) and aquamarine (`AQ_DRM_DEVICES`).
- **GPU-less CI:** load the host kernel **`vkms`** module (Virtual KMS — a software DRM device that llvmpipe renders into; shipped by stock Fedora/Ubuntu CI kernels) and pass that render node via `OMEDORA_RENDER_NODE`. This is the no-GPU path. (The dev box used here runs an Arch kernel built **without** `CONFIG_DRM_VKMS`, so the pure-no-GPU path couldn't be demonstrated locally — but the chain is identical: any working render node, real or vkms, satisfies aquamarine.)

**Knobs:** `OMEDORA_RENDER_NODE` (pin a render node), `OMEDORA_HEADLESS_RES` (default `1920x1080`), `OMEDORA_HEADLESS_KEEP` (return after the session is up instead of blocking — for scripted/CI driving).

**Limitations:** software rendering (llvmpipe / vkms) is slow — fine for smoke assertions and screenshots, not for perf testing. The lionheartp Hyprland build's `hyprctl monitors` intermittently returns `unknown request` before the explicit output is created (the launcher works around it). `hyprctl dispatch exec …` needs the Lua quoting form `hl.dispatch("exec","<cmd>")`; launching clients directly with `WAYLAND_DISPLAY` set to Hyprland's socket is simpler for scripted driving.

### Why this *can now* be in CI

The original blocker was "GitHub Actions runners are headless — no compositor to nest under." `--headless` removes that: the container brings its own compositor. The remaining requirement is a **DRM render node**, satisfied on GPU-less runners by loading **`vkms`** (`sudo modprobe vkms` in a CI step, then `OMEDORA_RENDER_NODE=/dev/dri/renderD128`). The systemd image build (~15–30 min) is still at the upper edge of practical CI runtime, so the pragmatic plan is a **scheduled / on-demand** CI job (not every push) that builds once, caches the image, and runs the `--headless` smoke. The earlier Xvfb + `x11`-backend idea is unnecessary.

### File layout

```
test/fedora/
├── Dockerfile              # L2/L3 base (docker)
├── integration.sh          # L2
├── smoke.sh                # L3 (audit)
├── omedora-session/        # L4-nested (podman, systemd)
│   ├── Dockerfile.base               # FROM fedora:44; systemd + deps + omedora tree (+ labwc for --headless); CMD /sbin/init
│   ├── session-launch.sh             # in-container: nests Hyprland under the HOST compositor
│   └── session-launch-headless.sh    # in-container: starts labwc + nests Hyprland into it (no host desktop)
├── build-session.sh        # boot base under systemd, install via machinectl shell, commit
├── run-integration.sh      # L2 host-side runner
├── run-smoke.sh            # L3 host-side runner
└── run-session.sh          # L4-nested runner: --shell | --rebuild | --keep
```

---

## 7. Container-test gotchas

Specific friction points worth knowing about before writing tests:

| Gotcha | Mitigation |
| --- | --- |
| **SELinux context differs.** Container is `container_t`, real install is `user_t`. Most omedora ops are identical in both; some (writing outside `/etc/yum.repos.d/`) may differ. | Catch user_t-specific issues at L4. Don't write L2 tests that depend on user_t policy. |
| **No systemd PID 1 at L2/L3.** The docker L2/L3 base has no init, so `systemctl status foo.service` returns nothing meaningful. | Defer anything needing a real session to **L4-nested**, which boots real PID-1 systemd under `podman --systemd=always` ([§6](#6-l4-nested-container-design)). Don't write L2/L3 tests that assume running units. |
| **Default user is root (L2).** Sudo is a no-op. Hides bugs in the sudo path. | L3 smoke and L4-nested both run as non-root `omedora` with sudoers preconfigured. L2 tolerates the simplification. |
| **dnf metadata is slow first time** (~10-30s cold). | Cache `/var/cache/dnf` aggressively (docker BuildKit cache mount at L2/L3; a named podman volume for the L4 build). |
| **COPR metadata** lives in dnf cache once enabled. Re-enabling doesn't re-fetch — just appends. | Pre-enable in the image. Skip the enable step in tests that don't specifically test enablement. |
| **Flatpak needs a session bus.** It wants the user D-Bus + polkit; runtimes are huge. | Mock at L2 (record `flatpak install` args, exit 0). At **L4-nested** real `flatpak install --user` works because the install runs in a logind session with a live user bus — verified installing Typora/Obsidian/Signal/localsend. |
| **`omarchy-update-restart`** uses `pacman -Qo` for kernel detection. Pacman isn't in Fedora containers. | The Fedora-arm patch lives on the patch-stack map. Until it lands, the test that runs `omarchy-update-restart` on Fedora will fail. That's a feature: the test is the forcing function. |
| **Network from CI runners.** GitHub Actions can reach `dl.fedoraproject.org`, `copr.fedoraproject.org`, `dl.flathub.org`. Bandwidth is fine. | If we hit rate limits on COPR, add backoff/retry to the test script. Not a current concern. |
| **grim against the nested wayland-N socket hangs.** When Hyprland uses the `wayland` aquamarine backend, the wlr-screencopy protocol doesn't complete cleanly inside the nested compositor — `grim` from inside the container blocks indefinitely. | Drive smoke assertions via `hyprctl` only (clients, monitors, getoption). If a screenshot is genuinely needed, capture the nested *window* from the host with `grim -g <geometry>` against the host compositor. |
| **`AQ_BACKENDS=headless` fails** on Hyprland 0.55.2 (lionheartp COPR build): `CBackend::create() failed!` — the headless aquamarine backend isn't built in. | Use the `wayland` backend (nest under the host compositor) for local dev. A CI-runnable headless path needs Xvfb + `AQ_BACKENDS=x11` (planned). |
| **`uwsm start` aborts in a container** — its env preloader asks `loginctl` for the session on the foreground VT and fails ("Could not determine session on foreground VT"); a container has no seat0/VTs. | L4-nested launches `Hyprland` directly under the logind session. The autostart's per-app `uwsm-app -- <cmd>` still works via the real `systemd --user` ([§6](#6-l4-nested-container-design)). |
| **Rootless podman maps omedora to a subuid**, so it can't connect to the host's `0755` Wayland socket. | `run-session.sh` (which owns the socket) widens it to `0777` for the session and restores the mode on exit. GPU needs no juggling — the render node is world-rw. |

---

## 8. CI workflow shape

`.github/workflows/test.yml` defines four parallel jobs on push and pull_request. **L4-nested is not in CI** (no host Wayland on GitHub runners for the nested compositor to render into; an Xvfb-wrapped headless path is technically possible but the systemd image build cost makes it impractical for every PR).

### `shell-unit` (fast, every PR)

Runs on `ubuntu-latest`. Installs only `jq`, `python3`, `shellcheck`. Runs every `test/*-test.sh` (currently `omarchy-cli-test.sh`; later joined by `distro-test.sh`, `pkg-helper-test.sh`, `pkg-map-test.sh`). Total runtime under 30s.

### `arch-regression` (fast, every PR)

```yaml
- run: docker run --rm -v $PWD:/repo -w /repo archlinux:latest bash -c '
    pacman -Sy --noconfirm jq python git gum &&
    test/omarchy-cli-test.sh
  '
```

Plus a check that `omarchy --help` (default invocation, no `OMARCHY_BRAND`) contains "omarchy" and not "omedora". This is the dual-distro contract.

### `fedora-integration` (medium, every PR)

Builds `test/fedora/Dockerfile`, mounts the repo, runs `test/fedora/integration.sh`. Caches `/var/cache/dnf` keyed on `test/fedora/Dockerfile` SHA. Runtime typically 2-5 minutes warm.

### `fedora-smoke` (slow, gated)

Same Dockerfile, runs `test/fedora/smoke.sh`. Triggered by:

- `schedule: '0 6 * * *'` (nightly at 06:00 UTC)
- Pull requests carrying the `smoke` label

Runtime 10-30 minutes. Not on every PR.

### What we do NOT add to CI

- L4-nested (local-only — see [§6](#6-l4-nested-container-design)).
- Coverage reporting (no useful signal for shell + container tests).
- Cross-version Fedora matrix until Fedora N+1 release prep (then we add F45 alongside F44).
- Cross-arch matrix (x86_64 only for the foreseeable future; matches Omarchy upstream).

---

## 9. Manual VM workflow (L4-VM residue)

L4-nested ([§6](#6-l4-nested-container-design)) now covers most of what used to require booting the VM. The VM workflow that remains is narrower — its job is the residue (display manager session pickup, real hardware enumeration, SELinux `user_t`, `systemctl --user`). No automation ships in this commit; the manual checklist:

### Setup

The `fedora44-dev` libvirt VM is configured per the user's reference notes. Default credentials: `oman` / `password`. Snapshot anchor: `baseline-clean`.

### When to reach for the VM (vs L4-nested)

| Reason | Layer |
| --- | --- |
| Visually verifying a theme, animation, or layout change | L4-nested (faster iteration) |
| Driving keybindings / walker / mako / screenshot end-to-end | L4-nested |
| Checking that the omedora.desktop entry actually shows up in GDM/SDDM session picker | **L4-VM** |
| Checking SELinux `user_t` doesn't block a new path you wrote to | **L4-VM** |
| Verifying `systemctl --user enable foo.service` works in a real session | **L4-VM** |
| Testing hardware-specific install paths (NVIDIA, T2 Mac, Surface) | **L4-VM** (and on real hardware where possible) |
| Pre-release sign-off | **L4-VM** plus L4-nested smoke |

### Pre-release residue checklist (in the VM)

```bash
# 1. Revert to clean snapshot
virsh -c qemu:///system snapshot-revert fedora44-dev baseline-clean

# 2. Boot and log in
virt-viewer --connect qemu:///system fedora44-dev

# 3. Inside the VM, bootstrap omedora
curl -fsSL https://raw.githubusercontent.com/<your-org>/omedora/dev/boot-omedora.sh | bash

# 4. Reboot
sudo systemctl reboot

# 5. At the display manager, select "Omedora" from the session picker, log in
```

VM-specific checks the container can't replicate:

- [ ] "Omedora" appears as a session option in GDM/SDDM picker; selecting it logs into a working session
- [ ] `journalctl --user -b 0` shows no SELinux denials (`type=AVC` lines) related to omedora's paths
- [ ] `systemctl --user list-units` shows the omedora user services running (e.g., swayosd, battery-monitor)
- [ ] `loginctl session-status` reflects the active Wayland seat
- [ ] Hardware-conditional install scripts (NVIDIA, etc.) ran / no-op'd correctly per the actual hardware

The compositor-level visual checks (theme switching, walker, screenshot, etc.) are still valuable as a final pass but they should have already been verified by L4-nested.

### Documenting regressions

If anything in the checklist fails, capture a screenshot (or terminal output for non-visual failures) and reference the upstream commit + omedora commit in the bug report. Revert the snapshot when done so the next test starts clean.

### Sudo etiquette

Per a persistent user preference, **Claude never invokes sudo via the Bash tool** — even with passwordless sudo configured. Tests that need root *inside a container* are fine (the container itself runs as root; no privilege escalation). Tests that need root *on the host* are not; the test script prints the exact command, waits, and resumes after the human runs it. The L4-VM workflow is interactive by design — the human is already at the keyboard.

---

## 10. Implementation roadmap

Steps 1-7 are **shipped** (the test-infrastructure foundation: L1, L2, L3, CI). Steps 8-11 are the **next slab** — install-pipeline gating + L4-nested + bulking out the package map. Each step is independently rebasable.

| Step | Status | Commit | Files | Notes |
| --- | --- | --- | --- | --- |
| 1 | ✅ shipped | Extract test helpers | `test/helpers.sh`, edit to `test/omarchy-cli-test.sh` | Mechanical extraction; the one shared-file patch in this roadmap. |
| 2 | ✅ shipped | Distro detection + L1 test | `bin/omarchy-distro`, `test/distro-test.sh` | |
| 3 | ✅ shipped | Brand shim + assertions | `bin/omarchy` (edit), `bin/omedora` (symlink), `bin/omarchy-version` (edit), brand assertions in `test/omarchy-cli-test.sh` | The CLI rebrand from [`architecture.md` §10](architecture.md#10-cli-rebrand-tactical). |
| 4 | ✅ shipped | Package helpers + L1 test | `bin/omarchy-pkg-*` (edits with Fedora dispatch shim), `bin/fedora/pkg.py`, `test/mocks/{dnf,rpm,pacman,flatpak,sudo}`, `test/pkg-helper-test.sh` | The biggest helper change. |
| 5 | ✅ shipped | Package map + validator | `install/packages/fedora.toml`, `bin/omarchy-dev-validate-fedora-packages`, `test/pkg-map-test.sh` | Starter set; grows incrementally per step 9. |
| 6 | ✅ shipped | L2 + CI bring-up | `test/fedora/Dockerfile`, `test/fedora/integration.sh`, `test/fedora/lib/container.sh`, `.github/workflows/test.yml`, `test/fedora/run-integration.sh` | After this, every PR is regression-tested. |
| 7 | ✅ shipped | L3 smoke (audit-only) | `test/fedora/smoke.sh`, `install/preflight/fedora-repos.sh`, `test/fedora/run-smoke.sh`, scheduled job in CI | Audits the package map against real dnf; does NOT yet run install.sh end-to-end. |
| 8 | ✅ shipped | **Install-pipeline gating** (preflight + orchestrator) | `install.sh` (Arch gate around `login/` and `post-install/`), `install/preflight/guard.sh` (Fedora arm), `install/preflight/pacman.sh`, `install/preflight/disable-mkinitcpio.sh`, `install/preflight/all.sh` (source `fedora-repos.sh` on Fedora) | Unblocks running `install.sh` against `fedora:44` end-to-end. |
| 9 | ✅ shipped | **Install-pipeline gating** (system-admin scope) | Arch-only gate on `install/config/all.sh` system-admin block (gpg, login, hardware, network, power, security, services, sudoers); per-script guards on `mimetypes.sh`, `theme.sh`, `nvim.sh`, `mise-work.sh` | System-admin concerns (sysctl, sudoers, /etc, systemd units) are the user's Fedora install's job — see [`architecture.md` §6](architecture.md#6-install-pipeline-gating). |
| 10 | planned | **Bulk-fill the package map** | `install/packages/fedora.toml` (add entries for the ~30 unmapped packages the L3 audit currently surfaces) | The L3 audit's "unmapped + dnf MISSES" list is the punch list. Many entries currently `source = "skip"`. |
| 11 | planned | **Wayland session entry** + Fedora-side config script | `default/wayland-sessions/omedora.desktop` (new), `install/config/wayland-session-fedora.sh` (new), wired into `install/config/all.sh` | The session entry the display manager picks up — used by L4-VM and (cosmetically) by L4-nested. |
| 12 | ✅ shipped | **L4-nested image + runner (systemd)** | `test/fedora/omedora-session/Dockerfile.base` (FROM fedora:44, systemd + tree), `test/fedora/build-session.sh` (boot+install+commit), `test/fedora/omedora-session/session-launch.sh`, `test/fedora/run-session.sh` (podman `--systemd=always`) | Verified: real PID-1 systemd boots, install runs in a logind session (Flatpaks install), nested Hyprland brings up the full autostart chain. Supersedes the earlier shimmed image (no-init + systemctl/uwsm-app shims) — those are deleted. |
| 13 | planned | **`smoke-assertions.sh`** | `test/fedora/omedora-session/smoke-assertions.sh` | hyprctl-driven assertions (theme switch, walker open, screenshot) for a scripted `--smoke` run. |
| 14 | deferred | VM smoke harness (optional) | `scripts/vm-smoke.sh` (new) | Deferred per user; lands if/when manual L4-VM workflow gets repetitive enough to automate. |

Implementation commits should land tests **with** their corresponding code, not in batches. A package-helper patch arrives with the helper test that proves it. This is TDD-ish in spirit but pragmatic — we're not strict about tests-first vs code-first within a commit.

---

## 11. Cross-links

- [`architecture.md` §15](architecture.md#15-patch-stack-map) — the patch-stack map's "Testing" row group lists every file this doc references (with `(planned)` annotations on files not yet on disk).
- [`architecture.md` §6](architecture.md#6-install-pipeline-gating) — the install-pipeline gating that L4-nested depends on.
- [`AGENTS.md`](AGENTS.md) — the "Verification before merge" rule points back here. Reading both is required for agents working on this fork.
- [`rebase-workflow.md`](rebase-workflow.md#4-verification-matrix) — the verification matrix complements this strategy; the matrix says *what to verify after a rebase*, this doc says *how the verification is structured*.
- [`packages.md`](packages.md) — defines the package-map TOML schema that `omarchy-dev-validate-fedora-packages` (per [§4](#4-test-style-conventions)) enforces.
