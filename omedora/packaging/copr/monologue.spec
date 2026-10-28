# monologue.spec — Theme-synced webcam recorder for Omarchy (omedora).
#
# monologue (https://github.com/omacom/monologue, MIT) is one of Omarchy 4.5's omacom apps, a removable preinstall in
# omarchy-base.packages. Arch recipe: omacom/omarchy-pkgs/pkgbuilds/monologue.
#
# COPR-safe: a plain C++17 qmake6 build, so every dependency is a BuildRequires
# and the build needs no network. Mirrors upstream's ./bin/build and the
# PKGBUILD's package() layout, like omacut.spec.

# qmake's release config builds an optimized binary without -g, so there is no
# debug info to extract; an empty debuginfo subpackage would fail the build.
%global debug_package %{nil}

Name:           monologue
Version:        0.3.1
Release:        1%{?dist}
Summary:        Theme-synced webcam recorder for Omarchy

License:        MIT
URL:            https://github.com/omacom/monologue

# GitHub's tag archive unpacks to monologue-<version>/. build-local.sh (spectool -g)
# fetches it and verifies it against monologue.spec.sources.
Source0:        %{url}/archive/refs/tags/v%{version}/%{name}-%{version}.tar.gz

# Compiled for x86_64 (the only arch omedora targets right now).
ExclusiveArch:  x86_64

BuildRequires:  gcc-c++
BuildRequires:  make
BuildRequires:  desktop-file-utils
# core/gui/qml/quick/quickcontrols2/multimedia/dbus/concurrent (monologue.pro);
# Qt Multimedia 6.8+ for camera and microphone capture.
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel
BuildRequires:  qt6-qtmultimedia-devel >= 6.8
# Run, not linked: ffmpeg/ffprobe finish recordings (by path, so ffmpeg-free
# or RPM Fusion satisfies it); the portal backs the file picker.
Requires:       /usr/bin/ffmpeg
Requires:       /usr/bin/ffprobe
Requires:       xdg-desktop-portal

%description
monologue is a small webcam recorder whose interface follows the Omarchy theme:
pick a camera and microphone, record, trim and save the clip.

%prep
%autosetup -n %{name}-%{version}

%build
./bin/build

%install
install -D -m 0755 build/monologue %{buildroot}%{_bindir}/monologue
install -D -m 0644 pkgbuild/monologue.svg \
  %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/monologue.svg
install -D -m 0644 pkgbuild/monologue.desktop \
  %{buildroot}%{_datadir}/applications/monologue.desktop

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/monologue.desktop

%files
%license LICENSE
%doc README.md
%{_bindir}/monologue
%{_datadir}/icons/hicolor/scalable/apps/monologue.svg
%{_datadir}/applications/monologue.desktop

%changelog
* Tue Oct 27 2026 omedora <noreply@omedora> - 0.3.1-1
- Initial from-source (qmake6/Qt6) build of monologue (https://github.com/omacom/monologue), an Omarchy 4.5
  preinstall. Mirrors upstream's ./bin/build and the PKGBUILD layout.
