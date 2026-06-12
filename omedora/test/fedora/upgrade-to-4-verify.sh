#!/bin/bash
#
# P6 upgrade-to-4 verification — runs INSIDE the fedora:44 test image.
#
# Proves bin/omedora-upgrade-to-4 against a REAL 3.8.2-line install:
#   1. build the FROM state: the live agaspar/omedora-3 COPR + the 3.8.2-era
#      RPM set (hyprland-omedora, walker/elephant, swayosd, hypridle/hyprlock/
#      hyprshot, gazelle-tui + the Fedora-proper waybar/mako/swaybg), and the
#      omedora v0.1.3 git checkout at ~/.local/share/omarchy with its config
#      seeding replayed (omedora-seed-config — what the 3.8.2 installer ran)
#   2. plant user customizations (hypr bindings, uwsm env, xdg-terminals.list)
#   3. run bin/omedora-upgrade-to-4 (OMEDORA_PLAN_AUTOCONFIRM=1)
#   4. assert: omedora+omedora-settings installed; retired RPMs GONE (incl.
#      hyprland-omedora via the settings Obsoletes); the kept Hyprland stack
#      still present; checkout -> .pre-omedora-4 backup + symlink to
#      /usr/share/omarchy; session entry present; the hash-match matrix
#      (refreshed/preserved/backed-up); quickshell hot-start skipped
#      gracefully (no session here); re-run idempotent exit 0;
#      `omarchy --help` works; the L1 suites stay green post-upgrade
#
# Run (host is Arch; podman, NOT docker; TMPDIR=/var/tmp/podman-tmp):
#   podman run --rm -v "$PWD:/repo" \
#     -v /var/tmp/omedora-dnf-cache:/var/cache/libdnf5 \
#     omedora-test:fedora44 bash /repo/omedora/test/fedora/upgrade-to-4-verify.sh

set -e

REPO="${REPO:-/repo}"
USER_NAME=omedora
USER_HOME=/home/$USER_NAME

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

# The 3.8.2-era package set this scenario asserts retirement on. COPR tier
# (hyprland-omedora pulls hyprland-no-session + uwsm + the vendored libs,
# exactly like a real v0.1.x install) + the Fedora-proper extras.
timeout 1800 dnf install -y --setopt=install_weak_deps=False \
  hyprland-omedora walker elephant swayosd hypridle hyprlock hyprshot \
  gazelle-tui waybar mako swaybg >/tmp/from-pkgs.log 2>&1 \
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
  # User customizations the upgrade must preserve:
  printf "\n# my custom binds\nbind = SUPER, Z, exec, true\n" >> ~/.config/hypr/bindings.conf
  printf "export MY_CUSTOM_VAR=keep-me\n" >> ~/.config/uwsm/env
  printf "my-custom-terminal.desktop\n" > ~/.config/xdg-terminals.list
' || bail "could not build the v0.1.3 user state"
echo "v0.1.3 checkout + config seeding in place"

check "FROM: walker installed" rpm -q walker
check "FROM: hyprland-omedora installed" rpm -q hyprland-omedora
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
check "new base dep installed: quickshell" rpm -q quickshell
check "new base dep installed: foot" rpm -q foot

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

check "GDM session entry present" test -f /usr/share/wayland-sessions/omedora.desktop
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
         test/update-flow-test.sh test/upgrade-to-4-test.sh; do
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
