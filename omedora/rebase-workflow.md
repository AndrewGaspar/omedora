# Upstream sync workflow (omedora-3)

Omedora carries a patch stack on top of an upstream Omarchy base. This doc covers the mechanics of taking a new upstream release: git topology, the **append-only cherry-pick recipe**, conflict triage, and the verification matrix that gates a release.

> **The one hard rule: never force-push `omedora-3`.** Installed machines refresh
> their checkout with `git pull --autostash` (`bin/omarchy-update-git`) — there is
> no `reset --hard` fallback anywhere on the auto-update path. The published branch
> must only ever move forward (fast-forward), or every existing install's next
> `omedora update` wedges in a divergent merge. This is why upstream syncs are
> **cherry-picked forward**, not rebased: a rebase rewrites the stack's SHAs and
> requires exactly the force-push we cannot do. (Contrast: the omedora-4 line is
> unreleased and package-backed, so it still rebases freely onto its pin tag.)

The patch stack's spine is the **patch-stack map** in [`architecture.md` §14](architecture.md#15-patch-stack-map). The sync workflow is a series of checks against that map.

---

## 1. Git topology

```
omarchy       basecamp/omarchy on GitHub (the upstream remote)
  ├─ master / rc / dev   (Omarchy branches; dev is force-push-prone)
  └─ vX.Y.Z tags         (Omarchy stable releases — sync tag-to-tag, never to dev)

origin        AndrewGaspar/omedora on GitHub
  ├─ omedora-3           (the published branch: embedded upstream history +
  │                       omedora patch stack + cherry-picked upstream deltas.
  │                       Append-only. What users clone and `git pull`.)
  ├─ 3.8.2-omedora       (legacy alias; keep fast-forwarded to omedora-3's tip —
  │                       shipped v0.1.x bootstraps have it baked in)
  └─ v0.1.x tags         (omedora's own releases, cut by bin/omedora-release)
```

The upstream base we sit on is recorded in the top-level `version` file (see
[versioning.md](versioning.md)); there is no separate pin-tag mechanism on this line.

**Lineage caveat:** upstream has rewritten history before (a mid-2025 rewrite
dropped GPG signatures, giving ~4k commits new SHAs with identical trees; the
current tags are back on the signed lineage omedora embeds). So never trust a
merge-base against an upstream *branch* — always verify tag-to-tag ancestry
first, and fall back to content-level dedup (step 2) if the tags moved lineage.

---

## 2. Per-release sync recipe (append-only cherry-pick)

When Omarchy ships a new stable release (e.g., upstream tag `v3.8.4`, with the
previous synced base recorded in `version` as `3.8.3`):

### Step 1 — Fetch and check the range is clean

```bash
git fetch omarchy --tags
git merge-base --is-ancestor v3.8.3 v3.8.4 && echo CLEAN || echo REWRITTEN
```

`CLEAN` is the normal case. `REWRITTEN` means upstream moved lineage again —
the range will contain rewritten-but-content-identical commits; the dedup in
step 2 handles them, but scope the delta with `git diff v3.8.3 v3.8.4` first
to know what's genuinely new.

### Step 2 — Scope, then cherry-pick the delta onto the branch tip

```bash
# What's coming, and where it collides with our modified-upstream files:
git log --oneline --no-merges v3.8.3..v3.8.4
comm -12 <(git diff --name-only <in-tree-base> HEAD | sort) \
         <(git diff --name-only v3.8.3 v3.8.4 | sort)

# The pick: patch-id dedup drops commits we already carry (earlier cherry-picks,
# rc/master double-commits); --empty=drop collapses the rest of the duplicates.
picks=$(git rev-list --right-only --cherry-pick --no-merges --reverse HEAD...v3.8.4)
git cherry-pick --empty=drop -x $picks
```

