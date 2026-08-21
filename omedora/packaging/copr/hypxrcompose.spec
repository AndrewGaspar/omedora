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
Patch0:         hypxrcompose-fedora-codec.patch

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

%build
%cmake -GNinja -DCMAKE_BUILD_TYPE=Release
%cmake_build

%install
%cmake_install

%check
# The Fedora patch keeps the Matroska stereo metadata checks while adapting
# x264-specific frame-packing assertions to the packaged SVT-AV1 default.
%{__cmake_builddir}/hypxrcompose_tests

%files
%license LICENSE
%doc hypxrcompose-fedora.md README.md NEXT-STEPS.md
%{_bindir}/hypxrcompose

%changelog
* Thu Aug 20 2026 omedora <noreply@omedora> - 0^20260820.1.gitf75ccd4ec-1
- Package the immutable current public master tip and complete headless suite.
- Require ffmpeg and ffprobe executable capabilities so Fedora ffmpeg-free and
  RPM Fusion full ffmpeg are both compatible runtime providers.
- Use Fedora's SVT-AV1 encoder for fixtures and packaged defaults because COPR's
  ffmpeg-free environment substitutes the non-functional noopenh264 shim.
