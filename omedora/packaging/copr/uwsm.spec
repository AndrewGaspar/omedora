# Adapted from solopasha/hyprlandRPM (uwsm/uwsm.spec) — the spec set the
# lionheartp/Hyprland COPR forked. uwsm (Universal Wayland Session Manager) is
# what omedora's session launches through (`uwsm start ... hyprland.desktop`);
# it was implicitly provided by that COPR, so vendoring the Hyprland stack
# (task #66) means owning uwsm too. All BuildRequires are in Fedora main.
Name:           uwsm
Version:        0.26.5
Release:        1%{?dist}
Summary:        Universal Wayland Session Manager

License:        MIT
URL:            https://github.com/Vladimir-csp/uwsm
Source:         %{url}/archive/v%{version}/%{name}-%{version}.tar.gz
BuildArch:      noarch

BuildRequires:  desktop-file-utils
# uwsm 0.26 raised its meson floor to >=1.3.0 (meson.build); Fedora 44 ships a
# newer meson, but pin the floor so an older build host fails loudly.
BuildRequires:  meson >= 1.3.0
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
# uuctl/fumon/uwsm-app default to disabled in 0.26's meson.options; enable the
# ones omedora ships (the session uses uwsm-app's app-daemon dispatch).
%meson -Duuctl=enabled -Dfumon=enabled -Duwsm-app=enabled
%meson_build

%install
%meson_install
%py_byte_compile %{python3} %{buildroot}%{_datadir}/%{name}/modules

# NOTE (omedora): 0.23.x carried an omedora patch that flock-serialized
# uwsm-app's app-daemon FIFO round-trip to fix a concurrent-autostart race
# (simultaneous uwsm-app launches interleaving in the daemon's read-until-EOF,
# silently dropping waybar/swaybg/etc.). As of upstream commit "fix: add mutex
# to uwsm-app.sh" (in 0.24+), uwsm-app.sh now acquires an flock mutex around the
# whole write+read transaction itself (get_lock/release_lock), which is exactly
# what our patch did. The patch is therefore DROPPED here as redundant — the
# upstream mutex supersedes it.

%check
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
# 0.26 splits the env/signal helpers into a libexec dir (prepare-env.sh,
# signal-handler.sh) sourced by the wayland-wm-env@/session units.
%dir %{_libexecdir}/%{name}
%{_libexecdir}/%{name}/prepare-env.sh
%{_libexecdir}/%{name}/signal-handler.sh
%{_datadir}/%{name}/
%{_datadir}/applications/uuctl.desktop
%{_mandir}/man1/%{name}.1.*
%{_mandir}/man1/fumon.1.*
%{_mandir}/man1/uuctl.1.*
%{_mandir}/man1/uwsm-app.1.*
%{_mandir}/man3/%{name}-plugins.3.*
# 0.26 systemd preset for fumon.service (enabled by the fumon feature).
%{_userpresetdir}/80-fumon.preset
%{_userunitdir}/fumon.service
%{_userunitdir}/*-graphical.slice
%{_userunitdir}/wayland-*.service
%{_userunitdir}/wayland-*.target

%changelog
* Tue Jun 16 2026 Andrew Gaspar <andrew.gaspar@outlook.com> - 0.26.5-1
- Bump to upstream 0.26.5 (tag tarball).

* Thu Jun 04 2026 Andrew Gaspar <andrew.gaspar@outlook.com> - 0.26.4-1
- Bump to upstream 0.26.4 (from 0.23.3).
- Drop the omedora uwsm-app flock patch: upstream's "fix: add mutex to
  uwsm-app.sh" now serializes the app-daemon round-trip natively
  (get_lock/release_lock), making our patch redundant.
- %%files: add the new 0.26 %%{_libexecdir}/uwsm helpers (prepare-env.sh,
  signal-handler.sh) and the 80-fumon.preset systemd user preset; the new
  session-envelope/pre/waitenv/bindpid units and graphical slices are picked
  up by the existing wayland-*.{service,target} / *-graphical.slice globs.
- BuildRequires: pin meson >= 1.3.0 (0.26's meson_version floor).

* Sat May 30 2026 Andrew Gaspar <andrew.gaspar@outlook.com> - 0.23.3-2
- Patch uwsm-app to flock its app-daemon FIFO round-trip, fixing a concurrent-
  autostart race where simultaneous uwsm-app launches interleaved in the
  daemon's read-until-EOF and got mis-parsed (waybar/swaybg/etc. silently
  dropped, non-deterministic per boot). Verified live: 6 concurrent launches
  now produce 6 clean separate dispatches.

* Sat May 30 2026 Andrew Gaspar <andrew.gaspar@outlook.com> - 0.23.3-1
- Initial omedora package (adapted from solopasha/hyprlandRPM) after dropping
  the lionheartp/Hyprland COPR, which previously provided uwsm.
