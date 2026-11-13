# hypxrland.spec — the HypXRland OpenXR compositor (omedora).
#
# HypXRland is a rolling fork layered directly on Hyprland 0.56.2. It is
# intentionally packaged in parallel with, rather than as a replacement for,
# Omedora's stable Hyprland:
#
#   /usr/libexec/hypxrland/Hyprland  private compositor binary
#   /usr/libexec/hypxrland/hyprctl   private XR-aware control client
#   /usr/bin/hypxrland-session       uwsm launcher for the XR session packages
#   /usr/lib/hypxrland/plugins/      plugins built for this compositor build
#   /usr/lib/hypxrland/include, pkgconfig  (hypxrland-devel) plugin headers
#
# We manually install only those files. In particular this package does NOT own
# /usr/bin/{Hyprland,hyprctl,start-hyprland,hyprpm}, any portal configuration,
# headers, pkg-config metadata, shared assets, or a wayland-session desktop
# entry. Stable hyprland-no-session supplies those shared 0.56.x surfaces and
# remains an independently launchable fallback. hypxrland-devel's headers live
# under /usr/lib/hypxrland, the same layout as the Arch hypxrland-headers
# package, so they never shadow hyprland-devel's /usr/include/hyprland.
#
# GitHub commit archives omit git-submodule contents. The build uses Omedora's
# packaged hyprland-protocols, wayland-protocols, hyprutils and Vulkan headers;
# udis86 has no suitable Fedora package, so its exact HypXRland submodule commit
# is fetched as Source1 and restored during %%prep. Lua 5.5 is built privately,
# matching hyprland.spec, because Fedora 44 provides Lua 5.4 while Hyprland
# 0.56.x requires 5.5.

%global base_version 0.56.2
%global snapshot 20261111.1
%global commit 7ac272db9ac77dee5c1ddab0d78ecb9885b7b204
%global shortcommit %(c=%{commit}; echo ${c:0:9})
%global udis86_commit 5336633af70f3917760a6d441ff02d93477b0c86
%global lua_version 5.5.0
# Large C++26 translation units plus the precompiled header exhaust memory on
# constrained COPR builders even at four-way parallelism.
%global _smp_ncpus_max 1

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
# The lua.org release tarball, kept in this directory because lua.org is too
# unreliable to fetch from at build time (its sha256 is pinned in hypxrland.spec.sources).
# The name is literal: srpm.sh stages local sources without expanding macros.
Source2:        lua-5.5.0.tar.gz
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
BuildRequires:  pkgconfig(hyprcursor) >= 0.1.13
BuildRequires:  pkgconfig(hyprgraphics) >= 0.5.1
BuildRequires:  pkgconfig(hyprlang) >= 0.6.8
BuildRequires:  pkgconfig(hyprland-protocols) >= 0.7.0
BuildRequires:  pkgconfig(hyprutils) >= 0.14.0
BuildRequires:  pkgconfig(hyprwire)
BuildRequires:  pkgconfig(hyprwayland-scanner) >= 0.4.6
BuildRequires:  cmake(hyprwayland-scanner) >= 0.4.6
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
# The stable package supplies the watchdog, common assets and—most
# importantly—the fallback compositor binary. HypXRland's hyprctl is installed
# privately because its only fork delta is XR-specific command help. Reassess
# this range and the shared-library policy when HypXRland rebases onto 0.57.
Requires:       hyprland-no-session%{?_isa} >= 0.56.2-1
Requires:       hyprland-no-session%{?_isa} < 0.57
Requires:       hypxrland-legacy-config >= 3.8.4^20260812.1.gitc83a2dd6c-1
Requires:       uwsm >= 0.26.5
Requires:       vulkan-loader%{?_isa}

%description
HypXRland extends Hyprland 0.56.2 with spatial OpenXR monitors, headset input,
anchoring and XR session control. This package installs the compositor under a
private libexec path so Omedora's stable Hyprland remains installed and usable
as a fallback.

The compositor uses the existing per-user
~/.config/hypr/hyprland-xr.lua configuration through the packaged
hypxrland-session launcher. Install hypxrland-omedora for the visible
"Omedora XR" display-manager entry.

%package        devel
Summary:        HypXRland headers for building plugins against this compositor build
Requires:       %{name}%{?_isa} = %{version}-%{release}
# src/openxr/*.hpp include openxr/openxr.h.
Requires:       pkgconfig(openxr)

