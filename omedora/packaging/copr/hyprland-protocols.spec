# hyprland-protocols.spec — Wayland protocol extensions for Hyprland (omedora).
#
# Pure protocol XML + pkgconfig; noarch. BuildRequired by hypridle/hyprsunset/
# xdg-desktop-portal-hyprland and bundled by hyprland itself. Not in Fedora 44.
# Adapted from solopasha/hyprlandRPM (the maintained Fedora spec set the dropped
# lionheartp/Hyprland COPR forked). omedora conventions: pinned Version,
# explicit Release + %changelog.

Name:           hyprland-protocols
Version:        0.7.0
Release:        1%{?dist}
Summary:        Wayland protocol extensions for Hyprland
BuildArch:      noarch

License:        BSD-3-Clause
URL:            https://github.com/hyprwm/hyprland-protocols
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildRequires:  meson

%description
%{summary}.

%package        devel
Summary:        Wayland protocol extensions for Hyprland
%description    devel
%{summary}.

%prep
%autosetup -p1

%build
%meson
%meson_build

%install
%meson_install

%files devel
%license LICENSE
%doc README.md
%{_datadir}/pkgconfig/%{name}.pc
%{_datadir}/%{name}/

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 0.7.0-1
- Initial omedora build of hyprland-protocols (adapted from solopasha/hyprlandRPM).
