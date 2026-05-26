# Enable the Fedora-side repos omedora needs:
#   - RPM Fusion (free + nonfree) for codecs and nonfree libs
#   - The lionheartp/Hyprland COPR (only if Hyprland isn't already in main repos)
#   - The Flathub remote (idempotent)
#
# This script is only sourced from install/preflight/all.sh on Fedora hosts.
# Safe to re-run; every operation is idempotent.
#
# Documented in omedora/architecture.md §5.

FEDORA_VERSION="$(. /etc/os-release && echo "$VERSION_ID")"

echo -e "\n\e[32mFedora preflight: enabling third-party repos\e[0m"

# --- RPM Fusion (free + nonfree) ------------------------------------------

if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
  sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm"
fi

if ! rpm -q rpmfusion-nonfree-release >/dev/null 2>&1; then
  sudo dnf install -y \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"
fi

# --- Hyprland COPR ---------------------------------------------------------
# Only enable if Hyprland isn't already in Fedora main repos. This lets the
# COPR usage drop off gracefully when Fedora absorbs Hyprland upstream.

if ! dnf --disablerepo='_copr_*' list available hyprland >/dev/null 2>&1; then
  echo "Hyprland not in Fedora main repos for this release — enabling lionheartp/Hyprland COPR"
  sudo dnf copr enable -y lionheartp/Hyprland
else
  echo "Hyprland already in Fedora main repos — skipping COPR enable"
fi

# --- Flathub remote --------------------------------------------------------

if ! flatpak remotes --user 2>/dev/null | grep -q '^flathub'; then
  flatpak remote-add --if-not-exists --user flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
fi

echo -e "\e[32mFedora preflight repos ready\e[0m"
