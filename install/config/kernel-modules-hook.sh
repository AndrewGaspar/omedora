# Arch-only — linux-modules-cleanup.service ships with kernel-modules-hook
# (Arch package). Fedora has equivalent kernel-cleanup behavior built in.
if [[ $(omarchy-distro 2>/dev/null || echo arch) != "arch" ]]; then
  return 0 2>/dev/null || exit 0
fi

chrootable_systemctl_enable linux-modules-cleanup.service
