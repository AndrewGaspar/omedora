# hyprland.spec — the Hyprland dynamic tiling Wayland compositor (omedora).
#
# The compositor itself. Built from the upstream release SOURCE tarball
# (source-vX.Y.Z.tar.gz), which bundles the udis86 + hyprland-protocols
# subprojects, so no separate submodule fetch is needed (unlike solopasha's
# -git spec). Adapted from solopasha/hyprlandRPM (its non-git release path).
# omedora conventions: pinned Version, explicit Release + changelog.
#
# Built from omedora's own COPR — no third-party COPRs. BuildRequires the
# whole vendored hypr* stack (glaze-static, hyprwayland-scanner, +the libs),
# all resolved from the omedora local repo at build time.
#
# Deviation from solopasha (whose pinned commit predated it): Hyprland 0.55.x+
# REQUIRES Lua 5.5 (pkg_search_module REQUIRED lua>=5.5,<5.6, for hyprpm plugin
# compilation), but Fedora 44 ships only Lua 5.4. We bundle the upstream Lua
# 5.5.0 release (Source2), build it static in %build, and expose a lua5.5.pc via
# PKG_CONFIG_PATH — the same in-tree-dependency pattern solopasha uses for
# libxkbcommon/sdbus. Lua is MIT-licensed; recorded as bundled() below.

%global macrosdir %(d=%{_rpmconfigdir}/macros.d; [ -d $d ] || d=%{_sysconfdir}/rpm; echo $d)
%global lua_version 5.5.0

Name:           hyprland
Version:        0.56.2
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
# 0.56.x find_package(glaze 7...<8) in hyprland core itself (0.55.x only needed
# it via `start`). Our glaze-devel Provides glaze-static and ships the CMake
# config package find_package looks for; 7.8.2 is inside the required range.
# Without it CMake FetchContent-clones glaze — fatal in an offline build root.
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
# 0.56.x added libeis (emulated input, for the RemoteDesktop portal path);
# Fedora ships it in libei-devel.
BuildRequires:  pkgconfig(libeis-1.0)
BuildRequires:  pkgconfig(libinput) >= 1.29
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
BuildRequires:  pkgconfig(wayland-protocols) >= 1.49
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

# NOTE on the subpackage split (omedora task: split session entry out of the
# binaries). Hyprland is built ONCE here, but the artifacts are divided so the
# compositor binaries and the *visible* wayland-sessions/*.desktop entries live
# in separate packages:
#
#   hyprland-no-session  (base) — ALL binaries, the portal config, man pages,
#                                 shell completions, %{_datadir}/hypr/. Owns
#                                 NEITHER wayland-sessions .desktop. This is what
#                                 an omedora install pulls (via hyprland-omedora,
#                                 which ships omedora's own uwsm session entry).
#                                 Provides: hyprland-bin (future retargeting).
#   hyprland             (full) — the natural/discoverable package: owns ONLY
#                                 wayland-sessions/hyprland.desktop (the plain,
#                                 visible "Hyprland" session). Requires the base.
#                                 `dnf install hyprland` yields the classic
#                                 binaries+session experience.
#   hyprland-uwsm               — owns wayland-sessions/hyprland-uwsm.desktop;
#                                 Requires the base.
#   hyprland-devel             — headers/protocols/macros; Requires the base.
#
# The base does NOT Recommends hyprland-uwsm: an omedora install must not pull
# the visible uwsm session entry (omedora ships its own via hyprland-omedora).

# The natural / discoverable top-level package pulls the binaries (base) and
# owns the plain, visible wayland-sessions/hyprland.desktop entry.
Requires:       hyprland-no-session%{?_isa} = %{version}-%{release}

%description
Hyprland is a dynamic tiling Wayland compositor that doesn't sacrifice on its
looks. It supports multiple layouts, fancy effects, a very flexible IPC model
allowing for a lot of customization, a powerful plugin system and more.

This package is the full / discoverable Hyprland: it pulls in the compositor
(hyprland-no-session) and ships the plain visible "Hyprland" session entry.

