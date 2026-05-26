# Testing

This doc is the canonical strategy for testing omedora. It defines a four-layer pyramid (shell unit → Fedora container integration → Fedora container smoke → VM full desktop), what's testable where, the conventions for writing new tests, the container design, the CI workflow shape, the manual VM checklist, and the implementation roadmap for the test infra itself.

For the higher-level architecture this strategy serves, see [`architecture.md`](architecture.md). For agent-facing rules that reference this doc, see [`AGENTS.md`](AGENTS.md).

> **Status:** L1, L2, L3 (audit-only), the CI workflow, install-pipeline gating, and L4-nested are **shipped** — see roadmap [§10](#10-implementation-roadmap) for the per-step status. L4-nested boots a real Omedora session inside `fedora:44` via Wayland-on-Wayland nesting; the install pipeline runs end-to-end and Hyprland accepts wayland clients in the nested compositor. Follow-ups: bulk-fill the package map (step 10) and `smoke-assertions.sh`. L4-VM is documented but operates manually.

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

The L4-nested image runs a full Omedora session inside a Fedora container. It depends on the install-pipeline gating (see [§10](#10-implementation-roadmap) and [`architecture.md` §6](architecture.md#6-install-pipeline-gating)) because it executes `install.sh` end-to-end against `fedora:44` — so until that lands, this layer can't be built.

### Image layout

Two-stage build, on top of the L2/L3 base:

1. **Stage 1 — install Omedora.** `FROM omedora-test:fedora44`, `git clone` (or bind-mount) the omedora repo, run `bash install.sh` as the non-root `omedora` user with sudoers preconfigured. The install pipeline must complete (preflight + packaging + config; login/post-install gated off). At the end of stage 1, the image looks like a freshly-installed omedora system: `~/.config/` populated, all Hyprland-ecosystem packages installed, the Wayland session entry at `/usr/share/wayland-sessions/omedora.desktop`.
2. **Stage 2 — boot the session.** The default CMD launches Hyprland via the same `AQ_BACKENDS=wayland` nesting trick documented in the sibling research. UWSM is used as the session manager exactly as a real user would experience.

Build product: `omedora-test:fedora44-session` (planned).

### The Wayland-on-Wayland nesting trick

Hyprland normally talks to KMS/DRM directly via the `drm` backend. That doesn't work inside a container — DRM requires real hardware access + seat permissions + getty-style setup. The `wayland` backend instead makes Hyprland a *Wayland client* of an existing compositor: it opens a window on the host's compositor and renders inside it.

The pieces needed at run-time:

| Need | How |
| --- | --- |
| Host Wayland socket reachable inside container | Bind-mount `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY` to a known path in the container; set the container-side `WAYLAND_DISPLAY` to point at it |
| `XDG_RUNTIME_DIR` set + writable | Container creates `/tmp` with mode 0700 and exports `XDG_RUNTIME_DIR=/tmp` |
| Hardware-accelerated rendering | `--device /dev/dri` + `--group-add $(getent group render | cut -d: -f3)` + same for video |
| Environment hints | `AQ_BACKENDS=wayland`, `WLR_BACKENDS=wayland`, `XDG_SESSION_TYPE=wayland` |
| Hyprland refuses to run as root | The omedora user (uid 1000) provisioned by the base image is used; never the container's root |

### Run modes

The host-side launcher (`test/fedora/run-session.sh`, planned) selects mode via flags:

- **`--interactive`** (default for local dev): drops you into a nested Hyprland window. You poke around, use walker, switch themes, take screenshots, exit when satisfied. **Working** — verified.
- **`--smoke`**: runs Hyprland in background, drives it via `hyprctl`, asserts on state. Exits cleanly. Still opens a transient window on the host because we're using the wayland backend. **Plumbing working**; `smoke-assertions.sh` is a follow-up.
- **`--headless`** (CI-friendly): wraps Hyprland in Xvfb so there's no host display dependency. Uses the `x11` backend instead of `wayland`. Same hyprctl-driven assertions. **Not yet wired** — Hyprland 0.55.2 from lionheartp COPR doesn't expose an `AQ_BACKENDS=headless` aquamarine backend (see [§7](#7-container-test-gotchas) gotcha), so the Xvfb path is the actual CI target.

### What L4-nested asserts (via `hyprctl`)

Sample assertions a smoke run would check:

- Hyprland reaches IPC ready within N seconds (`HYPRLAND_INSTANCE_SIGNATURE` socket appears)
- `hyprctl version` returns expected version
- `hyprctl monitors` shows at least one monitor (the nested fake screen)
- waybar process is running and produces output on its IPC socket
- mako process is running; `notify-send "test"` produces a notification
- `omarchy theme set tokyo-night` exits 0 and the waybar / terminal CSS files under `~/.config/omarchy/current/` reflect the theme name
- `omarchy theme set everforest` reverts; assertions repeat
- `hyprctl dispatch exec foot` produces a new client in `hyprctl clients`
- `omarchy capture screenshot fullscreen save` writes a PNG file
- `hyprctl getoption …` confirms key config values are loaded from omedora's real `config/hypr/`

### Why this isn't in CI (today)

GitHub Actions Linux runners are headless — they don't run a Wayland compositor. The `wayland` backend therefore won't work unmodified. The `--headless` (Xvfb + x11) mode IS CI-runnable, but Xvfb adds complexity and the test-image build time (~15–30min cold) is at the upper edge of practical CI runtime. Initial scope: **L4-nested is local-only**; CI keeps L1/L2/L3. If we hit a point where compositor-level regressions are bypassing pre-merge review, we revisit.

### File layout

```
test/fedora/
├── Dockerfile              # L2/L3 base
├── integration.sh          # L2
├── smoke.sh                # L3 (audit)
├── omedora-session/        # NEW (L4-nested) — planned
│   ├── Dockerfile          # FROM omedora-test:fedora44, runs install.sh
│   ├── boot-session.sh     # container-side: launches Hyprland (interactive|smoke|headless)
│   └── smoke-assertions.sh # hyprctl-driven assertions
├── run-integration.sh      # L2 host-side runner
├── run-smoke.sh            # L3 host-side runner
└── run-session.sh          # NEW — L4-nested host-side runner; --interactive|--smoke|--headless|--rebuild|--shell
```

---

## 7. Container-test gotchas

Specific friction points worth knowing about before writing tests:

| Gotcha | Mitigation |
| --- | --- |
| **SELinux context differs.** Container is `container_t`, real install is `user_t`. Most omedora ops are identical in both; some (writing outside `/etc/yum.repos.d/`) may differ. | Catch user_t-specific issues at L4. Don't write L2 tests that depend on user_t policy. |
| **No systemd PID 1.** `systemctl status foo.service` returns nothing meaningful. | Use `podman --systemd=true` for the rare test that needs it. Otherwise defer to L4. |
| **Default user is root.** Sudo is a no-op. Hides bugs in the sudo path. | L3 smoke runs as non-root with sudoers preconfigured. L2 tolerates the simplification. |
| **dnf metadata is slow first time** (~10-30s cold). | Cache `/var/cache/dnf` aggressively. |
| **COPR metadata** lives in dnf cache once enabled. Re-enabling doesn't re-fetch — just appends. | Pre-enable in the image. Skip the enable step in tests that don't specifically test enablement. |
| **Flatpak inside container is fiddly** — wants polkit, runtimes are huge. | Mock at L2 (record `flatpak install` args, exit 0). Exercise real flatpak at L4. |
| **`omarchy-update-restart`** uses `pacman -Qo` for kernel detection. Pacman isn't in Fedora containers. | The Fedora-arm patch lives on the patch-stack map. Until it lands, the test that runs `omarchy-update-restart` on Fedora will fail. That's a feature: the test is the forcing function. |
| **Network from CI runners.** GitHub Actions can reach `dl.fedoraproject.org`, `copr.fedoraproject.org`, `dl.flathub.org`. Bandwidth is fine. | If we hit rate limits on COPR, add backoff/retry to the test script. Not a current concern. |
| **grim against the nested wayland-N socket hangs.** When Hyprland uses the `wayland` aquamarine backend, the wlr-screencopy protocol doesn't complete cleanly inside the nested compositor — `grim` from inside the container blocks indefinitely. | Drive smoke assertions via `hyprctl` only (clients, monitors, getoption). If a screenshot is genuinely needed, capture the nested *window* from the host with `grim -g <geometry>` against the host compositor. |
| **`AQ_BACKENDS=headless` fails** on Hyprland 0.55.2 (lionheartp COPR build): `CBackend::create() failed!` — the headless aquamarine backend isn't built in. | Use the `wayland` backend (interactive/smoke modes) for local dev. For CI, wrap with Xvfb + `AQ_BACKENDS=x11` (planned). |

---

## 8. CI workflow shape

`.github/workflows/test.yml` defines four parallel jobs on push and pull_request. **L4-nested is not in CI** (no host Wayland on GitHub runners; Xvfb-wrapped headless mode is technically possible but the image build cost makes it impractical for every PR).

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
| 12 | ✅ shipped | **L4-nested image + runner** | `test/fedora/omedora-session/Dockerfile` (FROM omedora-test:fedora44, runs install.sh), `test/fedora/omedora-session/boot-session.sh`, `test/fedora/omedora-session/systemctl-shim.sh`, `test/fedora/run-session.sh` | Verified: nested Hyprland 0.55.2 boots inside `fedora:44`, accepts wayland clients (`hyprctl clients` lists `foot`). `smoke-assertions.sh` is a follow-up. |
| 13 | deferred | VM smoke harness (optional) | `scripts/vm-smoke.sh` (new) | Deferred per user; lands if/when manual L4-VM workflow gets repetitive enough to automate. |

Implementation commits should land tests **with** their corresponding code, not in batches. A package-helper patch arrives with the helper test that proves it. This is TDD-ish in spirit but pragmatic — we're not strict about tests-first vs code-first within a commit.

---

## 11. Cross-links

- [`architecture.md` §15](architecture.md#15-patch-stack-map) — the patch-stack map's "Testing" row group lists every file this doc references (with `(planned)` annotations on files not yet on disk).
- [`architecture.md` §6](architecture.md#6-install-pipeline-gating) — the install-pipeline gating that L4-nested depends on.
- [`AGENTS.md`](AGENTS.md) — the "Verification before merge" rule points back here. Reading both is required for agents working on this fork.
- [`rebase-workflow.md`](rebase-workflow.md#4-verification-matrix) — the verification matrix complements this strategy; the matrix says *what to verify after a rebase*, this doc says *how the verification is structured*.
- [`packages.md`](packages.md) — defines the package-map TOML schema that `omarchy-dev-validate-fedora-packages` (per [§4](#4-test-style-conventions)) enforces.
