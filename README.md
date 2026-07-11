# Omedora 4 <sup>alpha</sup>

**Omarchy 4, on stable Fedora.**

Omedora brings the [Omarchy](https://github.com/basecamp/omarchy) desktop — the
opinionated Hyprland setup from 37signals — to **Fedora Workstation**. This is the
**Omarchy 4** line: the re-architected, package-backed generation of Omarchy, with
the new Quickshell-based desktop shell. You install it on top of a normal Fedora
install, pick "Omedora" at the login screen, and get the Omarchy 4 experience —
Hyprland, the new shell, the themes, the keybindings, and the `omarchy` command
suite — running on Fedora's packages.

> ### ⚠️ This is an alpha
> The Omedora 4 line tracks upstream Omarchy 4 (codename "quattro"), which is still
> under active development and not yet released. Expect rough edges and breaking
> changes. **If you want the stable, field-tested experience today, use
> [Omedora 3](https://github.com/AndrewGaspar/omedora/tree/omedora-3)** (the
> `omedora-3` branch) instead.

> **The base system uses no third-party COPRs.** Everything Fedora and RPM Fusion
> don't ship — the Hyprland stack, the Quickshell shell, the tools — is built and
> served from Omedora's own COPR, **`agaspar/omedora-4`**. The one exception is
> **optional**: if you choose to install the Ghostty terminal from the menu, it's
> pulled on demand from the upstream-endorsed `scottames/ghostty` COPR, and only
> then.

---

## What you get

- **A drop-in Omarchy 4 session.** "Omedora" appears as a session on your existing
  login screen (GDM/SDDM). Your current desktop stays exactly where it is.
- **The Omarchy 4 desktop:** Hyprland plus the new **Quickshell** shell (bar,
  launcher, notifications, OSD — replacing the old waybar/walker/mako/swayosd
  stack), the wallpapers, and the themes.
- **The `omarchy` command suite,** also available as `omedora …`.
- **The TUIs and dev tooling** Omarchy ships — lazygit, lazydocker, mise, starship,
  the Nerd Fonts, and the Omedora-packaged apps (voxtype dictation, the screenshot
  and screen-recording tools) — packaged for Fedora.

## What Omedora is *not*

Omedora is **not a distro** — it's a desktop you add to Fedora. It doesn't touch
your bootloader, initramfs, Plymouth, or display manager, and it doesn't manage
snapshots, disk encryption, or kernel drivers. Fedora owns all of that. If you want
a from-scratch Omarchy OS, install upstream Omarchy on Arch.

---

## Install

### Requirements

- **Fedora 44 Workstation**, **x86_64** (the COPR builds for `fedora-44-x86_64`).
- A regular user in the `wheel` group (the Workstation default). You are **not**
  root.
- Internet access (Fedora mirrors, RPM Fusion, Flathub, the Omedora COPR).
- Run it from a **GNOME terminal**, not a bare TTY (the Flatpak apps and the
  first-run setup need a live user session bus).

### One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/AndrewGaspar/omedora/omedora-4/omedora/boot.sh | bash
```

Omarchy 4 ships as **packages**: the `omedora`/`omedora-settings` RPMs own
`/usr/share/omarchy` and the `omarchy-*` commands. So the bootstrap doesn't clone
into your home directory — it fetches just the plan gate and installer, shows you a
**plan** of everything it will do, asks you to confirm, and then hands off to the
package-backed install. Nothing changes before you approve.

### First login

Reboot, then at the login screen open the session picker (the gear/cog next to
**Sign In**) and choose **"Omedora"**.

```bash
sudo systemctl reboot
```

---

## Installing onto a machine you already use

Like Omedora 3, the Fedora install is deliberately **non-destructive** and
**coexistence-first**:

- **You confirm before anything changes.** The installer opens with a single plan
  gate summarizing every config it will back up, any foreign Hyprland packages it
  found, and the system changes it will make. You choose **Proceed** or **Abort**.
- **Your configs are backed up, never clobbered** (backup-then-write); defaults are
  only written if unset.
- **Optional pre-install btrfs snapshot** for one-command rollback if your root is
  btrfs.

---

## Staying up to date

Omarchy 4 updates through the package manager:

```bash
omedora update              # refresh the Omedora COPR + system packages, run migrations
omedora update-available    # is a newer Omedora release out?
omedora version             # the installed Omedora + Omarchy version
```

Because the payload is package-owned, updates come as new COPR builds — `omedora
update` refreshes them and runs any pending user/system migrations. Your
`~/.config` edits are yours; migrations handle required changes.

---

## Coming from Omedora 3?

Omedora 4 is a **major step change** (new shell, package-backed layout). Migration
from an Omedora 3 install is **opt-in** — you'll be asked before anything migrates,
never forced. Until Omedora 4 has a stable release, staying on
[Omedora 3](https://github.com/AndrewGaspar/omedora/tree/omedora-3) is the
recommended path.

---

## Under the hood

Omedora is a small, additive patch stack **continuously rebased onto upstream
Omarchy 4**. Most Omarchy files are byte-for-byte unchanged and the Arch code paths
stay intact — the same tree runs on both distros. For the design, packaging
strategy, and how to contribute, start with [`omedora/README.md`](omedora/README.md),
the documentation hub.

## The Omarchy Manual

The manual lives in [`manual/`](manual/), which is its authoritative source. It's
mirrored to [learn.omacom.io](https://learn.omacom.io/2/the-omarchy-manual), where
its screenshots are also hosted.

- [Welcome to Omarchy!](manual/01-welcome-to-omarchy.md)

**The Basics**

- [Getting Started](manual/02-getting-started.md)
- [Coming From Mac or Windows](manual/03-coming-from-mac-or-windows.md)
- [Navigation](manual/04-navigation.md)
- [The top bar](manual/05-the-top-bar.md)
- [Themes](manual/06-themes.md)
- [Hotkeys](manual/07-hotkeys.md)
- [Unified Clipboard & History](manual/08-unified-clipboard-history.md)
- [Reminders](manual/09-reminders.md)
- [Notices](manual/10-notices.md)
- [Text Extraction & Dictation](manual/11-text-extraction-dictation.md)
- [Screenshots & Recording](manual/12-screenshots-recording.md)
- [Toggles, idle & screensaver](manual/13-toggles-idle-screensaver.md)
- [Omarchy CLI](manual/14-omarchy-cli.md)

**The Applications**

- [Terminal](manual/15-terminal.md)
- [Neovim](manual/16-neovim.md)
- [AI](manual/17-ai.md)
- [Development Tools](manual/18-development-tools.md)
- [Shell Tools](manual/19-shell-tools.md)
- [Shell Functions](manual/20-shell-functions.md)
- [TUIs](manual/21-tuis.md)
- [GUIs](manual/22-guis.md)
- [Browsers](manual/23-browsers.md)
- [Commercial apps/services](manual/24-commercial-apps-services.md)
- [Web Apps](manual/25-web-apps.md)
- [Gaming](manual/26-gaming.md)
- [Filling out PDFs](manual/27-filling-out-pdfs.md)
- [Windows VM](manual/28-windows-vm.md)
- [Other Packages](manual/29-other-packages.md)

**Configuration**

- [Updates](manual/30-updates.md)
- [Dotfiles](manual/31-dotfiles.md)
- [Shell plugins](manual/32-shell-plugins.md)
- [Monitors](manual/33-monitors.md)
- [Keyboard, Mouse, Trackpad](manual/34-keyboard-mouse-trackpad.md)
- [Networking](manual/35-networking.md)
- [System sleep](manual/36-system-sleep.md)
- [Hardware authentication](manual/37-hardware-authentication.md)
- [Fonts](manual/38-fonts.md)
- [Backgrounds](manual/39-backgrounds.md)
- [Prompt](manual/40-prompt.md)
- [Branding](manual/41-branding.md)
- [Common tweaks](manual/42-common-tweaks.md)
- [Extra themes](manual/43-extra-themes.md)
- [Making your own theme](manual/44-making-your-own-theme.md)

**The Rest**

- [Mac support](manual/45-mac-support.md)
- [Troubleshooting](manual/46-troubleshooting.md)
- [FAQ](manual/47-faq.md)
- [System snapshots](manual/48-system-snapshots.md)
- [Security](manual/49-security.md)
- [Omarchy on...](manual/50-omarchy-on.md)
- [Dual Boot Install](manual/51-dual-boot-install.md)
- [Unattended Installs](manual/52-unattended-installs.md)

## License

Same as upstream Omarchy — [MIT](LICENSE).
