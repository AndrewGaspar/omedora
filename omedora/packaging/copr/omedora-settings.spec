# omedora-settings.spec — Fedora analogue of upstream's `omarchy-settings` Arch
# package (whose PKGBUILD lives in DHH's private omarchy-pkgs repo). The
# authoritative payload recipe is docs/file-layout.md's "Build-time map
# (repo -> installed paths)"; this spec transliterates it with the Fedora
# coexistence deviations documented inline below.
#
# Split (mirrors upstream): omedora-settings ships everything that must be on
# the target BEFORE the omedora runtime package installs — /etc/skel/**,
# /etc drop-ins we own outright, package-owned files under /usr/share and
# /usr/lib, fonts, branding, and the three debug binaries needed by a live
# ISO env (omarchy-debug, omarchy-debug-idle, omarchy-upload-log). The
# `omedora` package (runtime bin/ + install/ + migrations/ + themes/ + shell/)
# Requires this one.
#
# Internal install paths deliberately stay /usr/share/omarchy (NOT renamed to
# omedora): every bin/ script and the upstream rebase flow key off
# OMARCHY_PATH=/usr/share/omarchy.
#
# FEDORA COEXISTENCE DEVIATIONS from docs/file-layout.md (the hard constraints;
# see also the per-section comments in %install):
#   - default/libalpm/ (pacman hook), etc/mkinitcpio.conf.d/,
#     etc/limine-entry-tool.d/, default/limine/, default/snapper/: SKIPPED —
#     no pacman/mkinitcpio/limine/snapper on the Fedora path (Fedora keeps its
#     own bootloader + initrd story).
#   - default/plymouth/ (+ etc/plymouth/plymouthd.conf): SKIPPED — Fedora keeps
#     its stock BGRT plymouth theme.
#   - sddm: NOTHING installed under /usr/share/sddm or /etc/sddm.conf.d —
#     Fedora stays on GDM. The theme sources still ship under
#     /usr/share/omarchy/default/sddm/ as inert reference copies.
#   - Upstream's etc-overrides "post_install cp -f" model is REJECTED on
#     Fedora: /etc/os-release, /etc/nsswitch.conf, /etc/skel/.bashrc,
#     /etc/security/faillock.conf, /etc/cups/*, /etc/pam.d/* are never packaged
#     and never scriptlet-touched. Those files ship ONLY as reference copies
#     under /usr/share/omarchy/etc-overrides/ (no scriptlet copies them).
#   - default/applications/mimeapps.list is NOT installed to
#     /usr/share/applications/mimeapps.list: on Fedora that file is OWNED by
#     shared-mime-info (verified with dnf repoquery --file on fc44), so
#     packaging it is a hard file conflict. It stays a reference copy at
#     /usr/share/omarchy/default/applications/mimeapps.list.
#   - The wayland session installs as our own identity:
#     /usr/share/wayland-sessions/omedora.desktop (Exec via uwsm; see below),
#     superseding the stand-alone hyprland-omedora package.

Name:           omedora-settings
# Version is normally read from the repo's omedora/version file; hardcoded here
# for now — a follow-up wires .copr/srpm.sh to substitute it at SRPM-gen time.
Version:        0.2.0~beta.2
Release:        1%{?dist}
Summary:        Omedora pre-install settings: /etc/skel seeds, system defaults, fonts, branding

# Same license as the omarchy repo it is built from.
License:        MIT
URL:            https://github.com/omedora/omedora
# SELF-SOURCE marker: this package's source is THIS repo itself. The bare
# filename `omedora-self.tar.gz` tells .copr/srpm.sh and build-local.sh to
# produce the tarball via `git archive --prefix=omedora-%%{version}/ HEAD`
# from the repo checkout instead of spectool-fetching a URL. No sha256 pin
# applies (the tarball is generated from the local tree, not fetched).
Source0:        omedora-self.tar.gz

BuildArch:      noarch
BuildRequires:  desktop-file-utils
BuildRequires:  systemd-rpm-macros

# Fedora stand-in for upstream's `omarchy-settings` Arch package.
Provides:       omarchy-settings = %{version}-%{release}

# Supersedes the stand-alone session-entry package hyprland-omedora (which
# shipped only /usr/share/wayland-sessions/omedora.desktop — now part of this
# payload). NOTE: the obsoleted version is hardcoded at the last published
# hyprland-omedora (1.0.0), NOT `< %%{version}`: our 0.2.0~beta.2 sorts BELOW
# 1.0.0, so a %%{version}-based Obsoletes would never fire against an installed
# hyprland-omedora-1.0.0.
Provides:       hyprland-omedora = %{version}-%{release}
Obsoletes:      hyprland-omedora < 1.0.1

