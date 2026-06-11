# bluetui.spec — TUI for managing Bluetooth on Linux (omedora).
#
# This is a FROM-SOURCE (cargo) spec, the simplest of the from-source flavors:
# bluetui is a plain Rust binary crate with no meson wrapper, no GResources,
# and no installed assets beyond the executable itself. Upstream ships no
# release binaries, and it's not in Fedora main / RPM Fusion / the vetted
# COPR / Flathub (a TUI isn't a Flathub fit), so we compile it ourselves.
#
# HERMETIC / VENDORED build (COPR-ready). COPR builds in mock, where the
# rpmbuild (build) phase has NO network — only SRPM generation does. So we do
# NOT fetch crates at build time. Instead we build fully offline against a
# `cargo vendor` tarball (Source1) of upstream's pinned Cargo.lock:
# `%%cargo_prep -v vendor` writes .cargo/config.toml with `[net] offline = true`
# + `[source.vendored-sources]`, so cargo never touches crates.io. A successful
# build is itself proof that every needed crate was vendored (offline cargo
# errors out if even one is missing).
#
# The vendor tarball is NOT committed: build-local.sh generates it at SRPM-gen
# time from upstream's committed Cargo.lock (Source0 is a version-pinned tag
# tarball + an immutable crate set, so it's deterministic). A future COPR
# .copr/Makefile (#60) must run the same `cargo vendor` in its SRPM step.

Name:           bluetui
Version:        0.8.1
Release:        1%{?dist}
Summary:        TUI for managing Bluetooth on Linux

# VENDORED LICENSE: the binary statically links its whole crate tree, so the
# License tag must aggregate the licenses of ALL bundled crates, not just
# bluetui's own. The expression below is the AND of every distinct license
# emitted by `%%cargo_license_summary` over the vendored Cargo.lock; bluetui's
# own crate is GPL-3.0(-or-later) (upstream LICENSE is GPLv3). See the shipped
# LICENSE.dependencies / cargo-vendor.txt for the full per-crate breakdown.
License:        GPL-3.0-or-later AND (Apache-2.0 OR BSL-1.0) AND (Apache-2.0 OR MIT) AND (Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT) AND BSD-2-Clause AND MIT AND (MIT OR Apache-2.0 OR LGPL-2.1-or-later) AND MPL-2.0 AND (Unlicense OR MIT) AND Zlib
URL:            https://github.com/pythops/bluetui

# Source0: upstream source tarball. `spectool -g` (run by build-local.sh)
# fetches this into SOURCES/. GitHub's archive for tag vX.Y.Z unpacks to
# bluetui-X.Y.Z/.
Source0:        %{url}/archive/refs/tags/v%{version}/%{name}-%{version}.tar.gz
# Source1: `cargo vendor` tarball of upstream's pinned Cargo.lock. NOT committed:
# build-local.sh generates it deterministically into SOURCES/ at SRPM-gen time
# (a COPR .copr/Makefile, #60, must do the same in its SRPM step). Unpacks to
# vendor/.
Source1:        %{name}-%{version}-vendor.tar.zst

# Compiled for x86_64 (the only arch omedora targets right now).
ExclusiveArch:  x86_64

# --- Build toolchain -------------------------------------------------------
# The Rust toolchain compiles the crate.
BuildRequires:  cargo
BuildRequires:  rust
# cargo-rpm-macros provides %%cargo_prep / %%cargo_build / the license macros and
# the hermetic offline .cargo/config.toml seal. >= 24 has the -v vendor flag.
BuildRequires:  cargo-rpm-macros >= 24
# gcc links the final binary against system C libs.
BuildRequires:  gcc
# The bluer crate talks to BlueZ over D-Bus via libdbus-sys, which is declared
# with the "vendored" feature in upstream Cargo.toml — it bundles + builds
# libdbus from source. So we need a C compiler + pkg-config but NOT dbus-devel.
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
# Unpack the (build-time-generated) vendor tarball (creates ./vendor/), then have
# %%cargo_prep wire .cargo/config.toml to it with offline mode on.
%setup -q -T -D -a 1 -n %{name}-%{version}
%cargo_prep -v vendor

%build
# Offline build against the vendored sources (no crates.io access).
%cargo_build
# Record the bundled crates' licenses + manifest for the %%license payload.
%{cargo_license_summary}
%{cargo_license} > LICENSE.dependencies
%{cargo_vendor_manifest}

%install
install -D -m 0755 target/release/%{name} %{buildroot}%{_bindir}/%{name}

%files
%license LICENSE
# Aggregated dependency license info from the vendored crate tree.
%license LICENSE.dependencies
%license cargo-vendor.txt
%doc Readme.md
%{_bindir}/%{name}

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 0.8.1-1
- Initial from-source (cargo) build of bluetui.
- Hermetic vendored/offline build (cargo-vendor tarball generated at SRPM-gen
  time from upstream's Cargo.lock; COPR-ready).
