if omarchy-battery-present; then
  cat <<EOF | sudo tee "/etc/udev/rules.d/99-wifi-powersave.rules"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-wifi-powersave-on $HOME/.local/share/omarchy/bin/omarchy-wifi-powersave on"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-wifi-powersave-off $HOME/.local/share/omarchy/bin/omarchy-wifi-powersave off"
EOF

  # udevadm fails when systemd-udevd isn't running (e.g., unprivileged
  # containers). The .rules file is what matters; on-disk rules apply at
  # next udev start. Tolerate the failure so set -e doesn't abort install.
  sudo udevadm control --reload 2>/dev/null || true
  sudo udevadm trigger --subsystem-match=power_supply 2>/dev/null || true
fi
