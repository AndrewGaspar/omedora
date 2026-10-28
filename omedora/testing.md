# Testing

Omedora uses four verification layers. Results are reported by layer; passing a
lower layer never implies a higher one passed.

## 1. Layers

| Layer | Environment | Scope |
| --- | --- | --- |
| L1 | Any Linux development host | Shell units, static package/spec checks, migration gates, CLI metadata, and byte identity |
| L2 | Fedora (44, 45) and Arch containers | Real distro tooling, Fedora integration, and upstream Arch regression |
| L3 | Fedora container or clean Fedora system | Fresh package/install and release-upgrade flows |
| L4 | Nested full session and Fedora Workstation VM | Compositor, Quickshell, portals, GDM, SELinux, hardware, and visual goldens |

### Fedora release selection

Omedora supports Fedora 44 and Fedora 45. Every Fedora runner (L2, L3, L4, VM,
and `packaging/copr/build-{local,repo}.sh`) honors one knob,
`OMEDORA_FEDORA_RELEASE` (default `44`), resolved by
`omedora/test/fedora/lib/release.sh`:

```bash
OMEDORA_FEDORA_RELEASE=45 omedora/test/fedora/run-integration.sh
```

| Resource | Fedora 44 (default) | Fedora N ≠ 44 |
| --- | --- | --- |
| Base image | `registry.fedoraproject.org/fedora:44` | `…/fedora:N` (Dockerfile `FEDORA_RELEASE` build arg) |
| L2/L3 image | `omedora-test:fedora44` | `omedora-test:fedoraN` |
| L4 images | `omedora-test:fedora44-session-4*` | `omedora-test:fedoraN-session-4*` |
| dnf cache volumes | `omedora-dnf-cache`, `omedora-rpmbuild-dnf-cache` | the same with `-fN` |
| Local RPM build | `packaging/copr/output/`, `packaging/copr/repo/` | `output-fN/`, `repo-fN/` |
| VM base image | pinned `Fedora-Cloud-Base-Generic-44-1.7` | pinned GA if listed, else cached, else newest nightly |
| VM domain / SSH port | `omedora-vmtest` / 2222 | `omedora-vmtest-fN` / 2222+N−44 |

Fedora 44 keeps the names the harness used before the knob existed, so cached
images, volumes and local repos stay valid. fc44 and fc45 RPMs never share a
local repo. Explicit overrides (`OMEDORA_TEST_IMAGE`, `OMEDORA_SYSTEMD_*`,
`OMEDORA_RPMBUILD_IMAGE`, `OMEDORA_VM_BASE_URL`, …) still win. The VM image
lookup is documented in `omedora/test/fedora/vm/base-image.sh`; add each
release's GA image to its pin table once it is published.

Release gates run on both supported releases:

| Gate | Fedora 44 | Fedora 45 |
| --- | --- | --- |
| L2 `run-integration.sh` | required | required |
| L3 fresh install (`run-smoke.sh`, `update-verify.sh`) | required | required |
| L4 `build-session.sh` + `headless/run-tests.sh` (standard and `--workstation`) | required | required |
| VM `run-vm-test.sh` | required | required |
| F44 → F45 upgrade: L3 `run-release-upgrade.sh` | — | required |
| F44 → F45 upgrade: L4 `build-upgraded-session.sh --run` | — | required |
| F44 → F45 upgrade: VM `run-vm-test.sh --upgrade-to 45` | — | required |

The upgrade gates install Omedora on Fedora 44 from the live COPR, run
`omedora-upgrade-fedora --check` (which must refuse a release the COPR does
not build and accept 45), and then run the real dnf5 offline upgrade: the same
`dnf system-upgrade download` transaction that `dnf5 offline _execute` applies
at reboot. Each tier then proves the result from its own angle:

- **L3** (`run-release-upgrade.sh`, ~25 min): every package that came from the
  COPR is still installed, still from the COPR, a `.fc45` build and not
  downgraded; `omarchy update` passes twice on Fedora 45.
- **L4** (`build-upgraded-session.sh --run`): upgrades the Fedora 44 session
  image under systemd, boots the result (the offline transaction's reboot
  stops the container; starting it boots Fedora 45), runs `omarchy update`,
  commits `omedora-test:fedora45-session-4-upgraded` and runs the headless
  suite against it.
- **VM** (`run-vm-test.sh --upgrade-to 45`): the session tests on Fedora 44,
  then `omedora-upgrade-fedora --yes` with the real offline reboot, the
  post-upgrade package checks and `--post-check`, `omarchy update`, and the
  session tests again on Fedora 45 under GDM.

