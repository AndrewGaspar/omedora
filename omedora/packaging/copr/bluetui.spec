# bluetui.spec — TUI for managing Bluetooth on Linux (omedora).
#
# This is a FROM-SOURCE (cargo) spec, the simplest of the from-source flavors:
# bluetui is a plain Rust binary crate with no meson wrapper, no GResources,
# and no installed assets beyond the executable itself. Upstream ships no
# release binaries, and it's not in Fedora main / RPM Fusion / the vetted
# COPR / Flathub (a TUI isn't a Flathub fit), so we compile it ourselves.
#
# Build model mirrors swayosd.spec's network-fetch approach: `cargo` pulls
# crates from the network at build time (the fedora:44 build container has
# network; a COPR build host does too). A fully hermetic/offline build would
# vendor the crates (cargo vendor + .cargo/config.toml as an extra Source) —
# tracked as the same follow-up that swayosd carries, not done here.

Name:           bluetui
Version:        0.8.1
Release:        1%{?dist}
Summary:        TUI for managing Bluetooth on Linux

# Upstream Cargo.toml declares GPL-3.0.
License:        GPL-3.0-or-later
URL:            https://github.com/pythops/bluetui

# Upstream source tarball. `spectool -g` (run by build-local.sh) fetches this
# into SOURCES/. GitHub's archive for tag vX.Y.Z unpacks to bluetui-X.Y.Z/.
Source0:        %{url}/archive/refs/tags/v%{version}/%{name}-%{version}.tar.gz

# Compiled for x86_64 (the only arch omedora targets right now).
ExclusiveArch:  x86_64

# --- Build toolchain -------------------------------------------------------
# The Rust toolchain compiles the crate.
BuildRequires:  cargo
BuildRequires:  rust
# gcc links the final binary against system C libs.
BuildRequires:  gcc
# The bluer crate talks to BlueZ over D-Bus via libdbus-sys. The crate is
# declared with the "vendored" feature (it bundles + builds libdbus from
# source), so it needs a C compiler + pkg-config but not dbus-devel. We still
# name pkgconfig defensively; if a build error reveals dbus-devel is required,
# add it here.
BuildRequires:  pkgconf-pkg-config

# --- Runtime ---------------------------------------------------------------
# bluetui drives BlueZ over its D-Bus interface, so a working bluetooth stack
# (the bluez daemon) must be present and running on the target. RPM auto-detects
# the binary's link-time .so deps; name bluez explicitly so the management
# backend it controls is guaranteed installed.
Requires:       bluez

%description
bluetui is a terminal user interface for managing Bluetooth on Linux: scanning
for, pairing, connecting, and trusting devices, and toggling controller power /
discoverable / pairable state. It talks to BlueZ over D-Bus. omedora ships it as
its Bluetooth TUI.

%prep
# GitHub tag archive unpacks to bluetui-%{version}/.
%autosetup -n %{name}-%{version}

%build
# Release profile (strip + LTO) is set in upstream Cargo.toml.
cargo build --release --locked

%install
install -D -m 0755 target/release/%{name} %{buildroot}%{_bindir}/%{name}

%files
%license LICENSE
%doc Readme.md
%{_bindir}/%{name}

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 0.8.1-1
- Initial from-source (cargo) build of bluetui.
- Crates fetched from network at build time; vendoring is a COPR follow-up.
