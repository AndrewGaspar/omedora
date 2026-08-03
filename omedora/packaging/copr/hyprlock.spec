# hyprlock.spec — Hyprland's GPU-accelerated screen locker (omedora).
#
# Adapted from solopasha/hyprlandRPM. Deviation: Fedora 44 ships sdbus-cpp 2.2.1
# (newer than the 2.1.0 solopasha bundles), so we BuildRequire the SYSTEM
# sdbus-cpp-devel instead of vendoring + static-linking it. omedora conventions:
# pinned Version, explicit Release + changelog.

Name:           hyprlock
Version:        0.9.6
Release:        1%{?dist}
Summary:        Hyprland's GPU-accelerated screen locking utility
License:        BSD-3-Clause
URL:            https://github.com/hyprwm/hyprlock
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

# https://fedoraproject.org/wiki/Changes/EncourageI686LeafRemoval
ExcludeArch:    %{ix86}

BuildRequires:  cmake
BuildRequires:  gcc-c++

BuildRequires:  cmake(hyprwayland-scanner)
BuildRequires:  pkgconfig(cairo)
BuildRequires:  pkgconfig(egl)
BuildRequires:  pkgconfig(gbm)
BuildRequires:  pkgconfig(hyprgraphics)
BuildRequires:  pkgconfig(hyprlang)
BuildRequires:  pkgconfig(hyprutils)
BuildRequires:  pkgconfig(libdrm)
BuildRequires:  pkgconfig(libsystemd)
BuildRequires:  pkgconfig(opengl)
BuildRequires:  pkgconfig(pam)
BuildRequires:  pkgconfig(pangocairo)
BuildRequires:  pkgconfig(sdbus-c++)
BuildRequires:  pkgconfig(systemd)
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-egl)
BuildRequires:  pkgconfig(wayland-protocols)
BuildRequires:  pkgconfig(xkbcommon)

%description
%{summary}.

%prep
%autosetup -p1

%build
%cmake -DCMAKE_BUILD_TYPE=Release
%cmake_build

%install
%cmake_install
rm %{buildroot}%{_datadir}/hypr/%{name}.conf

%files
%license LICENSE
%doc README.md assets/example.conf
%{_bindir}/%{name}
%config(noreplace) %{_sysconfdir}/pam.d/%{name}

%changelog
* Mon Aug 03 2026 omedora <noreply@omedora> - 0.9.6-1
- Update to hyprlock 0.9.6 (Hyprland 0.56.1 wave).
- Rebuilt against hyprutils 0.14.0 (SONAME 13).

* Sat May 30 2026 omedora <noreply@omedora> - 0.9.5-1
- Initial omedora build of hyprlock 0.9.5 (adapted from solopasha/hyprlandRPM).
- Uses Fedora's system sdbus-c++ 2.2.1 instead of bundling sdbus-cpp.
