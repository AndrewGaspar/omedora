# satty.spec — Wayland screenshot annotation tool (omedora).
#
# This is a FROM-SOURCE (cargo) spec. Satty is a Rust/GTK4 app (it uses relm4
# on top of gtk4-rs + libadwaita); upstream ships NO release binaries. It is not
# in Fedora main / RPM Fusion / the vetted COPR, and — despite being a GUI — it
# is NOT on Flathub (no com.gabm.satty or any variant exists; verified against
# the Flathub appstream + search API in May 2026). So we compile it ourselves.
#
# Build model mirrors swayosd.spec: `cargo` fetches crates from the network at
# build time (the fedora:44 build container has network; a COPR build host does
# too). A fully hermetic/offline build would vendor the crates — the same
# follow-up swayosd carries, not done here.
#
# Unlike swayosd, Satty has NO meson wrapper and NO blueprint-compiler step:
# the UI is built in Rust via relm4, so the toolchain is just cargo + the GTK4 /
# libadwaita -devel libraries the gtk4-rs/libadwaita-rs crates link against.
# %install follows upstream's Makefile `install` target (binary + .desktop +
# scalable icon + license).

Name:           satty
Version:        0.20.1
Release:        1%{?dist}
Summary:        A screenshot annotation tool inspired by Swappy and Flameshot

# Upstream LICENSE is MPL-2.0.
License:        MPL-2.0
URL:            https://github.com/gabm/Satty

# Upstream source tarball. `spectool -g` (run by build-local.sh) fetches this
# into SOURCES/. GitHub's archive for tag vX.Y.Z unpacks to Satty-X.Y.Z/.
Source0:        %{url}/archive/refs/tags/v%{version}/Satty-%{version}.tar.gz

# Compiled for x86_64 (the only arch omedora targets right now).
ExclusiveArch:  x86_64

# --- Build toolchain -------------------------------------------------------
# The Rust toolchain compiles the workspace (satty + satty_cli crates).
BuildRequires:  cargo
BuildRequires:  rust
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

%build
cargo build --release --locked

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
%doc README.md
%{_bindir}/satty
%{_datadir}/applications/satty.desktop
%{_datadir}/icons/hicolor/scalable/apps/satty.svg

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 0.20.1-1
- Initial from-source (cargo) build of Satty (Rust/GTK4, relm4; no meson).
- Crates fetched from network at build time; vendoring is a COPR follow-up.
