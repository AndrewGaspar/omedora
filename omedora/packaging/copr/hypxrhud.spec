# hypxrhud.spec — shared OpenXR HUD daemon and battery client.

%global snapshot 20260714.1
%global commit 4799bc42721f11fca9b02fcad004062087c31947
%global shortcommit %(c=%{commit}; echo ${c:0:9})

Name:           hypxrhud
Version:        0^%{snapshot}.git%{shortcommit}
Release:        1%{?dist}
Summary:        Shared OpenXR HUD daemon for HypXRland

# Project code: BSD-3-Clause
# bundled stb headers: MIT
# embedded Liberation Mono font: OFL-1.1
License:        BSD-3-Clause AND MIT AND OFL-1.1
URL:            https://github.com/AndrewGaspar/hypxrhud
Source0:        %{url}/archive/%{commit}/%{name}-%{commit}.tar.gz

ExclusiveArch:  x86_64

BuildRequires:  cmake
BuildRequires:  dbus-daemon
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  ninja-build
BuildRequires:  systemd-rpm-macros
BuildRequires:  pkgconfig(egl)
BuildRequires:  pkgconfig(gbm)
BuildRequires:  pkgconfig(glesv2)
BuildRequires:  pkgconfig(jansson)
BuildRequires:  pkgconfig(libdrm)
BuildRequires:  pkgconfig(libsystemd)
BuildRequires:  pkgconfig(openxr)

Requires:       dbus

Provides:       bundled(stb)

%description
hypxrhud is a D-Bus-activated OpenXR overlay daemon shared by HypXRland
clients. The companion battery process publishes WiVRn headset and UPower
laptop gauges to the HUD.

%prep
%autosetup -n hypxrhud-%{commit} -p1

%build
%cmake -GNinja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=%{_prefix}
grep -q '^xrdeps_FOUND:INTERNAL=1$' %{__cmake_builddir}/CMakeCache.txt
%cmake_build

%install
%cmake_install
# Use RPM's canonical license location rather than the CMake-installed copy.
rm -rf %{buildroot}%{_datadir}/licenses/hypxrhud

%check
%ctest

%post
%systemd_user_post hypxrhud.service hypxrhud-battery.service

%preun
%systemd_user_preun hypxrhud.service hypxrhud-battery.service

%postun
%systemd_user_postun hypxrhud.service hypxrhud-battery.service

%files
%license LICENSE
%doc README.md examples/battery.toml
%{_bindir}/hypxrhud
%{_bindir}/hypxrhud-battery
%{_userunitdir}/hypxrhud.service
%{_userunitdir}/hypxrhud-battery.service
%{_datadir}/dbus-1/services/io.github.andrewgaspar.hypxrhud.service
%{_datadir}/hypxrhud/

%changelog
* Tue Jul 14 2026 omedora <noreply@omedora> - 0^20260714.1.git4799bc427-1
- Initial snapshot package with D-Bus activation and user services.
- Require the Fedora D-Bus runtime that owns the user-session bus units.
