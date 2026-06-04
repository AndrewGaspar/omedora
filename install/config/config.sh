# Fedora dispatch — see omedora/architecture.md §1. On Fedora, omedora installs
# onto a lived-in machine, so seeding must be coexistence-safe (backup-then-write,
# never clobber ~/.bashrc or the user's git config). The Arch body below is
# byte-for-byte unchanged.
if [[ $(omarchy-distro 2>/dev/null || echo arch) == "fedora" ]]; then
  source "$OMARCHY_INSTALL/config/config-fedora.sh"
  return 0 2>/dev/null || exit 0
fi

# Copy over Omarchy configs
mkdir -p ~/.config
cp -R ~/.local/share/omarchy/config/* ~/.config/

# Use default bashrc from Omarchy
cp ~/.local/share/omarchy/default/bashrc ~/.bashrc
