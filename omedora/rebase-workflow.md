# Rebase workflow (omedora-4)

Omedora is a patch stack carried on top of an upstream Omarchy 4 base. On this line the stack is **rebased onto a pin tag and force-pushed**. This doc covers the mechanics: git topology, the per-resync rebase recipe, the pin-tag rotation, conflict triage, and the verification matrix that gates a release.

> **Force-pushing `omedora-4` is correct here.** Installs on this line are
> **package-backed**: the `omedora` + `omedora-settings` RPMs from the
> `agaspar/omedora-4` COPR own `/usr/share/omarchy` and `/usr/bin/omarchy-*`
> ([`architecture.md` §16](architecture.md#16-omarchy-4-setup-system-gating-map)),
> and updates are `dnf`-backed end to end — `bin/omarchy-update`'s pipeline has
> **no git step at all** (`omarchy-update-git` does not exist on this branch),
> `omarchy-update-system-pkgs` dispatches to `sudo dnf upgrade --refresh` on
> Fedora, and `omarchy-update-available` dispatches to `bin/fedora/update-available`
> (`dnf check-upgrade --repo $(omedora-copr --repo-id)`). `omarchy-channel-set` is
> a no-op on Fedora. The only git touching a user's machine is `omedora/boot.sh`'s
> **shallow throwaway clone** (`git clone --depth 1 --branch omedora-4` into
> `~/.cache/omedora/bootstrap`) used once, to run the plan gate before any package
> lands; it is deleted-and-recreated on every run and never pulled. COPR clones the
> repo fresh per build (CI pins the SCM committish to the pushed SHA). **No
> installed machine has a checkout of this branch to fast-forward**, so rewriting
> its history breaks nobody.
>
> **Contrast — `omedora-3` must NEVER be force-pushed.** That line's installed
> machines refresh their `~/.local/share/omarchy` checkout with
> `git pull --autostash` (`bin/omarchy-update-git`) and its update detection
> compares git *tags*; a rewritten history wedges every existing install in a
> divergent merge. So omedora-3 syncs upstream by **append-only cherry-pick** and
> pushes fast-forward only — see [that branch's
> `omedora/rebase-workflow.md`](https://github.com/AndrewGaspar/omedora/blob/omedora-3/omedora/rebase-workflow.md).
>
> **The condition that ends v4's freedom:** if a user-facing git-clone-and-pull
> update path is ever introduced on this line (a `dev` channel that checks out the
> branch, an `omarchy-update-git` equivalent, tag-based update detection against
> `origin/omedora-4`), the append-only rule applies **from that moment on** — the
> rebase recipe below becomes forbidden and this doc must be replaced with the
> omedora-3 cherry-pick recipe.

The patch stack's spine is the **patch-stack map** in [`architecture.md` §15](architecture.md#15-patch-stack-map), extended for the v4 entry points by the **setup-system gating map** in [§16](architecture.md#16-omarchy-4-setup-system-gating-map). The rebase workflow is a series of checks against those maps.

---

## 1. Git topology

```
omarchy       basecamp/omarchy on GitHub (the upstream remote — NOT "upstream")
  ├─ quattro  the active Omarchy 4 line (was `omarchy-4`; renamed mid-port).
  │           Force-push-prone.
  ├─ master / rc / dev   the Omarchy 3.x lines; irrelevant to this branch
  └─ vX.Y.Z tags         Omarchy 3.x releases; this line has no v4 tags to sync to

origin        AndrewGaspar/omedora on GitHub
  ├─ omedora-4                the patch stack (99 commits over the pin, today).
  │                           Rebased + force-pushed. Nothing user-facing pulls it.
  ├─ omedora-3                the stable, append-only line
  └─ omedora-base-* tags      one per rebase: the upstream commit the stack sits on
```

Local setup:

```bash
git remote add omarchy https://github.com/basecamp/omarchy
git remote add origin  https://github.com/AndrewGaspar/omedora
git fetch --all --tags
```

### The pin tag

There is no "upstream release" to rebase onto — Omarchy 4 ships from a moving branch. So the base is an **immutable annotated tag we cut ourselves** at the upstream commit we rebased onto:

```
omedora-base-<YYYYMMDD>-omarchy4-<sha8>
```

`<YYYYMMDD>` is the rebase date, `<sha8>` the 8-char abbreviation of the upstream commit. Today's pin is `omedora-base-20260703-omarchy4-1e996609` (`omarchy/quattro` @ `1e996609`, tagged 2026-07-03). Its predecessor `omedora-base-20260611-omarchy4-17f024d4` is kept — **never delete an old pin tag**; they are the audit's history and the only stable reference to a rewritten lineage.

**The pin is recorded in exactly one place: the status banner at the top of [`architecture.md`](architecture.md).** [`test/byte-identity-test.sh`](../test/byte-identity-test.sh) re-derives it from there with

```bash
grep -oE 'omedora-base-[0-9]+-omarchy4-[0-9a-f]+' omedora/architecture.md | head -1
```

so rotating the pin is a one-line doc edit plus the tag; the audit follows automatically. (`OMEDORA_BASE_TAG` overrides it for local experiments.)

We never **merge** upstream into `omedora-4`. We always **rebase**, so the stack stays linear, each patch keeps its identity across resyncs, and the byte-identity audit has a single clean base to diff against.

---

## 2. Per-resync rebase recipe

Upstream `quattro` moves continuously (476 commits past the current pin as of this writing). Resync when the drift is worth paying for — a needed fix, a new base package, or before a release.

### Step 1 — Fetch and classify the move

```bash
git fetch omarchy --tags
PIN=$(grep -oE 'omedora-base-[0-9]+-omarchy4-[0-9a-f]+' omedora/architecture.md | head -1)

git merge-base --is-ancestor "$PIN^{commit}" omarchy/quattro \
  && echo "CLEAN (new tip descends from the pin)" \
  || echo "REWRITTEN (upstream force-pushed)"

git rev-list --count "$PIN..omarchy/quattro"   # how much is coming
git rev-list --count "$PIN..HEAD"              # our stack size
```

- **CLEAN** — the normal case. `git rebase omarchy/quattro` is safe: the merge-base *is* the pin, so only our commits replay.
- **REWRITTEN** — upstream re-hashed the commits our pin sits on. A plain `git rebase omarchy/quattro` now computes a merge-base far in the past and tries to replay **hundreds of upstream commits as if they were ours**. You must scope the replay explicitly:

  ```bash
  git rebase --onto omarchy/quattro "$PIN"
  ```

  Using `--onto <new> <old-pin>` is always correct and is the safer default even in the CLEAN case.

> **Upstream lineage caveat.** basecamp/omarchy has rewritten history before: a
> mid-2025 signature-stripping rewrite gave ~4k commits new SHAs with **identical
> trees**, and `quattro`/`dev` force-push routinely. Never trust a merge-base
> against an upstream *branch* blindly. When a rebase suddenly looks enormous,
> check whether the trees are the same before believing the commit count:
>
> ```bash
> git rev-parse "$PIN^{tree}"            # old base tree
> git rev-parse omarchy/quattro^{tree}   # candidate new base tree
> ```
>
> Equal trees mean a metadata-only rewrite — the "rebase" is a pure re-parent and
> should produce zero content conflicts. Unequal trees mean real upstream work;
> scope it with `git log --oneline --no-merges "$PIN..omarchy/quattro"` and
> `git diff --name-only "$PIN" omarchy/quattro` before starting.

### Step 2 — Run the rebase on a scratch branch

Never rebase `omedora-4` in place until you're confident:

```bash
git checkout -b rebase/onto-quattro-$(date +%Y%m%d) omedora-4
git rebase --onto omarchy/quattro "$PIN"
```

Before starting, it is worth knowing exactly where the delta collides with files we patch:

```bash
comm -12 <(git diff --name-only "$PIN" HEAD | sort) \
         <(git diff --name-only "$PIN" omarchy/quattro | sort)
```

That intersection is the conflict forecast, and every entry in it should be findable in the patch-stack map.

### Step 3 — Triage conflicts

For each conflict, classify it against the maps. See [§3](#3-conflict-triage-rubric) for the rubric. **Fold each resolution into the commit it belongs to** (that is what `git rebase` does by default when the conflict lands on that commit) rather than appending fixups — the stack must stay one-logical-change-per-commit so the *next* rebase is legible. Record notable resolutions in the rebase commit message; the executed 2026-07-03 rebase (`c0a2ef5c`) is the worked example:

- upstream renamed `omarchy-4` → `quattro`, 267 commits past the old pin, a clean linear descendant;
- 80-commit stack replayed with three resolutions (a distro early-exit that had to move above quattro's new `set -euo pipefail`; a menu-data relabel re-applied over upstream's new keys; one patch **dropped entirely** because upstream gutted the widget it patched);
- byte-identity green against the new pin, 56 modified upstream files.

Dropping a patch that upstream made unnecessary is a *good* outcome — it shrinks the stack. Say so in the commit message and remove the corresponding ALLOW entry.

### Step 4 — Rotate the pin tag

```bash
SHA8=$(git rev-parse --short=8 omarchy/quattro)
NEWPIN="omedora-base-$(date +%Y%m%d)-omarchy4-$SHA8"
git tag -a "$NEWPIN" omarchy/quattro \
  -m "Omedora base pin: omarchy/quattro @ $SHA8 ($(date +%F) rebase)"
```

Then update the pin reference in [`architecture.md`](architecture.md)'s status banner (the single source of truth — the audit greps it). Grep for stragglers:

```bash
grep -rn 'omedora-base-[0-9]*-omarchy4-' omedora/ .github/
```

### Step 5 — Re-derive the byte-identity ALLOW table

[`test/byte-identity-test.sh`](../test/byte-identity-test.sh) enforces that every file we modify **that also exists upstream** is additive-only against the pin, except for a per-file allowlist of exact deleted line texts (the documented "if/else relocations", where an upstream line moves verbatim into the Arch arm of a distro gate). Its header comment is the maintenance contract; read it before editing the table.

```bash
bash test/byte-identity-test.sh
```

Rotating the pin changes the baseline, so the table needs a pass:

- **`# UNALLOWED deletion(s) in <path>`** — either the relocation is new (add the exact deleted line text to `ALLOW["<path>"]` with a one-line note explaining the gate), or a resolution accidentally dropped upstream behavior. Check which before allowlisting.
- **`# WARNING: allowlist has a stale entry`** — the file no longer differs from the pin, or no longer deletes that line. Delete the entry. This is the normal way an entry retires: e.g. the `bin/omarchy-launch-webapp` entry exists only because a cherry-picked upstream commit sits *ahead* of the pin, and unwinds itself once the pin rotates past it.
- Note that one bash associative-array key holds **all** allowed deletions for a file, newline-separated — a second `ALLOW["same/path"]=` assignment silently overwrites the first.

### Step 6 — Verify

Run the full L1 gate and, before a release, the manual tiers — [§4](#4-verification-matrix).

### Step 7 — Promote and push (force-push is expected)

```bash
git checkout omedora-4
git reset --hard rebase/onto-quattro-<date>

git push origin "$NEWPIN"                          # tag FIRST — see below
git push --force-with-lease origin omedora-4
```

- **Push the pin tag before the branch.** CI's `shell-unit` job checks out with `fetch-depth: 0` precisely so the byte-identity audit can reach the pin; if the tag isn't on `origin` yet the audit degrades to a TAP `SKIP` instead of a real gate.
- **`--force-with-lease`, not `--force`** — it still refuses if someone else moved the branch.
- **COPR after a force-push.** `.github/workflows/copr-build.yml` decides what to rebuild by diffing against the push's `before` SHA, which a rebase orphans; it falls back to `HEAD~1` (commit `f86b09fc`), which under-selects after a big replay. If specs or the RPM payload moved in the resync, re-run the workflow via `workflow_dispatch` with an explicit package list, or use `omedora/packaging/copr/copr-submit.sh build <specs...>`. In-flight builds are unaffected: CI registers each COPR package with the **pushed SHA** as the SCM committish, not the branch name.
- **Release tags are not rewritten by a rebase.** A `vX.Y.Z` tag cut before a resync keeps pointing at the pre-rebase commit and stops being an ancestor of the branch. That is harmless on this line (update detection is `dnf`-based, not tag-based) but it does mean **cut releases after the rebase, not before**.

---

## 3. Conflict triage rubric

Walk the patch-stack map mentally. Every conflict should fit into one of these patterns; if it doesn't, stop and think about whether the rebase is doing the right thing.

Two structural conventions decide most resolutions on this line:

- **`bin/` helpers** get a top-of-file `case "${OMARCHY_DISTRO:-$(omarchy-distro …)}" in fedora) exec …` dispatch to a sibling under **`bin/fedora/<name>`** (no `omarchy-` prefix). The Arch body below stays byte-identical.
- **Scripts under `install/`** get the same top-of-file dispatch to a **`<name>-fedora.sh`** sibling in the same directory, or an Arch-only early return.

### Pattern A — Upstream renamed a file we patch

Example: `bin/omarchy-pkg-add` is renamed by upstream to `bin/omarchy-pkg-install`.

**Resolution:**

1. Move the omedora patch (the distro dispatch, or the `BRAND_NAME` shim) to the new file.
2. Rename the Fedora sibling too (`bin/fedora/pkg-add` → `bin/fedora/pkg-install`), and fix the `exec` path in the dispatch.
3. Update the patch-stack map in `architecture.md` in the same commit. Don't leave stale entries.
4. Re-key the file's `ALLOW` entry in `test/byte-identity-test.sh` if it had one.

### Pattern B — Upstream added a new package to `install/omarchy-base.packages`

Example: upstream adds `new-cool-app` to the base package list.

**Resolution:**

1. Look up `new-cool-app` in Fedora repos / RPM Fusion / vetted COPRs / Flathub / an omedora RPM (in that order — the [packages.md](packages.md) tiering rules and review checklist apply).
2. Add an entry to `install/packages/fedora.toml`; if it needs an omedora-built RPM, add the spec under `omedora/packaging/copr/` and wire it into `build-repo.sh`'s `SPECS` order.
3. The rebase itself doesn't conflict — `omarchy-base.packages` is upstream's file and we don't patch it. `omedora/install/packages.sh` resolves it through the map at install time.
4. `bin/omarchy-dev-validate-fedora-packages` must pass afterwards. If the new package also has to survive an upgrade, check `test/upgrade-to-4-test.sh`'s kept-packages cross-check.

### Pattern C — Upstream added a new helper command

Example: upstream adds `bin/omarchy-pkg-upgrade` to the package-helper family.

**Resolution:**

1. Read the new helper. If it calls `pacman`/`yay`/`checkupdates` directly, or reads pacman state, it needs a Fedora arm.
2. Add the top-of-file dispatch (`case … fedora) exec "$(dirname -- "${BASH_SOURCE[0]}")/fedora/<name>" "$@" ;; esac`).
3. Create the `bin/fedora/<name>` sibling, matching the upstream contract exactly (same stdout shape, same exit codes, same state files — see `bin/fedora/update-available` for how literally that is taken).
4. Add both to the patch-stack map.

This is the most common pattern. Don't be tempted to handle it inline — always use the dispatch+sibling structure, because it is what keeps the Arch path byte-identical and the audit green.

### Pattern D — Upstream added a new hardware-config script

Example: upstream adds `install/hardware/intel/new-thing.sh`.

**Resolution:**

1. Read the script. If it's bootloader/initramfs/DKMS/kernel-module territory, it does not run on Fedora — add it to the excluded set in `install/hardware/all-fedora.sh` **with a reason** (that file is the stage-level allowlist, not a per-script gate).
2. If it's partially portable, either add it to the portable subset or write a `-fedora.sh` sibling containing only the portable parts.
3. Update the [§16 gating map](architecture.md#16-omarchy-4-setup-system-gating-map) row.

### Pattern E — Upstream changed the help text in `bin/omarchy`

Example: upstream rewrites `show_main_help` with new copy.

**Resolution:** this is the rebrand-shim's worst-case scenario. The patch substitutes `omarchy` → `${BRAND_NAME}` in the help-rendering path. If upstream rewrites that path, the substitution may need to be re-applied to new code. Re-do the substitution carefully — it's mechanical. If upstream factored the help rendering differently, factor the substitution to match. `bash test/cli` and `omarchy commands --check` are the acceptance test.

This is also a good moment to consider: would upstream accept a PR that pulls the `BRAND_NAME` indirection into the dispatcher itself? If yes, send the PR — it permanently reduces our rebase risk.

### Pattern F — Upstream added a new setup stage or entry point

Example: upstream adds `install/config/new-thing.sh`, or a new step inside `omarchy-setup-system` / `omarchy-finalize-user` / `omarchy-first-run`.

**Resolution:**

1. Read what the new step does. Most config-level work is portable enough to run on Fedora unchanged.
2. If it isn't, gate or dispatch it per the conventions above — and remember the Fedora install driver is omedora-owned (`omedora/install-4.sh` → `omedora/install/*.sh`), so a genuinely new *stage* may also need a line there.
3. Give it a row in the [§16 gating map](architecture.md#16-omarchy-4-setup-system-gating-map) with an explicit decision and reason. Every script those entry points run must have a row; an unlisted new script is an unfinished rebase. `test/archism-gating-test.sh` and `test/etc-overrides-audit-test.sh` are the automated backstops.

### Pattern G — Upstream added a new migration that bypasses helpers

Example: a new `migrations/<timestamp>.sh` calls `pacman -S foo` or writes an Arch-only path directly.

**Resolution:** don't fork the migration. Gate it the way the existing ones are gated (`test/migration-gating-test.sh` encodes the expected shape and will tell you which new migrations are unclassified); an ungated Arch-ism fails on Fedora and the user is prompted to skip, which is the documented behavior ([architecture §9](architecture.md#9-migrations-strategy)).

If the migration is *important* (does something we want to happen on Fedora too), the right move is to file an upstream PR converting it to `omarchy-pkg-add` instead of raw `pacman`.

### Pattern H — Upstream removed a file we patch

Example: upstream deletes `bin/omarchy-pkg-aur-add` because AUR handling moved elsewhere.

**Resolution:**

1. Audit what omedora used the file for.
2. Find the upstream replacement (or absence) and re-apply the patch there.
3. Delete the Fedora sibling (`bin/fedora/<name>`) if no longer needed, or move it.
4. Update the patch-stack map **and** drop the file's `ALLOW` entry — the audit will warn about it as stale on the next run.

### Pattern I — Upstream changed a file shape in a way that invalidates an assumption

Example: upstream reworks a stage from sourcing individual scripts to looping over a directory, or replaces a shell component with a Quickshell one.

**Resolution:**

1. Re-read the new shape.
2. Re-apply the gating logic in the new style (e.g., a name-pattern filter in the loop instead of explicit Arch-only sources).
3. **Consider dropping the patch.** If upstream's rewrite removed the thing we were patching, the correct resolution is often no patch at all — that is how the last `shell/` patch retired, and the stack currently carries **zero** `shell/` patches. Keeping it that way is a goal, not an accident.
4. Update the patch-stack map's notes on that file.

### When in doubt

If a conflict doesn't fit any pattern, **stop the rebase** (`git rebase --abort`), open the patch-stack map and the conflicting commits, and think. The map is the contract — if reality diverges, fix one or the other rather than producing a frankenpatch.

---

## 4. Verification matrix

Run the automated tier after every rebase; the manual tiers before a release.

### Automated checks — the L1 gate (must pass)

`.github/workflows/test.yml` is the canonical list; it runs each test explicitly. Locally, the whole L1 unit tier is:

```bash
for t in test/*-test.sh; do echo "== $t"; bash "$t" || break; done   # 24 tests
bin/omarchy-dev-validate-fedora-packages                             # real fedora.toml
bash test/cli                                                        # upstream CLI suite
omarchy commands --check                                             # metadata + route collisions
```

| Check | Command | What it verifies |
| --- | --- | --- |
| Byte-identity audit | `bash test/byte-identity-test.sh` | Every modified upstream file is additive-only vs the pin, or its deletions are in the documented ALLOW table. **The rebase's own gate** — see [§2 step 5](#step-5--re-derive-the-byte-identity-allow-table) |
| Distro / pkg dispatch | `test/distro-test.sh`, `test/pkg-helper-test.sh`, `test/pkg-map-test.sh` | `omarchy-distro` tokens; every helper's Fedora arm reaches `bin/fedora/*`; `fedora.toml` schema |
| Gating audits | `test/archism-gating-test.sh`, `test/migration-gating-test.sh`, `test/etc-overrides-audit-test.sh` | No ungated Arch-ism reaches Fedora; every new migration is classified; no unowned `/etc` writes |
| Install/adopt behavior | `test/coexistence-plan-test.sh`, `test/coexistence-test.sh`, `test/adopt-user-test.sh`, `test/finalize-defaults-test.sh` | The plan gate discloses everything before it acts; backup-then-write; only-if-unset defaults |
| Update path | `test/update-flow-test.sh`, `test/upgrade-to-4-test.sh` | The `dnf` dispatch chain and the 3→4 upgrade's kept-package set |
| Spec static guards | `test/*-spec-test.sh` (voxtype, tensaku, omacut, omawrite, gpu-screen-recorder) | RPM specs keep their pinned sources, subpackage split, and file lists |
| Package map validation | `bin/omarchy-dev-validate-fedora-packages` | `fedora.toml` schema correctness, COPR allowlist compliance, installer existence |
| Upstream CLI suite (Arch contract) | `bash test/cli` — CI runs it in an `archlinux:latest` container | Dispatcher routing, metadata, command help, JSON output, executable bits, with the omedora bins present. **This is the dual-distro contract** |
| Metadata validation | `omarchy commands --check` | All commands have summary metadata, no route collisions, no missing binaries |

> `test/omarchy-cli-test.sh` does **not** exist on this branch — the upstream
> suite is `test/cli` (and `test/all` runs `test/cli` + `test/shell`). Older docs
> that name the former are stale.

### L4 session gate (before a release)

L4 is a **local / self-hosted pre-release gate, not CI** — it needs a DRM render node, which standard GitHub-hosted runners cannot provide in hardware or software ([`testing.md` §6](testing.md#6-l4-nested-container-design)).

| Check | Command | What it verifies |
| --- | --- | --- |
| L4-headless session suite | `omedora/test/fedora/headless/run-tests.sh` (podman + `/dev/dri`) | Boots a real Omedora v4 session (PID-1 systemd, labwc + nested Hyprland + the Quickshell shell) and runs the TAP suite: `00-session`, `10-launcher`, `20-portals`, `30-visual` (screenshot diff), `40-menu`, and `90-workstation` on the Workstation base |
| Workstation coexistence | `omedora/test/fedora/run-session.sh --workstation` (`--gnome` for the fallback) | Layering onto a real Fedora Workstation: tuned-ppd, the GNOME portal, GNOME staying selectable |
| L4-VM | `omedora/test/fedora/vm/run-vm-test.sh` | Real Fedora 44 Workstation VM: GDM autologin into `omedora.desktop`, real seat + DRM master, install **from the live COPR** (`%{from_repo}` provenance) |

### Manual checks (must pass before release)

| Check | Setup | What it verifies |
| --- | --- | --- |
| **Arch regression check** | The `arch-contract` CI job (`test/cli` in an Arch container) plus a read of the byte-identity output. | Omedora behaves exactly like upstream Omarchy on Arch — no surface drift. |
| **Fedora fresh install** | Clean Fedora 44, `curl … omedora/boot.sh \| bash`. | Plan gate → repos → `dnf install omedora` → `omarchy-setup-system` → adopt → finalize → first-run, all clean; the session boots. |
| **`omedora update` on Fedora** | After an install, run `omedora update`. | The `dnf upgrade --refresh` path completes; migrations run; idempotent on a second run. |
| **Upgrade from the previous release** | An install at the prior tag, then `omedora update`. | New COPR builds land; no wedge. |

### Smoke-test checklist (manual, in a real Omedora v4 session)

- [ ] Super+Space opens the Quickshell launcher; Super+Alt+Space opens the Omarchy menu.
- [ ] The bar renders workspaces, clock, tray, and the update indicator.
- [ ] `notify-send "test"` shows a Quickshell notification.
- [ ] `omarchy theme set tokyo-night` switches theme and the live shell reloads; `omarchy theme set everforest` reverts cleanly.
- [ ] `omarchy capture screenshot region` produces a file.
- [ ] `omarchy show logo` shows the OMEDORA wordmark on Fedora (OMARCHY on Arch).
- [ ] `omarchy-version` prints `Omedora <semver> (Omarchy <base>)`.
- [ ] The lock screen locks and unlocks (the `omarchy-lock-*` PAM services exist).
- [ ] `omarchy update` runs to completion with no spurious errors; the update indicator clears.
- [ ] Log out to GDM — both "Omedora" and "GNOME" are selectable; log back in and the session restores.

### Hardware sanity (when applicable)

If the rebase touched any hardware-detection or hardware-config code:

- [ ] Test on at least one Intel + AMD machine, and ideally one NVIDIA machine.
- [ ] Confirm no Arch-only script fires on Fedora (`install/hardware/all-fedora.sh`'s subset is the contract) and vice versa.

---

## 5. Release cadence and versioning

Versioning is authoritative in [versioning.md](versioning.md); the v4-specific summary:

- **Two numbers, two files.** `omedora/version` is omedora's own SemVer, tagged `vX.Y.Z` by `bin/omedora-release`; the top-level `version` file records the Omarchy base — **`4.0.0.alpha`** on this line. The base's *major* is what selects the COPR via `bin/omedora-copr`, which is why v4 lives in the isolated `agaspar/omedora-4` project and can never push an ABI-incompatible rebuild at an omedora-3 install.
- **`omarchy-version` prints both** on Fedora: `Omedora <omedora/version> (Omarchy 4.0.0.alpha)`.
- **This line has cut no releases yet.** `v0.1.0`–`v0.1.4` all belong to omedora-3 (none is an ancestor of `omedora-4`), and `omedora/version` here is inherited from that line. The first v4 tag is an alpha; expect `0.2.0`-era numbers to continue from where the RPM specs already sit.
- **Known drift to fix at the first release cut:** `omedora.spec` / `omedora-settings.spec` hardcode `Version: 0.2.0~alpha.0` rather than reading `omedora/version` (the spec comment records the follow-up: have `.copr/srpm.sh` substitute it at SRPM-gen time). Until that lands, a release bump must touch both.
- **Cadence is decoupled from upstream.** There is no upstream v4 release to follow — `quattro` is a moving branch. Release when there's something to ship (a resync, a packaging fix, a COPR bump). A resync does not by itself require a release.
- **Rebase, then release** — never the reverse (see [§2 step 7](#step-7--promote-and-push-force-push-is-expected)).
- **Base pin tags are a v4 mechanism.** omedora-3 records its base in the `version` file only and cuts no `omedora-base-*` tags.

---

## 6. When the rebase is too big

If a resync introduces dozens of conflicts (a major dispatcher refactor, another shell re-architecture), the cost-benefit shifts:

1. **First, check it's real.** A huge-looking rebase after an upstream force-push is frequently a metadata-only rewrite — compare the trees ([§2 step 1](#step-1--fetch-and-classify-the-move)) before spending a day on it.
2. **Consider waiting.** `quattro` churns; resyncing a week later onto a settled tip is often strictly cheaper than fighting a mid-refactor tip. Going forward to a later commit is fine; going backward is not.
3. **Consider splitting the stack.** If patches cluster naturally (helper dispatch vs CLI rebrand vs update flow vs packaging vs branding), rebase them as separate runs to keep conflict surfaces manageable.
4. **Consider dropping patches.** Every upstream rewrite is a chance to delete one of ours — see Pattern I. A smaller stack is the only durable fix.
5. **Consider upstreaming part of the patch.** Genuinely portable improvements (the brand-variable indirection, `omarchy-distro` itself) might be welcomed upstream. Each accepted PR permanently reduces our rebase surface.

The right answer depends on the change. The wrong answer is to grind through a big conflict pile and land in a degraded state.

---

## 7. Tools we lean on

- **`git rebase --onto`** — the workhorse. Always scope the replay against the pin.
- **`git rev-parse <ref>^{tree}`** — the metadata-only-rewrite detector.
- **`git rerere`** — recommended globally (`git config --global rerere.enabled true`). Records conflict resolutions so re-running a rebase reapplies them. Cuts repetitive triage work massively.
- **`git absorb`** (if installed) — attributes after-the-fact fixups to the right commit in the stack. Useful when you discover a missed conflict resolution.
- **`test/byte-identity-test.sh`** — the audit that keeps the stack honest across the rebase. Run it first and last.
- **`omarchy commands --check`** — the metadata validator. Run after every helper-touching change.
- **`bash test/cli`** — the upstream CLI suite. Treat it as authoritative for the Arch contract.

---

## 8. Agent-driven rebasing

The long-term goal is for Claude to drive most of the rebase work. The patterns in [§3](#3-conflict-triage-rubric) are deliberately mechanical so that an agent can:

1. Classify the upstream move and run the scoped rebase.
2. For each conflict, identify the pattern from the patch-stack + gating maps and the file path.
3. Apply the documented resolution, folding it into the originating commit.
4. Rotate the pin, re-derive the ALLOW table, and run the L1 gate.
5. Hand off to a human for the L4/manual tiers, the force-push, and any release cut.

`omedora/AGENTS.md` documents the agent-specific rules of engagement for this loop, including when to stop and ask for human intervention. Conflicts that fall outside the documented patterns are always stop-and-ask cases — as is any resolution that would add a *new* deletion to the byte-identity allowlist without a documented if/else relocation behind it.
