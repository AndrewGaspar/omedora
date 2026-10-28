echo "Enable Dell XPS 13 sidecar speaker amplifiers"

# omedora: skipped on Fedora — the amplifier setup installs an Arch package and
# rebuilds the boot image; boot/initramfs are Fedora's (omedora/AGENTS.md §6).
[[ "$(omarchy-distro)" == "fedora" ]] && exit 0

if omarchy-hw-dell-xps13-sidecar-amps; then
  source "$OMARCHY_PATH/install/hardware/dell-xps13-sidecar-amps.sh"
  omarchy-state set reboot-required
fi
