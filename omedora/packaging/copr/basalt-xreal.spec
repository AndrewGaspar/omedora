# basalt-xreal.spec — Basalt VIT tracker for monado-xreal's XREAL Air 6DoF.
#
# Builds the shared VIT library (libbasalt.so) of AndrewGaspar/basalt, branch
# xreal-vit: Monado's Basalt fork (gitlab.freedesktop.org/mateosss/basalt) plus
# the XREAL Air pipeline config, a restartable/second tracker, and IMU-queue
# fixes. monado-xreal dlopens it through VIT_SYSTEM_LIBRARY_PATH when the user
# opts into 6DoF (XREAL_AIR_SLAM=1); nothing else links it.
#
# PRIVATE NAMES: the library and its data live under %%{_libdir}/basalt-xreal/
# and %%{_datadir}/basalt-xreal/, never on the linker path, so a future Fedora
# `basalt` package (or a user-built one in /usr/local) cannot collide with it.
# No headers, pkg-config file, or tools are shipped.
#
# SUBMODULES: commit archives carry no submodules, so every one the library
# build reads is its own commit-pinned SourceN (pinned in
# basalt-xreal.spec.sources) unpacked into its submodule path in %%prep. The
# pins are the gitlinks recorded in the Basalt / basalt-headers commits.
#   system (exact or compatible Fedora versions): Eigen 5.0.1 (the submodule
#     pin is 5.0.1 too), cereal 1.3.2 (= the submodule pin), TBB, OpenCV, fmt.
#   bundled (no Fedora package, or the include path is hard-wired and the
#     Fedora version differs; all header-only): basalt-headers, Sophus,
#     CLI11 2.6.2, magic_enum 0.9.7, and the in-tree nlohmann/json 3.9.1 and
#     VIT interface.
#   not fetched: Pangolin (visualization off), opengv (only the tools use it),
#     ROS/rosbag/fastcdr (dataset tools), and the test-only
#     googletest/benchmark. Patch0 lets the library-only build configure
#     without opengv and against the system cereal.
#
# BUILD SHAPE: float instantiations only. The shipped xreal_air.toml selects
# the single-precision pipeline (use-double=0), and upstream's library-only
# mode also means float-only; the double set would roughly double the compile
# time and memory of a build already known for its RAM use. LTO is off for the
# same reason. Code generation targets x86-64-v3 (AVX2/FMA) rather than the
# Fedora baseline: the tracker runs in real time on Eigen kernels, and Basalt's
# own default is -march=native.

%global commit e3dec7b4477eb25629c7d3ebc509a7e6c2d15b86
%global shortcommit %(c=%{commit}; echo ${c:0:9})
# Upstream commit date of the pin (snapshot versioning, as the hypxr specs).
%global snapshot 20261015

# Submodule pins (gitlinks at %%{commit} and at basalt-headers_commit).
%global headers_commit e6db0fb84c69614bc4923fde6c52154c221c1768
%global sophus_commit d0b7315a0d90fc6143defa54596a3a95d9fa10ec
%global cli11_commit 37bb6edc5317e99af72ef48405e65d9ca5218861
%global magic_enum_commit e046b69a3736d314fad813e159b1c192eaef92cd
%global headers_shortcommit %(c=%{headers_commit}; echo ${c:0:9})
%global sophus_shortcommit %(c=%{sophus_commit}; echo ${c:0:9})

# VIT interface version = the library's VERSION; its major is the SONAME.
%global vit_version 2.0.1
%global vit_major 2

# Template-heavy Eigen code: LTO multiplies the build's memory and time.
%global _lto_cflags %{nil}

Name:           basalt-xreal
Version:        0^%{snapshot}.git%{shortcommit}
Release:        1%{?dist}
Summary:        Basalt visual-inertial tracker for monado-xreal's XREAL Air 6DoF

# Basalt, basalt-headers, CLI11: BSD-3-Clause. Sophus, magic_enum,
# nlohmann/json: MIT. VIT interface: BSL-1.0. Eigen (system headers compiled
# in): MPL-2.0.
License:        BSD-3-Clause AND MIT AND BSL-1.0 AND MPL-2.0
URL:            https://github.com/AndrewGaspar/basalt
Source0:        %{url}/archive/%{commit}/basalt-%{commit}.tar.gz
Source1:        https://gitlab.freedesktop.org/mateosss/basalt-headers/-/archive/%{headers_commit}/basalt-headers-%{headers_commit}.tar.gz
Source2:        https://github.com/strasdat/Sophus/archive/%{sophus_commit}/Sophus-%{sophus_commit}.tar.gz
Source3:        https://github.com/CLIUtils/CLI11/archive/%{cli11_commit}/CLI11-%{cli11_commit}.tar.gz
Source4:        https://github.com/Neargye/magic_enum/archive/%{magic_enum_commit}/magic_enum-%{magic_enum_commit}.tar.gz
# Library-only build against Fedora's deps: skip configuring opengv (only the
# tools link it) and accept a system cereal (no plain `cereal` target).
Patch0:         basalt-xreal-library-build.patch

