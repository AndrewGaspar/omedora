# omawrite.spec — dead-simple Markdown writing app (omedora).
#
# omawrite (github.com/omacom-io/omawrite, MIT, by omacom.io) is a quattro-line
# omarchy-family app: a minimal Qt6/QML (Qt Quick + Controls) distraction-free
# Markdown editor, bound to SUPER+SHIFT+W in omarchy's Hyprland config. Upstream
# omarchy pulls it via omarchy-base.packages (Arch recipe:
# omacom-io/omarchy-pkgs/pkgbuilds/omawrite); this spec is the Fedora port so
# omedora installs it natively instead of skip-mapping it, and the keybind works.
#
# COPR-safe: a plain C++17/qmake6 build — all deps come from BuildRequires and
# %build needs no network (nothing to vendor, unlike our Rust specs). We mirror
# upstream's ./bin/build (qmake6 + make) and its PKGBUILD package() layout.
#
# FONT NOTE: upstream's PKGBUILD depends on ttf-ia-writer (the proprietary "iA
# Writer Mono S" font the QML asks for by family name). That font is NOT in
# Fedora and is intentionally skip-mapped in omedora (fedora.toml [ttf-ia-writer],
# "TODO: source installer") — we do NOT package it here. omawrite requests the
# family by name via QFont / QML `font.family`, so Qt/fontconfig silently
# substitutes a fallback monospace when it is absent: the app still installs and
# runs, just not in the exact iA Writer typeface. So this RPM deliberately does
# NOT Require the font; wiring the font is a separate deferred item.

# qmake's `release` config builds an optimized, un-instrumented binary (no -g),
# so there is no debug info to extract — disable the (would-be-empty) debuginfo/
# debugsource subpackage, which otherwise errors with "Empty %files".
%global debug_package %{nil}

Name:           omawrite
Version:        0.1.1
Release:        1%{?dist}
Summary:        Dead-simple Markdown writing app

License:        MIT
URL:            https://github.com/omacom-io/omawrite

# Source0: upstream tag tarball. build-local.sh (spectool -g) fetches it into
# SOURCES/ and verifies it against omawrite.spec.sources. GitHub's archive for
# the version tag unpacks to omawrite-<version>/. (The trailing basename just
# names the download; GitHub serves the same bytes as archive/refs/tags/v<version>.)
Source0:        %{url}/archive/refs/tags/v%{version}/%{name}-%{version}.tar.gz

# Compiled for x86_64 (the only arch omedora targets right now).
ExclusiveArch:  x86_64

# --- Build toolchain -------------------------------------------------------
# C++17 compiler + make drive the qmake6-generated Makefile.
BuildRequires:  gcc-c++
BuildRequires:  make
# qmake6 + QtCore/Gui/Qml/Quick/QuickControls2/DBus headers (omawrite.pro).
# qmake6 itself ships in qt6-qtbase-devel.
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel
# desktop-file-utils validates the installed .desktop file in %check.
BuildRequires:  desktop-file-utils

# --- Runtime ---------------------------------------------------------------
# RPM auto-detects the binary's link-time Qt .so deps. xdg-desktop-portal backs
# omawrite's native open/save file picker. The iA Writer font (ttf-ia-writer) is
# deliberately NOT required — see the FONT NOTE header; Qt substitutes a fallback.
Requires:       xdg-desktop-portal

%description
omawrite is a minimal, distraction-free Markdown writing app with a Qt Quick
(QML) UI and live Markdown highlighting. In omarchy it opens on SUPER+SHIFT+W. It
uses the desktop portal for its file picker. It renders in the "iA Writer Mono S"
font when installed and falls back to another monospace font otherwise.

%prep
# GitHub tag archive unpacks to omawrite-%{version}/.
%autosetup -n %{name}-%{version}

%build
# Mirror upstream's ./bin/build: out-of-source qmake6 + parallel make. bin/build
# auto-detects qmake6 (from qt6-qtbase-devel) and uses nproc for -j.
./bin/build

%install
# Mirror the PKGBUILD package() layout.
install -D -m 0755 build/omawrite %{buildroot}%{_bindir}/omawrite
install -D -m 0644 pkgbuild/omawrite.svg \
  %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/omawrite.svg
install -D -m 0644 pkgbuild/omawrite.desktop \
  %{buildroot}%{_datadir}/applications/omawrite.desktop

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/omawrite.desktop

%files
%license LICENSE
%doc README.md
%{_bindir}/omawrite
%{_datadir}/icons/hicolor/scalable/apps/omawrite.svg
%{_datadir}/applications/omawrite.desktop

%changelog
* Fri Jul 03 2026 omedora <noreply@omedora> - 0.1.1-1
- Initial from-source (qmake6/Qt6) build of omawrite, the quattro-line Markdown
  writing app bound to SUPER+SHIFT+W (github.com/omacom-io/omawrite, MIT).
- Mirrors upstream's ./bin/build and PKGBUILD layout: ships /usr/bin/omawrite
  plus the omawrite .desktop/icon. Requires xdg-desktop-portal for the file
  picker. Does NOT Require the proprietary ttf-ia-writer font (skip-mapped in
  omedora); Qt substitutes a fallback monospace so the app still runs.
