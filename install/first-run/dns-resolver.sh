# Arch-only on omedora: Fedora already ships+manages systemd-resolved and
# /etc/resolv.conf; force-clobbering it here is redundant and can break a
# managed box's corporate VPN / split-DNS. See omedora/architecture.md.
[[ $(omarchy-distro 2>/dev/null || echo arch) == "arch" ]] || exit 0

# https://wiki.archlinux.org/title/Systemd-resolved
echo "Symlink resolved stub-resolv to /etc/resolv.conf"

sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
