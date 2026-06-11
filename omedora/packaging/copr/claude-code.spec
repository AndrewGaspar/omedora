# claude-code.spec — Anthropic's agentic terminal coding tool (omedora).
#
# This is a BINARY-REPACKAGE spec (like walker.spec): upstream distributes
# claude-code as a single self-contained Bun executable (embedded JS +
# resources, ~240 MB). It is NOT an npm package on this path and NOT a
# distro package; omarchy installs the very same prebuilt binary from
# downloads.claude.ai. We mirror omarchy's approach exactly so behavior matches
# Arch: drop the binary in /opt/claude-code/bin/claude and ship a /usr/bin/claude
# wrapper that exports DISABLE_UPDATES=1 (the RPM, not claude's self-updater,
# owns the binary).
#
# LICENSING NOTE (needs human sign-off before this is served from a public
# COPR): claude-code is proprietary (License: LicenseRef-claude-code, Anthropic
# terms). Redistributing the binary from the omedora repo is a redistribution
# decision. The omarchy AUR package sidesteps this by downloading at build time
# from Anthropic's CDN; a COPR build host does the same here (the binary is a
# build-time Source, not committed to this repo). Confirm this is acceptable
# before publishing.
#
# The binary is a self-contained Bun executable; stripping breaks the embedded
# payload, so disable strip + debug processing (matches the AUR's options=(!strip)).

Name:           claude-code
Version:        2.1.156
Release:        1%{?dist}
Summary:        Agentic coding tool that lives in your terminal

# Proprietary Anthropic license (the AUR uses LicenseRef-claude-code).
License:        LicenseRef-claude-code
URL:            https://github.com/anthropics/claude-code

# Upstream's prebuilt self-contained Bun binary for linux-x64, fetched at build
# time by spectool -g (run by build-local.sh). Renamed via #/ so the local file
# is versioned. Matches the URL omarchy's PKGBUILD downloads.
Source0:        https://downloads.claude.ai/claude-code-releases/%{version}/linux-x64/claude#/claude-%{version}-x86_64
# Upstream legal/compliance text, shipped as the license doc (as the AUR does).
Source1:        https://code.claude.com/docs/en/legal-and-compliance.md#/claude-code-legal.md

# Prebuilt x86_64 binary — architecture-specific.
ExclusiveArch:  x86_64

# Runtime: the wrapper is /bin/sh; claude shells out to common tools. bash is
# the only hard dep the AUR declares; the rest are optdepends the user already
# has under omedora (git, gh, ripgrep, etc.).
Requires:       bash

# A prebuilt self-contained binary has no source for debuginfo and must NOT be
# stripped (it breaks the embedded Bun resources). Disable both.
%global debug_package %{nil}
%global __os_install_post %{nil}

%description
Claude Code is Anthropic's agentic coding tool that lives in your terminal.
This package repackages upstream's prebuilt self-contained binary (the same
artifact omarchy installs on Arch) and disables its in-place self-updater so
the binary is managed by the package manager.

%prep
# Nothing to unpack — Source0 is a single binary.

%build
# Nothing to compile — upstream shipped the binary.

%install
# The self-contained Bun binary under /opt (matches omarchy's layout).
install -D -m 0755 %{SOURCE0} %{buildroot}/opt/claude-code/bin/claude
# Wrapper on PATH that disables upstream's self-update path.
install -d -m 0755 %{buildroot}%{_bindir}
cat > %{buildroot}%{_bindir}/claude << 'EOF'
#!/bin/sh
export DISABLE_UPDATES=1
exec /opt/claude-code/bin/claude "$@"
EOF
chmod 0755 %{buildroot}%{_bindir}/claude
# Legal text as the package's license document.
install -D -m 0644 %{SOURCE1} %{buildroot}%{_licensedir}/%{name}/LICENSE

%files
%license %{_licensedir}/%{name}/LICENSE
%dir /opt/claude-code
%dir /opt/claude-code/bin
/opt/claude-code/bin/claude
%{_bindir}/claude

%changelog
* Sat May 30 2026 omedora <noreply@omedora> - 2.1.156-1
- Initial binary-repackage of upstream claude-code (self-contained Bun binary),
  mirroring omarchy's PKGBUILD: /opt/claude-code/bin/claude + /usr/bin/claude
  wrapper exporting DISABLE_UPDATES=1.
- Proprietary; public-COPR redistribution pending human sign-off.
