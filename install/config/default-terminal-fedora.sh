#!/bin/bash

# Fedora-only: install and set the default terminal.
#
# omarchy's session launches the terminal via `xdg-terminal-exec`, which reads
# ~/.config/xdg-terminals.list to pick one. On Arch the terminal (alacritty)
# arrives through the omarchy-base metapackage, so upstream never sets it
# explicitly during install. On Fedora nothing pulls it in, so Super+Return
# (and the screensaver, TUIs, etc.) silently do nothing.
#
# omarchy-install-terminal does the whole job cross-distro: omarchy-pkg-add
# (→ dnf install alacritty on Fedora), drops the Alacritty.desktop entry, and
# writes xdg-terminals.list. Reuse it rather than re-implementing.

omarchy-install-terminal alacritty
