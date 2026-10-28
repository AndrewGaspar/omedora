# hype.spec — Markdown presentations with a visual slide editor (omedora).
#
# hype (https://github.com/omacom/hype, MIT) is one of Omarchy 4.5's omacom apps, a removable preinstall in
# omarchy-base.packages. Arch recipe: omacom/omarchy-pkgs/pkgbuilds/hype.
#
# COPR-safe: a plain C++17 qmake6 build, so every dependency is a BuildRequires
# and the build needs no network. Mirrors upstream's ./bin/build and the
# PKGBUILD's package() layout, like omacut.spec.

# qmake's release config builds an optimized binary without -g, so there is no
# debug info to extract; an empty debuginfo subpackage would fail the build.
%global debug_package %{nil}

Name:           hype
Version:        0.6.0
Release:        1%{?dist}
Summary:        Markdown presentations with a visual slide editor

License:        MIT
URL:            https://github.com/omacom/hype

# GitHub's tag archive unpacks to hype-<version>/. build-local.sh (spectool -g)
# fetches it and verifies it against hype.spec.sources.
Source0:        %{url}/archive/refs/tags/v%{version}/%{name}-%{version}.tar.gz

# Compiled for x86_64 (the only arch omedora targets right now).
ExclusiveArch:  x86_64

BuildRequires:  gcc-c++
BuildRequires:  make
BuildRequires:  desktop-file-utils
# Qt 6.9+ (bin/build refuses older): core/gui/qml/quick/quickcontrols2/
# multimedia/concurrent/dbus/svg (hype.pro), plus zlib and libwebp(demux).
BuildRequires:  qt6-qtbase-devel >= 6.9
BuildRequires:  qt6-qtdeclarative-devel >= 6.9
BuildRequires:  qt6-qtmultimedia-devel >= 6.9
BuildRequires:  qt6-qtsvg-devel >= 6.9
BuildRequires:  zlib-devel
BuildRequires:  libwebp-devel
# Run, not linked: ffmpeg/ffprobe for video export (by path, so ffmpeg-free or
# RPM Fusion satisfies it) and source-highlight for code slides. Image formats
# come through the Qt plugin, the file picker through the portal.
Requires:       /usr/bin/ffmpeg
Requires:       /usr/bin/ffprobe
Requires:       source-highlight
Requires:       qt6-qtimageformats
Requires:       xdg-desktop-portal

%description
hype turns a Markdown file into a slide deck: write slides as Markdown, arrange
them in a visual editor, present full screen, and export to PDF, PPTX or video.

%prep
%autosetup -n %{name}-%{version}

%build
./bin/build

%install
install -D -m 0755 build/hype %{buildroot}%{_bindir}/hype
install -D -m 0644 pkgbuild/hype.svg \
  %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/hype.svg
install -D -m 0644 pkgbuild/hype.desktop \
  %{buildroot}%{_datadir}/applications/hype.desktop

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/hype.desktop

%files
%license LICENSE
%doc README.md
%{_bindir}/hype
%{_datadir}/icons/hicolor/scalable/apps/hype.svg
%{_datadir}/applications/hype.desktop

%changelog
* Tue Oct 27 2026 omedora <noreply@omedora> - 0.6.0-1
- Initial from-source (qmake6/Qt6) build of hype (https://github.com/omacom/hype), an Omarchy 4.5
  preinstall. Mirrors upstream's ./bin/build and the PKGBUILD layout.
