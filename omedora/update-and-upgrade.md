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

## Fedora major upgrades

Omedora does not initiate `dnf system-upgrade`. The user upgrades Fedora through
Fedora's supported tooling. Before supporting a new Fedora release, maintainers
must:

1. Build all required Omedora RPMs for that release.
2. Validate every base-map target against its repositories.
3. Run the Fedora integration, fresh-install, upgrade, and session gates.
4. Review package moves, replacements, and SELinux behavior.

If the Omedora COPR does not have builds for the new Fedora release, users should
remain on the supported Fedora version. The update command must fail loudly
rather than replacing managed packages from an unreviewed source.

## Failure behavior

- A dnf transaction failure aborts the update and is safe to retry after the
  repository or dependency issue is corrected.
- Missing managed candidates, an unavailable Omedora COPR, or ambiguous core
  candidate data aborts before package installation. Core EVR/provenance
  mismatch after reconciliation or after the broad pass aborts immediately.
- A failed migration does not receive a completion marker and retries later.
- A missing snapshot implementation is tolerated; other snapshot failures are
  reported before continuing.
- Restart/reboot remains an explicit user decision.

## Tests

`test/update-flow-test.sh` uses fixture base/map files and mocked rpm/dnf tools to
prove the transaction includes core, mapped base, newly added base, Fedora
baseline, and installed optional RPMs while excluding an installed unrelated
RPM. It also verifies the Arch update arms emit no dnf calls.

Real package-manager behavior belongs in Fedora L2/L3 and the pre-release upgrade
gate described in [`testing.md`](testing.md).
