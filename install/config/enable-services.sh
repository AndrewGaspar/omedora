# omedora: Fedora dispatches to the enable-services-fedora.sh sibling (only
# enables what omedora installed and what isn't already on; never touches the
# display manager or power daemon). The Arch body below is byte-identical to
# upstream. See omedora/architecture.md §"Omarchy 4 setup-system gating map".
if [[ "${OMARCHY_DISTRO:-$(omarchy-distro 2>/dev/null || echo arch)}" == "fedora" ]]; then
  source "${BASH_SOURCE[0]%/*}/enable-services-fedora.sh"
  return 0 2>/dev/null || exit 0
fi

# Enable services only. Installs are followed by reboot, so don't start/reload
# daemons mid-install. UFW and hardware-gated services stay in their own scripts.
systemctl enable cups.service
systemctl enable cups-browsed.service
systemctl enable avahi-daemon.service
systemctl enable linux-modules-cleanup.service
systemctl enable docker.socket
systemctl enable systemd-resolved.service
systemctl enable NetworkManager.service
# Don't let network-online.target (pulled in by cups-browsed) hold up
# graphical.target waiting for DHCP/Wi-Fi association. Nothing in the session
# needs to block on the network. Mirrors the systemd-networkd-wait-online mask
# in install/hardware/network.sh.
systemctl mask NetworkManager-wait-online.service
systemctl enable power-profiles-daemon.service
systemctl enable sddm.service
# Kill one runaway app scope instead of letting reclaim thrashing take the
# whole session down. [Install] pulls in systemd-oomd.socket via Also=, which
# is what the user manager reports app.slice candidacy over.
systemctl enable systemd-oomd.service
