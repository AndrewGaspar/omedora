# quickshell.spec — Flexible QtQuick-based desktop shell toolkit (omedora).
#
# WHY VENDORED: Fedora 44 ships only a STALLED Feb-2026 git snapshot
# (0.2.1^git20260209.dacfa9d — identical across stable/updates/testing/rawhide).
# That snapshot predates both upstream's 0.3.0 release (2026-05-04) and the exact
# post-release snapshot pinned by Omarchy 4 beta. Quattro's shell restart command
# requires the snapshot's synchronous `quickshell kill`; 0.3.0 returns before the
# old shell exits and can race the replacement instance.
#
# Recipe ADAPTED from Fedora's own quickshell.spec (Neal Gompa / Jan Grulich,
# the authoritative BuildRequires + cmake-flags reference), advanced to Omarchy
# beta's exact 28771c7 snapshot, with these deviations:
#   * Source: pinned GitHub-mirror commit tarball (byte-stable archive), the
#     omedora convention; sha256 in quickshell.spec.sources.
#   * -DCRASH_HANDLER=OFF     — the crash handler needs cpptrace, which is NOT in
#                              Fedora 44 (no cpptrace / cmake(cpptrace) provider).
#                              The only in-Fedora alternative is -DVENDOR_CPPTRACE
#                              =ON (FetchContent), which fetches at BUILD time and
#                              would fail COPR's OFFLINE mock build. So we disable
#                              it — it is an optional crash-reporting convenience,
#                              not a desktop feature (Fedora's snapshot likewise
#                              shipped its crash reporter OFF). TODO(parent): once
#                              cpptrace lands in Fedora, flip CRASH_HANDLER back ON.
#   * +vulkan-headers        — SCREENCOPY/dmabuf path (find_package(VulkanHeaders)).
#   * +mesa-libEGL-devel     — dmabuf-deps pkg_check_modules(... egl).
#   * +polkit-devel          — polkit service now also needs polkit-gobject-1
#                              (Fedora's snapshot only used polkit-agent-1).
#   * +glib2-devel           — gobject-2.0 (polkit service).
#   * +libxcb-devel          — X11 (find_package(XCB)).
# The new 0.3.0 services NETWORK / BLUETOOTH / SERVICE_UPOWER / SERVICE_GREETD /
# SERVICE_NOTIFICATIONS are pure Qt6 DBus integrations (NetworkManager/BlueZ/etc.
# spoken over DBus at runtime) — no extra compile-time libs, only Qt6DBus, which
# Qt6 base already provides. All features stay enabled (upstream default); omarchy
# -4 expects the full toolkit.

%global commit 28771c7c74b42e20afca0b1b63980cb46515537c

Name:               quickshell
Version:            0.3.0^20.git28771c7
Release:            1%{?dist}
Summary:            Flexible QtQuick based desktop shell toolkit
# Code is LGPL, Hyprland protocols are BSD-3-Clause, wlr protocols are HPND-sell-variant
License:            LGPL-3.0-only AND BSD-3-Clause AND HPND-sell-variant
URL:                https://quickshell.org/
# Pinned Omarchy 4 beta snapshot from the GitHub mirror. Unpacks to
# quickshell-%%{commit}/.
Source0:            https://codeload.github.com/quickshell-mirror/quickshell/tar.gz/%{commit}#/%{name}-%{version}.tar.gz

# https://fedoraproject.org/wiki/Changes/EncourageI686LeafRemoval
ExcludeArch:        %{ix86}

