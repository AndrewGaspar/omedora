# glaze.spec — header-only C++ JSON/reflection library (omedora).
#
# BuildRequire-only dependency of Hyprland (hyprland BR glaze-static). Not in
# Fedora 44 / RPM Fusion, so omedora vendors it. Adapted from solopasha's
# Fedora spec set (github.com/solopasha/hyprlandRPM) — the maintained spec set
# omedora's hyprwm packaging is based on. Converted to omedora conventions:
# pinned Version (no rpmautospec auto-release/auto-changelog), explicit
# Release + changelog.
#
# Header-only: only a -devel (noarch) subpackage with the headers + cmake glue.

%global debug_package %{nil}

# NOTE: Hyprland 0.55.2's `start` + main CMake require glaze in the range
# [7, 8); we therefore pin a 7.x (not solopasha's older 5.5.2, which predates
# that bump and made hyprland FetchContent-clone glaze at build time — fatal in
# the offline build root).
Name:           glaze
Version:        7.8.2
Release:        1%{?dist}
Summary:        Extremely fast, in memory, JSON and interface library

License:        MIT
URL:            https://github.com/stephenberry/glaze
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildRequires:  cmake
BuildRequires:  gcc-c++

%description
%{summary}.

%package        devel
Summary:        Development files for %{name}
BuildArch:      noarch
Provides:       %{name}-static = %{version}-%{release}
%description    devel
Development files for %{name}.

%prep
%autosetup -p1

%build
%cmake \
    -Dglaze_INSTALL_CMAKEDIR=%{_datadir}/cmake/%{name} \
    -Dglaze_DISABLE_SIMD_WHEN_SUPPORTED:BOOL=ON \
    -Dglaze_DEVELOPER_MODE:BOOL=OFF \
    -Dglaze_ENABLE_FUZZING:BOOL=OFF
%cmake_build

%install
%cmake_install

%files devel
%license LICENSE
%doc README.md
%{_datadir}/cmake/%{name}/
%{_includedir}/%{name}/

%changelog
* Tue Jun 16 2026 omedora <noreply@omedora> - 7.8.2-1
- Bump to upstream 7.8.2 (Hyprland 0.55.4 wave). Still in the 7.x range
  Hyprland's glaze-static BuildRequire needs.

* Sat May 30 2026 omedora <noreply@omedora> - 7.7.1-1
- Initial omedora build of glaze 7.7.1 (adapted from solopasha/hyprlandRPM).
- BuildRequire-only header lib for Hyprland; not in Fedora/RPM Fusion.
- Pinned to 7.x (Hyprland 0.55.2 requires glaze >=7,<8).
