# Arch-only on omedora. These GNOME interface settings are redundant on Fedora:
# the theme system (omarchy-theme-set -> omarchy-theme-set-gnome) already drives
# color-scheme/gtk-theme/icon-theme from the active theme — at install (via
# config/theme.sh) and on every later theme switch — so a fixed dark hardcode
# here would just be re-decided by the theme on the next change. Let the theme
# system own it on Fedora. On Arch we keep the original behavior byte-identical
# to upstream (incl. the privileged Yaru icon-cache refresh, which Fedora can't
# do TTY-less anyway). See omedora/architecture.md.
if [[ $(omarchy-distro 2>/dev/null || echo arch) == "arch" ]]; then
  gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark"
  gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
  gsettings set org.gnome.desktop.interface icon-theme "Yaru-blue"
  sudo gtk-update-icon-cache /usr/share/icons/Yaru
fi