%description    devel
Headers and a pkg-config file for building Hyprland plugins against this
exact HypXRland build. A plugin loads only into the compositor build it was
compiled against, so build with PKG_CONFIG_PATH=/usr/lib/hypxrland/pkgconfig,
install under /usr/lib/hypxrland/plugins/<name>/ and require this exact
hypxrland version-release.

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
export GIT_COMMIT_DATE=2026-11-11
export GIT_DIRTY=clean
export GIT_TAG=v%{base_version}-469-g%{shortcommit}
export GIT_COMMITS=8130

%cmake \
  -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DNO_HYPRPM=TRUE \
  -DNO_TESTS=TRUE \
  -DBUILD_TESTING=FALSE \
  -DWITH_OPENXR=TRUE \
  -DHYPXR_PLUGIN_DIR=%{_prefix}/lib/hypxrland/plugins \
  -DUSE_TRACY=FALSE

# HypXRland's CMake treats OpenXR and the Vulkan GPU probe as optional. They
# are mandatory for this package, so fail before compiling a misleadingly
# successful non-XR or unguarded build.
grep -q '^openxr_dep_FOUND:INTERNAL=1$' %{__cmake_builddir}/CMakeCache.txt
# The plugin loader swaps stock /usr/lib{,64}/<pkg>/<name>.so paths for the
# builds here. Its default follows %%{_libdir} (lib64), not the shared layout.
grep -qx 'HYPXR_PLUGIN_DIR:STRING=%{_prefix}/lib/hypxrland/plugins' %{__cmake_builddir}/CMakeCache.txt
grep -Eq '^HYPR_VULKAN_INCLUDE_DIR:PATH=/.*' %{__cmake_builddir}/CMakeCache.txt

# Build the compositor and its matching control client. The latter stays under
# libexec and is PATH-prepended only by the XR session launcher.
%cmake_build --target Hyprland hyprctl

%install
install -Dpm0755 %{__cmake_builddir}/Hyprland \
  %{buildroot}%{_libexecdir}/hypxrland/Hyprland
install -Dpm0755 %{__cmake_builddir}/hyprctl/hyprctl \
  %{buildroot}%{_libexecdir}/hypxrland/hyprctl
install -Dpm0755 %{SOURCE3} %{buildroot}%{_bindir}/hypxrland-session
install -d %{buildroot}%{_prefix}/lib/hypxrland/plugins

# hypxrland-devel: the headers this build was compiled from, with the
# generated protocol headers and version.h, and its pkg-config file pointed at
# them. Same selection as upstream's own install rules.
include=%{buildroot}%{_prefix}/lib/hypxrland/include/hyprland
find src protocols -type f \( -name '*.h' -o -name '*.hpp' -o -name '*.inc' \) -print0 |
  while IFS= read -r -d '' header; do
    install -Dpm0644 "$header" "$include/$header"
  done
grep -Fq '"%{commit}"' "$include/src/version.h"
test -f "$include/protocols/hyprland-toplevel-export-v1.hpp"
install -d %{buildroot}%{_prefix}/lib/hypxrland/pkgconfig
sed -E 's|^prefix=.*$|prefix=%{_prefix}/lib/hypxrland/include|' \
  %{__cmake_builddir}/hyprland.pc \
  >%{buildroot}%{_prefix}/lib/hypxrland/pkgconfig/hyprland.pc
grep -Fxq 'prefix=%{_prefix}/lib/hypxrland/include' \
  %{buildroot}%{_prefix}/lib/hypxrland/pkgconfig/hyprland.pc

%check
bash -n %{SOURCE3}
# Upstream checks this variable before parsing even informational arguments.
runtime_dir=$(mktemp -d)
chmod 0700 "$runtime_dir"
XDG_RUNTIME_DIR="$runtime_dir" %{__cmake_builddir}/Hyprland --version |
  grep -F '%{commit}'
%{__cmake_builddir}/hyprctl/hyprctl --help | grep -F 'openxr'

%files
%license LICENSE
%doc example/openxr.conf contrib/hyprland-xr.lua docs/openxr/00-overview.md docs/openxr/05-configuration.md
%{_libexecdir}/hypxrland/
%{_bindir}/hypxrland-session
%dir %{_prefix}/lib/hypxrland
%dir %{_prefix}/lib/hypxrland/plugins

