# omacut.spec — dead-simple video length trimmer (omedora).
#
# omacut (github.com/omacom-io/omacut, MIT, by omacom.io) is a quattro-line
# omarchy-family app: a tiny Qt6/QML (Qt Quick + Controls, Material style) video
# trimmer that hands the actual cut to ffmpeg. Upstream omarchy pulls it via
# omarchy-base.packages (Arch recipe: omacom-io/omarchy-pkgs/pkgbuilds/omacut);
# this spec is the Fedora port so omedora installs it natively instead of
# skip-mapping it.
#
# COPR-safe: this is a plain C++17/qmake6 build, so all deps come from
# BuildRequires and the %build phase needs no network — nothing to vendor (unlike
# our Rust specs). We simply mirror upstream's ./bin/build (qmake6 + make) and
# its PKGBUILD package() layout.

# qmake's `release` config builds an optimized, un-instrumented binary (no -g),
# so there is no debug info to extract — disable the (would-be-empty) debuginfo/
# debugsource subpackage, which otherwise errors with "Empty %files".
%global debug_package %{nil}

Name:           omacut
Version:        0.1.2
Release:        1%{?dist}
Summary:        Dead-simple video length trimmer

License:        MIT
URL:            https://github.com/omacom-io/omacut

# Source0: upstream tag tarball. build-local.sh (spectool -g) fetches it into
# SOURCES/ and verifies it against omacut.spec.sources. GitHub's archive for the
# version tag unpacks to omacut-<version>/. (The trailing basename just names the
# download; GitHub serves the same bytes as archive/refs/tags/v<version>.)
Source0:        %{url}/archive/refs/tags/v%{version}/%{name}-%{version}.tar.gz

# Compiled for x86_64 (the only arch omedora targets right now).
ExclusiveArch:  x86_64

# --- Build toolchain -------------------------------------------------------
# C++17 compiler + make drive the qmake6-generated Makefile.
BuildRequires:  gcc-c++
BuildRequires:  make
# qmake6 + QtCore/Gui/Qml/Quick/QuickControls2/DBus headers (omacut.pro).
# qmake6 itself ships in qt6-qtbase-devel.
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel
# QtMultimedia: omacut previews the video via the Qt multimedia stack.
BuildRequires:  qt6-qtmultimedia-devel
# desktop-file-utils validates the installed .desktop file in %check.
BuildRequires:  desktop-file-utils

# --- Runtime ---------------------------------------------------------------
# RPM auto-detects the binary's link-time Qt .so deps. ffmpeg/ffprobe are
# invoked at RUNTIME (not linked) to perform the cut, so require them explicitly.
# Require the file PATHS rather than the "ffmpeg" package name so this resolves
# with either Fedora's ffmpeg-free (main repo) OR RPM Fusion's ffmpeg — omedora's
# build/repo path does not enable RPM Fusion.
Requires:       /usr/bin/ffmpeg
Requires:       /usr/bin/ffprobe
# xdg-desktop-portal backs omacut's native open/save file picker.
Requires:       xdg-desktop-portal

%description
omacut is a minimal video length trimmer with a Qt Quick (QML) UI: open a video,
drag the trim bar to the wanted in/out points, and export the clip. The trim
itself is handed to ffmpeg; exports are always written as MP4. It uses the
desktop portal for its file picker.

%prep
# GitHub tag archive unpacks to omacut-%{version}/.
%autosetup -n %{name}-%{version}

%build
# Mirror upstream's ./bin/build: out-of-source qmake6 + parallel make. bin/build
# auto-detects qmake6 (from qt6-qtbase-devel) and uses nproc for -j.
./bin/build

%install
# Mirror the PKGBUILD package() layout.
install -D -m 0755 build/omacut %{buildroot}%{_bindir}/omacut
install -D -m 0644 pkgbuild/omacut.svg \
  %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/omacut.svg
install -D -m 0644 pkgbuild/omacut.desktop \
  %{buildroot}%{_datadir}/applications/omacut.desktop

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/omacut.desktop

%files
%license LICENSE
%doc README.md
%{_bindir}/omacut
%{_datadir}/icons/hicolor/scalable/apps/omacut.svg
%{_datadir}/applications/omacut.desktop

%changelog
* Fri Jul 03 2026 omedora <noreply@omedora> - 0.1.2-1
- Initial from-source (qmake6/Qt6) build of omacut, the quattro-line video-trim
  tool (github.com/omacom-io/omacut, MIT).
- Mirrors upstream's ./bin/build and PKGBUILD layout: ships /usr/bin/omacut plus
  the omacut .desktop/icon. Requires ffmpeg/ffprobe (by path, so ffmpeg-free or
  RPM Fusion satisfies it) and xdg-desktop-portal for the file picker.
