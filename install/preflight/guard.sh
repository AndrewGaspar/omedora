abort() {
  echo -e "\e[31mOmarchy install requires: $1\e[0m"
  echo
  gum confirm "Proceed anyway on your own accord and without assistance?" || exit 1
}

# Fedora arm — Omedora has different guard concerns than Omarchy because we
# don't own the boot stack (no Limine/btrfs requirement, no Plymouth conflict,
# etc.). Early-return after a minimal sanity check; the Arch guards below are
# byte-for-byte upstream. See omedora/architecture.md §7.
if [[ $(omarchy-distro 2>/dev/null) == "fedora" ]]; then
  if (( EUID == 0 )); then
    echo -e "\e[31mOmedora install must run as a regular user (not root)\e[0m" >&2
    exit 1
  fi
  if [[ $(uname -m) != "x86_64" ]]; then
    echo -e "\e[31mOmedora install requires x86_64 (got $(uname -m))\e[0m" >&2
    exit 1
  fi
  if [[ ! -r /etc/os-release ]] || ! grep -q '^ID=fedora' /etc/os-release; then
    echo -e "\e[31mOmedora install requires Fedora (no /etc/os-release ID=fedora)\e[0m" >&2
    exit 1
  fi
  echo "Fedora guards: OK"
  # Return if sourced (the normal install.sh path); exit if executed directly
  # (test runs via `bash guard.sh`).
  return 0 2>/dev/null || exit 0
fi

# Must be an Arch distro
if [[ ! -f /etc/arch-release ]]; then
  abort "Vanilla Arch"
fi

# Must not be an Arch derivative distro
for marker in /etc/cachyos-release /etc/eos-release /etc/garuda-release /etc/manjaro-release; do
  if [[ -f $marker ]]; then
    abort "Vanilla Arch"
  fi
done

# Must not be running as root
if (( EUID == 0 )); then
  abort "Running as root (not user)"
fi

# Must be x86 only to fully work
if [[ $(uname -m) != "x86_64" ]]; then
  abort "x86_64 CPU"
fi

# Must have secure boot disabled
if bootctl status 2>/dev/null | grep -q 'Secure Boot: enabled'; then
  abort "Secure Boot disabled"
fi

# Must not have Gnome or KDE already install
if pacman -Qe gnome-shell &>/dev/null || pacman -Qe plasma-desktop &>/dev/null; then
  abort "Fresh + Vanilla Arch"
fi

# Must have limine installed
command -v limine &>/dev/null || abort "Limine bootloader"

# Must have btrfs root filesystem
[[ $(findmnt -n -o FSTYPE /) = "btrfs" ]] || abort "Btrfs root filesystem" 

# Cleared all guards
echo "Guards: OK"