ExclusiveArch:  x86_64

BuildRequires:  cmake
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  ninja-build
BuildRequires:  cmake(OpenCV)
BuildRequires:  cereal-devel >= 1.3.2
BuildRequires:  eigen3-devel >= 5.0.1
BuildRequires:  fmt-devel
BuildRequires:  tbb-devel

Provides:       bundled(basalt-headers) = 0^git%{headers_shortcommit}
Provides:       bundled(sophus) = 1.24.6^git%{sophus_shortcommit}
Provides:       bundled(cli11) = 2.6.2
Provides:       bundled(magic_enum) = 0.9.7
Provides:       bundled(json) = 3.9.1
Provides:       bundled(vit) = %{vit_version}

%description
The Basalt visual-inertial odometry tracker, built as the VIT (visual-inertial
tracking) library monado-xreal loads for XREAL Air 6DoF tracking. It is
Monado's Basalt fork with the XREAL Air pipeline settings (xreal_air.toml and
xreal_air_config.json), restartable trackers, and non-blocking IMU queues.

The library and its settings are private to monado-xreal
(%{_libdir}/basalt-xreal, %{_datadir}/basalt-xreal). 6DoF stays opt-in: it is
used only when monado-xreal runs with XREAL_AIR_SLAM=1. The build targets
x86-64-v3 (AVX2/FMA) CPUs.

%prep
%autosetup -N -n basalt-%{commit}
# Submodules into their recorded paths (before patching: Patch0 also touches
# basalt-headers).
tar -xzf %{SOURCE1} --strip-components=1 -C thirdparty/basalt-headers
mkdir -p thirdparty/basalt-headers/thirdparty/Sophus
tar -xzf %{SOURCE2} --strip-components=1 -C thirdparty/basalt-headers/thirdparty/Sophus
tar -xzf %{SOURCE3} --strip-components=1 -C thirdparty/CLI11
tar -xzf %{SOURCE4} --strip-components=1 -C thirdparty/magic_enum
# Eigen and cereal come from Fedora: drop their (empty) submodule paths so a
# stray builtin lookup fails loudly instead of finding nothing.
rmdir thirdparty/basalt-headers/thirdparty/eigen \
  thirdparty/basalt-headers/thirdparty/cereal
# Bundled licenses under distinct names for %%license.
cp -p thirdparty/basalt-headers/LICENSE LICENSE.basalt-headers
cp -p thirdparty/basalt-headers/thirdparty/Sophus/LICENSE.txt LICENSE.Sophus
cp -p thirdparty/CLI11/LICENSE LICENSE.CLI11
cp -p thirdparty/magic_enum/LICENSE LICENSE.magic_enum
%autopatch -p1

%build
# Basalt prepends its own -march (CXX_MARCH) to the passed flags, so Fedora's
# -march=x86-64 would win: append the target to the passed flags instead.
export CXXFLAGS="%{build_cxxflags} -march=x86-64-v3"
%cmake \
  -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTING=OFF \
  -DCXX_MARCH=x86-64-v3 \
  -DBASALT_BUILD_SHARED_LIBRARY_ONLY=ON \
  -DBASALT_BUILD_VISUALIZATION=OFF \
  -DBASALT_BUILD_TESTS=OFF \
  -DBASALT_ENABLE_ROSBAG2=OFF \
  -DBASALT_INSTANTIATIONS_DOUBLE=OFF \
  -DBASALT_INSTANTIATIONS_FLOAT=ON \
  -DBASALT_BUILTIN_EIGEN=OFF \
  -DBASALT_BUILTIN_CEREAL=OFF \
  -DBASALT_BUILTIN_SOPHUS=ON \
  -DEIGEN_ROOT=%{_includedir}/eigen3
# Basalt needs ~2.5 GB per compile job (upstream caps low-memory machines);
# cap the jobs by available memory so a smaller builder does not OOM.
mem_kb=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
jobs=$(( mem_kb / 2500000 ))
(( jobs < 1 )) && jobs=1
(( jobs > %{_smp_build_ncpus} )) && jobs=%{_smp_build_ncpus}
echo "basalt-xreal: building with $jobs jobs (MemAvailable ${mem_kb} kB)"
ninja-build -C %{__cmake_builddir} -j"$jobs" basalt

