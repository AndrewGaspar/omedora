# owe.spec — Omarchy's wallpaper engine (omedora).
#
# owe (github.com/omacom/owe, MIT) plays Omarchy 4.5's desktop backgrounds:
# stills, GIFs and video, including each theme's intro clip. The shell talks to
# the owed user daemon; omarchy-theme-set and omarchy-theme-bg-boot-intro call
# the owe CLI; first-run enables owed.service and installs the theme-set hook
# from /usr/share/owe/10-owe-sync. Arch recipe:
# omacom/omarchy-pkgs/pkgbuilds/owe.
#
# COPR-safe: a plain meson C build against Fedora's mpv, ffmpeg-free, EGL/GLES
# and libsystemd, so every dependency is a BuildRequires and the build needs no
# network. Mirrors the PKGBUILD's build() and package(), minus its libalpm
# restart hook (90-owe-restart.hook + /usr/lib/owe/package-restart), which only
# pacman runs.
#
# The meson test suite isn't run: its render tests need a software-GL EGL
# context and frame-timing windows the PKGBUILD already has to relax on slow
# builders.
#
# Codec note: the theme intros are H.264 High profile. Fedora's ffmpeg-free
# decodes H.264 only through openh264 (Constrained Baseline), so playing them
# needs RPM Fusion's ffmpeg-libs or a VA-API driver that decodes H.264.

Name:           owe
Version:        0.2.12
Release:        1%{?dist}
Summary:        High-performance wallpaper engine for Omarchy (mp4, gif, stills)

License:        MIT
# The release tarball ships no LICENSE file; MIT is declared in meson.build
# (project license) and the PKGBUILD.
URL:            https://github.com/omacom/owe

# GitHub's tag archive unpacks to owe-<version>/. build-local.sh (spectool -g)
# fetches it and verifies it against owe.spec.sources.
Source0:        %{url}/archive/refs/tags/v%{version}/%{name}-%{version}.tar.gz

# Compiled for x86_64 (the only arch omedora targets right now).
ExclusiveArch:  x86_64

BuildRequires:  meson
BuildRequires:  ninja-build
BuildRequires:  gcc
BuildRequires:  pkgconf-pkg-config
BuildRequires:  wayland-devel
BuildRequires:  wayland-protocols-devel
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-egl)
BuildRequires:  pkgconfig(egl)
BuildRequires:  pkgconfig(glesv2)
BuildRequires:  pkgconfig(gl)
BuildRequires:  pkgconfig(epoxy)
BuildRequires:  pkgconfig(mpv) >= 0.35
BuildRequires:  pkgconfig(libavformat)
BuildRequires:  pkgconfig(libavcodec)
BuildRequires:  pkgconfig(libavutil)
BuildRequires:  pkgconfig(libswscale)
BuildRequires:  pkgconfig(libsystemd)
BuildRequires:  systemd-rpm-macros

# The theme-set hook pings owed's socket with socat.
Requires:       socat

%description
owe is the wallpaper engine behind Omarchy's desktop backgrounds. The owed
user daemon renders stills, GIFs and video (through libmpv) on every output
with smooth transitions, and the owe CLI drives it from theme changes,
including each theme's intro clip.

%prep
%autosetup -n %{name}-%{version}

%build
%meson
%meson_build

%install
%meson_install
# The PKGBUILD's package() layout: a system user unit pointing at /usr/bin,
# the idle helper, the theme-set hook Omarchy installs, and an example config.
install -d %{buildroot}%{_userunitdir}
sed 's|%%h/.local/bin/owed|%{_bindir}/owed|' systemd/owed.service \
  >%{buildroot}%{_userunitdir}/owed.service
install -Dpm755 hooks/owe-idle %{buildroot}%{_bindir}/owe-idle
install -Dpm644 hooks/theme-set.d/10-owe-sync %{buildroot}%{_datadir}/owe/10-owe-sync
install -Dpm644 config/config.toml %{buildroot}%{_docdir}/%{name}/config.toml.example
install -Dpm644 README.md %{buildroot}%{_docdir}/%{name}/README.md

%check
grep -q '^ExecStart=.*%{_bindir}/owed ' %{buildroot}%{_userunitdir}/owed.service

%post
%systemd_user_post owed.service

%preun
%systemd_user_preun owed.service

%files
%doc %{_docdir}/%{name}/README.md
%doc %{_docdir}/%{name}/config.toml.example
%{_bindir}/owe
%{_bindir}/owed
%{_bindir}/owe-render
%{_bindir}/owe-idle
%dir %{_datadir}/owe
%{_datadir}/owe/10-owe-sync
%{_userunitdir}/owed.service

%changelog
* Tue Oct 27 2026 omedora <noreply@omedora> - 0.2.12-1
- Initial from-source (meson) build of owe, Omarchy 4.5's wallpaper engine
  (github.com/omacom/owe). Mirrors the omarchy-pkgs PKGBUILD without its
  libalpm restart hook.
