# hyprgraphics.spec — Hyprland graphics / resource utilities (omedora).
#
# BuildRequired by hyprtoolkit, hyprland, hyprlock. Fedora 44 ships a stale
# 0.1.5; omedora vendors 0.5.1 (newer EVR ⇒ auto-upgrade). Adapted from
# solopasha/hyprlandRPM. omedora conventions: pinned Version, explicit Release +
# changelog, soname via glob.

Name:           hyprgraphics
Version:        0.5.1
Release:        1%{?dist}
Summary:        Hyprland graphics / resource utilities

License:        BSD-3-Clause
URL:            https://github.com/hyprwm/hyprgraphics
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

# https://fedoraproject.org/wiki/Changes/EncourageI686LeafRemoval
ExcludeArch:    %{ix86}

BuildRequires:  cmake
BuildRequires:  gcc-c++

# 0.5.x added a GLES3 renderer path (not present in older releases), so it now
# links OpenGL ES + EGL. mesa-libGLES-devel provides pkgconfig(glesv2);
# mesa-libEGL-devel provides pkgconfig(egl).
BuildRequires:  mesa-libGLES-devel
BuildRequires:  mesa-libEGL-devel
BuildRequires:  pkgconfig(glesv2)
BuildRequires:  pkgconfig(egl)
BuildRequires:  pkgconfig(libdrm)
BuildRequires:  pkgconfig(cairo)
BuildRequires:  pkgconfig(hyprutils)
BuildRequires:  pkgconfig(libjpeg)
BuildRequires:  pkgconfig(libjxl_cms)
BuildRequires:  pkgconfig(libjxl_threads)
BuildRequires:  pkgconfig(libjxl)
BuildRequires:  pkgconfig(libmagic)
BuildRequires:  pkgconfig(libwebp)
BuildRequires:  pkgconfig(pixman-1)
BuildRequires:  pkgconfig(libpng)
BuildRequires:  pkgconfig(pangocairo)
BuildRequires:  pkgconfig(libheif)
BuildRequires:  pkgconfig(librsvg-2.0)

%description
%{summary}.

%package        devel
Summary:        Development files for %{name}
Requires:       %{name}%{?_isa} = %{version}-%{release}
%description    devel
Development files for %{name}.

%prep
%autosetup -p1

%build
%cmake -DCMAKE_BUILD_TYPE=Release
%cmake_build

%install
%cmake_install

%check
%ctest

%files
%license LICENSE
%doc README.md
%{_libdir}/lib%{name}.so.*

%files devel
%{_includedir}/%{name}/
%{_libdir}/lib%{name}.so
%{_libdir}/pkgconfig/%{name}.pc

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 0.5.1-1
- Initial omedora build of hyprgraphics 0.5.1 (adapted from solopasha/hyprlandRPM).
- Out-versions Fedora's stale 0.1.5.
