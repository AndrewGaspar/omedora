#!/bin/bash

# Omedora Fedora bootstrap — the curl-able installer entry point.
#
#   curl -fsSL https://raw.githubusercontent.com/AndrewGaspar/omedora/omarchy-4-omedora/omedora/boot.sh | bash
#
# Omarchy 4 ships as packages (the omedora/omedora-settings RPMs from the
# omedora COPR own /usr/share/omarchy and /usr/bin/omarchy-*), so this
# bootstrap does NOT install omedora into ~/.local/share. It clones the repo
# shallowly into a cache dir ONLY to get the plan gate + installer scripts —
# the plan gate must run and get your consent BEFORE any package lands — then
# hands off to omedora/install-4.sh, after which the installed
# /usr/share/omarchy payload takes over.
#
# CHANNELS (set OMEDORA_REF): a branch or tag; default omarchy-4-omedora.

set -eEo pipefail

export OMARCHY_BRAND="${OMARCHY_BRAND:-omedora}"
OMEDORA_REPO="${OMEDORA_REPO:-AndrewGaspar/omedora}"
OMEDORA_REF="${OMEDORA_REF:-omarchy-4-omedora}"

# Omedora wordmark — byte-for-byte copy of omedora/branding/logo.txt, inlined
# because the banner prints before the repo is cloned.
ANSI_ART_OMEDORA='                 ▄▄▄
 ▄█████▄    ▄███████████▄    ▄███████  ████████▄   ▄█████▄    ▄███████   ▄███████
███   ███  ███   ███   ███  ███        ███   ███  ███   ███  ███   ███  ███   ███
███   ███  ███   ███   ███  ███        ███   ███  ███   ███  ███   ███  ███   ███
███   ███  ███   ███   ███  ▄███▄▄▄    ███   ███  ███   ███  ███▄▄▄██▀ ▄███▄▄▄███
███   ███  ███   ███   ███  ▀███▀▀▀    ███   ███  ███   ███  ███▀▀▀▀   ▀███▀▀▀███
███   ███  ███   ███   ███  ███        ███   ███  ███   ███  █████████  ███   ███
███   ███  ███   ███   ███  ███        ███   ███  ███   ███  ███   ███  ███   ███
 ▀█████▀    ▀█   ███   █▀    ████████  ████████▀   ▀█████▀   ███   ███  ███   █▀
                                                             ███   █▀'

echo -e "\n\e[32m${ANSI_ART_OMEDORA}\e[0m"
echo -e "\nOmedora bootstrap (repo: $OMEDORA_REPO, ref: $OMEDORA_REF)\n"

# --- guards (ported from 3.8.2 guard.sh's Fedora arm) -------------------------
if (( EUID == 0 )); then
  echo -e "\e[31mOmedora install must run as a regular user (not root)\e[0m" >&2
  exit 1
fi
if [[ ! -r /etc/os-release ]] || ! grep -q '^ID=fedora' /etc/os-release; then
  echo -e "\e[31mThis bootstrap is for Fedora. On Arch, use Omarchy's ISO.\e[0m" >&2
  exit 1
fi
if [[ $(uname -m) != "x86_64" ]]; then
  echo -e "\e[31mOmedora install requires x86_64 (got $(uname -m))\e[0m" >&2
  exit 1
fi
if ! command -v sudo >/dev/null 2>&1; then
  echo -e "\e[31mOmedora install requires sudo\e[0m" >&2
  exit 1
fi
if ! sudo -v; then
  echo -e "\e[31mOmedora install requires working sudo for this user\e[0m" >&2
  exit 1
fi
echo "Fedora guards: OK"

# --- get the installer (local checkout, or a shallow clone to a cache dir) ----
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [[ -n $SCRIPT_DIR && -f "$SCRIPT_DIR/install-4.sh" && -d "$SCRIPT_DIR/../bin" ]]; then
  # Running from a checkout (dev / re-run): use it directly.
  exec bash "$SCRIPT_DIR/install-4.sh"
fi

# Bootstrap prerequisites: git to clone; gum is optional (the plan gate falls
# back to a plain read prompt when it's absent).
command -v git >/dev/null 2>&1 || sudo dnf install -y git

CLONE_DIR="${OMEDORA_BOOT_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/omedora/bootstrap}"
rm -rf "$CLONE_DIR"
mkdir -p "$(dirname "$CLONE_DIR")"
echo -e "Cloning omedora ($OMEDORA_REF) ...\n"
git clone --depth 1 --branch "$OMEDORA_REF" \
  "https://github.com/${OMEDORA_REPO}.git" "$CLONE_DIR"

exec bash "$CLONE_DIR/omedora/install-4.sh"