# The payload is config/data + a handful of bash scripts; the heavyweight
# runtime dependencies belong to the `omedora` package and the install
# transaction. RPM's automatic dependency generator still adds the script
# interpreters for the /usr/bin debug trio (bash), which is all this package
# genuinely needs at runtime. Auto-requires are suppressed for the
# /usr/share/omarchy and /etc/skel payload (reference copies and $HOME seeds —
# their interpreters/tools arrive with the desktop install, and treating every
# shebang in the seeded tree as a hard RPM dependency would be wrong).
%global __requires_exclude_from ^(%{_datadir}/omarchy/|/etc/skel/)
# Ship scripts byte-for-byte as committed (no shebang rewriting).
%global __brp_mangle_shebangs %{nil}

%description
Everything Omedora needs on the target before (or independently of) the
omedora runtime package: /etc/skel seeds for new users (~/.config defaults,
application launchers, branding), the resync/reference trees under
/usr/share/omarchy (config/, default/, applications/, etc-overrides/),
package-owned system files (systemd user units, environment.d, uwsm env.d,
fontconfig, fonts, icons), the /etc drop-ins Omedora owns outright, the
Omedora wayland-session entry, and the live-ISO debug binaries. Fedora port
of upstream omarchy-settings; never overwrites files owned by other Fedora
packages (see /usr/share/omarchy/etc-overrides/).

%prep
# Source0 is the whole repo (git archive, prefix omedora-%%{version}).
%setup -q -n omedora-%{version}

%build
# Nothing to build (noarch config/data package).

%install
# ---------------------------------------------------------------------------
# /usr/share/omarchy resync sources / reference trees
# ---------------------------------------------------------------------------
install -d %{buildroot}%{_datadir}/omarchy

# config/** -> /usr/share/omarchy/config/** (resync source for
# omarchy-reinstall-configs; the same tree also seeds /etc/skel below).
cp -a config %{buildroot}%{_datadir}/omarchy/config

# applications/ (launchers + their icon sources) -> /usr/share/omarchy/
# (omarchy-refresh-applications and several bins copy from $OMARCHY_PATH here).
cp -a applications %{buildroot}%{_datadir}/omarchy/applications

# default/** -> /usr/share/omarchy/default/ — minus the Arch-only trees
# (libalpm pacman hook, limine, snapper) and plymouth (Fedora keeps BGRT).
# default/sddm/ and default/wayland-sessions/ stay as inert reference copies
# inside our own prefix (nothing is installed under /usr/share/sddm).
cp -a default %{buildroot}%{_datadir}/omarchy/default
rm -rf %{buildroot}%{_datadir}/omarchy/default/libalpm \
       %{buildroot}%{_datadir}/omarchy/default/limine \
       %{buildroot}%{_datadir}/omarchy/default/snapper \
       %{buildroot}%{_datadir}/omarchy/default/plymouth

# Branding sources (omarchy-branding-* reset from $OMARCHY_PATH/{icon,logo}.txt).
# logo.txt is the wide WORDMARK shown by omarchy-show-logo, the screensaver, and
# `omarchy branding screensaver reset` — a user-facing surface omedora rebrands
# (see omedora/branding.md). Ship Omedora's wordmark for it; logo.svg/icon.* stay
# upstream (no omedora variants; the About icon stays Omarchy, matching 3.8.2).
install -pm644 logo.svg icon.txt icon.png %{buildroot}%{_datadir}/omarchy/
install -pm644 omedora/branding/logo.txt %{buildroot}%{_datadir}/omarchy/logo.txt

# etc-overrides/: REFERENCE COPIES ONLY on Fedora. Upstream Arch copies these
# over package-owned /etc files from post_install (cp -f); on Fedora those
# files (/etc/nsswitch.conf, /etc/skel/.bashrc, /etc/security/faillock.conf,
# /etc/cups/*, /etc/plymouth/plymouthd.conf) are owned by bash/glibc/pam/cups/
# plymouth and are deliberately NEVER packaged or scriptlet-touched. A separate
# opt-in adoption command may consult these copies; this package does not.
install -Dpm644 default/bashrc \
  %{buildroot}%{_datadir}/omarchy/etc-overrides/dot.bashrc
