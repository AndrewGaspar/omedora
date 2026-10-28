# disktree.spec — disk space treemap (omedora).
#
# disktree (github.com/tobi/disktree, MIT) replaces dua-cli in Omarchy 4.5's
# base set (migration 1791345484 adds it and drops dua-cli). Arch ships the
# upstream release binary as disktree-bin; this is the same BINARY-REPACKAGE
# (like lazygit.spec): the linux-x86_64 release tarball, installed per the
# omarchy-pkgs PKGBUILD's package(). install/packages/fedora.toml maps
# disktree-bin to this package.

Name:           disktree
Version:        0.11.0
Release:        1%{?dist}
Summary:        Disk space treemap: see what fills a disk, mark what should go, remove it

License:        MIT
URL:            https://github.com/tobi/disktree
Source0:        %{url}/releases/download/v%{version}/%{name}-%{version}-x86_64-linux.tar.gz

ExclusiveArch:  x86_64

# Prebuilt upstream binary: nothing to extract debug info from or strip again.
%global debug_package %{nil}
%global __os_install_post %{nil}

BuildRequires:  desktop-file-utils

# The binary dlopens EGL and the Wayland client/EGL libraries (it links only
# libxcb/libxkbcommon), so automatic requires miss them.
Requires:       libglvnd-egl
Requires:       libwayland-client
Requires:       libwayland-egl

%description
disktree draws a volume as a treemap coloured by kind of file, so what fills
the disk is visible at a glance. Mark what should go and remove it, to the
trash or for good.

%prep
%setup -q -n %{name}-%{version}-x86_64-linux

%build

%install
install -D -m 0755 %{name} %{buildroot}%{_bindir}/%{name}
install -d %{buildroot}%{_datadir}/applications
sed -e 's|@BINDIR@/||' -e 's|@VERSION@|%{version}|' %{name}.desktop.in \
  >%{buildroot}%{_datadir}/applications/%{name}.desktop
chmod 0644 %{buildroot}%{_datadir}/applications/%{name}.desktop
install -D -m 0644 %{name}.svg \
  %{buildroot}%{_datadir}/icons/hicolor/scalable/apps/%{name}.svg

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/%{name}.desktop

%files
%license LICENSE
%doc README.md
%{_bindir}/disktree
%{_datadir}/applications/%{name}.desktop
%{_datadir}/icons/hicolor/scalable/apps/%{name}.svg

%changelog
* Tue Oct 27 2026 omedora <noreply@omedora> - 0.11.0-1
- Initial binary-repackage of the upstream disktree release (Omarchy 4.5's
  dua-cli replacement), laid out per the omarchy-pkgs PKGBUILD.
