# Fedora sibling of install/config/firewall.sh (dispatched from its top gate;
# runs as root under omarchy-setup-system).
#
# Fedora ships firewalld (ufw/ufw-docker are skip-mapped), so this mirrors
# upstream's RULES on firewalld:
#   - allow LocalSend: 53317/udp + 53317/tcp           (= the two `ufw allow`s)
#   - allow Docker containers to reach DNS on the host  (= the rich-rule
#     equivalents of upstream's two allow-docker-dns rules)
#
# What is deliberately NOT mirrored:
#   - "default deny incoming": that's the user's firewalld zone policy
#     (FedoraWorkstation by default). Flipping the default zone target on a
#     lived-in machine is system policy omedora must not own.
#   - ufw-docker's after.rules surgery: with firewalld >= 0.9 + moby 20.10+,
#     docker integrates with firewalld natively via the "docker" zone.
#
# Idempotent: --add-port/--add-rich-rule are no-ops (ALREADY_ENABLED) when the
# rule exists. Uses firewall-cmd when the daemon is live, else
# firewall-offline-cmd (e.g. ISO-less container installs / pre-reboot).

if ! command -v firewall-offline-cmd >/dev/null 2>&1 && ! command -v firewall-cmd >/dev/null 2>&1; then
  echo "firewalld not installed; skipping firewall rules (install firewalld and re-run omarchy-setup-system to apply them)."
  return 0 2>/dev/null || exit 0
fi

fw() {
  if systemctl is-active firewalld >/dev/null 2>&1 && command -v firewall-cmd >/dev/null 2>&1; then
    firewall-cmd --permanent "$@"
  else
    firewall-offline-cmd "$@"
  fi
}

# LocalSend.
fw --add-port=53317/udp
fw --add-port=53317/tcp

# Docker containers -> host DNS (same source/dest ranges as upstream's rules).
fw --add-rich-rule='rule family="ipv4" source address="172.16.0.0/12" destination address="172.17.0.1/32" port port="53" protocol="udp" accept'
fw --add-rich-rule='rule family="ipv4" source address="192.168.0.0/16" destination address="172.17.0.1/32" port port="53" protocol="udp" accept'

# Make the permanent rules live now if the daemon is running; otherwise they
# apply on the next firewalld start (installs are followed by reboot/login).
if systemctl is-active firewalld >/dev/null 2>&1; then
  firewall-cmd --reload >/dev/null 2>&1 || true
fi

# firewalld is enabled by default on Fedora; re-assert only if present+disabled.
state="$(systemctl is-enabled firewalld.service 2>/dev/null || true)"
[[ $state == "disabled" ]] && systemctl enable firewalld.service

return 0 2>/dev/null || exit 0
