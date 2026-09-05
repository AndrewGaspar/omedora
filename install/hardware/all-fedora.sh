# Fedora hardware-setup list (dispatched from install/hardware/all.sh's top
# gate; runs as root under omarchy-setup-hardware).
#
# Only the genuinely portable scripts run on Fedora. Everything else in the
# Arch list is excluded because Fedora's own install owns drivers/boot (see
# omedora/architecture.md §8 + §14 and the §"Omarchy 4 setup-system gating
# map" decision table):
#   - kernel modules / DKMS / firmware (nvidia, fix-bcm43xx, fix-tuxedo-
#     backlight, fix-yt6801, apple/fix-spi-keyboard, apple/fix-t2, surface,
#     fix-surface-keyboard): RPM Fusion akmods / t2linux are the user's
#     well-trodden Fedora paths; omedora never reaches into dracut.
#   - kernel cmdline via /etc/limine-entry-tool.d (intel/fred, intel/
#     ptl-kernel, asus/fix-asus-ptl-*): no limine on Fedora.
#   - pacman repo extensions (pacman.sh) and Arch-only packages routed to
#     skip in the map (asus-rog, framework16, dell-xps-touchpad-haptics,
#     vulkan — Fedora ships mesa Vulkan drivers by default).
#   - host policy omedora must not own on a lived-in Fedora box: network.sh
#     (masking systemd-networkd-wait-online), bluetooth.sh (flipping
#     AutoEnable in the user's /etc/bluetooth/main.conf; the service is
#     already enabled on Fedora), set-wireless-regdom.sh (/etc/conf.d is
#     Arch; the file never exists, so it would no-op anyway), intel/* daemons
#     (thermald is enabled by default on Fedora), fix-fkeys.sh +
#     lenovo/fix-yoga-pro7-bass-speakers.sh + intel/fix-wifi7-eht.sh
#     (un-namespaced /etc/modprobe.d writes — module options are left to the
#     user; revisit on demand), apple/fix-suspend-nvme.sh (Mac support on
#     Fedora is t2linux territory).

# input-group.sh retired upstream in v4.0.2 (#9200 closed the unprivileged
# input escalation path; existing installs are trimmed by migration
# 1787865477). Nothing to grant on fresh installs.
run_logged "$OMARCHY_INSTALL/hardware/fix-synaptic-touchpad.sh"
run_logged "$OMARCHY_INSTALL/hardware/framework/qmk-hid.sh"
