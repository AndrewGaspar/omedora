# monado-xreal.spec — private XREAL Air runtime for HypXRland.

%global snapshot 20261016.2
%global commit 613d8eeb1e29be2b208a3b0eff2f5826f4bef983
%global shortcommit %(c=%{commit}; echo ${c:0:9})

Name:           monado-xreal
Version:        25.1.0^%{snapshot}.git%{shortcommit}
Release:        5%{?dist}
Summary:        HypXRland Monado runtime for XREAL Air displays

License:        BSL-1.0 AND Apache-2.0 AND BSD-3-Clause AND MIT
URL:            https://github.com/AndrewGaspar/monado
Source0:        %{url}/archive/%{commit}/%{name}-%{commit}.tar.gz
Source1:        monado-xreal.service
Source2:        openxr_monado-xreal.json
Source3:        monado-xreal.README.package.md
# A stopgap: keep the runtime off the "power-saver" profile while it runs.
Source4:        monado-xreal-avoid-power-saver.service
Source5:        monado-xreal-avoid-power-saver

ExclusiveArch:  x86_64

BuildRequires:  cmake
BuildRequires:  cmake(OpenCV)
BuildRequires:  cjson-devel
BuildRequires:  eigen3-devel
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  glslang
BuildRequires:  libcap
BuildRequires:  ninja-build
BuildRequires:  python3
# %%check runs the power-saver helper, which talks to the daemon with busctl.
BuildRequires:  /usr/bin/busctl
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
# %%check confirms the unit's VIT library and settings paths are the ones
# basalt-xreal installs.
BuildRequires:  basalt-xreal >= 0^20261015.gite3dec7b44

# Fedora's xr-hardware rules grant the active seat access to the XREAL HID
# interfaces. 1.1.2 is the first Fedora 44 build that includes Air Ultra
# (3318:0426) alongside Air/Air 2/Air 2 Pro.
Requires:       xr-hardware >= 1.1.2
# The opt-in 6DoF path loads Basalt's VIT library from basalt-xreal (the unit
# points VIT_SYSTEM_LIBRARY_PATH there). A hard dependency, not Recommends:
# Omedora installs packages with weak dependencies off, and turning 6DoF on
# should take only XREAL_AIR_SLAM=1. The floor exports basalt_vit_restartable.
Requires:       basalt-xreal >= 0^20261015.gite3dec7b44
# The power-saver helper reads and sets the PowerProfiles daemon's profile
# (tuned-ppd on Fedora) with busctl.
Requires:       /usr/bin/busctl

%description
This package builds the HypXRland-pinned Monado fork as an XREAL Air runtime:
the XREAL HID driver, real Vulkan compositor, and Wayland window/direct
backends. Its service, libraries, IPC socket, and manifest have private names
so it can be installed alongside the WiVRn runtime.

Tracking is 3DoF by default. The opt-in 6DoF path runs visual-inertial SLAM
through the Basalt tracker in basalt-xreal, which the user unit already points
at: set XREAL_AIR_SLAM=1 in a drop-in to enable it, and XREAL_AIR_PLANES=1 on
top for XR_EXT_plane_detection (horizontal planes). monado-cli, with the
xreal-slam-replay and plane-map-replay commands for recordings, is installed
privately under %{_libexecdir}/monado-xreal. See README.package.md.

The service binary deliberately has no file capabilities. A file capability
puts the Vulkan loader into secure-execution mode and prevents the per-machine
GPU ICD selection required by hybrid-GPU XREAL systems.

While the runtime runs, monado-xreal-avoid-power-saver.service switches the
"power-saver" power profile, which turns turbo off, to "balanced", and
switches it back when the runtime stops (tuned-ppd or power-profiles-daemon).
Any other profile is left alone. The runtime starts unchanged if no daemon
allows the switch. Mask that unit to turn it off.

%prep
%autosetup -n monado-%{commit} -p1
cp -p %{SOURCE3} README.package.md

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
  -DXRT_FEATURE_OPENXR_PLANE_DETECTION=ON \
  -DXRT_FEATURE_RENDERDOC=OFF \
  -DXRT_FEATURE_SERVICE=ON \
  -DXRT_FEATURE_SERVICE_SYSTEMD=OFF \
  -DXRT_FEATURE_SLAM=ON \
  -DXRT_FEATURE_STEAMVR_PLUGIN=OFF \
  -DXRT_FEATURE_WINDOW_PEEK=OFF \
  -DXRT_HAVE_DBUS=OFF \
  -DXRT_HAVE_HIDAPI=ON \
  -DXRT_HAVE_LIBUDEV=ON \
  -DXRT_HAVE_OPENCV=ON \
  -DXRT_HAVE_SYSTEM_CJSON=ON \
  -DXRT_HAVE_SYSTEMD=OFF \
  -DXRT_HAVE_WAYLAND=ON \
  -DXRT_HAVE_WAYLAND_DIRECT=ON \
  -DXRT_INSTALL_SYSTEMD_UNIT_FILES=OFF \
  -DXRT_IPC_MSG_SOCK_FILENAME=monado-xreal/comp_ipc \
  -DXRT_IPC_SERVICE_PID_FILENAME=monado-xreal.pid \
  -DXRT_MODULE_COMPOSITOR_MAIN=ON \
  -DXRT_MODULE_COMPOSITOR_NULL=OFF \
  -DXRT_MODULE_MONADO_CLI=ON \
  -DXRT_MODULE_MONADO_GUI=OFF \
  -DXRT_OXR_RUNTIME_SUFFIX=monado_xreal
