# hyprwayland-scanner.spec — Hyprland's C++ wayland-scanner (omedora).
#
# Build-time code generator: many hypr* components BR cmake(hyprwayland-scanner).
# Not in Fedora 44. Adapted from solopasha/hyprlandRPM. omedora conventions:
# pinned Version, explicit Release + changelog.

Name:           hyprwayland-scanner
Version:        0.4.6
Release:        1%{?dist}
Summary:        A Hyprland implementation of wayland-scanner, in and for C++

License:        BSD-3-Clause
URL:            https://github.com/hyprwm/hyprwayland-scanner
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

# https://fedoraproject.org/wiki/Changes/EncourageI686LeafRemoval
ExcludeArch:    %{ix86}

BuildRequires:  cmake
BuildRequires:  cmake(pugixml)
BuildRequires:  gcc-c++

%description
%{summary}.

%package        devel
Summary:        A Hyprland implementation of wayland-scanner, in and for C++
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
%{_bindir}/%{name}
%{_libdir}/pkgconfig/%{name}.pc
%{_libdir}/cmake/%{name}/

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 0.4.6-1
- Initial omedora build of hyprwayland-scanner 0.4.6 (adapted from solopasha/hyprlandRPM).
