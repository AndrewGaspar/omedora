# starship.spec — cross-shell prompt (the omedora shell prompt).
#
# This is a BINARY-REPACKAGE spec (like walker.spec): starship is a Rust
# project but upstream ships a prebuilt x86_64 release binary, so we wrap that
# rather than compile from source. That gets us dnf tracking (clean
# install/remove/upgrade) for the omedora repo with the least moving parts. A
# from-source cargo build would be the more idiomatic public-COPR form
# (cf. swayosd.spec); binary-repackage is the fastest correct thing for the
# local repo.
#
# The release tarball is a single `starship` binary with no top-level
# directory, so %setup -c -T -a 0 creates one and unpacks into it (same shape
# as walker.spec).

Name:           starship
Version:        1.25.1
Release:        1%{?dist}
Summary:        Minimal, blazing-fast, cross-shell prompt

# Upstream LICENSE is ISC (Copyright (c) 2019-2022, Starship Contributors).
License:        ISC
URL:            https://github.com/starship/starship

# Source0 is the upstream prebuilt glibc release tarball. spectool -g (run by
# build-local.sh) downloads it into SOURCES/. The tarball contains a single
# `starship` file with no top-level directory.
Source0:        %{url}/releases/download/v%{version}/starship-x86_64-unknown-linux-gnu.tar.gz

# Prebuilt x86_64 binary — architecture-specific.
ExclusiveArch:  x86_64

# A prebuilt binary has no source to generate debuginfo from, and we don't want
# RPM to strip/process it. Disable both (mirrors walker.spec).
%global debug_package %{nil}
%global __os_install_post %{nil}

%description
Starship is a minimal, blazing-fast, and infinitely customizable prompt for any
shell. omedora uses it as the default shell prompt; its per-shell init is wired
up per-user.

%prep
# The tarball contains a single file `starship` with no top-level directory, so
# -c creates one (starship-%{version}) and -T/-a 0 unpacks Source0 into it.
%setup -q -c -T -a 0

%install
install -D -m 0755 starship %{buildroot}%{_bindir}/starship

%files
%{_bindir}/starship

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 1.25.1-1
- Initial binary-repackage of upstream starship release.
