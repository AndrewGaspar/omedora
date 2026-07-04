# tensaku.spec — Wayland screenshot annotation tool (omedora).
#
# Tensaku (dev.tensaku.Tensaku) is the quattro line's replacement for satty as
# omarchy's screenshot/clipboard annotation editor. It is a FORK OF SATTY
# (Rust/GTK4 + libadwaita via relm4, plus OpenGL rendering and wlroots scroll-
# capture), MPL-2.0, by Jon Kinney — https://github.com/jondkinney/tensaku. This
# spec is modelled directly on omedora's satty.spec (the closest analog): a
# from-source cargo build, hermetically VENDORED so it builds offline in COPR's
# mock.
#
# WHY WE PACKAGE IT: upstream omarchy-base.packages pulls tensaku (Arch package,
# recipe in omacom-io/omarchy-pkgs). It ships /usr/bin/tensaku plus a
# /usr/bin/tensaku-edit bash wrapper that omarchy's capture scripts
# (omarchy-capture-screenshot, omarchy-clipboard-open, imv keybind) invoke as
# `tensaku-edit <img>`. Packaging it natively lets omedora adopt upstream's real
# editor instead of the satty shim (omedora/bin/tensaku-edit).
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
# Like satty, the UI is built in Rust via relm4 (no meson / blueprint-compiler).
# Tensaku's build.rs generates shell completions + a man page into top-level
# completions/ and man/ dirs when the `ci-release` cargo feature is on (mirrors
# satty's ci-release completion restore), so we build with that feature and
# install those artifacts alongside the binary.

Name:           tensaku
Version:        0.26.6
Release:        1%{?dist}
Summary:        Modern screenshot annotation tool for Wayland

# VENDORED LICENSE: the binary statically links its whole crate tree, so the
# License tag aggregates the licenses of ALL bundled crates, not just Tensaku's
# own (MPL-2.0; see LICENSE + NOTICE for the Satty attribution). The expression
# below is the AND of every distinct license emitted by
# `%%cargo_license_summary` over the vendored Cargo.lock; see the shipped
# LICENSE.dependencies / cargo-vendor.txt for the full per-crate breakdown.
License:        MPL-2.0 AND (Apache-2.0 OR MIT) AND ((Apache-2.0 OR MIT) AND CC0-1.0 AND MIT) AND ((MIT OR Apache-2.0) AND Unicode-3.0) AND Apache-2.0 AND (Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT) AND (BSD-3-Clause OR Apache-2.0) AND BSD-2-Clause AND BSD-3-Clause AND CC0-1.0 AND (CC0-1.0 OR Apache-2.0) AND ISC AND MIT AND (MIT OR Apache-2.0) AND (MIT OR Apache-2.0 OR Zlib) AND (MIT OR Zlib OR Apache-2.0) AND (Unlicense OR MIT) AND Zlib AND (Zlib OR Apache-2.0 OR MIT)
URL:            https://github.com/jondkinney/tensaku

# Source0: upstream source tarball. `spectool -g` (run by build-local.sh)
# fetches this into SOURCES/. GitHub's archive for tag vX.Y.Z unpacks to
# tensaku-X.Y.Z/. (The trailing /tensaku-<ver>.tar.gz just names the download;
# GitHub serves the same bytes as archive/refs/tags/v<ver>.tar.gz, which is what
# the AUR PKGBUILD pins.)
Source0:        %{url}/archive/refs/tags/v%{version}/%{name}-%{version}.tar.gz
# Source1: `cargo vendor` tarball of upstream's pinned Cargo.lock. NOT committed:
# build-local.sh generates it deterministically into SOURCES/ at SRPM-gen time
# (a COPR .copr/Makefile, #60, must do the same in its SRPM step). Unpacks to
# vendor/.
Source1:        %{name}-%{version}-vendor.tar.zst

# Compiled for x86_64 (the only arch omedora targets right now).
ExclusiveArch:  x86_64

# --- Build toolchain -------------------------------------------------------
# The Rust toolchain compiles the workspace (tensaku + tensaku_cli crates).
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
# gtk4-layer-shell crate links libgtk4-layer-shell (Tensaku's fullscreen overlay
# on wlroots) — this is the main dep beyond satty.
BuildRequires:  gtk4-layer-shell-devel
# The `epoxy` crate (an OpenGL function loader; Tensaku's HW-accelerated canvas)
# links system libepoxy and needs epoxy.pc at build time.
BuildRequires:  libepoxy-devel
# The `fontconfig` crate links system fontconfig for font loading.
BuildRequires:  fontconfig-devel
# The wayland-client / smithay-client-toolkit crates link libwayland-client for
# Tensaku's scrolling-screenshot capture.
BuildRequires:  wayland-devel
# desktop-file-utils validates the installed .desktop file.
BuildRequires:  desktop-file-utils

