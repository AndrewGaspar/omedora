#!/bin/bash
#
# P6 upgrade-to-4 verification — runs INSIDE the fedora:44 test image.
#
# Proves bin/omedora-upgrade-to-4 against a REAL 3.8.2-line install, including
# an Omedora XR stack installed from the live omedora-3 COPR:
#   1. build the FROM state: the live agaspar/omedora-3 COPR + the 3.8.2-era
#      RPM set (hyprland-omedora, walker/elephant, swayosd, hypridle/hyprlock/
#      hyprshot, gazelle-tui, the retired Python terminal-effects runtime,
#      HypXRland + its mandatory runtimes, the optional
#      monado-xreal runtime, and the Fedora-proper waybar/mako/swaybg), and the
#      omedora v0.1.3 git checkout at ~/.local/share/omarchy with its config
#      seeding replayed (omedora-seed-config — what the 3.8.2 installer ran)
#   2. plant user customizations plus representative XR configuration, pairing
#      state, runtime selection, and machine-specific user-service drop-ins
#   3. run bin/omedora-upgrade-to-4 (OMEDORA_PLAN_AUTOCONFIRM=1)
#   4. assert: omedora+omedora-settings installed; retired RPMs GONE; the
#      stable Hyprland stack and both Omedora sessions coexist; every mandatory
#      XR package and the opt-in Monado runtime migrated to omedora-4; the
#      private XR compositor/hyprctl and classic-config compatibility payload
#      landed; XR state is byte-identical except for the intentional Quattro
#      theme-path rewrite; all XR config sources resolve; checkout ->
#      .pre-omedora-4 backup + symlink to /usr/share/omarchy; the hash-match
#      matrix holds; quickshell hot-start skips gracefully (no session here);
#      re-run is idempotent; `omarchy --help` and the L1 suites stay green
#
# Run (host is Arch; podman, NOT docker; TMPDIR=/var/tmp/podman-tmp):
#   podman run --rm -v "$PWD:/repo" \
#     -v /var/tmp/omedora-dnf-cache:/var/cache/libdnf5 \
#     omedora-test:fedora44 bash /repo/omedora/test/fedora/upgrade-to-4-verify.sh

set -e

REPO="${REPO:-/repo}"
USER_NAME=omedora
USER_HOME=/home/$USER_NAME
from_repo_args=()
if [[ -n ${OMEDORA_UPGRADE_LOCAL_REPO:-} ]]; then
  from_repo_args+=("--disablerepo=$OMEDORA_UPGRADE_LOCAL_REPO")
fi
xr_v4_packages=(
  hypxrpaper hypxrva hypxrhud hypxrcompose
  hypxrvoice hypxrvoice-model-base-en
  wivrn-hypxr hypxrland-legacy-config
  hypxrland hypxrland-stack hypxrland-omedora
)
xr_o3_packages=(
  hypxrpaper hypxrva hypxrhud
  hypxrvoice hypxrvoice-model-base-en
  wivrn-hypxr hypxrland hypxrland-stack hypxrland-omedora
)

n=0; failed=0
ok()  { n=$((n+1)); echo "ok $n - $1"; }
nok() { n=$((n+1)); failed=$((failed+1)); echo "not ok $n - $1"; [[ -n ${2:-} ]] && printf '%s\n' "$2" | sed 's/^/    /'; }
check() { # check <desc> <cmd...>
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else nok "$desc" "cmd: $*"; fi
}
bail() { echo "Bail out! $*"; exit 1; }

as_user() { su "$USER_NAME" -c "$1"; }

# ---------------------------------------------------------------------------
echo "# --- FROM state: a 3.8.2-line omedora v0.1.3 install ---"
# ---------------------------------------------------------------------------

timeout 300 dnf -y copr enable agaspar/omedora-3 >/tmp/from-repos.log 2>&1 \
  || bail "could not enable the omedora-3 COPR ($(tail -2 /tmp/from-repos.log))"

# Seed Fedora's older Quickshell explicitly. The upgrade must replace an
# already-installed distro build, not merely install Omedora's snapshot when
# the name is absent. Keep both the old COPR and any injected O4 local repo out
# of this one transaction so the FROM provenance is unambiguous.
timeout 300 dnf install -y --setopt=install_weak_deps=False \
  "${from_repo_args[@]}" \
  --disablerepo='copr:copr.fedorainfracloud.org:agaspar:omedora-3' \
  quickshell >/tmp/from-quickshell.log 2>&1 \
  || bail "could not install Fedora's pre-Quattro Quickshell ($(tail -3 /tmp/from-quickshell.log))"

