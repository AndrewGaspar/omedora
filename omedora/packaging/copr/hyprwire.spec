# hyprwire.spec — fast wire protocol for IPC, used across hyprwm (omedora).
#
# BuildRequired by newer Hyprland. Not in Fedora 44. Adapted from
# solopasha/hyprlandRPM. omedora conventions: pinned Version, explicit Release +
# changelog, soname via glob.

Name:           hyprwire
Version:        0.3.1
Release:        2%{?dist}
Summary:        A fast and consistent wire protocol for IPC

License:        BSD-3-Clause
URL:            https://github.com/hyprwm/hyprwire
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

# https://fedoraproject.org/wiki/Changes/EncourageI686LeafRemoval
ExcludeArch:    %{ix86}

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  ninja-build
BuildRequires:  pkgconfig(hyprutils)
BuildRequires:  pkgconfig(libffi)
BuildRequires:  pkgconfig(pugixml)

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
%cmake -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DBUILD_TESTING=OFF
%cmake_build

%install
%cmake_install

%files
%license LICENSE
%doc README.md
%{_libdir}/lib%{name}.so.*

%files devel
%{_bindir}/%{name}-scanner
%{_includedir}/%{name}/
%{_libdir}/cmake/%{name}-scanner/
%{_libdir}/lib%{name}.so
%{_libdir}/pkgconfig/%{name}.pc
%{_libdir}/pkgconfig/%{name}-scanner.pc

%changelog
* Mon Aug 03 2026 omedora <noreply@omedora> - 0.3.1-2
- Rebuild against hyprutils 0.14.0 (libhyprutils SONAME 12 -> 13).

* Sat May 30 2026 omedora <noreply@omedora> - 0.3.1-1
- Initial omedora build of hyprwire 0.3.1 (adapted from solopasha/hyprlandRPM).