# --- Runtime ---------------------------------------------------------------
# RPM auto-detects the binary's link-time .so deps (gtk4, libadwaita, gdk-pixbuf,
# gtk4-layer-shell, libepoxy, fontconfig come along automatically). The shipped
# /usr/bin/tensaku-edit wrapper (what omedora's screenshot keybinding invokes)
# execs `wl-copy` to put the annotated image on the clipboard, so we require
# wl-clipboard explicitly — RPM can't see a dep hidden inside a bash script.
Requires:       wl-clipboard

%description
Tensaku is a screenshot annotation tool for Wayland, inspired by Swappy and
Flameshot and forked from Satty. It takes a captured image (e.g. from grim) and
provides a GTK4/libadwaita UI to draw rectangles, arrows, numbered markers,
text, blur, and highlights before saving or copying the result, with OpenGL
rendering, movable annotations, a layer panel, and wlroots scroll capture.
omedora uses it as the annotation step of its screenshot keybinding (via the
shipped tensaku-edit wrapper).

%prep
# GitHub tag archive unpacks to tensaku-%{version}/.
%autosetup -n %{name}-%{version}
# Unpack the (build-time-generated) vendor tarball (creates ./vendor/), then have
# %%cargo_prep wire .cargo/config.toml to it with offline mode on.
%setup -q -T -D -a 1 -n %{name}-%{version}
# Drop upstream's rust-toolchain.toml: it pins a specific rustup channel
# (1.95.0), which a rustup-managed cargo would try to auto-download — impossible
# in mock's offline build. Fedora's packaged cargo ignores it, but removing it
# makes the offline build robust regardless of the builder's cargo flavor.
rm -f rust-toolchain.toml
%cargo_prep -v vendor

%build
# Offline build of the workspace against the vendored sources (no crates.io).
# `ci-release` makes build.rs emit completions/ + man/ at the crate root (see
# header) so %%install can pick them up.
%cargo_build -f ci-release
# Record the bundled crates' licenses + manifest for the %%license payload.
%{cargo_license_summary}
%{cargo_license} > LICENSE.dependencies
%{cargo_vendor_manifest}

%install
# Mirror upstream Makefile's `install` target (PREFIX=%{_prefix}).
install -D -m 0755 target/release/tensaku %{buildroot}%{_bindir}/tensaku
install -D -m 0755 assets/tensaku-edit %{buildroot}%{_bindir}/tensaku-edit
install -D -m 0644 dev.tensaku.Tensaku.desktop \
  %{buildroot}%{_datadir}/applications/dev.tensaku.Tensaku.desktop
install -D -m 0644 assets/tensaku.svg \
  %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/dev.tensaku.Tensaku.svg
install -D -m 0644 man/tensaku.1 %{buildroot}%{_mandir}/man1/tensaku.1
install -D -m 0644 completions/tensaku.bash \
  %{buildroot}%{_datadir}/bash-completion/completions/tensaku
install -D -m 0644 completions/tensaku.fish \
  %{buildroot}%{_datadir}/fish/vendor_completions.d/tensaku.fish
install -D -m 0644 completions/_tensaku \
  %{buildroot}%{_datadir}/zsh/site-functions/_tensaku

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/dev.tensaku.Tensaku.desktop

%files
%license LICENSE
%license NOTICE
# Aggregated dependency license info from the vendored crate tree.
%license LICENSE.dependencies
%license cargo-vendor.txt
%doc README.md
%{_bindir}/tensaku
%{_bindir}/tensaku-edit
%{_datadir}/applications/dev.tensaku.Tensaku.desktop
%{_datadir}/icons/hicolor/scalable/apps/dev.tensaku.Tensaku.svg
%{_mandir}/man1/tensaku.1*
%{_datadir}/bash-completion/completions/tensaku
%{_datadir}/fish/vendor_completions.d/tensaku.fish
%{_datadir}/zsh/site-functions/_tensaku

%changelog
* Fri Jul 03 2026 omedora <noreply@omedora> - 0.26.6-1
- Initial from-source (cargo) build of Tensaku (Rust/GTK4 + relm4, a Satty
  fork; the quattro line's screenshot/clipboard annotation editor).
- Hermetic vendored/offline build (cargo-vendor tarball generated at SRPM-gen
  time from upstream's Cargo.lock; COPR-ready), mirroring satty.spec.
- Ships /usr/bin/tensaku + the /usr/bin/tensaku-edit wrapper omarchy's capture
  scripts invoke, plus the dev.tensaku.Tensaku .desktop/icon, man page, and
  bash/fish/zsh completions.
