# Omedora

**Omedora is Omarchy for stable Fedora Workstation.**

It's a fork of [basecamp/omarchy](https://github.com/basecamp/omarchy) — the opinionated Hyprland desktop project from 37signals — retargeted at enterprise-supported Fedora Workstation (44+). The aim is to preserve as much of the Omarchy experience as possible (keybindings, theming, the `omarchy` command suite, the look-and-feel) while running on Fedora's official package repositories, RPM Fusion, and a small set of vetted COPRs / Flathub apps.

## What omedora is

A **drop-in Hyprland session** that you install on top of an existing Fedora Workstation. After install, "Omedora" appears as a session option on your existing login screen (GDM, SDDM, whatever you have). Pick it, log in, and you get the Omarchy-style Hyprland desktop — same keybindings, same themes, same `omedora` / `omarchy` command surface.

The full Omarchy `~/.config/` payload, the 20 themes, the `omarchy-*` command suite (re-exposed as `omedora …`), and all the UX shell apps (waybar, mako, walker, swayosd, hypridle, hyprlock, etc.) come along for the ride.

## What omedora is not

**Not a distro.** Omedora doesn't own:

- The bootloader (GRUB2 stays as-is — no Limine, no systemd-boot)
- The initramfs (dracut stays as-is — no mkinitcpio porting)
- Plymouth (Fedora has its own)
- The display manager (GDM / SDDM stays as-is — omedora ships a Wayland session entry, not a DM swap)
- BTRFS snapshots, hibernation, firewall, disk encryption, kernel modules, DKMS drivers

If you want a from-scratch Hyprland distro, install upstream Omarchy on Arch. Omedora is the answer when you need to be on Fedora for reasons outside your control (employer-managed image, hardware enablement, RHEL alignment, just a preference for Fedora's release model).

## How it stays close to upstream

Omedora is structured as a **patch stack continuously rebased onto Omarchy's latest stable release**. The patches are deliberately small and additive: most Omarchy files are byte-for-byte unchanged, and the Arch code paths inside the dual-distro helpers stay intact. The same tree runs on both distros — Arch users of this fork get the upstream Omarchy experience untouched, Fedora users get the omedora-flavored variant.

Long-term, the goal is that agents (Claude) handle most of the rebase work each release. The `omedora/` documentation folder you're reading is the architectural anchor for that work.

## The documentation set

Read these in roughly this order:

| Doc | What it covers |
| --- | --- |
| [`architecture.md`](architecture.md) | The technical design: dual-distro patch model, package-helper dispatch, install-pipeline gating, CLI rebrand mechanism, update flow, branding. Includes the patch-stack map — the canonical list of files omedora touches. |
| [`packages.md`](packages.md) | The tiered package-mapping strategy (Fedora main → RPM Fusion → COPR → Flathub → source) and the TOML schema for `install/packages/fedora.toml`. |
| [`update-and-upgrade.md`](update-and-upgrade.md) | The `omedora update` flow on Fedora and what happens at Fedora major-version upgrades. |
| [`rebase-workflow.md`](rebase-workflow.md) | How to rebase onto a new upstream Omarchy release: branching, conflict triage, verification matrix. |
| [`branding.md`](branding.md) | Where "Omedora" surfaces vs where "Omarchy" remains, and the ASCII logo. |
| [`AGENTS.md`](AGENTS.md) | Supplemental rules for Claude (and humans) working on this fork. Read alongside the root [`../AGENTS.md`](../AGENTS.md). |

## Status

This commit is the **base commit of the omedora patch stack**: documentation + branding assets only. No code has been touched yet. Subsequent commits implement the architecture described here; they are the ones that get rebased onto each new Omarchy release.

## License

Same as upstream Omarchy. See [`../LICENSE`](../LICENSE).
