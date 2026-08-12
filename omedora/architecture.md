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
2. **Flathub remote** — `flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo`. Idempotent.

No third-party COPR is enabled here. omedora-3 has no third-party COPR dependencies: task #66 vendored the entire hyprwm stack as omedora RPMs (`omedora/packaging/copr/`) served from the omedora repo, built from omedora's own COPR.

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
- `install/preflight/first-run-mode.sh` keeps the unprivileged first-run marker on both distros, but its `sudo tee /etc/sudoers.d/first-run` NOPASSWD grant is **Arch-gated**. That grant exists only so Arch's privileged *post-login* finalizers (ufw firewall, resolv.conf symlink) can run in a TTY-less GUI session; on Fedora those finalizers are gated off (below), so first-run needs no sudo — and writing the drop-in would otherwise *crash the install* on a managed box with no `/etc/sudoers.d/` (the whole installer runs under `set -eEo pipefail`).
- **Post-login first-run** (`bin/omarchy-first-run`, autostarted from `default/hypr/autostart.lua`) runs a chain of `install/first-run/*.sh` finalizers. On Fedora it is reduced to its *unprivileged, user-session* steps (swayosd/elephant/battery/gdk-scale/gtk-primary-paste/gnome-theme `gsettings`/welcome/wifi — all `systemctl --user`/`gsettings`, **zero sudo**). The Arch system-policy finalizers carry a top-of-file `[[ … == "arch" ]] || exit 0` guard: `dns-resolver.sh` (clobbers `/etc/resolv.conf` — redundant on Fedora, breaks corporate VPN/split-DNS), `firewall.sh` (pure `ufw`; firewalld is Fedora's default and `ufw` is `source=skip`), `cleanup-reboot-sudoers.sh` (removes an Arch-`post-install`-only grant), plus `gnome-theme.sh`'s `sudo gtk-update-icon-cache` line and the trailing `sudo rm /etc/sudoers.d/first-run` in `omarchy-first-run` itself. A handful of shared `config/*.sh` scripts likewise gate just their Arch-only privileged lines: `walker-elephant.sh` (the `/etc/pacman.d/hooks` restart hook) and `theme.sh` (the Yaru system-icon symlinks). The browser theme-follow policy dirs (`/etc/{chromium,brave}/policies/managed`) are still created on Fedora — they back a real feature — but **user-owned `755`** instead of world-writable `a+rw`.
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

`omedora/packaging/copr/omedora.desktop` is the source of truth for omedora's session entry — it lives next to the spec that ships it. (There is no `default/wayland-sessions/` copy: omedora **packages** the entry rather than `sudo cp`-ing it, a deliberate divergence from omarchy, which keeps `default/wayland-sessions/omarchy.desktop` for its Arch sudo-cp.) On Fedora it is **shipped by a package** — `hyprland-omedora` (`omedora/packaging/copr/hyprland-omedora.spec`, noarch) owns `/usr/share/wayland-sessions/omedora.desktop` — rather than dropped into `/usr` by a `sudo cp`. Installing `hyprland` on Fedora remaps (`install/packages/fedora.toml`) to `hyprland-omedora`, which `Requires: hyprland-no-session` + `uwsm`, so the compositor binaries and the session entry arrive together via dnf. There is no longer a session-related `/usr` write in the installer; the old `install/config/wayland-session-fedora.sh` sudo-cp is retired (now a no-op, unwired from `install/config/all.sh`).

The Hyprland package set is split so the binaries and the visible session entries are separable: `hyprland-no-session` (the compositor binaries + portal config, NO `.desktop`), `hyprland` (the plain visible "Hyprland" session entry, Requires the base), `hyprland-uwsm` (the uwsm session entry), and `hyprland-omedora` (omedora's own uwsm entry). On Fedora omedora pulls only the base + `hyprland-omedora`, so the plain/uwsm visible entries are NOT installed.

The optional XR path follows the same rule. `hypxrland` places its compositor at a private libexec path and shares the stable 0.56.x watchdog, `hyprctl`, assets, portals, and libraries. `hypxrland-stack` pulls the mandatory runtime components (patched WiVRn, voice + model, HUD, VA gate, and paper); the hardware-specific XREAL Monado flavor is only suggested. `hypxrland-omedora` adds `/usr/share/wayland-sessions/omedora-xr.desktop`, displayed as **Omedora XR**, and launches the private binary through uwsm with `~/.config/hypr/hyprland-xr.conf`. It requires both the stack and `hyprland-omedora`, so one install brings up XR while the stable **Omedora** entry remains beside it in the greeter.

The RPM boundary deliberately stops at the user's home directory. The session launcher selects the packaged `/usr/lib64/hypxrva` shim, but it does not overwrite `~/.config/hypr`, WiVRn pairing keys, voice intent configuration, or hybrid-GPU systemd user drop-ins. Existing source-tree configs that hard-code build paths must be changed to the packaged `/usr/bin` paths; the stack README installed under `/usr/share/doc/hypxrland-stack/` records those handoff steps.

Contents:

```ini
[Desktop Entry]
Name=Omedora
Comment=Omedora Hyprland session managed by uwsm
Exec=uwsm start -g -1 -e -N Hyprland -D Hyprland -- start-hyprland
TryExec=uwsm
Type=Application
```

The `Exec` drives Hyprland directly through uwsm (no resolver `.desktop`): `-N`/`-D` supply the Name/DesktopNames that a `.desktop` would otherwise provide. We run `start-hyprland` — the upstream watchdog launcher that supervises Hyprland and passes `--watchdog-fd` — rather than the bare `Hyprland` binary, which would emit a "started without start-hyprland" warning (this matches what upstream's plain `hyprland.desktop`, `Exec=/usr/bin/start-hyprland`, does). The session uses UWSM exactly as upstream Omarchy does on Arch. The `Name` field is the user-facing brand surface on the display-manager picker. (Note: the systemd unit instance uwsm derives from the command basename is `wayland-wm@start\x2dhyprland.service`.)

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
| `bin/omarchy-pkg-aur-add-fedora` | New | Reads package map, routes to dnf (Fedora main / omedora repo) / COPR / flathub |
| `install/packages/fedora.toml` | New | The package-mapping data file |
| `install/packages/installers/README.md` | New | Pointer only — the source-installer tier is **retired**; packages with no Fedora/COPR/Flathub home are RPMs under `omedora/packaging/copr/` (see [Packaging tier](#packaging-tier-rpmcopr)) |
| `install/packages/fedora-upgrade.sh` | New | Major-Fedora-version migration handler |

### Packaging tier (RPM/COPR)

Packages with no Fedora / RPM Fusion / vetted-COPR / Flathub home are built as **RPMs** under `omedora/packaging/copr/` and served from the omedora dnf repo (a local repo today, a published COPR later). This replaces the retired source-installer tier; the `fedora.toml` entries are plain `source = "dnf"`. See [`packages.md` §4–§5](packages.md#4-the-rpmcopr-tier-omedorapackagingcopr) for spec conventions, build scripts, and repo injection.

| File | Type | Status | Notes |
| --- | --- | --- | --- |
| `omedora/packaging/copr/walker.spec` | New | ✅ shipped | Binary-repackage of upstream walker release; `Requires: gtk4-layer-shell` |
| `omedora/packaging/copr/elephant.spec` | New | ✅ shipped | Binary-repackage of elephant core + provider plugins + user service; `Requires: libqalculate` |
| `omedora/packaging/copr/omedora-nerd-fonts.spec` | New | ✅ shipped | Binary-repackage (noarch) of CascadiaCode + JetBrainsMono Nerd Fonts |
| `omedora/packaging/copr/swayosd.spec` | New | ✅ shipped | From-source (meson wrapping `cargo build`); ships server/client + libinput backend glue. Crate vendoring for hermetic builds is a follow-up |
| `omedora/packaging/copr/terminaltexteffects.spec` | New | ✅ shipped | From-source Python via `pyproject-rpm-macros` (noarch); provides `tte` |
| `omedora/packaging/copr/{glaze,hyprland-protocols,hyprutils,hyprwayland-scanner,hyprlang,hyprgraphics,hyprwire,hyprcursor,aquamarine,hyprtoolkit}.spec` | New | ✅ shipped | **The vendored Hyprland library tier (task #66).** From-source CMake/meson; pinned upstream releases; specs adapted from `solopasha/hyprlandRPM`. Listed in build order in `build-repo.sh`'s `SPECS` array (deep intra-stack `-devel` BuildRequires). hyprutils/hyprlang/hyprcursor/hyprgraphics out-version Fedora's stale copies so dnf upgrades cleanly; aquamarine exports `libaquamarine.so.13` for Hyprland 0.56.1. `glaze` pinned to 7.x (Hyprland needs ≥7,<8). |
| `omedora/packaging/copr/hyprland.spec` | New | ✅ shipped | **The compositor (task #66).** Built from the release `source-v0.56.1.tar.gz` (bundles udis86 + hyprland-protocols subprojects). Ships `macros.hyprland` for hyprpm. Built from omedora's own COPR — no third-party COPRs. |
| `omedora/packaging/copr/hypxrland.spec` | New | ✅ build-tested | **Parallel rolling XR compositor.** Pins a public HypXRland commit based on Hyprland 0.56.1 and builds OpenXR + the Vulkan GPU probe. Owns only `/usr/libexec/hypxrland/Hyprland` and `/usr/bin/hypxrland-session`; the stable compositor, watchdog, `hyprctl`, shared assets and library wave remain provided by the ordinary Hyprland packages. |
| `omedora/packaging/copr/{hypxrpaper,hypxrva,hypxrhud,hypxrvoice,hypxrvoice-model-base-en}.spec` | New | ✅ build-tested | **HypXRland leaf runtimes.** Immutable public-tip snapshots with checksum pins. Voice statically links its exact whisper.cpp + llama.cpp revisions and uses a separate checksum-pinned `base.en` data RPM; HUD ships D-Bus activation, user units, and an explicit Fedora D-Bus runtime dependency; the VA shim stays isolated under `/usr/lib64/hypxrva`. The public voice tip intentionally excludes newer dirty/local-only intent work in the sibling checkout. |
| `omedora/packaging/copr/wivrn-hypxr.spec` | New | ✅ build-tested | **Patched WiVRn 26.6.2 server/runtime.** Carries the headset-battery D-Bus and microphone-jitter changes and vendors WiVRn's exact patched Monado source for an offline build. NVENC, VA-API, and Vulkan Video remain enabled; x264 is disabled because its development package is outside Fedora main. Owns the standard WiVRn paths and conflicts with another `wivrn-server`. |
| `omedora/packaging/copr/monado-xreal.spec` + `{monado-xreal.service,openxr_monado-xreal.json}` | New | ✅ build-tested | **Optional XREAL Air runtime.** Private service/library/manifest names and a distinct IPC socket allow co-installation with WiVRn. The service has no file capability so Vulkan ICD selection continues to work on hybrid-GPU machines. GPU and connector selection remain per-machine user drop-ins. |
| `omedora/packaging/copr/hypxrland-stack.spec` | New | ✅ install-tested | Mandatory XR runtime meta-package; `Suggests` rather than `Requires` the XREAL-specific Monado flavor. Ships the user-config handoff README. A default Fedora 44 transaction installs every mandatory component without pulling the optional Monado flavor. |
| `omedora/packaging/copr/hypxrland-omedora.spec` + `omedora-xr.desktop` | New | ✅ build-tested | Adds the visible `Omedora XR` session, hard-coded to `~/.config/hypr/hyprland-xr.conf`. Requires `hypxrland-stack` plus `hyprland-omedora`, so installing XR preserves the stable branded session as a fallback. |
| `omedora/packaging/copr/{hyprland-guiutils,hyprlock,hypridle,hyprpicker,hyprsunset,hyprshot,xdg-desktop-portal-hyprland}.spec` | New | ✅ shipped | **The vendored Hyprland app/portal tier (task #66).** hyprland-guiutils (hyprtoolkit-based, successor to hyprland-qtutils, Obsoletes it) authored fresh; the rest adapted from `solopasha/hyprlandRPM`. hyprlock/hypridle/xdph use Fedora's system `sdbus-c++ 2.2.1` (no bundling). hyprpaper deliberately NOT vendored (omedora uses swaybg). |
| `omedora/packaging/copr/macros.hyprland` | New | ✅ shipped | rpm macro file shipped by `hyprland.spec` exposing the hyprland version for hyprpm plugin builds |
| `omedora/packaging/copr/build-local.sh` | New | ✅ shipped | Builds one spec via `rpmbuild -ba` in a `fedora:44` container → `output/`. Enables the local omedora repo inside the build container so `dnf builddep` resolves just-built sibling `-devel` packages (intra-stack deps); stages local (non-URL) Source files |
| `omedora/packaging/copr/build-repo.sh` | New | ✅ shipped | Builds all specs in its `SPECS=(...)` array (Hyprland stack in build order) and createrepos **incrementally** (folds each spec into `repo/` + `createrepo_c --update` so the next spec sees it) → `repo/` (the COPR stand-in) |
| `omedora/packaging/copr/.gitignore` | New | ✅ shipped | Ignores build products `output/` + `repo/` |
| `omedora/test/fedora/build-session.sh` (repo inject) | Edit | ✅ shipped | Builds the local repo, `podman cp`s it into the build container, drops `/etc/yum.repos.d/omedora-local.repo` so `install.sh`'s dnf resolves the omedora-repo packages |

### Install pipeline ([§6](#6-install-pipeline-gating))

| File | Type | Notes |
| --- | --- | --- |
| `install.sh` | Prepend / wrap | Wrap `login/all.sh` and `post-install/all.sh` in Arch gate |
| `install/preflight/all.sh` | Stage dispatch | Insert `fedora-repos.sh` on Fedora; gate `pacman.sh` and `disable-mkinitcpio.sh` |
| `install/preflight/guard.sh` | Prepend | Fedora arm with minimal guards + early return |
| `install/preflight/fedora-repos.sh` | New | RPM Fusion + Flathub remote (Hyprland COPR removed in task #66 — stack vendored) |
| `install/preflight/pacman.sh` | 1-line gate | Arch-only |
| `install/preflight/disable-mkinitcpio.sh` | 1-line gate | Arch-only |
| `install/preflight/first-run-mode.sh` | Arch-gate block | Keep the unprivileged marker on both; gate the `/etc/sudoers.d/first-run` NOPASSWD grant Arch-only (writing it crashes a managed box with no `/etc/sudoers.d`; Fedora first-run needs no sudo) |
| `bin/omarchy-first-run` | Arch-gate line | Gate the trailing `sudo rm /etc/sudoers.d/first-run` Arch-only (nothing to remove on Fedora; bare `sudo` would hang in a TTY-less GUI session) |
| `install/first-run/{dns-resolver,firewall,cleanup-reboot-sudoers}.sh` | 1-line gate | Arch-only privileged post-login finalizers (resolv.conf clobber / ufw / Arch reboot-grant cleanup); `… == "arch" || exit 0` at top |
| `install/first-run/gnome-theme.sh` | Arch-gate line | Keep `gsettings` on both; gate only `sudo gtk-update-icon-cache` Arch-only |
| `install/config/walker-elephant.sh` | Arch-gate block | Keep walker autostart + elephant menus on both; gate the `/etc/pacman.d/hooks` restart hook Arch-only |
| `install/config/theme.sh` | Arch-gate + Fedora branch | Gate Yaru system-icon symlinks Arch-only; create `/etc/chromium/policies/managed` user-owned `755` on Fedora (vs world-writable `a+rw` on Arch) so browser theme-follow still works |
| `install/config/all.sh` | Stage dispatch only if needed | Most config scripts work as-is via dispatched helpers |
| `install/config/fix-powerprofilesctl-shebang.sh` | 1-line gate | Early-return when `/usr/bin/powerprofilesctl` is absent (Fedora keeps tuned-ppd + a bash shim, so there's no python shebang to patch) |
| `install/config/powerprofilesctl-shim-fedora.sh` | New | Fedora-gated installer: copies the shim to `~/.local/bin/powerprofilesctl`, only when `/usr/bin/powerprofilesctl` is absent (tuned-ppd systems). Wired into `install/config/all.sh`'s Fedora-only user block, ahead of the power-profile features |
| `omedora/bin/powerprofilesctl-shim` | New | The shim source (tracked, testable). Bash `powerprofilesctl` implementing `get`/`list`/`set` against the PowerProfiles D-Bus API (`org.freedesktop.UPower.PowerProfiles` on the system bus) via `busctl`; defers to a real `/usr/bin/powerprofilesctl` if present. `list` output matches the `awk` in `omarchy-powerprofiles-{list,set}` |
| `install/config/powerprofilesctl-rules.sh` | Prepend | Top-of-file Fedora dispatch: on Fedora, source `powerprofilesctl-rules-fedora.sh` and return; Arch body byte-for-byte unchanged. (Still Arch-gated in `all.sh` — the sibling exists for correctness if invoked on a tuned-ppd box) |
| `install/config/powerprofilesctl-rules-fedora.sh` | New | tuned-ppd-aware variant: orders the udev `systemd-run` against `tuned-ppd.service` (no `power-profiles-daemon.service` on Fedora) and skips `systemctl enable power-profiles-daemon` unless that unit exists |
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
| `migrations/*` | Unchanged (one exception) | Historical migrations stay as-is; failures are skip-prompted as today. Exception: `migrations/1757147211.sh` gets a Fedora branch so the chromium/brave policy dirs are created user-owned `755`, not world-writable `a+rw` (matches `config/theme.sh`) |

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
| `bin/omarchy-show-logo` | Path swap | Prefer omedora/branding/logo.txt on Fedora / brand=omedora |
| `bin/omarchy-branding-screensaver` | Path swap | Same — `reset` case picks omedora logo on Fedora |
| `install/helpers/presentation.sh` | Brand-aware LOGO_PATH | Prepend: if brand=omedora or distro=fedora, set LOGO_PATH to omedora/branding/logo.txt; Arch path unchanged below |
| `install/config/branding.sh` | Fedora-gated | Seed screensaver.txt with omedora logo on Fedora; Arch path unchanged in else branch |
| `boot.sh` | Prepend / substitute | Read `$ANSI_ART_OMEDORA` env var when `OMARCHY_BRAND=omedora`; Arch path unchanged |
| `boot-omedora.sh` | New | Bootstrap wrapper that sets `OMARCHY_BRAND=omedora`, `OMARCHY_REPO`, inlines omedora logo, then sources `boot.sh` |

### Wayland session ([§13](#13-wayland-session-entry))

| File | Type | Notes |
| --- | --- | --- |
| `omedora/packaging/copr/omedora.desktop` | New | ✅ shipped. `Exec=uwsm start -g -1 -e -N Hyprland -D Hyprland -- start-hyprland` — drives Hyprland directly via uwsm (no resolver `.desktop`; `start-hyprland` is the watchdog launcher, avoids the bare-`Hyprland` warning); launching via uwsm sources `~/.config/uwsm/env` and puts `omarchy/bin` on PATH. Now **shipped by the `hyprland-omedora` package** (`omedora/packaging/copr/hyprland-omedora.spec`), not a sudo-cp. |
| `omedora/packaging/copr/hyprland-omedora.spec` | New | ✅ shipped. Noarch package owning `/usr/share/wayland-sessions/omedora.desktop`; `Requires: hyprland-no-session` + `uwsm`. The `[hyprland]` fedora.toml remap target. |
| `install/config/wayland-session-fedora.sh` | Retired | No-op now (unwired from `install/config/all.sh`). The session entry is owned by the `hyprland-omedora` package; no installer `/usr` write remains. |

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
| `AGENTS.md` (root) | Edit | ✅ shipped | Append-only note at the end: this is Omedora, also read `omedora/AGENTS.md`. Brand-neutral pointer (no rebrand); lowest-risk append. |

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
| `omedora/test/fedora/Dockerfile` | New | ✅ shipped | L2/L3 container base image (`fedora:44` + prereqs) |
| `omedora/test/fedora/integration.sh` | New | ✅ shipped | L2 orchestrator |
| `omedora/test/fedora/lib/container.sh` | New | ✅ shipped | Container test helpers (`assert_dnf_installed`, `assert_copr_enabled`) |
| `omedora/test/fedora/smoke.sh` | New | ✅ shipped | L3 audit-only smoke (scheduled / label-gated) |
| `omedora/test/fedora/run-integration.sh`, `run-smoke.sh` | New | ✅ shipped | Host-side runners for L2 / L3 |
| `bin/fedora/pkg.py` | New | ✅ shipped | Python implementation of pkg-add/missing/present/drop/aur-add on Fedora; map resolution + dnf/rpm/flatpak/source dispatch |
| `bin/omarchy-dev-validate-fedora-packages` | New | ✅ shipped | Package-map validator; mirrors `bin/omarchy-dev-bin-metadata` shape |
| `install/packages/fedora.toml` | New | ✅ shipped | Package map (44 entries; bulks out per testing.md step 10) |
| `install/packages/installers/` | New | ✅ shipped | Source-installer tier **retired** — only `README.md` (a pointer to `omedora/packaging/copr/`) remains. New non-Fedora packages are RPMs (see [Packaging tier](#packaging-tier-rpmcopr)) |
| `install/preflight/fedora-repos.sh` | New | ✅ shipped | RPM Fusion + Flathub remote enable. No third-party COPR block — task #66 vendored the hyprwm stack under `omedora/packaging/copr/`, served from the omedora repo |
| `.github/workflows/test.yml` | New | ✅ shipped | CI workflow — four parallel jobs (shell-unit, arch-regression, fedora-integration, fedora-smoke) |
| `install.sh` | Edit | planned (step 8) | Gate `login/all.sh` + `post-install/all.sh` behind Arch check; let preflight + packaging + config run on Fedora |
| `install/preflight/all.sh` | Edit | planned (step 8) | Source `fedora-repos.sh` on Fedora; skip `pacman.sh` + `disable-mkinitcpio.sh` on Fedora |
| `install/preflight/guard.sh` | Edit | planned (step 8) | Fedora arm: prepend early-return guard that checks distro + arch + non-root; existing Arch guards unchanged below |
| `install/preflight/pacman.sh` | Edit | planned (step 8) | 1-line `[[ $(omarchy-distro) == arch ]] \|\| return 0` guard at top |
| `install/preflight/disable-mkinitcpio.sh` | Edit | planned (step 8) | Same 1-line guard |
| `install/config/hardware/all.sh` | Edit | planned (step 9) | Stage dispatch — source `-fedora.sh` siblings if present; gate Arch-only entries on Fedora |
| `install/config/hardware/{nvidia,vulkan,intel/*,apple/*,asus/*,framework/*,lenovo/*,fix-*}.sh` | Edit | planned (step 9) | 1-line distro guards |
| `install/config/hardware/nvidia-fedora.sh` | New | planned (step 9) | Hyprland NVIDIA env vars only (no dracut writes — Fedora's akmod-nvidia handles drivers) |
| `omedora/packaging/copr/omedora.desktop` | New | shipped | The session entry GDM/SDDM displays as "Omedora"; now owned by the `hyprland-omedora` package (was a sudo-cp) |
| `install/config/wayland-session-fedora.sh` | Retired | shipped | No-op; the session entry is shipped by `hyprland-omedora` (no installer `/usr` write) |
| `omedora/test/fedora/omedora-session/Dockerfile.base` | New | shipped | `FROM fedora:44`; systemd + `systemd-container`/`systemd-pam` + dbus-broker + polkit + install toolchain + the omedora tree; `CMD /sbin/init`. Built/run under **podman** (`--systemd=always`) |
| `omedora/test/fedora/build-session.sh` | New | shipped | Boots the base under systemd, runs `install.sh` as omedora via `machinectl shell` (real logind session — Flatpaks install), `podman commit`s to `omedora-test:fedora44-session` |
| `omedora/test/fedora/omedora-session/session-launch.sh` | New | shipped | In-container launcher: nests Hyprland under the host compositor (`AQ_BACKENDS=wayland`). Launches `Hyprland` directly (uwsm start needs a seat/VT a container lacks); autostart's `uwsm-app` calls still hit the real `systemd --user` |
| `omedora/test/fedora/omedora-session/smoke-assertions.sh` | New | planned | hyprctl-driven assertions for a scripted `--smoke` run — follow-up |
| `omedora/test/fedora/run-session.sh` | New | shipped | L4-nested runner (podman `--systemd=always`); binds the host Wayland socket (widens to 0777, restores on exit) + `/dev/dri` + `/dev/rfkill` + `/dev/fuse` (with `--cap-add SYS_ADMIN` so xdg-document-portal's FUSE mount works in the rootless user-ns); flags `--shell` / `--rebuild` / `--keep` |
| `omedora/test/fedora/headless/run-tests.sh` | New | shipped | L4-headless host orchestrator: boots one self-contained headless session (labwc + nested Hyprland, no host socket), copies the suite in, runs each `tests/*.sh` in the logind session via `machinectl shell`, aggregates TAP. Adds `/dev/fuse` + `--cap-add SYS_ADMIN` when fuse is present (document-portal mount) |
| `omedora/test/fedora/headless/lib.sh` | New | shipped | In-container TAP helper library for the headless suite (`headless_session_env`, session-aware asserts, artifact capture; `wait_for_unit_active` / `assert_unit_active` / `assert_dbus_name` for dbus-activated units like the portals) |
| `omedora/test/fedora/headless/tests/20-portals.sh` | New | shipped | L4 acceptance for xdg-desktop-portal (task #55): asserts the dbus-activated main portal + hyprland & gtk backends are active and own their D-Bus names, and (when `/dev/fuse` present) that xdg-document-portal FUSE-mounts the doc store |

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
