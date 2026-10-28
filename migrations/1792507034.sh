echo "Check network connectivity against ping.omacom.io"

# omedora: skipped on Fedora — the ping.omacom.io connectivity drop-in isn't
# shipped on Fedora (NetworkManager keeps Fedora's own check), so there is
# nothing to reload.
[[ "$(omarchy-distro)" == "fedora" ]] && exit 0

as_root() {
  if (( EUID == 0 )); then
    "$@"
  else
    sudo "$@"
  fi
}

# omarchy-settings ships the drop-in; a running NetworkManager only reads it on
# reload. A failed reload fails the migration so it stays pending.
if systemctl is-active --quiet NetworkManager; then
  as_root nmcli general reload conf
fi
