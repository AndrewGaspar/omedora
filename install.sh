#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -eEo pipefail

# Define Omarchy locations
export OMARCHY_PATH="$HOME/.local/share/omarchy"
export OMARCHY_INSTALL="$OMARCHY_PATH/install"
export OMARCHY_INSTALL_LOG_FILE="/var/log/omarchy-install.log"
export PATH="$OMARCHY_PATH/bin:$PATH"

# Install
source "$OMARCHY_INSTALL/helpers/all.sh"
source "$OMARCHY_INSTALL/preflight/all.sh"
source "$OMARCHY_INSTALL/packaging/all.sh"
source "$OMARCHY_INSTALL/config/all.sh"
# login/ and post-install/ are Arch-only — they own the boot stack
# (Plymouth, SDDM, Limine+Snapper, final pacman config). Omedora doesn't
# own the boot stack on Fedora; see omedora/architecture.md §6 and §14.
if [[ $(omarchy-distro 2>/dev/null || echo arch) == "arch" ]]; then
  source "$OMARCHY_INSTALL/login/all.sh"
  source "$OMARCHY_INSTALL/post-install/all.sh"
fi
