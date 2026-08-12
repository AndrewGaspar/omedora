echo "Switch to the Omarchy quickshell-git build so shell restarts wait for instance exit"

# Omedora ships its Fedora Quickshell build from the omedora-4 COPR; the Arch
# replacement transaction below is neither available nor needed on Fedora.
[[ "$(omarchy-distro)" == "fedora" ]] && exit 0

if ! omarchy-pkg-present quickshell-git; then
  # One transaction with --ask 4 so pacman accepts replacing the conflicting
  # quickshell package in place; packages depending on quickshell stay
  # satisfied through the provides.
  sudo pacman -S --noconfirm --ask 4 quickshell-git
fi
