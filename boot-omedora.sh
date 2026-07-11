#!/bin/bash

# Omedora bootstrap shim.
#
# Usage: bash <(curl -fsSL https://raw.githubusercontent.com/AndrewGaspar/omedora/omedora-3/boot-omedora.sh)
#
# Sets OMARCHY_BRAND and OMARCHY_REPO so that boot.sh clones omedora instead
# of upstream Omarchy and prints the Omedora wordmark banner.  The logo is
# inlined here because boot.sh displays the banner *before* cloning the repo.

export OMARCHY_BRAND=omedora
export OMARCHY_REPO="${OMARCHY_REPO:-AndrewGaspar/omedora}"

# Omedora wordmark — byte-for-byte copy of omedora/branding/logo.txt.
# This is intentionally inlined: the repo has not been cloned yet when the
# banner is printed.
export ANSI_ART_OMEDORA='                 ▄▄▄
 ▄█████▄    ▄███████████▄    ▄███████  ████████▄   ▄█████▄    ▄███████   ▄███████
███   ███  ███   ███   ███  ███        ███   ███  ███   ███  ███   ███  ███   ███
███   ███  ███   ███   ███  ███        ███   ███  ███   ███  ███   ███  ███   ███
███   ███  ███   ███   ███  ▄███▄▄▄    ███   ███  ███   ███  ███▄▄▄██▀ ▄███▄▄▄███
███   ███  ███   ███   ███  ▀███▀▀▀    ███   ███  ███   ███  ███▀▀▀▀   ▀███▀▀▀███
███   ███  ███   ███   ███  ███        ███   ███  ███   ███  █████████  ███   ███
███   ███  ███   ███   ███  ███        ███   ███  ███   ███  ███   ███  ███   ███
 ▀█████▀    ▀█   ███   █▀    ████████  ████████▀   ▀█████▀   ███   ███  ███   █▀
                                                             ███   █▀'

# Delegate to boot.sh in the same directory (local dev) or download it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/boot.sh" ]]; then
  source "$SCRIPT_DIR/boot.sh"
else
  source <(curl -fsSL "https://raw.githubusercontent.com/${OMARCHY_REPO}/${OMARCHY_REF:-omedora-3}/boot.sh")
fi