All three drive Omedora's code from the checkout the way `omarchy dev link`
does (`OMARCHY_PATH`, `PATH` and sudo's `secure_path`), so they gate
unreleased code while every package still comes from the COPR. L3 and L4 take
`--installed` to use the published `omedora` payload instead, which is the
post-release check. They need the target chroot fully built; run them after
the COPR backfill or a release's builds finish.

## 2. L1 gate

Run every Omedora unit independently so one failure does not hide later tests:

```bash
failed=()
for test in test/*-test.sh; do
  bash "$test" || failed+=("$test")
done
(( ${#failed[@]} == 0 ))

bin/omarchy-dev-validate-fedora-packages
bash test/cli
bin/omarchy commands --check
```

For a rebase, run byte identity against the candidate commit when the prepared
pin tag has not been created yet:

```bash
OMEDORA_BASE_TAG=5978d93ae7da0a325b7493501911e3f1266cadd3 \
  bash test/byte-identity-test.sh
```

Important focused gates include:

| Test | Contract |
| --- | --- |
| `migration-gating-test.sh` | Arch-only migrations exit before touching Arch tooling on Fedora |
| `update-flow-test.sh` | Fedora's RPM transaction is managed-package-only; Arch emits no dnf |
| `pkg-map-test.sh` | Real map plus schema fixtures, including Quattro package classifications |
| `archism-gating-test.sh` | Shared setup paths do not leak hard Arch assumptions |
| `etc-overrides-audit-test.sh` | Fedora-owned generic configuration is not overwritten |
| `byte-identity-test.sh` | Modified upstream files are additive or exactly allowlisted |
| `upgrade-to-4-test.sh` | Mocked Omedora 3 to package-backed Omedora 4 transition |
| `*-spec-test.sh` | Static invariants for selected RPM specs |

`test/all` runs upstream `test/cli` and `test/shell`. The shell suite is useful on
a matching host but contains environment-sensitive tests; report those failures
separately rather than substituting it for the deterministic L1 list.

## 3. L2 containers

### Fedora integration

```bash
omedora/test/fedora/run-integration.sh
```

The runner builds `omedora-test:fedora44` (`omedora-test:fedora45` with
`OMEDORA_FEDORA_RELEASE=45`) from the checked-in Dockerfile and runs
`omedora/test/fedora/integration.sh` with the repository mounted at `/repo`.
This validates package-map behavior and Fedora-specific setup with real dnf/rpm
tools. Use `--rebuild` after changing the test image.

### Arch contract

```bash
docker run --rm -v "$PWD:/repo" -w /repo archlinux:latest bash -c '
  pacman -Syu --noconfirm --needed jq python git gum ripgrep fontconfig >/dev/null
  bash test/cli
'
```

The byte-identity audit plus upstream CLI suite is the Arch regression contract.
When shared Arch shell behavior changes upstream, run the relevant `test/shell.d`
tests in the Arch container as well.

L2 containers must use `--rm`. Remove only containers created by the current
task; never clean concurrent agents' images or cache volumes.

## 4. L3 gates

The audit smoke runner is:

```bash
omedora/test/fedora/run-smoke.sh
```

Additional package-backed release gates include:

```bash
omedora/test/fedora/update-verify.sh
omedora/test/fedora/upgrade-from-beta1-verify.sh
omedora/test/fedora/upgrade-to-4-verify.sh
```

Some scripts are designed to run inside a prepared Fedora test image rather
than directly on the host. Read each header and use the documented runner. A
release requires a clean fresh install on each supported Fedora release (see
the matrix in §1), two consecutive scoped update
runs, an upgrade from the previous published Omedora build, and the beta.1
bootstrap gate when releasing beta.2. The beta.1 gate must prove that the scoped
`omedora`/`omedora-settings` transaction lands new code before `omedora update`
is invoked and that an unrelated RPM with a newer available candidate remains
at its deliberately installed older EVR. Fedora L2 also builds disposable local
repositories to exercise exact core NEVRA selection and `%{from_repo}` repair
with real dnf5 behavior.

Do not publish COPR builds merely to satisfy delegated verification. If current
core RPMs do not contain the candidate source, record L3 as blocked on rebuild.

## 5. L4 nested session

`omedora/test/fedora/build-session.sh` creates the package/session image under
real PID 1 systemd. `omedora/test/fedora/headless/run-tests.sh` launches a full
headless session and runs:

- `00-session.sh`: session and IPC health.
- `10-launcher.sh`: Quickshell launcher behavior.
- `20-portals.sh`: portal services and D-Bus ownership.
- `30-visual.sh`: screenshot comparison against the reviewed reference.
- `40-menu.sh`: menu behavior.
- `90-workstation.sh`: Fedora Workstation coexistence when selected.

The Workstation variant exercises GNOME coexistence and tuned-ppd. L4 needs a
usable DRM render node and is not available on standard GitHub-hosted runners.

The session image is built in three layers, and only the first is shared
across checkouts:

| Image | Contents | Rebuilt when |
| --- | --- | --- |
| `omedora-test:fedora<N>-session-4-sysbase` | Fedora, systemd, test deps, the `omedora` user; no checkout | missing, or `--rebuild` |
| `…-session-4-pkgs` | the packages phase (plan, repos, package payload) | `--rebuild`, or its `omedora.pkgs-key` label no longer matches: base image, package source, or a packages-phase file changed |
| `…-session-4` | the config phase (system setup, adopt, finalize, first-run) | every build |

`build-session.sh` copies the current checkout (tracked and untracked
non-ignored files, uncommitted edits included) into the build container right
before each install phase, so a build always runs this checkout's install
scripts. Images it commits carry an `omedora.tree` label with the commit
(`-dirty-<hash>` for uncommitted changes); `run-session.sh`,
`headless/run-tests.sh` and `build-upgraded-session.sh` warn when an existing
image was built from a different tree. The `-sysbase` images replace the old
`-session-4-base` ones, which baked a checkout in and silently ran its install
scripts in every later build.

### Local-repo mode

To test unpublished core RPMs, build them from HEAD and use the `-local` image
lineage:

```bash
omedora/packaging/copr/build-repo.sh omedora-settings.spec omedora.spec
omedora/test/fedora/build-session.sh --local-repo
omedora/test/fedora/headless/run-tests.sh --local-repo
```

The local repo (`packaging/copr/repo[-f<N>]`) overlays the live COPR at
`priority=1` (see [`packages.md` §5](packages.md#5-local-repositories-in-tests)),
so the core RPMs come from it and the rest of the stack from the COPR.
`build-session.sh --local-repo` rebuilds the core RPMs itself when the repo
does not hold HEAD's build. They package `git archive HEAD`: commit before
building, or the run tests the previous commit's payload.

Never update `30-visual-reference.png` solely because a rebase changed pixels.
Capture the candidate, inspect the difference, identify the intended upstream
change, and accept a new golden only after human visual review. The 4.5 visual
changes (theme intros, backgrounds, bar) therefore remain an explicit L4 item.

## 6. L4 VM

```bash
omedora/test/fedora/vm/run-vm-test.sh
```

The rootless libvirt/KVM pipeline provisions Fedora Workstation
(`OMEDORA_FEDORA_RELEASE`, default 44), installs
from the live COPR, starts the packaged Omedora session through GDM, checks RPM
provenance, runs session assertions, and captures the real framebuffer. It is a
pre-release gate, not a per-PR CI job.

VM-only checks include:

- `omedora.desktop` appears and logs in through GDM while GNOME remains usable.
- SELinux `user_t` produces no relevant AVC denials.
- Real seat, DRM, and user-systemd behavior works.
- Hardware-specific paths no-op or apply as designed.

## 7. CI reality

`.github/workflows/test.yml` currently runs the explicit L1 Omedora tests and an
Arch-container `test/cli` job. The Fedora L2, L3, and L4 runners exist in the
tree but are not all CI jobs. Reports must distinguish "runner exists" from
"CI executed it".

## 8. Test style

- Shell tests use `test/helpers.sh` and TAP-style `pass`/`fail` assertions.
- External tools are replaced by executable PATH stubs that log exact argv.
- Every test creates and removes its own temporary directory.
- Distro seams use `OMARCHY_DISTRO`; package fixtures use
  `OMARCHY_FEDORA_MAP`, `OMARCHY_BASE_PKGS`, and related documented variables.
- Code and the test proving its behavior belong in the same logical commit.

## 9. Rebase sign-off

A parent reviewer should receive exact results for:

1. Every L1 test, including the count passed/failed.
2. Fedora map validation, `test/cli`, and `commands --check`.
3. Byte identity against the exact official base commit.
4. Fedora and Arch L2 commands actually run, per Fedora release.
5. L3/L4 commands actually run, or explicit blockers when they were not.
6. Any containers created and confirmation that they were removed.
