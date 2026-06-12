#!/bin/bash

# Fedora-only: install the omedora powerprofilesctl shim into ~/.local/bin.
#
# Fedora Workstation ships tuned-ppd, which provides the PowerProfiles D-Bus
# API but NOT the /usr/bin/powerprofilesctl CLI that Omarchy's power-profile
# features shell out to (omarchy-powerprofiles-{list,set,init}, the power panel,
# omarchy-menu). omedora keeps tuned-ppd (no daemon swap — power-profiles-daemon
# Conflicts with it) and supplies a small bash shim that drives the same D-Bus
# interface. See install/packages/fedora.toml [power-profiles-daemon].
#
# Runs as the user during finalize (writes ~/.local/bin, which is on PATH via
# default/bash/envs + the Hyprland session env). Install only when the real CLI
# is absent: on a Fedora box that happens to run power-profiles-daemon (which
# DOES ship /usr/bin/powerprofilesctl), the genuine CLI must win, so we don't
# shadow it. The shim self-guards too (it execs the real binary if present), but
# skipping the install keeps ~/.local/bin clean. Idempotent.

# Don't shadow a genuine powerprofilesctl (e.g. on a box running
# power-profiles-daemon). $OMEDORA_REAL_PPCTL is a test seam.
[[ -f "${OMEDORA_REAL_PPCTL:-/usr/bin/powerprofilesctl}" ]] && return 0

shim="$OMARCHY_PATH/omedora/bin/powerprofilesctl-shim"
[[ -f $shim ]] || return 0

mkdir -p ~/.local/bin
install -m 0755 "$shim" ~/.local/bin/powerprofilesctl
