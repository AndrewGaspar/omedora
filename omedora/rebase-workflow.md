# Rebase workflow

Omedora is a patch stack continuously rebased onto Omarchy's latest stable release. This doc covers the mechanics: git topology, the rebase recipe, conflict triage, and the verification matrix that gates a release.

The patch stack's spine is the **patch-stack map** in [`architecture.md` §14](architecture.md#15-patch-stack-map). The rebase workflow is a series of checks against that map.

---

## 1. Git topology

```
upstream      basecamp/omarchy on GitHub
  ├─ master   (Omarchy stable releases)
  ├─ dev      (Omarchy development branch)
  └─ rc       (Omarchy release candidates)

origin        the omedora fork on GitHub
  ├─ dev      (the omedora patch stack; rebased onto upstream releases)
  └─ tags     (omedora's own release tags, separate cadence from upstream)
```

Local setup:

```bash
git remote add upstream https://github.com/basecamp/omarchy.git
git remote add origin   https://github.com/<your-org>/omedora.git
git fetch --all --tags
```

The omedora `dev` branch is what users `git clone` and what `omarchy-update-git` pulls from. Its tip is always: `<latest upstream stable> + <omedora patch stack>`.

We never **merge** upstream into omedora's `dev`. We always **rebase** so the patch stack stays linear and individual patches retain their identity across releases.

---

## 2. Per-release rebase recipe

When Omarchy ships a new stable release (e.g., upstream tag `v6.1.0`):

### Step 1 — Fetch and identify the new base

```bash
git fetch upstream --tags
git fetch upstream master
NEW_BASE=$(git rev-parse upstream/master)   # or the tagged release SHA
OLD_BASE=$(git merge-base upstream/master origin/dev~N)   # find the base our stack sits on
                                                          # (where N = number of omedora commits)
```

In practice, tag the rebase base each time you release omedora:

```bash
git tag omedora-base-v$(date +%Y%m%d)-onto-v6.1.0 $NEW_BASE
```

This gives every omedora release a paired tag identifying which upstream tip it was rebased onto. The version banner in `bin/omarchy-version` reads this same identifier.

### Step 2 — Start a rebase branch

Never rebase `dev` directly until you're confident. Start a branch:

```bash
git checkout -b rebase/onto-v6.1.0 origin/dev
```

### Step 3 — Run the rebase

```bash
git rebase --onto $NEW_BASE $OLD_BASE
```

If your patch stack is well-organized (one logical change per commit, ordered as documented in the patch-stack map), each commit replays one at a time and conflicts appear locally.

### Step 4 — Triage conflicts

