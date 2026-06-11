# hyprland-preview-share-picker.spec — Hyprland screen-share picker (omedora).
#
# An alternative xdg-desktop-portal-hyprland custom share picker that shows
# live window + monitor previews. omarchy wires it in via
# config/hypr/xdph.conf (custom_picker_binary = hyprland-preview-share-picker)
# and ships a per-user config + theme under
# ~/.config/hyprland-preview-share-picker/.
#
# This is a FROM-SOURCE spec (like swayosd.spec): upstream ships no release
# binaries. It's a Rust project (edition 2024 — Fedora 44's rust 1.95 builds it
# fine; no nightly needed despite the AUR's cargo-nightly makedepend).
#
# Submodule wrinkle: the crate's `lib/` subcrate runs wayland-scanner at build
# time against hyprland-protocols XML that upstream vendors as a GIT SUBMODULE
# (lib/hyprland-protocols). GitHub release tarballs do NOT include submodule
# contents, so we fetch that protocols tree as a second Source and drop it into
# place in %prep. The submodule is pinned at hyprwm/hyprland-protocols commit
# 3a5c2bd (the commit lib/hyprland-protocols points at for the v0.2.1 tag).
#
# Hermetic/offline crate build (like satty/swayosd): we build fully offline
# against a `cargo vendor` tarball (Source2) of upstream's pinned Cargo.lock,
# generated at SRPM-gen time by build-local.sh / .copr/srpm.sh. `%%cargo_prep -v
# vendor` writes .cargo/config.toml with offline mode on, so cargo never touches
# crates.io — a successful build proves every crate (image, gtk4-rs, …) was
# vendored. (COPR's mock build phase has no network, which is why this matters.)
#
# Runtime dep note: `Requires: xdg-desktop-portal-hyprland` now resolves from
# the omedora repo (vendored as omedora/packaging/copr/xdg-desktop-portal-
# hyprland.spec). It used to come from the lionheartp/Hyprland COPR, which was
# retired in task #66.

%global protocols_commit 3a5c2bda1c1a4e55cc1330c782547695a93f05b2

Name:           hyprland-preview-share-picker
Version:        0.2.1
Release:        1%{?dist}
Summary:        Alternative Hyprland share picker with window and monitor previews

# Upstream LICENSE is MIT.
License:        MIT
URL:            https://github.com/WhySoBad/hyprland-preview-share-picker

# Main source: the tagged release tarball (unpacks to NAME-VERSION/).
Source0:        %{url}/archive/refs/tags/v%{version}/%{name}-%{version}.tar.gz
# The hyprland-protocols git submodule, fetched as a standalone tarball at the
# pinned commit. GitHub's archive for a commit unpacks to
# hyprland-protocols-<commit>/.
Source1:        https://github.com/hyprwm/hyprland-protocols/archive/%{protocols_commit}/hyprland-protocols-%{protocols_commit}.tar.gz
# Source2: `cargo vendor` tarball of upstream's pinned Cargo.lock. NOT committed;
# regenerated deterministically at SRPM-gen time. Unpacked to ./vendor/ in %%prep.
Source2:        %{name}-%{version}-vendor.tar.zst

# Compiled for x86_64 (the only arch omedora targets right now).
ExclusiveArch:  x86_64

# --- Build toolchain -------------------------------------------------------
# Rust + cargo build the binary; the gtk4 / wayland crates link C libs.
BuildRequires:  cargo
BuildRequires:  rust
# cargo-rpm-macros provides %%cargo_prep / %%cargo_build + the offline
# .cargo/config.toml seal and the license macros. >= 24 has the -v vendor flag.
BuildRequires:  cargo-rpm-macros >= 24
BuildRequires:  gcc
BuildRequires:  pkgconfig
# C libraries the gtk4-rs / gtk4-layer-shell / wayland crates link against.
BuildRequires:  gtk4-devel
BuildRequires:  gtk4-layer-shell-devel
BuildRequires:  wayland-devel

# --- Runtime ---------------------------------------------------------------
# RPM auto-detects link-time .so deps (gtk4, wayland) of the compiled binary;
# name the layer-shell lib explicitly so it's guaranteed present. The picker is
# invoked by xdg-desktop-portal-hyprland; slurp is used for region selection.
Requires:       gtk4-layer-shell
Requires:       xdg-desktop-portal-hyprland
Requires:       slurp

%description
hyprland-preview-share-picker is an alternative share picker for
xdg-desktop-portal-hyprland that renders live window and monitor previews when
selecting a screen-share source. omedora wires it in as the custom picker
binary for the portal's screencopy backend.

%prep
# Release tarball unpacks to %{name}-%{version}/.
%autosetup -n %{name}-%{version}
# Drop the hyprland-protocols submodule contents into lib/hyprland-protocols/.
# lib/src/protocols/*.rs reads ./hyprland-protocols/protocols/*.xml at build
# time (path relative to the lib/ crate root).
tar -xf %{SOURCE1}
rmdir lib/hyprland-protocols 2>/dev/null || true
mv hyprland-protocols-%{protocols_commit} lib/hyprland-protocols
# Unpack the (build-time-generated) cargo-vendor tarball (creates ./vendor/),
# then have %%cargo_prep wire .cargo/config.toml to it with offline mode on.
%setup -q -T -D -a 2 -n %{name}-%{version}
%cargo_prep -v vendor

%build
# build.rs shells out to `git describe` for a version banner; with no git repo
# it just warns and uses "unknown" — harmless.
# Offline build against the vendored crates (no crates.io).
%cargo_build
# Record the bundled crates' licenses + manifest for the %%license payload.
%{cargo_license_summary}
%{cargo_license} > LICENSE.dependencies
%{cargo_vendor_manifest}

%install
install -Dm0755 -t %{buildroot}%{_bindir} target/release/%{name}
# Ship the config schema (the AUR package does the same), generated by the
# freshly built binary.
./target/release/%{name} schema > schema.json
install -Dm0644 -t %{buildroot}%{_datadir}/%{name} schema.json

%files
%license LICENSE
# Aggregated dependency license info from the vendored crate tree.
%license LICENSE.dependencies
%license cargo-vendor.txt
%doc README.md
%{_bindir}/%{name}
%dir %{_datadir}/%{name}
%{_datadir}/%{name}/schema.json

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 0.2.1-1
- Initial from-source build of hyprland-preview-share-picker (cargo build).
- hyprland-protocols submodule fetched as Source1 (pinned commit 3a5c2bd) and
  staged into lib/hyprland-protocols for the build-time wayland-scanner step.
- Hermetic vendored/offline crate build (cargo-vendor tarball generated at
  SRPM-gen time), matching satty/swayosd; no crates.io access at build time.
