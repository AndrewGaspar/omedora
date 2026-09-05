echo "Switch back to the packaged quickshell now that 0.3.1 kills synchronously"

[[ ${OMARCHY_DISTRO:-$(omarchy-distro)} == "fedora" ]] && { return 0 2>/dev/null || exit 0; }

# 0.3.1 fixes `kill` returning before the instance has exited, which is the only
# reason Omarchy shipped the git build.
if omarchy-pkg-present quickshell-git; then
  # One transaction with --ask 4 so pacman accepts replacing the conflicting
  # quickshell-git in place; packages depending on quickshell stay satisfied.
  sudo pacman -S --noconfirm --ask 4 quickshell
fi
