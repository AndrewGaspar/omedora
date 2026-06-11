# walker.spec — Wayland-native application launcher (Super+Space in omedora).
#
# This is a BINARY-REPACKAGE spec: it takes upstream's prebuilt release binary
# and wraps it in an RPM. That gets us the two things the source installer
# couldn't: dnf tracking (clean install/remove/upgrade) and automatic
# dependency resolution via `Requires:` (so gtk4-layer-shell is pulled in for
# us instead of failing at runtime).
#
# A "from source" spec (compile with the Go toolchain) is the more idiomatic
# Fedora form and what we'd refine to for a public COPR; binary-repackage is
# the fastest correct thing for local testing.

Name:           walker
Version:        2.16.2
Release:        1%{?dist}
Summary:        Wayland-native application launcher

# TODO: confirm upstream license string before publishing to a COPR.
License:        MIT
URL:            https://github.com/abenz1267/walker

# Source0 is the upstream release tarball. `spectool -g` (run by our build
# script) downloads it into SOURCES/ from this URL. The %%{version} macro keeps
# the URL and the Version: field in sync.
Source0:        %{url}/releases/download/v%{version}/walker-v%{version}-x86_64-unknown-linux-gnu.tar.gz

# Prebuilt x86_64 binary — this package is architecture-specific.
ExclusiveArch:  x86_64

# THE PAYOFF: dnf will install gtk4-layer-shell automatically. (walker also
# needs gtk4 at runtime, which gtk4-layer-shell itself depends on, so it comes
# along transitively.)
Requires:       gtk4-layer-shell

# A prebuilt binary has no source to generate debuginfo from, and we don't want
# RPM to try to strip/process it. Disable both.
%global debug_package %{nil}
%global __os_install_post %{nil}

%description
Walker is a fast, Wayland-native application launcher and menu used by omedora
for Super+Space and the omarchy menu. It talks to the Elephant data-provider
backend over a socket.

%prep
# The tarball contains a single file `walker` with no top-level directory, so
# -c creates one (walker-%{version}) and -T/-a 0 unpacks Source0 into it.
%setup -q -c -T -a 0

%build
# Nothing to compile — upstream shipped the binary.

%install
# Install the binary to /usr/bin (the standard %{_bindir}). -D creates parent
# dirs; %{buildroot} is the staging tree RPM packs from.
install -D -m 0755 walker %{buildroot}%{_bindir}/walker

%files
# Everything this package owns. Must match what %install placed.
%{_bindir}/walker

%changelog
* Fri May 29 2026 omedora <noreply@omedora> - 2.16.2-1
- Initial binary-repackage of upstream walker release.
