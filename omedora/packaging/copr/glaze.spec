# glaze.spec — header-only C++ JSON/reflection library (omedora).
#
# BuildRequire-only dependency of Hyprland (hyprland BR glaze-static). Not in
# Fedora 44 / RPM Fusion, so omedora vendors it. Adapted from solopasha's
# Fedora spec set (github.com/solopasha/hyprlandRPM) — the maintained spec set
# the dropped lionheartp/Hyprland COPR forked. Converted to omedora conventions:
# pinned Version (no rpmautospec %autorelease/%autochangelog), explicit
# Release + %changelog.
#
# Header-only: only a -devel (noarch) subpackage with the headers + cmake glue.

%global debug_package %{nil}

Name:           glaze
Version:        5.5.2
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
* Sat May 30 2026 omedora <noreply@omedora> - 5.5.2-1
- Initial omedora build of glaze (adapted from solopasha/hyprlandRPM).
- BuildRequire-only header lib for Hyprland; not in Fedora/RPM Fusion.
