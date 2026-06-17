# satty.spec — Wayland screenshot annotation tool (omedora).
#
# This is a FROM-SOURCE (cargo) spec. Satty is a Rust/GTK4 app (it uses relm4
# on top of gtk4-rs + libadwaita); upstream ships NO release binaries. It is not
# in Fedora main / RPM Fusion / the vetted COPR, and — despite being a GUI — it
# is NOT on Flathub (no com.gabm.satty or any variant exists; verified against
# the Flathub appstream + search API in May 2026). So we compile it ourselves.
#
# HERMETIC / VENDORED build (COPR-ready). COPR builds in mock, where the
# rpmbuild (build) phase has NO network — only SRPM generation does. So we do
# NOT fetch crates at build time; we build fully offline against a `cargo vendor`
# tarball (Source1) of upstream's pinned Cargo.lock. `%%cargo_prep -v vendor`
# writes .cargo/config.toml with `[net] offline = true` + `[source.vendored-
# sources]`, so cargo never touches crates.io; a successful build proves every
# needed crate was vendored.
#
# The vendor tarball is NOT committed: build-local.sh generates it at SRPM-gen
# time from upstream's committed Cargo.lock (Source0 is a version-pinned tag
# tarball + an immutable crate set, so it's deterministic). A future COPR
# .copr/Makefile (#60) must run the same `cargo vendor` in its SRPM step.
#
# Unlike swayosd, Satty has NO meson wrapper and NO blueprint-compiler step:
# the UI is built in Rust via relm4, so the toolchain is just cargo + the GTK4 /
# libadwaita -devel libraries the gtk4-rs/libadwaita-rs crates link against.
# %%install follows upstream's Makefile `install` target (binary + .desktop +
# scalable icon + license).

Name:           satty
Version:        0.21.1
Release:        1%{?dist}
Summary:        A screenshot annotation tool inspired by Swappy and Flameshot

# VENDORED LICENSE: the binary statically links its whole crate tree, so the
# License tag aggregates the licenses of ALL bundled crates, not just Satty's
# own (MPL-2.0, upstream LICENSE). The expression below is the AND of every
# distinct license emitted by `%%cargo_license_summary` over the vendored
# Cargo.lock; see the shipped LICENSE.dependencies / cargo-vendor.txt for the
# full per-crate breakdown.
License:        MPL-2.0 AND (Apache-2.0 OR MIT) AND ((Apache-2.0 OR MIT) AND CC0-1.0 AND MIT) AND ((MIT OR Apache-2.0) AND Unicode-3.0) AND Apache-2.0 AND (Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT) AND (BSD-3-Clause OR Apache-2.0) AND CC0-1.0 AND (CC0-1.0 OR Apache-2.0) AND ISC AND MIT AND (MIT OR Apache-2.0) AND (MIT OR Apache-2.0 OR Zlib) AND (Unlicense OR MIT) AND Zlib AND (Zlib OR Apache-2.0 OR MIT)
URL:            https://github.com/gabm/Satty

# Source0: upstream source tarball. `spectool -g` (run by build-local.sh)
# fetches this into SOURCES/. GitHub's archive for tag vX.Y.Z unpacks to
# Satty-X.Y.Z/.
Source0:        %{url}/archive/refs/tags/v%{version}/Satty-%{version}.tar.gz
# Source1: `cargo vendor` tarball of upstream's pinned Cargo.lock. NOT committed:
# build-local.sh generates it deterministically into SOURCES/ at SRPM-gen time
# (a COPR .copr/Makefile, #60, must do the same in its SRPM step). Unpacks to
# vendor/.
Source1:        %{name}-%{version}-vendor.tar.zst

# Compiled for x86_64 (the only arch omedora targets right now).
ExclusiveArch:  x86_64

