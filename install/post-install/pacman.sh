# omedora: Arch-only (pacman.conf/mirrorlist restore + the cups pacnew dance
# have no Fedora analogue; cups-browsed.conf is on omedora's never-touch list).
# The body below is byte-identical to upstream. See omedora/architecture.md
# §"Omarchy 4 setup-system gating map".
if [[ "${OMARCHY_DISTRO:-$(omarchy-distro 2>/dev/null || echo arch)}" != "arch" ]]; then
  return 0 2>/dev/null || exit 0
fi

# Configure pacman after package installation completes. Offline target package
# installs use the live ISO's offline pacman.conf until this final restore.
cp -f "$OMARCHY_PATH/default/pacman/pacman-${OMARCHY_MIRROR:-stable}.conf" /etc/pacman.conf
cp -f "$OMARCHY_PATH/default/pacman/mirrorlist-${OMARCHY_MIRROR:-stable}" /etc/pacman.d/mirrorlist

# Wait for CUPS to own the file, the way omarchy-settings does, so pacman does
# not turn the override into a .pacnew during ISO package installation.
if [[ -f $OMARCHY_PATH/etc-overrides/cups-cups-files.conf && -f /etc/cups/cups-files.conf ]]; then
  install -m 0640 -o root -g cups "$OMARCHY_PATH/etc-overrides/cups-cups-files.conf" /etc/cups/cups-files.conf
  rm -f /etc/cups/cups-files.conf.pacnew
fi

source "$OMARCHY_INSTALL/hardware/pacman.sh"
