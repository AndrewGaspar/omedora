# wivrn-hypxr.spec — HypXRland's patched WiVRn server/runtime.

%global upstream_version 26.6.2
%global snapshot 20260820.1
# Tracks the upstream hypxr branch; Source0 remains pinned to its resolved tip.
%global commit 3729c7b3106c66a69b88d812ebd6eba9c4fe4744
%global shortcommit %(c=%{commit}; echo ${c:0:9})
%global monado_commit 1b526bb3a0ff326ecd05af4c2c541407f53c6d4b
# The combined WiVRn/Monado build exhausts memory at the host's 24-way default.
%global _smp_ncpus_max 4

Name:           wivrn-hypxr
Version:        %{upstream_version}^%{snapshot}.git%{shortcommit}
Release:        1%{?dist}
Summary:        HypXRland-patched WiVRn OpenXR streaming server

License:        GPL-3.0-only AND Apache-2.0 AND BSL-1.0 AND MIT
URL:            https://github.com/AndrewGaspar/WiVRn
Source0:        %{url}/archive/%{commit}/wivrn-%{commit}.tar.gz
Source1:        https://gitlab.freedesktop.org/monado/monado/-/archive/%{monado_commit}/monado-%{monado_commit}.tar.gz
Source2:        wivrn-hypxr-fedora.md

ExclusiveArch:  x86_64

BuildRequires:  boost-devel
BuildRequires:  cli11-devel
BuildRequires:  cmake >= 3.28
BuildRequires:  eigen3-devel
BuildRequires:  gcc
BuildRequires:  gcc-c++
BuildRequires:  git-core
BuildRequires:  glslang
BuildRequires:  libarchive-devel
BuildRequires:  libpng-devel
BuildRequires:  ninja-build
BuildRequires:  nlohmann-json-devel
BuildRequires:  openssl-devel
BuildRequires:  patch
BuildRequires:  spdlog-devel
BuildRequires:  spirv-tools
BuildRequires:  systemd-rpm-macros
BuildRequires:  vulkan-headers
BuildRequires:  pkgconfig(avahi-client)
BuildRequires:  pkgconfig(avahi-glib)
BuildRequires:  pkgconfig(gio-2.0)
BuildRequires:  pkgconfig(gio-unix-2.0)
BuildRequires:  pkgconfig(glib-2.0)
BuildRequires:  pkgconfig(libavcodec)
BuildRequires:  pkgconfig(libavutil)
BuildRequires:  pkgconfig(libdrm)
BuildRequires:  pkgconfig(libnotify)
BuildRequires:  pkgconfig(openxr)
BuildRequires:  pkgconfig(libpipewire-0.3)
BuildRequires:  pkgconfig(librsvg-2.0)
BuildRequires:  pkgconfig(libsystemd)
BuildRequires:  pkgconfig(vulkan)

Provides:       wivrn = %{version}-%{release}
Conflicts:      wivrn-server
Requires:       /usr/bin/ffmpeg

Provides:       bundled(ffnvcodec-headers)
Provides:       bundled(magic-enum)
Provides:       bundled(mdns)
Provides:       bundled(monado)
Provides:       bundled(vulkan-memory-allocator)

%description
This is the WiVRn server branch used by HypXRland. It carries the headset
battery D-Bus API and microphone jitter fixes and embeds WiVRn's exact patched
Monado revision. It installs the standard WiVRn service and OpenXR runtime, so
it is not co-installable with another WiVRn server package.

The hypxr branch also records and transfers full-fidelity .hypxrtake bundles.
That capture path launches the system ffmpeg executable for lossless overlay
and application-audio streams.

The Fedora build retains NVENC, VA-API, and Vulkan Video encoding. The x264
software encoder is disabled because x264-devel is not in Fedora's main
repositories; this keeps the package buildable in Omedora's COPR without a
third-party repository.

