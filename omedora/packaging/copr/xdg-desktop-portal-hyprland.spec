# xdg-desktop-portal-hyprland.spec — xdg-desktop-portal backend (omedora).
#
# The Hyprland portal backend (screencast/screenshot). omedora wires the
# preview-share-picker (omedora/packaging/copr/hyprland-preview-share-picker.spec)
# as the custom picker, but xdph still builds its default Qt hyprland-share-picker
# (harmless to ship). Adapted from solopasha/hyprlandRPM. Deviation: 1.4.x finds
# system sdbus-c++ (>=2.0.0) via pkg-config, satisfied by Fedora's 2.2.1, so no
# sdbus bundling. omedora conventions: pinned Version, explicit Release +
# changelog. Keeps solopasha's Epoch:1 so it out-ranks any older COPR build.
#
# Built from the HypXR share-switch branch (AndrewGaspar/xdg-desktop-portal-hyprland):
# 1.4.1 plus upstream #424, #425 and #447, a requeue after a failed frame
# (#445/#451), no repeated renegotiation, renegotiation instead of the DMA
# format RASSERT abort, and a dma-buf retry reset. The Arch side ships the same
# commit as xdg-desktop-portal-hyprland-hypxr; omedora owns this package on
# Fedora, so the fixes go straight in. VERSION in the archive is still 1.4.1.

%global base_version 1.4.1
%global snapshot 20261110
%global commit 540fb9237d29c4c2aee5b0b42688ef31e097d2ce
%global shortcommit %(c=%{commit}; echo ${c:0:9})

Name:           xdg-desktop-portal-hyprland
Epoch:          1
Version:        %{base_version}^%{snapshot}.git%{shortcommit}
Release:        1%{?dist}
Summary:        xdg-desktop-portal backend for Hyprland

License:        BSD-3-Clause
URL:            https://github.com/AndrewGaspar/xdg-desktop-portal-hyprland
Source0:        %{url}/archive/%{commit}/%{name}-%{commit}.tar.gz

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  systemd-rpm-macros

BuildRequires:  pkgconfig(gbm)
BuildRequires:  pkgconfig(hyprland-protocols) >= 0.7.0
BuildRequires:  pkgconfig(hyprlang) >= 0.6.8
BuildRequires:  pkgconfig(hyprutils) >= 0.14.0
BuildRequires:  pkgconfig(hyprwayland-scanner) >= 0.4.6
BuildRequires:  pkgconfig(libdrm)
BuildRequires:  pkgconfig(libpipewire-0.3)
BuildRequires:  pkgconfig(libsystemd)
BuildRequires:  pkgconfig(sdbus-c++)
# 1.4.x added uuid to the required pkg_check_modules list (libuuid-devel).
BuildRequires:  pkgconfig(uuid)
BuildRequires:  pkgconfig(Qt6Widgets)
BuildRequires:  pkgconfig(systemd)
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-protocols)
BuildRequires:  pkgconfig(wayland-scanner)

Requires:       dbus
# required for the Screenshot portal implementation
Requires:       grim
Recommends:     hyprpicker
Requires:       xdg-desktop-portal
# required for hyprland-share-picker
Requires:       slurp
Requires:       qt6-qtwayland

Enhances:       hyprland
Supplements:    hyprland

%description
%{summary}.

%prep
%autosetup -n %{name}-%{commit} -p1
test "$(cat VERSION)" = %{base_version}

%build
%cmake -DCMAKE_BUILD_TYPE=Release
%cmake_build

%install
%cmake_install

%post
%systemd_user_post %{name}.service

%preun
%systemd_user_preun %{name}.service

%files
%license LICENSE
%doc README.md
%{_bindir}/hyprland-share-picker
%{_datadir}/dbus-1/services/org.freedesktop.impl.portal.desktop.hyprland.service
%{_datadir}/xdg-desktop-portal/portals/hyprland.portal
%{_libexecdir}/%{name}
%{_userunitdir}/%{name}.service

%changelog
* Wed Nov 11 2026 omedora <noreply@omedora> - 1:1.4.1^20261110.git540fb9237-1
- Build from the HypXR share-switch branch at 540fb9237: a failed frame no
  longer stalls a screenshare for good (#445/#451), renegotiation after a
  resize or switch is deduplicated and no longer aborts on a DMA format
  change, and the dma-buf retries reset so later renegotiations stay on
  dma-buf. Also carries upstream #424, #425 and #447. No dependency changes.

* Mon Aug 03 2026 omedora <noreply@omedora> - 1:1.4.1-1
- Update to xdg-desktop-portal-hyprland 1.4.1 (Hyprland 0.56.1 wave).
- Rebuilt against hyprutils 0.14.0 (SONAME 13).
- New BuildRequires: pkgconfig(uuid) — 1.4.x added it to its required
  pkg_check_modules list.

* Sat May 30 2026 omedora <noreply@omedora> - 1:1.3.12-1
- Initial omedora build of xdg-desktop-portal-hyprland 1.3.12 (adapted from
  solopasha/hyprlandRPM). Uses Fedora's system sdbus-c++ 2.2.1.
