# Omedora 4 architecture

> **Current base (2026-09-05):** official Omarchy `v4.0.2`, commit
> `346e69e1cec6c4e8924531874af6ba010a1bc99e7`. The immutable Omedora
> pin is `omedora-base-20260905-omarchy4-346e69e1`, cut locally on this
> branch; push the tag before the branch at promote time.

Omedora is an additive Fedora port of Omarchy, not a separate implementation.
The same tree remains runnable on Arch. Fedora behavior is introduced through
small dispatches to Fedora siblings, while upstream Arch bodies remain
byte-for-byte identical wherever feasible.

## 1. Patch model

- Omarchy-owned files receive a top-of-file Fedora dispatch or early return.
- Substantial Fedora implementations live in new siblings, normally under
  `bin/fedora/` or with an `-fedora.sh` suffix under `install/`.
- Omedora-only installation, packaging, documentation, and test infrastructure
  lives under `omedora/`.
- `test/byte-identity-test.sh` audits every modified file that exists at the
  immutable base. Deletions require an exact, documented allowlist entry.
- The package-backed `omedora-4` branch may be rebased because installed systems
  consume RPMs, not a branch checkout. See [`rebase-workflow.md`](rebase-workflow.md).

## 2. Package-backed layout

Official Omarchy 4 installs `omarchy` and `omarchy-settings` packages into
`/usr/share/omarchy` and `/usr/bin`. Omedora mirrors that split:

| RPM | Owns |
| --- | --- |
| `omedora` | Commands, `bin/fedora/`, install helpers, migrations, themes, and `shell/` |
| `omedora-settings` | Config/default sources, `/etc/skel` seeds, reviewed system drop-ins, branding, and `omedora.desktop` |

Internal names remain `omarchy-*`, `$OMARCHY_*`, and `/usr/share/omarchy`.
Renaming those interfaces would break upstream compatibility and increase every
future rebase.

The Fedora bootstrap is `omedora/boot.sh` -> `omedora/install-4.sh`. It uses a
shallow throwaway clone only to display the plan before changing the machine.
After `dnf install omedora`, the installed RPM payload drives setup. There is no
normal git checkout or git-pull update path on Fedora.

## 3. Distro and package dispatch

`bin/omarchy-distro` emits `arch` or `fedora` and honors `OMARCHY_DISTRO` for
tests. Shared package helpers dispatch on Fedora to `bin/fedora/pkg.py` or the
small `pkg-install`/`pkg-remove` siblings:

| Omarchy helper | Fedora behavior |
| --- | --- |
| `omarchy-pkg-add`, `-install`, `-aur-add` | Resolve `install/packages/fedora.toml`; install RPMs or Flatpaks, or skip with a reason |
| `omarchy-pkg-missing`, `-present` | Query translated RPM names or Flatpak IDs |
| `omarchy-pkg-drop`, `-remove` | Remove only translated installed targets |

Absence from `fedora.toml` means the package name is valid unchanged through
dnf. Explicit entries select `dnf`, an allowlisted on-demand `copr`, `flathub`,
or `skip`. The retired source-installer schema is rejected; portable software
without an existing package source must be packaged as an Omedora RPM or
explicitly skipped.

## 4. Fedora install

`omedora/install-4.sh` runs these disclosed stages:

1. `plan.sh` inventories backups, package replacement, and system actions.
2. `snapshot.sh` offers an optional btrfs snapshot.
3. `repos.sh` enables the Omedora COPR, RPM Fusion, and Flathub.
4. `packages.sh` installs `omedora`, then resolves the Omarchy base list plus
   `omedora/install/fedora-baseline.packages` through the Fedora map.
5. `system.sh` runs the Fedora-safe system setup paths.
6. `adopt.sh` backs up and adopts an existing user's configuration.
7. `finalize.sh` and `first-run.sh` complete user setup.

Fedora keeps its existing display manager. `omedora-settings` packages
`/usr/share/wayland-sessions/omedora.desktop`; it does not install SDDM or a
second generic Hyprland session.

## 5. Package ownership

The full Omarchy base package list is upstream-owned. Omedora adds only a Fedora
translation map and a small Fedora baseline. Packages unavailable in Fedora,
RPM Fusion, or an approved source are built under `omedora/packaging/copr/` and
served from `agaspar/omedora-4`.

Hyprland is split so `hyprland-no-session` provides the compositor without a
login entry. Omedora packages Hyprland 0.56.2 with Aquamarine 0.14.0. The
separate HypXR package stack consumes that stable dependency wave and is
maintained by its own packaging workflow; a Quattro source rebase does not by
itself imply an HypXR rebuild.