%files devel
%{_prefix}/lib/hypxrland/include/
%{_prefix}/lib/hypxrland/pkgconfig/

%changelog
* Wed Nov 11 2026 omedora <noreply@omedora> - 0.56.2^20261111.1.git7ac272db9-1
- Refresh to 7ac272db9: the plugin loader opens the HypXRland build in
  /usr/lib/hypxrland/plugins/<pkg>/<name>.so when a config asks for the
  stock /usr/lib{,64}/<pkg>/<name>.so, so Omarchy's titlebars path loads
  omarchy-hyprland-titlebars-hypxr. HYPXR_PLUGIN_DIR is set explicitly,
  since its default would follow %%{_libdir}.
- hypxrland-devel requires the OpenXR headers its src/openxr headers include.

* Wed Nov 11 2026 omedora <noreply@omedora> - 0.56.2^20261105.1.git964889899-2
- Add hypxrland-devel: this build's headers and pkg-config file under
  /usr/lib/hypxrland, for plugins that must match the compositor exactly
  (omarchy-hyprland-titlebars-hypxr, hyprshare). The base package now owns
  /usr/lib/hypxrland/plugins/. Same commit; the compositor is unchanged.

* Thu Nov 05 2026 omedora <noreply@omedora> - 0.56.2^20261105.1.git964889899-1
- Refresh to the current public hypxrland tip: curved XR monitors,
  submitted as cylinder composition layers (XR_KHR_composition_layer_cylinder)
  with shape-aware hit tests and a curve config key, plus the xreal-capture
  diagnostic script and a Monado submodule bump. No new build dependencies
  and no soname changes; other submodule pins are unchanged.

* Mon Nov 02 2026 omedora <noreply@omedora> - 0.56.2^20261102.1.gite3a89bc8c-1
- Refresh to the current public hypxrland tip: XR surfaces (carried
  monitors snap onto detected tables and other horizontal planes through
  XR_EXT_plane_detection), damage-gated XR frame pacing (static XR monitors
  stop presenting), and the matching Monado submodule bump. Other submodule
  pins are unchanged.
- Report the real commit date, describe tag and commit count in the
  embedded version information; they were still the August values.

* Fri Oct 16 2026 omedora <noreply@omedora> - 0.56.2^20261016.1.git9097b3c02-1
- Refresh to the current public hypxrland tip: per-HMD xr_defaults and
  profiles with auto-named create, don/doff intent with settle/hide/fade,
  re-seat height fixes, sRGB swapchain output, and the matching Monado
  submodule bump. Other submodule pins are unchanged.

* Mon Oct 12 2026 omedora <noreply@omedora> - 0.56.2^20261011.1.git1d704fc1b-1
- Refresh to the current public hypxrland tip: monitor lease rules under Lua
  configs, Xwayland restart after a crash, DRM-lease connector lifetime,
  session-lock focus safety, and the OpenXR tranche-1 primitives. Submodule
  pins (udis86, monado, hypxrpaper) are unchanged.

* Fri Aug 21 2026 omedora <noreply@omedora> - 0.56.2^20260821.2.git67200a838-1
- Refresh to the current public hypxrland tip, including cached GPU probing for
  hyprctl systeminfo so repeated queries do not wake a suspended discrete GPU.

* Fri Aug 21 2026 omedora <noreply@omedora> - 0.56.2^20260821.1.git552222a48-1
- Rebase to the current public hypxrland tip on Hyprland 0.56.2.
- Preserve Omedora's private XR-aware hyprctl, classic-config bridge, and
  session-only PATH injection while also shipping upstream's Lua XR example.
- Require the matching stable Hyprland 0.56.2 fallback and minimum Quattro
  compatibility package versions.

* Wed Aug 12 2026 omedora <noreply@omedora> - 0.56.1^20260811.1.git25c9b3685-2
- Install the matching XR-aware hyprctl privately for Omedora 4 sessions.
- Require the classic hyprlang compatibility defaults used by HypXRland.

* Tue Aug 11 2026 omedora <noreply@omedora> - 0.56.1^20260811.1.git25c9b3685-1
- Initial rolling snapshot of HypXRland, based directly on Hyprland 0.56.1.
- Install the compositor and XR-help-aware hyprctl privately plus the packaged
  uwsm launcher; share the stable 0.56.x watchdog, assets and dependency wave.
- Require OpenXR and Vulkan-header GPU-probe support at build time.
