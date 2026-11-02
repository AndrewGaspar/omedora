# hyprpad.spec — drive Hyprland from a Steam Controller or gamepad (omedora).
#
# From-source (cargo) build of AndrewGaspar/hyprpad at a pinned upstream
# commit, following the hypxr-pkgs Arch PKGBUILD (pkgbuilds/hyprpad)
# prepare/build/check/package sequence: /usr path rewrites done on copies (the
# test suite embeds the checkout-path units/helpers and asserts on those exact
# paths), both crates built + tested, and the full host-integration payload
# (broker socket+service, user unit, udev rule, sysusers group, shell plugins,
# docs) installed.
#
# HERMETIC / VENDORED build (COPR-ready), same shape as satty.spec, with one
# twist: hyprpad is TWO standalone crates — the root daemon (Cargo.lock) and
# osk/ (its own Cargo.lock, deliberately not a workspace member per its
# Cargo.toml). `cargo vendor` syncs its target dir to exactly one resolve set,
# so the two dep sets cannot share one vendor dir: Source1 carries the root
# crate's vendor/ and Source2 (...-osk-deps.tar.zst) the osk crate's
# osk-vendor/, both generated deterministically at SRPM-gen time
# (build-local.sh + .copr/srpm.sh, kept in sync) and both sealed offline
# (cargo_prep for root, a derived osk/.cargo/config.toml pointing at
# ../osk-vendor for the keyboard). Neither tarball is committed or pinned in
# hyprpad.spec.sources; cargo's per-crate checksums anchor both to the pinned
# Source0 locks.
#
# Lua 5.4 is vendored and built from source (mlua `vendored` feature through
# `cc`), so no system Lua is needed. libwayland-client is dlopen'ed by both
# binaries (never in the ELF NEEDED list), so it is an explicit Requires.
#
# Host integration (mirrors the Arch package): the `hyprpad` group (sysusers),
# the 72-hyprpad-puck udev rule, the privileged broker socket+service, and the
# per-user hyprpad.service. The package enables NOTHING — not the socket, not
# the user unit, not the shell plugins; see the shipped README.package.md for
# the one-time host setup (group membership, udev trigger, `systemctl enable`).

%global         commit b3f9dc704f0a08e52b81dde95c9298699925ad76
%global         shortcommit %(c=%{commit}; echo ${c:0:9})
# Upstream commit date of the pin (snapshot versioning, as the hypxr specs).
%global         snapshot 20261013

Name:           hyprpad
Version:        0.1.0^%{snapshot}.git%{shortcommit}
Release:        1%{?dist}
Summary:        Drive Hyprland from a Steam Controller or gamepad without giving up Steam Input

# VENDORED LICENSE: both binaries statically link their crate trees, so the
# tag aggregates the licenses of ALL bundled crates in BOTH Cargo.locks (the
# cargo_license_summary output for the root crate and for osk/), not just
# hyprpad's own (MIT OR Apache-2.0). CC0-1.0 is the Kenney input-prompts art
# bundled under shell/*/art. See LICENSE.dependencies(.osk) + the
# cargo-vendor manifests.
License:        (MIT OR Apache-2.0) AND MIT AND (Apache-2.0 WITH LLVM-exception OR Apache-2.0 OR MIT) AND (Unlicense OR MIT) AND (MIT OR Apache-2.0 OR Zlib) AND CC0-1.0
URL:            https://github.com/AndrewGaspar/hyprpad
# Commit-pinned GitHub archive (immutable for a given sha; same pattern as
# voxtype.spec's Source0). Bump %%commit, %%snapshot and the .sources pin
# together.
Source0:        %{url}/archive/%{commit}/%{name}-%{commit}.tar.gz
# Source1: `cargo vendor` tarball of the root crate's pinned Cargo.lock. NOT
# committed: generated deterministically into SOURCES/ at SRPM-gen time.
# Unpacks to vendor/.
Source1:        %{name}-%{version}-vendor.tar.zst
# Source2: `cargo vendor` tarball of the standalone osk/ crate's pinned
# Cargo.lock, generated the same way (see the *-osk-deps block in
# build-local.sh / .copr/srpm.sh). Unpacks to osk-vendor/.
Source2:        %{name}-%{version}-osk-deps.tar.zst
# Source3: Fedora host-setup notes (local sibling, shipped as %%doc).
Source3:        hyprpad.README.package.md

# Compiled for x86_64 (the only arch omedora targets right now).
ExclusiveArch:  x86_64