For each conflict, classify it against the patch-stack map. See [§3](#3-conflict-triage-rubric) below for the rubric.

### Step 5 — Verify after the rebase completes

```bash
test/omarchy-cli-test.sh   # must pass
omarchy commands --check   # must pass (metadata validation)
```

Then run the full verification matrix ([§4](#4-verification-matrix)) before promoting the branch to `dev`.

### Step 6 — Promote and tag

```bash
git checkout dev
git reset --hard rebase/onto-v6.1.0
git tag v<omedora-version>
git push --force-with-lease origin dev
git push origin v<omedora-version> omedora-base-v<datestamp>-onto-v6.1.0
```

**`--force-with-lease`** is mandatory: `dev` was rebased, the history changed. Users running `omedora update` (which runs `omarchy-update-git` → `git pull --rebase` or equivalent) will pick up the new tip.

---

## 3. Conflict triage rubric

Walk the patch-stack map mentally. Every conflict should fit into one of these patterns; if it doesn't, stop and think about whether the rebase is doing the right thing.

### Pattern A — Upstream renamed a file we patch

Example: `bin/omarchy-pkg-add` is renamed by upstream to `bin/omarchy-pkg-install`.

**Resolution:**

1. Move the omedora patch (the `BRAND_NAME` shim or the helper-dispatch case) to the new file.
2. Rename the sibling Fedora file too (`bin/omarchy-pkg-add-fedora` → `bin/omarchy-pkg-install-fedora`).
3. Update the patch-stack map in `architecture.md` in the same commit. Don't leave stale entries.

### Pattern B — Upstream added a new package to `omarchy-base.packages`

Example: upstream adds `new-cool-app` to the base packages list.

**Resolution:**

1. Look up `new-cool-app` in Fedora repos / RPM Fusion / vetted COPRs / Flathub (in that order).
2. Add an entry to `install/packages/fedora.toml` if needed (the [packages.md](packages.md) checklist applies).
3. The patch-stack rebase itself doesn't conflict — `omarchy-base.packages` is upstream's file and we don't patch it. The package will be installed by `install/packaging/base.sh` calling `omarchy-pkg-add`, which dispatches via the map.

### Pattern C — Upstream added a new helper command

Example: upstream adds `bin/omarchy-pkg-upgrade` to the package-helper family.

**Resolution:**

1. Read the new helper. If it calls `pacman`/`yay` directly, it needs a Fedora arm.
2. Add the same prepend-shim pattern as the existing helpers (`case "$(omarchy-distro)" in fedora) exec <name>-fedora ;; esac`).
3. Create the `<name>-fedora` sibling.
4. Add both to the patch-stack map.

This is the most common pattern. Don't be tempted to handle it inline — always use the shim+sibling structure for consistency.

### Pattern D — Upstream added a new hardware-config script

Example: upstream adds `install/config/hardware/intel/new-thing.sh`.

**Resolution:**

1. Read the script. If it's bootloader/initramfs/kernel-module territory, gate it with `[[ $(omarchy-distro) == "arch" ]] || return 0` at the top.
2. If it's partially portable, write a `new-thing-fedora.sh` sibling that includes only the portable parts.
3. Update the patch-stack map.

### Pattern E — Upstream changed the help text in `bin/omarchy`

Example: upstream rewrites `show_main_help` with new copy.

**Resolution:** this is the rebrand-shim's worst-case scenario. The patch substitutes `omarchy` → `${BRAND_NAME}` in the help-rendering path. If upstream rewrites that path, the substitution may need to be re-applied to new code. Re-do the substitution carefully — it's mechanical. If upstream factored the help rendering differently, factor the substitution to match.

This is also a good moment to consider: would upstream accept a PR that pulls the `BRAND_NAME` indirection into the dispatcher itself? If yes, send the PR — it permanently reduces our rebase risk.

### Pattern F — Upstream added a new install stage

Example: upstream adds `install/late/all.sh` between `config` and `login`.

**Resolution:**

1. Read what the new stage does. Most likely it's portable enough to run on Fedora too (configs, services, etc.).
2. Update `install.sh` to source the new stage at the right point.
3. If the new stage has Arch-only scripts, gate them as in Pattern D.
4. Update the patch-stack map.

### Pattern G — Upstream added a new migration that bypasses helpers

Example: a new `migrations/<timestamp>.sh` calls `pacman -S foo` directly.

**Resolution:** don't patch it. The migration will fail on Fedora and the user will be prompted to skip. That's the documented behavior ([architecture §9](architecture.md#9-migrations-strategy)).

If the migration is *important* (does something we want to happen on Fedora too), the right move is to file an upstream PR converting the migration to use `omarchy-pkg-add` instead of raw `pacman`. Don't fork the migration in omedora.

### Pattern H — Upstream removed a file we patch

Example: upstream deletes `bin/omarchy-pkg-aur-add` because they moved AUR handling elsewhere.

**Resolution:**

1. Audit what omedora used the file for.
2. Find the upstream replacement (or absence) and re-apply the patch there.
3. Delete the sibling file (e.g., `bin/omarchy-pkg-aur-add-fedora`) if no longer needed, or move/rename it.
4. Update the patch-stack map.

### Pattern I — Upstream changed a file shape in a way that invalidates an assumption

Example: upstream changes `install/preflight/all.sh` from sourcing individual scripts to looping over a directory.

**Resolution:**

1. Re-read the new shape.
2. Re-apply the gating logic in the new style (e.g., a name-pattern filter in the loop instead of explicit Arch-only sources).
3. Update the patch-stack map's notes on that file.

### When in doubt

If a conflict doesn't fit any pattern, **stop the rebase** (`git rebase --abort`), open the patch-stack map and the conflicting commits, and think. The map is the contract — if reality diverges, fix one or the other rather than producing a frankenpatch.

---

## 4. Verification matrix

Before promoting a rebase branch to `dev`, run all of these. Some are automated; some need a VM.

### Automated checks (must pass)

| Check | Command | What it verifies |
| --- | --- | --- |
| CLI test suite | `test/omarchy-cli-test.sh` | Dispatcher routing, metadata, command help, JSON output, executable bits |
| Metadata validation | `omarchy commands --check` | All commands have summary metadata, no route collisions, no missing binaries |
| Package map validation | `omarchy dev validate-fedora-packages` (planned) | `fedora.toml` schema correctness, allowlist compliance, installer existence |
| Shell linting | `shellcheck bin/omarchy-* install/**/*.sh` | Catches regressions in shell quality |

### Manual checks (must pass before release)

| Check | Setup | What it verifies |
| --- | --- | --- |
| **Arch regression check** | Clean Arch install, run `boot.sh` end-to-end. | Omedora behaves exactly like upstream Omarchy on Arch — no surface drift. |
| **Fedora fresh install** | Clean Fedora 44 VM, run the omedora bootstrap (`boot-omedora.sh`) end-to-end. | All stages complete; Omedora session boots; theme switch, walker, waybar, terminal launch, keybindings all work. |
| **`omedora update` on Fedora** | After a previous omedora install, run `omedora update`. | All steps succeed; idempotent (second run is a no-op). |
| **Fedora upgrade simulation** | Fedora N install → `dnf system-upgrade` to N+1 → `omedora update`. | Major-upgrade migration triggers, COPRs re-enabled, packages updated cleanly. |

### Smoke-test checklist (manual on Fedora VM after install)

In an Omedora session:

- [ ] Super-key opens walker.
- [ ] Waybar shows correct workspaces, clock, system tray.
- [ ] Mako shows test notifications (`notify-send "test"`).
- [ ] `omarchy theme set tokyo-night` switches theme; terminal, waybar, walker all reload.
- [ ] `omarchy theme set everforest` reverts cleanly.
- [ ] `omarchy capture screenshot region` runs slurp+grim and produces a file.
- [ ] `omarchy show logo` shows the OMEDORA ASCII art (Fedora) or OMARCHY (Arch).
- [ ] `omedora --version` (and `omarchy --version`) shows the right version line on each distro.
- [ ] Tab-complete works for both `omarchy<TAB>` and `omedora<TAB>`.
- [ ] `omedora update` runs to completion with no spurious errors.
- [ ] Log out, log back in — session restores cleanly.

### Hardware sanity (when applicable)

If the rebase touched any hardware-detection or hardware-config code:

- [ ] Test on at least one Intel + AMD machine (any laptop), and ideally one NVIDIA machine.
- [ ] Confirm no Arch-specific scripts fire on Fedora and vice versa.

---

## 5. Release cadence and tagging

- **Omedora release cadence follows Omarchy stable.** Each upstream stable release prompts an omedora rebase + release. We do not release omedora independent of an upstream cut.
- **Omedora's version string** lives in `omedora/version` (separate from upstream's `version`). Bump it once per omedora release. Suggested scheme: `<upstream-semver>+omedora.<integer>` (e.g., `6.1.0+omedora.0` for the first release on Omarchy 6.1.0, `6.1.0+omedora.1` for a hotfix).
- **Base tag:** every release also tags the upstream base (`omedora-base-<datestamp>-onto-v<upstream>`). This makes "what upstream commit are we on" trivially queryable.
- **Hotfixes between upstream releases:** allowed but rare. Issue an `+omedora.N` bump without changing the upstream base.

---

## 6. When the rebase is too big

If a single upstream release introduces dozens of conflicts (e.g., a major dispatcher refactor or a re-architecture of the install pipeline), the cost-benefit shifts:

1. **Consider skipping a release.** Wait for the next upstream stable that settles the dust, and rebase onto that instead. We document a "minimum upstream version supported" — going forward to the next stable is fine; going back is not.
2. **Consider splitting omedora's patch stack.** If patches naturally cluster (helper dispatch vs CLI rebrand vs update flow vs branding), rebase them as separate runs to keep conflict surfaces manageable.
3. **Consider upstreaming part of the patch.** Genuinely portable improvements (e.g., the brand-variable indirection, the `omarchy-distro` command itself) might be welcomed upstream. Each accepted PR permanently reduces our rebase surface.

The right answer depends on the change. The wrong answer is to grind through a big conflict pile and merge in a degraded state.

---

## 7. Tools we lean on

- **`git rebase`** — the workhorse.
- **`git rerere`** — recommended to enable globally (`git config --global rerere.enabled true`). Records conflict resolutions so re-running a rebase reapplies the same resolution. Cuts repetitive triage work massively.
- **`git absorb`** (if installed) — when a rebase produces small fixups after the fact, `git absorb` automatically attributes them to the right commit in the stack. Useful when you discover a missed conflict resolution.
- **`omarchy commands --check`** — the metadata validator. Run after every helper-touching change.
- **`test/omarchy-cli-test.sh`** — the existing CLI test suite. Treat it as authoritative.

---

## 8. Agent-driven rebasing

The long-term goal is for Claude to drive most of the rebase work. The patterns in [§3](#3-conflict-triage-rubric) are deliberately mechanical so that an agent can:

1. Run the rebase.
2. For each conflict, identify the pattern from the patch-stack map and the file path.
3. Apply the documented resolution.
4. Run automated verification.
5. Hand off to a human for the manual verification matrix and the final force-push.

`omedora/AGENTS.md` documents the agent-specific rules of engagement for this loop, including when to stop and ask for human intervention. Conflicts that fall outside the documented patterns are always stop-and-ask cases.
