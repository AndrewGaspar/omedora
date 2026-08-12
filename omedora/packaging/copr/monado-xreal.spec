# monado-xreal.spec — private XREAL Air runtime for HypXRland.

%global snapshot 20260719.1
%global commit 3752d437c5c0b24df659ac749629ac8ead7e1bae
%global shortcommit %(c=%{commit}; echo ${c:0:9})

Name:           monado-xreal
Version:        25.1.0^%{snapshot}.git%{shortcommit}
Release:        2%{?dist}
Summary:        HypXRland Monado runtime for XREAL Air displays

License:        BSL-1.0 AND Apache-2.0 AND BSD-3-Clause AND MIT
URL:            https://github.com/AndrewGaspar/monado
Source0:        %{url}/archive/%{commit}/%{name}-%{commit}.tar.gz
Source1:        monado-xreal.service
Source2:        openxr_monado-xreal.json

ExclusiveArch:  x86_64

BuildRequires:  cmake
BuildRequires:  cjson-devel
BuildRequires:  eigen3-devel
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  glslang
BuildRequires:  libcap
BuildRequires:  ninja-build
BuildRequires:  python3
BuildRequires:  libshaderc-devel
BuildRequires:  spirv-tools
BuildRequires:  systemd-rpm-macros
BuildRequires:  vulkan-headers
BuildRequires:  wayland-protocols-devel
BuildRequires:  pkgconfig(egl)
BuildRequires:  pkgconfig(glesv2)
BuildRequires:  pkgconfig(hidapi-hidraw)
BuildRequires:  pkgconfig(libdrm)
BuildRequires:  pkgconfig(libudev)
BuildRequires:  pkgconfig(vulkan)
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-scanner)
BuildRequires:  pkgconfig(x11-xcb)
BuildRequires:  pkgconfig(xcb)
BuildRequires:  pkgconfig(xcb-randr)
BuildRequires:  pkgconfig(xrandr)

# Fedora's xr-hardware rules grant the active seat access to the XREAL HID
# interfaces. 1.1.2 is the first Fedora 44 build that includes Air Ultra
# (3318:0426) alongside Air/Air 2/Air 2 Pro.
Requires:       xr-hardware >= 1.1.2

%description
This package builds the HypXRland-pinned Monado fork as an XREAL Air runtime:
the XREAL HID driver, real Vulkan compositor, and Wayland window/direct
backends. Its service, libraries, IPC socket, and manifest have private names
so it can be installed alongside the WiVRn runtime.

The service binary deliberately has no file capabilities. A file capability
puts the Vulkan loader into secure-execution mode and prevents the per-machine
GPU ICD selection required by hybrid-GPU XREAL systems.

%prep
%autosetup -n monado-%{commit} -p1

