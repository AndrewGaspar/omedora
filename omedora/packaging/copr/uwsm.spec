# Adapted from solopasha/hyprlandRPM (uwsm/uwsm.spec) — the spec set the
# lionheartp/Hyprland COPR forked. uwsm (Universal Wayland Session Manager) is
# what omedora's session launches through (`uwsm start ... hyprland.desktop`);
# it was implicitly provided by that COPR, so vendoring the Hyprland stack
# (task #66) means owning uwsm too. All BuildRequires are in Fedora main.
Name:           uwsm
Version:        0.23.3
Release:        2%{?dist}
Summary:        Universal Wayland Session Manager

License:        MIT
URL:            https://github.com/Vladimir-csp/uwsm
Source:         %{url}/archive/v%{version}/%{name}-%{version}.tar.gz
BuildArch:      noarch

BuildRequires:  desktop-file-utils
BuildRequires:  meson
BuildRequires:  python-rpm-macros
BuildRequires:  python3
BuildRequires:  python3-dbus
BuildRequires:  python3-pyxdg
BuildRequires:  scdoc
BuildRequires:  systemd-rpm-macros

Requires:       python3
Requires:       python3-dbus
Requires:       python3-pyxdg
Requires:       util-linux

Recommends:     /usr/bin/notify-send
Recommends:     /usr/bin/whiptail
Recommends:     wofi

%description
Wraps standalone Wayland compositors into a set of Systemd units on the fly.
This provides robust session management including environment, XDG autostart
support, bi-directional binding with login session, and clean shutdown.
For compositors this is an opportunity to offload Systemd integration and
session/XDG autostart management in Systemd-managed environments.

%prep
%autosetup -p1

%build
%meson -Duuctl=enabled -Dfumon=enabled -Duwsm-app=enabled
%meson_build

%install
%meson_install
%py_byte_compile %{python3} %{buildroot}%{_datadir}/%{name}/modules

# omedora: serialize uwsm-app's app-daemon FIFO round-trip to fix a concurrent-
# autostart RACE. The uwsm-app client writes "\0app\0<args>" into the single
# shared $XDG_RUNTIME_DIR/uwsm-app-daemon-in FIFO with NO locking, and the
# daemon reads it with fifo.read() (until ALL writers close) then splits on NUL.
# When a compositor's autostart spawns several uwsm-app processes at once (e.g.
# Omarchy launches waybar/swaybg/mako/hypridle together), their writes interleave
# into one daemon read -> [app, waybar, app, swaybg, ...] -> it runs the first
# and treats the rest as ARGUMENTS, so the other apps are silently dropped
# (no wallpaper / no waybar, non-deterministic per boot). Wrap the whole
# write+read transaction in an flock so clients negotiate one at a time; the lock
# is released BEFORE the app is exec'd, so app lifetimes are NOT serialized.
# Verified: 6 concurrent launches -> 6 clean separate dispatches (was 1 merged).
# The asserts fail the build if upstream changes the client, signalling review.
%{__python3} - %{buildroot}%{_bindir}/uwsm-app <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
A1 = '# write args to input pipe'
A2 = 'done < "$PIPE_OUT"'
assert A1 in s and A2 in s, "uwsm-app flock anchors missing - review omedora patch"
assert 'omedora:' not in s, "uwsm-app already patched?"
acq = ('if command -v flock >/dev/null 2>&1; then\n'
       '  exec 9>"${XDG_RUNTIME_DIR}/uwsm-app-daemon.lock"  # omedora: serialize daemon round-trip\n'
       '  flock 9 2>/dev/null || true\n'
       'fi\n')
rel = ('\nif command -v flock >/dev/null 2>&1; then flock -u 9 2>/dev/null || true; fi'
       '  # omedora: release before app exec\n')
s = s.replace(A1, acq + A1, 1).replace(A2, A2 + rel, 1)
open(p, 'w').write(s)
PYEOF

%check
# Confirm the flock serialization landed in the installed client.
grep -q 'omedora: serialize daemon round-trip' %{buildroot}%{_bindir}/uwsm-app
desktop-file-validate %{buildroot}%{_datadir}/applications/*.desktop

%post
%systemd_user_post fumon.service

%preun
%systemd_user_preun fumon.service

%postun
%systemd_user_postun fumon.service

%files
%doc %{_docdir}/%{name}/
%license LICENSE
%{_bindir}/%{name}
%{_bindir}/%{name}-app
%{_bindir}/%{name}-terminal
%{_bindir}/%{name}-terminal-scope
%{_bindir}/%{name}-terminal-service
%{_bindir}/fumon
%{_bindir}/uuctl
%{_datadir}/%{name}/
%{_datadir}/applications/uuctl.desktop
%{_mandir}/man1/%{name}.1.*
%{_mandir}/man1/fumon.1.*
%{_mandir}/man1/uuctl.1.*
%{_mandir}/man1/uwsm-app.1.*
%{_mandir}/man3/%{name}-plugins.3.*
%{_userunitdir}/fumon.service
%{_userunitdir}/*-graphical.slice
%{_userunitdir}/wayland-*.service
%{_userunitdir}/wayland-*.target

%changelog
* Sat May 30 2026 Andrew Gaspar <andrew.gaspar@outlook.com> - 0.23.3-2
- Patch uwsm-app to flock its app-daemon FIFO round-trip, fixing a concurrent-
  autostart race where simultaneous uwsm-app launches interleaved in the
  daemon's read-until-EOF and got mis-parsed (waybar/swaybg/etc. silently
  dropped, non-deterministic per boot). Verified live: 6 concurrent launches
  now produce 6 clean separate dispatches.

* Sat May 30 2026 Andrew Gaspar <andrew.gaspar@outlook.com> - 0.23.3-1
- Initial omedora package (adapted from solopasha/hyprlandRPM) after dropping
  the lionheartp/Hyprland COPR, which previously provided uwsm.
