# hyprland-protocols.spec — Wayland protocol extensions for Hyprland (omedora).
#
# Pure protocol XML + pkgconfig; noarch. BuildRequired by hypridle/hyprsunset/
# xdg-desktop-portal-hyprland and bundled by hyprland itself. Not in Fedora 44.
# Adapted from solopasha/hyprlandRPM (the maintained Fedora spec set omedora's
# hyprwm packaging is based on). omedora conventions: pinned Version,
# explicit Release + changelog.

Name:           hyprland-protocols
Version:        0.8.0
Release:        1%{?dist}
Summary:        Wayland protocol extensions for Hyprland
BuildArch:      noarch

License:        BSD-3-Clause
URL:            https://github.com/hyprwm/hyprland-protocols
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

# 0.8.0 replaced meson with CMake; the project still enables C, so CMake
# needs a C compiler to configure.
BuildRequires:  cmake
BuildRequires:  gcc

%description
%{summary}.

%package        devel
Summary:        Wayland protocol extensions for Hyprland
%description    devel
%{summary}.

%prep
%autosetup -p1

%build
%cmake
%cmake_build

%install
%cmake_install

%files devel
%license LICENSE
%doc README.md
%{_datadir}/pkgconfig/%{name}.pc
%{_datadir}/%{name}/

%changelog
* Wed Nov 18 2026 omedora <noreply@omedora> - 0.8.0-1
- Update to hyprland-protocols 0.8.0 (the version Omarchy stable ships),
  which builds with CMake instead of meson.

* Sat May 30 2026 omedora <noreply@omedora> - 0.7.0-1
- Initial omedora build of hyprland-protocols (adapted from solopasha/hyprlandRPM).
