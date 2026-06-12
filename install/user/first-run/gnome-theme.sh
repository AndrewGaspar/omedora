# omedora: Arch-only. These fixed dark hardcodes are redundant on Fedora: the
# theme system (omarchy-theme-set -> omarchy-theme-set-gnome) already drives
# color-scheme/gtk-theme/icon-theme from the active theme — at install
# (install/user/theme.sh) and on every later switch — so a hardcode here would
# just be re-decided by the next theme change, and it would clobber the GNOME
# appearance of a user who keeps GNOME alongside Omedora. Same decision as the
# 3.8.2 branch. The Arch path below is byte-identical to upstream.
if [[ "${OMARCHY_DISTRO:-$(omarchy-distro 2>/dev/null || echo arch)}" != "arch" ]]; then
  exit 0
fi

gsettings set org.gnome.desktop.interface gtk-theme "Adwaita-dark"
gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
gsettings set org.gnome.desktop.interface icon-theme "Yaru-blue"
