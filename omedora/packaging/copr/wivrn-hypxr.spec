# wivrn-hypxr.spec — HypXRland's patched WiVRn server/runtime.

%global upstream_version 26.6.2
%global snapshot 20260803.1
%global commit d5cb02968d9e464c40ab6377fcee4f70aeb469af
%global shortcommit %(c=%{commit}; echo ${c:0:9})
%global monado_commit 1b526bb3a0ff326ecd05af4c2c541407f53c6d4b

Name:           wivrn-hypxr
Version:        %{upstream_version}^%{snapshot}.git%{shortcommit}
Release:        1%{?dist}
Summary:        HypXRland-patched WiVRn OpenXR streaming server

License:        GPL-3.0-only AND Apache-2.0 AND BSL-1.0 AND MIT
URL:            https://github.com/AndrewGaspar/WiVRn
Source0:        %{url}/archive/%{commit}/wivrn-%{commit}.tar.gz
Source1:        https://gitlab.freedesktop.org/monado/monado/-/archive/%{monado_commit}/monado-%{monado_commit}.tar.gz

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
BuildRequires:  pkgconfig(libpipewire-0.3)
BuildRequires:  pkgconfig(librsvg-2.0)
BuildRequires:  pkgconfig(libsystemd)
BuildRequires:  pkgconfig(vulkan)

Provides:       wivrn = %{version}-%{release}
Conflicts:      wivrn-server

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

The Fedora build retains NVENC, VA-API, and Vulkan Video encoding. The x264
software encoder is disabled because x264-devel is not in Fedora's main
repositories; this keeps the package buildable in Omedora's COPR without a
third-party repository.

%prep
%autosetup -n WiVRn-%{commit} -p1
tar -xf %{SOURCE1}
for patch_file in patches/monado/*.patch; do
  patch -d monado-%{monado_commit} -p1 --forward < "$patch_file"
done

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
  -DWIVRN_BUILD_TEST=OFF \
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

%post
%systemd_user_post wivrn.service

%preun
%systemd_user_preun wivrn.service

%postun
%systemd_user_postun wivrn.service

%files
%license COPYING LICENSE-OFL-1.1
%doc README.md
%{_bindir}/wivrn-server
%{_bindir}/wivrnctl
%{_libdir}/wivrn/
%{_userunitdir}/wivrn.service
%{_datadir}/openxr/1/openxr_wivrn.json

%changelog
* Mon Aug 03 2026 omedora <noreply@omedora> - 26.6.2^20260803.1.gitd5cb02968-1
- Initial snapshot of HypXRland's patched WiVRn 26.6.2 branch.
- Vendor and patch the exact Monado revision for an offline COPR build.
