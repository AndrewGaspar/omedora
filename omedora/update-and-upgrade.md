# Update and upgrade policy

Omedora is layered onto a Fedora installation the user already owns. Its update
command therefore updates Omedora's package universe, not the whole operating
system.

## Fedora update flow

Upstream Quattro's `bin/omarchy-update` remains the orchestrator:

```text
omarchy update
  -> prune Omedora/Omarchy package cache
  -> optional snapshot (absence is tolerated)
  -> update a developer checkout, only when OMARCHY_PATH is not /usr/share/omarchy
  -> Fedora keyring step: no-op
  -> omarchy-update-system-pkgs
       -> bin/fedora/update-system-pkgs
  -> omarchy-migrate
  -> post-update hook
  -> Fedora AUR step: no-op
  -> mise update
  -> Fedora orphan step: no-op
  -> status/log analysis and restart prompt
```

Normal package-backed Fedora installs use `/usr/share/omarchy`, so
`omarchy-update-dev` exits without touching git.

### One-time beta.1 bootstrap

`0.2.0-beta.1` predates the managed-only updater. Its installed update command
would start the old unscoped transaction before beta.2 code arrives, so beta.1
users must **not** run `omedora update` first. The supported transition is:

```bash
repo_id=$(omedora-copr --repo-id)
sudo dnf copr enable -y "$(omedora-copr)"
sudo dnf upgrade --refresh -y --setopt=install_weak_deps=False --from-repo="$repo_id" omedora omedora-settings
test "$(rpm -q --qf '%{VERSION}\n' omedora omedora-settings | sort -u)" = "0.2.0~beta.2" && omedora update
```

The first command idempotently enables the version-scoped `agaspar/omedora-4`
COPR selected by `omedora-copr`. The second command is a one-time transaction
scoped to the two core RPMs; dnf5's `--from-repo` constrains those requested
RPMs to that COPR while leaving normal repositories available for dependencies.
Only after those packages report beta.2 should the
normal updater run. `omedora/test/fedora/upgrade-from-beta1-verify.sh` enforces
this ordering against real RPM and dnf state as an L3 release gate. The shell
guard above makes that ordering executable: stale beta.1 RPMs prevent the final
update command from running.

## Managed RPM resolution

`bin/fedora/managed_packages.py` constructs the transaction in four parts:

1. `omedora` and `omedora-settings`.
2. Every dnf/COPR target resolved from the current
   `install/omarchy-base.packages`.
3. Every target in `omedora/install/fedora-baseline.packages`.
4. Every non-base dnf/COPR map target whose mapped RPM is already installed.

Base and baseline targets are unconditional. This is intentional: when a new
Omarchy release adds a base package, the next Omedora update must install it,
not merely update packages that were present before the release.

Non-base map entries are optional. They are included only if already installed,
so updating Omedora does not opt the user into every menu application or hardware
variant described by the map.

Before each pass, the sibling resolves and enables the version-scoped COPR
through `omedora-copr`. For `omedora` and `omedora-settings`, it queries the
latest noarch candidate from that repository and records each exact NEVRA and
EVR. Missing, duplicate, malformed, or wrong-repository results abort.

Core reconciliation is separate from the broad managed transaction. When an
installed core EVR differs, including a locally newer build, the sibling runs an
exact-NEVRA `dnf install --allow-downgrade --from-repo=<expected-id>`. When the
EVR matches but `%{from_repo}` is foreign, it runs an exact-NEVRA `dnf reinstall`
with the same source constraint. dnf5 applies `--from-repo` to the requested
items while leaving all enabled repositories available for dependencies.

The remaining managed names are then installed with:

```bash
sudo dnf install --refresh -y --setopt=install_weak_deps=False \
  --exclude=omedora --exclude=omedora-settings "${managed_without_core[@]}"
```

The exclusions prevent another enabled repository from replacing the reconciled
core RPMs during this broader pass. For other named installed packages, `dnf
install` selects the latest available build; newly added base names are
installed. Because every top-level target is explicit, unrelated installed
Fedora RPMs do not join the transaction. Dependency changes required by managed
targets may still be resolved normally by dnf.

After core reconciliation and again after the broad pass, the sibling requires
each installed core EVR to equal the selected expected-COPR EVR and each
installed `%{from_repo}` to equal the version-scoped COPR ID. Query failure,
ambiguity, transaction mismatch, or foreign provenance aborts the update.

