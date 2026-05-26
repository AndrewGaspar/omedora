# Update and upgrade flow

This doc covers two distinct concerns:

1. **`omedora update`** — the everyday update flow that mirrors `omarchy update`'s UX but targets only the omedora-managed package set on Fedora.
2. **Fedora major-version upgrades** (44 → 45 → 46 …) — how omedora detects and reacts to the user upgrading their underlying Fedora install via `dnf system-upgrade`.

For the architectural sketch and patch-stack entries, see [`architecture.md` §11](architecture.md#11-update-story--omedora-update).

---

## 1. Design principles

- **Same UX as Arch.** Users running `omedora update` should see the same confirmation prompt, the same banners, the same progress, and (where possible) the same restart prompts as Arch users running `omarchy update`. The dispatch is invisible.
- **Don't own the user's Fedora system.** `omedora update` does *not* run `dnf upgrade` of everything. It updates only the packages omedora installed. Users still update their Fedora system via their own preferred path (`dnf upgrade`, GNOME Software, etc.).
- **Idempotent.** Re-running `omedora update` immediately after a successful run should be a no-op (or very close to it).
- **Loud failures, soft skips.** Failures from package operations exit non-zero and surface the error. The only "soft skip" path is for map entries explicitly marked `source = "skip"`.
- **Survive Fedora major upgrades.** A user can `dnf system-upgrade` to a new Fedora release, then run `omedora update`, and omedora detects the change and self-repairs (re-enables COPRs, re-resolves the package map, etc.) without manual intervention.

---

## 2. The `omedora update` flow on Fedora

End-to-end, when a user runs `omedora update` (or `omarchy update`, same dispatcher):

```
omedora update
└─ bin/omarchy-update                       # user-facing wrapper (unchanged from Arch)
    ├─ PTY-logged via `script` to /tmp/omarchy-update.log
    ├─ omarchy-update-confirm               # confirmation prompt (unchanged)
    ├─ omarchy-snapshot create              # exits 127 on Fedora → tolerated
    ├─ omarchy-update-git                   # git pull in $OMARCHY_PATH (unchanged)
    └─ omarchy-update-perform               # body, distro-dispatched
        └─ case $(omarchy-distro) in fedora) exec omarchy-update-perform-fedora ;; esac
           │
           └─ omarchy-update-perform-fedora     # NEW
              ├─ omarchy-update-fedora-version-check  # NEW
              │   └─ if /etc/os-release VERSION_ID != last-fedora-version:
              │       prompt, then bash install/packages/fedora-upgrade.sh
              │       then write new marker
              ├─ omarchy-update-fedora-coprs          # NEW
              │   └─ dnf copr enable -y <each copr referenced in the package map>
              ├─ omarchy-update-fedora-pkgs           # NEW
              │   └─ sudo dnf upgrade -y --refresh \
              │        $(resolve omarchy-base.packages + all entries with source=dnf via map)
              ├─ omarchy-update-flatpaks              # NEW
              │   └─ flatpak update -y <each app_id with source=flathub in the map>
              ├─ omarchy-migrate                       # (unchanged; distro-aware via §9 of architecture)
              ├─ omarchy-hook post-update              # (unchanged)
              └─ omarchy-update-restart                # (unchanged)
```

### What each new step does in detail

#### `omarchy-update-fedora-version-check`

```
last_seen=$(cat ~/.local/state/omedora/last-fedora-version 2>/dev/null || echo "")
. /etc/os-release
current=$VERSION_ID

if [[ -n $last_seen && $last_seen != $current ]]; then
  echo "Fedora upgraded: $last_seen → $current"
  gum confirm "Run omedora's Fedora-upgrade migration now?" || exit 0
  bash $OMARCHY_INSTALL/packages/fedora-upgrade.sh
fi

mkdir -p ~/.local/state/omedora
echo "$current" > ~/.local/state/omedora/last-fedora-version
```

On first run after install, `last-fedora-version` doesn't exist — the script records the current version and moves on without prompting (the install itself is the "initial setup"). The check fires only after a `dnf system-upgrade` happens between omedora updates.

#### `omarchy-update-fedora-coprs`

```
mapfile -t coprs < <(omarchy-pkg-map-coprs)   # parses fedora.toml, emits unique copr identifiers

for copr in "${coprs[@]}"; do
  if ! dnf copr list 2>/dev/null | grep -qF "$copr"; then
    sudo dnf copr enable -y "$copr"
  fi
done
```

Why this step exists: Fedora's `dnf system-upgrade` disables third-party repos (RPM Fusion, COPRs) during the upgrade. They must be re-enabled afterward or `dnf upgrade` won't see updated builds for packages from those sources. Running this on every `omedora update` is idempotent and ensures the set is correct.

#### `omarchy-update-fedora-pkgs`

```
# Resolve the omedora-managed package list:
#   - All packages in omarchy-base.packages, translated via fedora.toml.
#   - All other map entries with source = "dnf" or source = "copr" (the COPR ones already enabled above).
#   - Skip entries with source = "flathub" (handled by omarchy-update-flatpaks).
#   - Skip entries with source = "source" (handled by their own installers; updated separately if needed).
#   - Skip entries with source = "skip".
mapfile -t pkgs < <(omarchy-pkg-map-resolve --source=dnf,copr)

if (( ${#pkgs[@]} > 0 )); then
  echo "Updating Fedora packages managed by omedora..."
  sudo dnf upgrade -y --refresh "${pkgs[@]}"
fi
```

The crucial difference from `omarchy-update-system-pkgs` (the Arch counterpart, which is `sudo pacman -Syyu --noconfirm`): we pass an explicit package list to `dnf upgrade`. The user's other Fedora packages are not touched. If the user has 200 packages installed beyond omedora, none of them are updated by this step.

#### `omarchy-update-flatpaks`

```
mapfile -t apps < <(omarchy-pkg-map-resolve --source=flathub)

if (( ${#apps[@]} > 0 )); then
  echo "Updating omedora Flatpaks..."
  flatpak update -y "${apps[@]}"
fi
```

Again, scoped: only Flatpaks omedora installed. The user's other Flatpaks are untouched.

#### Source-installed packages

Source installers (under `install/packages/installers/install-<name>.sh`) write their installed version to `~/.local/state/omedora/installed-versions/<name>`. When omedora wants to update them, it re-runs the installer — the installer checks its own version stamp and either no-ops or refreshes. This means we don't need a separate `omarchy-update-source-pkgs` step at the orchestrator level; it's handled implicitly when the package map's source-installed packages get re-resolved.

In practice, source installers are infrequent (Walker and a small handful at most). The cleanest flow is to bump `VERSION_TAG` inside the installer script when we want users to get a new build, and let `omedora update` → `omarchy-migrate` → migration-that-re-runs-installer handle the delivery. That keeps the update-flow surface narrow.

---

## 3. Fedora major-version upgrade handling

When a user runs `dnf system-upgrade` to go from Fedora 44 to Fedora 45, three things can break omedora:

1. **Third-party `.repo` files get disabled.** Fedora's `dnf system-upgrade` plugin auto-disables RPM Fusion and any COPRs to prevent cross-version dependency conflicts during the upgrade. They need re-enabling on the new release.
2. **COPRs may lack a build for the new Fedora version.** If `lionheartp/Hyprland` doesn't have an F45 build yet on the morning the user upgrades, `dnf` will refuse to install/update Hyprland from that source. omedora needs to handle this gracefully.
3. **Packages may have moved into or out of main repos.** Hyprland might be in F45 main repos when it wasn't in F44; conversely a package we relied on may have been removed. The package map should reflect the new reality.

### `install/packages/fedora-upgrade.sh`

This script runs once after a detected major upgrade. Its job:

```
echo "Reconfiguring omedora for $(. /etc/os-release; echo $VERSION_ID)"

# 1. Re-run the preflight repo enablement (idempotent).
bash $OMARCHY_INSTALL/preflight/fedora-repos.sh

# 2. Probe each COPR for current-Fedora build availability.
mapfile -t coprs < <(omarchy-pkg-map-coprs)
for copr in "${coprs[@]}"; do
  if ! dnf --enablerepo="copr:copr.fedorainfracloud.org:${copr/\//:}" list available &>/dev/null; then
    echo "WARNING: COPR $copr has no builds for this Fedora version yet."
    echo "         Packages using this COPR may fail to install/update until the COPR catches up."
  fi
done

# 3. Re-resolve the package map and look for entries that should now use main repos.
omarchy-pkg-map-check-promotions

# 4. (Optional, gated by user confirm) re-run the install pipeline to pick up any new packages
#    upstream Omarchy added since the last omedora update.
gum confirm "Re-run omedora install to apply latest configuration?" && {
  bash $OMARCHY_INSTALL/packaging/all.sh
  bash $OMARCHY_INSTALL/config/all.sh
}
```

The "check-promotions" step is just a diagnostic: it scans the map for entries with `source = "copr"` whose package now exists in main repos, and tells the maintainer (via the log) that the map can probably be updated. It doesn't automatically rewrite the map — that's a human/agent decision.

After the script finishes, control returns to `omarchy-update-fedora-version-check`, which writes the new version marker.

### What the user sees during a major upgrade

1. User runs `dnf system-upgrade reboot` and goes through Fedora's normal upgrade flow.
2. After the reboot completes, the user logs back in. Their Omedora session may or may not start cleanly — if a Hyprland-stack package broke (e.g., portal mismatch), the user may need to fall back to GNOME / their previous session to run the next step.
3. From a working terminal, the user runs `omedora update`.
4. `omarchy-update-fedora-version-check` detects the mismatch and prompts: "Fedora upgraded: 44 → 45. Run omedora's Fedora-upgrade migration now?"
5. User confirms; the migration runs, re-enables COPRs, warns about any COPR that lacks a build for F45.
6. The normal `omedora update` flow continues — dnf upgrade picks up the latest builds, Flatpaks update, migrations run.
7. The user logs into the Omedora session again, which should now work on F45.

---

## 4. Comparison: `omarchy update` on Arch vs `omedora update` on Fedora

| Step | Arch | Fedora | Notes |
| --- | --- | --- | --- |
| Confirm prompt | `omarchy-update-confirm` | same | Unchanged; distro-agnostic UX. |
| Snapshot | `omarchy-snapshot create` (snapper) | exit 127 (tolerated) | omedora doesn't own snapshots. |
| Git pull omedora repo | `omarchy-update-git` | same | Unchanged. |
| Major-version check | — | `omarchy-update-fedora-version-check` | New on Fedora; no equivalent on Arch (rolling release). |
| Re-enable third-party repos | — | `omarchy-update-fedora-coprs` | New on Fedora; pacman doesn't disable repos on its own. |
| Update keyring | `omarchy-update-keyring` | — | Arch-specific (omarchy + archlinux keyring). Fedora's RPM keys are managed by dnf itself. |
| Reset available-update marker | `omarchy-update-available-reset` | same | Unchanged. |
| Update system packages | `omarchy-update-system-pkgs` (`pacman -Syyu`) | `omarchy-update-fedora-pkgs` (`dnf upgrade <omedora list>`) | **Key difference:** Arch updates *the whole system*; Fedora updates *only omedora-managed packages*. |
| Run migrations | `omarchy-migrate` | same | Distro-aware via env var; migrations self-gate. |
| Update AUR packages | `omarchy-update-aur-pkgs` | — | Arch-specific; Fedora has no AUR. |
| Update Flatpaks | — | `omarchy-update-flatpaks` | Fedora-only step. |
| Remove orphans | `omarchy-update-orphan-pkgs` | — | Arch-specific. dnf autoremove is a separate user concern; out of scope. |
| Post-update hook | `omarchy-hook post-update` | same | Unchanged. |
| Analyze logs | `omarchy-update-analyze-logs` | same | Unchanged. |
| Prompt restart | `omarchy-update-restart` | same | Already distro-agnostic in shape; detects deleted Hyprland binary, kernel updates (via `/usr/lib/modules/*/vmlinuz` and `pacman -Qo` — note that the kernel-update detection currently uses `pacman -Qo`, which won't work on Fedora; this needs a Fedora arm). |

**Open issue:** `omarchy-update-restart` uses `pacman -Qo "$kernel"` to attribute a kernel file to a package, to detect kernel updates. On Fedora this needs to be `rpm -qf "$kernel"`. Add a distro dispatch inside the kernel-update-detection block or split into a Fedora sibling. This is a known patch-stack entry; see [`architecture.md` patch-stack map](architecture.md#15-patch-stack-map).

---

## 5. Failure modes and recovery

### `dnf upgrade` fails partway

Same behavior as Arch's `pacman -Syyu` failing partway: surface the error, exit non-zero. `omarchy-update` is wrapped in a `trap ERR` that points the user to the discord/community link. User re-runs after fixing the underlying issue.

### A COPR is unreachable

`omarchy-update-fedora-coprs` will fail loudly if `dnf copr enable` errors out. The user can:

1. Re-run `omedora update` later when the COPR is back.
2. If a COPR is permanently dead, edit the package map to move affected entries to a different tier (source installer, Flathub, or skip).

`omarchy-update-fedora-pkgs` is the next step; it will fail if the COPR's packages aren't available. The error message includes which packages failed, which makes diagnosis straightforward.

### A Flatpak refuses to update

`flatpak update -y` may report failures for individual apps without aborting the run. The exit code reflects the worst case. Users can inspect with `flatpak update -y --verbose` separately if needed.

### A migration fails

Existing upstream behavior: gum prompts the user to skip or abort. Skipping writes a marker into `~/.local/state/omarchy/migrations/skipped/`, so the migration won't re-prompt. This is the same on Fedora.

### A source installer fails

The installer's exit code propagates. Source installers should be coded defensively (network resilience, idempotency); when they fail, the user gets a clear error and can either re-run `omedora update` or invoke the installer manually.

### The user's Omedora session won't start after `dnf system-upgrade`

Documented user-facing recovery path:

1. Log in to a fallback session (GNOME / their previous DE).
2. Open a terminal.
3. Run `omedora update`. The Fedora-upgrade migration will run.
4. Log out, log back in to Omedora.

If that doesn't help, file an issue with the omedora repo including the output of `omedora debug` (which captures Fedora version, GPU, Hyprland version, and recent journal lines).

---

## 6. What omedora update does NOT do

To avoid surprising users coming from Arch:

- **Does not run `dnf upgrade` of the whole system.** The user's other packages are not touched.
- **Does not run `flatpak update -y`** for *all* their Flatpaks. Only the ones omedora installed.
- **Does not run `dnf autoremove`.** Removing orphans on Fedora is a user-policy choice; we don't make it.
- **Does not change `dnf` configuration or repo priorities.** RPM Fusion and the Hyprland COPR are added via standard `dnf install rpmfusion-*-release` / `dnf copr enable`, nothing more.
- **Does not reboot.** It may prompt for one via `omarchy-update-restart` (e.g., when Hyprland was updated and the running binary is now "(deleted)"), but the user decides.
- **Does not silently fall back tiers.** If a `source = "dnf"` entry's package can't be installed because the repo is down, it fails — not silently switch to Flathub.

These boundaries are what make `omedora update` safe to run frequently on top of an enterprise-managed Fedora install.
