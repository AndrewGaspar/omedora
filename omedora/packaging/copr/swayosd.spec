# swayosd.spec — on-screen-display for volume/brightness/caps-lock (omedora).
#
# This is a FROM-SOURCE spec (unlike walker.spec/elephant.spec, which repackage
# upstream prebuilt binaries). SwayOSD ships NO release binaries, so we compile
# it: it's a Rust project whose meson build wraps `cargo build` in a
# custom_target. meson drives cargo, sassc compiles the SCSS theme, and
# glib-compile-resources bundles the GResource.
#
# HERMETIC / VENDORED build (COPR-ready). COPR builds in mock, where the
# rpmbuild (build) phase has NO network — only SRPM generation does. So cargo
# must never reach crates.io at build time. Because the build is meson-driven
# (meson's custom_target shells out to `cargo build`) rather than a bare
# %%cargo_build, we vendor by hand: %%prep unpacks the `cargo vendor` tarball
# (Source1) and writes a project-root .cargo/config.toml that sets
# `[net] offline = true` + `[source.vendored-sources]` (absolute vendor path).
# Cargo discovers that config from meson's CARGO_MANIFEST_PATH (the source root)
# and builds fully offline against vendor/. We keep %%meson_build; a successful
# offline build proves every needed crate was vendored.
#
# The vendor tarball is NOT committed: build-local.sh generates it at SRPM-gen
# time from upstream's committed Cargo.lock (Source0 is a version-pinned tag
# tarball + an immutable crate set, so it's deterministic). A future COPR
# .copr/Makefile (#60) must run the same `cargo vendor` in its SRPM step.
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

# VENDORED LICENSE: the binaries statically link their whole crate tree, so the
# License tag aggregates the licenses of ALL bundled crates, not just SwayOSD's
# own GPL-3.0-or-later (upstream LICENSE is GPLv3). The expression below is the
# AND of every distinct license reported by cargo2rpm's license-summary over the
# vendored Cargo.lock. (This is a meson-driven build, so we compute it from the
# vendored tree rather than via %%cargo_license_summary in %%build.)
License:        GPL-3.0-or-later AND (MIT OR Apache-2.0) AND ((MIT OR Apache-2.0) AND Unicode-3.0) AND Apache-2.0 AND (Apache-2.0 OR MIT) AND (Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT) AND MIT AND (MIT OR Apache-2.0 OR LGPL-2.1-or-later) AND (MIT OR Apache-2.0 OR Zlib) AND MPL-2.0 AND (Unlicense OR MIT) AND (Zlib OR Apache-2.0 OR MIT)
URL:            https://github.com/ErikReider/SwayOSD

# Source0: upstream source tarball. `spectool -g` (run by build-local.sh)
# fetches this into SOURCES/. GitHub's archive for tag vX.Y.Z unpacks to
# SwayOSD-X.Y.Z/.
Source0:        %{url}/archive/refs/tags/v%{version}/SwayOSD-%{version}.tar.gz
# Source1: `cargo vendor` tarball of upstream's pinned Cargo.lock. NOT committed:
# build-local.sh generates it deterministically into SOURCES/ at SRPM-gen time
# (a COPR .copr/Makefile, #60, must do the same in its SRPM step). Unpacks to
# vendor/.
Source1:        %{name}-%{version}-vendor.tar.zst

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
# cargo-rpm-macros pulls in cargo2rpm (used to derive the vendored License tag)
# and keeps this spec consistent with the other vendored Rust specs. The hermetic
# .cargo/config.toml here is written by hand (meson drives cargo, not %%cargo_build).
BuildRequires:  cargo-rpm-macros >= 24
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
# Unpack the (build-time-generated) vendor tarball (creates ./vendor/ in the
# source root).
%setup -q -T -D -a 1 -n SwayOSD-%{version}
# Hermetic seal for the meson-driven cargo build: write a project-root
# .cargo/config.toml that points cargo at the vendored sources and forbids any
# network access. meson sets CARGO_MANIFEST_PATH to this source root, so cargo
# discovers this config and resolves every crate from vendor/ offline. We use an
# absolute path because meson runs cargo with its own CARGO_TARGET_DIR/CWD.
mkdir -p .cargo
cat > .cargo/config.toml <<EOF
[source.crates-io]
replace-with = "vendored-sources"

[source.vendored-sources]
directory = "$(pwd)/vendor"

[net]
offline = true
EOF

%build
%meson
%meson_build
# Record the bundled crates' licenses + manifest for the %%license payload.
# cargo2rpm reads the offline vendored-sources config we wrote in %%prep, so
# these run without any network access.
cargo2rpm --path Cargo.toml license-summary
cargo2rpm --path Cargo.toml license-breakdown > LICENSE.dependencies
cargo2rpm write-vendor-manifest

%install
%meson_install

%files
%license LICENSE
# Aggregated dependency license info from the vendored crate tree.
%license LICENSE.dependencies
%license cargo-vendor.txt
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
- Hermetic vendored/offline build: meson's cargo custom_target builds against a
  cargo-vendor tarball (generated at SRPM-gen time from upstream's Cargo.lock)
  via a project-root .cargo/config.toml (COPR-ready).
