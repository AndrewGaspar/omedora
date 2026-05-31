# hyprland.spec — the Hyprland dynamic tiling Wayland compositor (omedora).
#
# The compositor itself. Built from the upstream release SOURCE tarball
# (source-vX.Y.Z.tar.gz), which bundles the udis86 + hyprland-protocols
# subprojects, so no separate submodule fetch is needed (unlike solopasha's
# -git spec). Adapted from solopasha/hyprlandRPM (its non-git release path).
# omedora conventions: pinned Version, explicit Release + changelog.
#
# Replaces the dropped third-party lionheartp/Hyprland COPR. BuildRequires the
# whole vendored hypr* stack (glaze-static, hyprwayland-scanner, +the libs),
# all resolved from the omedora local repo at build time.

%global macrosdir %(d=%{_rpmconfigdir}/macros.d; [ -d $d ] || d=%{_sysconfdir}/rpm; echo $d)

Name:           hyprland
Version:        0.55.2
Release:        1%{?dist}
Summary:        Dynamic tiling Wayland compositor that doesn't sacrifice on its looks

# hyprland: BSD-3-Clause
# subprojects/hyprland-protocols: BSD-3-Clause
# subprojects/udis86: BSD-2-Clause
# bundled protocol XML: HPND-sell-variant / LGPL-2.1-or-later
License:        BSD-3-Clause AND BSD-2-Clause AND HPND-sell-variant AND LGPL-2.1-or-later
URL:            https://github.com/hyprwm/Hyprland
# The release SOURCE tarball (bundles subprojects); unpacks to hyprland-source/.
Source0:        %{url}/releases/download/v%{version}/source-v%{version}.tar.gz
# rpm macro exposing the hyprland version for plugin builds (hyprpm).
Source1:        macros.hyprland

# https://fedoraproject.org/wiki/Changes/EncourageI686LeafRemoval
ExcludeArch:    %{ix86}

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  meson
BuildRequires:  ninja-build
BuildRequires:  glaze-static
BuildRequires:  glslang-devel
BuildRequires:  pkgconfig(aquamarine)
BuildRequires:  pkgconfig(cairo)
BuildRequires:  pkgconfig(egl)
BuildRequires:  pkgconfig(gbm)
BuildRequires:  pkgconfig(gio-2.0)
BuildRequires:  pkgconfig(glesv2)
BuildRequires:  pkgconfig(hwdata)
BuildRequires:  pkgconfig(hyprcursor)
BuildRequires:  pkgconfig(hyprgraphics)
BuildRequires:  pkgconfig(hyprlang)
BuildRequires:  pkgconfig(hyprutils)
BuildRequires:  pkgconfig(hyprwire)
BuildRequires:  pkgconfig(hyprwayland-scanner)
BuildRequires:  cmake(hyprwayland-scanner)
BuildRequires:  pkgconfig(libdisplay-info)
BuildRequires:  pkgconfig(libdrm)
BuildRequires:  pkgconfig(libinput) >= 1.28
BuildRequires:  pkgconfig(libliftoff)
BuildRequires:  pkgconfig(libseat)
BuildRequires:  pkgconfig(libudev)
# 0.55.x added these: muparser (expression eval) + lcms2 (color management).
BuildRequires:  pkgconfig(muparser)
BuildRequires:  pkgconfig(lcms2)
BuildRequires:  pkgconfig(pango)
BuildRequires:  pkgconfig(pangocairo)
BuildRequires:  pkgconfig(pixman-1)
BuildRequires:  pkgconfig(re2)
BuildRequires:  pkgconfig(systemd)
BuildRequires:  pkgconfig(tomlplusplus)
BuildRequires:  pkgconfig(uuid)
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-protocols) >= 1.45
BuildRequires:  pkgconfig(wayland-scanner)
BuildRequires:  pkgconfig(wayland-server)
BuildRequires:  pkgconfig(xcb-composite)
BuildRequires:  pkgconfig(xcb-dri3)
BuildRequires:  pkgconfig(xcb-errors)
BuildRequires:  pkgconfig(xcb-ewmh)
BuildRequires:  pkgconfig(xcb-icccm)
BuildRequires:  pkgconfig(xcb-present)
BuildRequires:  pkgconfig(xcb-render)
BuildRequires:  pkgconfig(xcb-renderutil)
BuildRequires:  pkgconfig(xcb-res)
BuildRequires:  pkgconfig(xcb-shm)
BuildRequires:  pkgconfig(xcb-util)
BuildRequires:  pkgconfig(xcb-xfixes)
BuildRequires:  pkgconfig(xcb-xinput)
BuildRequires:  pkgconfig(xcb)
BuildRequires:  pkgconfig(xcursor)
BuildRequires:  pkgconfig(xkbcommon)
BuildRequires:  pkgconfig(xwayland)