ninja-build -C %{__cmake_builddir} %{?_smp_mflags} \
  monado-service openxr_monado_xreal monado cli

%install
install -Dpm0755 \
  %{__cmake_builddir}/src/xrt/targets/service/monado-service \
  %{buildroot}%{_libexecdir}/monado-xreal/monado-service
install -Dpm0755 \
  %{__cmake_builddir}/src/xrt/targets/cli/monado-cli \
  %{buildroot}%{_libexecdir}/monado-xreal/monado-cli
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
install -Dpm0644 %{SOURCE4} \
  %{buildroot}%{_userunitdir}/monado-xreal-avoid-power-saver.service
install -Dpm0755 %{SOURCE5} \
  %{buildroot}%{_libexecdir}/monado-xreal/avoid-power-saver

%check
grep -q '^XRT_BUILD_DRIVER_XREAL_AIR:BOOL=ON$' \
  %{__cmake_builddir}/CMakeCache.txt
grep -q '^XRT_HAVE_WAYLAND:BOOL=ON$' \
  %{__cmake_builddir}/CMakeCache.txt
grep -q '^XRT_FEATURE_SLAM:BOOL=ON$' \
  %{__cmake_builddir}/CMakeCache.txt
grep -q '^XRT_FEATURE_OPENXR_PLANE_DETECTION:BOOL=ON$' \
  %{__cmake_builddir}/CMakeCache.txt
# 6DoF: the unit points at basalt-xreal's library and settings (both must
# exist as installed by the BuildRequires'd package) and never enables SLAM or
# planes itself.
unit=%{buildroot}%{_userunitdir}/monado-xreal.service
vit=$(sed -n 's/^Environment=VIT_SYSTEM_LIBRARY_PATH=//p' "$unit")
slam_config=$(sed -n 's/^Environment=XREAL_AIR_SLAM_CONFIG=//p' "$unit")
[[ $vit == %{_libdir}/basalt-xreal/libbasalt.so.2 ]]
[[ $slam_config == %{_datadir}/basalt-xreal/xreal_air.toml ]]
test -e "$vit"
test -f "$slam_config"
if grep -qE '^Environment=XREAL_AIR_(SLAM|PLANES)=' "$unit"; then
  exit 1
fi
%{buildroot}%{_libexecdir}/monado-xreal/monado-cli 2>&1 | grep -q xreal-slam-replay
grep -F '%{_libdir}/monado-xreal/libopenxr_monado_xreal.so' %{SOURCE2}
# No file capabilities: they would put the Vulkan loader in secure-execution
# mode. `! cmd` never trips rpm's `sh -e`, so the check exits by hand. The
# assignment fails the build if getcap itself fails.
caps=$(getcap %{buildroot}%{_libexecdir}/monado-xreal/monado-service)
if [[ -n $caps ]]; then
  exit 1
fi
# The runtime pulls the power-saver unit in without depending on it, and that
# unit is bound to the runtime, so its ExecStop= runs however the runtime
# ends. The helper fails open: with no PowerProfiles daemon (none runs in a
# build root) both steps log and exit 0.
grep -qx 'Wants=monado-xreal-avoid-power-saver.service' "$unit"
avoid_unit=%{buildroot}%{_userunitdir}/monado-xreal-avoid-power-saver.service
grep -qx 'BindsTo=monado-xreal.service' "$avoid_unit"
grep -qx 'ExecStart=%{_libexecdir}/monado-xreal/avoid-power-saver enter' "$avoid_unit"
grep -qx 'ExecStop=%{_libexecdir}/monado-xreal/avoid-power-saver leave' "$avoid_unit"
mkdir -p avoid-power-saver-rt
for step in enter leave; do
  RUNTIME_DIRECTORY=$PWD/avoid-power-saver-rt \
    DBUS_SYSTEM_BUS_ADDRESS="unix:path=$PWD/no-such-bus" \
    timeout 30 %{buildroot}%{_libexecdir}/monado-xreal/avoid-power-saver "$step"
done

%post
%systemd_user_post monado-xreal.service

