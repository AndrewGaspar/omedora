# hyprutils.spec — Hyprland's shared C++ utility library (omedora).
#
# Foundational library: nearly every other hypr* component BuildRequires
# hyprutils-devel. Fedora 44 ships a STALE 0.7.1; omedora vendors the current
# 0.13.1 (newer EVR ⇒ dnf upgrades the stale copy automatically, so the rest of
# our stack — which needs the new ABI — is installable). Adapted from
# solopasha/hyprlandRPM. omedora conventions: pinned Version, explicit Release +
# changelog, soname owned via glob (self-adjusting across releases).

Name:           hyprutils
Version:        0.13.1
Release:        1%{?dist}
Summary:        Hyprland utilities library used across the ecosystem

License:        BSD-3-Clause
URL:            https://github.com/hyprwm/hyprutils
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

# https://fedoraproject.org/wiki/Changes/EncourageI686LeafRemoval
ExcludeArch:    %{ix86}

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  pkgconfig(pixman-1)

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
# Own both the SONAME symlink (lib*.so.N) and the real file (lib*.so.X.Y.Z) via
# glob, so we don't hardcode a SOVERSION that changes between releases.
%{_libdir}/lib%{name}.so.*

%files devel
%{_includedir}/%{name}/
%{_libdir}/lib%{name}.so
%{_libdir}/pkgconfig/%{name}.pc

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 0.13.1-1
- Initial omedora build of hyprutils 0.13.1 (adapted from solopasha/hyprlandRPM).
- Out-versions Fedora's stale 0.7.1 so the vendored Hyprland stack is installable.
