# Rebase workflow for Omedora 4

Omedora 4 is a package-backed patch stack on top of Omarchy 4. Installed Fedora
systems use `omedora` and `omedora-settings` RPMs from the Omedora COPR; they do
not pull the `omedora-4` branch. This permits a reviewed, force-with-lease rebase
workflow on this line. Omedora 3 remains append-only because those installs use
a git checkout.

## 1. Current topology

| Ref | Purpose |
| --- | --- |
| `omarchy` remote | `omacom/omarchy` upstream |
| upstream `v4.0.2` | Official release at `346e69e1cec6c4e8924531874af6ba010a1bc99e` |
| `origin/omedora-4` | Omedora patch stack |
| `omedora-base-20260905-omarchy4-346e69e1` | Immutable pin for this rebase |

The pin label is recorded at the top of [`architecture.md`](architecture.md).
`test/byte-identity-test.sh` reads it there. During delegated review, before the
tag exists, pass the official commit through `OMEDORA_BASE_TAG`.

## 2. Isolated rebase

Never rebase a maintainer worktree in place. Fetch the selected upstream object
without creating a local upstream release tag, then create an isolated branch:

```bash
git fetch --no-tags omarchy 346e69e1cec6c4e8924531874af6ba010a1bc99e
git worktree add -b agent/quattro-rebase \
  /home/ajg/code/omedora-quattro-rebase origin/omedora-4
```

Replay only Omedora commits above the previous immutable base:

```bash
git rebase --onto \
  346e69e1cec6c4e8924531874af6ba010a1bc99e \
  f0020448ca87329199de7cb12f2015ebc4a3e5e7
```

Using explicit `--onto <new-base> <old-base>` is mandatory. Upstream branches
may be rewritten; a merge-base-derived rebase can accidentally replay upstream
history as Omedora work.

## 3. Conflict and semantic review

Textual conflict freedom is not semantic proof. After replay:

1. List files changed by both upstream and Omedora.
2. Review every clean auto-merge in that intersection.
3. Compare package manifests, migrations, setup entry points, update flow, and
   visual defaults even when they did not conflict.
4. Classify every modified upstream path in the patch-stack map.
5. Run byte identity against the exact new commit.

Common cases:

| Upstream change | Omedora response |
| --- | --- |
| New base package | Resolve it through Fedora repos/map; add a reasoned map entry when needed |
| New Arch-only migration | Add an early Fedora gate and runtime coverage |
| New pacman/helper command | Add a top dispatch and Fedora sibling; retain the Arch body |
| Removed/replaced component | Drop obsolete Omedora patches rather than preserving dead behavior |
| Changed help/menu output | Reapply only the narrow branding or availability adaptation |
| Changed wallpaper/default | Require L4 visual review; do not blindly update the golden |

Migration files are an explicit exception to the general preference for leaving
upstream history untouched: an ungated Arch migration blocks the package-backed
Fedora migration pipeline, so it is patched in place and tested.

## 4. Pin rotation

Prepare the label from the rebase date and upstream SHA:

```bash
NEWPIN=omedora-base-20260905-omarchy4-346e69e1
```

After parent review, create the annotated tag at the upstream commit:

```bash
git tag -a "$NEWPIN" 346e69e1cec6c4e8924531874af6ba010a1bc99e \
  -m "Omedora base pin: Omarchy v4.0.2 @ 346e69e1"
```

Do not create or push the tag from delegated implementation work. Existing pin
tags are immutable and are never moved or deleted.

## 5. Byte identity

Run before and after authored fixes:

```bash
OMEDORA_BASE_TAG=346e69e1cec6c4e8924531874af6ba010a1bc99e \
  bash test/byte-identity-test.sh
```

An unallowlisted deletion means either an upstream behavior was accidentally
lost or a real relocation needs exact documentation. Never add an allowlist
entry merely to make the test green. Remove stale entries once the new base
contains the formerly forward-ported upstream change.

## 6. Verification matrix

### L1

```bash
for test in test/*-test.sh; do bash "$test" || break; done
bin/omarchy-dev-validate-fedora-packages
bash test/cli
bin/omarchy commands --check
```

### L2

```bash
omedora/test/fedora/run-integration.sh

docker run --rm -v "$PWD:/repo" -w /repo archlinux:latest bash -c '
  pacman -Syu --noconfirm --needed jq python git gum ripgrep fontconfig >/dev/null
  bash test/cli
'
```

### L3 and L4

Run the fresh-install/update/upgrade gates and both nested-session and VM visual
gates described in [`testing.md`](testing.md). Report unavailable tiers as
unavailable. A candidate is not release-ready until new core RPMs exist for L3
and the official 4.0.2 visual changes have been reviewed at L4.

## 7. Package impact

Determine rebuilds from payload changes, not from the rebase itself:

- Changes under runtime commands, migrations, themes, install helpers, or
  `shell/` require `omedora`.
- Changes under config/default assets, branding, or packaged system files
  require `omedora-settings`.
- Component specs rebuild only when their source, patch, or ABI requirement
  changes.
- HypXR is a separate package stream. Do not fold another agent's HypXR refresh
  into a Quattro rebase commit.

For the official 4.0.2 rebase, rebuild `omedora` and `omedora-settings`; no
rebase-driven HypXR ABI rebuild is required.

## 8. Promotion

After all required verification and review:

1. Create and push the immutable base pin first so CI can resolve it.
2. Promote the reviewed branch with `git push --force-with-lease`, never plain
   `--force`.
3. Rebuild changed core RPMs explicitly; do not rely on an orphaned pre-rebase
   `before` SHA to select packages.
4. Verify the published RPM transaction and upgrade path.
5. Cut the Omedora release tag last.

No push, COPR publication, GitHub mutation, or release tag belongs in an
isolated delegated implementation task unless explicitly authorized.