%preun
%systemd_user_preun monado-xreal.service

%postun
%systemd_user_postun monado-xreal.service

%files
%license LICENSE
%doc README.md README.package.md
%{_libexecdir}/monado-xreal/
%{_libdir}/monado-xreal/
%{_userunitdir}/monado-xreal.service
%{_userunitdir}/monado-xreal-avoid-power-saver.service
%{_datadir}/openxr/1/openxr_monado-xreal.json

%changelog
* Mon Nov 02 2026 omedora <noreply@omedora> - 25.1.0^20261016.2.git613d8eeb1-5
- Replace the "performance" hold with monado-xreal-avoid-power-saver.service:
  on a laptop whose CPU and GPU share one power limit, performance pinned
  every core at full clock and throttled the iGPU, so the compositor missed
  frames (#14). The new unit, still bound to the runtime, switches
  power-saver to balanced while the runtime runs and restores power-saver
  when it stops, crashes or is killed, unless the profile was changed in the
  meantime. Other profiles, and a power-saver another application holds, are
  left alone. The helper is a busctl shell script, so the package no longer
  requires python3-gobject-base. The unit also stops a -4 hold left running
  by an upgrade. Mask the unit to turn it off.

* Mon Nov 02 2026 omedora <noreply@omedora> - 25.1.0^20261016.2.git613d8eeb1-4
- Hold the "performance" power profile while the runtime runs, a stopgap until
  Monado runs well without turbo: monado-xreal.service pulls in the new
  monado-xreal-performance-hold.service (Wants=), which is bound to it and runs
  %%{_libexecdir}/monado-xreal/performance-hold. The helper holds through the
  PowerProfiles API until stopped and fails open. It replaces the session-long
  hold in hypxrland-omedora. Mask the unit to turn it off.

* Mon Nov 02 2026 omedora <noreply@omedora> - 25.1.0^20261016.2.git613d8eeb1-3
- Give the user unit CPUWeight=1000, so the runtime wins CPU against the
  session's other apps, and ManagedOOMPreference=avoid, which systemd-oomd
  honors under Fedora's per-user-slice defaults. No IOWeight=: the user
  manager has no io controller delegated. Document both in README.package.md.

* Mon Nov 02 2026 omedora <noreply@omedora> - 25.1.0^20261016.2.git613d8eeb1-2
- Make the %%check that monado-service has no file capabilities able to fail:
  rpm's sh -e ignored the bare `! getcap ...` line, and a failing getcap
  passed too.

* Sun Nov 01 2026 omedora <noreply@omedora> - 25.1.0^20261016.2.git613d8eeb1-1
- Refresh to the fork's hypxrland branch tip 613d8ee, six commits past
  HypXRland's submodule pin: opt-in horizontal plane detection
  (XR_EXT_plane_detection with an SGBM depth source, XREAL_AIR_PLANES=1 on
  top of 6DoF) and plane output in the replay CLI.
- Ship 6DoF ready to enable: require basalt-xreal and point the unit's
  VIT_SYSTEM_LIBRARY_PATH and XREAL_AIR_SLAM_CONFIG at it, so XREAL_AIR_SLAM=1
  is the only setting a user adds. 6DoF and planes stay off by default.
- Install monado-cli privately in /usr/libexec/monado-xreal for the
  xreal-slam-replay and plane-map-replay commands, and README.package.md.

* Sun Nov 01 2026 omedora <noreply@omedora> - 25.1.0^20261016.1.git6e23edfb3-2
- Create the IPC socket directory with RuntimeDirectory=monado-xreal: the
  service failed to bind $XDG_RUNTIME_DIR/monado-xreal/comp_ipc on a fresh
  login because nothing created the directory.

* Fri Oct 16 2026 omedora <noreply@omedora> - 25.1.0^20261016.1.git6e23edfb3-1
- Refresh to the current HypXRland-pinned Monado tip: XREAL SLAM robustness
  (wear hold, divergence restarts, pose guard), per-serial gyro-bias
  persistence, Air 2 Ultra SLAM camera capture, and presence starting worn.
- Build with XRT_FEATURE_SLAM and OpenCV so the opt-in 6DoF path
  (XREAL_AIR_SLAM=1 with a user-built Basalt via VIT_SYSTEM_LIBRARY_PATH) is
  available; the default remains 3DoF and no Basalt library is shipped.

* Wed Aug 12 2026 omedora <noreply@omedora> - 25.1.0^20260719.1.git3752d437c-2
- Require Fedora's current xr-hardware udev rules for all supported XREAL Air
  product IDs, including Air Ultra.

* Sun Jul 19 2026 omedora <noreply@omedora> - 25.1.0^20260719.1.git3752d437c-1
- Initial private XREAL Air runtime from HypXRland's pinned Monado fork.
