# hypxrland.spec — the HypXRland OpenXR compositor (omedora).
#
# HypXRland is a rolling fork layered directly on Hyprland 0.56.1. It is
# intentionally packaged in parallel with, rather than as a replacement for,
# Omedora's stable Hyprland:
#
#   /usr/libexec/hypxrland/Hyprland  private compositor binary
#   /usr/bin/hypxrland-session       uwsm launcher for the XR session packages
#
# We manually install only those files. In particular this package does NOT own
# /usr/bin/{Hyprland,hyprctl,start-hyprland,hyprpm}, any portal configuration,
# headers, pkg-config metadata, shared assets, or a wayland-session desktop
# entry. Stable hyprland-no-session supplies those shared 0.56.x surfaces and
# remains an independently launchable fallback.
#
# GitHub commit archives omit git-submodule contents. The build uses Omedora's
# packaged hyprland-protocols, wayland-protocols, hyprutils and Vulkan headers;
# udis86 has no suitable Fedora package, so its exact HypXRland submodule commit
# is fetched as Source1 and restored during %%prep. Lua 5.5 is built privately,
# matching hyprland.spec, because Fedora 44 provides Lua 5.4 while Hyprland
# 0.56.x requires 5.5.

%global base_version 0.56.1
%global snapshot 20260811.1
%global commit 25c9b36859b81f412254e6446eae716f242215a6
%global shortcommit %(c=%{commit}; echo ${c:0:9})
%global udis86_commit 5336633af70f3917760a6d441ff02d93477b0c86
%global lua_version 5.5.0

Name:           hypxrland
Version:        %{base_version}^%{snapshot}.git%{shortcommit}
Release:        1%{?dist}
Summary:        Hyprland-based spatial OpenXR compositor

# HypXRland/Hyprland: BSD-3-Clause
# bundled udis86: BSD-2-Clause
# bundled protocol XML: HPND-sell-variant / LGPL-2.1-or-later
# bundled Lua 5.5 (statically linked): MIT
License:        BSD-3-Clause AND BSD-2-Clause AND HPND-sell-variant AND LGPL-2.1-or-later AND MIT
URL:            https://github.com/AndrewGaspar/Hyprland

# Immutable snapshot of the public hypxrland branch. The URL fragment gives
# spectool a stable, package-specific filename for the integrity pin.
Source0:        %{url}/archive/%{commit}/%{name}-%{commit}.tar.gz
# Restore the one required submodule not supplied by an Omedora/Fedora package.
Source1:        https://github.com/canihavesomecoffee/udis86/archive/%{udis86_commit}/udis86-%{udis86_commit}.tar.gz
# Fedora 44 has Lua 5.4; Hyprland 0.56.x requires 5.5.
Source2:        https://www.lua.org/ftp/lua-%{lua_version}.tar.gz
# Package-owned launcher shared by the branded session packages.
Source3:        hypxrland-session

ExclusiveArch:  x86_64

BuildRequires:  cmake
BuildRequires:  gcc-c++
BuildRequires:  meson
BuildRequires:  ninja-build
BuildRequires:  make
BuildRequires:  readline-devel
BuildRequires:  glaze-static
BuildRequires:  glslang-devel
BuildRequires:  vulkan-headers
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
BuildRequires:  pkgconfig(hyprland-protocols)
BuildRequires:  pkgconfig(hyprutils)
BuildRequires:  pkgconfig(hyprwire)
BuildRequires:  pkgconfig(hyprwayland-scanner)
BuildRequires:  cmake(hyprwayland-scanner)
BuildRequires:  pkgconfig(libdisplay-info)
BuildRequires:  pkgconfig(libdrm)
BuildRequires:  pkgconfig(libeis-1.0)
BuildRequires:  pkgconfig(libinput) >= 1.29
BuildRequires:  pkgconfig(libliftoff)
BuildRequires:  pkgconfig(libseat)
BuildRequires:  pkgconfig(libudev)
BuildRequires:  pkgconfig(muparser)
BuildRequires:  pkgconfig(lcms2)
BuildRequires:  pkgconfig(openxr)
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

Provides:       bundled(udis86)
Provides:       bundled(lua) = %{lua_version}
Provides:       hypxrland-bin = %{version}-%{release}

# HypXRland is deliberately a parallel add-on to the stable 0.56.x package.
# The stable package supplies the watchdog, generic hyprctl client, common
# assets and—most importantly—the fallback compositor binary. Reassess this
# range and the shared-library policy when HypXRland rebases onto 0.57.
Requires:       hyprland-no-session%{?_isa} >= %{base_version}
Requires:       hyprland-no-session%{?_isa} < 0.57
Requires:       uwsm
Requires:       vulkan-loader%{?_isa}

