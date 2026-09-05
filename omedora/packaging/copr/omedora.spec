# omedora.spec — Fedora analogue of upstream's `omarchy` Arch package (whose
# PKGBUILD lives in DHH's private omarchy-pkgs repo). The authoritative payload
# recipe is docs/file-layout.md's "Build-time map (repo -> installed paths)".
#
# Split (mirrors upstream): this package is the RUNTIME — every bin/ command
# (incl. the omedora-* Fedora helpers and the bin/fedora/ pkg backends), the
# install/finalize scripts, migrations, themes, and the Quickshell desktop
# (shell/). It Requires omedora-settings (the pre-install seeds/system files,
# Fedora analogue of omarchy-settings).
#
# Internal install paths deliberately stay /usr/share/omarchy and
# /usr/bin/omarchy-* (NOT renamed): every script keys off
# OMARCHY_PATH=/usr/share/omarchy, and staying name-compatible keeps upstream
# rebases mechanical.
#
# FEDORA DEVIATION from the map: default/libalpm/hooks/00-omarchy-update-guard
# (a pacman hook, the only `omarchy`-package entry outside bin/install/
# migrations/themes/shell) is SKIPPED — no pacman on Fedora.

Name:           omedora
# Version is normally read from the repo's omedora/version file; hardcoded here
# for now — a follow-up wires .copr/srpm.sh to substitute it at SRPM-gen time.
Version:        0.2.0~beta.3
Release:        1%{?dist}
Summary:        Omedora runtime: omarchy commands, installer, migrations, themes, Quickshell desktop

License:        MIT
URL:            https://github.com/omedora/omedora
# SELF-SOURCE marker: this package's source is THIS repo itself. The bare
# filename `omedora-self.tar.gz` tells .copr/srpm.sh and build-local.sh to
# produce the tarball via `git archive --prefix=omedora-%%{version}/ HEAD`
# from the repo checkout instead of spectool-fetching a URL. No sha256 pin
# applies (the tarball is generated from the local tree, not fetched).
Source0:        omedora-self.tar.gz

BuildArch:      noarch

# Fedora stand-in for upstream's `omarchy` Arch package.
Provides:       omarchy = %{version}-%{release}

# The pre-install half (seeds /etc/skel, system defaults, fonts, branding,
# session entry).
Requires:       omedora-settings

# HARD runtime essentials ONLY — what this package's own scripts need to run at
# all (modeled on install/omarchy-base.packages, deliberately NOT the full
# desktop set: the full set is installed by the omedora install transaction,
# per install/omarchy-base.packages + install/packages/fedora.toml).
#   bash/jq/gum/fzf — the bin/omarchy-* command family's interpreters + menus
#   python3         — bin/fedora package-map and managed-update backends
#   quickshell      — the shell/ Quickshell desktop (lock/OSD/launcher/bar)
#   foot            — default terminal omarchy-launch-* falls back to
#   uwsm            — the session manager the omedora session launches through
#   hyprland        — the compositor (vendored hyprland.spec in this dir).
#       NOTE: once the rebuilt hyprland RPM with the no-session split is in the
#       repo, this could tighten to hyprland-no-session to keep the plain
#       visible "Hyprland" login entry off GDM (the omedora.desktop entry from
#       omedora-settings is meant to be the only visible session).
Requires:       bash
Requires:       jq
Requires:       gum
Requires:       python3
Requires:       hyprland-no-session
Requires:       uwsm
Requires:       quickshell
Requires:       foot
Requires:       fzf

# Auto-requires are suppressed for the /usr/share/omarchy and /etc/skel payload
# (installer/migration/theme scripts run inside the fully-provisioned install,
# not as RPM-time dependencies); /usr/bin scripts still get their interpreter
# deps generated (bash, python3 — both also explicit above).
%global __requires_exclude_from ^(%{_datadir}/omarchy/|/etc/skel/)
# Ship scripts byte-for-byte as committed (no shebang rewriting).
%global __brp_mangle_shebangs %{nil}