`-x` records `(cherry picked from commit …)` so provenance survives. Resolve
conflicts per the rubric in [§3](#3-conflict-triage-rubric), always preserving
omedora's Fedora gates/dispatch/branding on our side of the merge.

### Step 3 — Record the new base + port the delta

- Confirm the top-level `version` file ends at the new upstream version
  (upstream's own bump usually arrives in the delta; hand-set it if their tag
  carries a stale file — it happens).
- Audit the delta for Fedora work: new packages → `install/packages/fedora.toml`
  mappings; new migrations → trace what each does on a Fedora machine; new
  helpers/hardware scripts → the patterns in [§3](#3-conflict-triage-rubric).

### Step 4 — Verify

```bash
test/omarchy-cli-test.sh   # must pass
omarchy commands --check   # must pass (metadata validation)
```

Then the full verification matrix ([§4](#4-verification-matrix)).

### Step 5 — Release and push (plain push, never force)

```bash
bin/omedora-release <new-omedora-semver> --push   # changelog + tag vX.Y.Z + push
git push origin omedora-3:3.8.2-omedora           # keep the legacy alias current
```

Sanity check that the push was a fast-forward (it must be, if nothing was
rebased): a scratch `git pull` on a pre-sync clone should fast-forward cleanly.

---

## 3. Conflict triage rubric

Walk the patch-stack map mentally. Every conflict should fit into one of these patterns; if it doesn't, stop and think about whether the sync is doing the right thing.

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
3. The pick itself doesn't conflict — `omarchy-base.packages` is upstream's file and we don't patch it. The package will be installed by `install/packaging/base.sh` calling `omarchy-pkg-add`, which dispatches via the map.

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

This is also a good moment to consider: would upstream accept a PR that pulls the `BRAND_NAME` indirection into the dispatcher itself? If yes, send the PR — it permanently reduces our sync risk.

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

If a conflict doesn't fit any pattern, **stop the sync** (`git cherry-pick --abort`), open the patch-stack map and the conflicting commits, and think. The map is the contract — if reality diverges, fix one or the other rather than producing a frankenpatch.

---

## 4. Verification matrix

Before cutting the release that ships a sync, run all of these. Some are automated; some need a VM.

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

If the sync touched any hardware-detection or hardware-config code:

- [ ] Test on at least one Intel + AMD machine (any laptop), and ideally one NVIDIA machine.
- [ ] Confirm no Arch-specific scripts fire on Fedora and vice versa.

---

## 5. Release cadence and tagging

Versioning is authoritative in [versioning.md](versioning.md); summary:

- **Two numbers.** `omedora/version` is omedora's own SemVer (`0.1.x`, tagged
  `vX.Y.Z` by `bin/omedora-release`); the top-level `version` file records the
  Omarchy base we're synced to (its major names the COPR, e.g. `omedora-3`).
- **Cadence is decoupled.** Omedora releases whenever there's something to ship —
  fixes, package bumps, or an upstream sync. An upstream sync bumps the base
  file; the release that ships it advances the SemVer like any other release
  and gets a changelog header of `(Omarchy <base>)`.
- **No base tags on this line.** The `version` file is the pin; `omedora-base-*`
  tags are an omedora-4 mechanism.

---

## 6. When the delta is too big

If a single upstream release introduces dozens of conflicts (e.g., a major dispatcher refactor or a re-architecture of the install pipeline), the cost-benefit shifts:

1. **Consider skipping a release.** Wait for the next upstream stable that settles the dust, and sync to that instead. We document a "minimum upstream version supported" — going forward to the next stable is fine; going back is not.
2. **Consider splitting omedora's patch stack.** If patches naturally cluster (helper dispatch vs CLI rebrand vs update flow vs branding), pick them as separate passes to keep conflict surfaces manageable.
3. **Consider upstreaming part of the patch.** Genuinely portable improvements (e.g., the brand-variable indirection, the `omarchy-distro` command itself) might be welcomed upstream. Each accepted PR permanently reduces our sync surface.

The right answer depends on the change. The wrong answer is to grind through a big conflict pile and merge in a degraded state.

---

## 7. Tools we lean on

- **`git cherry-pick`** — the workhorse (`--empty=drop -x`, over a patch-id-deduped `rev-list`).
- **`git rerere`** — recommended to enable globally (`git config --global rerere.enabled true`). Records conflict resolutions so re-running a pick reapplies the same resolution. Cuts repetitive triage work massively.
- **`git absorb`** (if installed) — when a sync produces small fixups after the fact, `git absorb` automatically attributes them to the right commit in the stack. Useful when you discover a missed conflict resolution.
- **`omarchy commands --check`** — the metadata validator. Run after every helper-touching change.
- **`test/omarchy-cli-test.sh`** — the existing CLI test suite. Treat it as authoritative.

---

## 8. Agent-driven syncing

The long-term goal is for Claude to drive most of the sync work. The patterns in [§3](#3-conflict-triage-rubric) are deliberately mechanical so that an agent can:

1. Run the cherry-pick.
2. For each conflict, identify the pattern from the patch-stack map and the file path.
3. Apply the documented resolution.
4. Run automated verification.
5. Hand off to a human for the manual verification matrix and the release cut (a plain, fast-forward push).

`omedora/AGENTS.md` documents the agent-specific rules of engagement for this loop, including when to stop and ask for human intervention. Conflicts that fall outside the documented patterns are always stop-and-ask cases.