# The 3.8.2-era package set this scenario asserts retirement or migration on.
# hyprland-omedora pulls hyprland-no-session + uwsm + the vendored stable
# stack. hypxrland-omedora pulls the mandatory XR stack; monado-xreal remains
# an explicit, hardware-specific opt-in. The remaining packages are the
# Fedora-proper extras from a real v0.1.x install.
timeout 1800 dnf install -y --setopt=install_weak_deps=False \
  "${from_repo_args[@]}" \
  hyprland-omedora walker elephant swayosd hypridle hyprlock hyprshot \
  gazelle-tui waybar mako swaybg python3-terminaltexteffects \
  hypxrland-omedora monado-xreal \
  >/tmp/from-pkgs.log 2>&1 \
  || bail "could not install the 3.8.2-era package set ($(tail -3 /tmp/from-pkgs.log))"
echo "from-state packages installed"

as_user '
  set -e
  mkdir -p ~/.local/share
  git clone -q --depth 1 --branch v0.1.3 https://github.com/AndrewGaspar/omedora.git \
    ~/.local/share/omarchy
  # Replay the 3.8.2 config seeding (install/config/config-fedora.sh ran
  # omedora-seed-config over the whole config payload, protecting git/config).
  OMEDORA_SEED_SKIP="git/config" \
    ~/.local/share/omarchy/bin/omedora-seed-config \
    --source ~/.local/share/omarchy/config --dest ~/.config >/dev/null
  # The 3.8.2 sentinel-guarded ~/.bashrc block.
  cat >>~/.bashrc <<"EOF"

# >>> omedora >>>
# Managed by omedora. Sources the omarchy default bash configuration
if [[ $- == *i* && -r ~/.local/share/omarchy/default/bash/rc ]]; then
  source ~/.local/share/omarchy/default/bash/rc
fi
# <<< omedora <<<
EOF
  # User customizations the upgrade must preserve.
  printf "\n# my custom binds\nbind = SUPER, Z, exec, true\n" >> ~/.config/hypr/bindings.conf
  printf "export MY_CUSTOM_VAR=keep-me\n" >> ~/.config/uwsm/env
  printf "my-custom-terminal.desktop\n" > ~/.config/xdg-terminals.list

  # A standalone classic-hyprlang XR entry point. Quattro intentionally
  # rewrites only the legacy theme-state source; the package-provided classic
  # defaults remain reachable through the ~/.local/share/omarchy symlink.
  cat > ~/.config/hypr/hyprland-xr.conf <<"EOF"
source = ~/.local/share/omarchy/default/hypr/envs.conf
source = ~/.local/share/omarchy/default/hypr/autostart.conf
source = ~/.config/omarchy/current/theme/hyprland.conf
source = ~/.config/hypr/bindings.conf
openxr {
  enabled = true
}
EOF

  # Representative XR user and machine state. RPM transitions must not edit
  # pairing keys, runtime selection, voice/HUD setup, or service overrides.
  mkdir -p \
    ~/.config/hypxr ~/.config/hypxrvoice ~/.config/hypxrhud \
    ~/.config/wivrn ~/.config/openxr/1 \
    ~/.config/systemd/user/wivrn.service.d \
    ~/.config/systemd/user/monado-xreal.service.d \
    ~/.xr-pre-omedora-4
  printf "GPU_DEVICE=/dev/dri/renderD128\n" > ~/.config/hypxr/setup.env
  printf "[intent]\nbackend = \"rules\"\n" > ~/.config/hypxrvoice/config.toml
  printf "anchor = \"desk\"\n" > ~/.config/hypxrhud/hypxrhud.toml
  printf "{\"encoder\":\"vaapi\"}\n" > ~/.config/wivrn/config.json
  printf "{\"headset\":\"paired-key\"}\n" > ~/.config/wivrn/known_keys.json
  printf "{\"runtime\":\"wivrn\"}\n" > ~/.config/openxr/1/active_runtime.json
  printf "[Service]\nEnvironment=LIBVA_DRIVER_NAME=radeonsi\n" \
    > ~/.config/systemd/user/wivrn.service.d/override.conf
  printf "[Service]\nEnvironment=VK_ICD_FILENAMES=/machine/icd.json\n" \
    > ~/.config/systemd/user/monado-xreal.service.d/override.conf

  for rel in \
    .config/hypr/hyprland-xr.conf \
    .config/hypxr/setup.env \
    .config/hypxrvoice/config.toml \
    .config/hypxrhud/hypxrhud.toml \
    .config/wivrn/config.json \
    .config/wivrn/known_keys.json \
    .config/openxr/1/active_runtime.json \
    .config/systemd/user/wivrn.service.d/override.conf \
    .config/systemd/user/monado-xreal.service.d/override.conf; do
    mkdir -p "$HOME/.xr-pre-omedora-4/$(dirname "$rel")"
    cp "$HOME/$rel" "$HOME/.xr-pre-omedora-4/$rel"
  done
