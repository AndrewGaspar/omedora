#!/bin/bash

# Omedora Fedora bootstrap — the curl-able installer entry point.
#
#   curl -fsSL https://omedora.org/boot.sh | bash      # (or the raw GitHub URL)
#
# This is the Fedora counterpart of the Arch-only top-level boot.sh (which is
# pacman/mirror based and left byte-identical to upstream). It installs the
# bootstrap prerequisites with dnf, clones omedora into the path the installer
# hardcodes (~/.local/share/omarchy), and runs install.sh.
#
# CHANNELS (set OMEDORA_REF):
#   stable  (default)  the repository's DEFAULT branch — the maintainer keeps
#                      that pointed at the current stable release line, and
#                      `omedora-release` cuts annotated vX.Y.Z tags on it, so a
#                      fresh install lands on stable and update detection
#                      (omarchy-update-available) compares those tags.
#   dev                the dev branch (latest, unstable).
#   rc                 the rc branch (release candidates), if present.
#   <branch|tag>       any explicit git ref.
#
# The omedora COPR that serves the RPMs is resolved later by bin/omedora-copr
# (version-scoped per Omarchy base) — nothing version-specific is hard-coded here.

set -e

REPO="${OMEDORA_REPO:-AndrewGaspar/omedora}"
REF="${OMEDORA_REF:-stable}"
DEST="$HOME/.local/share/omarchy"

echo -e "\n\e[32mOmedora bootstrap\e[0m (repo: $REPO, channel: $REF)\n"

if [[ ! -r /etc/os-release ]] || ! grep -q '^ID=fedora' /etc/os-release; then
  echo -e "\e[31mThis bootstrap is for Fedora. On Arch, use the top-level boot.sh.\e[0m" >&2
  exit 1
fi

# Bootstrap prerequisites: git to clone, gum for the installer's styled prompts,
# dnf-plugins-core for `dnf copr` (the preflight enables the omedora COPR).
sudo dnf install -y git gum dnf-plugins-core

rm -rf "$DEST"
if [[ $REF == "stable" ]]; then
  echo -e "Cloning omedora (stable = default branch) ...\n"
  git clone "https://github.com/${REPO}.git" "$DEST" >/dev/null
else
  echo -e "Cloning omedora ($REF) ...\n"
  git clone --branch "$REF" "https://github.com/${REPO}.git" "$DEST" >/dev/null
fi

echo -e "\nInstallation starting...\n"
bash "$DEST/install.sh"
