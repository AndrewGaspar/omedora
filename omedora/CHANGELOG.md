## v0.2.0-beta.3 — 2026-09-05 (Omarchy 4.0.2)

- Rebase the full Omedora 4 patch stack onto official Omarchy `v4.0.2` at
  `346e69e1cec6c4e8924531874af6ba010a1bc99e7` (from the `v4.0.0` pin).
- Follow upstream's v4.0.2 security rework (#9200): retired input-group grant,
  removed `omarchy-asdcontrol` sudoers drop-in, new `omarchy-dns` and
  `omarchy-theme-browser` drop-ins packaged.
- Handle six new Arch-only migrations on Fedora: gate four (mise-bin and
  quickshell swaps, input-group trim, cups-browsed removal) and record two
  as reviewed-safe (keyring, mirror).
- Map the renamed/added v4.0.2 base packages (`mise-bin`, `qt6-imageformats`,
  `vulkan-intel`/`vulkan-radeon`, `quickshell`) so the managed updater
  resolves them.
- Fix the beta update path: default `OMARCHY_PATH` in `omarchy-update-dev`,
  resolve the COPR project from the packaged payload in `omedora-copr`,
  skip the systemd reload in the printer migration when no bus is present.
- Fix fresh installs on the v4 line: drive system setup via
  `omarchy apply system`, gate `snapper.sh` Arch-only, skip
  not-found/masked units when enabling services.
- Check the Omedora 4 XR payload by COPR provenance instead of release
  number, and extend the package-map and mocked-upgrade coverage.

## v0.2.0-beta.2 — 2026-08-20 (Omarchy 4.0.0)

- Rebase the full Omedora 4 patch stack onto official Omarchy `v4.0.0` at
  `f0020448ca87329199de7cb12f2015ebc4a3e5e7`.
- Keep Fedora updates scoped to Omedora-managed RPMs and add coverage proving
  unrelated installed packages are excluded.
- Require beta.1 users to bootstrap beta.2 with a scoped
  `dnf upgrade omedora omedora-settings` before invoking `omedora update`.
- Enable and verify the version-scoped Omedora COPR, fail closed when managed
  candidates or core provenance are unavailable, and honor map version bounds.
- Gate the Quattro wpa_supplicant and mkinitcpio migrations on Fedora.
- Classify the optional `grok-bot` menu package as unavailable on Fedora.

## v0.2.0-beta.1 — 2026-08-12 (Omarchy Quattro beta3+13)

- Rebase the Omedora 4 patch stack onto `quattro` at `106320ab`.
- Adapt Fedora provisioning and migration gates to the current beta layout.
- Port the complete parallel HypXRland package stack to `agaspar/omedora-4`.
- Preserve stable Hyprland as the fallback beside the private Omedora XR
  compositor, control client, and session.
- Upgrade surviving Omedora 3 RPMs before disabling its COPR so DNF5 installs
  changed Omedora 4 payloads and dependencies.
- Verify the package-backed Omedora 3 to Omedora 4 XR transition end to end.

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