' || bail "could not build the v0.1.3 user state"
echo "v0.1.3 checkout + config seeding in place"

check "FROM: walker installed" rpm -q walker
check "FROM: hyprland-omedora installed" rpm -q hyprland-omedora
check "FROM: Python terminal effects installed" rpm -q python3-terminaltexteffects
check "FROM: Fedora Quickshell installed" rpm -q quickshell
dnf repoquery --installed --qf '%{from_repo}' quickshell 2>/dev/null \
  | grep -Eq '^(fedora|updates)$' \
  && ok "FROM: Quickshell came from Fedora" \
  || nok "FROM: Quickshell came from Fedora" \
    "repo: $(dnf repoquery --installed --qf '%{from_repo}' quickshell 2>/dev/null || true)"
[[ $(rpm -q --qf '%{VERSION}' quickshell 2>/dev/null) != "0.3.0^20.git28771c7" ]] \
  && ok "FROM: Quickshell predates the Quattro beta snapshot" \
  || nok "FROM: Quickshell predates the Quattro beta snapshot" \
    "version: $(rpm -q --qf '%{VERSION}' quickshell 2>/dev/null || true)"
for package in "${xr_o3_packages[@]}" monado-xreal; do
  check "FROM: XR package installed: $package" rpm -q "$package"
done
check "FROM: checkout is a git tree" test -d "$USER_HOME/.local/share/omarchy/.git"
check "FROM: seeded waybar config present" test -f "$USER_HOME/.config/waybar/config.jsonc"

# ---------------------------------------------------------------------------
echo "# --- the upgrade ---"
# ---------------------------------------------------------------------------

as_user "OMEDORA_PLAN_AUTOCONFIRM=1 timeout 3000 bash $REPO/bin/omedora-upgrade-to-4" \
  >/tmp/upgrade.log 2>&1 \
  || { echo "UPGRADE FAILED rc=$?"; tail -40 /tmp/upgrade.log; exit 1; }
echo "upgrade run complete"
# log/warn lines are ANSI-colored, so match anywhere in the line.
grep -aE '==>|Warning:' /tmp/upgrade.log | sed 's/^/  /' | head -40

# ---------------------------------------------------------------------------
echo "# --- assertions ---"
# ---------------------------------------------------------------------------

check "omedora installed" rpm -q omedora
check "omedora-settings installed" rpm -q omedora-settings
[[ $(rpm -q --qf '%{VERSION}' omedora 2>/dev/null) == "0.2.0~beta.2" ]] \
  && ok "Omedora core migrated to the Quattro beta package" \
  || nok "Omedora core migrated to the Quattro beta package" \
    "version: $(rpm -q --qf '%{VERSION}' omedora 2>/dev/null || true)"
[[ $(rpm -q --qf '%{VERSION}' omedora-settings 2>/dev/null) == "0.2.0~beta.2" ]] \
  && ok "Omedora settings migrated to the Quattro beta package" \
  || nok "Omedora settings migrated to the Quattro beta package" \
    "version: $(rpm -q --qf '%{VERSION}' omedora-settings 2>/dev/null || true)"

for p in walker elephant swayosd hypridle hyprlock hyprshot gazelle-tui \
         waybar mako swaybg hyprland-omedora; do
  if rpm -q "$p" >/dev/null 2>&1; then
    nok "retired package gone: $p" "$(rpm -q "$p")"
  else
    ok "retired package gone: $p"
  fi
