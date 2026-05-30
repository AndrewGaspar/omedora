# Omedora architecture

This is the canonical technical design for omedora — the Fedora port of Omarchy. It is the spine of the patch stack: every code patch in this fork should trace back to one of the sections below, and every section names the concrete files (or file patterns) it touches. The [patch-stack map at the end](#15-patch-stack-map) is the rebase checklist.

> If you are an agent or contributor: also read [`AGENTS.md`](AGENTS.md) — it adds rules of the road that build on top of the architecture documented here.

---

## 1. Dual-distro patch model

Omedora is **not** a clean-room Fedora port. It is a thin layer of additive patches on top of upstream Omarchy that makes the same code tree run on both Arch and Fedora. The same `bin/omarchy-pkg-add` exists in both worlds; it just dispatches to `pacman` on Arch and `dnf` on Fedora.

**Why additive:**

- Every line we add to a shared file is a future rebase conflict. The Arch path must therefore remain byte-for-byte identical to upstream wherever feasible. Distro branches show up as early-return guards or `case "$OMARCHY_DISTRO" in ...` dispatches at the *top* of helpers, not interleaved through their bodies.
- Arch is the regression canary. Cloning omedora on Arch and running the installer must behave exactly like upstream Omarchy. If Arch breaks, our abstraction leaked.
- Files that are *purely* additive (new files in new directories, like `install/packages/fedora.toml`) carry zero rebase risk. Files that *patch* upstream (like `bin/omarchy-pkg-add`) carry real risk — keep that set as small as possible.

**What we explicitly do not do:**

- We do not rename `omarchy-*` files (see [§10 CLI rebrand](#10-cli-rebrand-tactical) for why).
- We do not fork the dispatcher.
- We do not reshape upstream stage directories. `install/preflight/`, `install/packaging/`, `install/config/`, `install/login/`, `install/post-install/` stay where they are; we add gates around them, not new orderings.
- We do not introduce a "build" or "overlay" step. Cloning omedora is functionally identical to cloning upstream — same `~/.local/share/omarchy/` layout.

---

## 2. Distro detection: `bin/omarchy-distro`

One new command. Reads `/etc/os-release` and prints exactly one token to stdout: `arch` or `fedora`. Extensible later (`debian`, `opensuse`, etc.) without breaking callers.

```bash
#!/bin/bash
# omarchy:summary=Print the detected host distribution token (arch|fedora)
# omarchy:hidden=true

if [[ -n $OMARCHY_DISTRO ]]; then
  printf '%s\n' "$OMARCHY_DISTRO"
  exit 0
fi

. /etc/os-release 2>/dev/null
case "$ID" in
  arch)   echo arch ;;
  fedora) echo fedora ;;
  *)
    case " $ID_LIKE " in
      *" fedora "*) echo fedora ;;
      *" arch "*)   echo arch ;;
      *) echo "Unsupported distro: $ID" >&2; exit 1 ;;
    esac
    ;;
esac
```

**Why a command, not just an env var:**

- It can be unit-tested via the existing `test/omarchy-cli-test.sh` metadata-validation harness.
- It honors `$OMARCHY_DISTRO` as an escape hatch (run-as-fedora-on-Arch for development), so callers can subshell-set it and exercise the Fedora paths from an Arch box.
- It's a normal Omarchy subcommand reachable as `omarchy distro` (hidden in help). Consistent with how the rest of the project exposes utility checks (`omarchy-hw-*`, `omarchy-cmd-*`).

Every helper that needs distro awareness opens with one cached call:

```bash
OMARCHY_DISTRO=${OMARCHY_DISTRO:-$(omarchy-distro)}
```

---

## 3. Package-helper dispatch

The single biggest architectural lever. Omarchy already routes nearly every package operation through five helpers:

| Helper | Current Arch behavior | Fedora behavior (after patch) |
| --- | --- | --- |
| `bin/omarchy-pkg-add` | `sudo pacman -S --noconfirm --needed <pkgs>` then verify with `pacman -Q` | Resolve names via the package map, then `sudo dnf install -y <names>`. COPR/Flathub/source paths route through `omarchy-pkg-aur-add` (see below). |
| `bin/omarchy-pkg-missing` | `pacman -Q <pkg>` per package | `rpm -q <fedora-name>` per package, using the package map to translate names |
| `bin/omarchy-pkg-present` | inverse of `pkg-missing` | inverse of `pkg-missing` |
| `bin/omarchy-pkg-drop` | `sudo pacman -Rs --noconfirm <pkgs>` (existing behavior) | `sudo dnf remove -y <fedora-names>` |
| `bin/omarchy-pkg-aur-add` | `yay -S --noconfirm --needed <pkgs>` | **Tiered-fallback entry point.** Looks up each name in the package map and routes to dnf-with-COPR / `flatpak install` / a source installer under `install/packages/installers/`. |

**Patch shape** for each helper:

```bash
#!/bin/bash
# omarchy:summary=... (unchanged)
# ... unchanged metadata ...

OMARCHY_DISTRO=${OMARCHY_DISTRO:-$(omarchy-distro)}

case "$OMARCHY_DISTRO" in
  fedora)
    exec omarchy-pkg-add-fedora "$@"
    ;;
esac

# --- unchanged upstream Arch implementation below ---
if omarchy-pkg-missing "$@"; then
  sudo pacman -S --noconfirm --needed "$@" || exit 1
fi
# ...
```

Each helper grows by ~5 lines at the top and gains a sibling Arch-untouched file like `bin/omarchy-pkg-add-fedora` that holds the Fedora implementation. The sibling is a new file, the parent patch is a 5-line prepend — both low-conflict on rebase.

**No callers change.** This is the whole point. The 200+ scripts that call `omarchy-pkg-add` continue to work without edits.

---

## 4. Package mapping: `install/packages/fedora.toml`

Translations live in a data file, not code. See [`packages.md`](packages.md) for the full schema, tier rules, and contributor checklist. The short version:

- Absence from the map ⇒ "name is identical on Fedora; install with dnf."
- Presence overrides: lists the Fedora package name(s), or routes to a COPR, Flathub app ID, or named source installer, or marks the package as deliberately skipped (with a reason).

The file lives at `install/packages/fedora.toml`. Adjacent: `install/packages/installers/*.sh` for the source-install scripts (e.g., `install-walker.sh`). The Fedora-side helpers know to look there.

---

## 5. Repo enablement: `install/preflight/fedora-repos.sh`

A new install script in the preflight stage, sourced only when `omarchy-distro` reports `fedora`. Enables exactly:

1. **RPM Fusion free + nonfree** — for multimedia codecs and the handful of nonfree libs (e.g., `libva-nvidia-driver`) we may need.
2. **`lionheartp/Hyprland` COPR** — only if `dnf list hyprland` doesn't already find Hyprland in main repos. This check is performed at install time; the goal is to drop COPR usage gracefully when Fedora absorbs Hyprland into main repos.
3. **Flathub remote** — `flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo`. Idempotent.

Conservative by design. New COPRs require explicit review (see [`packages.md`](packages.md) review checklist). Random PPA-style additions are out.

---

## 6. Install-pipeline gating

The orchestrator (`install.sh`) currently sources six stages unconditionally:

```bash
source "$OMARCHY_INSTALL/helpers/all.sh"
source "$OMARCHY_INSTALL/preflight/all.sh"
source "$OMARCHY_INSTALL/packaging/all.sh"
source "$OMARCHY_INSTALL/config/all.sh"
source "$OMARCHY_INSTALL/login/all.sh"
source "$OMARCHY_INSTALL/post-install/all.sh"
```

Patched orchestrator:

```bash
source "$OMARCHY_INSTALL/helpers/all.sh"
source "$OMARCHY_INSTALL/preflight/all.sh"
source "$OMARCHY_INSTALL/packaging/all.sh"
source "$OMARCHY_INSTALL/config/all.sh"
if [[ $(omarchy-distro) == "arch" ]]; then
  source "$OMARCHY_INSTALL/login/all.sh"
  source "$OMARCHY_INSTALL/post-install/all.sh"
fi
```

Two stages drop off on Fedora because they are entirely about owning the boot stack (Plymouth theme install, SDDM, hibernation, Limine+Snapper) and the final post-install pacman re-config — all out of scope for omedora.

**Stage-internal gating.** Inside the surviving stages, individual scripts may still be Arch-only:

- `install/preflight/all.sh` invokes `pacman.sh`, `migrations.sh`, `first-run-mode.sh`, `disable-mkinitcpio.sh`. On Fedora: insert `fedora-repos.sh` after `show-env.sh`, and gate `pacman.sh` and `disable-mkinitcpio.sh` behind `[[ $(omarchy-distro) == "arch" ]]` (or skip them via the `all.sh` dispatcher).
- `install/packaging/all.sh` invokes `base.sh`, `fonts.sh`, `nvim.sh`, `icons.sh`, `webapps.sh`, `tuis.sh`, `npm.sh`, hardware-conditional installers, and the `omarchy-base.packages` glob-and-install. All of these route through `omarchy-pkg-add` and therefore work as-is once helpers are dispatching — the only adjustment is that some packages will be skipped via the map (e.g., `linux-firmware-marvell`).
- `install/config/hardware/all.sh` invokes the long list of hardware fixes. Each script that touches `/etc/mkinitcpio.conf*` or builds Arch-specific drivers gets a one-line top-of-file guard: `[[ $(omarchy-distro) == "arch" ]] || return 0`. A few are partially portable (see [§7](#7-hardware-detection)).
- `install/login/all.sh` and `install/post-install/all.sh` — gated off entirely at the orchestrator level. No internal changes needed.

The naming pattern for Fedora-specific siblings is **suffix `-fedora.sh`** (e.g., `install/config/hardware/nvidia-fedora.sh`). The Arch script keeps its plain name (`nvidia.sh`). Each `all.sh` dispatcher conditionally sources whichever sibling matches the distro.

---

## 7. `install/preflight/guard.sh` — relax for Fedora

Upstream `guard.sh` hard-checks: vanilla Arch, no GNOME/KDE, x86_64, secure boot disabled, Limine bootloader installed, btrfs root. Almost all of these are bootloader/disk-shape concerns that are out of scope on Fedora.

**Patch shape:** prepend a Fedora arm that early-returns after its own short guards (must not run as root, must be x86_64, must be a recognized Fedora release). The Arch block below the prepend stays byte-for-byte.

```bash
DISTRO=$(omarchy-distro)
if [[ $DISTRO == "fedora" ]]; then
  (( EUID == 0 )) && abort "Running as user (not root)"
  [[ $(uname -m) == "x86_64" ]] || abort "x86_64 CPU"
  return 0
fi
# ...existing Arch guards unchanged...
```

Single ~5-line additive block at the top.

---

## 8. Hardware detection

The hardware-detection layer (`bin/omarchy-hw-*`) is mostly distro-agnostic by construction — these scripts read `/sys/class/dmi/`, `/proc/cpuinfo`, and `lspci` output. They get checked into the patch-stack map only because a handful do `pacman -Q` checks for installed packages; those calls route through `omarchy-pkg-present`, which becomes distro-aware via [§3](#3-package-helper-dispatch), so the `hw-*` files themselves need no patches.

The hardware *config* layer (`install/config/hardware/*.sh`) is where the friction lives. Two patterns:

1. **Fully Arch-only:** anything that writes to `/etc/mkinitcpio.conf*`, references Arch-specific kernel module packages, or assumes `linux-zen`/`linux-lts` variants. Gate the whole file with `[[ $(omarchy-distro) == "arch" ]] || return 0`.
2. **Partially portable:** e.g., `nvidia.sh` writes both `/etc/mkinitcpio.conf.d/nvidia.conf` (Arch-only) and Hyprland NVIDIA env vars into `~/.config/hypr/envs.lua` (portable). Split: keep the existing file as the Arch path (guarded), and add a `nvidia-fedora.sh` sibling that writes only the portable Hyprland env vars and skips dracut module config (because the user's RPM Fusion `akmod-nvidia` setup already handles that).

The latter pattern is rare; the majority are case 1. Don't proactively split files that don't need it.

---

## 9. Migrations strategy

`bin/omarchy-migrate` iterates `$OMARCHY_PATH/migrations/*.sh` and sources each pending one via `bash $file`. There are currently 312 migrations and growing; we do not retroactively translate them.

**Patch shape:** the runner becomes distro-aware in *one* line — it exports `OMARCHY_DISTRO` before each `bash $file` so migrations can self-gate.

```bash
if OMARCHY_DISTRO="${OMARCHY_DISTRO:-$(omarchy-distro)}" bash "$file"; then
  touch "$STATE_DIR/$filename"
else
  # ...existing skip-prompt behavior...
fi
```

**Migration behavior on Fedora:**

- Migrations whose entire body routes through `omarchy-pkg-*` helpers Just Work — the helpers dispatch, the migration succeeds.
- Migrations that call raw `pacman`/`yay`/`pacman-key` and aren't guarded will fail. The existing skip-prompt behavior already handles this: the user is asked to skip, and a marker is dropped in `$STATE_DIR/skipped/` so the migration doesn't re-prompt.
- New migrations (post-omedora) **must** use the helper commands. This rule is documented in [`AGENTS.md`](AGENTS.md) and mirrors the upstream Omarchy expectation.
- The base commit does not ship per-migration patches. If a specific historical migration matters on Fedora and bypasses the helpers, file an upstream issue/PR to convert it; we don't fork migration files.

---

## 10. CLI rebrand (tactical)

**Goal:** users type `omedora …`, see `omedora …` in all help text / examples / suggestions, and don't blame Omarchy for omedora-specific behavior — while we touch zero of the 318 `omarchy-*` subcommand files and add zero rebase risk to subcommand metadata.

**Mechanism — touches ~3 files:**

1. **`bin/omedora` is a symlink to `bin/omarchy`.** Both names exist on PATH and reach the same dispatcher.
2. **`bin/omarchy` computes `BRAND_NAME` at the top:**
   ```bash
   if [[ -n $OMARCHY_BRAND ]]; then
     BRAND_NAME="$OMARCHY_BRAND"
   elif [[ "$(basename "$0")" == "omedora" ]]; then
     BRAND_NAME="omedora"
   elif [[ "$(omarchy-distro)" == "fedora" ]]; then
     BRAND_NAME="omedora"
   else
     BRAND_NAME="omarchy"
   fi
   ```
   The dispatcher's output-rendering functions (`show_main_help`, `show_commands_help`, `show_command_help`, suggestion lines, the "Unknown Omarchy command" error path) substitute the literal `omarchy` token with `${BRAND_NAME}` when emitting strings.

3. **Subcommand metadata gets brand-substituted on the way out.** Routes (e.g., `omarchy theme set`) and examples (e.g., `omarchy screenshot | omarchy capture screenshot region`) are stored in the per-command associative arrays unchanged. When rendered, they pass through one substitution. The route-resolution layer continues to accept `omarchy …` *and* `omedora …` as equivalent inputs (both strip to the same internal key).

**Bash/zsh completion:** a new `default/completions/omedora` (and matching zsh file) registers the dispatcher's existing completion handler under the `omedora` name. The existing `omarchy` completion stays intact. Both names tab-complete; both share suggestions. The existing suppression of `omarchy-*` direct-name suggestions also remains.

**`bin/omarchy-version`** learns to print one extra line when `BRAND_NAME == omedora`:

```
Omedora <omedora-version> (rebased on Omarchy <upstream-version>)
```

The Omedora version lives in a new `omedora/version` file; the upstream version stays in the root `version` file. `omarchy-version` reads both and renders accordingly.

**`boot.sh`** embeds the OMARCHY ASCII banner inline. On Fedora-bootstrapped installs, the banner should read OMEDORA. The cleanest patch: detect at the top of `boot.sh` whether the user explicitly ran the omedora bootstrap (e.g., via an `OMARCHY_BRAND=omedora` env var, or by sourcing a `boot-omedora.sh` shim that sets it), then either inline a different `ansi_art` or print from `omedora/branding/logo.txt` if available.

**What we explicitly do NOT do:**

- Do not rename `bin/omarchy-*` files. (Massive rebase carnage, zero user benefit.)
- Do not fork the dispatcher.
- Do not rebrand on Arch. On Arch, `omarchy` invocation continues to say "omarchy" everywhere; the dual-distro principle holds.

**Patch surface for the rebrand:**

| File | Change |
| --- | --- |
| `bin/omedora` | New symlink → `omarchy` |
| `bin/omarchy` | Add `BRAND_NAME` shim at top; substitute in `show_main_help`, `show_commands_help`, `show_command_help`, `dispatch_or_help` error/suggestion paths |
| `bin/omarchy-version` | Add omedora banner line when brand=omedora |
| `default/completions/omedora` | New file (or two — one for bash, one for zsh) |
| `boot.sh` | Add brand-aware banner; new sibling `boot-omedora.sh` that sets `OMARCHY_BRAND=omedora` and forwards to `boot.sh` |
| `omedora/version` | New file (omedora release version, independent of upstream `version`) |

Total: 6 files, one of which is a symlink and three are new. The diff to `bin/omarchy` is the only one that introduces meaningful rebase risk; the patches are concentrated in the help-rendering helpers near the bottom of the file, which are stable upstream code.

---

## 11. Update story — `omedora update`

See [`update-and-upgrade.md`](update-and-upgrade.md) for the end-to-end flow, sequence diagrams, user-facing prompts, and Fedora major-upgrade handling. The architectural sketch:

The current Arch update orchestrator is `bin/omarchy-update` (user prompt + snapshot + git pull) → `bin/omarchy-update-perform` (the actual sequence: keyring → system-pkgs → migrate → aur-pkgs → orphan-pkgs → hook → restart). We patch the *body* (`omarchy-update-perform`), not the wrapper, so the confirmation/snapshot/git-pull UX stays identical on both distros.

**Patched `bin/omarchy-update-perform`:**

```bash
case "$(omarchy-distro)" in
  fedora) exec omarchy-update-perform-fedora ;;
esac
# ...unchanged Arch body below...
```

**`bin/omarchy-update-perform-fedora`** is a new file with the Fedora-equivalent sequence:

1. `omarchy-update-fedora-version-check` — detect Fedora major-version upgrade and run the upgrade migration if needed.
2. `omarchy-update-fedora-coprs` — re-enable COPRs (Fedora's `dnf system-upgrade` disables third-party repos by default).
3. `omarchy-update-fedora-pkgs` — `sudo dnf upgrade -y --refresh <omedora-managed-package-list>`. The list is derived from `omarchy-base.packages` resolved through the package map, plus any other entries with `source = "dnf"`. **No whole-system upgrade.**
4. `omarchy-update-flatpaks` — `flatpak update -y` for app IDs marked `source = "flathub"` in the map.
5. `omarchy-migrate` — distro-aware migration runner ([§9](#9-migrations-strategy)).
6. `omarchy-hook post-update` — unchanged from upstream.
7. `omarchy-update-restart` — unchanged from upstream; already detects deleted Hyprland binary etc. and prompts for reboot/restart.

The orchestrator's snapshot step (`omarchy-snapshot create`) is tolerated to exit 127 on Fedora — that exit code is already special-cased upstream as "snapshot infra not present, continue."

**Fedora major-upgrade handling** is its own concern documented in detail in [`update-and-upgrade.md`](update-and-upgrade.md). Summary: a marker file at `~/.local/state/omedora/last-fedora-version` tracks the OS version last seen; on mismatch, `install/packages/fedora-upgrade.sh` runs, which re-enables COPRs (idempotent), re-resolves the package map against the new Fedora version, and updates the marker.

**Patch surface for updates:**

| File | Change |
| --- | --- |
| `bin/omarchy-update-perform` | Add Fedora dispatch at top (~3 lines) |
| `bin/omarchy-update-perform-fedora` | New file (the Fedora sequence) |
| `bin/omarchy-update-fedora-pkgs` | New file |
| `bin/omarchy-update-fedora-coprs` | New file |
| `bin/omarchy-update-flatpaks` | New file |
| `bin/omarchy-update-fedora-version-check` | New file |
| `install/packages/fedora-upgrade.sh` | New file |

The Arch update flow (`omarchy-update-system-pkgs`, `omarchy-update-aur-pkgs`, `omarchy-update-orphan-pkgs`, `omarchy-update-keyring`) is untouched.

---

## 12. Branding

See [`branding.md`](branding.md) for the full surface-by-surface rules. Quick summary:

- The "Omedora" brand surfaces in: the Wayland session entry shown in display managers, the dispatcher's help/examples (when brand=omedora), `omedora --version`, the screensaver / `omarchy show-logo` ASCII, and install banners on the Fedora path.
- The "Omarchy" brand stays in: `bin/omarchy-*` filenames, code comments, helper headers, the root `AGENTS.md`, the upstream `logo.txt`, the upstream `version` file.
- The ASCII logo (`omedora/branding/logo.txt`) is designed in the same figlet idiom as upstream's `logo.txt`, reusing the O/M/R/A glyphs byte-for-byte and adding new E/D glyphs in the same stroke style.
- The `bin/omarchy-show-logo` and `bin/omarchy-branding-screensaver` consumers gain a one-line path swap: prefer `$OMARCHY_PATH/omedora/branding/logo.txt` on Fedora, fall back to `$OMARCHY_PATH/logo.txt` elsewhere.

---

## 13. Wayland session entry

A single new file: `default/wayland-sessions/omedora.desktop`. Installed by a Fedora-side config script into one of:

- `/usr/share/wayland-sessions/omedora.desktop` (system-wide, requires sudo) — preferred so it shows up for any user on the machine.
- `~/.local/share/wayland-sessions/omedora.desktop` (user-only) — fallback if the user doesn't want to grant sudo for this step.

Contents (roughly):

```ini
[Desktop Entry]
Name=Omedora
Comment=Hyprland session preconfigured by Omedora
Exec=uwsm start -- hyprland.desktop
Type=Application
```

The session uses UWSM exactly as upstream Omarchy does on Arch. The `Name` field is the entire user-facing brand surface on the display-manager picker.

---

## 14. Out of scope, with rationale

| Out of scope | Why |
| --- | --- |
| Bootloader (GRUB2, Limine, systemd-boot) | Users already have a working bootloader from their Fedora install. Replacing it is invasive and adds zero value for a session-only port. |
| Initramfs (dracut, mkinitcpio) | Same reason. Fedora's dracut handles drivers for the user's hardware; omedora doesn't add drivers. |
| Plymouth themes | Fedora ships its own. Replacing it requires bootloader / initramfs reach, which is out of scope. |
| Display manager swap (GDM↔SDDM) | Users keep their existing DM. The "Omedora" session entry is enough to make the brand visible at login. |
| Snapper / snapshot boot | Not portable away from Limine without grub-btrfs setup, which is again bootloader territory. Out. |
| Hibernation setup | System-level partition/swap concern; user's distro should own this. |
| Firewall (ufw, ufw-docker) | Fedora ships `firewalld`. Installing `ufw` conflicts with it. `ufw` is marked `skip` in the package map with that reason. |
| Docker daemon config (`/etc/docker/daemon.json`) | System-level config that users may already have set up differently. Out. Users can opt in themselves. |
| Disk encryption, partitioning, swap setup | Anaconda territory. Not omedora's job. |
| Kernel modules and DKMS drivers (NVIDIA, T2 Mac, Surface, Tuxedo, YT6801, Marvell firmware) | Fedora handles these via RPM Fusion `akmod-*` packages; users with these devices set them up via well-trodden Fedora paths. Omedora does *not* reach into `/etc/dracut.conf.d/`. |
| T2 Mac repo (`arch-mact2`) | Arch-specific Mac support repo. Fedora's equivalent (`t2linux` / `t2-fedora`) is its own project; users who need it install it via its own instructions. |
| Hardware-specific kernel work (Apple SPI, Intel IPU7 camera, etc.) | Same reason as drivers. Out. |
| Whole-system upgrades (`dnf upgrade` of everything) | `omedora update` is *not* `dnf upgrade`. It upgrades only the packages omedora installed. Users still run `dnf upgrade` themselves to maintain their Fedora system. |

If you find yourself wanting to do one of the above, stop and either find a way to leave it to the user / their Fedora install, or open a discussion before touching anything.

---

## 15. Patch-stack map

This is the canonical list of files omedora touches. **Every code patch in the stack should fall into one of these rows.** If you need to touch a file not on this map, stop and either justify adding the file to the map (with reason in the commit body) or restructure the change.

Each row is classified by patch type:

- **New (additive)** — a wholly new file omedora introduces. Zero rebase conflict risk.
- **Prepend (additive)** — existing file with a small block prepended at the top (typically a `case "$(omarchy-distro)" in fedora) exec ... ;; esac` shim or an early-return guard). Low rebase risk; conflicts are usually trivial.
- **Substitute (rendered output)** — existing file with `omarchy` literals in output strings replaced by `${BRAND_NAME}`. Medium rebase risk; conflicts may appear when upstream changes the help text.
- **Path swap** — existing file with one or two lines changed to prefer a Fedora-side path. Low rebase risk.
- **1-line gate** — existing file with one guard line added (`[[ $(omarchy-distro) == "arch" ]] || return 0`). Low rebase risk.
- **Stage dispatch** — existing `all.sh` file with conditional sourcing added. Medium rebase risk if upstream adds/removes stage entries.

### Distro detection

| File | Type | Notes |
| --- | --- | --- |
| `bin/omarchy-distro` | New | Single command. Hidden in help. |

### Package helpers ([§3](#3-package-helper-dispatch))

| File | Type | Notes |
| --- | --- | --- |
| `bin/omarchy-pkg-add` | Prepend | ~5-line dispatch shim at top |
| `bin/omarchy-pkg-add-fedora` | New | Fedora implementation |
| `bin/omarchy-pkg-missing` | Prepend | Same shim |
| `bin/omarchy-pkg-missing-fedora` | New | `rpm -q` per fedora-resolved name |
| `bin/omarchy-pkg-present` | Prepend | Same shim |
| `bin/omarchy-pkg-present-fedora` | New | Inverse of missing |
| `bin/omarchy-pkg-drop` | Prepend | Same shim |
| `bin/omarchy-pkg-drop-fedora` | New | `dnf remove -y` |
| `bin/omarchy-pkg-aur-add` | Prepend | Same shim — but on Fedora becomes the tier-fallback entry point |
| `bin/omarchy-pkg-aur-add-fedora` | New | Reads package map, routes to dnf/COPR/flathub/source |
| `install/packages/fedora.toml` | New | The package-mapping data file |
| `install/packages/installers/*.sh` | New | Per-package source installers (only added when needed) |
| `install/packages/fedora-upgrade.sh` | New | Major-Fedora-version migration handler |

### Install pipeline ([§6](#6-install-pipeline-gating))

| File | Type | Notes |
| --- | --- | --- |
| `install.sh` | Prepend / wrap | Wrap `login/all.sh` and `post-install/all.sh` in Arch gate |
| `install/preflight/all.sh` | Stage dispatch | Insert `fedora-repos.sh` on Fedora; gate `pacman.sh` and `disable-mkinitcpio.sh` |
| `install/preflight/guard.sh` | Prepend | Fedora arm with minimal guards + early return |
| `install/preflight/fedora-repos.sh` | New | RPM Fusion + Hyprland COPR + Flathub remote |
| `install/preflight/pacman.sh` | 1-line gate | Arch-only |
| `install/preflight/disable-mkinitcpio.sh` | 1-line gate | Arch-only |
| `install/config/all.sh` | Stage dispatch only if needed | Most config scripts work as-is via dispatched helpers |
| `install/config/hardware/all.sh` | Stage dispatch | Source `-fedora.sh` siblings if present; skip Arch-only entries on Fedora |
| `install/config/hardware/{nvidia,vulkan,intel/*,apple/*,asus/*,framework/*,lenovo/*,fix-*}.sh` | 1-line gate | Most are Arch-only; gate at top with `return 0` on Fedora |
| `install/config/hardware/nvidia-fedora.sh` | New | Hyprland env vars only (no dracut/mkinitcpio writes) |
| `install/packaging/all.sh` | Unchanged ideally | Works through `omarchy-pkg-add` dispatch |
| `install/packaging/{base,fonts,nvim,icons,webapps,tuis,npm,asus-rog,framework16,dell-xps-touchpad-haptics,surface}.sh` | Unchanged ideally | Helper dispatch handles them |
| `install/login/**` | Unchanged | Gated off entirely at orchestrator level |
| `install/post-install/**` | Unchanged | Gated off entirely at orchestrator level |

### Migrations ([§9](#9-migrations-strategy))

| File | Type | Notes |
| --- | --- | --- |
| `bin/omarchy-migrate` | 1-line edit | Set `OMARCHY_DISTRO` before each `bash $file` |
| `migrations/*` | Unchanged | Historical migrations stay as-is; failures are skip-prompted as today |

### CLI rebrand ([§10](#10-cli-rebrand-tactical))

| File | Type | Notes |
| --- | --- | --- |
| `bin/omedora` | New (symlink) | → `omarchy` |
| `bin/omarchy` | Substitute | `BRAND_NAME` shim at top + substitution in help/error rendering |
| `bin/omarchy-version` | Prepend / append | Add omedora banner line when brand=omedora |
| `default/completions/omedora` (bash) | New | Registers same handler as `omarchy` completion |
| `default/completions/omedora-zsh` | New (if zsh completion exists upstream) | Mirrors the bash file |
| `omedora/version` | New | Omedora's own version string |

### Update flow ([§11](#11-update-story--omedora-update))

| File | Type | Notes |
| --- | --- | --- |
| `bin/omarchy-update-perform` | Prepend | Fedora dispatch (~3 lines) |
| `bin/omarchy-update-perform-fedora` | New | Fedora update sequence |
| `bin/omarchy-update-fedora-pkgs` | New | dnf upgrade limited to omedora-managed packages |
| `bin/omarchy-update-fedora-coprs` | New | dnf copr enable re-assertion |
| `bin/omarchy-update-flatpaks` | New | flatpak update of omedora-tracked apps |
| `bin/omarchy-update-fedora-version-check` | New | Marker-file comparison + upgrade migration trigger |
| `bin/omarchy-update-keyring` | 1-line gate | Arch-only (Fedora has no equivalent; not needed) |
| `bin/omarchy-update-aur-pkgs` | 1-line gate | Arch-only |
| `bin/omarchy-update-orphan-pkgs` | 1-line gate | Arch-only (dnf autoremove is separate concern; out of scope) |
| `bin/omarchy-update-system-pkgs` | 1-line gate | Arch-only |
| `bin/omarchy-update-restart` | Unchanged | Already distro-agnostic in shape |

### Branding ([§12](#12-branding))

| File | Type | Notes |
| --- | --- | --- |
| `omedora/branding/logo.txt` | New | OMEDORA wordmark ASCII |
| `omedora/branding/icon.txt` | Optional new | Reuse upstream `icon.txt` for v1; revisit later |
| `bin/omarchy-show-logo` | Path swap | Prefer omedora/branding/logo.txt on Fedora |
| `bin/omarchy-branding-screensaver` | Path swap | Same |
| `boot.sh` | Prepend / substitute | Brand-aware ASCII banner |
| `boot-omedora.sh` | New | Bootstrap wrapper that sets `OMARCHY_BRAND=omedora` |

### Wayland session ([§13](#13-wayland-session-entry))

| File | Type | Notes |
| --- | --- | --- |
| `default/wayland-sessions/omedora.desktop` | New | Installed to `/usr/share/wayland-sessions/` (or `~/.local/share/wayland-sessions/`) |
| `install/config/wayland-session-fedora.sh` (or similar) | New | The install step that copies the session entry |

### Documentation (this folder)

| File | Type | Notes |
| --- | --- | --- |
| `omedora/README.md` | New | Entry point |
| `omedora/architecture.md` | New | This doc |
| `omedora/packages.md` | New | Package mapping format and rules |
| `omedora/update-and-upgrade.md` | New | Update flow detail |
| `omedora/rebase-workflow.md` | New | Git workflow + conflict triage |
| `omedora/branding.md` | New | Brand surfacing rules |
| `omedora/AGENTS.md` | New | Supplemental agent rules |
| `omedora/testing.md` | New | Test strategy (the pyramid + container design + CI shape) |

### Testing (see [`testing.md`](testing.md))

Per-file status as of the current tip of `dev`. The roadmap in `testing.md` §10 has commit-grouping notes.

| File | Type | Status | Notes |
| --- | --- | --- | --- |
| `test/helpers.sh` | New | ✅ shipped | Shared TAP helpers (`pass`/`fail`/`assert_output_contains`/`assert_equals`/`assert_file_exists`/`assert_exit_code`/`assert_output_lacks`) |
| `test/omarchy-cli-test.sh` | Edit | ✅ shipped | Sources `helpers.sh`; brand-shim assertions added |
| `test/distro-test.sh` | New | ✅ shipped | L1 unit test for `bin/omarchy-distro` |
| `test/pkg-helper-test.sh` | New | ✅ shipped | L1 unit test for package-helper dispatch (mocks `dnf`/`rpm`/`pacman`/`flatpak`/`sudo`) |
| `test/pkg-map-test.sh` | New | ✅ shipped | L1 unit test wrapping `omarchy-dev-validate-fedora-packages` |
| `test/mocks/{dnf,rpm,pacman,flatpak,sudo}` | New | ✅ shipped | Shell mocks — record invocations to `$MOCK_LOG`, exit 0 by default |
| `test/fedora/Dockerfile` | New | ✅ shipped | L2/L3 container base image (`fedora:44` + prereqs) |
| `test/fedora/integration.sh` | New | ✅ shipped | L2 orchestrator |
| `test/fedora/lib/container.sh` | New | ✅ shipped | Container test helpers (`assert_dnf_installed`, `assert_copr_enabled`) |
| `test/fedora/smoke.sh` | New | ✅ shipped | L3 audit-only smoke (scheduled / label-gated) |
| `test/fedora/run-integration.sh`, `run-smoke.sh` | New | ✅ shipped | Host-side runners for L2 / L3 |
| `bin/fedora/pkg.py` | New | ✅ shipped | Python implementation of pkg-add/missing/present/drop/aur-add on Fedora; map resolution + dnf/rpm/flatpak/source dispatch |
| `bin/omarchy-dev-validate-fedora-packages` | New | ✅ shipped | Package-map validator; mirrors `bin/omarchy-dev-bin-metadata` shape |
| `install/packages/fedora.toml` | New | ✅ shipped | Package map (44 entries; bulks out per testing.md step 10) |
| `install/packages/installers/` | New | ✅ shipped | Per-package source installers (currently empty; populated as needed) |
| `install/preflight/fedora-repos.sh` | New | ✅ shipped | RPM Fusion + lionheartp/Hyprland COPR + Flathub remote enable |
| `.github/workflows/test.yml` | New | ✅ shipped | CI workflow — four parallel jobs (shell-unit, arch-regression, fedora-integration, fedora-smoke) |
| `install.sh` | Edit | planned (step 8) | Gate `login/all.sh` + `post-install/all.sh` behind Arch check; let preflight + packaging + config run on Fedora |
| `install/preflight/all.sh` | Edit | planned (step 8) | Source `fedora-repos.sh` on Fedora; skip `pacman.sh` + `disable-mkinitcpio.sh` on Fedora |
| `install/preflight/guard.sh` | Edit | planned (step 8) | Fedora arm: prepend early-return guard that checks distro + arch + non-root; existing Arch guards unchanged below |
| `install/preflight/pacman.sh` | Edit | planned (step 8) | 1-line `[[ $(omarchy-distro) == arch ]] \|\| return 0` guard at top |
| `install/preflight/disable-mkinitcpio.sh` | Edit | planned (step 8) | Same 1-line guard |
| `install/config/hardware/all.sh` | Edit | planned (step 9) | Stage dispatch — source `-fedora.sh` siblings if present; gate Arch-only entries on Fedora |
| `install/config/hardware/{nvidia,vulkan,intel/*,apple/*,asus/*,framework/*,lenovo/*,fix-*}.sh` | Edit | planned (step 9) | 1-line distro guards |
| `install/config/hardware/nvidia-fedora.sh` | New | planned (step 9) | Hyprland NVIDIA env vars only (no dracut writes — Fedora's akmod-nvidia handles drivers) |
| `default/wayland-sessions/omedora.desktop` | New | planned (step 11) | The session entry GDM/SDDM displays as "Omedora" |
| `install/config/wayland-session-fedora.sh` | New | planned (step 11) | Installs `omedora.desktop` to `/usr/share/wayland-sessions/` (or user fallback) |
| `test/fedora/omedora-session/Dockerfile.base` | New | shipped | `FROM fedora:44`; systemd + `systemd-container`/`systemd-pam` + dbus-broker + polkit + install toolchain + the omedora tree; `CMD /sbin/init`. Built/run under **podman** (`--systemd=always`) |
| `test/fedora/build-session.sh` | New | shipped | Boots the base under systemd, runs `install.sh` as omedora via `machinectl shell` (real logind session — Flatpaks install), `podman commit`s to `omedora-test:fedora44-session` |
| `test/fedora/omedora-session/session-launch.sh` | New | shipped | In-container launcher: nests Hyprland under the host compositor (`AQ_BACKENDS=wayland`). Launches `Hyprland` directly (uwsm start needs a seat/VT a container lacks); autostart's `uwsm-app` calls still hit the real `systemd --user` |
| `test/fedora/omedora-session/smoke-assertions.sh` | New | planned | hyprctl-driven assertions for a scripted `--smoke` run — follow-up |
| `test/fedora/run-session.sh` | New | shipped | L4-nested runner (podman `--systemd=always`); binds the host Wayland socket (widens to 0777, restores on exit) + `/dev/dri` + `/dev/rfkill`; flags `--shell` / `--rebuild` / `--keep` |

### Files explicitly NOT touched

For completeness — these are the boundaries of the patch stack:

- `config/**` (Hyprland Lua, Waybar, Walker, terminal configs, mako, swayosd, fastfetch, environment.d, uwsm, etc.) — fully portable as-is.
- `themes/**` (20 themes, TOML colors, templates, btop themes, neovim themes, vscode IDs, waybar CSS) — fully portable as-is.
- `default/themed/*.tpl` — fully portable; templating engine is pure sed.
- `default/hypr/**` — Hyprland Lua modules; portable.
- `default/bash/`, `default/firefox/`, `default/chromium/`, `default/mako/`, `default/waybar/`, `default/walker/` — portable.
- `default/pacman/` — Arch-only by definition; never sourced on Fedora.
- `default/plymouth/` — Plymouth is out of scope on Fedora; this directory is never installed from on Fedora.
- `default/systemd/`, `default/environment.d/`, `default/wayland-sessions/` (existing entries) — portable.
- `bin/omarchy-hw-*` — distro-agnostic by construction; helper-dispatch handles the few `pacman -Q` callers.
- `bin/omarchy-*` (the other ~300 subcommands) — most are distro-agnostic; the ones touched are listed above.
- `migrations/*` — historical migrations stay frozen.
- `test/omarchy-cli-test.sh` — used as-is for CLI validation on both distros (a planned future commit extracts shared helpers into `test/helpers.sh` and adds brand-shim assertions; see the Testing row group above).
- `applications/**` — standard `.desktop` files, portable.
- `icon.png`, `icon.txt`, `logo.svg`, `logo.txt` (root) — left alone; the Fedora-branded versions ship under `omedora/branding/`.
- `version` (root) — upstream version, untouched. Omedora version lives at `omedora/version`.

---

## How to use this map

When you start a rebase or a new patch:

1. Run `git diff upstream/<release> -- <files-not-on-map>`. The answer should be empty.
2. If it isn't, either: (a) the patch needs to be restructured to fit the map, or (b) the map needs a new entry (in which case update this doc *in the same commit* as the code change).
3. The map is the contract. If reality drifts from it, fix one or the other — don't let them diverge silently.

This is the canonical document the rebase workflow ([`rebase-workflow.md`](rebase-workflow.md)) checks against.
