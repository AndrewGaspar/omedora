# lazydocker.spec — terminal UI for docker/podman (jesseduffield's Go TUI).
#
# This is a BINARY-REPACKAGE spec (mirrors walker.spec): lazydocker is a Go
# binary whose upstream ships a prebuilt x86_64 Linux release tarball, so there
# is no %build — %install just drops the prebuilt binary into /usr/bin. That
# gets us dnf tracking (clean install/remove/upgrade) for free.
#
# Why not Fedora main / RPM Fusion / a COPR: lazydocker is in neither Fedora
# main nor RPM Fusion (confirmed against fedora:44). The well-known
# atim/lazydocker COPR is NOT on omedora's COPR allowlist (which holds only
# scottames/ghostty, for the optional on-demand Ghostty terminal), so we build
# it ourselves. A from-source Go build is
# the more idiomatic Fedora form we'd refine to for a public COPR;
# binary-repackage is the fastest correct thing.

Name:           lazydocker
Version:        0.25.2
Release:        1%{?dist}
Summary:        Simple terminal UI for docker and docker-compose

License:        MIT
URL:            https://github.com/jesseduffield/lazydocker

# Source0 is the upstream release tarball. Note the asset filename uses the bare
# version (no leading "v") and a capitalized "Linux", while the release tag is
# "v%%{version}". `spectool -g` (run by our build script) downloads it into
# SOURCES/.
Source0:        %{url}/releases/download/v%{version}/lazydocker_%{version}_Linux_x86_64.tar.gz

# Prebuilt x86_64 binary — this package is architecture-specific.
ExclusiveArch:  x86_64

# A prebuilt binary has no source to generate debuginfo from, and we don't want
# RPM to try to strip/process it. Disable both.
%global debug_package %{nil}
%global __os_install_post %{nil}

%description
Lazydocker is a fast, terminal-based UI for docker and docker-compose (works
with podman too). It surfaces container/image/volume state, logs, and stats
through a keyboard-driven interface.

%prep
# The tarball contains LICENSE, README.md, and the `lazydocker` binary with no
# top-level directory, so -c creates one (lazydocker-%{version}) and -T/-a 0
# unpacks Source0 into it.
%setup -q -c -T -a 0

%build
# Nothing to compile — upstream shipped the binary.

%install
# Install the binary to /usr/bin (%{_bindir}). -D creates parent dirs;
# %{buildroot} is the staging tree RPM packs from.
install -D -m 0755 lazydocker %{buildroot}%{_bindir}/lazydocker

%files
%license LICENSE
%doc README.md
%{_bindir}/lazydocker

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 0.25.2-1
- Initial binary-repackage of upstream lazydocker release.
