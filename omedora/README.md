# Omedora

**Omedora is Omarchy for stable Fedora Workstation.**

It's a fork of [basecamp/omarchy](https://github.com/basecamp/omarchy) — the opinionated Hyprland desktop project from 37signals — retargeted at enterprise-supported Fedora Workstation (44+). The aim is to preserve as much of the Omarchy experience as possible (keybindings, theming, the `omarchy` command suite, the look-and-feel) while running on Fedora's official package repositories, RPM Fusion, and a small set of vetted COPRs / Flathub apps.

## What omedora is

A **drop-in Hyprland session** that you install on top of an existing Fedora Workstation. After install, "Omedora" appears as a session option on your existing login screen (GDM, SDDM, whatever you have). Pick it, log in, and you get the Omarchy-style Hyprland desktop — same keybindings, same themes, same `omedora` / `omarchy` command surface.

The full Omarchy `~/.config/` payload, the 20 themes, the `omarchy-*` command suite (re-exposed as `omedora …`), and all the UX shell apps (waybar, mako, walker, swayosd, hypridle, hyprlock, etc.) come along for the ride.

## What omedora is not

**Not a distro.** Omedora does not own:

- The bootloader (GRUB2 stays as-is — no Limine, no systemd-boot)
- The initramfs (dracut stays as-is — no mkinitcpio porting)
- Plymouth (Fedora has its own)
- The display manager (GDM / SDDM stays as-is — omedora ships a Wayland session entry, not a DM swap)
- BTRFS snapshots, hibernation, firewall, disk encryption, kernel modules, DKMS drivers

