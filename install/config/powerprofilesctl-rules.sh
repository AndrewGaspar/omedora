# omedora: on Fedora we keep tuned-ppd, which has no power-profiles-daemon unit
# and is already enabled. The udev rules + `systemctl enable power-profiles-
# daemon` below assume p-p-d, so dispatch to a Fedora-aware sibling that drops
# the wrong service dependency and skips the enable. Arch path below unchanged.
case "$(omarchy-distro 2>/dev/null || echo arch)" in
fedora) source "$OMARCHY_INSTALL/config/powerprofilesctl-rules-fedora.sh"; return 0 2>/dev/null || exit 0 ;;
esac

if omarchy-battery-present; then
  cat <<EOF | sudo tee "/etc/udev/rules.d/99-power-profile.rules"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemd-run --no-block --collect --property=After=power-profiles-daemon.service $HOME/.local/share/omarchy/bin/omarchy-powerprofiles-set"
SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="/usr/bin/systemd-run --no-block --collect --property=After=power-profiles-daemon.service $HOME/.local/share/omarchy/bin/omarchy-powerprofiles-set"
EOF

  sudo systemctl enable power-profiles-daemon

  sudo udevadm control --reload 2>/dev/null
  sudo udevadm trigger --subsystem-match=power_supply 2>/dev/null
fi
