# omasnap.spec — Wayland screenshot + annotation overlay (omedora).
#
# omasnap (github.com/omacom/omasnap, MIT; bundled fonts OFL-1.1, Lucide icons
# ISC) is Omarchy 4.5's screenshot tool: omarchy-capture-screenshot execs it,
# and the clipboard image opener and imv's edit binding hand images to it. It
# replaces satty/tensaku in omarchy-base.packages (migration 1788129995 adds it
# and drops those two). Arch recipe: omacom/omarchy-pkgs/pkgbuilds/omasnap.
#
# COPR-safe: a plain CMake/Ninja C++ build against Fedora's Qt 6, LayerShellQt,
# wayland and libdeflate, so every dependency is a BuildRequires and the build
# phase needs no network. Mirrors the PKGBUILD's build() and package().
#
# The upstream smoke suite (omasnap-smoke) is not built or run: it fsyncs under
# /tmp against 5-second settle windows, which the PKGBUILD itself has to work
# around on loaded builders, and an offscreen Qt run in mock adds nothing the
# desktop-file check doesn't cover for packaging.

Name:           omasnap
Version:        1.24.0
Release:        1%{?dist}
Summary:        Native Wayland screenshot and annotation overlay for Hyprland

License:        MIT AND OFL-1.1 AND ISC
URL:            https://github.com/omacom/omasnap

# GitHub's tag archive unpacks to omasnap-<version>/. build-local.sh (spectool
# -g) fetches it and verifies it against omasnap.spec.sources.
Source0:        %{url}/archive/refs/tags/v%{version}/%{name}-%{version}.tar.gz

# Compiled for x86_64 (the only arch omedora targets right now).
ExclusiveArch:  x86_64

BuildRequires:  cmake >= 3.24
BuildRequires:  ninja-build
BuildRequires:  gcc-c++
BuildRequires:  pkgconf-pkg-config
# Qt6 Concurrent/Core/Gui/Test/Widgets (CMakeLists: find_package(Qt6 6.8 ...)).
BuildRequires:  qt6-qtbase-devel >= 6.8
BuildRequires:  layer-shell-qt-devel
BuildRequires:  wayland-devel
# wayland-scanner runs over the staging ext-image-copy-capture/-capture-source
# and ext-foreign-toplevel-list XMLs, read from /usr/share/wayland-protocols.
BuildRequires:  wayland-protocols-devel
BuildRequires:  libdeflate-devel
BuildRequires:  desktop-file-utils

# Runtime tools omasnap invokes rather than links (the PKGBUILD's depends):
# OCR of a selection and the clipboard hand-off.
Requires:       tesseract
Requires:       tesseract-langpack-eng
Requires:       wl-clipboard

%description
omasnap is a native Wayland screenshot tool for Hyprland: it freezes the
screen under a layer-shell overlay, lets you select a region, window or
output, annotate it (arrows, boxes, text, blur, highlights), pin it, scroll-
capture long content, extract text with OCR, and save it or copy it to the
clipboard.

%prep
%autosetup -n %{name}-%{version}

%build
%cmake -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTING=OFF
%cmake_build

%install
%cmake_install
install -Dpm644 README.md %{buildroot}%{_docdir}/%{name}/README.md

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/omasnap.desktop

%files
%license LICENSE
%dir %{_datadir}/licenses/%{name}
%{_datadir}/licenses/%{name}/Neucha-OFL.txt
%{_datadir}/licenses/%{name}/JetBrainsMono-OFL.txt
%{_datadir}/licenses/%{name}/Inter-OFL.txt
%{_datadir}/licenses/%{name}/Lucide-ISC.txt
%doc %{_docdir}/%{name}/README.md
%{_bindir}/omasnap
%{_datadir}/applications/omasnap.desktop

%changelog
* Tue Oct 27 2026 omedora <noreply@omedora> - 1.24.0-1
- Initial from-source (CMake/Qt6) build of omasnap, Omarchy 4.5's screenshot
  and annotation overlay (github.com/omacom/omasnap). Mirrors the omarchy-pkgs
  PKGBUILD; requires tesseract + English data and wl-clipboard at runtime.
