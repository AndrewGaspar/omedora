# elephant.spec — data-provider backend for walker.
#
# Like walker.spec, this is a binary-repackage of upstream's release. It turned
# out elephant needs NO from-source build and NO symlink hack: its provider
# loader (internal/providers/load.go) searches a built-in libDirs list that
# includes /usr/lib/elephant, *plus* ~/.config — so a system package just drops
# the provider plugins in /usr/lib/elephant/providers/ and elephant finds them.
#
# elephant ships as a core executable plus one Go-plugin (.so) per provider,
# all built together in the same release so their plugin ABI matches. We ship
# the providers omedora's walker config + omarchy-menu actually use.

Name:           elephant
Version:        2.21.0
Release:        1%{?dist}
Summary:        Data provider and executor backend for the Walker launcher

# TODO: confirm upstream license string before publishing to a COPR.
License:        MIT
URL:            https://github.com/abenz1267/elephant

# Core executable.
Source0:        %{url}/releases/download/v%{version}/elephant-linux-amd64.tar.gz
# Provider plugins (one .so each). Keep this list in sync with the %%install
# loop and the omedora walker config (config/walker/config.toml).
Source1:        %{url}/releases/download/v%{version}/desktopapplications-linux-amd64.tar.gz
Source2:        %{url}/releases/download/v%{version}/websearch-linux-amd64.tar.gz
Source3:        %{url}/releases/download/v%{version}/providerlist-linux-amd64.tar.gz
Source4:        %{url}/releases/download/v%{version}/files-linux-amd64.tar.gz
Source5:        %{url}/releases/download/v%{version}/symbols-linux-amd64.tar.gz
Source6:        %{url}/releases/download/v%{version}/calc-linux-amd64.tar.gz
Source7:        %{url}/releases/download/v%{version}/clipboard-linux-amd64.tar.gz
Source8:        %{url}/releases/download/v%{version}/menus-linux-amd64.tar.gz
Source9:        %{url}/releases/download/v%{version}/runner-linux-amd64.tar.gz

ExclusiveArch:  x86_64

# Provides the %%{_userunitdir} macro (path for systemd *user* units).
BuildRequires:  systemd-rpm-macros

# calc provider dlopen's libqalculate at runtime; without it the `=` calc prefix
# silently disables itself. RPM auto-detects the core/plugin .so library needs,
# but libqalculate is a runtime (not link-time) dep, so name it explicitly.
Requires:       libqalculate

# Prebuilt binaries: no debuginfo, and DO NOT strip — Go plugins carry build
# metadata that plugin.Open() verifies; stripping can make them fail to load.
%global debug_package %{nil}
%global __os_install_post %{nil}

%description
Elephant is the data-provider and executor backend that the Walker launcher
queries over a socket. It loads provider plugins (application launching, file
search, calculator, clipboard, menus, etc.) and exposes them to Walker.

%prep
# No shared top-level dir across the tarballs; just unpack each Source into the
# build dir by hand. %%setup -c -T makes the empty dir; -a N adds Source N.
%setup -q -c -T
# Unpack the core + every provider tarball (each yields <name>-linux-amd64.so).
for f in %{SOURCE0} %{SOURCE1} %{SOURCE2} %{SOURCE3} %{SOURCE4} %{SOURCE5} \
         %{SOURCE6} %{SOURCE7} %{SOURCE8} %{SOURCE9}; do
  %{__tar} -xzf "$f"
done

%build
# Nothing to compile.

%install
# Core binary.
install -D -m 0755 elephant-linux-amd64 %{buildroot}%{_bindir}/elephant

# Provider plugins → /usr/lib/elephant/providers/<name>.so (a built-in libDir).
# Strip the "-linux-amd64" suffix so the filenames read as plain provider names.
provdir=%{buildroot}%{_prefix}/lib/elephant/providers
install -d "$provdir"
for so in *-linux-amd64.so; do
  install -m 0644 "$so" "$provdir/${so%-linux-amd64.so}.so"
done

# systemd *user* service. elephant runs per-user alongside the graphical
# session (it needs the user's WAYLAND_DISPLAY / env). This mirrors the unit
# `elephant service enable` would generate.
install -d %{buildroot}%{_userunitdir}
cat > %{buildroot}%{_userunitdir}/elephant.service <<'EOF'
[Unit]
Description=Elephant data provider
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=%{_bindir}/elephant
Restart=on-failure

[Install]
WantedBy=graphical-session.target
EOF

%files
%{_bindir}/elephant
%dir %{_prefix}/lib/elephant
%dir %{_prefix}/lib/elephant/providers
%{_prefix}/lib/elephant/providers/*.so
%{_userunitdir}/elephant.service

%changelog
* Fri May 29 2026 omedora <noreply@omedora> - 2.21.0-1
- Initial binary-repackage of elephant core + the providers omedora uses.
- Providers install to /usr/lib/elephant/providers (a built-in elephant libDir).
