# mise.spec — polyglot dev-tool/runtime version manager (asdf successor).
#
# This is a BINARY-REPACKAGE spec (like walker.spec / elephant.spec): mise is a
# Rust project but upstream ships a fully self-contained prebuilt release
# tarball for linux-x64, so we wrap that rather than compile from source. That
# gets us dnf tracking (clean install/remove/upgrade) for the omedora repo with
# the least moving parts. A from-source cargo build would be the more idiomatic
# public-COPR form (cf. swayosd.spec); binary-repackage is the fastest correct
# thing for the local repo.
#
# The upstream tarball is a small self-contained tree (bin/mise, a fish vendor
# activation snippet, a man page, LICENSE). We ship the binary, man page, the
# fish vendor_conf.d snippet, and the license; we drop bin/mise.d, which is a
# leaked cargo dep-list build artifact (full of /project/... build paths) of no
# runtime value.

Name:           mise
Version:        2026.6.11
Release:        1%{?dist}
Summary:        Polyglot dev tool and runtime version manager

# Upstream LICENSE is MIT (Copyright (c) 2025 Jeff Dickey).
License:        MIT
URL:            https://github.com/jdx/mise

# Source0 is the upstream linux-x64 release tarball (glibc build). spectool -g
# (run by build-local.sh) downloads it into SOURCES/. The %%{version} macro
# keeps the URL in sync with Version:. The tarball unpacks to a top-level
# `mise/` directory.
Source0:        %{url}/releases/download/v%{version}/mise-v%{version}-linux-x64.tar.gz

# Prebuilt x86_64 binary — architecture-specific.
ExclusiveArch:  x86_64

# A prebuilt binary has no source to generate debuginfo from, and we don't want
# RPM to strip/process it. Disable both (mirrors walker.spec/elephant.spec).
%global debug_package %{nil}
%global __os_install_post %{nil}

%description
mise (formerly rtx) is a fast, polyglot tool-version manager — a drop-in
replacement for asdf — that also handles environment variables and project task
running. omedora uses it as the developer runtime manager; its shell activation
is wired up per-user.

%prep
# The tarball unpacks to a top-level mise/ directory; -n names it so setup
# cd's into the literal `mise` dir (not the default name-version dir).
%setup -q -n mise

%install
install -D -m 0755 bin/mise %{buildroot}%{_bindir}/mise
# Man page.
install -D -m 0644 man/man1/mise.1 %{buildroot}%{_mandir}/man1/mise.1
# Fish vendor activation snippet (auto-sourced by fish from vendor_conf.d).
install -D -m 0644 share/fish/vendor_conf.d/mise-activate.fish \
    %{buildroot}%{_datadir}/fish/vendor_conf.d/mise-activate.fish

%files
%license LICENSE
%doc README.md
%{_bindir}/mise
%{_mandir}/man1/mise.1*
%{_datadir}/fish/vendor_conf.d/mise-activate.fish

%changelog
* Tue Jun 16 2026 omedora <noreply@omedora> - 2026.6.11-1
- Bump to upstream 2026.6.11.

* Thu Jun 04 2026 omedora <noreply@omedora> - 2026.6.0-1
- Bump to upstream 2026.6.0.

* Sat May 30 2026 omedora <noreply@omedora> - 2026.5.16-1
- Initial binary-repackage of upstream mise linux-x64 release.
