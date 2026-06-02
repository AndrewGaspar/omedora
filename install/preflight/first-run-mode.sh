# Set first-run mode marker so we can install stuff post-installation
mkdir -p ~/.local/state/omarchy
touch ~/.local/state/omarchy/first-run.mode

# Setup sudo-less access for first-run. Arch-only on omedora: the NOPASSWD grant
# exists so Arch's privileged first-run finalizers (ufw firewall, resolv.conf
# symlink) can run in a TTY-less GUI session. On Fedora those finalizers are
# Arch-gated, so first-run needs no sudo at all — and writing here would crash a
# managed box that lacks /etc/sudoers.d. See omedora/architecture.md and
# install/first-run/{dns-resolver,firewall,cleanup-reboot-sudoers}.sh.
if [[ $(omarchy-distro 2>/dev/null || echo arch) == "arch" ]]; then
sudo tee /etc/sudoers.d/first-run >/dev/null <<EOF
Cmnd_Alias FIRST_RUN_CLEANUP = /bin/rm -f /etc/sudoers.d/first-run
Cmnd_Alias SYMLINK_RESOLVED = /usr/bin/ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
$USER ALL=(ALL) NOPASSWD: /usr/bin/systemctl
$USER ALL=(ALL) NOPASSWD: /usr/bin/ufw
$USER ALL=(ALL) NOPASSWD: /usr/bin/ufw-docker
$USER ALL=(ALL) NOPASSWD: /usr/bin/gtk-update-icon-cache
$USER ALL=(ALL) NOPASSWD: SYMLINK_RESOLVED
$USER ALL=(ALL) NOPASSWD: FIRST_RUN_CLEANUP
EOF
sudo chmod 440 /etc/sudoers.d/first-run
fi
