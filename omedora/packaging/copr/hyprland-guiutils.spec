# hyprland-guiutils.spec — Hyprland's hyprtoolkit-based GUI utilities (omedora).
#
# Successor to hyprland-qtutils (the Qt path omedora does not use): a set of
# small native GUI helpers (hyprland-dialog/-run/-welcome/-donate-screen/
# -update-screen) built on hyprtoolkit. Referenced by name in
# install/omarchy-base.packages. Not in Fedora 44 and NOT in solopasha's spec
# set, so this spec is authored fresh in omedora's conventions, mirroring the
# from-source hypr* component pattern. Upstream ships no release tarball, so
# Source0 is the tagged-archive (unpacks to hyprland-guiutils-VERSION/).

Name:           hyprland-guiutils
Version:        0.2.1
Release:        1%{?dist}
Summary:        Hyprland's hyprtoolkit-based GUI utilities

License:        BSD-3-Clause
URL:            https://github.com/hyprwm/hyprland-guiutils
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

# https://fedoraproject.org/wiki/Changes/EncourageI686LeafRemoval
ExcludeArch:    %{ix86}

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  ninja-build
BuildRequires:  pkgconfig(hyprlang)
BuildRequires:  pkgconfig(hyprutils)
BuildRequires:  pkgconfig(hyprtoolkit)
BuildRequires:  pkgconfig(pango)
BuildRequires:  pkgconfig(cairo)

# Successor to the Qt-based hyprland-qtutils; let dnf migrate cleanly if a user
# ever had a qtutils build from the dropped COPR.
Provides:       hyprland-qtutils = %{version}-%{release}
Obsoletes:      hyprland-qtutils < %{version}-%{release}

%description
hyprland-guiutils is a collection of small native GUI utilities for Hyprland
(dialog, run launcher, welcome/donate/update screens) built on the
hyprtoolkit Wayland-native toolkit. It is the successor to hyprland-qtutils.

%prep
%autosetup -p1

%build
%cmake -GNinja -DCMAKE_BUILD_TYPE=Release
%cmake_build

%install
%cmake_install

%files
%license LICENSE
%doc README.md
%{_bindir}/hyprland-dialog
%{_bindir}/hyprland-run
%{_bindir}/hyprland-welcome
%{_bindir}/hyprland-donate-screen
%{_bindir}/hyprland-update-screen

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 0.2.1-1
- Initial omedora build of hyprland-guiutils 0.2.1 (authored fresh; not in
  solopasha's set). Successor to hyprland-qtutils (Obsoletes/Provides it).
