# Enable the Fedora-side repos omedora needs:
#   - RPM Fusion (free + nonfree) for codecs and nonfree libs
#   - The Flathub remote (idempotent)
#
# The Hyprland stack is no longer pulled from a third-party COPR: the whole
# hyprwm stack is vendored as omedora RPMs (omedora/packaging/copr/) and served
# from the omedora repo, so there is no COPR to enable here (task #66).
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

# --- Hyprland ---------------------------------------------------------------
# Hyprland and the rest of the hyprwm stack are vendored as omedora RPMs and
# resolved from the omedora repo (see install/packages/fedora.toml). No COPR is
# enabled here anymore — the lionheartp/Hyprland COPR was retired in task #66.

# --- Flathub remote --------------------------------------------------------

if ! flatpak remotes --user 2>/dev/null | grep -q '^flathub'; then
  flatpak remote-add --if-not-exists --user flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
fi

echo -e "\e[32mFedora preflight repos ready\e[0m"
