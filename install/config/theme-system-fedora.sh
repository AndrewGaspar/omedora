# Fedora sibling of install/config/theme-system.sh (dispatched from its top
# gate; runs as root under omarchy-setup-system).
#
# Differences from the Arch body, per omedora/architecture.md:
#   - No Yaru symlink surgery: Arch-only decision carried over from 3.8.2
#     (Fedora's yaru-theme package lays out its own icon tree; we don't patch
#     another package's files).
#   - The Chromium theme-follow policy dir IS created (it backs a real feature:
#     omarchy-theme-set-browser writes policy JSON there as the user), but
#     owned by the install user with mode 755 instead of world-writable a+rw.
#   - No /usr/lib/chromium/initial_preferences: that's the Arch chromium
#     binary's path. TODO(P4-review): Fedora's chromium reads initial prefs
#     from /usr/lib64/chromium-browser/ — decide whether to seed the
#     follow-system-appearance default there too.

mkdir -p /etc/chromium/policies/managed
chmod 755 /etc/chromium/policies/managed
if [[ -n ${OMARCHY_INSTALL_USER:-} ]]; then
  chown "$OMARCHY_INSTALL_USER" /etc/chromium/policies/managed
fi
