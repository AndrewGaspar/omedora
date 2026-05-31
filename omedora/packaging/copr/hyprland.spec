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
#
# Deviation from solopasha (whose pinned commit predated it): Hyprland 0.55.x
# REQUIRES Lua 5.5 (pkg_search_module REQUIRED lua>=5.5,<5.6, for hyprpm plugin
# compilation), but Fedora 44 ships only Lua 5.4. We bundle the upstream Lua
# 5.5.0 release (Source2), build it static in %build, and expose a lua5.5.pc via
# PKG_CONFIG_PATH — the same in-tree-dependency pattern solopasha uses for
# libxkbcommon/sdbus. Lua is MIT-licensed; recorded as bundled() below.

%global macrosdir %(d=%{_rpmconfigdir}/macros.d; [ -d $d ] || d=%{_sysconfdir}/rpm; echo $d)
%global lua_version 5.5.0

Name:           hyprland
Version:        0.55.2
Release:        1%{?dist}
Summary:        Dynamic tiling Wayland compositor that doesn't sacrifice on its looks

# hyprland: BSD-3-Clause
# subprojects/hyprland-protocols: BSD-3-Clause
# subprojects/udis86: BSD-2-Clause
# bundled protocol XML: HPND-sell-variant / LGPL-2.1-or-later
# bundled Lua 5.5 (statically linked): MIT
License:        BSD-3-Clause AND BSD-2-Clause AND HPND-sell-variant AND LGPL-2.1-or-later AND MIT
URL:            https://github.com/hyprwm/Hyprland
# The release SOURCE tarball (bundles subprojects); unpacks to hyprland-source/.
Source0:        %{url}/releases/download/v%{version}/source-v%{version}.tar.gz
# rpm macro exposing the hyprland version for plugin builds (hyprpm).
Source1:        macros.hyprland
# Lua 5.5 — Fedora 44 only has 5.4; Hyprland 0.55.x requires 5.5. Built static
# in %build and exposed via pkg-config. MIT-licensed.
Source2:        https://www.lua.org/ftp/lua-%{lua_version}.tar.gz

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
# To build the bundled Lua 5.5 (static).
BuildRequires:  make
BuildRequires:  readline-devel

# udis86 bundled here is a modified fork.
Provides:       bundled(udis86)
# Lua 5.5 is statically linked from a bundled upstream release (Fedora has 5.4).
Provides:       bundled(lua) = %{lua_version}

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
# Release tarball unpacks to hyprland-source/. -a2 also unpacks the Lua tarball
# (lua-%{lua_version}/) into the source tree.
%autosetup -n hyprland-source -p1 -a2
# Inject the version into the macros file shipped for hyprpm plugin builds.
sed -i -e "s|@@HYPRLAND_VERSION@@|%{version}|g" %{SOURCE1}

%build
# --- Bundled Lua 5.5 (Fedora 44 has only 5.4; Hyprland 0.55.x needs 5.5) -----
# Build Lua static and stage it under a private prefix, then synthesize a
# pkg-config file so Hyprland's `pkg_search_module(... lua>=5.5 ...)` finds it.
pushd lua-%{lua_version} >/dev/null
# Lua 5.5's Makefile target is `linux` (readline is built in by default; the old
# `linux-readline` target was removed). -fPIC so it links into Hyprland.
make %{?_smp_mflags} MYCFLAGS="%{optflags} -fPIC" linux
make INSTALL_TOP=%{_builddir}/lua-prefix install
popd >/dev/null
mkdir -p %{_builddir}/lua-prefix/lib/pkgconfig
cat > %{_builddir}/lua-prefix/lib/pkgconfig/lua5.5.pc <<EOF
prefix=%{_builddir}/lua-prefix
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: Lua
Description: Lua language engine (bundled, static)
Version: %{lua_version}
Libs: -L\${libdir} -llua -lm -ldl
Cflags: -I\${includedir}
EOF
export PKG_CONFIG_PATH="%{_builddir}/lua-prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

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
# Hyprland 0.55.x ships a start-hyprland launcher wrapper alongside the binary
# (newer than solopasha's pinned spec, hence not in its %%files).
%{_bindir}/start-hyprland
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
