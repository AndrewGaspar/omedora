# hypxrcompose.spec - headless offline compositor for .hypxrtake bundles.

%global snapshot 20260820.1
%global commit f75ccd4ec60a898c50f4f7ceaedba574225ef3f4
%global shortcommit %(c=%{commit}; echo ${c:0:9})

Name:           hypxrcompose
Version:        0^%{snapshot}.git%{shortcommit}
Release:        1%{?dist}
Summary:        Offline compositor for HypXRland full-fidelity XR captures

License:        BSD-3-Clause
URL:            https://github.com/AndrewGaspar/hypxrcompose
Source0:        %{url}/archive/%{commit}/%{name}-%{commit}.tar.gz
Source1:        hypxrcompose-fedora.md

ExclusiveArch:  x86_64

BuildRequires:  cmake
BuildRequires:  ffmpeg-free
BuildRequires:  gcc-c++
BuildRequires:  gtest-devel
BuildRequires:  ninja-build
BuildRequires:  nlohmann-json-devel
BuildRequires:  pkgconfig(egl)
BuildRequires:  pkgconfig(glesv2)

Requires:       /usr/bin/ffmpeg
Requires:       /usr/bin/ffprobe

%description
hypxrcompose validates, synthesizes, and renders HypXRland .hypxrtake capture
bundles into finished mono or stereo video. It reprojects recorded OpenXR eye
buffers and passthrough cameras headlessly with EGL/OpenGL ES, and delegates
media decoding, encoding, and audio mixing to ffmpeg and ffprobe subprocesses.

%prep
%autosetup -n hypxrcompose-%{commit} -p1
cp %{SOURCE1} hypxrcompose-fedora.md
# Fedora's ffmpeg-free omits libx264. Use its OpenH264 encoder in constant-QP,
# all-intra mode for synthetic camera media and as the default output encoder.
sed -i \
  -e 's/{"-c:v", "libx264", "-qp", "0", "-pix_fmt", "yuv444p"}/{"-c:v", "libopenh264", "-rc_mode", "off", "-qp", "0", "-g", "1", "-pix_fmt", "yuv420p"}/' \
  src/Synth.cpp
sed -i 's/videoCodec = "libx264"/videoCodec = "libopenh264"/' \
  src/Render.hpp src/Ffmpeg.hpp
sed -i 's/libx264 (default), libx265, ffv1/libopenh264 (default), ffv1, libsvtav1/' \
  src/main.cpp

%build
%cmake -GNinja -DCMAKE_BUILD_TYPE=Release
%cmake_build

%install
%cmake_install

%check
# Fedora cannot exercise x264's frame-packing SEI. All other tests cover
# rendering, media I/O, Matroska stereo metadata, and validation.
%{__cmake_builddir}/hypxrcompose_tests \
  --gtest_filter=-EndToEnd.StereoSideBySideOutputCarriesStereoSignalling

%files
%license LICENSE
%doc hypxrcompose-fedora.md README.md NEXT-STEPS.md
%{_bindir}/hypxrcompose

%changelog
* Thu Aug 20 2026 omedora <noreply@omedora> - 0^20260820.1.gitf75ccd4ec-1
- Package the immutable current public master tip and complete headless suite.
- Require ffmpeg and ffprobe executable capabilities so Fedora ffmpeg-free and
  RPM Fusion full ffmpeg are both compatible runtime providers.
- Use constant-QP, all-intra OpenH264 fixtures and defaults because Fedora's
  ffmpeg-free does not ship libx264.
