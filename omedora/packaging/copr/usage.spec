# usage.spec — jdx's spec-driven CLI tool (a mise companion).
#
# This is a BINARY-REPACKAGE spec (like walker.spec): usage is a Rust project
# but upstream ships a prebuilt x86_64 release binary, so we wrap that rather
# than compile from source. That gets us dnf tracking (clean
# install/remove/upgrade) for the omedora repo with the least moving parts. A
# from-source cargo build would be the more idiomatic public-COPR form
# (cf. swayosd.spec); binary-repackage is the fastest correct thing for the
# local repo.
#
# `usage` defines CLIs via a KDL spec and powers mise's completions/help, so it
# travels with mise in the omedora shell-tooling cluster. The release tarball
# holds the `usage` binary plus its man page, with no top-level directory, so
# %setup -c -T -a 0 creates one and unpacks into it.

Name:           usage
Version:        3.5.0
Release:        1%{?dist}
Summary:        Spec for defining CLIs, with autocompletion and more (mise companion)

# Upstream LICENSE is MIT (Copyright (c) 2025 Jeff Dickey).
License:        MIT
URL:            https://github.com/jdx/usage

# Source0 is the upstream prebuilt glibc release tarball. spectool -g (run by
# build-local.sh) downloads it into SOURCES/. The tarball contains `usage` and
# `usage.1` with no top-level directory.
Source0:        %{url}/releases/download/v%{version}/usage-x86_64-unknown-linux-gnu.tar.gz

# Prebuilt x86_64 binary — architecture-specific.
ExclusiveArch:  x86_64

# A prebuilt binary has no source to generate debuginfo from, and we don't want
# RPM to strip/process it. Disable both (mirrors walker.spec).
%global debug_package %{nil}
%global __os_install_post %{nil}

%description
usage is a specification (and CLI) for defining command-line interfaces in a
KDL document, providing autocompletion, help, and argument parsing. It is a
companion to mise (both by jdx), which uses it to power completions and help.

%prep
# The tarball contains `usage` + `usage.1` with no top-level directory, so -c
# creates one (usage-%{version}) and -T/-a 0 unpacks Source0 into it.
%setup -q -c -T -a 0

%install
install -D -m 0755 usage %{buildroot}%{_bindir}/usage
install -D -m 0644 usage.1 %{buildroot}%{_mandir}/man1/usage.1

%files
%{_bindir}/usage
%{_mandir}/man1/usage.1*

%changelog
* Tue Jun 16 2026 omedora <noreply@omedora> - 3.5.0-1
- Bump to upstream 3.5.0.

* Thu Jun 04 2026 omedora <noreply@omedora> - 3.4.0-1
- Bump to upstream 3.4.0.

* Sat May 30 2026 omedora <noreply@omedora> - 3.3.0-1
- Initial binary-repackage of upstream usage release.
