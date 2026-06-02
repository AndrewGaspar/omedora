# Arch-only on omedora: the reboot grant this removes is written by
# install/post-install/allow-reboot.sh, which only runs on Arch. On Fedora the
# file never exists and the bare `sudo test` would hang on a password prompt in
# this TTY-less GUI session. See omedora/architecture.md.
[[ $(omarchy-distro 2>/dev/null || echo arch) == "arch" ]] || exit 0

if sudo test -f /etc/sudoers.d/99-omarchy-installer-reboot; then
  sudo rm -f /etc/sudoers.d/99-omarchy-installer-reboot
fi
