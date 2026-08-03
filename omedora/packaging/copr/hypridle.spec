# hypridle.spec — Hyprland's idle daemon (omedora).
#
# Adapted from solopasha/hyprlandRPM. Deviation: use Fedora 44's system
# sdbus-cpp 2.2.1 (pkgconfig(sdbus-c++)) rather than bundling/static-linking
# sdbus-cpp 2.1.0. omedora conventions: pinned Version, explicit Release +
# changelog. Ships the hypridle user unit (omedora drives idle via its own
# config; the daemon is the same binary).

Name:           hypridle
Version:        0.1.8
Release:        1%{?dist}
Summary:        Hyprland's idle daemon
License:        BSD-3-Clause
URL:            https://github.com/hyprwm/hypridle
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

# https://fedoraproject.org/wiki/Changes/EncourageI686LeafRemoval
ExcludeArch:    %{ix86}

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  systemd-rpm-macros

BuildRequires:  cmake(hyprwayland-scanner)
BuildRequires:  pkgconfig(hyprland-protocols)
BuildRequires:  pkgconfig(hyprlang)
BuildRequires:  pkgconfig(hyprutils)
BuildRequires:  pkgconfig(libsystemd)
BuildRequires:  pkgconfig(sdbus-c++)
BuildRequires:  pkgconfig(systemd)
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-protocols)

%description
%{summary}.

%prep
%autosetup -p1

%build
%cmake
%cmake_build

%install
%cmake_install
rm %{buildroot}%{_datadir}/hypr/hypridle.conf

%files
%license LICENSE
%doc README.md assets/example.conf
%{_bindir}/%{name}
%{_userunitdir}/%{name}.service

%post
%systemd_user_post %{name}.service

%preun
%systemd_user_preun %{name}.service

%postun
%systemd_user_postun %{name}.service

%changelog
* Mon Aug 03 2026 omedora <noreply@omedora> - 0.1.8-1
- Update to hypridle 0.1.8 (Hyprland 0.56.1 wave).
- Rebuilt against hyprutils 0.14.0 (SONAME 13).

* Sat May 30 2026 omedora <noreply@omedora> - 0.1.7-1
- Initial omedora build of hypridle 0.1.7 (adapted from solopasha/hyprlandRPM).
- Uses Fedora's system sdbus-c++ 2.2.1 instead of bundling sdbus-cpp.
