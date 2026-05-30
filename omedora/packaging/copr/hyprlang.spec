# hyprlang.spec — implementation library for the hypr config language (omedora).
#
# BuildRequires hyprutils-devel — this is the canonical 2-spec chain that proves
# build-local.sh resolves a just-built sibling from the local /copr/repo. Fedora
# 44 ships a stale 0.6.4; omedora vendors 0.6.8 (newer EVR ⇒ auto-upgrade).
# Adapted from solopasha/hyprlandRPM. omedora conventions: pinned Version,
# explicit Release + %changelog, soname via glob.

Name:           hyprlang
Version:        0.6.8
Release:        1%{?dist}
Summary:        The official implementation library for the hypr config language

License:        LGPL-3.0-only
URL:            https://github.com/hyprwm/hyprlang
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

# https://fedoraproject.org/wiki/Changes/EncourageI686LeafRemoval
ExcludeArch:    %{ix86}

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  pkgconfig(hyprutils)

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
%cmake
%cmake_build

%install
%cmake_install

%check
%ctest

%files
%license LICENSE
%doc README.md
%{_libdir}/libhyprlang.so.*

%files devel
%{_includedir}/hyprlang.hpp
%{_libdir}/libhyprlang.so
%{_libdir}/pkgconfig/hyprlang.pc

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 0.6.8-1
- Initial omedora build of hyprlang 0.6.8 (adapted from solopasha/hyprlandRPM).
- Out-versions Fedora's stale 0.6.4.