done
check "kept: hyprland-no-session still installed" rpm -q hyprland-no-session
check "kept: uwsm still installed" rpm -q uwsm
[[ $(rpm -q --qf '%{VERSION}' quickshell 2>/dev/null) == "0.3.0^20.git28771c7" ]] \
  && ok "Quickshell matches the Quattro beta snapshot" \
  || nok "Quickshell matches the Quattro beta snapshot" \
    "version: $(rpm -q --qf '%{VERSION}' quickshell 2>/dev/null || true)"
check "new base dep installed: foot" rpm -q foot
for package in dotnet-runtime-10.0 vips-tools omacalc ttfx herdr; do
  check "new Quattro base dep installed: $package" rpm -q "$package"
done
dotnet --list-runtimes 2>/dev/null | grep -qE '^Microsoft\.NETCore\.App 10\.' \
  && ok ".NET 10 runtime is functional" \
  || nok ".NET 10 runtime is functional" "$(dotnet --list-runtimes 2>&1 || true)"
if rpm -q python3-terminaltexteffects >/dev/null 2>&1; then
  nok "ttfx retires python3-terminaltexteffects" "$(rpm -q python3-terminaltexteffects)"
else
  ok "ttfx retires python3-terminaltexteffects"
fi
if grep -q "Some base packages could not be installed" /tmp/upgrade.log; then
  nok "all Quattro base packages installed without fallback warning"
else
  ok "all Quattro base packages installed without fallback warning"
fi

# Every mandatory XR leaf/meta/session package must remain installed and be
# resolvable with the old COPR disabled. Equal-NEVR leaves can legitimately
# retain their original from_repo provenance after `dnf install`; the packages
# with Omedora 4 payload changes are checked separately by omedora-4 provenance
# (release numbers reset whenever the version bumps, so release magnitude
# cannot identify the payload).
# monado-xreal was explicitly installed in FROM and must survive by the same
# mechanism even though it remains optional for fresh installs.
for package in "${xr_v4_packages[@]}" monado-xreal; do
  if ! rpm -q "$package" >/dev/null 2>&1; then
    nok "XR package survives: $package"
    continue
  fi
  ok "XR package survives: $package"
  available_names=$(dnf repoquery --available --queryformat '%{name}\n' \
    "$package" 2>/dev/null || true)
  if grep -qxF "$package" <<<"$available_names"; then
    ok "XR package resolves with omedora-3 disabled: $package"
  else
    nok "XR package resolves with omedora-3 disabled: $package"
  fi
done

for package in \
  hypxrland hypxrvoice monado-xreal hypxrland-stack hypxrland-omedora; do
  package_evr=$(rpm -q --qf '%{VERSION}-%{RELEASE}' "$package" 2>/dev/null || true)
  package_repo=$(dnf repoquery --installed --qf '%{from_repo}' "$package" 2>/dev/null || true)
  if grep -Eq 'omedora-4$' <<<"$package_repo"; then
    ok "$package has the Omedora 4 payload ($package_evr from $package_repo)"
  else
    nok "$package has the Omedora 4 payload" \
      "evr: ${package_evr:-not installed}; repo: ${package_repo:-unknown}"
  fi
done
check "HypXRland owns the private compositor" \
  rpm -qf /usr/libexec/hypxrland/Hyprland
check "HypXRland owns the private XR-aware hyprctl" \
  rpm -qf /usr/libexec/hypxrland/hyprctl
check "stable hyprctl remains installed" test -x /usr/bin/hyprctl
check "private XR-aware hyprctl is installed" test -x /usr/libexec/hypxrland/hyprctl
[[ $(rpm -qf /usr/libexec/hypxrland/hyprctl 2>/dev/null) == hypxrland-* ]] \
  && ok "private XR-aware hyprctl owner is hypxrland" \
  || nok "private XR-aware hyprctl owner is hypxrland" \
    "owner: $(rpm -qf /usr/libexec/hypxrland/hyprctl 2>&1 || true)"

# The computed retired list came from dnf repoquery from_repo, not the fallback.
if grep -q "probing the known 3.8.2-era" /tmp/upgrade.log; then
  nok "retired list computed via dnf repoquery from_repo" "fallback probe was used"
else
  ok "retired list computed via dnf repoquery from_repo"
fi

