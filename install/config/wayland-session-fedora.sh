# Fedora-only: NO-OP (retained for history; no longer wired into install/config/all.sh).
#
# Previously this dropped omedora's wayland-session entry into /usr with a
# `sudo cp` of default/wayland-sessions/omedora.desktop — the ONE /usr write the
# omedora installer made. That entry is now SHIPPED BY A PACKAGE:
# hyprland-omedora (omedora/packaging/copr/hyprland-omedora.spec) owns
# /usr/share/wayland-sessions/omedora.desktop. On Fedora, installing `hyprland`
# remaps to hyprland-omedora (install/packages/fedora.toml), so the session
# entry arrives via dnf, no sudo-cp needed.
#
# The session still launches Hyprland through uwsm (Exec=uwsm start ... --
# Hyprland), which sources ~/.config/uwsm/env -> PATH incl. omarchy/bin.
#
# On Arch the session entry is handled by install/login/sddm.sh (Arch-only),
# which is untouched. This file is intentionally a no-op and is no longer called.
:
