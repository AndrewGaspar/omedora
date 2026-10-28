# signed.spec — Sign PDFs and fill them in with text and dates (omedora).
#
# signed (https://github.com/omacom/signed, MIT) is one of Omarchy 4.5's omacom apps, a removable preinstall in
# omarchy-base.packages. Arch recipe: omacom/omarchy-pkgs/pkgbuilds/signed.
#
# COPR-safe: a plain C++17 qmake6 build, so every dependency is a BuildRequires
# and the build needs no network. Mirrors upstream's ./bin/build and the
# PKGBUILD's package() layout, like omacut.spec.

# qmake's release config builds an optimized binary without -g, so there is no
# debug info to extract; an empty debuginfo subpackage would fail the build.
%global debug_package %{nil}

Name:           signed
Version:        0.3.1
Release:        1%{?dist}
Summary:        Sign PDFs and fill them in with text and dates

License:        MIT
URL:            https://github.com/omacom/signed

# GitHub's tag archive unpacks to signed-<version>/. build-local.sh (spectool -g)
# fetches it and verifies it against signed.spec.sources.
Source0:        %{url}/archive/refs/tags/v%{version}/%{name}-%{version}.tar.gz

# Compiled for x86_64 (the only arch omedora targets right now).
ExclusiveArch:  x86_64

BuildRequires:  gcc-c++
BuildRequires:  make
BuildRequires:  desktop-file-utils
# core/gui/qml/quick/quickcontrols2/dbus plus poppler-qt6 and libqpdf through
# pkg-config (signed.pro).
BuildRequires:  qt6-qtbase-devel
BuildRequires:  qt6-qtdeclarative-devel
BuildRequires:  pkgconf-pkg-config
BuildRequires:  pkgconfig(poppler-qt6)
BuildRequires:  pkgconfig(libqpdf)
# The PKGBUILD depends on noto-fonts for the text it stamps into documents and
# on qt6-wayland for the native window; the portal backs the file picker.
Requires:       google-noto-sans-fonts
Requires:       qt6-qtwayland
Requires:       xdg-desktop-portal

%description
signed opens a PDF, lets you place a drawn or typed signature, text and dates
on its pages, and saves the filled-in document.

%prep
%autosetup -n %{name}-%{version}

%build
./bin/build

%install
install -D -m 0755 build/signed %{buildroot}%{_bindir}/signed
install -D -m 0644 pkgbuild/signed.svg \
  %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/signed.svg
install -D -m 0644 pkgbuild/signed.desktop \
  %{buildroot}%{_datadir}/applications/signed.desktop

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/signed.desktop

%files
%license LICENSE
%doc README.md
%{_bindir}/signed
%{_datadir}/icons/hicolor/scalable/apps/signed.svg
%{_datadir}/applications/signed.desktop

%changelog
* Tue Oct 27 2026 omedora <noreply@omedora> - 0.3.1-1
- Initial from-source (qmake6/Qt6) build of signed (https://github.com/omacom/signed), an Omarchy 4.5
  preinstall. Mirrors upstream's ./bin/build and the PKGBUILD layout.
