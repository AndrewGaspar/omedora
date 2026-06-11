# Omedora versioning, releases & updates

How omedora versions itself, cuts releases, serves packages, and how an install
checks for and applies updates. This is the contract the launch (#87) depends on.

## Version identity

Two numbers, two files:

| File | Meaning | Moves when |
|---|---|---|
| `omedora/version` | **omedora's own SemVer** (e.g. `0.1.0`) — the public version | we ship features/fixes/package bumps |
| `version` | the **Omarchy base** we're rebased on (e.g. `3.8.2`) | we rebase onto a new Omarchy |

`omarchy-version` prints both: `Omedora 0.1.0 (rebased on Omarchy 3.8.2)`. The
omedora number is the public identity we tag and advertise; the Omarchy number
is the upstream baseline.

## Releases = annotated git tags `vX.Y.Z`

Cut a release with **`omedora-release <version> [--push]`** (`bin/omedora-release`):
it validates the new SemVer is greater than current, bumps `omedora/version`,
prepends a `omedora/CHANGELOG.md` section (auto-filled from commits since the
last tag), commits `release: omedora vX.Y.Z (Omarchy <base>)`, and creates the
annotated tag `vX.Y.Z`. With `--push` it pushes the branch + tag.

Tags are the spine of update detection: `omarchy-update-available` compares the
newest remote tag against the installed one, so **tagging is what tells installs
an update exists.**

## Channels & bootstrap

Fresh Fedora installs come through **`omedora/boot.sh`** (the curl-able entry;
the top-level `boot.sh` stays Arch/pacman-only). Channel via `OMEDORA_REF`:

| `OMEDORA_REF` | resolves to | for |
|---|---|---|
| `stable` (default) | the repo's **default branch** | normal installs |
| `dev` | the `dev` branch | latest, unstable |
| `rc` | the `rc` branch | release candidates |
| `<branch\|tag>` | that exact ref | pinning |

**Maintainer contract:** keep the GitHub **default branch pointed at the current
stable release line** (e.g. `3.8.2-omedora`), and cut `vX.Y.Z` tags on it with
`omedora-release`. Then `stable` installs land on that line and update detection
compares its tags.

## Packages = the per-major-line COPR

RPMs are served from a COPR whose project is **scoped per Omarchy major line**:
`omedora-<major>` (today `agaspar/omedora-3`, for the whole Omarchy 3.x line).
The single source of truth is **`bin/omedora-copr`** (`owner/project`, or the dnf
repo id via `--repo-id`); nothing else hard-codes the name. A routine patch bump
(3.8.2 → 3.8.3) stays on the same COPR; a rebase onto Omarchy 4.x bumps the
`version` major → a new isolated COPR (`omedora-4`) so existing installs never
get an ABI-incompatible rebuild pushed underneath them.

RPM `Version:` fields track **upstream** (hyprland 0.55.2, uwsm 0.26.4), *not*
omedora's number. The COPR auto-rebuilds on push, so package updates flow through
`dnf upgrade` independently of omedora releases.

## Updates: two channels, one command

`omarchy update` works on Fedora:

1. **`omarchy-update-git`** — `git pull` the omedora source (config/bin). Like
   Omarchy, this does **not** re-copy `config/*` over your `~/.config`; those are
   yours to edit, and migrations handle any required config changes.
2. **`omarchy-update-perform`** dispatches on Fedora to
   **`omarchy-update-perform-fedora`**, which runs **`omedora-update-pkgs`**
   (`dnf upgrade --refresh` — pulls new COPR builds + system updates), then
   migrations / post-update hook / restart. No pacman, AUR, keyring, or btrfs
   snapshot.

**Check** for updates with `omarchy-update-available` (brand-aware:
"Omedora update available (vX.Y.Z)") — config/bin updates ride the git tags,
package updates ride the COPR.

## At a glance

```
omedora/version   0.1.0     ← public SemVer; tagged vX.Y.Z by omedora-release
version           3.8.2     ← Omarchy base; its major names the COPR (omedora-3)
bin/omedora-copr            ← single source of truth for the COPR name
bin/omedora-release         ← cut a release (bump + changelog + tag)
omedora/boot.sh             ← Fedora bootstrap (stable|dev|rc channel)
omarchy update              ← git pull + dnf upgrade (Fedora pipeline)
```
