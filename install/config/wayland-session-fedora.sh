# Fedora-only: install the Omedora Hyprland session entry into the display
# manager's session list (GDM/SDDM). On Arch this is handled by
# install/login/sddm.sh (Arch-only on omedora). On Fedora we keep the existing
# DM and only drop the .desktop — the wayland-sessions install is the ONE /usr
# write omedora makes (the explicit exception in AGENTS.md §6).
#
# Why it matters: the session MUST launch via uwsm (Exec=uwsm start ...), which
# sources ~/.config/uwsm/env and puts ~/.local/share/omarchy/bin on PATH.
# Without it, omarchy-* commands (autostart, keybinds) and walker launches fail
# with "command not found". The lionheartp/Hyprland COPR also ships a plain
# `hyprland.desktop` (Exec=Hyprland, NO uwsm) that appears as a bare "Hyprland"
# session — picking that one bypasses uwsm and breaks PATH. Users should pick
# "Omedora".

sudo mkdir -p /usr/share/wayland-sessions
sudo cp "$OMARCHY_PATH/default/wayland-sessions/omedora.desktop" \
  /usr/share/wayland-sessions/omedora.desktop
echo "Installed Omedora session entry -> /usr/share/wayland-sessions/omedora.desktop"
