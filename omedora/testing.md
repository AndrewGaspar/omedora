# Testing

This doc is the canonical strategy for testing omedora. It defines a four-layer pyramid (shell unit → Fedora container integration → Fedora container smoke → VM full desktop), what's testable where, the conventions for writing new tests, the container design, the CI workflow shape, the manual VM checklist, and the implementation roadmap for the test infra itself.

For the higher-level architecture this strategy serves, see [`architecture.md`](architecture.md). For agent-facing rules that reference this doc, see [`AGENTS.md`](AGENTS.md).

> **Status:** L1, L2, L3 (audit-only), the CI workflow, install-pipeline gating, and L4-nested are **shipped** — see roadmap [§10](#10-implementation-roadmap) for the per-step status. L4-nested boots a real Omedora session inside `fedora:44` under **real PID-1 systemd** (`podman --systemd=always`): the install runs end-to-end in a logind session (Flatpaks and all), and launching Hyprland brings up the full autostart chain (waybar, mako, swaybg, hypridle, fcitx5) nested under the host compositor. The **L4-headless automated test suite** (`omedora/test/fedora/headless/`) — a TAP harness with screenshots-on-failure and a CI exit code — is the canonical L4 assertion path (closes #45). Follow-up: bulk-fill the package map (step 10). **L4-VM is now a scripted, unattended pipeline** (`omedora/test/fedora/vm/run-vm-test.sh`, see [§9](#9-l4-vm-real-vm-pipeline)): it provisions a real Fedora Workstation VM (rootless libvirt+KVM, no host sudo), installs Omedora from the live COPR, autologins the Omedora session via GDM, and runs the L4-headless TAP suite over that real session — verified end-to-end (install exit 0; 12/12 install asserts incl. COPR provenance; 8/8 session asserts). It's a local / self-hosted-runner pre-release gate, not a per-PR CI gate (no KVM on GitHub runners).

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
| **L4-VM real-VM pipeline** | Rootless libvirt+KVM (`qemu:///session`) Fedora 44 **Workstation** VM, cloud-init-provisioned, install from the **live COPR** (`omedora/test/fedora/vm/`, see [§9](#9-l4-vm-real-vm-pipeline)) | ~25–45min cold (`--fast` skips Flatpaks) | The bits L4-nested can't reach: display-manager session pickup (real **GDM** autologin into `omedora.desktop`), real seat + DRM master, `systemctl --user` against a real session bus, real-framebuffer screenshot (`virsh screenshot`), and **COPR provenance** (`%{from_repo}` is the COPR, not an injected local repo). Reuses the L4-headless TAP suite over the real session. | Before each omedora release; on hardware/DM/SELinux-specific patches |

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

Each L1 test is independently runnable: `bash test/distro-test.sh` produces TAP output and exits non-zero on failure. The L2/L3 orchestrators are also self-contained but require a built `omedora/test/fedora/` container image.

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

In `omedora/test/fedora/Dockerfile`:

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
2. **`build-session.sh`** — boots the base under `--systemd=always`, waits for systemd + the `omedora` user manager, then runs the install **as omedora through `machinectl shell`** (a real PAM/logind session: `XDG_RUNTIME_DIR`, user D-Bus, a PTY — no `script` hack), and `podman commit`s the finished container to `omedora-test:fedora44-session`.

This is the most faithful path — literally "boot Fedora, log in, run the installer." Concrete wins over the old build-time install: **Flatpaks actually install** (real session bus; Typora/Obsidian/Signal/localsend + the freedesktop runtimes) instead of being skipped, the install runs under a real PTY, and there's no `OMARCHY_CHROOT_INSTALL`, no systemctl shim, no uwsm-app shim.

Two non-obvious bring-up fixes live in `Dockerfile.base`: install `systemd-pam` (the minimal Fedora image omits `pam_systemd.so`, without which `machinectl shell` gets no session or `XDG_RUNTIME_DIR`), and a `user@.service` drop-in pinning `XDG_RUNTIME_DIR=/run/user/%i` (so the lingering user manager starts at boot instead of dying with exit 49).

#### Two-stage build (incremental-rebuild speedup)

Profiling a warm build showed the install wall-time is dominated by **one stage**: `install/packaging/base.sh` (`dnf install` of the whole package set) is **~93%** of it (~3 min, even with the dnf cache warm), while the config stages you actually iterate on are **~10 s combined**. Re-running the whole install to test a one-line config change therefore paid the full ~3 min package cost for nothing.

`build-session.sh` now splits the install into **two committed layers**, sourcing the *same* real install `all.sh` files in the *same* order as `install.sh` (via `omedora-session/staged-install.sh` — `install.sh` itself is untouched, so zero added rebase surface):

| Image | Built from | Stages |
| --- | --- | --- |
| `omedora-test:fedora44-session-base` | `Dockerfile.base` | Fedora + systemd + the omedora tree |
| `omedora-test:fedora44-session-pkgs` | base | `preflight/all.sh` + `packaging/all.sh` (the slow `dnf install`) |
| `omedora-test:fedora44-session` | **pkgs** | `config/all.sh` (the fast, idempotent config) |

Build modes:

| Command | What it does | Wall time (this dev box) |
| --- | --- | --- |
| `build-session.sh` | base (if missing) → **pkgs (if missing)** → config → session | full first time; **~9 s** (config-only) if the pkgs image already exists |
| `build-session.sh --rebuild` | clean: base + pkgs + config (force-repackage); rebuilds the RPM repo **only if a spec changed** | packages phase + config |
| `build-session.sh --rebuild-repo` | as `--rebuild`'s default path but also force-rebuilds the local RPM repo | + ~3–4 min repo build |
| `build-session.sh --fast` (alias `--config-only`) | boot the **existing** pkgs image, re-run **only** the config stages, recommit session | **~9 s** (boot ~3 s + config ~3 s + commit ~3 s) |
| `build-session.sh --packages-only` | build/refresh just the pkgs image, no session | packages phase only |

So the common loop — *edit one config script, rebuild* — is `build-session.sh --fast` (or just `build-session.sh`, which now skips straight to the config phase whenever the pkgs image is present): **~9 s** measured, versus the **~14 min** a full single-stage install paid before. It re-applies config against the already-installed packages instead of re-installing them. `--rebuild` is unchanged in fidelity: a clean, full repackage. The fast path is **opt-in for fidelity-critical cases** — if you changed a *package* (added/removed a dnf package, edited a spec), use a plain rebuild or `--rebuild` so the pkgs image is regenerated; `--fast` deliberately does not touch packages.

The config stages are safe to re-run on top of an already-packaged filesystem because they're idempotent (`mkdir -p`, symlink, copy). `staged-install.sh`'s `config` phase re-seeds the install-log start marker (the packaging phase that normally prints it ran in a previous container) so `run_logged`/the error handler still behave.

**dnf cache actually persists now (dnf5 path fix).** Fedora 44 ships **dnf5**, whose package cache lives under `/var/cache/libdnf5` — *not* the dnf4 path `/var/cache/dnf`. The build previously mounted the persistent cache volume (and the `Dockerfile.base` BuildKit cache) at `/var/cache/dnf`, so despite `keepcache=True` the volume stayed **empty** (measured: 0 RPMs after a full install, while `/var/cache/libdnf5` held **1.9 GB / 1153 RPMs** that were discarded with the container). Every cold/`--rebuild` packages phase therefore re-downloaded the entire package set (~14 min). Mounting the volume + BuildKit cache at `/var/cache/libdnf5` makes the cache stick, so repeat package builds reuse the downloaded RPMs.

**The RPM repo rebuilds only when a spec changed.** The local omedora RPM repo (walker/elephant/fonts/swayosd/tte) is built by 5 throwaway Fedora containers (~3–4 min total). It used to rebuild on *every* `--rebuild` and never otherwise — so `--rebuild` paid the cost even with unchanged specs, while a default build that edited a spec wrongly kept the stale repo. It now rebuilds iff a `*.spec` / `build-repo.sh` / `build-local.sh` is newer than the built `repodata/repomd.xml` (or the repo is missing); `--rebuild-repo` forces it.

> **Override knobs:** `OMEDORA_SYSTEMD_PKGS_IMAGE` overrides the intermediate image name (defaults to the session image name with a `-pkgs` tag suffix). The existing `OMEDORA_SYSTEMD_BASE_IMAGE`, `OMEDORA_SYSTEMD_SESSION_IMAGE`, `OMEDORA_BUILD_CTR`, and `OMEDORA_DNF_CACHE_VOL` still apply (the cache volume is mounted at the dnf5 path `/var/cache/libdnf5`).

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

`omedora/test/fedora/run-session.sh` (default: interactive):

- **(default)** boots the session image under systemd and `machinectl shell`s into `session-launch.sh`, opening a nested Hyprland window on your desktop with the full Omedora session. Close the window to exit; the runner removes the container and restores the host socket mode. **Working — verified.**
- **`--shell`** — boots systemd and drops you into a `machinectl shell` as omedora (no compositor) for poking around a real logind session.
- **`--rebuild`** — rebuilds the session image (re-runs `build-session.sh`) first.
- **`--keep`** — leaves the container running on exit for inspection.

Scripted `hyprctl`-driven assertions (session smoke, walker open, screenshot) now live in the **[L4-headless automated test suite](#l4-headless-automated-test-suite-omedoratestfedoraheadless)** below — the canonical L4 assertion path (closes the old `smoke-assertions.sh` follow-up, task #45).

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

### L4-headless automated test suite (`omedora/test/fedora/headless/`)

This is the **canonical way to write L4 assertions** — it subsumes the planned `smoke-assertions.sh` (roadmap step 13 / task #45). It boots **one** headless Omedora session (the `--headless` recipe above), then runs a suite of small assertion scripts against it via `hyprctl` / `grim`, in **TAP** style, with **screenshots-on-failure** and a **CI-friendly exit code**. It reuses the L1 TAP primitives (`test/helpers.sh`) so L1 and L4 tests speak the same language.

**Layout**

```
omedora/test/fedora/headless/
├── run-tests.sh        # host orchestrator: boot one session, run the suite, report
├── lib.sh              # sourced by every test (in-container): session env + assertions
├── tests/
│   ├── 00-session.sh   # smoke: Hyprland IPC, ≥1 monitor, waybar/mako/swaybg up
│   ├── 10-walker.sh    # #56 guard: omarchy-launch-walker --dmenu renders a walker layer, ≥20×
│   ├── 20-portals.sh   # xdg-desktop-portal frontend + hyprland/gtk backends active
│   ├── 30-visual.sh    # visual diff: waybar + wallpaper are actually DRAWN (not just running)
│   ├── 40-menu.sh      # golden-image: omarchy control menu (Super+Alt+Space) renders
│   └── 50-launcher.sh  # golden-image: walker app launcher (Super+Space) renders
├── fixtures/
│   ├── 30-visual-reference.png    # committed known-good screenshot (1920×1080) 30-visual diffs against
│   ├── 40-menu-reference.png      # committed golden baseline (1920×1080) 40-menu diffs against
│   └── 50-launcher-reference.png  # committed golden baseline (1920×1080) 50-launcher diffs against
└── .gitignore          # ignores artifacts/
```

**Run it**

```
omedora/test/fedora/headless/run-tests.sh                 # build image if missing, run all tests
omedora/test/fedora/headless/run-tests.sh --rebuild       # rebuild the session image first
omedora/test/fedora/headless/run-tests.sh --test '10-*.sh' # run a subset (glob)
omedora/test/fedora/headless/run-tests.sh --keep          # leave the container up for inspection
```

The orchestrator prints a TAP plan (`1..N`), one `ok`/`not ok` per test, and a `pass`/`fail` summary; it **exits non-zero iff any test failed** (the CI gate). Each run uses a **unique container name** (`omedora-htest-$$`), so two invocations run **concurrently** without colliding (verified — distinct containers, no shared host socket).

> **machinectl-shell exit codes:** `machinectl shell` always exits 0 regardless of the program it ran (it reports the PTY-forwarding result). The orchestrator works around this by having the inner shell write the test's real exit code to a sentinel file in the artifacts dir and reading it back — don't trust `machinectl shell`'s own rc.

**Test-writing convention.** Each `tests/NN-name.sh` is numbered (lower runs first; `00-` smoke first), idempotent, and re-runnable against a live session:

```bash
#!/bin/bash
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
headless_session_env                       # attach: IPC sig + WAYLAND_DISPLAY + uwsm/env PATH
# ... drive the session, then assert (each emits a TAP line):
wait_for_layer walker 5
assert_layer walker "omarchy-menu renders a walker surface"
```

`lib.sh` provides, on top of the shared TAP helpers (`pass`, `fail`, `assert_equals`, `assert_output_contains`, …): `headless_session_env`, `assert_layer`/`wait_for_layer`, `assert_client`/`wait_for_client`, `assert_monitor`, `assert_proc`, `screenshot`, `dump_state`. A failed `assert_*` auto-captures a `grim` screenshot + `hyprctl layers/clients/monitors` dumps + failed-unit list before exiting non-zero.

**Artifacts.** On any failure the orchestrator copies that test's screenshots + state dumps to `omedora/test/fedora/headless/artifacts/<test>/` (git-ignored). A green run writes nothing.

#### `30-visual.sh` — screenshot-diff: the session must *look* right

`00-session.sh` asserts the autostart **processes** are running (`assert_proc waybar/swaybg/mako`). But a process can be alive and **not visually present**: a uwsm app-daemon autostart race has been seen to drop waybar + swaybg from actually *rendering* while the processes (sometimes) still exist — a black screen with no bar and no wallpaper that the process-based test happily passes. `30-visual.sh` exists to catch exactly that **visual-component-missing** class of bug.

**What it checks.** It `grim`s the whole headless output (fixed 1920×1080 — the launcher's headless monitor) and diffs it against a committed reference (`fixtures/30-visual-reference.png`) using the new `assert_screenshot_matches` helper. The metric is ImageMagick `compare -metric AE -fuzz 5%` normalized to a **differing-pixel fraction**; the test passes if **≤ 1.0 %** of pixels differ. This is deliberately *tolerance-based*, not pixel-perfect — the session renders via llvmpipe and we only want the coarse signal "are the big static structures drawn?" Empirically: two captures of the same good session diff at **0.0 %**; a **missing waybar** diffs at **~2.8 %**; a **black/fallback wallpaper** at **~95 %**; a fully-broken (no bar + no wallpaper) session at **~98 %** — so 1 % sits in a wide, robust gap.

**Exclusion-zone approach.** Most of the waybar is time/state-dependent (clock, workspace marker, network/battery icons), so those regions are **masked to solid black in BOTH the reference and the candidate before diffing**. The exclusion list is a small declarative `x,y,w,h # reason` array at the top of `30-visual.sh`; each rectangle is documented with *what* it is and *why*. They were derived from the **real** waybar layout (`config/waybar/config.jsonc`, top bar, height 26 × monitor scale 2.0 = 52 px band) by scanning the captured band for content clusters — not guessed:

| Rectangle (x,y,w,h) | Masked content | Why dynamic |
|---|---|---|
| `20,0,272,52` | left: omarchy menu glyph + `hyprland/workspaces` | active-workspace marker (`󱓻`) + which workspaces are occupied are state-dependent |
| `825,0,285,52` | center: `clock#horizontal` + weather/update/screen-recording/idle/notification-silencing indicators | clock changes every minute; indicators are state-dependent |
| `1645,0,260,52` | right: tray + bluetooth + network + pulseaudio + cpu + battery | network/battery/bluetooth icons + tray are state-dependent |

What's left **unmasked and therefore asserted**: the solid waybar background band across the rest of the top 52 px (proves the bar is drawn — if it's missing, those rows show wallpaper/black) and the **entire** wallpaper region below (proves swaybg painted the real background, not a black fallback).

**Regenerating the reference** (do this only when the UI *legitimately* changes — waybar height, wallpaper, static layout). Boot a session with `run-tests.sh --keep`, attach as `omedora`, and **confirm the components are truly up** — both the `wallpaper` and `waybar` layers must appear in `hyprctl layers` (the autostart race can drop them). If missing, relaunch them as persistent user units before capturing:

```bash
WL=$(hyprctl instances -j | python3 -c 'import sys,json;print(json.load(sys.stdin)[0]["wl_socket"])')
SIG=$(ls -t "$XDG_RUNTIME_DIR/hypr" | head -1)
systemd-run --user --unit=ref-swaybg --setenv=WAYLAND_DISPLAY=$WL --setenv=HYPRLAND_INSTANCE_SIGNATURE=$SIG \
  swaybg -i ~/.config/omarchy/current/background -m fill
systemd-run --user --unit=ref-waybar --setenv=WAYLAND_DISPLAY=$WL --setenv=HYPRLAND_INSTANCE_SIGNATURE=$SIG waybar
makoctl dismiss --all      # clear transient notifications
grim omedora/test/fedora/headless/fixtures/30-visual-reference.png
```

The dynamic content (clock, etc.) in the reference is irrelevant because it's masked. After regenerating, re-check the exclusion rectangles still cover every dynamic cluster (re-scan the band if the layout moved). **Note:** on a *fresh* `run-tests.sh` boot the autostart race (being fixed separately) can leave the session visually broken, in which case `30-visual` correctly reports `not ok` — that is the test doing its job, not a flake.

> **Runner note.** `run-tests.sh` copies `fixtures/` into the container alongside `lib.sh` + `tests/`, so committed reference images are available to the in-container test at `../fixtures/`.

#### `40-menu.sh` / `50-launcher.sh` — golden-image tests for the menus

`40-menu.sh` and `50-launcher.sh` are **golden-image** screenshot tests for the two main walker surfaces:

| Test | Trigger (exactly what the keybind runs) | Bind |
|---|---|---|
| `40-menu.sh` | `setsid uwsm-app -- omarchy-menu` (no arg → `show_main_menu` → `omarchy-launch-walker --dmenu`) | `SUPER + ALT + SPACE` (`o.bind_menu(…, "Omarchy menu", nil)` → `omarchy-menu`) |
| `50-launcher.sh` | `setsid uwsm-app -- omarchy-launch-walker` (no `--dmenu` → the app launcher) | `SUPER + SPACE` (`o.bind(…, { omarchy = "walker" })` → `omarchy-launch-walker`) |

Both are walker layer-surfaces (gtk4-layer-shell, same render path as `10-walker`). Each test triggers the menu the way its bind does, waits for the `walker` layer to map (`wait_for_layer walker 10`), `grim`s the live 1920×1080 output, and diffs it against a committed baseline (`fixtures/40-menu-reference.png`, `fixtures/50-launcher-reference.png`) via `assert_screenshot_matches`. After capturing, each test closes the menu (`walker --close` + kill) and waits for the layer to tear down so it can't leak into a later test — they're idempotent and re-runnable.

**Why golden-image (and a lenient threshold).** These menus are deliberately **high-entropy**: the omarchy menu's option list and the launcher's installed-app list both change legitimately across upstream versions. We accept that on **one explicit condition** — the baseline is **affirmatively regenerated** when a rebase onto a new upstream version changes a menu. So these are golden-image gates, **not** bulletproof pixel diffs: the threshold is **25 %** of pixels (`-fuzz 5%` AE, same metric as `30-visual`), tuned to catch **structural** regressions (menu didn't open / blank or black panel / wrong menu / no walker layer) while tolerating llvmpipe software-render noise **and** the row-by-row churn of menu/app text across versions. Empirically: when the menu renders, two captures of the same good session diff at **~0 %** (verified: 40-menu **0.0000 %**, 50-launcher **0.0126 %**); a plain desktop with **no menu open** diffs at **~95–97 %** (verified: **97.34 %** vs the menu baseline, **95.22 %** vs the launcher baseline). 25 % sits in that wide gap.

**Exclusion zones.** Only the genuinely-nondeterministic bit is masked: each menu's search field carries a **blinking text cursor**, so the one search-field row is masked to black in both ref and candidate (`690,55,320,65` for 40-menu's "Go…" field; `360,180,1000,70` for 50-launcher's "Search…" field — both located by cropping the committed baseline, both well inside the panel). Per the golden-image contract we lean on the **threshold** for the rest of the content variance rather than masking every row.

**Regenerating a baseline — this is the whole point of these tests.** When a rebase changes a menu, `40-menu`/`50-launcher` will go **red on purpose**. That is the test asking a human to look. Do this, in order:

1. **Eyeball the failure.** Open the failed run's artifacts:
   `omedora/test/fedora/headless/artifacts/40-menu/40-menu-candidate.png` (+ `-diff.png`), or the `50-launcher/` equivalents. Confirm the menu **actually rendered** and the change is the expected upstream change. **A blank/black panel is a real regression — do NOT regenerate; fix the regression.**
2. **Confirm the change is intended** (e.g. upstream added/renamed a menu entry, or the installed-app set changed) — i.e. the new look is what you *want* to be the new known-good.
3. **Regenerate + commit the new baseline** from a known-good headless session (never your live desktop — use the headless container):

   ```bash
   export TMPDIR=/var/tmp/podman-tmp
   omedora/test/fedora/headless/run-tests.sh --keep --test '00-*'   # boot a clean 1920×1080 headless session
   CTR=omedora-htest-$(…)   # the container name the runner printed (--keep leaves it up)
   podman exec "$CTR" su - omedora -c '
     export XDG_RUNTIME_DIR=/run/user/1000
     [[ -f $HOME/.config/uwsm/env ]] && source $HOME/.config/uwsm/env
     export HYPRLAND_INSTANCE_SIGNATURE=$(ls -t $XDG_RUNTIME_DIR/hypr | head -1)
     export WAYLAND_DISPLAY=$(hyprctl instances -j | python3 -c "import sys,json;print(json.load(sys.stdin)[0][\"wl_socket\"])")
     # 40-menu: setsid uwsm-app -- omarchy-menu          (50-launcher: omarchy-launch-walker)
     setsid uwsm-app -- omarchy-menu >/dev/null 2>&1 &
     for i in $(seq 1 50); do hyprctl layers -j | grep -q "\"namespace\": \"walker\"" && break; sleep 0.2; done
     sleep 1
     hyprctl layers -j | grep -q "\"namespace\": \"walker\"" || { echo "walker layer MISSING — do not commit"; exit 1; }
     grim /home/omedora/40-menu-reference.png'
   podman cp "$CTR:/home/omedora/40-menu-reference.png" \
     omedora/test/fedora/headless/fixtures/40-menu-reference.png
   podman rm -f "$CTR"
   ```

   **Verify the new baseline visually shows the menu** (not a blank/black panel) before committing it. Commit with a message noting the upstream version it was regenerated for, then re-run `run-tests.sh --test '40-*'` (or `'50-*'`) to confirm green. If the search-field cursor moved (panel geometry changed upstream), re-locate the exclusion rectangle by cropping the new baseline.

> The same affirmative-regenerate procedure is documented inline in each test's header comment, so a contributor who hits the red test sees it at the point of failure.

**CI notes.** Same requirement as `--headless`: a DRM render node (`--device /dev/dri`). GPU-less runners: `sudo modprobe vkms`, then `OMEDORA_RENDER_NODE=/dev/dri/renderD<n>`. Build-once-then-run on a scheduled/on-demand job (the image build is ~15–30 min).

### Workstation-base variant (`--workstation`)

The default L4 base (`Dockerfile.base`) is a *minimal* `fedora:44` (systemd + a few install deps + labwc). But Omedora is installed **on top of an existing Fedora**, in practice **Fedora Workstation** — and that heavier base is where a whole class of *layering* bugs lives that the minimal base can't surface: the `tuned-ppd` vs `power-profiles-daemon` power conflict, `xdg-desktop-portal-gnome` competing with the hyprland portal backend, and the GNOME-as-fallback login coexistence. None of those exist when there's no GNOME at all.

`--workstation` builds + runs the **same** install on a second-tier base that adds the real Workstation package set:

- **`Dockerfile.workstation`** `FROM`s the standard base and `dnf -y group install workstation-product-environment` (GNOME, GDM, NetworkManager, pipewire, the ppd-service provider, `xdg-desktop-portal-gnome`, …). It sets the **container** default target to `multi-user.target` (the automated path launches the session explicitly via `machinectl shell`; GDM can't acquire a seat under rootless podman anyway) but leaves **GDM unmasked/installed** so the login-layer coexistence is real. On bare metal the product keeps `graphical.target` + GDM — this target override is a container-only concession.
- The flag threads through all three entry points (each gets its own `-workstation` image lineage + container name, so a Workstation run and a standard run can run **concurrently**):

  ```bash
  export TMPDIR=/var/tmp/podman-tmp
  omedora/test/fedora/build-session.sh --workstation          # build standard base, layer Workstation, install on top
  omedora/test/fedora/headless/run-tests.sh --workstation      # full suite (00–50) + the 90-workstation coexistence test
  omedora/test/fedora/run-session.sh --workstation --headless  # interactive Omedora/Hyprland session on the Workstation base
  ```

- **`90-workstation.sh`** asserts the coexistence invariants (Workstation set present, both wayland-session entries registered, GDM unmasked, `gnome-shell` launchable, `powerprofilesctl` works while `power-profiles-daemon`'s own daemon is not the active provider, the GNOME portal backend is present). It is **SKIP-gated**: on the standard base (no `gnome-shell`) it emits TAP SKIPs and passes, so the one `tests/` dir serves both runs — a plain `run-tests.sh` shows `90-workstation` as SKIP, `--workstation` runs it for real.

**GNOME fallback.** Omedora's Fedora session install is *additive* (`install/config/wayland-session-fedora.sh` keeps the existing DM and only drops the `omedora.desktop` session entry), so on real hardware **GDM offers both "GNOME" and "Omedora"** and you can log out of Hyprland into GNOME at will (GDM remembers your last pick — Omedora forces no default). The real **greeter/session-picker UX is an L4-VM thing** (it needs a real seat + DRM master the rootless container can't give). The container stand-in is **`run-session.sh --workstation --gnome`**, which nests GNOME Shell (Mutter `--nested`) into labwc instead of Hyprland (`OMEDORA_HEADLESS_SESSION=gnome`) — best-effort/interactive, proving GNOME runs and is reachable, not golden-imaged.

**Expected power outcome / possible real finding.** On Fedora 41+, Workstation's default ppd-service is **`tuned-ppd`**, which is exactly what Omedora's skip-PPD + shim design (`install/packages/fedora.toml` `[power-profiles-daemon]`) targets — so the `--workstation` install should be **conflict-free** and `90-workstation` green. If the group instead pulls `power-profiles-daemon`, the Omedora packages phase aborts on the mutual `Conflict` (there is **no** `dnf swap`/`--allowerasing` today) — a genuine finding this variant exists to catch, fixed separately (e.g. a Fedora-gated `dnf swap`).

**Cost.** The Workstation base is ~1.5–2 GB; it's cached as an image layer and shares the dnf5 cache volume with the standard base, so it's a one-time cost. The variant is **opt-in** — never built or run unless you pass `--workstation`.

### Vanilla / piggyback Hyprland path (`raw-hyprland-test.sh`)

The Hyprland packaging split ships four packages from COPR `agaspar/omedora-3.8.2`: `hyprland-no-session` (all binaries, no session entry), `hyprland` (the natural/discoverable full package — owns the plain `wayland-sessions/hyprland.desktop`, `Requires hyprland-no-session`), `hyprland-uwsm`, and `hyprland-devel`. Omedora itself installs `hyprland-omedora` (its own uwsm session). But a **piggybacker** — someone on plain Fedora who just wants Hyprland — runs `dnf install hyprland` and expects a working *vanilla* session with Hyprland's built-in defaults, no omedora config and no uwsm. **`omedora/test/fedora/raw-hyprland-test.sh`** is a standalone L4 test that proves exactly that.

It is self-contained (does **not** use the omedora session image): it builds its own minimal `fedora:44` systemd image whose only desktop bit is **labwc** (the headless nesting host, same role as in the omedora headless launcher) plus a login user, then **inside** that container:

1. `dnf copr enable agaspar/omedora-3.8.2` + `dnf install -y hyprland`, and asserts the resolution held: `rpm -q hyprland hyprland-no-session` both present, `/usr/share/wayland-sessions/hyprland.desktop` owned by the **full** `hyprland` package (not the binaries one), and `/usr/bin/{Hyprland,start-hyprland,hyprctl}` owned by `hyprland-no-session`.
2. Launches **raw Hyprland** — `start-hyprland` directly via plain `systemd-run --user` (so it survives the `machinectl shell` returning), nested into labwc's socket via Aquamarine's `wayland` backend (`AQ_BACKENDS=wayland`). Crucially **no uwsm, no `~/.config/hypr`, no seeded config**: `HYPRLAND_CONFIG` points at an empty file so Hyprland uses its compiled-in defaults. (uwsm isn't even installed.)
3. Asserts it reasonably started: `hyprctl version` answers, `hyprctl monitors -j` shows ≥1 monitor (an explicit headless output, same promotion technique as the omedora launcher), **no `Safe Mode` in the log**, and the `Hyprland` process is alive.

Run it (host is Arch → podman `fedora:44`; needs a DRM render node like the headless suite):

```bash
export TMPDIR=/var/tmp/podman-tmp
omedora/test/fedora/raw-hyprland-test.sh            # build vanilla image if missing, then run
omedora/test/fedora/raw-hyprland-test.sh --keep     # leave the container up to poke at
omedora/test/fedora/raw-hyprland-test.sh --rebuild  # rebuild the vanilla image first
```

It validates `hyprland-no-session` is self-sufficient as the binaries package **and** that `dnf install hyprland` yields a working default session — the piggybacker contract — independently of anything omedora installs. (On GPU-less CI, `modprobe vkms` + `OMEDORA_RENDER_NODE=/dev/dri/renderD<n>` as for the headless suite.)

### Why this *can now* be in CI

The original blocker was "GitHub Actions runners are headless — no compositor to nest under." `--headless` removes that: the container brings its own compositor. The remaining requirement is a **DRM render node**, satisfied on GPU-less runners by loading **`vkms`** (`sudo modprobe vkms` in a CI step, then `OMEDORA_RENDER_NODE=/dev/dri/renderD128`). The systemd image build (~15–30 min) is still at the upper edge of practical CI runtime, so the pragmatic plan is a **scheduled / on-demand** CI job (not every push) that builds once, caches the image, and runs the `--headless` smoke. The earlier Xvfb + `x11`-backend idea is unnecessary.

### File layout

```
omedora/test/fedora/
├── Dockerfile              # L2/L3 base (docker)
├── integration.sh          # L2
├── smoke.sh                # L3 (audit)
├── omedora-session/        # L4-nested (podman, systemd)
│   ├── Dockerfile.base               # FROM fedora:44; systemd + deps + omedora tree (+ labwc for --headless); CMD /sbin/init
│   ├── Dockerfile.workstation        # FROM the base + workstation-product-environment (the --workstation variant)
│   ├── session-launch.sh             # in-container: nests Hyprland under the HOST compositor
│   ├── session-launch-headless.sh    # in-container: starts labwc + nests Hyprland (or GNOME, via OMEDORA_HEADLESS_SESSION) into it
│   └── session-launch-common.sh      # shared uwsm-start setup for both launchers
├── headless/               # L4-headless automated test suite (TAP, screenshots-on-fail, CI gate)
│   ├── run-tests.sh                  # host orchestrator: boot one session, run tests/, report (--workstation for the WS base)
│   ├── lib.sh                        # in-container: session env + headless assertions
│   ├── tests/                        # NN-name.sh assertion scripts (00-session, 10-walker, …, 90-workstation [SKIP-gated])
│   └── .gitignore                    # ignores artifacts/
├── raw-hyprland-test.sh    # standalone L4: vanilla `dnf install hyprland` (COPR) boots a DEFAULT Hyprland session (no omedora/uwsm)
├── build-session.sh        # boot base under systemd, install via machinectl shell, commit (--workstation for the WS base)
├── run-integration.sh      # L2 host-side runner
├── run-smoke.sh            # L3 host-side runner
└── run-session.sh          # L4-nested runner: --shell | --rebuild | --keep | --workstation | --gnome
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

Builds `omedora/test/fedora/Dockerfile`, mounts the repo, runs `omedora/test/fedora/integration.sh`. Caches `/var/cache/dnf` keyed on `omedora/test/fedora/Dockerfile` SHA. Runtime typically 2-5 minutes warm.

### `fedora-smoke` (slow, gated)

Same Dockerfile, runs `omedora/test/fedora/smoke.sh`. Triggered by:

- `schedule: '0 6 * * *'` (nightly at 06:00 UTC)
- Pull requests carrying the `smoke` label

Runtime 10-30 minutes. Not on every PR.

### What we do NOT add to CI

- L4-nested (local-only — see [§6](#6-l4-nested-container-design)).
- Coverage reporting (no useful signal for shell + container tests).
- Cross-version Fedora matrix until Fedora N+1 release prep (then we add F45 alongside F44).
- Cross-arch matrix (x86_64 only for the foreseeable future; matches Omarchy upstream).

---

## 9. L4-VM real-VM pipeline

> **Now scripted + unattended.** The L4-VM tier is an automated pipeline at
> [`omedora/test/fedora/vm/`](../test/fedora/vm/) (see its
> [`README.md`](../test/fedora/vm/README.md) for the full architecture). One
> command — `omedora/test/fedora/vm/run-vm-test.sh` — provisions a **real Fedora
> 44 Workstation VM** (rootless `qemu:///session` libvirt + KVM, cloud-init,
> passt networking, **no host sudo**), installs Omedora **from the live COPR**
> (`install.sh`, `OMARCHY_NONINTERACTIVE=1`), boots the Omedora/Hyprland session
> via **GDM autologin** on a real seat, and runs the **same L4-headless TAP
> suite** over that real session (session-attach via `XDG_RUNTIME_DIR`) plus a
> real-framebuffer `virsh screenshot`. It asserts the packages came **from the
> COPR** (`%{from_repo}`), the `omedora.desktop` entry is owned by
> `hyprland-omedora`, GNOME stays selectable, and the install log is clean.
> Resources are named `omedora-vmtest-*` and self-clean; the user's VMs are never
> touched.
>
> **Not a CI gate** (nested virt on GitHub runners has no KVM → TCG is
> impractically slow); it's a local / self-hosted-runner **before-each-release**
> gate. See the README's "CI assessment".

The narrower **manual checklist** below remains the fallback for the residue the
scripted pipeline doesn't yet automate (notably the GDM *greeter UX* of picking
"Omedora" by hand, real-hardware install paths, and SELinux denial review):

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
| 6 | ✅ shipped | L2 + CI bring-up | `omedora/test/fedora/Dockerfile`, `omedora/test/fedora/integration.sh`, `omedora/test/fedora/lib/container.sh`, `.github/workflows/test.yml`, `omedora/test/fedora/run-integration.sh` | After this, every PR is regression-tested. |
| 7 | ✅ shipped | L3 smoke (audit-only) | `omedora/test/fedora/smoke.sh`, `install/preflight/fedora-repos.sh`, `omedora/test/fedora/run-smoke.sh`, scheduled job in CI | Audits the package map against real dnf; does NOT yet run install.sh end-to-end. |
| 8 | ✅ shipped | **Install-pipeline gating** (preflight + orchestrator) | `install.sh` (Arch gate around `login/` and `post-install/`), `install/preflight/guard.sh` (Fedora arm), `install/preflight/pacman.sh`, `install/preflight/disable-mkinitcpio.sh`, `install/preflight/all.sh` (source `fedora-repos.sh` on Fedora) | Unblocks running `install.sh` against `fedora:44` end-to-end. |
| 9 | ✅ shipped | **Install-pipeline gating** (system-admin scope) | Arch-only gate on `install/config/all.sh` system-admin block (gpg, login, hardware, network, power, security, services, sudoers); per-script guards on `mimetypes.sh`, `theme.sh`, `nvim.sh`, `mise-work.sh` | System-admin concerns (sysctl, sudoers, /etc, systemd units) are the user's Fedora install's job — see [`architecture.md` §6](architecture.md#6-install-pipeline-gating). |
| 10 | planned | **Bulk-fill the package map** | `install/packages/fedora.toml` (add entries for the ~30 unmapped packages the L3 audit currently surfaces) | The L3 audit's "unmapped + dnf MISSES" list is the punch list. Many entries currently `source = "skip"`. |
| 11 | planned | **Wayland session entry** + Fedora-side config script | `default/wayland-sessions/omedora.desktop` (new), `install/config/wayland-session-fedora.sh` (new), wired into `install/config/all.sh` | The session entry the display manager picks up — used by L4-VM and (cosmetically) by L4-nested. |
| 12 | ✅ shipped | **L4-nested image + runner (systemd)** | `omedora/test/fedora/omedora-session/Dockerfile.base` (FROM fedora:44, systemd + tree), `omedora/test/fedora/build-session.sh` (boot+install+commit), `omedora/test/fedora/omedora-session/session-launch.sh`, `omedora/test/fedora/run-session.sh` (podman `--systemd=always`) | Verified: real PID-1 systemd boots, install runs in a logind session (Flatpaks install), nested Hyprland brings up the full autostart chain. Supersedes the earlier shimmed image (no-init + systemctl/uwsm-app shims) — those are deleted. |
| 13 | ✅ shipped | **L4-headless automated test suite** (was `smoke-assertions.sh`; closes #45) | `omedora/test/fedora/headless/run-tests.sh`, `omedora/test/fedora/headless/lib.sh`, `omedora/test/fedora/headless/tests/{00-session,10-walker}.sh`, `omedora/test/fedora/headless/.gitignore` | TAP suite over a headless session: `00-session` (IPC, monitor, autostart) + `10-walker` (#56 regression guard, ≥20 walker opens). Screenshots-on-failure, unique-named containers (parallelizable), exits non-zero iff any test fails. The canonical L4 assertion path — see [the suite section](#l4-headless-automated-test-suite-omedoratestfedoraheadless). |
| 14 | ✅ shipped | **L4-headless Workstation-base variant** | `omedora/test/fedora/omedora-session/Dockerfile.workstation`, `--workstation` on `build-session.sh`/`run-session.sh`/`headless/run-tests.sh`, `--gnome` + `OMEDORA_HEADLESS_SESSION` in `run-session.sh`/`session-launch-headless.sh`, `omedora/test/fedora/headless/tests/90-workstation.sh` | Build+test the install on a real Fedora Workstation base (`workstation-product-environment`) to surface layering conflicts (power/portal) the minimal base hides, and verify the GNOME-as-fallback login coexistence. Opt-in; `90-workstation` SKIPs off-Workstation. See [the variant section](#workstation-base-variant---workstation). |
| 15 | deferred | VM smoke harness (optional) | `scripts/vm-smoke.sh` (new) | Deferred per user; lands if/when manual L4-VM workflow gets repetitive enough to automate. |

Implementation commits should land tests **with** their corresponding code, not in batches. A package-helper patch arrives with the helper test that proves it. This is TDD-ish in spirit but pragmatic — we're not strict about tests-first vs code-first within a commit.

---

## 11. Cross-links

- [`architecture.md` §15](architecture.md#15-patch-stack-map) — the patch-stack map's "Testing" row group lists every file this doc references (with `(planned)` annotations on files not yet on disk).
- [`architecture.md` §6](architecture.md#6-install-pipeline-gating) — the install-pipeline gating that L4-nested depends on.
- [`AGENTS.md`](AGENTS.md) — the "Verification before merge" rule points back here. Reading both is required for agents working on this fork.
- [`rebase-workflow.md`](rebase-workflow.md#4-verification-matrix) — the verification matrix complements this strategy; the matrix says *what to verify after a rebase*, this doc says *how the verification is structured*.
- [`packages.md`](packages.md) — defines the package-map TOML schema that `omarchy-dev-validate-fedora-packages` (per [§4](#4-test-style-conventions)) enforces.
