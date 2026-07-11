# Omedora

**Omarchy, on stable Fedora.**

Omedora brings the [Omarchy](https://github.com/basecamp/omarchy) desktop — the
opinionated Hyprland setup from 37signals — to **Fedora Workstation**. You install
it on top of a normal Fedora install, pick "Omedora" at the login screen, and get
the full Omarchy experience: the same Hyprland window management, the same 20+
themes, the same keybindings, and the same `omarchy` command suite — running on
Fedora's packages instead of Arch's.

It's for people who want the Omarchy desktop but need (or prefer) to be on Fedora:
an employer-managed image, hardware enablement, RHEL alignment, or simply Fedora's
release model.

> **Everything installs from Fedora's own repos, RPM Fusion, Flathub, and
> Omedora's own COPR — no third-party COPRs.** The Hyprland stack and tools that
> Fedora doesn't ship are built and served from `agaspar/omedora-3`, which we
> maintain. Nothing comes from an unvetted external repo.

---

## What you get

- **A drop-in Hyprland session.** "Omedora" shows up as a session on your existing
  login screen (GDM/SDDM). Your current desktop stays exactly where it is — log
  into either one.
- **The whole Omarchy desktop:** Hyprland, Waybar, Walker, Mako, SwayOSD, hypridle,
  hyprlock, the wallpapers, and all 20+ themes.
- **The `omarchy` command suite,** also available as `omedora …` (e.g.
  `omedora theme set tokyo-night`).
- **The TUIs and dev tooling** Omarchy ships — lazygit, lazydocker, mise, starship,
  and the Nerd Fonts — packaged for Fedora.

## What Omedora is *not*

Omedora is **not a distro** — it's a desktop you add to Fedora. It doesn't touch
your bootloader (GRUB2), initramfs (dracut), Plymouth, or display manager, and it
doesn't manage snapshots, disk encryption, or kernel drivers. Fedora owns all of
that. If you want a from-scratch Hyprland OS, install upstream Omarchy on Arch.

---

## Install

### Requirements

- **Fedora 44 Workstation**, **x86_64** (the installer checks this — the COPR
  currently builds for `fedora-44-x86_64`).
- A regular user in the `wheel` group (the Workstation default). You are **not**
  root.
- Internet access (Fedora mirrors, RPM Fusion, Flathub, the Omedora COPR).
- Run it from a **GNOME terminal**, not a bare TTY — the Flatpak apps need a live
  user session bus.

> If your `sudo` prompts for a password, run `sudo -v` first so the install
> doesn't block waiting for one midway through.

### One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/AndrewGaspar/omedora/omedora-3/omedora/boot.sh | bash
```

That's it. The bootstrap installs a few prerequisites (`git`, `gum`,
`dnf-plugins-core`), clones Omedora to `~/.local/share/omarchy`, and runs the
installer. Before anything is changed, it shows you a **plan** of exactly what it
will do and asks you to confirm.

The install takes **20–40 minutes** on a fresh machine (mostly Flatpak downloads).
The log lives at `/var/log/omarchy-install.log`.

<details>
<summary>Prefer to drive it yourself? Manual install</summary>

```bash
sudo dnf install -y git gum dnf-plugins-core
git clone https://github.com/AndrewGaspar/omedora.git ~/.local/share/omarchy
bash ~/.local/share/omarchy/install.sh
```

Clone to `~/.local/share/omarchy` specifically — that's the path the installer
expects. For an unattended run, prefix with `OMARCHY_NONINTERACTIVE=1`.
</details>

### First login

Reboot, then at the login screen click the session picker (the gear/cog next to
**Sign In**) and choose **"Omedora"**.

```bash
sudo systemctl reboot
```

> **Pick "Omedora", not "Hyprland".** The "Omedora" session launches through
> `uwsm`, which sets up your PATH so the `omarchy-*` commands and Walker work. A
> bare "Hyprland" entry skips that. (On Fedora, Omedora only installs the
> "Omedora" session entry, so you normally won't even see a plain one.)

Once you're in, Waybar, Mako, the wallpaper, and hypridle all start automatically.
Press **`Super+Space`** to open Walker and you're off.

---

## Installing onto a machine you already use

Omedora installs on top of a Fedora Workstation you're already using, so on Fedora
it's deliberately **non-destructive**:

- **You confirm before anything changes.** The installer opens with a single
  summary of everything it intends to do — every existing config file it will back
  up, any foreign Hyprland packages it found, and the `~/.bashrc` line it will add.
  You choose **Proceed** or **Abort**; aborting leaves the machine untouched.
- **Your configs are backed up, never clobbered.** Existing `~/.config` files are
  copied to `<file>.pre-omedora-<timestamp>` before Omedora writes its version.
  Your `~/.bashrc` is appended to (inside a guarded block), and your git config is
  left completely alone.
- **Optional one-button rollback (btrfs).** If your root is btrfs (Fedora's
  default), the installer offers to snapshot `/` first, so you can roll back with
  `omedora snapshot rollback <name> --apply`. Your `/home` is never touched.

You can re-run the same foreign-package scan any time with `omedora doctor`
(and `omedora doctor --fix` to replace foreign Hyprland packages with Omedora's).

---

## Staying up to date

```bash
omedora update              # pull the latest Omedora + dnf upgrade (COPR + system)
omedora update-available    # is a newer Omedora release out?
omedora version             # e.g. "Omedora 0.1.7 (rebased on Omarchy 3.8.2)"
```

`omedora update` refreshes the Omedora source and runs `dnf upgrade --refresh`,
which picks up new COPR builds and your system updates. It never re-copies configs
over your `~/.config` — those are yours; migrations handle any required changes.

---

## Troubleshooting

**Only "Hyprland" (no "Omedora") in the picker, and `omarchy-*`/Walker don't work.**
You selected the plain Hyprland entry, which launches without `uwsm`, so
`~/.local/share/omarchy/bin` isn't on your PATH. Pick **"Omedora"** instead. If the
"Omedora" entry is missing, `sudo dnf reinstall hyprland-omedora` (it owns the
entry), then log out and pick it.

**A Flatpak app failed to install.** Flatpak needs a live user session bus. If you
ran the installer from a bare TTY, re-run it from a GNOME terminal, or install the
apps afterward:
```bash
flatpak install -y flathub org.signal.Signal md.obsidian.Obsidian com.spotify.Client io.typora.Typora org.localsend.localsend_app
```

**`walker`/`elephant` not found, or `dnf copr enable` failed.** Make sure the COPR
is enabled and reinstall:
```bash
sudo dnf install -y dnf-plugins-core
sudo dnf copr enable -y agaspar/omedora-3
sudo dnf install -y walker elephant omedora-nerd-fonts swayosd
```

**First install stalls at the node step with a gnupg lock error**
(`gpg: ... waiting for lock`). This happens if the machine's hostname changed after
the lock was created. Clear the stale lock and continue — it's safe:
```bash
gpgconf --kill all
rm -f ~/.gnupg/public-keys.d/pubring.db.lock ~/.gnupg/public-keys.d/.#lk*
mise use -g node@latest
```

More install detail and known gaps live in
[`omedora/install.md`](omedora/install.md).

---

## Under the hood

Omedora is a small, additive patch stack **continuously rebased onto Omarchy's
latest stable release**. Most Omarchy files are byte-for-byte unchanged, and the
Arch code paths stay intact — the same tree runs on both distros. If you want the
design details, the packaging strategy, or to contribute, start with
[`omedora/README.md`](omedora/README.md), the documentation hub.

## License

Same as upstream Omarchy — [MIT](LICENSE).