install -Dpm644 etc/nsswitch.conf \
  %{buildroot}%{_datadir}/omarchy/etc-overrides/nsswitch.conf
install -Dpm644 etc/security/faillock.conf \
  %{buildroot}%{_datadir}/omarchy/etc-overrides/security/faillock.conf
install -Dpm644 etc/cups/cups-browsed.conf \
  %{buildroot}%{_datadir}/omarchy/etc-overrides/cups/cups-browsed.conf
install -Dpm644 etc/plymouth/plymouthd.conf \
  %{buildroot}%{_datadir}/omarchy/etc-overrides/plymouth/plymouthd.conf

# ---------------------------------------------------------------------------
# /etc/skel — seeds NEW users (useradd -m), exactly like upstream. Existing
# users are adopted by a separate explicit command, never by this package.
# ---------------------------------------------------------------------------
install -d %{buildroot}/etc/skel/.config
cp -a config/. %{buildroot}/etc/skel/.config/
# Branding seeds (about <- icon.txt [upstream], screensaver <- the Omedora
# wordmark; matches what omarchy-branding-{about,screensaver} reset to now that
# /usr/share/omarchy/logo.txt is Omedora's). This is the v4 home of the 3.8.2
# install/config/branding.sh screensaver rebrand.
install -Dpm644 icon.txt %{buildroot}/etc/skel/.config/omarchy/branding/about.txt
install -Dpm644 omedora/branding/logo.txt %{buildroot}/etc/skel/.config/omarchy/branding/screensaver.txt
# Web-app/utility launchers.
install -d %{buildroot}/etc/skel/.local/share/applications
cp -a applications/*.desktop %{buildroot}/etc/skel/.local/share/applications/
# Nautilus python extensions (static per-user files outside ~/.config).
install -d %{buildroot}/etc/skel/.local/share/nautilus-python/extensions
cp -a default/nautilus-python/extensions/*.py \
  %{buildroot}/etc/skel/.local/share/nautilus-python/extensions/
# Hypr toggle flags state seed.
install -Dpm644 default/hypr/toggles/flags.lua \
  %{buildroot}/etc/skel/.local/state/omarchy/toggles/hypr/flags.lua
# NOTE: /etc/skel/.bashrc is NOT shipped (owned by Fedora's bash package);
# the shipped bashrc lives at /usr/share/omarchy/etc-overrides/dot.bashrc.

# ---------------------------------------------------------------------------
# Package-owned system files (per the file-layout.md map). All target paths
# verified unowned (or standard drop-in dirs) on Fedora 44 unless noted.
# ---------------------------------------------------------------------------
# systemd user units.
install -d %{buildroot}%{_userunitdir}
install -pm644 default/systemd/user/*.service \
  %{buildroot}%{_userunitdir}/
# Keep existing absolute wants links valid until the per-user migration
# replaces the retired notifier name. The directory watcher itself is gone.
ln -s omarchy-migrate-notify.service \
  %{buildroot}%{_userunitdir}/omarchy-update-user-notify.service
# system-sleep hook: ONLY unmount-fuse is package-installed (per the map);
# force-igpu / keyboard-backlight are hardware-quirk files deployed by the
# omarchy-hw-* scripts on matching machines, not packaged globally.
install -Dpm755 default/systemd/system-sleep/unmount-fuse \
  %{buildroot}%{_prefix}/lib/systemd/system-sleep/unmount-fuse
# environment.d (systemd user-session environment generator drop-in dir).
install -Dpm644 default/environment.d/10-omarchy-fcitx.conf \
  %{buildroot}%{_prefix}/lib/environment.d/10-omarchy-fcitx.conf
# uwsm env.d (sourced by `uwsm start`; uwsm is vendored in this repo's COPR
# set, /usr/share/uwsm/env.d is ours to own jointly with it).
install -Dpm644 default/uwsm/env.d/10-omarchy \
  %{buildroot}%{_datadir}/uwsm/env.d/10-omarchy
# fontconfig: conf.avail + the standard activation symlink in /etc/fonts/conf.d
# (both dirs owned by Fedora's fontconfig; we list only our two entries).
install -Dpm644 default/fontconfig/conf.avail/50-omarchy.conf \
  %{buildroot}%{_datadir}/fontconfig/conf.avail/50-omarchy.conf
install -d %{buildroot}%{_sysconfdir}/fonts/conf.d
ln -s %{_datadir}/fontconfig/conf.avail/50-omarchy.conf \
  %{buildroot}%{_sysconfdir}/fonts/conf.d/50-omarchy.conf
# xdg-terminal-exec terminal preference list (dir owned by Fedora's
# xdg-terminal-exec package; we list only our file).
install -Dpm644 default/xdg-terminal-exec/hyprland-xdg-terminals.list \
  %{buildroot}%{_datadir}/xdg-terminal-exec/hyprland-xdg-terminals.list
# Omarchy icon font.
install -Dpm644 default/fonts/omarchy/omarchy.ttf \
  %{buildroot}%{_datadir}/fonts/omarchy/omarchy.ttf

# Wayland session entry — OUR session identity: omedora.desktop, launched via
# uwsm (which sources ~/.config/uwsm/env; without it omarchy-* commands fail
# in-session). The file is the in-repo source of truth previously shipped by
# the hyprland-omedora package (Exec drives Hyprland through uwsm with
# `-- start-hyprland`, no resolver .desktop needed); this supersedes both that
# package and upstream's default/wayland-sessions/omarchy.desktop (which stays
# under /usr/share/omarchy/default/ as a reference copy). Installed to the
# standard /usr/share/wayland-sessions (upstream's /usr/local path is not
# package territory on Fedora).
install -Dpm644 omedora/packaging/copr/omedora.desktop \
  %{buildroot}%{_datadir}/wayland-sessions/omedora.desktop

# Application icons -> hicolor. The repo stores them under their display names
# ("Disk Usage.png", "Battle.net.png"); the shipped .desktop files reference
# slugified icon names (disk-usage, battle-net), so slugify on install:
# lowercase, spaces and inner dots -> dashes. Installed at 512x512 (the
# dominant source size; the map's {48,256,scalable} buckets don't match the
# actual all-PNG ~512px sources in-tree).
install -d %{buildroot}%{_datadir}/icons/hicolor/512x512/apps
for f in applications/icons/*.png; do
  base=$(basename "$f" .png)
  slug=$(echo "$base" | tr "[:upper:]" "[:lower:]" | tr " ." "--")
  install -pm644 "$f" "%{buildroot}%{_datadir}/icons/hicolor/512x512/apps/${slug}.png"
done
# Omarchy/Omedora brand icon (pixmaps + hicolor, per the map).
install -Dpm644 icon.png %{buildroot}%{_datadir}/pixmaps/omarchy.png
install -Dpm644 icon.png %{buildroot}%{_datadir}/icons/hicolor/256x256/apps/omarchy.png

# ---------------------------------------------------------------------------
# /etc drop-ins we own outright (etc/** per the map, MINUS the Arch-only and
# never-touch entries — see the header). All are unowned drop-in paths on
# Fedora; all marked %%config(noreplace) so user edits survive upgrades.
# ---------------------------------------------------------------------------
install -Dpm644 etc/fastfetch/config.jsonc %{buildroot}%{_sysconfdir}/fastfetch/config.jsonc
# Env bootstrap for system login shells (sources OMARCHY_PATH/PATH setup).
install -Dpm644 etc/profile.d/omarchy.sh %{buildroot}%{_sysconfdir}/profile.d/omarchy.sh
# sudoers drop-ins (0440 per sudoers convention; /etc/sudoers.d owned by sudo).
install -d %{buildroot}%{_sysconfdir}/sudoers.d
install -pm440 etc/sudoers.d/omarchy-* %{buildroot}%{_sysconfdir}/sudoers.d/
# sysctl / modprobe drop-ins. Quattro beta retired the old udev rules.
install -d %{buildroot}%{_sysconfdir}/sysctl.d
install -pm644 etc/sysctl.d/*.conf %{buildroot}%{_sysconfdir}/sysctl.d/
install -Dpm644 etc/modprobe.d/omarchy-usb-autosuspend.conf \
  %{buildroot}%{_sysconfdir}/modprobe.d/omarchy-usb-autosuspend.conf
# Keep the already-reviewed systemd manager/logind/resolved drop-ins. New beta
# oomd and inhibit-delay policy is machine-wide behavior and remains reference
# material until Omedora explicitly adopts that system policy.
for f in \
  logind.conf.d/10-ignore-power-button.conf \
  resolved.conf.d/10-disable-multicast.conf \
  resolved.conf.d/20-docker-dns.conf \
  system.conf.d/10-faster-shutdown.conf \
  system.conf.d/20-omarchy-nofile.conf \
  user.conf.d/20-omarchy-nofile.conf; do
  install -Dpm644 "etc/systemd/$f" \
    "%{buildroot}%{_sysconfdir}/systemd/$f"
done
# docker daemon defaults + system gnupg dirmngr keyservers: NOT installed to
# /etc. Both paths are unowned on Fedora 44 but are generic, user-editable
# locations (a pre-existing /etc/docker/daemon.json — registry mirrors, cgroup
# options — would be shunted to .rpmorig and silently replaced, breaking the
# user's setup). Coexistence contract: ship as reference copies; the install's
# docker setup applies daemon.json only-if-absent (disclosed at the plan gate).
install -Dpm644 etc/docker/daemon.json %{buildroot}%{_datadir}/omarchy/etc-overrides/docker/daemon.json
install -Dpm644 etc/gnupg/dirmngr.conf %{buildroot}%{_datadir}/omarchy/etc-overrides/gnupg/dirmngr.conf
# New beta machine-wide policy stays visible as inert reference material. It
# is not installed to /etc on Fedora without a separate coexistence review.
install -Dpm644 etc/NetworkManager/conf.d/omarchy-wifi-powersave.conf \
  %{buildroot}%{_datadir}/omarchy/etc-overrides/NetworkManager/conf.d/omarchy-wifi-powersave.conf
install -Dpm644 etc/tmpfiles.d/omarchy-zswap.conf \
  %{buildroot}%{_datadir}/omarchy/etc-overrides/tmpfiles.d/omarchy-zswap.conf
install -Dpm644 etc/systemd/logind.conf.d/20-inhibit-delay.conf \
  %{buildroot}%{_datadir}/omarchy/etc-overrides/systemd/logind.conf.d/20-inhibit-delay.conf
install -Dpm644 etc/systemd/oomd.conf.d/10-omarchy.conf \
  %{buildroot}%{_datadir}/omarchy/etc-overrides/systemd/oomd.conf.d/10-omarchy.conf
# DELIBERATELY NOT INSTALLED from etc/: mkinitcpio.conf.d/, limine-entry-tool.d/,
# sddm.conf.d/ (Arch / sddm-only), nsswitch.conf, security/faillock.conf,
# cups/, plymouth/ (never-touch; reference copies in etc-overrides/ above),
# docker/daemon.json + gnupg/dirmngr.conf (reference copies, see above).

# ---------------------------------------------------------------------------
# Live-ISO debug trio (per the map: needed before the omedora package lands)
# + their entries in the /usr/share/omarchy/bin symlink farm.
# ---------------------------------------------------------------------------
install -d %{buildroot}%{_bindir} %{buildroot}%{_datadir}/omarchy/bin
for b in omarchy-debug omarchy-debug-idle omarchy-upload-log; do
  install -pm755 "bin/$b" "%{buildroot}%{_bindir}/$b"
  ln -s "%{_bindir}/$b" "%{buildroot}%{_datadir}/omarchy/bin/$b"
done

%check
desktop-file-validate %{buildroot}%{_datadir}/wayland-sessions/omedora.desktop

# No scriptlets: on Fedora the icon cache, desktop database, and fontconfig
# cache are refreshed by FILE TRIGGERS shipped in gtk-update-icon-cache /
# desktop-file-utils / fontconfig — nothing to declare here. Upstream's
# post_install etc-overrides copying is intentionally NOT replicated (see the
# header: coexistence model).

%files
%license LICENSE
# Live-ISO debug trio.
%{_bindir}/omarchy-debug
%{_bindir}/omarchy-debug-idle
%{_bindir}/omarchy-upload-log
# /usr/share/omarchy trees (dir itself co-owned with the omedora package).
%dir %{_datadir}/omarchy
%dir %{_datadir}/omarchy/bin
%{_datadir}/omarchy/bin/omarchy-debug
%{_datadir}/omarchy/bin/omarchy-debug-idle
%{_datadir}/omarchy/bin/omarchy-upload-log
%{_datadir}/omarchy/config/
%{_datadir}/omarchy/default/
%{_datadir}/omarchy/applications/
%{_datadir}/omarchy/etc-overrides/
%{_datadir}/omarchy/logo.txt
%{_datadir}/omarchy/logo.svg
%{_datadir}/omarchy/icon.txt
%{_datadir}/omarchy/icon.png
# /etc/skel seeds (recursive; /etc/skel itself is owned by Fedora's setup).
/etc/skel/.config/
/etc/skel/.local/
# systemd user units + sleep hook.
%{_userunitdir}/bt-agent.service
%{_userunitdir}/omarchy-fcitx5.service
%{_userunitdir}/omarchy-migrate-notify.service
%{_userunitdir}/omarchy-recover-internal-monitor.service
%{_userunitdir}/omarchy-sleep-lock.service
%{_userunitdir}/omarchy-speaker-tuning.service
%{_userunitdir}/omarchy-tailscale-receive.service
%{_userunitdir}/omarchy-update-user-notify.service
%{_prefix}/lib/systemd/system-sleep/unmount-fuse
%{_prefix}/lib/environment.d/10-omarchy-fcitx.conf
# uwsm env.d (dirs co-owned with the vendored uwsm package).
%dir %{_datadir}/uwsm
%dir %{_datadir}/uwsm/env.d
%{_datadir}/uwsm/env.d/10-omarchy
%{_datadir}/fontconfig/conf.avail/50-omarchy.conf
%{_sysconfdir}/fonts/conf.d/50-omarchy.conf
%{_datadir}/xdg-terminal-exec/hyprland-xdg-terminals.list
%dir %{_datadir}/fonts/omarchy
%{_datadir}/fonts/omarchy/omarchy.ttf
%{_datadir}/wayland-sessions/omedora.desktop
%{_datadir}/icons/hicolor/512x512/apps/*.png
%{_datadir}/icons/hicolor/256x256/apps/omarchy.png
%{_datadir}/pixmaps/omarchy.png
# /etc drop-ins.
%dir %{_sysconfdir}/fastfetch
%config(noreplace) %{_sysconfdir}/fastfetch/config.jsonc
%{_sysconfdir}/profile.d/omarchy.sh
%config(noreplace) %{_sysconfdir}/sudoers.d/omarchy-asdcontrol
%config(noreplace) %{_sysconfdir}/sudoers.d/omarchy-passwd-tries
%config(noreplace) %{_sysconfdir}/sudoers.d/omarchy-tzupdate
%config(noreplace) %{_sysconfdir}/sysctl.d/90-omarchy-file-watchers.conf
%config(noreplace) %{_sysconfdir}/sysctl.d/99-omarchy-sysctl.conf
%config(noreplace) %{_sysconfdir}/modprobe.d/omarchy-usb-autosuspend.conf
%dir %{_sysconfdir}/systemd/logind.conf.d
%config(noreplace) %{_sysconfdir}/systemd/logind.conf.d/10-ignore-power-button.conf
%dir %{_sysconfdir}/systemd/resolved.conf.d
%config(noreplace) %{_sysconfdir}/systemd/resolved.conf.d/10-disable-multicast.conf
%config(noreplace) %{_sysconfdir}/systemd/resolved.conf.d/20-docker-dns.conf
%dir %{_sysconfdir}/systemd/system.conf.d
%config(noreplace) %{_sysconfdir}/systemd/system.conf.d/10-faster-shutdown.conf
%config(noreplace) %{_sysconfdir}/systemd/system.conf.d/20-omarchy-nofile.conf
%dir %{_sysconfdir}/systemd/user.conf.d
%config(noreplace) %{_sysconfdir}/systemd/user.conf.d/20-omarchy-nofile.conf

%changelog
* Thu Aug 20 2026 omedora <noreply@omedora> - 0.2.0~beta.2-1
- Refresh the packaged defaults for the official Omarchy 4.0.0 release.

* Wed Aug 12 2026 omedora <noreply@omedora> - 0.2.0~beta.1-1
- Refresh the package-backed defaults for the current Quattro beta branch.
- Continue providing the stable Omedora session beside optional Omedora XR.
- Package the beta login-only migration notifier and current user services;
  retain the old notifier service name only as a compatibility symlink.
- Retire removed udev and systemd unit drop-ins; keep new beta NetworkManager,
  zswap, oomd, and inhibit policy as inert references pending Fedora review.

* Thu Jun 11 2026 omedora <noreply@omedora> - 0.2.0~alpha.0-1
- Initial Fedora analogue of upstream's omarchy-settings Arch package,
  transliterated from docs/file-layout.md's build-time map.
- Coexistence model: never packages or touches Fedora-owned /etc files
  (os-release, nsswitch.conf, skel/.bashrc, faillock.conf, cups, pam.d);
  those ship as reference copies under /usr/share/omarchy/etc-overrides/
  with no scriptlets. No plymouth/sddm/limine/snapper/mkinitcpio payload.
- Ships the omedora wayland-session entry, superseding hyprland-omedora
  (Obsoletes/Provides).
