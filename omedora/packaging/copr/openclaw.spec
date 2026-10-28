# openclaw.spec — the release a self-updating OpenClaw starts from (omedora).
#
# This is a SEED spec, a variant of binary-repackage, and it mirrors Omarchy's
# Arch package (omacom-io/omarchy-pkgs pkgbuilds/openclaw) file for file. Since
# Omarchy 4.0.6 that package is NOT OpenClaw itself. It is the seed:
#   /usr/share/openclaw/openclaw.tgz     the npm release tarball, unmodified
#   /usr/share/openclaw/install-cli.sh   upstream's installer from that tarball,
#   /usr/share/openclaw/install-policy.sh  plus the helper it sources
#   /usr/share/openclaw/openclaw.png     the Control UI icon for the web app
# omarchy-install-openclaw-cli runs
#   bash /usr/share/openclaw/install-cli.sh --install-method npm \
#     --prefix ~/.openclaw --version /usr/share/openclaw/openclaw.tgz
# as the desktop user. That installs a private Node and the package into a
# prefix the user owns, which `openclaw update` and the Control UI's Update
# button then replace in place. A copy under /usr would belong to dnf, and
# upstream's updater refuses to write there, so nothing here goes on PATH.
#
# No npm vendoring: nothing is installed or compiled at build time. The npm
# dependency tree is resolved on the user's networked machine by upstream's
# installer, as on Arch. The only network fetch is Source0, sha256-pinned in
# openclaw.spec.sources and fetched in COPR's SRPM step, so the offline mock
# build just copies files.
#
# Upstream has no aarch64/x86_64 split in the tarball (the installer fetches
# the right Node), so the package is noarch.

Name:           openclaw
Version:        2026.10.7
Release:        1%{?dist}
Summary:        Seed for the self-updating OpenClaw AI gateway under ~/.openclaw

License:        MIT
URL:            https://github.com/openclaw/openclaw

# The npm registry tarball, as the Arch package uses (upstream's release cadence
# outruns the AUR, so Omarchy follows npm directly).
Source0:        https://registry.npmjs.org/%{name}/-/%{name}-%{version}.tgz

BuildArch:      noarch

BuildRequires:  bash
BuildRequires:  tar
BuildRequires:  gzip

# Upstream's installer: bash to run it; curl to fetch Node and npm packages;
# tar/gzip to unpack Node; sha256sum (coreutils) to verify it. git is the one
# thing it would otherwise try to install with sudo dnf, so it comes along, as
# on Arch (depends=(bash curl git)).
Requires:       bash
Requires:       curl
Requires:       git-core
Requires:       tar
Requires:       gzip
Requires:       coreutils
# Skills OpenClaw drives when present (the Arch package's optdepends that
# Fedora ships).
Suggests:       jq
Suggests:       ripgrep
Suggests:       tmux
Suggests:       ffmpeg-free
Suggests:       gh
Suggests:       uv

%description
OpenClaw is a multi-channel AI gateway with extensible messaging integrations.

This package is the release a self-updating OpenClaw starts from, not the
OpenClaw that runs: it ships the upstream npm release tarball, the installer
that came with it, and the Control UI icon under /usr/share/openclaw. Set it up
under ~/.openclaw with: omarchy-install-openclaw-cli --now
After that, OpenClaw updates itself with: openclaw update

%prep
# Only the installer, its helper, the icon and the license come out of the
# tarball; the tarball itself ships whole.
%setup -q -c -T
tar -xzf %{SOURCE0} \
  'package/scripts/install-*.sh' \
  package/dist/control-ui/apple-touch-icon.png \
  package/LICENSE

%build
# Nothing to build: the seed is the release as published.

%install
install -D -m 0644 %{SOURCE0} %{buildroot}%{_datadir}/%{name}/%{name}.tgz
# install-cli.sh sources its helpers from beside itself, so they ship with it.
install -m 0644 -t %{buildroot}%{_datadir}/%{name} package/scripts/install-*.sh
install -D -m 0644 package/dist/control-ui/apple-touch-icon.png \
  %{buildroot}%{_datadir}/%{name}/%{name}.png

%check
# Loading the installer from what this package ships fails the build, rather
# than every setup, if a helper it sources is missing. --help is offline.
bash %{buildroot}%{_datadir}/%{name}/install-cli.sh --help >/dev/null
test -s %{buildroot}%{_datadir}/%{name}/%{name}.tgz
test -s %{buildroot}%{_datadir}/%{name}/%{name}.png

%post
if [ "$1" -eq 1 ]; then
  echo "==> This is the release a self-updating OpenClaw starts from."
  echo "==> Set it up under ~/.openclaw: omarchy-install-openclaw-cli --now"
fi

%files
%license package/LICENSE
%dir %{_datadir}/%{name}
%{_datadir}/%{name}/%{name}.tgz
%{_datadir}/%{name}/install-*.sh
%{_datadir}/%{name}/%{name}.png

%changelog
* Tue Oct 27 2026 omedora <noreply@omedora> - 2026.10.7-1
- Initial seed package, mirroring Omarchy's Arch openclaw package: the npm
  release tarball, upstream's install-cli.sh (+ install-policy.sh) and the
  Control UI icon under /usr/share/openclaw, from which
  omarchy-install-openclaw-cli sets up the self-updating copy in ~/.openclaw.