%package        no-session
Summary:        Hyprland compositor binaries (no wayland-session entry)
# Future retargeting hook: anything that just needs the compositor binary can
# Requires: hyprland-bin instead of a specific package name.
Provides:       hyprland-bin = %{version}-%{release}
Requires:       xorg-x11-server-Xwayland%{?_isa}
Requires:       aquamarine%{?_isa} >= 0.9.3
Requires:       hyprcursor%{?_isa} >= 0.1.7
Requires:       hyprgraphics%{?_isa} >= 0.5.1
Requires:       hyprlang%{?_isa} >= 0.6.7
Requires:       hyprutils%{?_isa} >= 0.14.0
# Used in the default configuration / for a working graphical session.
# NOTE: deliberately NO `Recommends: hyprland-uwsm` here — the base must not
# pull the visible uwsm session entry (omedora ships hyprland-omedora instead).
Recommends:     mesa-dri-drivers
Recommends:     polkit
%description    no-session
The Hyprland dynamic tiling Wayland compositor binaries (Hyprland, hyprctl,
hyprpm, start-hyprland), the xdg-desktop-portal config, man pages and shell
completions — everything EXCEPT a wayland-sessions/*.desktop session entry.
Install the `hyprland` package for the plain visible session entry, or
`hyprland-uwsm` for the uwsm-managed one.

%package        uwsm
Summary:        Files for a uwsm-managed Hyprland session
Requires:       hyprland-no-session%{?_isa} = %{version}-%{release}
Requires:       uwsm
%description    uwsm
Files for a uwsm-managed Hyprland session.

%package        devel
Summary:        Header and protocol files for %{name}
Requires:       hyprland-no-session%{?_isa} = %{version}-%{release}
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

# The full / discoverable package: ONLY the plain visible session entry. The
# compositor itself comes via Requires: hyprland-no-session.
%files
%{_datadir}/wayland-sessions/hyprland.desktop

%files no-session
%license LICENSE
%{_bindir}/[Hh]yprland
# Hyprland 0.55.x ships a start-hyprland launcher wrapper alongside the binary
# (newer than solopasha's pinned spec, hence not in its %%files).
%{_bindir}/start-hyprland
%{_bindir}/hyprctl
%{_bindir}/hyprpm
# Directory glob — 0.56.x added share/hypr/hyprland.lua (the default Lua config)
# and share/hypr/stubs/hl.meta.lua (LuaLS stubs) alongside the installable
# assets; all of them are owned here, so no %%files change was needed.
%{_datadir}/hypr/
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
* Fri Aug 21 2026 omedora <noreply@omedora> - 0.56.2-1
- Update the stable fallback compositor to Hyprland 0.56.2 so it provides the
  exact shared dependency wave consumed by the rebased HypXRland package.
- Keep the no-session/full/uwsm/devel package split unchanged.

* Mon Aug 03 2026 omedora <noreply@omedora> - 0.56.1-1
- Update to Hyprland 0.56.1.
- Requires hyprutils >= 0.14.0 (hard upstream minimum, HYPRUTILS_MINIMUM_VERSION)
  and aquamarine 0.14.0 (libaquamarine.so.13); the whole hypr* stack is rebuilt
  in the same wave. The aquamarine floor stays 0.9.3 (unchanged upstream).
- New BuildRequires: pkgconfig(libeis-1.0) (Fedora libei-devel); glaze is now
  find_package'd by hyprland core itself, not just by `start` — the existing
  glaze-static BR (7.8.2, inside the required [7,8) range) covers it.
- Bumped the libinput (>= 1.29) and wayland-protocols (>= 1.49) BR floors to
  match upstream's CMake minimums.
- New install artifacts share/hypr/hyprland.lua and share/hypr/stubs/hl.meta.lua
  are already owned by hyprland-no-session's %%{_datadir}/hypr/ glob; the
  no-session/full/uwsm/devel split is unchanged.

* Tue Jun 16 2026 omedora <noreply@omedora> - 0.55.4-1
- Bump to upstream 0.55.4. CMakeLists dependency floors are unchanged from
  0.55.2 (aquamarine>=0.9.3, hyprlang>=0.6.7, hyprcursor>=0.1.7,
  hyprutils>=0.13.1, hyprgraphics>=0.5.1, hyprwayland-scanner 0.3.10,
  hyprland-protocols>=0.6.4, lua>=5.5,<5.6), all already satisfied by the
  vendored stack; only glaze and aquamarine moved alongside this bump.

* Tue Jun 03 2026 omedora <noreply@omedora> - 0.55.2-2
- Split the wayland-session entries out of the compositor binaries. Hyprland is
  still built once, but: hyprland-no-session (new base) owns all binaries +
  portal config + man/completions and NO .desktop; hyprland (full) owns only
  wayland-sessions/hyprland.desktop and Requires the base; hyprland-uwsm and
  hyprland-devel retargeted to Require hyprland-no-session.
- Base Provides: hyprland-bin. Base no longer Recommends hyprland-uwsm (so an
  omedora install does not pull the visible uwsm session entry).

* Sat May 30 2026 omedora <noreply@omedora> - 0.55.2-1
- Initial omedora build of Hyprland 0.55.2 from the release source tarball.
- Adapted from solopasha/hyprlandRPM; built from omedora's own COPR.
- Subprojects (udis86, hyprland-protocols) bundled in the release tarball.
