# hyprpicker.spec — wlroots-compatible Wayland color picker (omedora).
#
# Adapted from solopasha/hyprlandRPM. omedora conventions: pinned Version,
# explicit Release + changelog.

Name:           hyprpicker
Version:        0.4.7
Release:        1%{?dist}
Summary:        A wlroots-compatible Wayland color picker
# LICENSE: BSD-3-Clause; bundled wlr-layer-shell XML: HPND-sell-variant
License:        BSD-3-Clause AND HPND-sell-variant
URL:            https://github.com/hyprwm/hyprpicker
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz

BuildRequires:  cmake
BuildRequires:  gcc-c++

BuildRequires:  pkgconfig(cairo)
BuildRequires:  pkgconfig(hyprutils)
BuildRequires:  pkgconfig(hyprwayland-scanner)
BuildRequires:  pkgconfig(libjpeg)
BuildRequires:  pkgconfig(pango)
BuildRequires:  pkgconfig(pangocairo)
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-protocols)
BuildRequires:  pkgconfig(xkbcommon)

Recommends:     wl-clipboard

%description
%{summary}.

%prep
%autosetup -p1

%build
%cmake \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_MANDIR=%{_mandir}
%cmake_build

%install
%cmake_install

%files
%license LICENSE
%doc README.md
%{_bindir}/%{name}
%{_mandir}/man1/%{name}.1.*

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 0.4.7-1
- Initial omedora build of hyprpicker 0.4.7 (adapted from solopasha/hyprlandRPM).
