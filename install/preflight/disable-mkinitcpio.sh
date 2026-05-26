# Temporarily disable mkinitcpio hooks to prevent multiple regenerations during package installation
# This speeds up installation significantly

# Arch-only — Fedora uses dracut, no mkinitcpio hooks to disable
if [[ $(omarchy-distro 2>/dev/null || echo arch) != "arch" ]]; then
  return 0 2>/dev/null || exit 0
fi

echo "Temporarily disabling mkinitcpio hooks during installation..."

# Move the specific mkinitcpio pacman hooks out of the way if they exist
if [[ -f /usr/share/libalpm/hooks/90-mkinitcpio-install.hook ]]; then
  sudo mv /usr/share/libalpm/hooks/90-mkinitcpio-install.hook /usr/share/libalpm/hooks/90-mkinitcpio-install.hook.disabled
fi

if [[ -f /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook ]]; then
  sudo mv /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook /usr/share/libalpm/hooks/60-mkinitcpio-remove.hook.disabled
fi

echo "mkinitcpio hooks disabled"