# --- Build toolchain -------------------------------------------------------
BuildRequires:  cargo
BuildRequires:  rust
# cargo-rpm-macros provides %%cargo_prep / %%cargo_build and the hermetic
# offline .cargo/config.toml seal. >= 24 has the -v vendor flag.
BuildRequires:  cargo-rpm-macros >= 24
# gcc builds the vendored Lua 5.4 (mlua `vendored` via `cc`) + links.
BuildRequires:  gcc
# pkg-config drives the -sys crates' library discovery.
BuildRequires:  pkgconf-pkg-config
# systemd-rpm-macros supplies %%{_unitdir} / %%{_userunitdir} / %%{_sysusersdir}
# and the %%systemd_* scriptlets. The hyprpad group needs no scriptlet: rpm
# (>= 4.19, so F44+) reads the shipped sysusers.d file, auto-Provides
# group(hyprpad) and creates the group at install.
BuildRequires:  systemd-rpm-macros
# systemd-udev ships udevadm, used in %%check to validate the udev rule.
BuildRequires:  systemd-udev

# --- Runtime ---------------------------------------------------------------
# libwayland-client is dlopen'ed at runtime by both binaries (see header), so
# RPM auto-detection never sees it: name Fedora's split package by hand.
Requires:       libwayland-client
# hyprpad-steam (the masked Steam launcher) wraps Steam in bubblewrap to hide
# the real controller; the daemon itself never needs it.
Recommends:     bubblewrap

%description
hyprpad drives Hyprland from a Steam Controller or gamepad without giving up
Steam Input: the daemon reads the real controller over hidraw, presents Steam
a virtual Valve controller over /dev/uhid, and maps pads, combos, and the
guide button to compositor actions through an embedded Lua config. A
privileged fd broker (socket-activated, reachable only to the `hyprpad` group)
hands out the controller descriptors, and a separate on-screen keyboard
binary (hyprpad-osk) covers text entry from the couch. This package also ships
the Omarchy shell plugins (cheat-sheet panel, bar widget) that
hyprpad-cheatsheet / hyprpad-statusbar install. See README.package.md for the
one-time host setup.

%prep
# Commit archive unpacks to hyprpad-<sha>/.
%autosetup -n %{name}-%{commit}
# Unpack the (build-time-generated) vendor tarballs (./vendor/ for the root
# crate, ./osk-vendor/ for the standalone osk crate).
%setup -q -T -D -a 1 -n %{name}-%{commit}
%setup -q -T -D -a 2 -n %{name}-%{commit}
# Seal the root crate offline, then seal osk against its own vendor dir with
# the same generated stanza, re-pointed one level up.
%cargo_prep -v vendor
mkdir -p osk/.cargo
sed 's#directory = "vendor"#directory = "../osk-vendor"#' .cargo/config.toml \
  > osk/.cargo/config.toml
# Rewrite the checkout-path units/helpers to /usr paths on COPIES under
# packaged/ (same as the Arch PKGBUILD): the test suite embeds the pristine
# tree files and asserts on exactly those paths, so the tree stays untouched.
mkdir -p packaged/systemd/user packaged/bin
sed 's|^ExecStart=.*/hyprpad broker$|ExecStart=/usr/bin/hyprpad broker|' \
  packaging/systemd/hyprpad-broker.service > packaged/systemd/hyprpad-broker.service
sed 's|%%h/\.local/bin/hyprpad|/usr/bin/hyprpad|g' \
  packaging/systemd/user/hyprpad.service > packaged/systemd/user/hyprpad.service
for script in hyprpad-cheatsheet hyprpad-statusbar; do
  sed 's|^DEFAULT_SRC=.*$|DEFAULT_SRC="/usr/share/hyprpad/shell/$PLUGIN_ID"|' \
    "scripts/$script" > "packaged/bin/$script"
done

%build
# cargo_build builds with Fedora's `rpm` profile, so binaries land in
# target/rpm/ (osk/target/rpm/ for the keyboard), not target/release/.
# Offline builds against the vendored sources (no crates.io): the daemon, then
# the standalone on-screen keyboard + its offline model builder, both with
# Fedora's Rust flags.
%cargo_build
pushd osk
%cargo_build
popd
# Record the bundled crates' licenses + manifests for the %%license payload,
# for both crate trees (the osk binaries bundle their own set).
%{cargo_license_summary}
%{cargo_license} > LICENSE.dependencies
%{cargo_vendor_manifest}
pushd osk
%{cargo_license_summary}
%{cargo_license} > LICENSE.dependencies
%{cargo_vendor_manifest}
popd