%install
install -Dpm0755 %{__cmake_builddir}/libbasalt.so.%{vit_version} \
  %{buildroot}%{_libdir}/basalt-xreal/libbasalt.so.%{vit_version}
ln -s libbasalt.so.%{vit_version} \
  %{buildroot}%{_libdir}/basalt-xreal/libbasalt.so.%{vit_major}
# Monado's VIT loader and docs refer to the unversioned name.
ln -s libbasalt.so.%{vit_major} %{buildroot}%{_libdir}/basalt-xreal/libbasalt.so
install -Dpm0644 data/xreal/xreal_air_config.json \
  %{buildroot}%{_datadir}/basalt-xreal/xreal_air_config.json
# The configured toml points config-path at upstream's share/basalt; point it
# at the private copy instead.
sed 's|^config-path=.*$|config-path="%{_datadir}/basalt-xreal/xreal_air_config.json"|' \
  %{__cmake_builddir}/data/vit/xreal_air.toml \
  > %{buildroot}%{_datadir}/basalt-xreal/xreal_air.toml
chmod 0644 %{buildroot}%{_datadir}/basalt-xreal/xreal_air.toml

%check
lib=%{buildroot}%{_libdir}/basalt-xreal/libbasalt.so.%{vit_version}
cache=%{__cmake_builddir}/CMakeCache.txt
grep -qx 'BASALT_BUILD_SHARED_LIBRARY_ONLY:BOOL=ON' "$cache"
grep -qx 'BASALT_BUILD_VISUALIZATION:BOOL=OFF' "$cache"
grep -qx 'BASALT_INSTANTIATIONS_DOUBLE:BOOL=OFF' "$cache"
grep -qx 'BASALT_BUILTIN_EIGEN:BOOL=OFF' "$cache"
grep -q '^EIGEN3_INCLUDE_DIR:PATH=%{_includedir}/eigen3$' "$cache"
# SONAME and the exported VIT surface (the version script hides the rest).
objdump -p "$lib" | grep -qE 'SONAME[[:space:]]+libbasalt\.so\.%{vit_major}$'
nm -D --defined-only "$lib" | grep -qw vit_api_get_version
nm -D --defined-only "$lib" | grep -qw vit_tracker_create
nm -D --defined-only "$lib" | grep -qw basalt_vit_restartable
! nm -D --defined-only "$lib" | grep -v -E ' (vit_|basalt_vit_|BASALT_)' | grep -q ' T '
# No GUI stack leaked in (visualization is off).
! objdump -p "$lib" | grep -E 'NEEDED' | grep -qiE 'pangolin|libGL|epoxy|wayland'
# The settings point at the installed json, use the float pipeline, take the
# calibration from the driver, and keep the GUI off.
toml=%{buildroot}%{_datadir}/basalt-xreal/xreal_air.toml
grep -qx 'config-path="%{_datadir}/basalt-xreal/xreal_air_config.json"' "$toml"
grep -qx 'use-double=0' "$toml"
grep -qx 'cam-calib=""' "$toml"
grep -qx 'show-gui=0' "$toml"
test -f %{buildroot}%{_datadir}/basalt-xreal/xreal_air_config.json
# Load it the way Monado does and ask for the VIT version.
cat > vit-smoke.c <<'EOF'
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
typedef int (*get_version_t)(uint32_t *, uint32_t *, uint32_t *);
int main(int argc, char **argv) {
  void *h = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!h) { fprintf(stderr, "%s\n", dlerror()); return 1; }
  get_version_t get = (get_version_t)dlsym(h, "vit_api_get_version");
  uint32_t ma = 0, mi = 0, pa = 0;
  if (!get || get(&ma, &mi, &pa) != 0) return 1;
  printf("VIT %u.%u.%u\n", ma, mi, pa);
  return ma != (uint32_t)atoi(argv[2]);
}
EOF
gcc -o vit-smoke vit-smoke.c
./vit-smoke "$lib" %{vit_major}

%files
%license LICENSE LICENSE.basalt-headers LICENSE.Sophus LICENSE.CLI11 LICENSE.magic_enum
%doc README.md
%dir %{_libdir}/basalt-xreal
%{_libdir}/basalt-xreal/libbasalt.so.%{vit_version}
%{_libdir}/basalt-xreal/libbasalt.so.%{vit_major}
%{_libdir}/basalt-xreal/libbasalt.so
%{_datadir}/basalt-xreal/

%changelog
* Sun Nov 01 2026 omedora <noreply@omedora> - 0^20261015.gite3dec7b44-1
- Initial package: the xreal-vit Basalt fork at e3dec7b as monado-xreal's
  private VIT library, with the XREAL Air pipeline settings.