%description
HypXRland extends Hyprland 0.56.1 with spatial OpenXR monitors, headset input,
anchoring and XR session control. This package installs the compositor under a
private libexec path so Omedora's stable Hyprland remains installed and usable
as a fallback.

The compositor uses the existing per-user
~/.config/hypr/hyprland-xr.conf configuration through the packaged
hypxrland-session launcher. Install hypxrland-omedora for the visible
"Omedora XR" display-manager entry.

%prep
# The commit archive unpacks to Hyprland-<commit>/; -a2 also unpacks the Lua
# release beside the source tree, matching hyprland.spec's private Lua build.
%autosetup -n Hyprland-%{commit} -p1 -a 2

# GitHub archives preserve the submodule directory but not its contents.
tar -xf %{SOURCE1}
rmdir subprojects/udis86 2>/dev/null || true
mv udis86-%{udis86_commit} subprojects/udis86

%build
# Build Lua 5.5 as a private static dependency. It is used only to link this
# compositor and does not replace Fedora's system Lua.
pushd lua-%{lua_version} >/dev/null
make %{?_smp_mflags} MYCFLAGS="%{optflags} -fPIC" linux
make INSTALL_TOP=%{_builddir}/hypxrland-lua-prefix install
popd >/dev/null
mkdir -p %{_builddir}/hypxrland-lua-prefix/lib/pkgconfig
cat > %{_builddir}/hypxrland-lua-prefix/lib/pkgconfig/lua5.5.pc <<EOF
prefix=%{_builddir}/hypxrland-lua-prefix
libdir=\${prefix}/lib
includedir=\${prefix}/include
Name: Lua
Description: Lua language engine bundled for HypXRland
Version: %{lua_version}
Libs: -L\${libdir} -llua -lm -ldl
Cflags: -I\${includedir}
EOF
export PKG_CONFIG_PATH="%{_builddir}/hypxrland-lua-prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"

# Source archives have no .git metadata, so explicitly preserve the fork's
# identity in `hyprctl systeminfo`, crash reports and the instance signature.
export GIT_COMMIT_HASH=%{commit}
export GIT_BRANCH=hypxrland
export GIT_COMMIT_MESSAGE="packaged HypXRland snapshot %{shortcommit}"
export GIT_COMMIT_DATE=2026-08-11
export GIT_DIRTY=clean
export GIT_TAG=v%{base_version}-285-g%{shortcommit}
export GIT_COMMITS=7928

%cmake \
  -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DNO_HYPRPM=TRUE \
  -DNO_TESTS=TRUE \
  -DBUILD_TESTING=FALSE \
  -DWITH_OPENXR=TRUE \
  -DUSE_TRACY=FALSE

# HypXRland's CMake treats OpenXR and the Vulkan GPU probe as optional. They
# are mandatory for this package, so fail before compiling a misleadingly
# successful non-XR or unguarded build.
grep -q '^openxr_dep_FOUND:INTERNAL=1$' %{__cmake_builddir}/CMakeCache.txt
grep -Eq '^HYPR_VULKAN_INCLUDE_DIR:PATH=/.*' %{__cmake_builddir}/CMakeCache.txt

# Build only the compositor target. hyprctl's only fork delta is help text, and
# the stock 0.56.1 client transports the server-registered `openxr` command.
%cmake_build --target Hyprland

%install
install -Dpm0755 %{__cmake_builddir}/Hyprland \
  %{buildroot}%{_libexecdir}/hypxrland/Hyprland
install -Dpm0755 %{SOURCE3} %{buildroot}%{_bindir}/hypxrland-session

%check
bash -n %{SOURCE3}
# Upstream checks this variable before parsing even informational arguments.
runtime_dir=$(mktemp -d)
chmod 0700 "$runtime_dir"
XDG_RUNTIME_DIR="$runtime_dir" %{__cmake_builddir}/Hyprland --version |
  grep -F '%{commit}'

%files
%license LICENSE
%doc example/openxr.conf docs/openxr/00-overview.md docs/openxr/05-configuration.md
%{_libexecdir}/hypxrland/Hyprland
%{_bindir}/hypxrland-session

%changelog
* Tue Aug 11 2026 omedora <noreply@omedora> - 0.56.1^20260811.1.git25c9b3685-1
- Initial rolling snapshot of HypXRland, based directly on Hyprland 0.56.1.
- Install only the private compositor and packaged uwsm launcher; share the
  stable 0.56.x watchdog, hyprctl, assets and dependency wave.
- Require OpenXR and Vulkan-header GPU-probe support at build time.
