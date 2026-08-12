# hypxrpaper.spec — ambient OpenXR background client for HypXRland.

%global snapshot 20260704.1
%global commit 5cae848cd4540df24d1901447cdd0060491069e6
%global shortcommit %(c=%{commit}; echo ${c:0:9})

Name:           hypxrpaper
Version:        0^%{snapshot}.git%{shortcommit}
Release:        1%{?dist}
Summary:        Ambient panorama and scene client for OpenXR

# Project code: BSD-3-Clause
# bundled stb_image and cgltf: MIT
# bundled forest-clearing assets: CC0-1.0
License:        BSD-3-Clause AND MIT AND CC0-1.0
URL:            https://github.com/AndrewGaspar/hypxrpaper
Source0:        %{url}/archive/%{commit}/%{name}-%{commit}.tar.gz

ExclusiveArch:  x86_64

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  ninja-build
BuildRequires:  pkgconfig(egl)
BuildRequires:  pkgconfig(gbm)
BuildRequires:  pkgconfig(glesv2)
BuildRequires:  pkgconfig(libdrm)
BuildRequires:  pkgconfig(openxr)

Provides:       bundled(cgltf)
Provides:       bundled(stb)

%description
hypxrpaper owns a primary OpenXR session and renders either a panorama, a
procedural sky, or a static glTF scene behind HypXRland's overlay monitors.
The package includes the project's CC0 forest-clearing scene.

%prep
%autosetup -n hypxrpaper-%{commit} -p1

%build
%cmake -GNinja -DCMAKE_BUILD_TYPE=Release
%cmake_build

%install
%cmake_install
install -d %{buildroot}%{_datadir}/hypxrpaper/scenes
cp -a assets/forest-clearing \
  %{buildroot}%{_datadir}/hypxrpaper/scenes/

%check
%{buildroot}%{_bindir}/hypxrpaper --help 2>&1 | grep -F -- '--scene'

%files
%license LICENSE assets/forest-clearing/ATTRIBUTION.md
%doc README.md
%{_bindir}/hypxrpaper
%{_datadir}/hypxrpaper/

%changelog
* Sat Jul 04 2026 omedora <noreply@omedora> - 0^20260704.1.git5cae848cd-1
- Initial snapshot package with the bundled forest-clearing scene.