After the first transaction, the sibling resolves the list again from the
potentially replaced `omedora` payload. If the new release changed the base list
or map, it runs one more scoped transaction. This is what installs a base package
introduced by the release being applied, without requiring a second user update.

An unscoped `dnf upgrade` is prohibited. `bin/omedora-update-pkgs`, retained as
a compatibility command, executes the same scoped sibling and cannot bypass the
policy.

## Other update sources

- Arch keyring, AUR, and pacman orphan logic are Fedora no-ops.
- Omedora does not run `dnf autoremove`.
- Flatpak entries remain user-managed unless a specific Omedora migration or
  install action updates them; the RPM transaction never broadens into a global
  `flatpak update`.
- Mise-managed development tools continue through upstream's
  `omarchy-update-mise` behavior.

## Update availability

`bin/omarchy-update-available` dispatches to
`bin/fedora/update-available`. It runs `dnf check-upgrade` scoped to the Omedora
COPR repo ID from `bin/omedora-copr` and writes the state files consumed by the
Quickshell update indicator. Pending kernel or unrelated Fedora updates do not
light the Omedora indicator.

## Fedora release upgrades

Omedora supports the two newest Fedora releases: the current one and the one
before it (today **Fedora 44 and 45**). A release is supported exactly when the
version-scoped COPR has a chroot for it; check with:

```bash
omedora-copr --chroot-available        # the running release
omedora-copr --chroot-available 46     # any release; exit 0 = supported
```

Exit 0 means the COPR builds for that release, 1 means it does not (the
supported releases are printed), and 2 means the check itself failed.

### Upgrading Fedora

Use `omedora-upgrade-fedora` instead of calling `dnf system-upgrade` yourself:

```bash
omedora-upgrade-fedora --check           # read-only preflight for the next release
omedora-upgrade-fedora                   # upgrade to the next release
omedora-upgrade-fedora --releasever 45   # an explicit target
```

A plain `dnf system-upgrade` while the COPR has no builds for the target
release skips the COPR (`skip_if_unavailable`) and then either fails on
dependency problems or, with `--allowerasing`, removes the Omedora session
(`hyprland-no-session`, `omedora`, `aquamarine`, ...) and downgrades the
vendored Hyprland stack and Quickshell to Fedora's older same-name packages.
`omedora-upgrade-fedora` refuses to start until that can't happen:

1. **Preflight** (read-only; `--check` stops here). The target must be newer
   than the running release and `omedora-copr --chroot-available <target>`
   must answer 0; if the API can't be reached, it refuses rather than guess.
   Then it runs `dnf --releasever=<target> distro-sync --refresh --assumeno
   --allowerasing` as a dry run (dnf5's `system-upgrade` has no dry run) and
   refuses if the transaction would remove or downgrade any package installed
   from the Omedora COPR. Removing other packages is refused too, unless you pass
   `--allowerasing`. Omedora packages that the dry run leaves alone have no build
   for the target yet; they are listed as a warning.
2. **Snapshot.** On a btrfs root it offers an `omedora-snapshot` of `/`
   (`--yes` takes it, `--no-snapshot` skips it).
3. **Upgrade.** `dnf upgrade --refresh` on the running release (Fedora's first
   documented step), then `dnf system-upgrade download --releasever=<target>`,
   then it asks before `dnf offline reboot`. `--allowerasing` is passed to the
   download only when you passed it.

After the upgrade reboots into the new release, log in and run `omarchy update`.
The updater ends with `omedora-upgrade-fedora --post-check`, which warns about
Omedora packages still carrying the old release's dist tag (for example `.fc44`
on Fedora 45). Those packages had no rebuild yet. Once the COPR has the
rebuilds, run `sudo dnf upgrade --refresh <names>` to install them.

### Snapshots don't cover /boot

`omedora-snapshot` snapshots the root subvolume only. `/boot` is a separate
partition, so after you roll `/` back across a release upgrade
(`omedora snapshot rollback <name> --apply`), `/boot` still holds the new
release's kernels and boot entries. The default entry then boots a kernel whose
modules are gone from `/lib/modules`. The package database rolled back with `/`,
so dnf doesn't know about those kernels either. To recover:

1. In the boot menu, pick an entry for an old-release kernel (for example
   `6.x.y-z.fc44`).
2. Once booted, remove each new-release kernel's boot entry, kernel, and
   initramfs from `/boot`:

   ```bash
   ls /boot/loader/entries/                        # find the .fc45 versions
   sudo kernel-install remove 6.x.y-z.fc45.x86_64
   ```