%description
The Omedora runtime: the omarchy/omedora command family in /usr/bin (plus the
bin/fedora dnf backends), install and finalize scripts, system/user
migrations, themes, and the Quickshell desktop shell, all rooted at
/usr/share/omarchy (OMARCHY_PATH). Fedora port of upstream's omarchy package;
depends on omedora-settings for the /etc/skel seeds and system defaults.

%prep
# Source0 is the whole repo (git archive, prefix omedora-%%{version}).
%setup -q -n omedora-%{version}

%build
# Nothing to build (noarch script/data package).

%install
# ---------------------------------------------------------------------------
# /usr/bin: bin/omarchy, bin/omarchy-*, bin/omedora* (symlink preserved:
# omedora -> omarchy) and the bin/fedora/ backend dir. bin/fedora/ MUST live
# beside the omarchy-pkg-* scripts (they exec
# "$(dirname BASH_SOURCE)/fedora/pkg…"), hence /usr/bin/fedora/.
# ---------------------------------------------------------------------------
install -d %{buildroot}%{_bindir}
cp -a bin/. %{buildroot}%{_bindir}/
# The live-ISO debug trio ships in omedora-settings (needed on the target
# before this package installs, per the map) — drop it from this payload.
rm %{buildroot}%{_bindir}/omarchy-debug \
   %{buildroot}%{_bindir}/omarchy-debug-idle \
   %{buildroot}%{_bindir}/omarchy-upload-log