%install
install -D -m 755 target/rpm/hyprpad %{buildroot}%{_bindir}/hyprpad
install -D -m 755 osk/target/rpm/hyprpad-osk %{buildroot}%{_bindir}/hyprpad-osk
install -D -m 755 osk/target/rpm/hyprpad-osk-build-model \
  %{buildroot}%{_bindir}/hyprpad-osk-build-model
install -D -m 755 scripts/hyprpad-steam packaged/bin/hyprpad-cheatsheet \
  packaged/bin/hyprpad-statusbar -t %{buildroot}%{_bindir}/

# Host integration: sysusers group, udev rule, broker socket+service, user unit.
install -D -m 644 packaging/sysusers.d/hyprpad.conf \
  %{buildroot}%{_sysusersdir}/hyprpad.conf
install -D -m 644 packaging/udev/72-hyprpad-puck.rules \
  %{buildroot}%{_udevrulesdir}/72-hyprpad-puck.rules
install -D -m 644 packaging/systemd/hyprpad-broker.socket \
  packaged/systemd/hyprpad-broker.service -t %{buildroot}%{_unitdir}/
install -D -m 644 packaged/systemd/user/hyprpad.service \
  %{buildroot}%{_userunitdir}/hyprpad.service

# Omarchy shell plugins, copied into ~/.config/omarchy/plugins by
# `hyprpad-cheatsheet install` and `hyprpad-statusbar install`.
for plugin in hyprpad.cheatsheet hyprpad.status; do
  (cd "shell/$plugin" && find . -type f -exec \
    install -D -m 644 '{}' "%{buildroot}%{_datadir}/hyprpad/shell/$plugin/{}" \;)
done

# Documentation + license.
install -D -m 644 config/hyprpad.lua %{buildroot}%{_docdir}/%{name}/hyprpad.lua
install -D -m 644 config/hyprpad-rules.lua %{buildroot}%{_docdir}/%{name}/hyprpad-rules.lua
install -D -m 644 docs/12-lizard-free.md %{buildroot}%{_docdir}/%{name}/12-lizard-free.md
install -D -m 644 README.md %{buildroot}%{_docdir}/%{name}/README.md
install -D -m 644 osk/README.md %{buildroot}%{_docdir}/%{name}/README.osk.md
install -D -m 644 shell/README.md %{buildroot}%{_docdir}/%{name}/README.shell.md
install -D -m 644 %{SOURCE3} %{buildroot}%{_docdir}/%{name}/README.package.md
install -D -m 644 LICENSE-MIT LICENSE-APACHE -t %{buildroot}%{_licensedir}/%{name}/
install -D -m 644 shell/hyprpad.cheatsheet/art/kenney/LICENSE.txt \
  %{buildroot}%{_licensedir}/%{name}/LICENSE.kenney-input-prompts.txt
install -D -m 644 shell/hyprpad.cheatsheet/art/LICENSES.md \
  %{buildroot}%{_licensedir}/%{name}/LICENSES.cheatsheet-art.md
install -D -m 644 shell/hyprpad.status/art/LICENSES.md \
  %{buildroot}%{_licensedir}/%{name}/LICENSES.status-art.md
# The osk crate tree's license breakdown + vendor manifest. A file named
# cargo-vendor.txt anywhere under the license dir feeds rpm's
# bundled(crate(...)) Provides generator, so osk's crates are declared too.
install -D -m 644 osk/LICENSE.dependencies osk/cargo-vendor.txt \
  -t %{buildroot}%{_licensedir}/%{name}/osk/

%check
# Upstream's own suites, as the Arch PKGBUILD runs them, offline against the
# vendored trees. Two broker policy tests assume a NON-root build user: they
# exclude a uid other than their own via UidPolicy::Only and expect "not
# permitted", but the broker always admits uid 0, so as root they fall
# through to the device scan instead. COPR's mock builds as an unprivileged
# user and runs them; a root build (the local podman harness) skips just
# those two.
skip=()
if (( $(id -u) == 0 )); then
  skip=(--skip serve_refuses_a_peer_the_policy_excludes
        --skip request_at_reports_a_refusal_as_an_error)