link_target=$(readlink "$USER_HOME/.local/share/omarchy" || true)
[[ $link_target == /usr/share/omarchy ]] \
  && ok "checkout replaced by symlink to /usr/share/omarchy" \
  || nok "checkout replaced by symlink to /usr/share/omarchy" "target: '$link_target'"
backup_dir=$(compgen -G "$USER_HOME/.local/share/omarchy.pre-omedora-4-*.bak" | head -1)
[[ -n $backup_dir && -d $backup_dir/.git ]] \
  && ok "checkout backup beside it (with .git): ${backup_dir##*/}" \
  || nok "checkout backup beside it (with .git)"

check "stable Omedora GDM session entry present" \
  test -f /usr/share/wayland-sessions/omedora.desktop
check "Omedora XR GDM session entry present" \
  test -f /usr/share/wayland-sessions/omedora-xr.desktop
grep -qx 'Name=Omedora' /usr/share/wayland-sessions/omedora.desktop \
  && ok "stable session remains named Omedora" \
  || nok "stable session remains named Omedora"
grep -qx 'Name=Omedora XR' /usr/share/wayland-sessions/omedora-xr.desktop \
  && ok "XR session is named Omedora XR" \
  || nok "XR session is named Omedora XR"
grep -qx 'Exec=/usr/bin/hypxrland-session' /usr/share/wayland-sessions/omedora-xr.desktop \
  && ok "XR session uses the packaged launcher" \
  || nok "XR session uses the packaged launcher"
check "legacy classic env config present" \
  test -f /usr/share/omarchy/default/hypr/envs.conf
check "legacy classic autostart config present" \
  test -f /usr/share/omarchy/default/hypr/autostart.conf
check "omarchy payload present" test -d /usr/share/omarchy/shell

# The hash-match matrix on real files.
grep -q "my custom binds" "$USER_HOME/.config/hypr/bindings.conf" \
  && ok "customized hypr .conf preserved in place" \
  || nok "customized hypr .conf preserved in place"
check "v4 hyprland.lua installed" test -f "$USER_HOME/.config/hypr/hyprland.lua"
check "v4 shell.json installed" test -f "$USER_HOME/.config/omarchy/shell.json"
cmp -s "$USER_HOME/.config/btop/btop.conf" /usr/share/omarchy/config/btop/btop.conf \
  && ok "pristine shipped default refreshed to the packaged v4 default (btop)" \
  || nok "pristine shipped default refreshed to the packaged v4 default (btop)"
[[ ! -e $USER_HOME/.config/uwsm/env ]] \
  && ok "uwsm/env retired" || nok "uwsm/env retired"
compgen -G "$USER_HOME/.config/uwsm/env.pre-omedora-4-*.bak" >/dev/null \
  && ok "uwsm/env backed up (not destroyed)" || nok "uwsm/env backed up (not destroyed)"
grep -q "MY_CUSTOM_VAR=keep-me" "$USER_HOME/.config/uwsm/env.d/99-omarchy-upgrade-env" 2>/dev/null \
  && ok "custom uwsm env line migrated to env.d" || nok "custom uwsm env line migrated to env.d"
grep -q "my-custom-terminal" "$USER_HOME/.config/xdg-terminals.list" 2>/dev/null \
  && ok "customized retired file kept active as an override" \
  || nok "customized retired file kept active as an override"
compgen -G "$USER_HOME/.config/waybar.pre-omedora-4-*.bak" >/dev/null \
  && ok "waybar config moved to .bak" || nok "waybar config moved to .bak"
[[ ! -e $USER_HOME/.config/waybar ]] \
  && ok "waybar config no longer active" || nok "waybar config no longer active"
grep -q ">>> omedora >>>" "$USER_HOME/.bashrc" \
  && ok "~/.bashrc untouched (sentinel block intact)" \
  || nok "~/.bashrc untouched (sentinel block intact)"

# XR state stays byte-identical, except that hyprland-xr.conf follows Quattro's
# intentional move of the active theme from ~/.config to ~/.local/state.
for xr_rel in \
  .config/hypxr/setup.env \
  .config/hypxrvoice/config.toml \
  .config/hypxrhud/hypxrhud.toml \
  .config/wivrn/config.json \
  .config/wivrn/known_keys.json \
  .config/openxr/1/active_runtime.json \
  .config/systemd/user/wivrn.service.d/override.conf \
  .config/systemd/user/monado-xreal.service.d/override.conf; do
  cmp -s "$USER_HOME/$xr_rel" "$USER_HOME/.xr-pre-omedora-4/$xr_rel" \
    && ok "XR state preserved byte-for-byte: $xr_rel" \
    || nok "XR state preserved byte-for-byte: $xr_rel"
