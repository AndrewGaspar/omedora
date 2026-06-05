## v0.1.0 — 2026-06-05 (Omarchy 3.8.2)

Initial public release — **Omarchy for stable Fedora Workstation**.

- **Install path (Fedora 44):** `omedora/boot.sh` → the `agaspar/omedora-3` COPR
  → `install.sh`, with the Arch-only stages (Plymouth/SDDM/Limine/pacman) gated
  off automatically.
- **Vendored RPMs** for the whole Hyprland desktop stack plus
  walker/elephant/swayosd/uwsm/nerd-fonts/TUIs, served from the COPR —
  sha256-pinned sources, Rust crates vendored deterministically at SRPM-gen time.
- **Hyprland session split:** `hyprland-omedora` ships the uwsm-launched Omedora
  session entry; a plain `hyprland` remains for piggybackers.
- **Coexistence:** an up-front plan-then-confirm gate backs up (never clobbers)
  your existing config before changing anything; `omedora doctor --fix` swaps
  foreign-repo Hyprland packages for omedora's pinned builds.
- **Versioning / release / update:** omedora SemVer over the Omarchy base,
  `omedora update` (git pull + dnf upgrade), update detection via release tags,
  and a version-scoped-per-major COPR.
- **Verified end-to-end on a real Fedora 44 Workstation VM:** provision GNOME+GDM
  → install from the live COPR → boot the Omedora/Hyprland session on a real seat
  → full assertion suite green.