%prep
%autosetup -n WiVRn-%{commit} -p1
cp %{SOURCE2} wivrn-hypxr-fedora.md
tar -xf %{SOURCE1}
for patch_file in patches/monado/*.patch; do
  patch -d monado-%{monado_commit} -p1 --forward < "$patch_file"
done
# Host tests need only spdlog's packaged CMake target. Do not let FetchContent
# attempt a network download during the offline build phase.
sed -i 's/FetchContent_MakeAvailable(spdlog)/find_package(spdlog REQUIRED)/' \
  common/CMakeLists.txt
# The server-side tests use assert(), while a Release build defines NDEBUG.
# Scope -UNDEBUG to those executables; never alter the production server.
sed -i '/target_include_directories(take-bundle PRIVATE/a\
\tforeach(target transfer-pacer fov-watch take-bundle)\
\t\ttarget_compile_options(${target} PRIVATE -UNDEBUG)\
\tendforeach()' server/CMakeLists.txt
grep -q 'target_compile_options(${target} PRIVATE -UNDEBUG)' server/CMakeLists.txt
! grep -Eq '^[[:space:]]*add_compile_options\(' server/CMakeLists.txt

%build
%cmake \
  -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DFETCHCONTENT_SOURCE_DIR_MONADO=%{_builddir}/%{buildsubdir}/monado-%{monado_commit} \
  -DGIT_DESC=v%{upstream_version} \
  -DGIT_COMMIT=%{commit} \
  -DWIVRN_BUILD_CLIENT=OFF \
  -DWIVRN_BUILD_DASHBOARD=OFF \
  -DWIVRN_BUILD_DISSECTOR=OFF \
  -DWIVRN_BUILD_SERVER=ON \
  -DWIVRN_BUILD_SERVER_LIBRARY=ON \
  -DWIVRN_BUILD_TEST=ON \
  -DWIVRN_BUILD_WIVRNCTL=ON \
  -DWIVRN_OPENXR_MANIFEST_TYPE=relative \
  -DWIVRN_USE_NVENC=ON \
  -DWIVRN_USE_PIPEWIRE=ON \
  -DWIVRN_USE_SYSTEM_BOOST=ON \
  -DWIVRN_USE_SYSTEMD=ON \
  -DWIVRN_USE_SYSTEM_OPENXR=ON \
  -DWIVRN_USE_VAAPI=ON \
  -DWIVRN_USE_VULKAN_ENCODE=ON \
  -DWIVRN_USE_X264=OFF
%cmake_build

%install
%cmake_install
# Omedora packages the service definition but does not own firewall policy.
# Users decide whether to open WiVRn's TCP/UDP 9757 on their active zone.
rm -f %{buildroot}%{_prefix}/lib/firewalld/services/wivrn.xml

%check
test -x %{buildroot}%{_bindir}/wivrn-server
test -x %{buildroot}%{_bindir}/wivrnctl
grep -F 'libopenxr_wivrn.so' \
  %{buildroot}%{_datadir}/openxr/1/openxr_wivrn.json
test_count=0
for test_binary in \
  common/recorder-packets \
  common/recorder-names \
  common/recorder-transfer \
  common/take-wav \
  server/transfer-pacer \
  server/fov-watch \
  server/take-bundle; do
  %{__cmake_builddir}/$test_binary
  test_count=$((test_count + 1))
done
test "$test_count" -eq 7
echo "WiVRn host test suite: $test_count passed, 0 failed"

%post
%systemd_user_post wivrn.service

%preun
%systemd_user_preun wivrn.service

%postun
%systemd_user_postun wivrn.service

%files
%license COPYING LICENSE-OFL-1.1
%doc wivrn-hypxr-fedora.md README.md docs/hypxrtake-host-capture.md
%{_bindir}/wivrn-server
%{_bindir}/wivrnctl
%{_libdir}/wivrn/
%{_userunitdir}/wivrn.service
%{_datadir}/openxr/1/openxr_wivrn.json

%changelog
* Thu Aug 20 2026 omedora <noreply@omedora> - 26.6.2^20260820.1.git3729c7b31-1
- Track the unified public hypxr branch and include its full-fidelity capture
  and recorder-transfer host work.
- Require the ffmpeg executable capability for capture subprocesses and
  document the mandatory commit-matched custom headset client.
- Run all seven host-native capture tests offline with assertions enabled only
  on assertion-based test executables, never on the production server.
- Continue vendoring the branch's unchanged pinned Monado revision.

* Mon Aug 03 2026 omedora <noreply@omedora> - 26.6.2^20260803.1.gitd5cb02968-1
- Initial snapshot of HypXRland's patched WiVRn 26.6.2 branch.
- Vendor and patch the exact Monado revision for an offline COPR build.
