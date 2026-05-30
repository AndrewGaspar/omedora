#!/bin/bash

# Fedora-aware variant of powerprofilesctl-rules.sh.
#
# Mirrors the upstream udev rules (auto-switch the power profile on AC
# plug/unplug by invoking omarchy-powerprofiles-set, which on Fedora resolves
# to the omedora powerprofilesctl shim driving tuned-ppd's D-Bus API), with two
# tuned-ppd adjustments:
#
#   1. The systemd-run ordering property `After=power-profiles-daemon.service`
#      names a unit that does not exist under tuned-ppd. Order against
#      tuned-ppd.service (the daemon that actually owns the PowerProfiles D-Bus
#      API on Fedora) instead.
#   2. `systemctl enable power-profiles-daemon` is skipped unless that unit
#      actually exists — on tuned-ppd it doesn't, and tuned-ppd ships enabled.
#
# NOTE: this script writes to /etc/ and runs sudo, so per omedora policy
# (system-admin = Arch-only on Fedora; see omedora/architecture.md §6/§14) it is
# NOT wired into the Fedora install path. It exists so the upstream
# powerprofilesctl-rules.sh remains correct if ever invoked on a tuned-ppd
# system (e.g. by a user running it manually).

if omarchy-battery-present; then
  # Order against whichever PowerProfiles daemon is present.
  if systemctl list-unit-files power-profiles-daemon.service >/dev/null 2>&1; then
    ppd_after="power-profiles-daemon.service"
  else
    ppd_after="tuned-ppd.service"
  fi

  cat <<EOF | sudo tee "/etc/udev/rules.d/99-power-profile.rules"
SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile --property=After=$ppd_after $HOME/.local/share/omarchy/bin/omarchy-powerprofiles-set"
SUBSYSTEM=="power_supply", ATTR{type}=="USB", RUN+="/usr/bin/systemd-run --no-block --collect --unit=omarchy-power-profile --property=After=$ppd_after $HOME/.local/share/omarchy/bin/omarchy-powerprofiles-set"
EOF

  # power-profiles-daemon ships disabled and must be enabled; tuned-ppd ships
  # enabled and has no such unit. Only enable when the unit exists.
  if systemctl list-unit-files power-profiles-daemon.service >/dev/null 2>&1; then
    sudo systemctl enable power-profiles-daemon
  fi

  sudo udevadm control --reload 2>/dev/null
  sudo udevadm trigger --subsystem-match=power_supply 2>/dev/null
fi
