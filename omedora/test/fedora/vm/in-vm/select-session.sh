#!/bin/bash
#
# L4-VM in-guest: make the Omedora/Hyprland session the one GDM autologin starts,
# then (re)start the graphical seat so it comes up. Runs over SSH as the VM user.
#
# GDM autologin (set in cloud-init's /etc/gdm/custom.conf) logs the user in, but
# WHICH session it starts is the user's AccountsService "Session" preference
# (/var/lib/AccountsService/users/<user>). We pin it to "omedora" so the seat
# boots straight into Hyprland with a real DRM master — the thing containers
# can't give and the whole reason L4-VM exists.

set -uo pipefail
USER_NAME="$(id -un)"

echo "# selecting omedora.desktop as the user's GDM session"

# 1. AccountsService session preference -> omedora (xsession key works for
#    wayland sessions too; GDM reads both Session and XSession).
sudo install -d -m 0775 /var/lib/AccountsService/users
sudo tee "/var/lib/AccountsService/users/$USER_NAME" >/dev/null <<EOF
[User]
Session=omedora
XSession=omedora
SystemAccount=false
EOF

# 2. Belt-and-suspenders: GDM also honours ~/.dmrc on some paths.
cat > "$HOME/.dmrc" <<EOF
[Desktop]
Session=omedora
EOF

# 3. Confirm the session file the greeter would offer actually exists.
if [[ -f /usr/share/wayland-sessions/omedora.desktop ]]; then
  echo "# omedora.desktop present:"
  grep -E '^(Name|Exec)=' /usr/share/wayland-sessions/omedora.desktop | sed 's/^/#   /'
else
  echo "# WARNING: /usr/share/wayland-sessions/omedora.desktop missing — session will not start" >&2
fi

# 4. Make sure the graphical target is default + restart GDM so autologin picks
#    up the new session selection. (If a GNOME session is already running from
#    the first boot, restarting GDM drops it and re-autologins into omedora.)
sudo systemctl set-default graphical.target >/dev/null 2>&1 || true
echo "# restarting gdm to autologin into the omedora session"
sudo systemctl restart gdm.service || {
  echo "# gdm restart failed; trying isolate graphical.target" >&2
  sudo systemctl isolate graphical.target || true
}

echo "# select-session done"
