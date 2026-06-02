# Set links for Nautilus action icons (Arch-only on omedora: privileged write to
# the system Yaru icon theme, whose path may not exist on Fedora. See
# omedora/architecture.md).
if [[ $(omarchy-distro 2>/dev/null || echo arch) == "arch" ]]; then
sudo ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-previous-symbolic.svg /usr/share/icons/Yaru/scalable/actions/go-previous-symbolic.svg
sudo ln -snf /usr/share/icons/Adwaita/symbolic/actions/go-next-symbolic.svg /usr/share/icons/Yaru/scalable/actions/go-next-symbolic.svg
fi

# Setup user theme folder
mkdir -p ~/.config/omarchy/themes

# Chromium policy directory for theme. omarchy-theme-set-browser writes color.json
# here as the user, hence the world-writable a+rw on Arch. On Fedora keep the
# theme-follow feature but avoid a world-writable dir under /etc — create it owned
# by the user instead (re-tightens any a+rw dir a prior migration left behind).
if [[ $(omarchy-distro 2>/dev/null || echo arch) == "fedora" ]]; then
  sudo install -d -o "$USER" -m 755 /etc/chromium/policies/managed
else
  sudo mkdir -p /etc/chromium/policies/managed
  sudo chmod a+rw /etc/chromium/policies/managed
fi

# Set initial theme
omarchy-theme-set "Tokyo Night"
rm -rf ~/.config/chromium/SingletonLock # otherwise archiso will own the chromium singleton

# Set specific app links for current theme
mkdir -p ~/.config/btop/themes
ln -snf ~/.config/omarchy/current/theme/btop.theme ~/.config/btop/themes/current.theme

mkdir -p ~/.config/mako
ln -snf ~/.config/omarchy/current/theme/mako.ini ~/.config/mako/config

# Default Chromium to follow system appearance ("device") instead of dark.
# /usr/lib/chromium/ is the Arch path; on Fedora chromium reads its initial
# preferences from a different location. Guard so the install doesn't fail
# when the path is missing; Fedora users get chromium's defaults instead.
if [[ -d /usr/lib/chromium ]]; then
  echo '{"browser":{"theme":{"color_scheme":0,"color_scheme2":0}}}' | sudo tee /usr/lib/chromium/initial_preferences >/dev/null
fi
