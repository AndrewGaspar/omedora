echo "Create managed policy directories for Chromium and Brave for theme switching"

# On Fedora create these owned by the user (mode 755) rather than world-writable,
# so a managed box never gets an a+rw dir under /etc; the theme-follow feature
# (omarchy-theme-set-browser writes color.json as the user) still works. Arch path
# unchanged. See omedora/architecture.md.
if [[ $(omarchy-distro 2>/dev/null || echo arch) == "fedora" ]]; then
  sudo install -d -o "$USER" -m 755 /etc/chromium/policies/managed
  sudo install -d -o "$USER" -m 755 /etc/brave/policies/managed
else
  sudo mkdir -p /etc/chromium/policies/managed
  sudo chmod a+rw /etc/chromium/policies/managed

  sudo mkdir -p /etc/brave/policies/managed
  sudo chmod a+rw /etc/brave/policies/managed
fi
