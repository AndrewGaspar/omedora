# omarchy-hyprland-titlebars.spec — Omarchy's floating-workspace titlebars (omedora).
#
# A Hyprland plugin (a hyprbars fork; it still registers as "hyprbars") that
# Omarchy 4.5's floating workspace mode loads. Omarchy hardcodes its path,
# /usr/lib/omarchy-hyprland-titlebars/titlebars.so, in
# default/hypr/workspace-modes.lua and skips titlebars when the file is absent,
# so the upstream install path is kept on Fedora too.
#
# A plugin loads only into the exact compositor build it was compiled against,
# so this requires the exact hyprland-no-session version-release of the
# hyprland-devel it was built with. Every hyprland.spec release needs a rebuild
# of this spec with hyprland_evr bumped; test/hypxr-spec-test.sh checks the pin.
#
# The plugin includes Hyprland's Lua headers. Hyprland bundles Lua 5.5 (Fedora
# ships 5.4), so the 5.5.0 headers come from the release tarball hyprland.spec
# builds. Nothing links Lua here: the compositor exports it to plugins.

%global hyprland_evr 0.56.2-1%{?dist}
%global lua_version 5.5.0
# Matches the Arch package (!lto) and upstream's plugin builds.
%global _lto_cflags %{nil}

Name:           omarchy-hyprland-titlebars
Version:        0.2.2
Release:        1%{?dist}
Summary:        Titlebars for Omarchy's floating workspaces (Hyprland plugin)

License:        BSD-3-Clause AND MIT
URL:            https://github.com/omacom/omarchy-hyprland-titlebars
Source0:        %{url}/archive/v%{version}/%{name}-%{version}.tar.gz
Source1:        https://www.lua.org/ftp/lua-%{lua_version}.tar.gz

BuildRequires:  cmake
BuildRequires:  ninja-build
BuildRequires:  gcc-c++
# Hyprland's render headers include glslang's C interface.
BuildRequires:  glslang-devel
BuildRequires:  pkgconfig(aquamarine)
BuildRequires:  pkgconfig(cairo)
BuildRequires:  pkgconfig(egl)
BuildRequires:  pkgconfig(hyprcursor) >= 0.1.13
BuildRequires:  pkgconfig(hyprgraphics) >= 0.5.1
BuildRequires:  pkgconfig(hyprlang) >= 0.6.8
BuildRequires:  pkgconfig(hyprutils) >= 0.14.0
BuildRequires:  pkgconfig(libdrm)
BuildRequires:  pkgconfig(libinput)
BuildRequires:  pkgconfig(libudev)
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
BuildRequires:  hyprland-devel = %{hyprland_evr}

Requires:       hyprland-no-session%{?_isa} = %{hyprland_evr}

%description
Titlebars for windows on Omarchy's floating workspaces, as a plugin for the
stable Hyprland compositor.

%prep
%autosetup -p1 -a1
mkdir lua-include
cp -p lua-%{lua_version}/src/{lua.h,luaconf.h,lualib.h,lauxlib.h} lua-include/

%build
export CXXFLAGS="%{build_cxxflags} -I$PWD/lua-include"
%cmake -DCMAKE_BUILD_TYPE=Release
%cmake_build

%install
%cmake_install
test -f %{buildroot}%{_prefix}/lib/%{name}/titlebars.so

%check
# The compiler's record of the headers it read: Hyprland's plugin API must come
# from hyprland-devel's /usr/include/hyprland, never anywhere else.
ninja -C %{__cmake_builddir} -t deps >deps.txt
grep -qF '%{_includedir}/hyprland/src/plugins/PluginAPI.hpp' deps.txt
if grep -E 'src/plugins/PluginAPI\.hpp' deps.txt | grep -vqF '%{_includedir}/hyprland/'; then
  echo "titlebars.so was built against headers other than hyprland-devel's" >&2
  exit 1
fi
grep -qF "$PWD/lua-include/lua.h" deps.txt

%files
%license LICENSE LICENSE.MIT
%doc README.md
%dir %{_prefix}/lib/%{name}
%{_prefix}/lib/%{name}/titlebars.so

%changelog
* Wed Nov 11 2026 omedora <noreply@omedora> - 0.2.2-1
- Initial omedora build of omarchy-hyprland-titlebars 0.2.2 (Omarchy 4.5
  stable's version) for the stable Hyprland 0.56.2-1 build.
