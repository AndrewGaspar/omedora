# hyprcursor.spec — the Hyprland cursor format, library and utilities (omedora).
#
# BuildRequired by hyprland. Fedora 44 ships a stale 0.1.11; omedora vendors
# 0.1.13 (newer EVR ⇒ auto-upgrade). Adapted from solopasha/hyprlandRPM.
# omedora conventions: pinned Version, explicit Release + changelog, soname via
# glob.

Name:           hyprcursor
Version:        0.1.13
Release:        2%{?dist}
Summary:        The hyprland cursor format, library and utilities

License:        BSD-3-Clause
URL:            https://github.com/hyprwm/hyprcursor
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

# https://fedoraproject.org/wiki/Changes/EncourageI686LeafRemoval
ExcludeArch:    %{ix86}

BuildRequires:  cmake
BuildRequires:  gcc-c++

BuildRequires:  pkgconfig(cairo)
BuildRequires:  pkgconfig(hyprlang)
BuildRequires:  pkgconfig(librsvg-2.0)
BuildRequires:  pkgconfig(libzip)
BuildRequires:  pkgconfig(tomlplusplus)

%description
%{summary}.

%package        devel
Summary:        Development files for %{name}
Requires:       %{name}%{?_isa} = %{version}-%{release}
%description    devel
Development files for %{name}.

%prep
%autosetup -p1

%build
%cmake -DCMAKE_BUILD_TYPE=Release
%cmake_build

%install
%cmake_install

%files
%license LICENSE
%doc README.md
%{_bindir}/hyprcursor-util
%{_libdir}/lib%{name}.so.*

%files devel
%{_includedir}/%{name}.hpp
%{_includedir}/%{name}/
%{_libdir}/lib%{name}.so
%{_libdir}/pkgconfig/%{name}.pc

%changelog
* Mon Aug 03 2026 omedora <noreply@omedora> - 0.1.13-2
- Rebuild against hyprutils 0.14.0 (libhyprutils SONAME 12 -> 13), pulled in
  transitively via hyprlang.

* Sat May 30 2026 omedora <noreply@omedora> - 0.1.13-1
- Initial omedora build of hyprcursor 0.1.13 (adapted from solopasha/hyprlandRPM).
- Out-versions Fedora's stale 0.1.11.