BuildRequires:      cmake
BuildRequires:      gcc-c++
BuildRequires:      ninja-build
BuildRequires:      desktop-file-utils
# Qt6 — base toolkit + QML/Quick + private headers (declarative + wayland-client).
BuildRequires:      cmake(Qt6Core)
BuildRequires:      cmake(Qt6Gui)
BuildRequires:      cmake(Qt6Qml)
BuildRequires:      cmake(Qt6Quick)
BuildRequires:      cmake(Qt6QuickControls2)
BuildRequires:      cmake(Qt6Widgets)
BuildRequires:      cmake(Qt6Network)
BuildRequires:      cmake(Qt6DBus)
BuildRequires:      cmake(Qt6CorePrivate)
BuildRequires:      cmake(Qt6QuickPrivate)
BuildRequires:      cmake(Qt6ShaderTools)
BuildRequires:      cmake(Qt6WaylandClient)
# Build-time SPIR-V tooling for the shader pipeline.
BuildRequires:      spirv-tools
# Static / build-time libs and feature deps.
BuildRequires:      pkgconfig(CLI11)
# NOTE: cpptrace (CRASH_HANDLER) is intentionally NOT a BuildRequires — it is not
# packaged in Fedora 44, so we build with -DCRASH_HANDLER=OFF (see %conf).
BuildRequires:      vulkan-headers
BuildRequires:      pkgconfig(jemalloc)
BuildRequires:      pkgconfig(libdrm)
BuildRequires:      pkgconfig(gbm)
BuildRequires:      mesa-libEGL-devel
BuildRequires:      pkgconfig(libpipewire-0.3)
BuildRequires:      pkgconfig(pam)
BuildRequires:      pkgconfig(polkit-agent-1)
BuildRequires:      pkgconfig(polkit-gobject-1)
BuildRequires:      pkgconfig(glib-2.0)
BuildRequires:      pkgconfig(gobject-2.0)
BuildRequires:      pkgconfig(wayland-client)
BuildRequires:      pkgconfig(wayland-protocols)
BuildRequires:      pkgconfig(xcb)

# Undetectable runtime dependencies (carried over from Fedora's spec):
# qtwayland is needed for Qt < 6.10 (Fedora 44 ships 6.x < 6.10); qtsvg for
# svg images/icons (upstream "implicit dependency" recommendation).
Requires:           (qt6-qtwayland%{?_isa} if qt6-qtbase%{?_isa} < 6.10)
Requires:           qt6-qtsvg%{?_isa}

# Quickshell ships notification + polkit agents (these Provides mirror Fedora's).
Provides:           desktop-notification-daemon = %{version}-%{release}
Provides:           PolicyKit-authentication-agent = %{version}-%{release}

%description
Quickshell is a toolkit for building status bars, widgets, lockscreens, and
other desktop components using QtQuick.

It can be used alongside a Wayland compositor to build a complete desktop
environment.

%prep
%autosetup -n %{name}-%{commit} -p1

%conf
%cmake  -GNinja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_SKIP_INSTALL_RPATH=ON \
        -DDISTRIBUTOR="omedora COPR (agaspar/omedora-4)" \
        -DDISTRIBUTOR_DEBUGINFO_AVAILABLE=YES \
        -DINSTALL_QML_PREFIX=%{_lib}/qt6/qml \
        -DGIT_REVISION=%{commit} \
        -DCRASH_HANDLER=OFF \
        %{nil}

%build
%cmake_build

%install
%cmake_install

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/*.desktop

%files
%license LICENSE*
%doc BUILD.md CONTRIBUTING.md README.md changelog/
%{_bindir}/qs
%{_bindir}/quickshell
%{_datadir}/applications/org.quickshell.desktop
%{_datadir}/icons/hicolor/scalable/apps/org.quickshell.svg
%{_qt6_qmldir}/Quickshell/

%changelog
* Wed Aug 12 2026 omedora <noreply@omedora> - 0.3.0^20.git28771c7-1
- Match Omarchy 4 beta's exact post-0.3.0 snapshot.
- Include synchronous quickshell kill and IpcHandler lifetime fixes required by
  Quattro's shell restart path.

* Thu Jun 11 2026 omedora <noreply@omedora> - 0.3.0-1
- Initial omedora build of quickshell 0.3.0 (upstream release 2026-05-04).
- Vendored because Fedora 44 ships only a stalled Feb-2026 snapshot
  (0.2.1^git20260209.dacfa9d) lacking omarchy-4-needed APIs (QsWindow
  updatesEnabled property -> broken wallpaper).
- Recipe adapted from Fedora's quickshell.spec; +vulkan-headers/polkit-gobject/
  gobject/xcb/egl for 0.3.0's new ON-by-default features. CRASH_HANDLER OFF
  (cpptrace not in Fedora 44).