## 6. System boundary

Omedora deliberately does not own Fedora's bootloader, initramfs, Plymouth,
display manager, kernel modules, DKMS drivers, firewall defaults, snapshot
stack, hibernation setup, or user-wide Fedora update policy. Fedora-specific
setup siblings either implement a narrow equivalent or leave the host policy
alone.

Generic Fedora-owned configuration is never overwritten. Reference material
that is useful to Omedora stays under `/usr/share/omarchy/etc-overrides`; only
Omedora-namespaced drop-ins reviewed in `omedora-settings.spec` are packaged.

## 7. User and branding boundary

Existing user files follow backup-then-write or only-if-unset behavior. The RPM
payload seeds `/etc/skel` for new users but does not treat an existing home as
package territory.

`omedora` is an alias of the `omarchy` dispatcher. The display-manager entry,
logo, Fedora-only install output, and version banner use Omedora branding. The
shared dispatcher's help remains upstream Omarchy output. Command filenames,
environment variables, filesystem paths, root Omarchy assets, and command
metadata retain upstream naming. See [`branding.md`](branding.md).

## 8. Version identity

- `omedora/version`: Omedora release identity, currently `0.2.0-beta.2`.
- `omedora/base-version`: reported upstream base, currently `4.0.0`.
- root `version`: upstream-owned package metadata and intentionally unchanged.
- the `omedora-base-*` tag: immutable git object used by the rebase and
  byte-identity audits.

## 9. Migrations

Quattro user migrations live in `migrations/*.sh` and run under
`bash -euo pipefail`. A failure prevents the completion marker and blocks later
migrations, so Arch-only migrations must exit successfully on Fedora before
touching pacman, Limine, mkinitcpio, or other Arch state.

`test/migration-gating-test.sh` statically classifies hard Arch tokens and
runtime-tests known gates with failing Arch-tool stubs. Fedora-relevant
migrations should use portable helpers instead of being skipped.

## 10. CLI branding

The dispatcher stays byte-identical at `bin/omarchy`; `bin/omedora` is its
symlink and intentionally renders the same Omarchy command help. Fedora reports
`Omedora <release> (rebased on Omarchy <base>)` from the separately dispatched
`omarchy-version`. Screensaver and package payload branding use
`omedora/branding/logo.txt` without modifying upstream's root assets.

## 11. Updates

Upstream Quattro's `bin/omarchy-update` is the orchestrator on both distros. On
Fedora, Arch-only keyring, AUR, and orphan steps exit cleanly. The shared
`omarchy-update-system-pkgs` dispatches to `bin/fedora/update-system-pkgs`.

That sibling resolves one explicit managed package set containing:

- current `install/omarchy-base.packages` targets, including packages added by a
  newer release;
- `omedora/install/fedora-baseline.packages` targets;
- non-base dnf/COPR map targets only when their RPM is already installed;
- `omedora` and `omedora-settings`.

It enables the version-scoped COPR and selects the latest exact expected-repo
NEVRA for each core RPM. It downgrades a locally newer core build or reinstalls
a same-EVR foreign build as needed with dnf5's `--from-repo` constraint, then
verifies exact installed EVR and `%{from_repo}`. The remaining managed names run
in a separate scoped transaction that excludes both core names, followed by the
same identity verification. It resolves once more from the potentially updated
core payload and repeats only if that managed list changed. It never runs an
unscoped `dnf upgrade`, so unrelated Fedora RPMs remain the user's responsibility.
`bin/omedora-update-pkgs` is only a compatibility wrapper to the same sibling.

## 12. Release packaging

Changing runtime files requires rebuilding `omedora`; changing packaged
defaults requires rebuilding `omedora-settings`. This rebase changes both and
therefore prepares `0.2.0-beta.2` for each. No COPR build, release tag, or git
push is part of the rebase implementation itself.

## 13. Verification

The gates are defined in [`testing.md`](testing.md). At minimum, a rebase runs
all `test/*-test.sh`, the Fedora map validator, upstream `test/cli`, command
metadata validation, and the byte-identity audit against the prepared base.
Fedora and Arch container checks supplement L1. L3 install and L4 visual/VM
results must never be inferred from lower layers.

## 14. Out-of-scope matrix

| Surface | Fedora owner |
| --- | --- |
| GRUB/Limine, EFI, partitioning | Fedora installation |
| dracut/initramfs and kernel drivers | Fedora/RPM Fusion |
| GDM/SDDM selection | Existing Fedora desktop |
| firewalld zone policy | User/administrator |
| generic `/etc` configuration | Fedora packages or administrator |
| whole-system `dnf upgrade` | User/administrator |

