# swayosd.spec — on-screen-display for volume/brightness/caps-lock (omedora).
#
# This is a FROM-SOURCE spec (unlike walker.spec/elephant.spec, which repackage
# upstream prebuilt binaries). SwayOSD ships NO release binaries, so we compile
# it: it's a Rust project whose meson build wraps `cargo build` in a
# custom_target. meson drives cargo, sassc compiles the SCSS theme, and
# glib-compile-resources bundles the GResource.
#
# We build with `cargo` fetching crates from the network at build time (the
# fedora:44 build container has network; a COPR build host does too). For a
# fully hermetic/offline COPR build we'd vendor the crates (cargo vendor +
# .cargo/config.toml as an extra Source) — tracked as a follow-up, not done here.
#
# SwayOSD has two halves:
#   - swayosd-server / swayosd-client: the per-user OSD daemon + the CLI that
#     pokes it. omedora drives these via its OWN user unit
#     (config/systemd/user/swayosd-server.service) and its OWN theme/config in
#     ~/.config/swayosd/, so the RPM only needs to deliver the binaries.
#   - swayosd-libinput-backend: an optional system daemon (+ its polkit/udev/
#     dbus/systemd-system glue) that lets brightness/backlight keys work without
#     root. We ship it too so those keys Just Work; it's inert unless enabled.

Name:           swayosd
Version:        0.3.1
Release:        1%{?dist}
Summary:        GTK based on-screen-display for audio, brightness and caps-lock

# Upstream LICENSE is GPLv3.
License:        GPL-3.0-or-later
URL:            https://github.com/ErikReider/SwayOSD

# Upstream source tarball. `spectool -g` (run by build-local.sh) fetches this
# into SOURCES/. GitHub's archive for tag vX.Y.Z unpacks to SwayOSD-X.Y.Z/.
Source0:        %{url}/archive/refs/tags/v%{version}/SwayOSD-%{version}.tar.gz

# Compiled for x86_64 (the only arch omedora targets right now).
ExclusiveArch:  x86_64

# --- Build toolchain -------------------------------------------------------
# meson + ninja drive the build; gcc links the Rust binaries against the C libs.
BuildRequires:  meson
BuildRequires:  ninja-build
BuildRequires:  gcc
# Rust toolchain: meson's custom_target shells out to `cargo build`.
BuildRequires:  cargo
BuildRequires:  rust
# sassc compiles style/style.scss -> style.css at build time (required program).
BuildRequires:  sassc
# glib-compile-resources (from glib2-devel) bundles the GResource; glib2-devel
# also provides the gio/glib pkg-config the Rust gtk bindings link against.
BuildRequires:  glib2-devel
# C libraries the gtk4-rs / pulse / libinput crates link against (pkg-config).
BuildRequires:  gtk4-devel
BuildRequires:  gtk4-layer-shell-devel
BuildRequires:  libinput-devel
BuildRequires:  pulseaudio-libs-devel
# The libdbus-sys crate links system libdbus-1 (dbus-1.pc).
BuildRequires:  dbus-devel
# The evdev-sys crate needs libevdev.pc; without it, it tries to autoreconf and
# compile libevdev from source (and fails — no autotools in the build root).
BuildRequires:  libevdev-devel
# systemd-devel gives libudev (the libinput backend reads udev) + the
# systemd.pc that meson queries for systemdsystemunitdir.
BuildRequires:  systemd-devel
# Provides the %%{_unitdir} macro + %%systemd_* scriptlets for the system unit.
BuildRequires:  systemd-rpm-macros

# --- Runtime ---------------------------------------------------------------
# RPM auto-detects the link-time .so dependencies of the compiled binaries, so
# gtk4 / libpulse / libinput / libudev come along automatically. gtk4-layer-shell
# is loaded for the OSD overlay; name it explicitly so it's guaranteed present.
Requires:       gtk4-layer-shell

%description
SwayOSD is a GTK based on-screen-display for visualizing changes to audio
volume, screen brightness and caps-lock/num-lock state on wlroots-based Wayland
compositors. omedora uses it for the volume and brightness key OSDs.

This package provides swayosd-server and swayosd-client plus the optional
swayosd-libinput-backend (with its polkit/udev/dbus/systemd glue) so that
brightness/backlight keys can be handled without root.

%prep
# GitHub tag archive unpacks to SwayOSD-%{version}/.
%autosetup -n SwayOSD-%{version}

%build
%meson
%meson_build

%install
%meson_install

%files
%license LICENSE
%doc README.md
# The OSD daemon + CLI omedora drives via its own user unit.
%{_bindir}/swayosd-server
%{_bindir}/swayosd-client
# Optional system-level libinput backend + its integration glue.
%{_bindir}/swayosd-libinput-backend
%{_unitdir}/swayosd-libinput-backend.service
%{_libdir}/udev/rules.d/99-swayosd.rules
%{_datadir}/dbus-1/system.d/org.erikreider.swayosd.conf
%{_datadir}/dbus-1/system-services/org.erikreider.swayosd.service
%{_datadir}/polkit-1/actions/org.erikreider.swayosd.policy
%{_datadir}/polkit-1/rules.d/org.erikreider.swayosd.rules
# Upstream's default config + compiled theme. omedora overrides these per-user
# in ~/.config/swayosd/, so owning the system copies here is harmless.
%dir %{_sysconfdir}/xdg/swayosd
%config(noreplace) %{_sysconfdir}/xdg/swayosd/config.toml
%config(noreplace) %{_sysconfdir}/xdg/swayosd/backend.toml
%{_sysconfdir}/xdg/swayosd/style.css

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 0.3.1-1
- Initial from-source build of SwayOSD (meson wrapping cargo build).
- Ships swayosd-server/-client + the libinput backend and its polkit/udev/dbus/
  systemd-system glue so brightness keys work without root.
- Crates fetched from network at build time; vendoring is a COPR follow-up.
