# lazygit.spec — terminal UI for git (jesseduffield's Go TUI).
#
# This is a BINARY-REPACKAGE spec (mirrors walker.spec): lazygit is a Go binary
# whose upstream ships a prebuilt x86_64 Linux release tarball, so there is no
# %build — %install just drops the prebuilt binary into /usr/bin. That gets us
# dnf tracking (clean install/remove/upgrade) for free.
#
# Why not Fedora main / RPM Fusion / a COPR: lazygit is in neither Fedora main
# nor RPM Fusion (confirmed against fedora:44). The well-known atim/lazygit COPR
# is NOT on omedora's COPR allowlist (which holds only scottames/ghostty, for
# the optional on-demand Ghostty terminal), so we build it ourselves. A
# from-source Go build is the more idiomatic Fedora form we'd
# refine to for a public COPR; binary-repackage is the fastest correct thing.

Name:           lazygit
Version:        0.62.2
Release:        1%{?dist}
Summary:        Simple terminal UI for git commands

License:        MIT
URL:            https://github.com/jesseduffield/lazygit

# Source0 is the upstream release tarball. Note the asset filename uses the bare
# version (no leading "v"), while the release tag is "v%%{version}". `spectool -g`
# (run by our build script) downloads it into SOURCES/.
Source0:        %{url}/releases/download/v%{version}/lazygit_%{version}_linux_x86_64.tar.gz

# Prebuilt x86_64 binary — this package is architecture-specific.
ExclusiveArch:  x86_64

# A prebuilt binary has no source to generate debuginfo from, and we don't want
# RPM to try to strip/process it. Disable both.
%global debug_package %{nil}
%global __os_install_post %{nil}

%description
Lazygit is a fast, terminal-based UI for git. It exposes staging, branching,
rebasing, stashing, and more through a keyboard-driven interface.

%prep
# The tarball contains LICENSE, README.md, and the `lazygit` binary with no
# top-level directory, so -c creates one (lazygit-%{version}) and -T/-a 0
# unpacks Source0 into it.
%setup -q -c -T -a 0

%build
# Nothing to compile — upstream shipped the binary.

%install
# Install the binary to /usr/bin (%{_bindir}). -D creates parent dirs;
# %{buildroot} is the staging tree RPM packs from.
install -D -m 0755 lazygit %{buildroot}%{_bindir}/lazygit

%files
%license LICENSE
%doc README.md
%{_bindir}/lazygit

%changelog
* Thu Jun 04 2026 omedora <noreply@omedora> - 0.62.2-1
- Bump to upstream 0.62.2.

* Sat May 30 2026 omedora <noreply@omedora> - 0.62.1-1
- Initial binary-repackage of upstream lazygit release.
