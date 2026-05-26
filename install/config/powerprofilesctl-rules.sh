if omarchy-battery-present; then
  cat <<EOF | sudo tee "/etc/udev/rules.d/99-power-profile.rules"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile --property=After=power-profiles-daemon.service $HOME/.local/share/omarchy/bin/omarchy-powerprofiles-set"
SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile --property=After=power-profiles-daemon.service $HOME/.local/share/omarchy/bin/omarchy-powerprofiles-set"
EOF

  sudo systemctl enable power-profiles-daemon

  # udevadm fails when systemd-udevd isn't running (e.g., unprivileged
  # containers). The .rules file is what matters; on-disk rules apply at
  # next udev start. Tolerate the failure so set -e doesn't abort install.
  sudo udevadm control --reload 2>/dev/null || true
  sudo udevadm trigger --subsystem-match=power_supply 2>/dev/null || true
fi