fi
%cargo_test -- -- "${skip[@]}"
pushd osk
%cargo_test
popd
# Then prove the SHIPPED artifacts work.
# Helper scripts stay valid bash after the DEFAULT_SRC rewrite.
bash -n scripts/hyprpad-steam packaged/bin/hyprpad-cheatsheet packaged/bin/hyprpad-statusbar
# No subcommand prints usage on stderr and exits 2 by design.
{ target/rpm/hyprpad 2>&1 || true; } | grep -F 'usage: hyprpad'
osk/target/rpm/hyprpad-osk --help | grep -F 'hyprpad-osk'
# (A bare `! cmd` never trips set -e, so negative checks exit explicitly.)
for bin in target/rpm/hyprpad osk/target/rpm/hyprpad-osk; do
  if ldd "$bin" | grep -F 'not found'; then exit 1; fi
done
# The packaged (rewritten) units point at /usr/bin and nowhere else.
grep -Fxq 'ExecStart=/usr/bin/hyprpad broker' packaged/systemd/hyprpad-broker.service
grep -Fxq 'ExecStart=/usr/bin/hyprpad run' packaged/systemd/user/hyprpad.service
grep -Fxq 'ExecReload=/usr/bin/hyprpad reload' packaged/systemd/user/hyprpad.service
grep -Fxq 'Environment=HYPRPAD_OSK_BIN=/usr/bin/hyprpad-osk' packaged/systemd/user/hyprpad.service
grep -Fxq 'Documentation=file:///usr/share/doc/hyprpad/12-lizard-free.md' \
  packaged/systemd/user/hyprpad.service
if grep -E '^[^#]*\.local/bin' packaged/systemd/user/hyprpad.service; then exit 1; fi
grep -Fxq 'DEFAULT_SRC="/usr/share/hyprpad/shell/$PLUGIN_ID"' packaged/bin/hyprpad-cheatsheet
grep -Fxq 'DEFAULT_SRC="/usr/share/hyprpad/shell/$PLUGIN_ID"' packaged/bin/hyprpad-statusbar
# The udev rule parses (no install needed).
udevadm verify packaging/udev/72-hyprpad-puck.rules

%post
%systemd_post hyprpad-broker.service hyprpad-broker.socket
%systemd_user_post hyprpad.service

%preun
%systemd_preun hyprpad-broker.service hyprpad-broker.socket
%systemd_user_preun hyprpad.service

%postun
%systemd_postun_with_restart hyprpad-broker.service hyprpad-broker.socket
%systemd_user_postun_with_restart hyprpad.service

%files
%license %{_licensedir}/%{name}/LICENSE-MIT
%license %{_licensedir}/%{name}/LICENSE-APACHE
%license %{_licensedir}/%{name}/LICENSE.kenney-input-prompts.txt
%license %{_licensedir}/%{name}/LICENSES.cheatsheet-art.md
%license %{_licensedir}/%{name}/LICENSES.status-art.md
# Aggregated dependency license info from both vendored crate trees.
%license LICENSE.dependencies
%license cargo-vendor.txt
%license %{_licensedir}/%{name}/osk/LICENSE.dependencies
%license %{_licensedir}/%{name}/osk/cargo-vendor.txt
%doc %{_docdir}/%{name}/hyprpad.lua
%doc %{_docdir}/%{name}/hyprpad-rules.lua
%doc %{_docdir}/%{name}/12-lizard-free.md
%doc %{_docdir}/%{name}/README.md
%doc %{_docdir}/%{name}/README.osk.md
%doc %{_docdir}/%{name}/README.shell.md
%doc %{_docdir}/%{name}/README.package.md
%{_bindir}/hyprpad
%{_bindir}/hyprpad-osk
%{_bindir}/hyprpad-osk-build-model
%{_bindir}/hyprpad-steam
%{_bindir}/hyprpad-cheatsheet
%{_bindir}/hyprpad-statusbar
%{_sysusersdir}/hyprpad.conf
%{_udevrulesdir}/72-hyprpad-puck.rules
%{_unitdir}/hyprpad-broker.service
%{_unitdir}/hyprpad-broker.socket
%{_userunitdir}/hyprpad.service
%dir %{_datadir}/hyprpad
%{_datadir}/hyprpad/shell

%changelog
* Sun Nov 01 2026 omedora <noreply@omedora> - 0.1.0^20261013.gitb3f9dc704-1
- Initial from-source (cargo) build of hyprpad at upstream commit b3f9dc7:
  daemon + standalone on-screen keyboard, built fully offline against two
  cargo-vendor tarballs (root lock + osk lock), upstream test suites run in
  check. Ships the broker socket/service, user unit, udev rule, sysusers
  group, Omarchy shell plugins, and helper scripts with /usr rewrites.
