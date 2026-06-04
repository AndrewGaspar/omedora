# hyprland-omedora.spec — omedora's Hyprland wayland-session entry (omedora).
#
# A tiny noarch package that ships ONLY the omedora wayland-session entry:
#   /usr/share/wayland-sessions/omedora.desktop
# whose Exec drives Hyprland directly through uwsm (no resolver .desktop):
#   uwsm start -g -1 -e -N Hyprland -D Hyprland -- start-hyprland
# -N/-D supply the session metadata a .desktop would otherwise provide. We run
# `start-hyprland` (the upstream watchdog launcher that supervises Hyprland and
# passes --watchdog-fd) rather than the bare `Hyprland` binary, which would emit
# a "started without start-hyprland" warning — this matches what upstream's plain
# hyprland.desktop (Exec=/usr/bin/start-hyprland) does.
#
# Background: omedora's session used to be dropped into /usr by a Fedora-gated
# `sudo cp` in install/config/wayland-session-fedora.sh (the one /usr write the
# omedora installer made). It is now owned by this package instead. Installing
# `hyprland` on Fedora remaps (install/packages/fedora.toml) to hyprland-omedora,
# which pulls the compositor (hyprland-no-session) + uwsm transitively, so the
# whole session stack lands without the visible plain/uwsm session entries.
#
# The session entry MUST launch via uwsm: uwsm sources ~/.config/uwsm/env and
# puts ~/.local/share/omarchy/bin on PATH. Without it omarchy-* commands
# (autostart, keybinds) and walker launches fail with "command not found".
#
# Source0 is a LOCAL file (omedora.desktop, staged alongside this spec — a copy
# of the repo's default/wayland-sessions/omedora.desktop, the source of truth),
# handled exactly like hyprland.spec's local macros.hyprland Source:
# build-local.sh / .copr/srpm.sh copy bare-filename Sources in by hand (spectool
# only fetches URLs), and a COPR uploads them alongside the spec.

Name:           hyprland-omedora
Version:        1.0.0
Release:        1%{?dist}
Summary:        Omedora Hyprland wayland-session entry (uwsm-launched)

# The shipped omedora.desktop is omedora's own trivial session entry.
License:        MIT
URL:            https://github.com/omedora/omedora
# Local Source: omedora's wayland-session entry (copy of the repo's
# default/wayland-sessions/omedora.desktop). Bare filename — not a URL — so
# build-local.sh/.copr stage it from the sibling file (like macros.hyprland).
Source0:        omedora.desktop

BuildArch:      noarch
BuildRequires:  desktop-file-utils

# The compositor binaries (no session entry of their own) + the session manager
# omedora launches through. Pulling hyprland-omedora pulls the whole stack.
Requires:       hyprland-no-session
Requires:       uwsm

%description
The omedora Hyprland wayland-session entry. Ships a single
wayland-sessions/omedora.desktop whose Exec launches the Hyprland compositor
binary directly through uwsm (which sources ~/.config/uwsm/env and puts
omarchy's bin dir on PATH). Pulls in the Hyprland compositor binaries
(hyprland-no-session) and uwsm.

%prep
# Nothing to unpack — Source0 is the .desktop file itself.

%build
# Nothing to build (noarch data-only package).

%install
install -Dpm644 %{SOURCE0} \
  %{buildroot}%{_datadir}/wayland-sessions/omedora.desktop

%check
desktop-file-validate %{buildroot}%{_datadir}/wayland-sessions/omedora.desktop

%files
%{_datadir}/wayland-sessions/omedora.desktop

%changelog
* Tue Jun 03 2026 omedora <noreply@omedora> - 1.0.0-1
- Initial package: ship omedora's wayland-session entry as an RPM (previously a
  Fedora-gated `sudo cp` in install/config/wayland-session-fedora.sh).
- Exec drives Hyprland directly via uwsm (-- start-hyprland, the watchdog
  launcher; -N/-D session metadata; no resolver .desktop). Requires
  hyprland-no-session + uwsm.
