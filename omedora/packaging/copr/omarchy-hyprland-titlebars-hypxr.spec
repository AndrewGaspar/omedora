# omarchy-hyprland-titlebars-hypxr.spec — Omarchy's titlebars built for HypXRland (omedora).
#
# The same plugin as omarchy-hyprland-titlebars, built against hypxrland-devel
# so it loads into the XR compositor (the stock build fails there with "Version
# mismatch"). It installs beside the stock plugin under
# /usr/lib/hypxrland/plugins/, the Arch package's layout. The stock package
# stays a dependency: Omarchy checks its file exists before loading titlebars.
#
# The exact hypxrland version-release pin keeps the pair in step: every
# hypxrland.spec release needs a rebuild of this spec with hypxrland_evr
# bumped; test/hypxr-spec-test.sh checks the pin. Lua 5.5 headers as in
# omarchy-hyprland-titlebars.spec.

%global hypxrland_evr 0.56.2^20261111.1.git7ac272db9-1%{?dist}
%global upstream_name omarchy-hyprland-titlebars
%global lua_version 5.5.0
%global _lto_cflags %{nil}

Name:           omarchy-hyprland-titlebars-hypxr
Version:        0.2.2
Release:        2%{?dist}
Summary:        Titlebars for Omarchy's floating workspaces, built for HypXRland

License:        BSD-3-Clause AND MIT
URL:            https://github.com/omacom/omarchy-hyprland-titlebars
Source0:        %{url}/archive/v%{version}/%{upstream_name}-%{version}.tar.gz
# The lua.org release tarball, kept in this directory because lua.org is too
# unreliable to fetch from at build time (its sha256 is pinned in omarchy-hyprland-titlebars-hypxr.spec.sources).
# The name is literal: srpm.sh stages local sources without expanding macros.
Source1:        lua-5.5.0.tar.gz

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
BuildRequires:  hypxrland-devel = %{hypxrland_evr}

Requires:       hypxrland%{?_isa} = %{hypxrland_evr}
Requires:       omarchy-hyprland-titlebars

%description
Titlebars for windows on Omarchy's floating workspaces, built for the HypXRland
XR compositor.

%prep
%autosetup -n %{upstream_name}-%{version} -p1 -a1
mkdir lua-include
cp -p lua-%{lua_version}/src/{lua.h,luaconf.h,lualib.h,lauxlib.h} lua-include/

%build
export CXXFLAGS="%{build_cxxflags} -I$PWD/lua-include"
# Only HypXRland's pkg-config file: stable hyprland-devel's must not win.
export PKG_CONFIG_PATH=%{_prefix}/lib/hypxrland/pkgconfig
%cmake -DCMAKE_BUILD_TYPE=Release
grep -Fq '%{_prefix}/lib/hypxrland/include' %{__cmake_builddir}/CMakeCache.txt
%cmake_build

%install
install -Dpm0755 %{__cmake_builddir}/titlebars.so \
  %{buildroot}%{_prefix}/lib/hypxrland/plugins/%{upstream_name}/titlebars.so

%check
# The compiler's record of the headers it read: Hyprland's plugin API must come
# from hypxrland-devel, never from stable hyprland-devel's /usr/include/hyprland.
ninja -C %{__cmake_builddir} -t deps >deps.txt
grep -qF '%{_prefix}/lib/hypxrland/include/hyprland/src/plugins/PluginAPI.hpp' deps.txt
if grep -qF '%{_includedir}/hyprland/' deps.txt; then
  echo "titlebars.so was built against stable Hyprland's headers" >&2
  exit 1
fi
grep -qF "$PWD/lua-include/lua.h" deps.txt

%files
%license LICENSE LICENSE.MIT
%doc README.md
%dir %{_prefix}/lib/hypxrland/plugins/%{upstream_name}
%{_prefix}/lib/hypxrland/plugins/%{upstream_name}/titlebars.so

%changelog
* Wed Nov 11 2026 omedora <noreply@omedora> - 0.2.2-2
- Rebuild for HypXRland 0.56.2^20261111.1.git7ac272db9-1, whose plugin loader
  opens this build when Omarchy asks for the stock titlebars path.

* Wed Nov 11 2026 omedora <noreply@omedora> - 0.2.2-1
- Initial omedora build of omarchy-hyprland-titlebars 0.2.2 for HypXRland
  0.56.2^20261105.1.git964889899-2.
