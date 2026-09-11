## v0.2.0-beta.5 — 2026-09-11 (Omarchy 4.0.3)

- test(vm): ship the TAP helpers with the suite and name the compositor RPM
- test(vm): stop sudo -v from prompting the VM test user
- test(fedora): bring the L3 update and L4 VM gates onto the Omarchy 4 line
- mise.spec: update to 2026.9.5 so upgrade.auto_prune is a known setting
- chore(release): prepare core specs at 0.2.0~beta.5
- byte-identity: record the carried shell feature patches
- hypxrland.spec: name hyprland-xr.lua, not .conf, in the package description
- docker: keep an existing Docker CE / podman-docker install (#6)
- pkg map: add satisfied_by so an installed provider counts as the entry
- Surface a refused lock in omarchy-system-lock on Fedora
- Add migration restoring the lock screen PAM service on Fedora
- ttfx.spec: update to 0.3.2 (stop dumping core when the terminal goes away)
- port(update): gate omarchy-update-pkg-prune on Fedora
- Map sof-firmware to alsa-sof-firmware on Fedora

## v0.2.0-beta.4 — 2026-09-08 (Omarchy 4.0.3)

- voxtype.spec: silence macro-expanded-in-comment warning (line 359)
- voxtype-spec-test: no-$$ rule ignores indented comments too
- voxtype-spec-test: exempt comment lines from the no-$$ rule
- voxtype.spec: fix lib64/%files mismatch + PID-expanded man loop
- voxtype.spec: disable debuginfo/debugsource (vendor +x trips brp)
- voxtype.spec: build vendored whisper.cpp with -fPIC (PIE link fix)
- voxtype.spec: %%-escape parse-unknown macros in comments
- voxtype: reconcile tree with the from-source 1.0.1 single-package build
- voxtype: from-source build of muse-stack fork 1.0.1 (vendored, CPU-only)
- chore(rebase): re-pin Omedora 4 onto Omarchy v4.0.3
- fixup: follow upstream repair-only fingerprint migration
- Launcher: a gamepad-friendly fullscreen app grid (from the tip checkout, uncommitted there)
- Bar: a keyboard focus ring over the bar's icons
- Menu search: tolerate dictated punctuation and filler words
- Shell: handle the standard Back key (XF86Back) — up one menu level, close at root
- Close the rename editor when its device stops being remembered
- Judge a device by either of its names, not just its label
- Let a device be renamed from the Bluetooth panel
- Show the friendly name a device was given
- build(fedora): run the XR session from hyprland-xr.lua
- chore(release): build beta.3 RPMs, relax upgrade version pin
- docs: summarize beta.3 changelog
- release: omedora v0.2.0-beta.3 (Omarchy 4.0.2)
- fix(fedora): skip systemd reload in printer migration without bus
- fix(fedora): map vulkan driver packages
- fix(fedora): skip not-found and masked units in enable_if_present
- fix(fedora): gate snapper config Arch-only
- fix(fedora): drive system setup via omarchy apply system
- fix(fedora): map new v4.0.2 base packages
- fix(fedora): resolve base version from packaged payload in omedora-copr
- fix(fedora): follow upstream #9200 security rework in packaging
- fix(fedora): default OMARCHY_PATH in omarchy-update-dev
- fix(test): check Omedora 4 XR payload by provenance, not release number
- fix(fedora): gate new v4.0.1/v4.0.2 Arch-ism migrations
- chore(rebase): re-pin Omedora 4 onto Omarchy v4.0.2
- fix(fedora): use SVT-AV1 for hypxrcompose
- test(fedora): verify the Quattro XR package wave
- build(fedora): refresh the Quattro HypXR stack
- fix(fedora): package Quattro crash watcher unit
- build(fedora): update Hyprland to 0.56.2
- docs: align Omedora contracts with Quattro
- chore(rebase): prepare Omarchy 4.0.0 release metadata
- test(fedora): modernize package-backed integration
- fix(fedora): scope updates to managed RPMs
- fix(fedora): align Quattro package mappings
- fix(fedora): gate Quattro-only migrations
- Map the Quattro .NET runtime on Fedora
- Force the Quattro Quickshell transition
- Package the remaining Quattro beta tools
- Finalize the Quattro beta release notes
- Test the Omedora 3 to 4 XR transition
- Sync the beta user-service package payload
- Package the parallel HypXRland stack for Omedora 4
- Prepare the Omedora 4 beta upgrade path
- Adapt Omedora 4 to Quattro beta
- docs(rebase): rewrite the workflow for omedora-4's pin-tag rebase line
- fix(doctor): stop flagging stock packages with opaque provenance as foreign
- chore(branch): rename omarchy-4-omedora->omedora-4 in tree refs
- docs(readme): friendly install-focused root README + omedora/ docs index
- chore(copr): remove stale lionheartp/Hyprland references (base has no third-party COPRs)
- feat(fedora): install gpu-screen-recorder so screen recording works
- feat(copr): package gpu-screen-recorder from source
- chore(fedora): drop lionheartp/Hyprland from the COPR allowlist
- fix(fedora): map ghostty to the scottames/ghostty COPR (lazy, on-demand)
- feat(fedora): adopt native omacut and omawrite
- feat(copr): package omacut and omawrite from source
- fix(upgrade): add tensaku to v4_kept_packages
- feat(fedora): adopt native tensaku; satty shim becomes a fallback
- feat(copr): package tensaku screenshot annotation editor from source
- ci(copr): fall back to HEAD~1 when the push `before` is unreachable
- fix(fedora): handle quattro's new base packages (tensaku/omacut/omawrite)
- test(upgrade): exclude on-demand voxtype from the kept-packages cross-check
- fix(fedora): gate new quattro Arch-ism migrations + channel-current
- docs(update): correct the Fedora update-available dispatch comment
- chore(rebase): re-pin omedora-4 onto omarchy/quattro
- feat(menu): hide Install > AUR entry on Fedora
- fix(branding): label the Menu > Update entry Omedora, not Omarchy
- ci(copr): auto-register new packages before building (#123)
- fix(fedora): scope the update indicator to omedora COPR packages (#108)
- test(byte-identity): allowlist e8939ed9's omarchy-launch-webapp deletions
- Make webapps profile-aware for Chromium browsers
- Add Wezterm auto-theming support
- chore(copr): bump Hyprland wave — glaze 7.8.2, aquamarine 0.12.1, hyprland 0.55.4
- chore(copr): bump satty 0.20.1 -> 0.21.1
- chore(copr): bump mise 2026.6.11, usage 3.5.0, uwsm 0.26.5
- fix(voxtype): inline the NVIDIA lspci probe (don't exec omarchy-hw-nvidia)
- docs(voxtype): describe the COPR-hosted subpackaged flavors
- test(voxtype): flavor auto-detect + spec static guard; drop remove ALLOW
- feat(voxtype): wire the COPR flavors — flavor installer + GPU auto-detect
- feat(voxtype): COPR spec — subpackaged binary-repackage (base + cuda + migraphx)
- feat(voxtype): bar mic offers to install voxtype when it's missing (Fedora)
- fix(branding): seed screensaver + show-logo wordmark from Omedora art
- test(fedora): voxtype-install L1 + docs/fedora.toml updates
- feat(fedora): wire voxtype install/remove to the upstream RPM
- feat(fedora): add on-demand voxtype RPM installer sibling
- fix(fedora): gate channel/plymouth/fingerprint Arch-isms (#113, re-derived)
- fix(fedora): gate omarchy-debug package listing to rpm/dnf
- fix(fedora): gate RetroArch install to RPM Fusion (retroarch + libretro cores)
- fix(fedora): bootstrap LazyVim nvim config on the v4 desktop (#106)
- fix(fedora): voxtype dictation degrades gracefully (#109)
- fix(fedora): add perl-JSON-PP/Encode + libxkbcommon-utils to the baseline (#107)
- fix(fedora): make the About/version surface Fedora-aware (#110)
- fix(fedora): wire the powerprofilesctl shim on the omarchy-4 line (P7 gap)
- ci(copr): fetch full history so multi-commit pushes can diff changed specs
- docs: correct the quickshell-vendor rationale (forward-looking, not a break fix)
- fix(upgrade): keep quickshell on upgrade (it's now a vendored omedora package)
- integrate(quickshell): drop the Background.qml shim now that 0.3.0 is vendored
- feat(copr): vendor quickshell 0.3.0 as an omedora RPM
- docs(testing): update the L4 sections for the v4 Quickshell desktop
- test(l4): degrade 90-workstation power-coexistence gracefully in-container
- test(l4): regenerate the 30-visual golden for the v4 desktop + harden it
- test(l4): suppress the container-only Hyprland config-error banner
- test(l1): add the byte-identity audit for modified upstream files
- fix(shell): guard updatesEnabled assignment for older quickshell (Fedora 44)
- test(l4): rewrite the headless suite for the v4 shell-IPC desktop
- test(l4): adapt the headless lib + orchestrator to the v4 shell
- test(l4): adapt the session container harness to the v4 Quickshell desktop
- test(upgrade): cross-check v4_kept_packages against build-repo.sh's spec set
- test(fedora): P6 upgrade-to-4 L4 verification scenario
- fix(upgrade): never let retired-package removal cascade past the retired set
- test(upgrade): L1 suite for omedora-upgrade-to-4 + CI wiring
- feat(upgrade): omedora-upgrade-to-4 — in-place 3.8.2-line -> omedora 4 upgrader
- test(fedora): P5 update-pipeline verification script
- fix(update+plan): container reboot-prompt hang + the /dev/stdin flake
- fix(install): installed-system path resolution + payload-driven RPM rebuilds
- port(update): Fedora gating for the v4 omarchy-update pipeline
- fix(test): hermetic installed-state for the plan gate's transaction assertion
- fix(test): stub update-desktop-database in the finalize-defaults suite
- fix(install): retire the hyprland-omedora shim on the 4.x line
- fix(install): two L3-smoke-caught bootstrap bugs + the v4 smoke itself
- feat(install): port the Fedora desktop baseline + chromium bridge to the v4 flow
- test: L1 suites for the plan gate, coexistence seeding, and finalize gating
- docs(architecture): record the Omarchy 4 setup-system gating map (§16)
- feat(fedora): coexistence gates for the user finalize/first-run stage
- feat(fedora): gate omarchy-setup-system's scripts for the Fedora path
- feat(install): the omedora fresh-install bootstrap for the Omarchy 4 base
- port: bring omarchy-doctor (foreign-repo conflict scanner) onto the v4 base
- ci: flip the COPR-build trigger to omarchy-4-omedora
- test: L1 audit locking in the etc-overrides never-touch list
- packaging(settings): docker/gnupg configs become reference copies, not /etc payload
- packaging: wire the core specs into build-repo.sh
- packaging: draft the omedora + omedora-settings core RPM specs
- packaging: add self-source mode to the SRPM-gen harness
- test: defer the coexistence seeding suite to the P4 bootstrap port
- port(adopt): omedora-adopt-user — coexistence-safe /etc/skel adoption
- port(map): regenerate fedora.toml against omarchy-4's base package list
- port(pkg): Fedora dispatch shims onto the v4 pkg-helper family
- packaging: default copr-submit.sh to the omarchy-4-omedora branch
- packaging: retire the shell-replaced + NetworkManager-replaced specs for 4.x
- docs(packages): record P1 spike results — quickshell + hyprland-Lua are GO
- ci+docs: P0 workflows for the omarchy-4 line + port-status banner
- port: L1 test scaffold (helpers, mocks, distro + pkg-map tests)
- port: distro detector, Fedora pkg layer, omedora command set, package map
- port: bring the omedora/ tree + .copr/ SRPM flow onto the omarchy-4 base

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