# udis86 bundled here is a modified fork.
Provides:       bundled(udis86)

Requires:       xorg-x11-server-Xwayland%{?_isa}
Requires:       aquamarine%{?_isa} >= 0.9.3
Requires:       hyprcursor%{?_isa} >= 0.1.7
Requires:       hyprgraphics%{?_isa} >= 0.5.1
Requires:       hyprlang%{?_isa} >= 0.6.7
Requires:       hyprutils%{?_isa} >= 0.13.1

# Used in the default configuration / for a working graphical session.
Recommends:     mesa-dri-drivers
Recommends:     polkit
Recommends:     %{name}-uwsm

%description
Hyprland is a dynamic tiling Wayland compositor that doesn't sacrifice on its
looks. It supports multiple layouts, fancy effects, a very flexible IPC model
allowing for a lot of customization, a powerful plugin system and more.

%package        uwsm
Summary:        Files for a uwsm-managed Hyprland session
Requires:       %{name}%{?_isa} = %{version}-%{release}
Requires:       uwsm
%description    uwsm
Files for a uwsm-managed Hyprland session.

%package        devel
Summary:        Header and protocol files for %{name}
Requires:       %{name}%{?_isa} = %{version}-%{release}
Requires:       git-core
Requires:       cpio
Requires:       pkgconfig(xkbcommon)
%description    devel
%{summary}.

%prep
# Release tarball unpacks to hyprland-source/.
%autosetup -n hyprland-source -p1
# Inject the version into the macros file shipped for hyprpm plugin builds.
sed -i -e "s|@@HYPRLAND_VERSION@@|%{version}|g" %{SOURCE1}

%build
# Pin the version-banner env vars so CMake doesn't shell out to git (there's no
# repo in the build root) and doesn't bake in "unknown".
export GIT_COMMIT_HASH=v%{version}
export GIT_TAG=v%{version}
export GIT_BRANCH=main
export GIT_DIRTY=""
%cmake \
    -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DNO_TESTS=TRUE \
    -DBUILD_TESTING=FALSE
%cmake_build

%install
%cmake_install
install -Dpm644 %{SOURCE1} -t %{buildroot}%{macrosdir}

%files
%license LICENSE
%{_bindir}/[Hh]yprland
%{_bindir}/hyprctl
%{_bindir}/hyprpm
%{_datadir}/hypr/
%{_datadir}/wayland-sessions/hyprland.desktop
%{_datadir}/xdg-desktop-portal/hyprland-portals.conf
%{_mandir}/man1/hyprctl.1*
%{_mandir}/man1/Hyprland.1*
%{_datadir}/bash-completion/completions/hypr*
%{_datadir}/fish/vendor_completions.d/hypr*.fish
%{_datadir}/zsh/site-functions/_hypr*

%files uwsm
%{_datadir}/wayland-sessions/hyprland-uwsm.desktop

%files devel
%{_datadir}/pkgconfig/hyprland.pc
%{_includedir}/hyprland/
%{macrosdir}/macros.hyprland

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 0.55.2-1
- Initial omedora build of Hyprland 0.55.2 from the release source tarball.
- Adapted from solopasha/hyprlandRPM; replaces the dropped lionheartp/Hyprland COPR.
- Subprojects (udis86, hyprland-protocols) bundled in the release tarball.
