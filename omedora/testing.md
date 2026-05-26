# Testing

This doc is the canonical strategy for testing omedora. It defines a four-layer pyramid (shell unit → Fedora container integration → Fedora container smoke → VM full desktop), what's testable where, the conventions for writing new tests, the container design, the CI workflow shape, the manual VM checklist, and the implementation roadmap for the test infra itself.

For the higher-level architecture this strategy serves, see [`architecture.md`](architecture.md). For agent-facing rules that reference this doc, see [`AGENTS.md`](AGENTS.md).

> **Status:** this doc defines the plan. Most of the files it references — `test/helpers.sh`, the L1 test files, `test/mocks/`, `test/fedora/`, `bin/omarchy-dev-validate-fedora-packages`, `.github/workflows/test.yml` — do **not** yet exist. They land in subsequent commits per the roadmap in [§9](#9-implementation-roadmap-deferred). Until then, omedora's only test is upstream's `test/omarchy-cli-test.sh`.

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

## 2. The four-layer pyramid

| Layer | Where | Runtime | What it covers | When it runs |
| --- | --- | --- | --- | --- |
| **L1 Shell unit** | Any host (Arch, Fedora, Linux CI) | < 5s total | Dispatcher rendering with brand shim, `omarchy-distro` detection with mocked `/etc/os-release`, package-helper dispatch with mocked `dnf`/`rpm`, `install/packages/fedora.toml` schema validation | Every PR (CI) + pre-commit |
| **L2 Fedora container integration** | `fedora:44` container | 30s–5min per test | Real `dnf install` of small package sets, COPR enable, package-map name translation against real `rpm -q`, update-flow staging with fixture markers, migration runner with fixture migrations, kernel-detection on real Fedora kernels | Every PR (CI) |
| **L2 Arch regression** | `archlinux:latest` container | ~30s | Upstream's `test/omarchy-cli-test.sh` passes unchanged; brand shim defaults to "omarchy" on Arch; helpers' Arch arms behave exactly like upstream | Every PR (CI) — **dual-distro contract enforcement** |
| **L3 Fedora smoke** | `fedora:44` container | 10–30min | Full install pipeline from a fresh container; all `omarchy-base.packages` resolve; all COPRs enable; source installers complete; configs land in `$HOME` | Nightly + `smoke` label on PR |
| **L4 VM full-DE** | `fedora44-dev` libvirt VM, revert to `baseline-clean` snapshot | ~10min install + manual checklist | Real Hyprland session boot, live theme switching with running waybar/mako/walker, keybindings, screenshot, hyprlock, display-manager session pickup, real hardware enumeration, SELinux user_t behavior | Before each omedora release; on visually risky patches |

**Critical: the L2 Arch regression job is non-negotiable.** Without it, the additive abstraction in [`architecture.md`](architecture.md) leaks silently — a contributor edits a shared helper, the Fedora arm gets tested, the Arch arm rots, and we don't find out until an Arch user files a bug. Run it every PR.

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

### Needs L4 (VM only)

| Surface | Why L4 |
| --- | --- |
| Hyprland actually starting and rendering | Needs a real Wayland compositor and DRM; no container does this |
| Live theme switching with running waybar/mako/walker | Needs a running compositor + IPC sockets |
| Display manager session pickup ("Omedora" in GDM/SDDM) | Needs a real DM running and reading wayland-sessions |
| Real hardware enumeration | `lspci` / `/sys/class/dmi/` in containers reflect container view, not real hardware |
| SELinux `user_t` interactions | Containers run `container_t`; user_t policy differs |
| `systemctl --user` services | Containers don't run a user session bus by default |
| Reboot / kernel-update prompts | `omarchy-update-restart` heuristics need a real running kernel |
| The actual user-session login experience | Self-evident |

The point of this split is to **prevent contributors from dumping L4 tests into L2** (or vice versa). When you're tempted to "just write a test for theme switching in the container," remember: the container doesn't have a compositor. That test belongs at L4.

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

## 5. Container design

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

## 6. Container-test gotchas

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

---

## 7. CI workflow shape

A future `.github/workflows/test.yml` (planned) defines four parallel jobs on push and pull_request:

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

- Coverage reporting (no useful signal for shell + container tests).
- Cross-version Fedora matrix until Fedora N+1 release prep (then we add F45 alongside F44).
- Cross-arch matrix (x86_64 only for the foreseeable future; matches Omarchy upstream).

---

## 8. Manual VM workflow (L4)

Per [the deferral decision](#9-implementation-roadmap-deferred), no automation ships in this commit. The manual checklist:

### Setup

The `fedora44-dev` libvirt VM is configured per the user's reference notes. Default credentials: `oman` / `password`. Snapshot anchor: `baseline-clean`.

### Per-release smoke

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

### Smoke checklist (in the Omedora session)

- [ ] Super key opens walker
- [ ] Waybar renders with correct workspaces, clock, system tray
- [ ] `notify-send "test"` shows a mako notification
- [ ] `omarchy theme set tokyo-night` switches theme; terminal, waybar, walker reload
- [ ] `omarchy theme set everforest` reverts cleanly
- [ ] `omarchy capture screenshot region` runs slurp+grim, produces a file
- [ ] `omarchy show logo` renders OMEDORA (not OMARCHY)
- [ ] Tab-complete works for both `omarchy<TAB>` and `omedora<TAB>`
- [ ] `omedora --version` shows the right two-line banner
- [ ] `omedora update` runs to completion with no spurious errors
- [ ] Log out → Omedora session reappears in the picker → log back in cleanly

### Documenting regressions

If anything in the checklist fails, capture a screenshot (or terminal output for non-visual failures) and reference the upstream commit + omedora commit in the bug report. Revert the snapshot when done so the next test starts clean.

### Sudo etiquette

Per a persistent user preference, **Claude never invokes sudo via the Bash tool** — even with passwordless sudo configured. Tests that need root *inside a container* are fine (the container itself runs as root; no privilege escalation). Tests that need root *on the host* are not; the test script prints the exact command, waits, and resumes after the human runs it. The L4 VM workflow is interactive by design — the human is already at the keyboard.

---

## 9. Implementation roadmap (deferred)

The test infra lands in subsequent commits in this order. Each is independently rebasable and small enough to review in one pass.

| Step | Commit | Files | Notes |
| --- | --- | --- | --- |
| 1 | Extract test helpers | `test/helpers.sh` (new), `test/omarchy-cli-test.sh` (edit) | Mechanical extraction. Largest rebase risk in this whole roadmap because it patches an upstream file. |
| 2 | Distro detection + L1 test | `bin/omarchy-distro` (new), `test/distro-test.sh` (new) | Test and command land together since the test needs the command. |
| 3 | Brand shim + assertions | `bin/omarchy` (edit), `bin/omedora` (symlink), `bin/omarchy-version` (edit), assertions in `test/omarchy-cli-test.sh` | The CLI rebrand from [`architecture.md` §10](architecture.md#10-cli-rebrand-tactical). |
| 4 | Package helpers + L1 test | `bin/omarchy-pkg-*` (edits), siblings `*-fedora` (new), `test/mocks/{dnf,rpm,pacman,flatpak}` (new), `test/pkg-helper-test.sh` (new) | The biggest helper change. |
| 5 | Package map validator | `install/packages/fedora.toml` (new), `bin/omarchy-dev-validate-fedora-packages` (new), `test/pkg-map-test.sh` (new) | Includes a starter set of map entries (renames, COPR for hyprland, a few skips). |
| 6 | L2/CI bring-up | `test/fedora/Dockerfile` (new), `test/fedora/integration.sh` (new), `test/fedora/lib/*.sh` (new), `test/fedora/fixtures/*` (new), `.github/workflows/test.yml` (new) | Second-largest of the implementation commits. After this lands, every subsequent PR is regression-tested. |
| 7 | L3 smoke | `test/fedora/smoke.sh` (new), schedule trigger in `test.yml` | Latest because it depends on most of the above being in place. |
| 8 | VM smoke harness (optional) | `scripts/vm-smoke.sh` (new) | Deferred per user; lands if/when manual workflow gets repetitive enough to automate. |

Implementation commits should land tests **with** their corresponding code, not in batches. A package-helper patch arrives with the helper test that proves it. This is TDD-ish in spirit but pragmatic — we're not strict about tests-first vs code-first within a commit.

---

## 10. Cross-links

- [`architecture.md` §15](architecture.md#15-patch-stack-map) — the patch-stack map's "Testing" row group lists every file this doc proposes (with `(planned)` annotations until they exist).
- [`AGENTS.md`](AGENTS.md) — the "Verification before merge" rule points back here. Reading both is required for agents working on this fork.
- [`rebase-workflow.md`](rebase-workflow.md#4-verification-matrix) — the verification matrix complements this strategy; the matrix says *what to verify after a rebase*, this doc says *how the verification is structured*.
- [`packages.md`](packages.md) — defines the package-map TOML schema that `omarchy-dev-validate-fedora-packages` (per [§4](#4-test-style-conventions)) enforces.