If you want a from-scratch Hyprland distro, install upstream Omarchy on Arch. Omedora is the answer when you need to be on Fedora for reasons outside your control (employer-managed image, hardware enablement, RHEL alignment, a preference for Fedora's release model).

## How it stays close to upstream

Omedora is structured as a **patch stack continuously rebased onto Omarchy's latest stable release**. The patches are deliberately small and additive: most Omarchy files are byte-for-byte unchanged, and the Arch code paths inside the dual-distro helpers stay intact. The same tree runs on both distros — Arch users of this fork get the upstream Omarchy experience untouched, Fedora users get the omedora-flavored variant.

Long-term, the goal is that agents (Claude) handle most of the rebase work each release. The `omedora/` documentation folder you're reading is the architectural anchor for that work.

---

## Installation guide (Fedora 44 Workstation)

> **Supported: Fedora 44 only.** The omedora COPR currently targets
> `fedora-44-x86_64`. Other releases (43, rawhide) aren't built yet — open an
> issue if you want one and there's demand.

Omedora installs **on top of an existing Fedora 44 Workstation**. Its vendored
packages — the Hyprland stack, `walker`/`elephant`/`swayosd`, `uwsm`, the
nerd-fonts and TUIs — are served from the **`agaspar/omedora-3` COPR**, which the
installer enables for you. There is nothing to build by hand.

**Before you start:**

- Fedora 44 Workstation (GNOME), **x86_64** (the installer hard-checks this).
- A regular user in the `wheel` group (standard on Workstation); you are **not** root.
- Internet access (Fedora mirrors, RPM Fusion, the omedora COPR, Flathub).
- The installer calls `sudo` for system writes and must not block on a password
  mid-install. If your wheel `sudo` needs a password, run `sudo -v` first (or add
  a temporary NOPASSWD rule).

### 1. Quick install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/AndrewGaspar/omedora/3.8.2-omedora/omedora/boot.sh | bash
```

`omedora/boot.sh` installs the bootstrap prerequisites (`git`, `gum`,
`dnf-plugins-core`), clones omedora to `~/.local/share/omarchy`, and runs
`install.sh`. The channel is selected with `OMEDORA_REF` (default `stable` = the
repository's default branch, which tracks the current stable release line):

```bash
OMEDORA_REF=dev curl -fsSL https://raw.githubusercontent.com/AndrewGaspar/omedora/dev/omedora/boot.sh | bash   # track the dev branch
```

### 2. Manual install

If you'd rather drive it yourself:

```bash
sudo dnf install -y git gum dnf-plugins-core
git clone https://github.com/AndrewGaspar/omedora.git ~/.local/share/omarchy
bash ~/.local/share/omarchy/install.sh
```

> **Why `~/.local/share/omarchy`?** That's the path the installer hardcodes
> (`OMARCHY_PATH`). Don't clone anywhere else.

For a scripted/repeatable run (skips the `gum` error menu on failure and exits
immediately), prefix with `OMARCHY_NONINTERACTIVE=1`:

```bash
OMARCHY_NONINTERACTIVE=1 bash ~/.local/share/omarchy/install.sh
```

### 3. What the installer does

On Fedora, `install.sh` runs the preflight, packaging, and config stages; the
Arch-only stages (`login/`, `post-install/` — Plymouth, SDDM, Limine, final
pacman config) are gated off automatically because `omarchy-distro` reports
`fedora`.

1. **Preflight** — the Fedora guard (non-root, x86_64, Fedora). Then enables
   **RPM Fusion** (free + nonfree), the **`agaspar/omedora-3` COPR** (omedora's
   vendored Hyprland stack + tools), and **Flathub**. If you're installing onto a
   machine you already use, the up-front coexistence gate runs here — see
   [Installing onto a machine you already use](#installing-onto-a-machine-you-already-use).
2. **Packaging** — everything installs via `dnf` or `flatpak`. The Hyprland
   stack (`hyprland-no-session`, `hyprland-omedora`, `hyprlock`, `hypridle`,
   `hyprsunset`, `xdg-desktop-portal-hyprland`, …), `walker`, `elephant`,
   `swayosd`, `uwsm`, `omedora-nerd-fonts`, and the TUIs come from the COPR. GUI
   apps (Signal, Obsidian, Spotify, Typora, localsend) install as Flatpaks from
   Flathub — these need a live user session bus, so run the installer from a
   GNOME terminal, not a bare TTY.
3. **Config** — omedora's `~/.config/*` payload (Hyprland, waybar, walker, mako,
   …) is seeded with **backup-then-write** semantics (your existing files are
   backed up, never clobbered — see the coexistence section). Themes install.
   The Wayland session entry `/usr/share/wayland-sessions/omedora.desktop` is
   owned by the `hyprland-omedora` package.

The install takes **20–40 minutes** on a fresh VM, dominated by Flatpak runtime
downloads. The log is written to `/var/log/omarchy-install.log`.

---

### 4. Reboot and select the Omedora session

After the install completes, reboot:

```bash
sudo systemctl reboot
```

At the GDM login screen, click the session icon (the gear / cog next to the Sign In button) and select **"Omedora"** from the list. Log in with your regular user password.

> **Pick "Omedora", not "Hyprland".** A bare `hyprland.desktop` session (`Exec=Hyprland`) launches Hyprland **without uwsm** — selecting it leaves `~/.local/share/omarchy/bin` off your PATH, so `omarchy-*` commands and Walker silently fail to launch anything. (On Fedora, omedora pulls only the `hyprland-no-session` binaries + the `hyprland-omedora` session entry, so the plain entry isn't even installed.) The "Omedora" entry (shipped by the `hyprland-omedora` package) launches via uwsm and is the correct one.
>
> If the "Omedora" entry is missing, reinstall the session package — it owns the entry:
>
> ```bash
> sudo dnf reinstall hyprland-omedora
> ```
>
> Then log out and pick **Omedora** at the login screen.

Once logged in, Hyprland starts via `uwsm`. The full autostart chain fires: `waybar`, `mako`, `swaybg` (wallpaper), `hypridle`, and `fcitx5` all launch as `systemd --user` units via `uwsm-app`.

---

### 5. Verification checklist

After the session is running, confirm the key omedora surfaces work:

- [ ] **Menu opens:** Press `Super+Space`. Walker should appear as a fullscreen launcher.
- [ ] **`tte` is on PATH:** Open a terminal (`Super+Enter`) and run `tte --help`. The terminal-text-effects CLI should respond.
- [ ] **No swayosd crash toast:** Adjust volume (omedora maps `XF86AudioRaiseVolume` / `XF86AudioLowerVolume`). A brief overlay should appear, not a mako error notification.
- [ ] **Fonts render correctly:** Open `kitty` or `foot`. The terminal should render JetBrainsMono Nerd Font with icon glyphs (no tofu squares). Waybar icons should also render cleanly.
- [ ] **Theme switching works:** Run `omedora theme set tokyo-night` (or `omarchy theme set tokyo-night`) in a terminal. Waybar, mako, and the Hyprland border color should update without crashing.
- [ ] **`omedora --version`** prints something like `Omedora 0.1.0 (rebased on Omarchy 3.8.2)`.

---

### 6. Troubleshooting and known gaps

**Only "Hyprland" (no "Omedora") in the session picker — and `omarchy-*`/Walker don't work**
A bare "Hyprland" entry (the plain `hyprland.desktop`, `Exec=Hyprland`, no uwsm) launches without `~/.config/uwsm/env`, so `~/.local/share/omarchy/bin` is missing from PATH and every `omarchy-*` command (autostart, keybinds, Walker launches) fails with "command not found". Select **"Omedora"** instead. The "Omedora" entry is shipped by the `hyprland-omedora` package; if it's missing, `sudo dnf reinstall hyprland-omedora` (see §4).

**`flatpak install` failed during install**
Flatpak installs (Signal, Obsidian, Spotify, Typora, localsend) require a live user D-Bus session. If you ran `install.sh` from a tty without a graphical session, these will fail. Re-run from a GNOME terminal, or install the Flatpaks manually afterward:

```bash
flatpak install -y flathub org.signal.Signal md.obsidian.Obsidian com.spotify.Client io.typora.Typora org.localsend.localsend_app
```

**`walker` or `elephant` not found after install**
Confirm the omedora COPR is enabled (`dnf copr list | grep omedora`). If it's missing, enable it and install the packages:

```bash
sudo dnf copr enable -y agaspar/omedora-3
sudo dnf install -y walker elephant omedora-nerd-fonts swayosd python3-terminaltexteffects
```

**Hyprland fails to start (VT / seat errors)**
This is normal if you try to launch Hyprland from inside another Wayland compositor (e.g., GNOME) directly from a terminal. Log out of GNOME and select the "Omedora" session at GDM instead. Hyprland must be started as the first compositor on a VT seat — uwsm handles this when launched from the display manager.

**Packages marked `skip` in `install/packages/fedora.toml`**
Most former skips (`mise`, `starship`, `usage`, `lazygit`, `lazydocker`, `satty`, `bluetui`, `hyprland-preview-share-picker`) are packaged as omedora RPMs and resolve from the COPR. A few remain deliberately skipped because they're proprietary, vendor-installed, or out of omedora's scope: `claude-code` (proprietary; install via Anthropic's official installer), `1password-cli`, and the 37signals-internal tools. `omarchy-nvim` is also skipped: rather than an RPM, the installer (`install/packaging/nvim.sh`) bootstraps the Neovim config and runs Lazy sync directly on the user's machine, since the package's build needs a network plugin-sync that fails in COPR's offline build. These are logged during install and can be installed manually afterward.

**`dnf copr enable` fails**
The `agaspar/omedora-3` COPR is enabled automatically by the preflight. If it fails (network hiccup, or `dnf-plugins-core` missing), install the plugin and re-enable manually:

```bash
sudo dnf install -y dnf-plugins-core
sudo dnf copr enable -y agaspar/omedora-3
```

---

### Installing onto a machine you already use

Omedora installs **on top of an existing Fedora Workstation**, so on Fedora the
installer is deliberately non-destructive — it never silently overwrites config
you already have. (The Arch path keeps upstream Omarchy's behavior unchanged.)

- **You confirm before anything changes.** Right at the start — before the
  installer touches a single file — it shows one summary of everything it intends
  to do on your machine: the exact list of existing config files it will back up
  and replace, any foreign-repo Hyprland packages it found, and whether it will
  append the `~/.bashrc` block. You then choose **Proceed** or **Abort**; aborting
  leaves the machine completely untouched. If there's nothing to back up and no
  foreign-repo packages, it says so and proceeds without nagging. A non-interactive
  install (no TTY) prints the same summary and continues, since the backup-then-write
  below never deletes anything.

What this means in practice:

- **Your configs are backed up before being replaced.** When omedora seeds its
  `config/*` into `~/.config`, each destination file is handled individually: if
  it doesn't exist it's written; if it's byte-identical it's left alone; if it
  exists and differs, your version is first copied to
  `<file>.pre-omedora-<timestamp>` and *then* omedora's is written. So after an
  install you can always recover your original (e.g.
  `~/.config/hypr/hyprland.conf.pre-omedora-1717430400`). Re-running the install
  or `omedora update` is idempotent: files that already match are skipped, so no
  new backups pile up.

- **`~/.bashrc` is appended to, not replaced.** Omedora adds a small
  sentinel-guarded block (between `# >>> omedora >>>` and `# <<< omedora <<<`)
  that sources the omarchy default shell configuration. Everything else in your
  `~/.bashrc` is preserved, and re-running never double-appends the block.

- **`~/.config/git/config` is left completely alone.** That file is your git
  identity; omedora never copies its own over it. (omedora's
  `git config --global` writes go to `~/.gitconfig` and are additive.)

- **Foreign Hyprland packages are detected — and you can have omedora replace
  them.** Omedora pins and installs its own Hyprland desktop stack (hyprland,
  hyprlock, hypridle, waybar, walker, swayosd, the portal, …). If you already
  have some of these installed from a *foreign* repo — e.g. a third-party COPR
  like `solopasha/hyprland` — the up-front plan names the package and the repo,
  and offers a three-way choice: **Replace** them with omedora's pinned builds,
  **Keep** them and install anyway, or **Abort**. Choosing Replace shows the
  exact package transaction and, once omedora's repos are enabled, runs it for
  you (`dnf swap` for renamed packages like `hyprland`→`hyprland-omedora`,
  `dnf distro-sync` with the foreign repo disabled for same-name packages). A
  non-interactive install keeps the foreign packages and just warns.

  You can run the same scan — and fix — any time:

  ```bash
  omedora doctor        # detect: non-zero exit if a foreign-repo conflict exists
  omedora doctor --fix  # replace foreign packages with omedora's (shows the
                        # transaction, asks once, then applies)
  ```

### 7. After install: staying up to date

```bash
omedora update          # pull the latest omedora source + dnf upgrade (COPR + system)
```

On Fedora, `omedora update` pulls the omedora source (config/bin) and runs
`dnf upgrade --refresh`, which picks up new builds from the `agaspar/omedora-3`
COPR (and your system updates). It does **not** re-copy `config/*` over your
`~/.config` — those are yours to edit; migrations handle any required changes.

Check whether a newer omedora release is out (it compares git tags):

```bash
omedora update-available     # "Omedora update available (vX.Y.Z)" / "up to date"
omedora version              # Omedora 0.1.0 (rebased on Omarchy 3.8.2)
omedora version-channel      # the tracked git ref + COPR
```

See [`versioning.md`](versioning.md) for the full release/versioning/update model.

---

## The documentation set

Read these in roughly this order:

| Doc | What it covers |
|---|---|
| [`architecture.md`](architecture.md) | The technical design: dual-distro patch model, package-helper dispatch, install-pipeline gating, CLI rebrand mechanism, update flow, branding. Includes the patch-stack map — the canonical list of files omedora touches. |
| [`packages.md`](packages.md) | The tiered package-mapping strategy (Fedora main → RPM Fusion → COPR → Flathub → omedora RPMs → skip) and the TOML schema for `install/packages/fedora.toml`. |
| [`testing.md`](testing.md) | The test pyramid (shell unit → Fedora container integration → smoke → L4-nested full session → L4-VM real Workstation VM). Includes the L4-headless automated suite and the libvirt VM pipeline. |
| [`versioning.md`](versioning.md) | omedora's SemVer + release-tag scheme, the version-scoped COPR, and the two-channel (git + dnf) update flow. |
| [`update-and-upgrade.md`](update-and-upgrade.md) | The `omedora update` flow on Fedora and what happens at Fedora major-version upgrades. |
| [`rebase-workflow.md`](rebase-workflow.md) | How to rebase onto a new upstream Omarchy release: branching, conflict triage, verification matrix. |
| [`branding.md`](branding.md) | Where "Omedora" surfaces vs where "Omarchy" remains, and the ASCII logo. |
| [`AGENTS.md`](AGENTS.md) | Supplemental rules for Claude (and humans) working on this fork. Read alongside the root [`../AGENTS.md`](../AGENTS.md). |

## Status

The stable line is the **`3.8.2-omedora`** branch (the repo default; rebased on Omarchy 3.8.2). The full Fedora install path is shipped and serving from the **`agaspar/omedora-3` COPR** (`fedora-44-x86_64`): all vendored RPMs build on the COPR, the installer enables it and resolves the whole stack, the coexistence gate + foreign-package replacement are in, and the versioning/release/update machinery is wired. The install is verified end-to-end on a **real Fedora 44 Workstation VM** (`omedora/test/fedora/vm/`) — provision GNOME+GDM → install from the live COPR → boot the Omedora session on a real seat → the full assertion suite passes — in addition to the L4-nested container suite.

## Known Issues

**First-run `install.sh` fails at the node step with a gnupg lock error.** The installer aborts during `mise use -g node@latest` (in `install/config/mise-work.sh`) with `gpg: error writing keyring '[keyboxd]': SQL library used incorrectly` and `gpg: ... waiting for lock (held by <pid>) ...`, and node is never installed. The tell is that re-running `install.sh` reports the *same* PID every time.

Cause: mise verifies the node download with GPG, which takes a gnupg dotlock under `~/.gnupg/public-keys.d/`. If the machine's hostname changes after that lock is created — e.g. the Fedora installer's default `fedora` later becomes your real hostname — gnupg will not auto-break the now-stale lock, because it only clears stale locks whose recorded hostname matches the current host. So every retry re-reads the same dead PID and wedges. (Confirmed via `cat ~/.gnupg/public-keys.d/*.lock` printing the PID and the old hostname, with `ps -p <pid>` showing no such process.)

Workaround — remove the stale lock and retry. This is safe: the recorded PID is dead and the keybox (`pubring.db`) itself is intact, only locked.

```bash
gpgconf --kill all
rm -f ~/.gnupg/public-keys.d/pubring.db.lock ~/.gnupg/public-keys.d/.#lk*
mise use -g node@latest
```

A durable fix — Fedora-gated `mise settings set node.gpg_verify false`, which keeps SHA256 verification but skips the gnupg lock entirely — is under consideration but not yet shipped.

## License

Same as upstream Omarchy. See [`../LICENSE`](../LICENSE).
