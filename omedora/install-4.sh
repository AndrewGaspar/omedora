#!/bin/bash

# Omedora fresh-install orchestrator for the Omarchy 4 (package-backed) base.
#
# Run via omedora/boot.sh (the curl-able bootstrap), or directly from a
# checkout: bash omedora/install-4.sh
#
# Upstream Omarchy 4 has no install.sh — fresh installs are ISO-built on Arch.
# On Fedora, omedora installs onto an EXISTING Fedora system instead, so this
# orchestrator does what the ISO does (packages -> setup-system ->
# provision-user) but coexistence-first: one up-front plan gate before any
# change, backup-then-write for user configs, only-if-unset for defaults.
#
# Sequence (each step an omedora-owned script in omedora/install/):
#   1. plan.sh      aggregate + disclose EVERYTHING, Proceed/Abort gate
#   2. snapshot.sh  opt-in pre-install btrfs snapshot
#   3. repos.sh     omedora COPR + RPM Fusion + Flathub (+ consented foreign swap)
#   4. packages.sh  dnf install omedora, then the mapped omarchy-base set
#   5. system.sh    sudo omarchy apply system (Fedora-gated upstream scripts)
#   6. adopt.sh     omedora-adopt-user (skel replay, backup-then-write)
#   7. finalize.sh  omarchy-provision-user --force --first-install
#   8. first-run.sh omarchy-provision-first-run, only with a live user bus
#
# Env:
#   OMEDORA_PLAN_AUTOCONFIRM=1  proceed past the gate without prompting (CI)
#   OMEDORA_SETUP_FROM_REPO=1   run setup/finalize from this checkout instead
#                               of the installed /usr/share/omarchy (dev/test)
#   plus the plan.sh seams documented there.

set -eEo pipefail

export OMEDORA_REPO_ROOT="${OMEDORA_REPO_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)}"
export OMARCHY_BRAND="${OMARCHY_BRAND:-omedora}"
export PATH="$OMEDORA_REPO_ROOT/bin:$PATH"

# --- guards (also enforced by boot.sh; cheap to re-check for direct runs) ----
if (( EUID == 0 )); then
  echo -e "\e[31mOmedora install must run as a regular user (not root)\e[0m" >&2
  exit 1
fi
if [[ ! -r /etc/os-release ]] || ! grep -q '^ID=fedora' /etc/os-release; then
  echo -e "\e[31mOmedora install requires Fedora (no /etc/os-release ID=fedora)\e[0m" >&2
  exit 1
fi
if [[ $(uname -m) != "x86_64" ]]; then
  echo -e "\e[31mOmedora install requires x86_64 (got $(uname -m))\e[0m" >&2
  exit 1
fi
# sudo guard, tty-aware: on an interactive terminal `sudo -v` prompts once and
# caches; without a tty (CI containers) it can't prompt — and Fedora's stock
# passworded %wheel rule makes `sudo -v` DEMAND a password even when a NOPASSWD
# rule also matches (verifypw=all), so probe with `sudo -n true` instead.
sudo_ok() {
  command -v sudo >/dev/null 2>&1 || return 1
  if [[ -t 0 ]]; then sudo -v; else sudo -n true; fi
}
if ! sudo_ok; then
  echo -e "\e[31mOmedora install requires working sudo for this user\e[0m" >&2
  exit 1
fi

trap 'echo -e "\n\e[31mOmedora install failed (see output above). Re-running the installer is safe: every step is idempotent and user files are only ever backed up, never deleted.\e[0m" >&2' ERR

source "$OMEDORA_REPO_ROOT/omedora/install/plan.sh"
source "$OMEDORA_REPO_ROOT/omedora/install/snapshot.sh"
source "$OMEDORA_REPO_ROOT/omedora/install/repos.sh"
source "$OMEDORA_REPO_ROOT/omedora/install/packages.sh"
source "$OMEDORA_REPO_ROOT/omedora/install/system.sh"
source "$OMEDORA_REPO_ROOT/omedora/install/adopt.sh"
source "$OMEDORA_REPO_ROOT/omedora/install/finalize.sh"
source "$OMEDORA_REPO_ROOT/omedora/install/first-run.sh"

echo
echo -e "\e[32mOmedora install complete.\e[0m"
echo "Log out and pick the \"Omedora\" session at the GDM login screen."