The boot menu then defaults to the newest old-release kernel again.

### If you upgraded too early

If Fedora was upgraded before Omedora supported the new release, `omarchy
update` stops before changing anything. It says that Omedora doesn't support
Fedora N yet, instead of showing dnf's `Chroot not found` error. Either roll back
to a pre-upgrade snapshot or wait for the builds and run `omarchy update` again.

### Maintainer checklist for a new Fedora release

The chroot policy is in [`versioning.md`](versioning.md#fedora-releases-and-copr-chroots).
Before announcing support for a new release:

1. Enable its chroot and backfill every RPM in dependency order.
2. Validate every base-map target against its repositories.
3. Run the Fedora integration, fresh-install, upgrade, and session gates.
4. Review package moves, replacements, and SELinux behavior.

## Failure behavior

- A dnf transaction failure aborts the update and is safe to retry after the
  repository or dependency issue is corrected.
- Missing managed candidates, an unavailable Omedora COPR, or ambiguous core
  candidate data aborts before package installation. When the COPR can't be
  enabled because it has no chroot for the running Fedora release, the error
  says that instead of passing on dnf's `Chroot not found`. Core EVR/provenance
  mismatch after reconciliation or after the broad pass aborts immediately.
- A failed migration does not receive a completion marker and retries later.
- A missing snapshot implementation is tolerated; other snapshot failures are
  reported before continuing.
- Restart/reboot remains an explicit user decision.

## dnf release-change guard

A raw `sudo dnf system-upgrade download --releasever=N`, `dnf --releasever=N
distro-sync`, or a GNOME Software upgrade bypasses `omedora-upgrade-fedora`.
When the COPR has no `fedora-N` chroot, dnf5 skips the repo
(`skip_if_unavailable`), and the transaction then fails or, with
`--allowerasing`, removes Hyprland and downgrades quickshell and the hypr
libraries to Fedora's older copies. That leaves a broken desktop.

`omedora-settings` ships a libdnf5 actions-plugin hook,
`/etc/dnf/libdnf5-plugins/actions.d/omedora-release-guard.actions`, which runs
`/usr/libexec/omedora/omedora-release-guard` on `goal_resolved`. The package
requires `libdnf5-plugin-actions` because Fedora does not install it by
default. The hook runs in every libdnf5 front end: the `dnf` CLI,
`dnf5daemon-server` (GNOME Software on Fedora 44/45), and PackageKit's dnf5
backend. Rules:

- Same-release transactions are never blocked. The guard compares dnf's
  `releasever` with `/etc/os-release`.
- A release-changing transaction is stopped if it would remove, downgrade, or
  hand to another vendor any package whose vendor is
  `Fedora Copr - user <owner>`. The guard also stops it if the COPR repo loaded
  nothing and `omedora-copr --chroot-available N` exits 1. This catches a
  partially built new chroot as well as a missing one.
- The guard fails open. It allows the transaction, with a warning, on probe
  exit 2, a timeout, a missing `omedora-copr`, a plugin error, or a guard
  crash (the action keeps `raise_error=0`).
- The offline reboot phase (`dnf5 offline _execute`) is always allowed and
  makes no network call. That phase replays a stored transaction with
  `cacheonly=all`, no repositories, and the old `releasever`.
- `enabled=host-only` keeps the hook out of `--installroot` operations.
- Bypass: `sudo OMEDORA_ALLOW_RELEASE_UPGRADE=1 dnf ...`. dnf's
  `--disable-plugin=actions` also bypasses it.

Each resolved goal costs about 35 ms. The guard queries the network only for a
release change whose COPR repo loaded nothing. Its verdicts are logged to
`/var/log/dnf5.log` (`omedora-release-guard:`). `test/dnf-release-guard-test.sh`
covers the decision logic and the json protocol.

## Tests

`test/update-flow-test.sh` uses fixture base/map files and mocked rpm/dnf tools to
prove the transaction includes core, mapped base, newly added base, Fedora
baseline, and installed optional RPMs while excluding an installed unrelated
RPM. It also verifies the Arch update arms emit no dnf calls.
`test/update-unsupported-release-test.sh` covers the unsupported-release message
and the post-update rebuild warning. `test/upgrade-fedora-test.sh` covers the
`omedora-upgrade-fedora` preflight decisions and upgrade order.
`test/copr-chroot-probe-test.sh` covers the chroot probe contract.

Real package-manager behavior belongs in Fedora L2/L3 and the pre-release upgrade
gate described in [`testing.md`](testing.md).
