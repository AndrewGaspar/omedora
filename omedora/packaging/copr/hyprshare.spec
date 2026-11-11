# hyprshare.spec — switch what a screenshare shows, for HypXRland (omedora).
#
# A Hyprland plugin (AndrewGaspar/hyprshare) that hooks a private compositor
# function and reads private members, so it works only with the exact
# HypXRland build whose headers it was compiled against. It is built with its
# own Makefile against hypxrland-devel (HYPRLAND_PC_DIR) and the compositor's
# defines (the Makefile's HYPRLAND_DEFINES), and installs under
# /usr/lib/hypxrland/plugins/, the Arch package's layout. Load it from
# ~/.config/hypr/hyprland-xr.lua:
#   hl.plugin.load("/usr/lib/hypxrland/plugins/hyprshare/hyprshare.so")
#
# Every hypxrland.spec release needs a rebuild of this spec with
# hypxrland_evr bumped; test/hypxr-spec-test.sh checks the pin.
#
# Lua: HypXRland bundles Lua 5.5 statically and exports it to plugins; Fedora's
# lua-devel is 5.4. A local lua.pc gives the Makefile the 5.5.0 headers from the
# tarball hypxrland.spec builds, with no Libs, so the plugin links no Lua of its
# own and binds to the compositor's.

%global hypxrland_evr 0.56.2^20261105.1.git964889899-2%{?dist}
%global commit f82d095e45dda325b7972039a9d6f273a45bc8c6
%global shortcommit %(c=%{commit}; echo ${c:0:9})
%global snapshot 20261111
%global lua_version 5.5.0
# The Makefile builds with -fno-lto; keep rpm's LTO flags out as well.
%global _lto_cflags %{nil}

Name:           hyprshare
Version:        0^%{snapshot}.git%{shortcommit}
Release:        1%{?dist}
Summary:        Switch what a screenshare shows without restarting it, for HypXRland

License:        BSD-3-Clause
URL:            https://github.com/AndrewGaspar/hyprshare
Source0:        %{url}/archive/%{commit}/%{name}-%{commit}.tar.gz
Source1:        https://www.lua.org/ftp/lua-%{lua_version}.tar.gz

BuildRequires:  gcc-c++
BuildRequires:  make
BuildRequires:  binutils
# Hyprland's render headers include glslang's C interface.
BuildRequires:  glslang-devel
BuildRequires:  pkgconfig(aquamarine)
BuildRequires:  pkgconfig(cairo)
BuildRequires:  pkgconfig(egl)
BuildRequires:  pkgconfig(hyprcursor) >= 0.1.13
# HypXRland's src/openxr headers (reached via OpenXRManager.hpp) include
# openxr/openxr.h; hypxrland-devel doesn't pull the OpenXR headers in yet.
BuildRequires:  pkgconfig(openxr)
BuildRequires:  pkgconfig(hyprgraphics) >= 0.5.1
BuildRequires:  pkgconfig(hyprlang) >= 0.6.8
BuildRequires:  pkgconfig(hyprutils) >= 0.14.0
BuildRequires:  pkgconfig(libdrm)
BuildRequires:  pkgconfig(libinput)
BuildRequires:  pkgconfig(libudev)
BuildRequires:  pkgconfig(pangocairo)
BuildRequires:  pkgconfig(pixman-1)
BuildRequires:  pkgconfig(wayland-server)
BuildRequires:  pkgconfig(xcb)
BuildRequires:  pkgconfig(xcb-composite)
BuildRequires:  pkgconfig(xcb-errors)
BuildRequires:  pkgconfig(xcb-icccm)
BuildRequires:  pkgconfig(xcb-render)
BuildRequires:  pkgconfig(xcb-res)
BuildRequires:  pkgconfig(xcb-xfixes)
BuildRequires:  pkgconfig(xkbcommon)
BuildRequires:  hypxrland-devel = %{hypxrland_evr}

Requires:       hypxrland%{?_isa} = %{hypxrland_evr}

%description
hyprshare lets a screenshare switch to another window or monitor without
restarting the share, for the HypXRland XR compositor.

%prep
%autosetup -n %{name}-%{commit} -p1 -a1
mkdir -p lua/include lua/pkgconfig
cp -p lua-%{lua_version}/src/{lua.h,luaconf.h,lualib.h,lauxlib.h} lua/include/
cat >lua/pkgconfig/lua.pc <<PC
Name: Lua
Description: Lua %{lua_version} headers matching HypXRland's bundled Lua
Version: %{lua_version}
Cflags: -I$PWD/lua/include
Libs:
PC
# The Makefile hardcodes the compositor's HYPRLAND_VERSION define; it must
# match the headers, or a new HypXRland release needs a new hyprshare.
version=$(PKG_CONFIG_PATH=%{_prefix}/lib/hypxrland/pkgconfig pkg-config --modversion hyprland)
grep -Fq "'-DHYPRLAND_VERSION=\"$version\"'" Makefile

%build
export PKG_CONFIG_PATH=$PWD/lua/pkgconfig:%{_prefix}/lib/hypxrland/pkgconfig
# rpm's CXXFLAGS/LDFLAGS come in through the environment, so the Makefile's
# own += flags (-std=gnu++26, -fPIC, -shared, -z nodelete) still apply.
# glaze is not reached through any installed header.
# -MD leaves the compiler's header list (build/*.d) for %%check.
export CPPFLAGS="${CPPFLAGS:-} -MD"
%make_build HYPRLAND_PC_DIR=%{_prefix}/lib/hypxrland/pkgconfig GLAZE_INCLUDE=
test -f build/hyprshare-v4.so

%install
install -Dpm0755 build/hyprshare-v4.so \
  %{buildroot}%{_prefix}/lib/hypxrland/plugins/%{name}/%{name}.so

%check
# The compiler's record of the headers it read: Hyprland's plugin API must come
# from hypxrland-devel, never from stable hyprland-devel's /usr/include/hyprland,
# and Lua from the 5.5.0 headers above.
cat build/*.d >deps.txt
grep -qF '%{_prefix}/lib/hypxrland/include/hyprland/src/plugins/PluginAPI.hpp' deps.txt
if grep -qF '%{_includedir}/hyprland/' deps.txt; then
  echo "hyprshare was built against stable Hyprland's headers" >&2
  exit 1
fi
grep -qF "$PWD/lua/include/lua.h" deps.txt
# Lua comes from the compositor, never from a separate liblua.
if objdump -p build/hyprshare-v4.so | grep -E 'NEEDED.*liblua'; then
  echo "hyprshare must not link its own Lua" >&2
  exit 1
fi
# Every Lua symbol it needs must be exported by the compositor.
nm -D --undefined-only build/hyprshare-v4.so | awk '{print $2}' |
  grep -E '^luaL?_' | sort -u >needed-lua
nm -D --defined-only %{_libexecdir}/hypxrland/Hyprland | awk '{print $3}' |
  grep -E '^luaL?_' | sort -u >exported-lua
missing=$(comm -23 needed-lua exported-lua)
if [ -n "$missing" ]; then
  echo "Lua symbols the compositor does not export: $missing" >&2
  exit 1
fi

%files
%license LICENSE
%doc README.md
%dir %{_prefix}/lib/hypxrland/plugins/%{name}
%{_prefix}/lib/hypxrland/plugins/%{name}/%{name}.so

%changelog
* Wed Nov 11 2026 omedora <noreply@omedora> - 0^20261111.gitf82d095e4-1
- Initial omedora build of hyprshare at f82d095e4 for HypXRland
  0.56.2^20261105.1.git964889899-2.
