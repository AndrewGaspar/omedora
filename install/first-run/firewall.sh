# Arch-only on omedora: this is pure ufw, which Fedora does not use (firewalld
# is the default and already active; ufw is source=skip). Running it on Fedora
# would also abort first-run with `ufw: command not found`. See
# omedora/architecture.md and install/packages/fedora.toml ([ufw]).
[[ $(omarchy-distro 2>/dev/null || echo arch) == "arch" ]] || exit 0

# Allow nothing in, everything out
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow ports for LocalSend
sudo ufw allow 53317/udp
sudo ufw allow 53317/tcp

# Allow Docker containers to use DNS on host
sudo ufw allow in proto udp from 172.16.0.0/12 to 172.17.0.1 port 53 comment 'allow-docker-dns'
sudo ufw allow in proto udp from 192.168.0.0/16 to 172.17.0.1 port 53 comment 'allow-docker-dns'

# Turn on the firewall
sudo ufw --force enable

# Enable UFW systemd service to start on boot
sudo systemctl enable ufw

# Turn on Docker protections
sudo ufw-docker install
sudo ufw reload