done

xr_expected=$(mktemp)
sed 's|~/.config/omarchy/current|~/.local/state/omarchy/current|g' \
  "$USER_HOME/.xr-pre-omedora-4/.config/hypr/hyprland-xr.conf" >"$xr_expected"
cmp -s "$USER_HOME/.config/hypr/hyprland-xr.conf" "$xr_expected" \
  && ok "XR config changed only by the intended theme-path rewrite" \
  || nok "XR config changed only by the intended theme-path rewrite" \
    "$(diff -u "$xr_expected" "$USER_HOME/.config/hypr/hyprland-xr.conf" || true)"
xr_config_backup=$(compgen -G \
  "$USER_HOME/.config/hypr/hyprland-xr.conf.pre-omedora-4-*.bak" | head -1)
[[ -n $xr_config_backup ]] && \
  cmp -s "$xr_config_backup" \
    "$USER_HOME/.xr-pre-omedora-4/.config/hypr/hyprland-xr.conf" \
  && ok "pre-rewrite XR config was backed up byte-for-byte" \
  || nok "pre-rewrite XR config was backed up byte-for-byte"

while IFS= read -r xr_source; do
  xr_source=${xr_source/#\~/$USER_HOME}
  if [[ -r $xr_source ]]; then
    ok "XR config source resolves: $xr_source"
  else
    nok "XR config source resolves: $xr_source"
  fi
done < <(sed -n \
  's/^[[:space:]]*source[[:space:]]*=[[:space:]]*//p' \
  "$USER_HOME/.config/hypr/hyprland-xr.conf")

# No graphical session in the container: step 9 must skip gracefully.
grep -q "No live Hyprland session" /tmp/upgrade.log \
  && ok "quickshell hot-start skipped gracefully (no session)" \
  || nok "quickshell hot-start skipped gracefully (no session)"

# omedora-3 COPR disabled after success.
if dnf repolist --enabled 2>/dev/null | grep -q "omedora-3"; then
  nok "omedora-3 COPR disabled"
else
  ok "omedora-3 COPR disabled"
fi
dnf repolist --enabled 2>/dev/null | grep -q "omedora-4" \
  && ok "omedora-4 COPR enabled" || nok "omedora-4 COPR enabled"

# Re-run is idempotent.
if as_user "OMEDORA_PLAN_AUTOCONFIRM=1 timeout 300 bash $REPO/bin/omedora-upgrade-to-4" \
     >/tmp/rerun.log 2>&1 && grep -q "Nothing to do" /tmp/rerun.log; then
  ok "re-run is idempotent (exit 0, nothing to do)"
else
  nok "re-run is idempotent (exit 0, nothing to do)" "$(tail -5 /tmp/rerun.log)"
fi

# The installed CLI works.
as_user "omarchy --help" >/tmp/help.log 2>&1 && grep -qi "omarchy" /tmp/help.log \
  && ok "omarchy --help works post-upgrade" \
  || nok "omarchy --help works post-upgrade" "$(tail -5 /tmp/help.log)"

# ---------------------------------------------------------------------------
echo "# --- L1 suites post-upgrade ---"
# ---------------------------------------------------------------------------
# Run as the (non-root) omedora user, like CI and real machines. test/cli is
# NOT in this set: it belongs to the Arch-contract CI job and needs an
# unversioned `python`, which Fedora doesn't ship by default.
for t in test/distro-test.sh test/pkg-map-test.sh test/pkg-helper-test.sh \
         test/hypxr-spec-test.sh test/quickshell-spec-test.sh test/update-flow-test.sh \
         test/upgrade-to-4-test.sh; do
  if as_user "bash $REPO/$t" >/tmp/l1.log 2>&1; then
    ok "post-upgrade L1: $t"
  else
    nok "post-upgrade L1: $t" "$(tail -10 /tmp/l1.log)"
  fi
done

echo
echo "1..$n"
if (( failed > 0 )); then
  echo "# P6 upgrade verification: $failed/$n FAILED"
  exit 1
fi
echo "# P6 upgrade verification: ALL $n GREEN"
