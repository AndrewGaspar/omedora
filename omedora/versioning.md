# Omedora versioning and releases

Omedora 4 has three separate identities. They must not be conflated.

| Identity | Source | Current value | Purpose |
| --- | --- | --- | --- |
| Omedora release | `omedora/version` | `0.2.0-beta.7` | Public version and release tag |
| Reported Omarchy base | `omedora/base-version` | `4.5.0-rc2` | User-facing upstream compatibility label |
| Immutable git base | `omedora-base-20261027-omarchy4-5978d93a` | `5978d93ae7da0a325b7493501911e3f1266cadd3` | Rebase and byte-identity audit anchor |

The root `version` file belongs to upstream Omarchy. It remains unchanged even
when its historical prerelease text is less precise than Omedora's immutable
pin. It still provides the major used by `bin/omedora-copr` to select
`agaspar/omedora-4`.

## User-visible version

On Fedora, `omarchy-version` reports:

```text
Omedora 0.2.0-beta.7 (rebased on Omarchy 4.5.0-rc2)
```

On Arch, upstream package-version behavior remains unchanged.

## RPM versions

`omedora` and `omedora-settings` carry the Omedora release identity. RPM
prereleases replace SemVer's hyphen with `~`, so `0.2.0-beta.2` becomes
`0.2.0~beta.2` and sorts below final `0.2.0`.

Component RPMs use their component's upstream version, not the Omedora release.
A Quattro source rebase alone does not justify rebuilding unchanged component
packages. This rebase changes both core payloads, so both core specs are prepared
at `0.2.0~beta.7`.

## Release tags

Omedora releases use annotated `vX.Y.Z` or prerelease tags created by
`bin/omedora-release`. Base pins use separate annotated
`omedora-base-<date>-omarchy4-<sha8>` tags. A base pin is created before the
rebased branch is promoted; a release tag is created only after verification.

Delegated implementation work prepares file versions and the pin label but does
not create tags, push branches, or publish COPR builds.

## Update channel

Installed Omedora 4 systems consume RPMs from the per-major COPR. They do not
pull the `omedora-4` git branch. `omarchy-update-available` checks the Omedora
repo, and `omarchy update` updates an explicit Omedora-managed RPM set. Fedora
channel switching is intentionally unavailable.

The temporary git clone used by `omedora/boot.sh` is a pre-install plan source,
not an installed update channel.

## Fedora releases and COPR chroots

Omedora supports Fedora N and N-1: the current Fedora release and the one before
it. Support means the version-scoped COPR has that release's chroot (today
`fedora-44-x86_64` and `fedora-45-x86_64`). The fresh-install gate, the updater,
and `omedora-upgrade-fedora` all ask `omedora-copr --chroot-available`.

- **Every build goes to every enabled chroot.** A push builds each changed
  package for all enabled chroots; nothing is built for one release only.
- **A new release's chroot is added by hand at Fedora branching.** Omedora keeps
  no rawhide chroot, so COPR's "follow Fedora branching" has nothing to fork.
  Enable `fedora-<N>-x86_64` on the project when Fedora branches N from rawhide,
  then backfill it in dependency order with `copr-submit.sh` (re-register first;
  see the script's header):

  ```bash
  BRANCH=$(git rev-parse origin/omedora-4) omedora/packaging/copr/copr-submit.sh register
  CHROOTS=fedora-<N>-x86_64 omedora/packaging/copr/copr-submit.sh build
  ```

  Until the backfill finishes, the chroot exists but isn't complete.
  `omedora-upgrade-fedora`'s dry run catches that: it refuses while any Omedora
  package would be removed or downgraded.
- **A release's chroot is dropped after Fedora's end of life** for that release.
  N-1 reaches end of life about four weeks after N+1 is released, by which time
  N+1's chroot has been added.

## Release order

1. Rebase the patch stack onto the selected official upstream commit.
2. Prepare and create the immutable base pin.
3. Run L1 and Fedora/Arch L2.
4. Rebuild changed RPMs and verify their repository transaction.
5. Run upgrade and required L3/L4 gates against those exact builds.
6. Promote the branch with `--force-with-lease` only after review.
7. Cut the Omedora release tag after the promoted commit is final.

See [`rebase-workflow.md`](rebase-workflow.md) for mechanics and
[`testing.md`](testing.md) for the verification layers.
