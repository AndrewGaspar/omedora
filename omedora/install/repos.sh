# Enable the Fedora-side repos omedora needs (everything here was disclosed at
# the plan gate):
#   - the omedora COPR (resolved by bin/omedora-copr — single source of truth)
#   - RPM Fusion (free + nonfree) for codecs and nonfree libs
#   - the Flathub remote (--user scope)
# then apply the foreign-repo package replacement if the user chose "Replace"
# at the gate (OMEDORA_REPLACE_FOREIGN=1 — the swap needs the COPR enabled, so
# it can't run at gate time).
#
# Ported from omedora-3's install/preflight/fedora-repos.sh +
# fedora-swap.sh. Safe to re-run; every operation is idempotent.

FEDORA_VERSION="$(. /etc/os-release && echo "$VERSION_ID")"

echo -e "\n\e[32mOmedora: enabling repos\e[0m"

# --- RPM Fusion (free + nonfree) ---------------------------------------------

if ! rpm -q rpmfusion-free-release >/dev/null 2>&1; then
  sudo dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VERSION}.noarch.rpm"
fi

if ! rpm -q rpmfusion-nonfree-release >/dev/null 2>&1; then
  sudo dnf install -y \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VERSION}.noarch.rpm"
fi

# --- The omedora COPR ----------------------------------------------------------
# Serves the omedora/omedora-settings RPMs plus the vendored Hyprland stack,
# walker/elephant/swayosd, nerd-fonts, TUIs, uwsm... The test harness can
# instead inject a LOCAL repo at /etc/yum.repos.d/omedora-local.repo for
# hermetic, network-free runs; when present, skip the COPR enable.
if [[ ! -f /etc/yum.repos.d/omedora-local.repo ]]; then
  # dnf-plugins-core provides the `copr` subcommand. `copr enable` is idempotent.
  sudo dnf install -y dnf-plugins-core >/dev/null 2>&1 || true
  sudo dnf -y copr enable "$("$OMEDORA_REPO_ROOT/bin/omedora-copr")"
fi

# --- Flathub remote ------------------------------------------------------------

if ! flatpak remotes --user 2>/dev/null | grep -q '^flathub'; then
  flatpak remote-add --if-not-exists --user flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
fi

# --- foreign-repo replacement (consented to at the gate) ------------------------

if [[ -n ${OMEDORA_REPLACE_FOREIGN:-} ]]; then
  echo -e "\e[32mOmedora: replacing foreign-repo Hyprland packages with omedora's builds (you chose Replace)\e[0m"
  "$OMEDORA_REPO_ROOT/bin/omedora-replace-foreign" --yes
fi

echo -e "\e[32mOmedora repos ready\e[0m"