# Symlink farm /usr/share/omarchy/bin -> /usr/bin (the map's "and symlinks in
# /usr/share/omarchy/bin/"; used when scripts resolve siblings via
# $OMARCHY_PATH/bin). The settings package adds the debug trio's links.
install -d %{buildroot}%{_datadir}/omarchy/bin
for f in %{buildroot}%{_bindir}/*; do
  name=$(basename "$f")
  ln -s "%{_bindir}/$name" "%{buildroot}%{_datadir}/omarchy/bin/$name"
done

# ---------------------------------------------------------------------------
# /usr/share/omarchy payload.
# ---------------------------------------------------------------------------
cp -a install %{buildroot}%{_datadir}/omarchy/install
cp -a migrations %{buildroot}%{_datadir}/omarchy/migrations
# migrations/system/ is currently empty (git doesn't track empty dirs) but
# omarchy-migrate-system globs it — make sure it exists either way.
install -d %{buildroot}%{_datadir}/omarchy/migrations/system
cp -a themes %{buildroot}%{_datadir}/omarchy/themes
cp -a shell %{buildroot}%{_datadir}/omarchy/shell
# Omarchy base version + omedora's own SemVer (read by omedora-release and
# omarchy-update-available).
install -pm644 version %{buildroot}%{_datadir}/omarchy/version
install -Dpm644 omedora/version %{buildroot}%{_datadir}/omarchy/omedora/version
install -Dpm644 omedora/base-version %{buildroot}%{_datadir}/omarchy/omedora/base-version
# Fedora-only packages that complement upstream's base list. The managed update
# resolver reads this from the installed payload as well as from source trees.
install -Dpm644 omedora/install/fedora-baseline.packages \
  %{buildroot}%{_datadir}/omarchy/omedora/install/fedora-baseline.packages

# omedora helper binaries that live under the payload (not /usr/bin) because
# they're sourced/copied by install steps via $OMARCHY_PATH, not run as
# omarchy-* commands. powerprofilesctl-shim: copied to ~/.local/bin by
# install/user/powerprofilesctl-shim-fedora.sh (tuned-ppd has no CLI).
install -Dpm755 omedora/bin/powerprofilesctl-shim %{buildroot}%{_datadir}/omarchy/omedora/bin/powerprofilesctl-shim
# tensaku-edit: copied to ~/.local/bin by install/user/tensaku-edit-shim-fedora.sh
# (quattro swapped satty -> the Arch-only tensaku; this shim wraps satty).
install -Dpm755 omedora/bin/tensaku-edit %{buildroot}%{_datadir}/omarchy/omedora/bin/tensaku-edit

# /etc/skel: pre-applied user-migration markers (per the map's `version` row).
# A NEW user starts at the shipped migration level — omarchy-migrate-user
# treats a missing state file as "pending", and useradd -m copies these
# markers into the fresh $HOME (same names omarchy-provision-user touches).
install -d %{buildroot}/etc/skel/.local/state/omarchy/migrations/user
for m in migrations/user/*.sh; do
  [ -f "$m" ] || continue
  touch "%{buildroot}/etc/skel/.local/state/omarchy/migrations/user/$(basename "$m")"
done

%check
# Syntax-check the dispatcher (cheap smoke that the payload is a runnable tree).
bash -n %{buildroot}%{_bindir}/omarchy

%post
# On UPGRADE only ($1 > 1): apply pending system migrations, mirroring
# upstream's post_upgrade() -> omarchy-migrate-system. Best-effort: in a
# minimal chroot the command (or what a migration needs) may be unavailable,
# and a failed migration must never fail the RPM transaction.
if [ "$1" -gt 1 ]; then
  if command -v omarchy-migrate-system >/dev/null 2>&1; then
    omarchy-migrate-system || :
  fi
fi

%files
%license LICENSE
# Command family: the dispatcher, every omarchy-* (minus the debug trio owned
# by omedora-settings — excluded in %%install so this glob can't match them),
# the omedora-* helpers (incl. the omedora -> omarchy symlink), and the
# bin/fedora/ dnf backend dir.
%{_bindir}/omarchy
%{_bindir}/omarchy-*
%{_bindir}/omedora
%{_bindir}/omedora-*
%{_bindir}/fedora/
# /usr/share/omarchy (dir + bin farm co-owned with omedora-settings).
%dir %{_datadir}/omarchy
%dir %{_datadir}/omarchy/bin
%{_datadir}/omarchy/bin/omarchy
%{_datadir}/omarchy/bin/omarchy-*
%{_datadir}/omarchy/bin/omedora
%{_datadir}/omarchy/bin/omedora-*
%{_datadir}/omarchy/bin/fedora
%{_datadir}/omarchy/install/
%{_datadir}/omarchy/migrations/
%{_datadir}/omarchy/themes/
%{_datadir}/omarchy/shell/
%{_datadir}/omarchy/version
%dir %{_datadir}/omarchy/omedora
%{_datadir}/omarchy/omedora/version
%{_datadir}/omarchy/omedora/base-version
%dir %{_datadir}/omarchy/omedora/install
%{_datadir}/omarchy/omedora/install/fedora-baseline.packages
%dir %{_datadir}/omarchy/omedora/bin
%{_datadir}/omarchy/omedora/bin/powerprofilesctl-shim
%{_datadir}/omarchy/omedora/bin/tensaku-edit
# Pre-applied user-migration markers for new users.
/etc/skel/.local/

%changelog
* Thu Aug 20 2026 omedora <noreply@omedora> - 0.2.0~beta.2-1
- Rebase the runtime payload onto the official Omarchy 4.0.0 release.
- Scope Fedora updates to the Omedora-managed RPM set.

* Wed Aug 12 2026 omedora <noreply@omedora> - 0.2.0~beta.1-1
- Rebase onto the current Quattro beta branch and adapt its provisioning flow.
- Add the Omedora 3 to Omedora 4 package-backed upgrade path.

* Thu Jun 11 2026 omedora <noreply@omedora> - 0.2.0~alpha.0-1
- Initial Fedora analogue of upstream's omarchy Arch package, transliterated
  from docs/file-layout.md's build-time map: bin/ (+ bin/fedora dnf backends),
  install/, migrations/, themes/, shell/, version files, the
  /usr/share/omarchy/bin symlink farm, and skel user-migration markers.
- Skips the pacman libalpm update-guard hook (no pacman on Fedora).
- Requires omedora-settings; lean hard-runtime Requires only (the full desktop
  set comes from the omedora install transaction).
