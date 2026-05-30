#!/bin/bash

# Fedora-only: install the omedora powerprofilesctl shim.
#
# Fedora Workstation ships tuned-ppd, which provides the PowerProfiles D-Bus
# API but not the /usr/bin/powerprofilesctl CLI that Omarchy's power-profile
# features shell out to (omarchy-powerprofiles-{list,set,init}, omarchy-menu).
# omedora keeps tuned-ppd (no daemon swap) and supplies a small bash shim that
# drives the same D-Bus interface.
#
# Install only when the real CLI is absent: on a Fedora box that happens to run
# power-profiles-daemon (which DOES ship /usr/bin/powerprofilesctl), the genuine
# CLI must win, so we don't shadow it. The shim self-guards too (it execs the
# real binary if present), but skipping the install keeps ~/.local/bin clean.

[[ -f /usr/bin/powerprofilesctl ]] && return 0

mkdir -p ~/.local/bin
cp "$OMARCHY_PATH/omedora/bin/powerprofilesctl-shim" ~/.local/bin/powerprofilesctl
chmod +x ~/.local/bin/powerprofilesctl