## 15. Patch-stack map

This map classifies the Omedora delta against the immutable base. The exact
inventory is always reproducible with `git diff --name-status <pin> HEAD`; every
path must fit one row below.

| Paths | Patch type | Contract |
| --- | --- | --- |
| `README.md` | Document replacement | Fedora-facing project landing page; exact upstream deletions are byte-audited |
| `bin/omarchy-pkg-*`, `bin/omarchy-update-*`, `bin/omarchy-channel-*`, `bin/omarchy-snapshot`, `bin/omarchy-version*` | Prepend/early dispatch | Fedora sibling or clean no-op; Arch body retained |
| `bin/omarchy-{apply-lock,debug,default-browser,migrate,provision-user,reinstall-configs,restart-terminal,setup-security-fingerprint,voxtype-*,webapp-*}` | Narrow Fedora branch | Portable contract preserved; relocations are byte-audited |
| `bin/fedora/*`, `bin/omedora*`, `bin/omarchy-distro`, `bin/omarchy-doctor`, `bin/omarchy-dev-validate-fedora-packages` | New additive files | Fedora implementation and Omedora commands |
| `install/config/{docker,enable-services,firewall,theme-system}.sh`, `install/user/{mise-work,xcompose}.sh` | Dispatch or narrow branch | Fedora sibling handles host-safe behavior |
| `install/hardware/all.sh`, `install/login/sddm.sh`, `install/post-install/pacman.sh`, `install/user/first-run/gnome-theme.sh`, `install/config/increase-lockout-limit.sh` | Fedora gate | Exclude Arch boot/login or host-policy behavior |
| `install/**/*-fedora.sh`, `install/packages/fedora.toml` | New additive files | Fedora implementations and package translation |
| `migrations/*.sh` modified by Omedora | Early Fedora gate/branch | Must pass static and runtime migration gating tests |
| `default/omarchy/omarchy-menu.jsonc`, `etc/fastfetch/config.jsonc` | User-facing Fedora adaptation | Menu availability/branding and Omedora version display |
| `config/wezterm/`, `default/themed/wezterm.lua.tpl`, webapp profile additions | Forward-ported upstream additions | Retire from the delta when a later base includes them |
| `.copr/`, `.github/workflows/`, `omedora/packaging/` | New additive files | RPM build and CI infrastructure |
| `omedora/install*`, `omedora/branding*`, `omedora/*.md`, `omedora/version`, `omedora/base-version` | New additive files | Fedora bootstrap, policy, docs, and identity |
| `test/*-test.sh`, `test/mocks/`, `omedora/test/fedora/` | New additive files | L1 through L4 verification |
| `test/shell.d/version-test.sh` | Additive test branch | Fedora version-banner contract; upstream assertions retained |

Adding a modified upstream path that does not fit this map requires updating the
map in the same change. Additive RPM specs and their source manifests are
covered by the `omedora/packaging/` row; HypXR changes remain a separate logical
change even though they share that directory.

## 16. Setup-system gating map

| Entry point/path | Fedora decision |
| --- | --- |
| `install/config/theme-system.sh` | Dispatch to `theme-system-fedora.sh`; avoid Arch Yaru and Chromium paths |
| `install/config/increase-lockout-limit.sh` | Gate; Fedora PAM is authselect-managed and Omedora does not install SDDM |
| `bin/omarchy-setup-lock` | Dispatch to `bin/fedora/setup-lock` using Fedora's `system-auth` include |
| `install/config/docker.sh` | Dispatch; add group and apply daemon defaults only when absent |
| `install/config/snapper.sh` | Gate; Limine/snapper boot snapshots are out of scope (§14) |
| `install/config/enable-services.sh` | Dispatch; enable only present, reviewed services |
| `install/config/firewall.sh` | Dispatch to narrow firewalld application rules without changing zone defaults |
| `install/hardware/all.sh` | Dispatch to `all-fedora.sh`, an explicit portable subset |
| `install/login/sddm.sh` | Gate; preserve the existing display manager |
| `install/post-install/pacman.sh` | Gate; pacman configuration is Arch-only |
| `bin/omarchy-provision-user` | Fedora only-if-unset browser/mailto branch |
| `install/user/xcompose.sh` | Fedora backup-then-write branch |
| `install/user/mise-work.sh` | Dispatch; avoid the Arch ISO package cache |
| `install/user/first-run/gnome-theme.sh` | Gate; do not clobber a coexisting GNOME appearance |

All other setup-system/user steps run unchanged or self-guard based on command
availability. A new upstream setup step must be explicitly classified here when
it reaches host policy, boot/login state, or an Arch-only tool.