%build
export CXXFLAGS="%{build_cxxflags} -include cstdint"
%cmake \
  -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTING=OFF \
  -DGIT_DESC=%{shortcommit} \
  -DXRT_BUILD_DRIVER_ARDUINO=OFF \
  -DXRT_BUILD_DRIVER_BLUBUR_S1=OFF \
  -DXRT_BUILD_DRIVER_DAYDREAM=OFF \
  -DXRT_BUILD_DRIVER_EUROC=OFF \
  -DXRT_BUILD_DRIVER_HDK=OFF \
  -DXRT_BUILD_DRIVER_HYDRA=OFF \
  -DXRT_BUILD_DRIVER_NS=OFF \
  -DXRT_BUILD_DRIVER_OHMD=OFF \
  -DXRT_BUILD_DRIVER_OPENGLOVES=OFF \
  -DXRT_BUILD_DRIVER_PSMV=OFF \
  -DXRT_BUILD_DRIVER_PSSENSE=OFF \
  -DXRT_BUILD_DRIVER_PSVR=OFF \
  -DXRT_BUILD_DRIVER_PSVR2=OFF \
  -DXRT_BUILD_DRIVER_QWERTY=OFF \
  -DXRT_BUILD_DRIVER_REMOTE=OFF \
  -DXRT_BUILD_DRIVER_RIFT=OFF \
  -DXRT_BUILD_DRIVER_RIFT_S=OFF \
  -DXRT_BUILD_DRIVER_ROKID=OFF \
  -DXRT_BUILD_DRIVER_SIMULATED=OFF \
  -DXRT_BUILD_DRIVER_SOLARXR=OFF \
  -DXRT_BUILD_DRIVER_STEAMVR_LIGHTHOUSE=OFF \
  -DXRT_BUILD_DRIVER_SURVIVE=OFF \
  -DXRT_BUILD_DRIVER_TWRAP=OFF \
  -DXRT_BUILD_DRIVER_VF=OFF \
  -DXRT_BUILD_DRIVER_VIVE=OFF \
  -DXRT_BUILD_DRIVER_WMR=OFF \
  -DXRT_BUILD_DRIVER_XREAL_AIR=ON \
  -DXRT_BUILD_SAMPLES=OFF \
  -DXRT_FEATURE_DEBUG_GUI=OFF \
  -DXRT_FEATURE_RENDERDOC=OFF \
  -DXRT_FEATURE_SERVICE=ON \
  -DXRT_FEATURE_SERVICE_SYSTEMD=OFF \
  -DXRT_FEATURE_SLAM=OFF \
  -DXRT_FEATURE_STEAMVR_PLUGIN=OFF \
  -DXRT_FEATURE_WINDOW_PEEK=OFF \
  -DXRT_HAVE_DBUS=OFF \
  -DXRT_HAVE_HIDAPI=ON \
  -DXRT_HAVE_LIBUDEV=ON \
  -DXRT_HAVE_OPENCV=OFF \
  -DXRT_HAVE_SYSTEM_CJSON=ON \
  -DXRT_HAVE_SYSTEMD=OFF \
  -DXRT_HAVE_WAYLAND=ON \
  -DXRT_HAVE_WAYLAND_DIRECT=ON \
  -DXRT_INSTALL_SYSTEMD_UNIT_FILES=OFF \
  -DXRT_IPC_MSG_SOCK_FILENAME=monado-xreal/comp_ipc \
  -DXRT_IPC_SERVICE_PID_FILENAME=monado-xreal.pid \
  -DXRT_MODULE_COMPOSITOR_MAIN=ON \
  -DXRT_MODULE_COMPOSITOR_NULL=OFF \
  -DXRT_MODULE_MONADO_CLI=OFF \
  -DXRT_MODULE_MONADO_GUI=OFF \
  -DXRT_OXR_RUNTIME_SUFFIX=monado_xreal
ninja-build -C %{__cmake_builddir} %{?_smp_mflags} \
  monado-service openxr_monado_xreal monado

%install
install -Dpm0755 \
  %{__cmake_builddir}/src/xrt/targets/service/monado-service \
  %{buildroot}%{_libexecdir}/monado-xreal/monado-service
install -Dpm0755 \
  %{__cmake_builddir}/src/xrt/targets/openxr/libopenxr_monado_xreal.so \
  %{buildroot}%{_libdir}/monado-xreal/libopenxr_monado_xreal.so
install -Dpm0755 \
  %{__cmake_builddir}/src/xrt/targets/libmonado/libmonado.so.25.1.0 \
  %{buildroot}%{_libdir}/monado-xreal/libmonado.so.25.1.0
ln -s libmonado.so.25.1.0 \
  %{buildroot}%{_libdir}/monado-xreal/libmonado.so.25
ln -s libmonado.so.25 \
  %{buildroot}%{_libdir}/monado-xreal/libmonado.so
install -Dpm0644 %{SOURCE1} \
  %{buildroot}%{_userunitdir}/monado-xreal.service
install -Dpm0644 %{SOURCE2} \
  %{buildroot}%{_datadir}/openxr/1/openxr_monado-xreal.json

%check
grep -q '^XRT_BUILD_DRIVER_XREAL_AIR:BOOL=ON$' \
  %{__cmake_builddir}/CMakeCache.txt
grep -q '^XRT_HAVE_WAYLAND:BOOL=ON$' \
  %{__cmake_builddir}/CMakeCache.txt
grep -F '%{_libdir}/monado-xreal/libopenxr_monado_xreal.so' %{SOURCE2}
! getcap %{buildroot}%{_libexecdir}/monado-xreal/monado-service | grep -q .

%post
%systemd_user_post monado-xreal.service

%preun
%systemd_user_preun monado-xreal.service

%postun
%systemd_user_postun monado-xreal.service

%files
%license LICENSE
%doc README.md
%{_libexecdir}/monado-xreal/
%{_libdir}/monado-xreal/
%{_userunitdir}/monado-xreal.service
%{_datadir}/openxr/1/openxr_monado-xreal.json

%changelog
* Wed Aug 12 2026 omedora <noreply@omedora> - 25.1.0^20260719.1.git3752d437c-2
- Require Fedora's current xr-hardware udev rules for all supported XREAL Air
  product IDs, including Air Ultra.

* Sun Jul 19 2026 omedora <noreply@omedora> - 25.1.0^20260719.1.git3752d437c-1
- Initial private XREAL Air runtime from HypXRland's pinned Monado fork.
