# hypxrva.spec — VA-API decode gate used by HypXRland sessions.

%global snapshot 20260803.1
%global commit bba2c5f8b733eaab347e11460a25df8f62e53866
%global shortcommit %(c=%{commit}; echo ${c:0:9})

Name:           hypxrva
Version:        0^%{snapshot}.git%{shortcommit}
Release:        1%{?dist}
Summary:        Dynamic VA-API decode gate for HypXRland

License:        BSD-3-Clause
URL:            https://github.com/AndrewGaspar/hypxrva
Source0:        %{url}/archive/%{commit}/%{name}-%{commit}.tar.gz

ExclusiveArch:  x86_64

BuildRequires:  cmake
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  ninja-build
BuildRequires:  pkgconfig(libva)
BuildRequires:  pkgconfig(libva-drm)

# The shim is loaded by libva rather than linked to it, so automatic ELF
# dependency generation cannot discover this relationship.
Requires:       libva%{?_isa}

%description
hypxrva interposes a private VA-API driver and blocks hardware video decode
while an XR headset is donned. Its watcher follows HypXRland monitor state and
its probe utility reports the selected real driver.

The shim deliberately lives alone in %{_libdir}/hypxrva. An XR session selects
it with LIBVA_DRIVER_NAME=hypxr and LIBVA_DRIVERS_PATH=%{_libdir}/hypxrva.

%prep
%autosetup -n hypxrva-%{commit} -p1

%build
%cmake -GNinja -DCMAKE_BUILD_TYPE=Release
%cmake_build

%install
# Upstream's user-local installer hard-codes lib/hypxrva. Install the shim
# manually into Fedora's architecture library directory and the tools normally.
install -Dpm0755 %{__cmake_builddir}/hypxr_drv_video.so \
  %{buildroot}%{_libdir}/hypxrva/hypxr_drv_video.so
install -Dpm0755 %{__cmake_builddir}/hypxrva-watcher \
  %{buildroot}%{_bindir}/hypxrva-watcher
install -Dpm0755 %{__cmake_builddir}/hypxrva-vaprobe \
  %{buildroot}%{_bindir}/hypxrva-vaprobe

%check
HYPXRVA_GPU_TESTS=0 %ctest

%files
%license LICENSE
%doc README.md
%{_bindir}/hypxrva-watcher
%{_bindir}/hypxrva-vaprobe
%dir %{_libdir}/hypxrva
%{_libdir}/hypxrva/hypxr_drv_video.so

%changelog
* Mon Aug 03 2026 omedora <noreply@omedora> - 0^20260803.1.gitbba2c5f8b-1
- Initial snapshot package; keep the interposer isolated in lib64/hypxrva.
