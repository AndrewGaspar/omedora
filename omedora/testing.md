# Testing

Omedora uses four verification layers. Results are reported by layer; passing a
lower layer never implies a higher one passed.

## 1. Layers

| Layer | Environment | Scope |
| --- | --- | --- |
| L1 | Any Linux development host | Shell units, static package/spec checks, migration gates, CLI metadata, and byte identity |
| L2 | Fedora 44 and Arch containers | Real distro tooling, Fedora integration, and upstream Arch regression |
| L3 | Fedora container or clean Fedora system | Fresh package/install and release-upgrade flows |
| L4 | Nested full session and Fedora Workstation VM | Compositor, Quickshell, portals, GDM, SELinux, hardware, and visual goldens |

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
OMEDORA_BASE_TAG=f0020448ca87329199de7cb12f2015ebc4a3e5e7 \
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

The runner builds `omedora-test:fedora44` from the checked-in Dockerfile and runs
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
release requires a clean Fedora 44 fresh install, two consecutive scoped update
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

Never update `30-visual-reference.png` solely because a rebase changed pixels.
Capture the candidate, inspect the difference, identify the intended upstream
change, and accept a new golden only after human visual review. The official
4.0.0 Tokyo Night background renumbering therefore remains an explicit L4 item.

## 6. L4 VM

```bash
omedora/test/fedora/vm/run-vm-test.sh
```

The rootless libvirt/KVM pipeline provisions Fedora 44 Workstation, installs
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
4. Fedora and Arch L2 commands actually run.
5. L3/L4 commands actually run, or explicit blockers when they were not.
6. Any containers created and confirmation that they were removed.
