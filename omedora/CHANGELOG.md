## v0.1.8 — 2026-08-03 (Omarchy 3.8.4)

- fix(l4): repair the golden gate for IM 7.1.2 + mask the 0.56.1 .conf banner
- docs(install): note Hyprland 0.56.1's per-login .conf notice is informational on Omedora
- Retune opacity for Hyprland 0.56's corrected alpha premultiplication
- Parse plain hyprctl binds output to survive Hyprland 0.56's broken JSON
- chore(copr): rebuild the unversioned hypr* libs against hyprutils 0.14 (SONAME 13)
- chore(copr): Hyprland 0.56.1 wave — hyprutils 0.14, aquamarine 0.14, XDPH 1.4.1
- docs(sync): document the append-only cherry-pick strategy for omedora-3
- test(pkg): resolve the 3.8.4 mappings against the shipped fedora.toml
- fix(power): drop the fixed unit name from the Fedora power-profile udev rule
- feat(fedora): map the packages the 3.8.4 migrations install
- chore(base): record Omarchy 3.8.4 as the rebased-on version
- Package name is now neovim
- Fix Neovim theme symlink pointing at the Omarchy 4 theme location (#6318)
- Fix Foot text bindings migration
- Remove the dropped packages preventing installation
- New waybar won't die without a pkill -9
- Only promote firmware during kernel transitions
- Address upgrade migration review feedback
- Make package removal ignore providers
- Nudge XPS 13 text scaling down just ever so slightly
- Drop fixed unit name from power-profile udev rule to prevent wakeup failures
- Bundle vconsole.conf in the initramfs so Plymouth uses the right keymap at the LUKS prompt
- Backfill Mesa Vulkan drivers for systems installed before vulkan.sh
- Append the terminal feature instead of just ovewrwritting the 3
- Add mup alias for updating mise without the release age guard
- Add cy alias for codex
- Widen sof-firmware install to all Intel SOF audio platforms
- Bump version
- Add migration for easier tmux pane controls
- Make sure Intel wildcat machines get sof-firmware for working audio
- Use titles for better remote server identification with hyprland groups
- Add easier tmux pane controls
- Fix repeated fingerprint setup
- fix(doctor): stop flagging stock packages with opaque provenance as foreign
- docs(readme): drop bespoke troubleshooting from the landing page
- chore(branch): rename 3.8.2-omedora->omedora-3 in tree refs
- docs(readme): friendly install-focused root README + omedora/ docs index
- chore(copr): remove stale lionheartp/Hyprland references (all COPRs are now our own)

## v0.1.7 — 2026-06-20 (Omarchy 3.8.2)

- test(install): cover the Fedora Package picker + AUR no-op
- feat(install): hide the AUR install path on Fedora
- feat(install): port the Install → Package picker to dnf on Fedora

## v0.1.6 — 2026-06-16 (Omarchy 3.8.2)

- fix(branding): rebrand the waybar menu + update tooltips to Omedora

## v0.1.5 — 2026-06-16 (Omarchy 3.8.2)

- fix(branding): label the Menu > Update entry Omedora, not Omarchy

## v0.1.4 — 2026-06-16 (Omarchy 3.8.2)

- ci(copr): register changed packages before building (#123)
- Make webapps profile-aware for Chromium browsers
- Add Wezterm auto-theming support
- ci(copr): fetch full history so multi-commit pushes diff cleanly
- chore(copr): bump Hyprland wave — glaze 7.8.2, aquamarine 0.12.1, hyprland 0.55.4
- chore(copr): bump satty 0.20.1 -> 0.21.1
- chore(copr): bump mise 2026.6.11, usage 3.5.0, uwsm 0.26.5
- feat(upgrade): ship omedora-upgrade-to-4 on the stable line
- docs(testing): correct the L4-in-CI feasibility claim — hosted runners can't
- fix(test): isolate XDG_DATA_DIRS in mimetypes-browser-test
- test(ci): wire fcitx seed-skip + XCompose backup tests into the L1 job
- feat(fedora): disclose default-app & preference changes in the plan gate
- fix(fedora): set HEY as mailto handler only when none is set
- fix(fedora): back up ~/.XCompose before overwriting it
- fix(fedora): skip seeding fcitx IME env vars when fcitx isn't installed
- refactor(fedora): drop redundant GNOME dark-mode hardcode on Fedora
- test(fedora): cover default-browser respect/force in mimetypes.sh
- fix(fedora): don't clobber the user's default web browser

## v0.1.3 — 2026-06-05 (Omarchy 3.8.2)

- fix(bootstrap): default boot-omedora.sh ref to 3.8.2-omedora, not dev
- fix(fedora): brand the update flow as Omedora; drop upstream community links

## v0.1.2 — 2026-06-05 (Omarchy 3.8.2)

- docs(update): correct util-linux-script reference to fedora-baseline.sh
- test(fedora): upgrade-from-prior-release integration test + recovery docs
- test(update): L1 unit coverage for the Fedora update-flow fixes
- feat(fedora): install util-linux-script so fresh installs log the update
- refactor(update): honor $OMEDORA_DNF_CMD in omedora-update-pkgs
- fix(update): Fedora-gate the NTP-restart and kernel-ownership probes in the update chain
- fix(update): guard the `script` PTY wrapper so a missing util-linux-script doesn't kill the update
- test(snapshot): L4-VM btrfs rollback test on a real rebooted Fedora VM
- feat(snapshot): offer a pre-install btrfs snapshot at the gate
- feat(snapshot): omedora-snapshot — btrfs system snapshots for Fedora

## v0.1.1 — 2026-06-05 (Omarchy 3.8.2)

- fix(replace): keep the atomic swap critical, make reconciliation non-fatal
- fix(replace): swap + install + distro-sync so a foreign Hyprland replace works
- feat(replace): disable the foreign COPR after replacing its packages
- fix(fedora): coexistence gate is interactive under `curl | bash`
- fix(install): stop the error handler from choking on dash-prefixed output
- fix(test): L2 integration installs the nerd-fonts from the COPR
- fix(test): give pkg-helper-test a session bus for the flatpak routing asserts
- fix(ci): point L2/L3 COPR assertions at omedora-3 + run Test on the launch branch

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
