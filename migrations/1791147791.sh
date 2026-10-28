echo "Answer ARP only for each interface's own address, so a dock and Wi-Fi on one network keep their routes"

# omedora: skipped on Fedora — omedora-settings ships 90-omarchy-arp.conf only
# as a reference copy (machine-wide network policy), so there is nothing to
# apply.
[[ "$(omarchy-distro)" == "fedora" ]] && exit 0

# Boot applies the shipped file regardless; this applies it now. The kernel
# uses the higher of the "all" value and an interface's own, so "all" covers
# the interfaces that already exist.
sysctl_conf="${OMARCHY_ARP_SYSCTL_CONF:-/etc/sysctl.d/90-omarchy-arp.conf}"

if [[ $(sysctl -n net.ipv4.conf.all.arp_ignore) == "1" && $(sysctl -n net.ipv4.conf.all.arp_announce) == "2" ]]; then
  exit 0
fi

sudo sysctl -p "$sysctl_conf" >/dev/null || omarchy-state set reboot-required
