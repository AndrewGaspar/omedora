# Agents: working on omedora

This file is for Claude (and other agents) maintaining the omedora fork. It builds on top of the root [`../AGENTS.md`](../AGENTS.md), which is Omarchy's upstream contributor guide and stays untouched on rebase. Both apply — when there is no conflict, both rules hold; when there is a conflict, this file wins because omedora-specific concerns are not covered upstream.

If you only have time to read one section: it's [§1 Patch discipline](#1-patch-discipline). The rest elaborates.

---

## 1. Patch discipline

Every change you make falls into one of these categories. If you can't categorize it, **stop and think before editing**.

1. **A new file in a new omedora-specific path** (e.g., `install/packages/installers/install-foo.sh`). Zero rebase risk. Go ahead.
2. **A new file in an upstream-owned path** (e.g., `bin/omarchy-pkg-add-fedora` sitting next to `bin/omarchy-pkg-add`). Low risk; conflict only if upstream adds a file with the same name.
3. **A documented patch to an upstream file** that matches a row in [the patch-stack map](architecture.md#15-patch-stack-map). Low-to-medium risk depending on patch type.
4. **A patch to an upstream file that isn't on the map.** **Stop.** Either:
    - Reshape the patch to fit the map (e.g., factor the change into a new sibling file).
    - Justify adding a new row to the map, and update [`architecture.md`](architecture.md) in the same commit.

The map is the contract. If you find yourself wanting to silently extend it, you're about to make the rebase harder for future-you (or future-Claude).

**Where new files go.** Standalone omedora additions — tooling with no upstream caller, like `omedora/packaging/copr/` (the RPM specs + build scripts) — live under **`omedora/`**, not at the repo top level and not scattered through Omarchy's tree. Only place an omedora file *inside* the Omarchy hierarchy (`bin/`, `install/`, `default/`, `test/`) when integration genuinely forces it: it must be on `$PATH` (`bin/omarchy-distro`, `bin/fedora/pkg.py`), sourced by an upstream `all.sh` (the Fedora-gated `install/*/…-fedora.sh` scripts), read by a tool at a fixed path (`install/packages/fedora.toml`), or required there by convention (`.github/workflows/`). Smaller Omarchy footprint ⇒ cleaner rebases. When unsure, default to `omedora/`.

---

## 2. Additive-only edits

When patching a shared file (one that exists upstream and we modify), follow the additive principle:

- **The Arch code path stays byte-for-byte identical to upstream wherever feasible.**
- Distro branches show up as early-return guards or `case "$(omarchy-distro)" in fedora) ... ;; esac` dispatches **at the top of the function or file**, not interleaved through the body.
- Prefer a top-of-file shim that `exec`s to a sibling file, over inlining 30 lines of Fedora logic inside the upstream helper.

Why: every line we inject mid-function is a 3-way merge conflict waiting to happen. Top-of-file prepends and early-returns rebase cleanly because upstream rarely edits the very first lines of a file.

**Good:**

```bash
#!/bin/bash
# omarchy:summary=... (unchanged)
OMARCHY_DISTRO=${OMARCHY_DISTRO:-$(omarchy-distro)}
case "$OMARCHY_DISTRO" in
  fedora) exec omarchy-pkg-add-fedora "$@" ;;
esac

# --- upstream code below, unchanged ---
if omarchy-pkg-missing "$@"; then
  sudo pacman -S --noconfirm --needed "$@" || exit 1
fi
# ...
```

**Bad** (interleaved):

```bash
if omarchy-pkg-missing "$@"; then
  if [[ $(omarchy-distro) == "fedora" ]]; then
    sudo dnf install -y "$@" || exit 1
  else
    sudo pacman -S --noconfirm --needed "$@" || exit 1
  fi
fi
```

The second form *works* but bonds our patch to every line of upstream behavior. Don't.

---

## 3. Package map updates

When upstream adds a package to `omarchy-base.packages` or to a feature install script and the package needs translation on Fedora, follow this sequence:

1. Check Fedora main repos: `dnf search <name>`.
2. Check RPM Fusion: `dnf --enablerepo=rpmfusion-free,rpmfusion-nonfree search <name>`.
3. Check the allowed third-party COPRs (see the allowlist in [`packages.md` §7](packages.md#7-review-checklist)). The allowlist is currently empty (`lionheartp/Hyprland` was retired in task #66 when the hyprwm stack was vendored).
4. Check Flathub: search https://flathub.org/.
5. Only if all four fail: package it as an omedora RPM under `omedora/packaging/copr/` and route the entry to `source = "dnf"` (see [`packages.md` §4](packages.md#4-the-rpmcopr-tier-omedorapackagingcopr)). The source-installer tier is retired. If a spec isn't feasible right now, park the entry as `source = "skip"` with a TODO.

Each map entry change goes in a commit with the rationale in the commit body. Detail the tier choice and any alternatives you considered. Future maintainers will read this history.

**Never add a third-party COPR to the allowlist without explicit human approval.** A new COPR requires a separate PR that updates `packages.md` § 7 with rationale (maintainer, build history, why we trust it). (This does not apply to the omedora repo — our own RPMs in `omedora/packaging/copr/` — which is reviewed as ordinary source.)

---

## 4. Brand discipline

See [`branding.md`](branding.md) for the full surface map. The core rules:

- **Never rename `omarchy-*` files.**
- **Never rename `$OMARCHY_*` env vars or filesystem paths.**
- New user-facing strings in `bin/omarchy` use `${BRAND_NAME}`.
- New user-facing strings in Fedora-side install scripts use literal `omedora` (those scripts only run on Fedora).
- Don't add brand strings to migrations, themes, or configs.
- Don't shadow upstream's root `logo.txt` / `icon.txt` / `version` — put omedora versions under `omedora/branding/` and `omedora/version`.

---

## 5. Update-flow commands

New Fedora-specific update commands follow the `bin/omarchy-update-fedora-*` naming pattern, matching the existing `bin/omarchy-update-*` cluster. Examples on the map:

- `omarchy-update-fedora-pkgs`
- `omarchy-update-fedora-coprs`
- `omarchy-update-fedora-version-check`
- `omarchy-update-flatpaks` (no `-fedora-` because there's no Arch equivalent to "update Flatpaks under our management")

The dispatch happens in `bin/omarchy-update-perform` (not `bin/omarchy-update` — the user-facing wrapper stays distro-agnostic).

---

## 6. Things you must NOT introduce

These are scope violations. If you find yourself wanting to do any of them, **stop and ask a human**.

- **System-level config under `/etc/`** (other than the wayland-sessions install, which is explicitly on the map). No firewall changes, no docker daemon config, no sudoers tweaks, no SELinux policy, no dracut module config.
- **Bootloader configuration** (GRUB, Limine, systemd-boot, EFI variables).
- **Initramfs configuration** (dracut.conf.d, mkinitcpio.conf — neither, on Fedora).
- **Display manager replacement** (don't install SDDM, don't disable GDM, don't change autologin).
- **Kernel modules or DKMS drivers** (NVIDIA, T2, Surface, anything that needs an `akmod-*`).
- **Whole-system upgrades.** `omedora update` does **not** run `dnf upgrade` of everything — only the omedora-managed package set.

If a task seems to require one of these, the right move is almost always to leave it to the user / their Fedora install. If you genuinely think we need it, escalate — don't quietly add it.

---

## 7. Verification before merge

The canonical test strategy lives in [`testing.md`](testing.md) — the four-layer pyramid (L1 shell unit / L2 Fedora container integration + Arch regression / L3 Fedora smoke / L4 VM full-DE). "Verification before merge" means **tests at the appropriate layer per `testing.md`** — ad-hoc shell snippets in the PR body are not enough.

Before any PR is merged into omedora's `dev`:

1. **Automated:** `test/omarchy-cli-test.sh` passes. `omarchy commands --check` passes. As the test infra in `testing.md` lands incrementally, additional L1/L2 tests join this list and CI runs them automatically.
2. **Manual (Fedora):** boot a Fedora 44 VM, install omedora, run the touched code path. For a typical helper patch: run `omedora update` end-to-end and confirm no spurious errors.
3. **Manual (Arch):** if the patch touched a shared file (anything with both Arch and Fedora arms), spin up an Arch box (or use the existing Omarchy infrastructure) and confirm the Arch path is unchanged.
4. **Document both** in the PR body. Include the commands run, the VM environment, and any output worth flagging.

If you can't run the Fedora VM yourself (because of tool limitations), say so explicitly in the PR — don't claim verification you didn't do.

### Commit & worktree hygiene

Land work as **logical, self-contained commits, pushed as you go** — one coherent change per commit (a packaging fix, a gating change, a doc update), with the rationale in the body. Don't let a worktree accumulate a large dirty pile a reviewer has to untangle. When committing in a worktree that also holds unrelated in-progress changes, use a **targeted `git add <path>`** so you commit only your change, never a blanket `git add -A`.

**Parallel / delegated work gets its own worktree + branch, not a shared dirty tree.** Isolate a long-running task with `git worktree add -b <branch> ../omedora-<topic> <base>` so it can't collide with concurrent work. A background agent is told to leave its changes **uncommitted** in its worktree so the parent can review the diff before committing it as a clean logical commit — so an uncommitted/dirty worktree is frequently *expected in-progress work*, not a failure. Check whose work it is (`git status` / `git log`) before assuming a worktree is dirty by mistake.

**Clean up podman before you exit.** The L4 harness spins up build containers (and large session/`-pkgs` images) under podman. Before finishing a task, **remove any containers you created** (`podman rm -f <name>`) — a left-running build container holds a multi-GB image layer and its storage, and they pile up fast (a single abandoned launch-gate run left ~10 GB + a wedged commit). Remove throwaway containers, prune dangling images you produced (`podman image prune -f`), and never leave an orphaned build container `Up` after your turn. Do NOT remove containers/images another concurrent task is using, and keep the `*-dnf-cache` volumes (they speed rebuilds). If a `podman commit`/build fails with `disk quota exceeded` under `/tmp`, set `TMPDIR=/var/tmp` (the storage there isn't quota-capped) — see the `l4-podman-systemd` memory.

---

## 8. Memory

When you learn something that future-you will want to remember about omedora maintenance, write it to this project's memory directory (`/home/ajg/.claude/projects/-home-ajg-code-omedora/memory/`). Specifically:

- **Fedora packaging surprises:** "swayosd moved into Fedora main repos as of F45 — drop the COPR check." "The `lionheartp/Hyprland` COPR was unreachable for 48 hours in March 2026; users hit `omedora update` failures."
- **Rebase patterns that aren't yet in [`rebase-workflow.md`](rebase-workflow.md):** if you encounter a new conflict pattern, save it as a `feedback` memory and update the doc in the next session.
- **User preferences specific to this fork:** if the maintainer says "always cite the upstream Omarchy issue when filing a related omedora bug," save that as a feedback memory.

Don't memorize: code patterns (the docs are canonical), package-map entries (the file is canonical), ephemeral session state.

---

## 9. When to stop and ask

Even with all the above, some situations require a human in the loop. Stop and ask when:

- A rebase conflict doesn't fit any of the patterns in [`rebase-workflow.md` §3](rebase-workflow.md#3-conflict-triage-rubric).
- Upstream Omarchy has made a structural change that invalidates [`architecture.md`'s patch-stack map](architecture.md#15-patch-stack-map). The map needs human-decided updates before the rebase can proceed.
- A new package's tier choice in `install/packages/fedora.toml` would require adding a new COPR to the allowlist.
- A user-reported bug isn't reproducing in a clean Fedora 44 VM and you suspect it's environmental.
- A patch you're considering would touch one of the [§6 forbidden surfaces](#6-things-you-must-not-introduce).

Stopping early is cheap. Carrying a half-resolved patch through a rebase is expensive.

---

## 10. Useful commands

```bash
# Detect distro
omarchy distro

# Validate the package map (planned helper)
omarchy dev validate-fedora-packages

# Run the CLI test suite
test/omarchy-cli-test.sh

# Validate command metadata
omarchy commands --check

# List all commands grouped by prefix
omarchy commands

# See which files in your working tree differ from upstream
git diff upstream/master -- bin/ install/ default/

# Find files we patch that match a particular pattern
git log upstream/master..HEAD --name-only --format= | sort -u

# Re-run a specific install stage on an existing system
bash $OMARCHY_INSTALL/packaging/all.sh

# Force a particular distro mode (development)
OMARCHY_DISTRO=fedora omarchy pkg add foo

# Force a particular brand (development)
OMARCHY_BRAND=omedora omarchy --help
```

---

## 11. The principle behind all of this

Omedora exists because not everyone can run Arch. The patch stack exists because not everyone can constantly re-derive a port from scratch. The map exists because not every contributor can hold the whole codebase in their head.

When in doubt, ask: **does this make the next rebase easier or harder?** If easier, do it. If harder, find another way.
