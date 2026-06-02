gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark"
gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
gsettings set org.gnome.desktop.interface icon-theme "Yaru-blue"

# Arch-only on omedora: keep the unprivileged gsettings above on both distros,
# but the system icon-cache refresh is a privileged write Fedora doesn't need
# (and would require sudo in a TTY-less first-run session). See
# omedora/architecture.md.
if [[ $(omarchy-distro 2>/dev/null || echo arch) == "arch" ]]; then
  sudo gtk-update-icon-cache /usr/share/icons/Yaru
fi
