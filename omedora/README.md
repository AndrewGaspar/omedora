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

## Manual installation guide (Fedora 44 client VM)

This section walks through installing Omedora by hand on a **fresh Fedora 44 Workstation VM**. It is the closest approximation to the real end-user flow before a published COPR exists. Every command below is taken directly from the installer scripts and build tooling — nothing is invented.

**Assumptions:**

- Fedora 44 Workstation (GNOME spin) installed, with a regular user account that has `sudo` rights via the `wheel` group.
- x86\_64 only (Omedora's installer hard-checks this).
- You are **not** running as root.
- Internet access to Fedora mirrors, COPR, and Flathub.
- The build steps use `podman` (available in Fedora's main repos) to run the RPM builds in a `fedora:44` container — this avoids needing `rpmbuild` installed on your workstation and exactly matches what CI does.
- > **PLACEHOLDER:** The GitHub URL used below is `https://github.com/AndrewGaspar/omedora`. Verify this matches the published remote before sharing the guide externally.

---

### 1. Prerequisites

Install `podman`, `createrepo_c`, `git`, and `gum` on the Fedora host.

`gum` is required **before** `install.sh` runs — the preflight stage uses it for styled output. `podman` is needed to build the RPMs. `createrepo_c` assembles the local repo.

```bash
sudo dnf install -y podman createrepo_c git gum
```

Make sure your user is in the `wheel` group (standard on Workstation). The installer calls `sudo` for system-level writes; it must not require a password prompt mid-install. If your wheel sudo needs a password, either enter it proactively (`sudo -v`) or add yourself to a NOPASSWD rule for the duration.

---

### 2. Clone omedora

```bash
git clone https://github.com/AndrewGaspar/omedora.git ~/.local/share/omarchy
```

> **Why `~/.local/share/omarchy`?** That is the path the installer hardcodes (`OMARCHY_PATH`). Cloning omedora there is exactly what `boot.sh` does via `OMARCHY_REPO=AndrewGaspar/omedora`. Do not clone to a different path.

If you want a specific branch (the development branch is `dev`):

```bash
git -C ~/.local/share/omarchy checkout dev
```

---

### 3. Build the omedora RPMs locally

Omedora needs five packages that are not in Fedora's official repos or RPM Fusion. These are built as RPMs and served from a local `dnf` repository. There is no public COPR yet — you build them yourself.

The packages are:

| RPM name | What it provides |
|---|---|
| `walker` | The walker application launcher |
| `elephant` | Walker's calculator and clipboard provider |
| `omedora-nerd-fonts` | CascadiaCode + JetBrainsMono Nerd Fonts (icon-patched) |
| `swayosd` | On-screen display for volume/brightness |
| `python3-terminaltexteffects` | The `tte` terminal-effects CLI |

The build scripts run each `*.spec` inside a throwaway `fedora:44` container via `podman`, so the build environment exactly matches what a COPR would use. The output lands in `omedora/packaging/copr/output/` and the assembled repo (with `createrepo_c` metadata) lands in `omedora/packaging/copr/repo/`.

```bash
cd ~/.local/share/omarchy
bash omedora/packaging/copr/build-repo.sh
```

This runs all five specs in sequence, then assembles `omedora/packaging/copr/repo/`. The first run pulls the `registry.fedoraproject.org/fedora:44` base image and downloads build dependencies — expect 10–20 minutes on a cold cache. Subsequent runs are faster.

When it finishes you should see a `repo contents:` listing with the five `.rpm` files.

---

### 4. Enable the local repo

The installer resolves `walker`, `elephant`, `omedora-nerd-fonts`, `swayosd`, and `python3-terminaltexteffects` by name from `dnf`. For those names to resolve, `dnf` needs to know about the local repo you just built.

Drop a `.repo` file pointing at it. Resolve the path **as your own user first** — inside `sudo bash -c`, `~` would expand to `/root`, not your home:

```bash
REPO_DIR="$(realpath ~/.local/share/omarchy/omedora/packaging/copr/repo)"
sudo tee /etc/yum.repos.d/omedora-local.repo >/dev/null <<EOF
[omedora-local]
name=Omedora local packages
baseurl=file://$REPO_DIR
enabled=1
gpgcheck=0
EOF
```

> This is exactly what `omedora/test/fedora/build-session.sh` does (step 2.5), translated from `podman cp` + `exec` into direct host commands. The `file://` URL must point at the directory containing `repodata/`. Note `$REPO_DIR` is expanded by *your* shell before `sudo` runs, so the path resolves against your home — don't move the `realpath` inside the `sudo` command (there `~` becomes `/root`).

Verify `dnf` can see the repo:

```bash
dnf repoinfo omedora-local
```

---

### 5. Run the installer

The installer sources `~/.local/share/omarchy/install.sh` directly. On Fedora it runs the preflight (guards, third-party repo enablement), the packaging stage (all packages via `dnf`/Flathub dispatch), and the config stage. The Arch-only stages (`login/`, `post-install/` — Plymouth, SDDM, Limine, final pacman config) are gated off automatically because `omarchy-distro` reports `fedora`.

From a terminal in your regular user session:

```bash
bash ~/.local/share/omarchy/install.sh
```

The installer is **interactive** — it uses `gum` for styled output and error handling. If something fails partway through, `gum` prompts you with options (retry, view log, exit). The install log is written to `/var/log/omarchy-install.log`.

To run non-interactively (useful for scripted or repeatable testing — skips the gum error menu on failure and exits immediately):

```bash
OMARCHY_NONINTERACTIVE=1 bash ~/.local/share/omarchy/install.sh
```

**What to expect:**

1. **Preflight:** The Fedora guard checks that you are not root and are on x86\_64. Then `fedora-repos.sh` enables RPM Fusion (free + nonfree) and the `lionheartp/Hyprland` COPR (Hyprland is not in Fedora 44 main repos). Flathub is also enabled as a Flatpak remote.
2. **Packaging:** All packages are installed via `dnf` or `flatpak`. The omedora-local repo satisfies `walker`, `elephant`, `omedora-nerd-fonts`, `swayosd`, and `python3-terminaltexteffects`. Hyprland and related tools (`hypridle`, `hyprlock`, `hyprpaper`, `hyprsunset`, `xdg-desktop-portal-hyprland`) come from the `lionheartp/Hyprland` COPR. GUI apps (Signal, Obsidian, Spotify, Typora, localsend) install as Flatpaks from Flathub — these require an active user session bus (you're running in a real GNOME session, so this is fine).
3. **Config:** Omedora's `~/.config/` payload (Hyprland, waybar, walker, mako, etc.) is written to your home directory. Themes are installed. The Wayland session entry `/usr/share/wayland-sessions/omedora.desktop` is shipped by the `hyprland-omedora` package (pulled in when `hyprland` installs on Fedora) — no longer a sudo-cp. **At the login screen, pick "Omedora" — not the bare "Hyprland" entry** (the plain entry launches without uwsm, which breaks PATH so `omarchy-*` commands and Walker can't launch anything).
4. The install takes **20–40 minutes** on a fresh VM, dominated by Flatpak runtime downloads.

---

### 6. Reboot and select the Omedora session

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

### 7. Verification checklist

After the session is running, confirm the key omedora surfaces work:

- [ ] **Menu opens:** Press `Super+Space`. Walker should appear as a fullscreen launcher.
- [ ] **`tte` is on PATH:** Open a terminal (`Super+Enter`) and run `tte --help`. The terminal-text-effects CLI should respond.
- [ ] **No swayosd crash toast:** Adjust volume (omedora maps `XF86AudioRaiseVolume` / `XF86AudioLowerVolume`). A brief overlay should appear, not a mako error notification.
- [ ] **Fonts render correctly:** Open `kitty` or `foot`. The terminal should render JetBrainsMono Nerd Font with icon glyphs (no tofu squares). Waybar icons should also render cleanly.
- [ ] **Theme switching works:** Run `omedora theme set tokyo-night` (or `omarchy theme set tokyo-night`) in a terminal. Waybar, mako, and the Hyprland border color should update without crashing.
- [ ] **`omedora --version`** prints something like `Omedora 0.1.0-base (rebased on Omarchy ...)`.

---

### 8. Troubleshooting and known gaps

**Only "Hyprland" (no "Omedora") in the session picker — and `omarchy-*`/Walker don't work**
A bare "Hyprland" entry (the plain `hyprland.desktop`, `Exec=Hyprland`, no uwsm) launches without `~/.config/uwsm/env`, so `~/.local/share/omarchy/bin` is missing from PATH and every `omarchy-*` command (autostart, keybinds, Walker launches) fails with "command not found". Select **"Omedora"** instead. The "Omedora" entry is shipped by the `hyprland-omedora` package; if it's missing, `sudo dnf reinstall hyprland-omedora` (see §6).

**`flatpak install` failed during install**
Flatpak installs (Signal, Obsidian, Spotify, Typora, localsend) require a live user D-Bus session. If you ran `install.sh` from a tty without a graphical session, these will fail. Re-run from a GNOME terminal, or install the Flatpaks manually afterward:

```bash
flatpak install -y flathub org.signal.Signal md.obsidian.Obsidian com.spotify.Client io.typora.Typora org.localsend.localsend_app
```

**`walker` or `elephant` not found after install**
Confirm the `omedora-local` repo was visible when `install.sh` ran (`dnf repoinfo omedora-local`). If it was missing, install them now:

```bash
sudo dnf install -y walker elephant omedora-nerd-fonts swayosd python3-terminaltexteffects
```

**Hyprland fails to start (VT / seat errors)**
This is normal if you try to launch Hyprland from inside another Wayland compositor (e.g., GNOME) directly from a terminal. Log out of GNOME and select the "Omedora" session at GDM instead. Hyprland must be started as the first compositor on a VT seat — uwsm handles this when launched from the display manager.

**Packages marked `skip` in `install/packages/fedora.toml`**
Most former skips (`mise`, `starship`, `usage`, `lazygit`, `lazydocker`, `satty`, `bluetui`, `hyprland-preview-share-picker`) are now packaged as omedora RPMs and resolve from the local repo you built in step 3. A few remain deliberately skipped because they're proprietary, vendor-installed, or out of omedora's scope: `claude-code` (proprietary; install via Anthropic's official installer), `1password-cli`, and the 37signals-internal tools. `omarchy-nvim` is also skipped: rather than an RPM, the installer (`install/packaging/nvim.sh`) bootstraps the Neovim config and runs Lazy sync directly on the user's machine, since the package's build needs a network plugin-sync that fails in COPR's offline build. These are logged during install and can be installed manually afterward.

**Build fails: `podman` pull errors**
If `build-repo.sh` fails pulling `registry.fedoraproject.org/fedora:44`, try:

```bash
podman pull registry.fedoraproject.org/fedora:44
```

If that also fails (common behind corporate proxies), set `HTTPS_PROXY` / `HTTP_PROXY` in your environment before running the build.

**`dnf copr enable` fails**
The `lionheartp/Hyprland` COPR is enabled automatically by the preflight. If it fails (network hiccup), re-run the preflight step manually:

```bash
sudo dnf copr enable -y lionheartp/Hyprland
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

### 9. After install: staying up to date

When a public COPR is published, the local `.repo` file and the build step (§3–§4) go away. The only change will be swapping the `source = "dnf"` entries in `install/packages/fedora.toml` to reference the COPR, and dropping the `omedora-local.repo` file.

Until then, to pick up new upstream Omarchy config changes:

```bash
git -C ~/.local/share/omarchy pull --rebase
bash ~/.local/share/omarchy/install.sh
```

The install is idempotent — re-running it applies new config files and any package additions without reinstalling everything.

---

## The documentation set

Read these in roughly this order:

| Doc | What it covers |
|---|---|
| [`architecture.md`](architecture.md) | The technical design: dual-distro patch model, package-helper dispatch, install-pipeline gating, CLI rebrand mechanism, update flow, branding. Includes the patch-stack map — the canonical list of files omedora touches. |
| [`packages.md`](packages.md) | The tiered package-mapping strategy (Fedora main → RPM Fusion → COPR → Flathub → omedora RPMs → skip) and the TOML schema for `install/packages/fedora.toml`. |
| [`testing.md`](testing.md) | The four-layer test pyramid (shell unit → Fedora container integration → smoke → L4-nested full session). Includes the L4-headless automated test suite. |
| [`update-and-upgrade.md`](update-and-upgrade.md) | The `omedora update` flow on Fedora and what happens at Fedora major-version upgrades. |
| [`rebase-workflow.md`](rebase-workflow.md) | How to rebase onto a new upstream Omarchy release: branching, conflict triage, verification matrix. |
| [`branding.md`](branding.md) | Where "Omedora" surfaces vs where "Omarchy" remains, and the ASCII logo. |
| [`AGENTS.md`](AGENTS.md) | Supplemental rules for Claude (and humans) working on this fork. Read alongside the root [`../AGENTS.md`](../AGENTS.md). |

## Status

The `dev` branch has the install pipeline gating (Fedora arm of `install.sh`, `preflight/guard.sh`, `preflight/fedora-repos.sh`) and the full RPM packaging set shipped. The Wayland session entry install step is planned (step 11 in [`testing.md` §10](testing.md#10-implementation-roadmap)). The L4-nested test path (boot a full Omedora session in a Fedora container under real `systemd --user`) is shipped and verified.

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
