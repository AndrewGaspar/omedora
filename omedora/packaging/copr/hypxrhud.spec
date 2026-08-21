# hypxrhud.spec — shared OpenXR HUD daemon and first-party producers.

%global snapshot 20260817.1
%global commit f96d0e794f9cfc3505b9f671920fd091effbc7f5
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
Source1:        hypxrhud-fedora.md

ExclusiveArch:  x86_64

BuildRequires:  cmake
BuildRequires:  dbus-daemon
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  ninja-build
BuildRequires:  systemd-rpm-macros
BuildRequires:  /usr/bin/busctl
BuildRequires:  pkgconfig(egl)
BuildRequires:  pkgconfig(gbm)
BuildRequires:  pkgconfig(glesv2)
BuildRequires:  pkgconfig(jansson)
BuildRequires:  pkgconfig(libdrm)
BuildRequires:  pkgconfig(libsystemd)
BuildRequires:  pkgconfig(openxr)
BuildRequires:  pkgconfig(xkbcommon)

Requires:       dbus

Provides:       bundled(stb)

%description
hypxrhud is a D-Bus-activated OpenXR overlay daemon shared by HypXRland
clients. The companion battery process publishes WiVRn headset and UPower
laptop gauges to the HUD. Static, manually started producers add a
privacy-visible ShowMeTheKey keystroke overlay and a hyprctl command ticker;
the keystroke producer remains inactive when /usr/bin/showmethekey-cli is not
installed.

%prep
%autosetup -n hypxrhud-%{commit} -p1
cp %{SOURCE1} hypxrhud-fedora.md

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
%systemd_user_post hypxrhud.service hypxrhud-battery.service hypxrhud-keys.service hypxrhud-cmdlog.service

%preun
%systemd_user_preun hypxrhud.service hypxrhud-battery.service hypxrhud-keys.service hypxrhud-cmdlog.service

%postun
%systemd_user_postun hypxrhud.service hypxrhud-battery.service hypxrhud-keys.service hypxrhud-cmdlog.service

%files
%license LICENSE
%doc hypxrhud-fedora.md README.md docs/*.md
%{_bindir}/hypxrhud
%{_bindir}/hypxrhud-battery
%{_bindir}/hypxrhud-keys
%{_bindir}/hypxrhud-cmdlog
%{_userunitdir}/hypxrhud.service
%{_userunitdir}/hypxrhud-battery.service
%{_userunitdir}/hypxrhud-keys.service
%{_userunitdir}/hypxrhud-cmdlog.service
%{_datadir}/dbus-1/services/io.github.andrewgaspar.hypxrhud.service
%{_datadir}/hypxrhud/examples/
%{_datadir}/hypxrhud/shim/

%changelog
* Mon Aug 17 2026 omedora <noreply@omedora> - 0^20260817.1.gitf96d0e794-1
- Refresh to the UTC-dated current public master tip.
- Add the static keystroke and command-ticker producers, their user units,
  example configurations, documentation, and staged hyprctl shim.
- Build the keystroke producer against xkbcommon; it remains inactive without
  the separately installed ShowMeTheKey backend.
- Install busctl in the buildroot for the command-ticker D-Bus integration test.

* Tue Jul 14 2026 omedora <noreply@omedora> - 0^20260714.1.git4799bc427-1
- Initial snapshot package with D-Bus activation and user services.
- Require the Fedora D-Bus runtime that owns the user-session bus units.