# --- Build toolchain -------------------------------------------------------
# The Rust toolchain compiles the workspace (satty + satty_cli crates).
BuildRequires:  cargo
BuildRequires:  rust
# cargo-rpm-macros provides %%cargo_prep / %%cargo_build / the license macros and
# the hermetic offline .cargo/config.toml seal. >= 24 has the -v vendor flag.
BuildRequires:  cargo-rpm-macros >= 24
# gcc links the binary against the C GTK stack.
BuildRequires:  gcc
# pkg-config drives the -sys crates' library discovery.
BuildRequires:  pkgconf-pkg-config
# C libraries the gtk4-rs / libadwaita-rs / gdk-pixbuf crates link against.
BuildRequires:  gtk4-devel
BuildRequires:  libadwaita-devel
BuildRequires:  gdk-pixbuf2-devel
# The `epoxy` crate (an OpenGL function loader pulled in via gtk4's GL canvas)
# links system libepoxy and needs epoxy.pc at build time.
BuildRequires:  libepoxy-devel
# desktop-file-utils validates the installed .desktop file.
BuildRequires:  desktop-file-utils

# --- Runtime ---------------------------------------------------------------
# RPM auto-detects the binary's link-time .so deps (gtk4, libadwaita, gdk-pixbuf
# come along automatically). Satty reads a screenshot from stdin/a file and
# writes/copies the annotated result; on a wlroots Wayland session omedora pairs
# it with grim (capture) + wl-clipboard (copy), but those are driven by the
# omedora screenshot keybinding, not a hard library dep of satty itself, so they
# are not Requires'd here.

%description
Satty is a screenshot annotation tool for Wayland, inspired by Swappy and
Flameshot. It takes a captured image (e.g. from grim) and provides a GTK4/
libadwaita UI to draw rectangles, arrows, text, blur, and highlights before
saving or copying the result. omedora uses it as the annotation step of its
screenshot keybinding.

%prep
# GitHub tag archive unpacks to Satty-%{version}/.
%autosetup -n Satty-%{version}
# Unpack the (build-time-generated) vendor tarball (creates ./vendor/), then have
# %%cargo_prep wire .cargo/config.toml to it with offline mode on.
%setup -q -T -D -a 1 -n Satty-%{version}
%cargo_prep -v vendor

%build
# Offline build of the workspace against the vendored sources (no crates.io).
%cargo_build
# Record the bundled crates' licenses + manifest for the %%license payload.
%{cargo_license_summary}
%{cargo_license} > LICENSE.dependencies
%{cargo_vendor_manifest}

%install
# Mirror upstream Makefile's `install` target (PREFIX=%{_prefix}).
install -D -m 0755 target/release/satty %{buildroot}%{_bindir}/satty
install -D -m 0644 satty.desktop \
  %{buildroot}%{_datadir}/applications/satty.desktop
install -D -m 0644 assets/satty.svg \
  %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/satty.svg

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/satty.desktop

%files
%license LICENSE
# Aggregated dependency license info from the vendored crate tree.
%license LICENSE.dependencies
%license cargo-vendor.txt
%doc README.md
%{_bindir}/satty
%{_datadir}/applications/satty.desktop
%{_datadir}/icons/hicolor/scalable/apps/satty.svg

%changelog
* Tue Jun 16 2026 omedora <noreply@omedora> - 0.21.1-1
- Bump to upstream 0.21.1. No spec change beyond Version/pin: 0.21.0 moved
  build.rs completion generation to OUT_DIR (a `ci-release` cargo feature
  restores the old top-level completions/ dir for upstream's `make install`),
  but this spec runs its own %%install (binary + .desktop + svg only) and never
  packaged shell completions, so the change is a no-op here. Vendor tarball is
  regenerated from the in-tarball Cargo.lock by build-local.sh.

* Sat May 30 2026 omedora <noreply@omedora> - 0.20.1-1
- Initial from-source (cargo) build of Satty (Rust/GTK4, relm4; no meson).
- Hermetic vendored/offline build (cargo-vendor tarball generated at SRPM-gen
  time from upstream's Cargo.lock; COPR-ready).
