#!/bin/bash
#
# L1 unit tests for bin/omedora-upgrade-to-4 (the 3.8.2-line -> omedora 4
# in-place upgrader). Everything external is stubbed on PATH (no network, no
# real package manager, no root); the installed v4 payload is a fixture tree
# built from this repo, selected via the OMEDORA_UPGRADE_PAYLOAD seam.
#
#   PART 1 — guards: non-Fedora refusal, root refusal, already-upgraded
#            idempotency (exit 0), missing-checkout refusal.
#   PART 2 — the plan gate: discloses the COPR swap, the COMPUTED retired
#            package list (from a mocked `dnf repoquery --installed` +
#            rpm state), and the checkout retirement; refuses without
#            --yes/autoconfirm; interactive decline aborts; and the gate
#            writes NOTHING (dry behavior).
#   PART 3 — the full mocked upgrade run (autoconfirm seam): repo swap +
#            package transaction order, retired removals, checkout backup +
#            symlink, the hash-match user transition (refresh / retire /
#            override-kept / customized-untouched / backup-then-write),
#            uwsm env migration, and the no-session quickshell skip.
#   PART 4 — re-run idempotency and the iwd-active special case.
#
# Style: test/update-flow-test.sh (PATH shims + a mock log).

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

UPGRADE="$ROOT/bin/omedora-upgrade-to-4"

SCRATCH="$(mktemp -d)"
trap '[[ -n $SCRATCH && -d $SCRATCH ]] && rm -rf "$SCRATCH"' EXIT

SHIM="$SCRATCH/shim"
mkdir -p "$SHIM"
MOCK_LOG="$SCRATCH/mock.log"
RPM_STATE="$SCRATCH/rpm-installed"
WHATREQ_STATE="$SCRATCH/rpm-whatrequires"
REPOQUERY_OUT="$SCRATCH/repoquery.out"
export MOCK_LOG RPM_STATE WHATREQ_STATE REPOQUERY_OUT

stub() { printf '#!/bin/bash\n%s\n' "$2" >"$SHIM/$1"; chmod +x "$SHIM/$1"; }

stub sudo 'printf "sudo %s\n" "$*" >>"$MOCK_LOG"
while [[ ${1:-} == -* ]]; do shift; done   # swallow sudo flags (-n/-v probes)
[[ $# -gt 0 ]] || exit 0
exec "$@"'
stub dnf  'printf "dnf %s\n" "$*" >>"$MOCK_LOG"
[[ -n ${DNF_FAIL_REFRESH:-} && " $* " == *" upgrade -y --refresh "* ]] && exit 42
exit 0'
# rpm stub: `-q <name>` consults $RPM_STATE (installed names, one per line);
# `-q --whatrequires <name>` consults $WHATREQ_STATE ("<name> <dependent>"
# pairs) and mimics rpm's "no package requires X" + exit 1 otherwise.
stub rpm 'printf "rpm %s\n" "$*" >>"$MOCK_LOG"
case " $* " in
  *" --whatrequires "*)
    pkg="${*: -1}"
    hits=$(awk -v p="$pkg" "\$1 == p { print \$2 }" "$WHATREQ_STATE" 2>/dev/null)
    if [[ -n $hits ]]; then printf "%s\n" "$hits"; exit 0; fi
    echo "no package requires $pkg"; exit 1 ;;
esac
if [[ ${1:-} == -q ]]; then grep -qxF "${2:-}" "$RPM_STATE" 2>/dev/null; exit $?; fi
exit 0'
stub systemctl 'printf "systemctl %s\n" "$*" >>"$MOCK_LOG"
case " $* " in *" is-active "*iwd*) exit "${IWD_ACTIVE_RC:-3}" ;; esac
exit 0'
stub pgrep 'exit 1'   # no live Hyprland session
stub pkill 'printf "pkill %s\n" "$*" >>"$MOCK_LOG"; exit 0'
stub findmnt 'echo ext4'
stub flatpak 'exit 1'
stub update-desktop-database 'exit 0'
stub gum 'exit 1'   # if a prompt ever reaches gum unexpectedly, it declines

# Read-only dnf query seam: serves the mocked `repoquery --installed` state.
FAKE_DNF_QUERY="$SCRATCH/fake-dnf-query"
cat >"$FAKE_DNF_QUERY" <<'EOF'
#!/bin/bash
case " $* " in
  *" repoquery "*" --installed "*|*" repoquery --installed "*)
    cat "$REPOQUERY_OUT" 2>/dev/null
    exit 0
    ;;
esac
exit 0
EOF
chmod +x "$FAKE_DNF_QUERY"

# os-release fixtures (the OMEDORA_OS_RELEASE seam).
printf 'ID=fedora\nVERSION_ID=44\n' >"$SCRATCH/os-fedora"
printf 'ID=arch\n' >"$SCRATCH/os-arch"

# Mocked installed state: omedora-3 COPR serves walker/swayosd (retired on the
# 4 line) AND hyprland/hyprutils/HypXRland (kept — same names continue on 4);
# git/bash come from Fedora repos and must never be touched.
copr3="copr:copr.fedorainfracloud.org:agaspar:omedora-3"
cat >"$REPOQUERY_OUT" <<EOF
walker $copr3
elephant $copr3
swayosd $copr3
hyprland $copr3
hyprutils $copr3
hypxrpaper $copr3
hypxrva $copr3
hypxrhud $copr3
hypxrvoice $copr3
hypxrvoice-model-base-en $copr3
wivrn-hypxr $copr3
monado-xreal $copr3
hypxrland $copr3
hypxrland-stack $copr3
hypxrland-omedora $copr3
git updates
bash anaconda
quickshell updates
EOF
# rpm -q state (must agree with the repoquery state above): the COPR set +
# the 3.8.2-era Fedora-proper extras that v4 retires + iwd + polkit-kde,
# which a coexisting KDE Plasma still requires (cascade guard).
printf '%s\n' \
  walker elephant swayosd hyprland hyprutils \
  hypxrpaper hypxrva hypxrhud hypxrvoice hypxrvoice-model-base-en \
  wivrn-hypxr monado-xreal hypxrland hypxrland-stack hypxrland-omedora \
  waybar mako iwd polkit-kde quickshell >"$RPM_STATE"
# whatrequires pairs: plasma-workspace (OUTSIDE the retired set) requires
# polkit-kde; walker (INSIDE the set) requires elephant — intra-set deps must
# not block removal.
printf 'polkit-kde plasma-workspace\nelephant walker\n' >"$WHATREQ_STATE"

# --- the fixture v4 payload (the OMEDORA_UPGRADE_PAYLOAD seam) ----------------
PAYLOAD="$SCRATCH/payload"
mkdir -p "$PAYLOAD/install/packages" "$PAYLOAD/bin/fedora" \
  "$PAYLOAD/default/hypr/toggles" "$PAYLOAD/default/agents/skills/omarchy" \
  "$PAYLOAD/applications" "$PAYLOAD/shell"
cp -r "$ROOT/config" "$PAYLOAD/config"
cp -r "$ROOT/default/systemd" "$PAYLOAD/default/systemd"
cp "$ROOT/default/hypr/toggles/flags.lua" "$PAYLOAD/default/hypr/toggles/flags.lua"
cp "$ROOT/install/packages/fedora.toml" "$PAYLOAD/install/packages/fedora.toml"
cp "$ROOT/bin/fedora/pkg.py" "$PAYLOAD/bin/fedora/pkg.py"
printf '%s\n' \
  dotnet-runtime libvips quickshell-git omacalc ttfx herdr foot \
  >"$PAYLOAD/install/omarchy-base.packages"
printf 'icon\n' >"$PAYLOAD/icon.txt"
printf 'logo\n' >"$PAYLOAD/logo.txt"
touch "$PAYLOAD/default/agents/skills/omarchy/SKILL.md"
printf '[Desktop Entry]\nName=Fixture\nType=Application\nExec=true\n' \
  >"$PAYLOAD/applications/Fixture.desktop"
for b in omarchy-setup-system omarchy-theme-set omarchy-restart-terminal omarchy-migrate; do
  printf '#!/bin/bash\nprintf "%s %%s\\n" "$*" >>"$MOCK_LOG"\nexit 0\n' "$b" >"$PAYLOAD/bin/$b"
  chmod +x "$PAYLOAD/bin/$b"
done

# --- a fake 3.8.2-line $HOME ---------------------------------------------------
# Legacy file contents are synthesized (CI checkouts are shallow; no `git show
# omedora-3:` available). Hash-matched fixtures use files this repo ships
# whose sha256 IS in the upgrader's known-default table (verified):
#   config/btop/btop.conf        -> a known `refresh` hash
#   etc/fastfetch/config.jsonc   -> a known `retire` hash
make_home() {
  local h="$1"
  mkdir -p \
    "$h/.config/hypr" "$h/.config/systemd/user" "$h/.local/share" "$h/.local/bin" \
    "$h/.config/omarchy/current/theme" "$h/.config/hypxr" "$h/.config/hypxrvoice" \
    "$h/.config/hypxrhud" "$h/.config/wivrn" "$h/.config/openxr/1" \
    "$h/.config/chromium/Default" \
    "$h/.config/systemd/user/wivrn.service.d" "$h/.config/systemd/user/monado-xreal.service.d"

  # The legacy git checkout with a snapshot stub inside.
  git init -q "$h/.local/share/omarchy"
  mkdir -p "$h/.local/share/omarchy/bin"
  printf '#!/bin/bash\nprintf "omedora-snapshot %%s\\n" "$*" >>"$MOCK_LOG"\nexit 0\n' \
    >"$h/.local/share/omarchy/bin/omedora-snapshot"
  chmod +x "$h/.local/share/omarchy/bin/omedora-snapshot"

  # Legacy hyprland.conf: sources the legacy default/hypr .conf tree + theme.
  cat >"$h/.config/hypr/hyprland.conf" <<'EOF'
source = ~/.local/share/omarchy/default/hypr/autostart.conf
source = ~/.config/omarchy/current/theme/hyprland.conf
source = ~/.config/hypr/bindings.conf
EOF
  printf '# my custom binds\nbind = SUPER, Z, exec, true\n' >"$h/.config/hypr/bindings.conf"
  cat >"$h/.config/hypr/hyprland-xr.conf" <<'EOF'
source = ~/.config/hypr/hyprland.conf
openxr {
  enabled = true
}
EOF

  # XR pairing, model, runtime, and machine-specific service state is user
  # data. The upgrade must preserve each byte-for-byte.
  printf 'GPU_DEVICE=/dev/dri/renderD128\n' >"$h/.config/hypxr/setup.env"
  printf '[intent]\nbackend = "rules"\n' >"$h/.config/hypxrvoice/config.toml"
  printf 'anchor = "desk"\n' >"$h/.config/hypxrhud/hypxrhud.toml"
  printf '{"encoder":"vaapi"}\n' >"$h/.config/wivrn/config.json"
  printf '{"headset":"paired-key"}\n' >"$h/.config/wivrn/known_keys.json"
  printf '{"runtime":"wivrn"}\n' >"$h/.config/openxr/1/active_runtime.json"
  printf '[Service]\nEnvironment=LIBVA_DRIVER_NAME=radeonsi\n' >"$h/.config/systemd/user/wivrn.service.d/override.conf"
  printf '[Service]\nEnvironment=VK_ICD_FILENAMES=/machine/icd.json\n' >"$h/.config/systemd/user/monado-xreal.service.d/override.conf"

  printf 'Tokyo Night\n' >"$h/.config/omarchy/current/theme.name"
  printf 'accent = "#7aa2f7"\n' >"$h/.config/omarchy/current/theme/colors.toml"
  printf 'legacy btop theme\n' >"$h/.config/omarchy/current/theme/btop.theme"
  printf '{"custom":"keep"}\n' >"$h/.config/omarchy/bar.json"
  cat >"$h/.config/chromium/Default/Preferences" <<'EOF'
{
  "extensions": {
    "commands": {
      "copy": {
        "extension": "bocglpkldciamkbmlphanhkfnhpmnbma",
        "command_name": "copy-url"
      }
    },
    "settings": {
      "bocglpkldciamkbmlphanhkfnhpmnbma": {
        "commands": {"copy-url": {"was_assigned": true}}
      },
      "bgpiichlckmfanooecilcjemknkcpngb": {
        "commands": {"copy-url": {}}
      }
    }
  }
}
EOF

  # Hash-matched shipped default -> must be refreshed (stays the v4 default).
  mkdir -p "$h/.config/btop"
  cp "$ROOT/config/btop/btop.conf" "$h/.config/btop/btop.conf"

  # Customized terminal config -> hash mismatch, must be left untouched.
  mkdir -p "$h/.config/alacritty"
  printf '# heavily customized by the user\n[font]\nsize = 22\n' >"$h/.config/alacritty/alacritty.toml"

  # Hash-matched retired file -> backed up then removed (package owns it now).
  mkdir -p "$h/.config/fastfetch"
  cp "$ROOT/etc/fastfetch/config.jsonc" "$h/.config/fastfetch/config.jsonc"

  # Customized retired file -> backed up AND kept active as an override.
  printf 'my-custom-terminal.desktop\n' >"$h/.config/xdg-terminals.list"

  # uwsm env: legacy omedora-managed lines + one real customization.
  mkdir -p "$h/.config/uwsm"
  cat >"$h/.config/uwsm/env" <<'EOF'
export OMARCHY_PATH=$HOME/.local/share/omarchy
export PATH=$OMARCHY_PATH/bin:$PATH:$HOME/.local/bin
export MY_CUSTOM_VAR=keep-me
EOF

  # Legacy UI config dir -> moved to .bak.
  mkdir -p "$h/.config/waybar"
  printf '{}\n' >"$h/.config/waybar/config.jsonc"

  # Seeded legacy user unit file -> backed up.
  printf '[Service]\nExecStart=/usr/bin/swayosd-server\n' \
    >"$h/.config/systemd/user/swayosd-server.service"

  # ~/.bashrc with the 3.8.2 sentinel block -> must never be touched.
  cat >"$h/.bashrc" <<'EOF'
# user content above
# >>> omedora >>>
if [[ $- == *i* && -r ~/.local/share/omarchy/default/bash/rc ]]; then
  source ~/.local/share/omarchy/default/bash/rc
fi
# <<< omedora <<<
# user content below
EOF

  local xr_rel
  for xr_rel in \
    .config/hypr/hyprland-xr.conf \
    .config/hypxr/setup.env \
    .config/hypxrvoice/config.toml \
    .config/hypxrhud/hypxrhud.toml \
    .config/wivrn/config.json \
    .config/wivrn/known_keys.json \
    .config/openxr/1/active_runtime.json \
    .config/systemd/user/wivrn.service.d/override.conf \
    .config/systemd/user/monado-xreal.service.d/override.conf; do
    cp "$h/$xr_rel" "$h/$xr_rel.pretest"
  done
}

# Common invocation: fedora os-release, fixture payload, mocked queries.
run_upgrade() {
  local home="$1"; shift
  env -i \
    HOME="$home" \
    USER="$(id -un)" \
    LOGNAME="$(id -un)" \
    PATH="$SHIM:/usr/local/bin:/usr/bin:/bin" \
    MOCK_LOG="$MOCK_LOG" \
    RPM_STATE="$RPM_STATE" \
    WHATREQ_STATE="$WHATREQ_STATE" \
    REPOQUERY_OUT="$REPOQUERY_OUT" \
    DNF_FAIL_REFRESH="${DNF_FAIL_REFRESH:-}" \
    IWD_ACTIVE_RC="${IWD_ACTIVE_RC:-3}" \
    OMEDORA_OS_RELEASE="$SCRATCH/os-fedora" \
    OMEDORA_DNF_CMD="$FAKE_DNF_QUERY" \
    OMEDORA_UPGRADE_PAYLOAD="$PAYLOAD" \
    OMEDORA_UPGRADE_EUID=1000 \
    OMARCHY_PKG_DRY_RUN=1 \
    "$@" bash "$UPGRADE"
}

# ===========================================================================
echo "# --- PART 1: guards ---"
# ===========================================================================

H1="$SCRATCH/home1"; make_home "$H1"

out=$(env HOME="$H1" OMEDORA_OS_RELEASE="$SCRATCH/os-arch" bash "$UPGRADE" 2>&1) && rc=0 || rc=$?
assert_equals "non-Fedora host refused" "1" "$rc"
assert_output_contains "non-Fedora message names Fedora" "$out" "only supported on Fedora"

out=$(env HOME="$H1" OMEDORA_OS_RELEASE="$SCRATCH/os-fedora" OMEDORA_UPGRADE_EUID=0 \
  bash "$UPGRADE" 2>&1) && rc=0 || rc=$?
assert_equals "root invocation refused" "1" "$rc"
assert_output_contains "root refusal explains sudo-internally" "$out" "not root"

H_DONE="$SCRATCH/home-done"
mkdir -p "$H_DONE/.local/share"
ln -s /usr/share/omarchy "$H_DONE/.local/share/omarchy"
out=$(run_upgrade "$H_DONE" 2>&1) && rc=0 || rc=$?
assert_equals "already-upgraded re-run exits 0" "0" "$rc"
assert_output_contains "already-upgraded message" "$out" "already"

H_EMPTY="$SCRATCH/home-empty"; mkdir -p "$H_EMPTY"
out=$(run_upgrade "$H_EMPTY" 2>&1) && rc=0 || rc=$?
assert_equals "missing legacy checkout refused" "1" "$rc"
assert_output_contains "missing-checkout message" "$out" "No 3.8.2-line omedora install found"

# ===========================================================================
echo "# --- PART 2: the plan gate (dry, discloses, refuses) ---"
# ===========================================================================

: >"$MOCK_LOG"
out=$(run_upgrade "$H1" OMEDORA_PLAN_FORCE_NONINTERACTIVE=1 2>&1) && rc=0 || rc=$?
assert_equals "no-tty without --yes refuses" "1" "$rc"
assert_output_contains "plan discloses the new COPR" "$out" "agaspar/omedora-4"
assert_output_contains "plan discloses disabling the old COPR" "$out" "agaspar/omedora-3"
assert_output_contains "plan lists computed retired package walker" "$out" "walker"
assert_output_contains "plan lists computed retired package swayosd" "$out" "swayosd"
assert_output_contains "plan lists installed extra waybar" "$out" "waybar"
assert_output_contains "plan lists iwd (installed, inactive)" "$out" "iwd"
assert_output_contains "plan discloses v4 survivor migration" "$out" "migrate 12 installed package(s)"
assert_output_contains "plan lists surviving stable Hyprland" "$out" "hyprland"
assert_output_contains "plan lists surviving HypXRland" "$out" "hypxrland"
assert_output_contains "plan keeps polkit-kde for its outside dependent" "$out" \
  "polkit-kde (required by: plasma-workspace)"
assert_output_contains "plan discloses the checkout retirement backup" "$out" ".pre-omedora-4-"
assert_output_contains "plan discloses the config engine" "$out" "hash-match"
assert_output_contains "refusal points at --yes" "$out" "--yes"

# Read-only probes (sudo -n true, rpm -q, repoquery) are fine; nothing may
# mutate before consent.
grep -qE 'dnf (install|remove|mark)|copr (enable|disable)|systemctl (enable|disable|stop)' "$MOCK_LOG" \
  && fail "gate is dry: no mutating calls before consent" \
  || pass "gate is dry: no mutating calls before consent"
[[ -L $H1/.local/share/omarchy ]] \
  && fail "gate is dry: checkout not yet retired" \
  || pass "gate is dry: checkout not yet retired"
[[ -f $H1/.config/uwsm/env ]] && ! compgen -G "$H1/.config/uwsm/env.pre-omedora-4-*" >/dev/null \
  && pass "gate is dry: no config backups written" \
  || fail "gate is dry: no config backups written"

out=$(echo n | run_upgrade "$H1" OMEDORA_PLAN_FORCE_INTERACTIVE=1 2>&1) && rc=0 || rc=$?
assert_equals "interactive decline aborts" "1" "$rc"
assert_output_contains "interactive decline message" "$out" "aborted at your request"

H_FAIL="$SCRATCH/home-failed-survivor"; make_home "$H_FAIL"
: >"$MOCK_LOG"
out=$(DNF_FAIL_REFRESH=1 run_upgrade "$H_FAIL" OMEDORA_PLAN_AUTOCONFIRM=1 \
  OMEDORA_PLAN_FORCE_NONINTERACTIVE=1 2>&1) && rc=0 || rc=$?
assert_equals "failed survivor migration aborts" "42" "$rc"
grep -q "copr disable agaspar/omedora-3" "$MOCK_LOG" \
  && fail "failed survivor migration keeps old COPR enabled" \
  || pass "failed survivor migration keeps old COPR enabled"
[[ -d $H_FAIL/.local/share/omarchy/.git && ! -L $H_FAIL/.local/share/omarchy ]] \
  && pass "failed survivor migration keeps legacy checkout active" \
  || fail "failed survivor migration keeps legacy checkout active"

# ===========================================================================
echo "# --- PART 3: the full mocked upgrade (autoconfirm seam) ---"
# ===========================================================================

: >"$MOCK_LOG"
out=$(run_upgrade "$H1" OMEDORA_PLAN_AUTOCONFIRM=1 OMEDORA_PLAN_FORCE_NONINTERACTIVE=1 \
  OMEDORA_SNAPSHOT=1 2>&1) && rc=0 || rc=$?
assert_equals "autoconfirmed upgrade exits 0" "0" "$rc"
assert_output_contains "autoconfirm seam acknowledged" "$out" "proceeding with the upgrade plan"
assert_output_contains "completion banner" "$out" "Omedora 4 upgrade complete"

# Snapshot ran from the legacy checkout, before any package change.
assert_output_contains "snapshot taken" "$(cat "$MOCK_LOG")" "omedora-snapshot create pre-omedora-4"

# Repo + package transaction order and content.
grep -q "dnf -y copr enable agaspar/omedora-4" "$MOCK_LOG" \
  && pass "omedora-4 COPR enabled" || fail "omedora-4 COPR enabled"
grep -q "dnf install -y omedora omedora-settings" "$MOCK_LOG" \
  && pass "omedora + omedora-settings in ONE transaction" \
  || fail "omedora + omedora-settings in ONE transaction"
grep -q "dnf mark user omedora omedora-settings" "$MOCK_LOG" \
  && pass "packages marked user-installed" || fail "packages marked user-installed"
survivor_line=$(grep "dnf upgrade -y --refresh" "$MOCK_LOG" | head -1)
for package in \
  hyprland hyprutils hypxrpaper hypxrva hypxrhud hypxrvoice \
  hypxrvoice-model-base-en wivrn-hypxr monado-xreal hypxrland \
  hypxrland-stack hypxrland-omedora; do
  assert_output_contains "survivor transaction includes $package" "$survivor_line" "$package"
done
survivor_lineno=$(grep -n "dnf upgrade -y --refresh" "$MOCK_LOG" | head -1 | cut -d: -f1)
disable_lineno=$(grep -n "dnf -y copr disable agaspar/omedora-3" "$MOCK_LOG" | head -1 | cut -d: -f1)
(( survivor_lineno < disable_lineno )) \
  && pass "survivors migrate before old COPR disable" \
  || fail "survivors migrate before old COPR disable"
grep -q "dnf -y copr disable agaspar/omedora-3" "$MOCK_LOG" \
  && pass "omedora-3 COPR disabled after success" || fail "omedora-3 COPR disabled after success"

remove_line=$(grep "dnf remove --noautoremove -y" "$MOCK_LOG" | head -1)
assert_output_contains "retired removal includes walker" "$remove_line" "walker"
assert_output_contains "retired removal includes swayosd" "$remove_line" "swayosd"
assert_output_contains "retired removal includes waybar" "$remove_line" "waybar"
assert_output_contains "retired removal includes mako" "$remove_line" "mako"
assert_output_contains "retired removal includes iwd (inactive)" "$remove_line" "iwd"
assert_output_contains "retired removal includes elephant (intra-set dependent ok)" "$remove_line" "elephant"
assert_output_lacks "retired removal keeps polkit-kde (outside dependent)" "$remove_line" "polkit-kde"
assert_output_lacks "retired removal keeps hyprland" "$remove_line" "hyprland"
assert_output_lacks "retired removal keeps hyprutils" "$remove_line" "hyprutils"
assert_output_lacks "retired removal keeps hypxrland" "$remove_line" "hypxrland"
assert_output_lacks "retired removal keeps Omedora XR session" "$remove_line" "hypxrland-omedora"
assert_output_lacks "retired removal never touches git" "$remove_line" " git"

# New base deps resolved through the v4 map (pkg.py dry-run seam).
assert_output_contains "v4 base set resolved through pkg.py" "$out" "[dry-run] sudo dnf install"
base_install_line=$(grep '\[dry-run\] sudo dnf install' <<<"$out" | tail -1)
for package in dotnet-runtime-10.0 vips-tools omacalc ttfx herdr; do
  assert_output_contains "Quattro base mapping resolved: $package" \
    "$base_install_line" "$package"
done
assert_output_lacks "installed Fedora Quickshell skipped by the add-only resolver" \
  "$base_install_line" "quickshell"
grep -q '^sudo dnf upgrade -y --refresh quickshell$' "$MOCK_LOG" \
  && pass "installed Fedora Quickshell forced onto the Omedora snapshot" \
  || fail "installed Fedora Quickshell forced onto the Omedora snapshot"

# Checkout retirement: backup + symlink (no live session -> no overlay).
backup_dir=$(compgen -G "$H1/.local/share/omarchy.pre-omedora-4-*.bak" | head -1)
[[ -n $backup_dir && -d $backup_dir/.git ]] \
  && pass "checkout backed up with its .git" || fail "checkout backed up with its .git"
assert_equals "checkout replaced by the package symlink" \
  "$(readlink "$H1/.local/share/omarchy")" "/usr/share/omarchy"

# User transition: the hash-match matrix.
cmp -s "$H1/.config/btop/btop.conf" "$PAYLOAD/config/btop/btop.conf" \
  && pass "hash-matched shipped default refreshed to the v4 default" \
  || fail "hash-matched shipped default refreshed to the v4 default"
grep -q "size = 22" "$H1/.config/alacritty/alacritty.toml" \
  && pass "customized config left untouched" || fail "customized config left untouched"
compgen -G "$H1/.config/alacritty/alacritty.toml.pre-omedora-4-*" >/dev/null \
  && fail "customized config not needlessly backed up" \
  || pass "customized config not needlessly backed up"

[[ ! -e $H1/.config/fastfetch/config.jsonc ]] \
  && pass "hash-matched retired file removed (package owns it now)" \
  || fail "hash-matched retired file removed (package owns it now)"
compgen -G "$H1/.config/fastfetch/config.jsonc.pre-omedora-4-*.bak" >/dev/null \
  && pass "retired file backed up first" || fail "retired file backed up first"

grep -q "my-custom-terminal" "$H1/.config/xdg-terminals.list" \
  && pass "customized retired file kept active as an override" \
  || fail "customized retired file kept active as an override"
compgen -G "$H1/.config/xdg-terminals.list.pre-omedora-4-*.bak" >/dev/null \
  && pass "customized retired file backed up too" \
  || fail "customized retired file backed up too"

# uwsm env migration.
[[ ! -f $H1/.config/uwsm/env ]] \
  && pass "uwsm/env retired (package env.d owns it)" || fail "uwsm/env retired (package env.d owns it)"
compgen -G "$H1/.config/uwsm/env.pre-omedora-4-*.bak" >/dev/null \
  && pass "uwsm/env backed up" || fail "uwsm/env backed up"
grep -q "MY_CUSTOM_VAR=keep-me" "$H1/.config/uwsm/env.d/99-omarchy-upgrade-env" \
  && pass "custom uwsm env line migrated to env.d" || fail "custom uwsm env line migrated to env.d"
grep -q "OMARCHY_PATH=\$HOME" "$H1/.config/uwsm/env.d/99-omarchy-upgrade-env" \
  && fail "legacy OMARCHY_PATH line neutralized in env.d" \
  || pass "legacy OMARCHY_PATH line neutralized in env.d"

# Legacy UI configs + units retired with backups; hypr .conf left in place.
compgen -G "$H1/.config/waybar.pre-omedora-4-*.bak" >/dev/null \
  && pass "waybar config dir moved to .bak" || fail "waybar config dir moved to .bak"
[[ ! -e $H1/.config/waybar ]] \
  && pass "waybar config dir no longer active" || fail "waybar config dir no longer active"
compgen -G "$H1/.config/systemd/user/swayosd-server.service.pre-omedora-4-*.bak" >/dev/null \
  && pass "legacy user unit file backed up" || fail "legacy user unit file backed up"
grep -q "my custom binds" "$H1/.config/hypr/bindings.conf" \
  && pass "legacy hypr .conf kept in place for reference" \
  || fail "legacy hypr .conf kept in place for reference"

# v4 entry points + payload seeding.
assert_file_exists "v4 hyprland.lua installed" "$H1/.config/hypr/hyprland.lua"
assert_file_exists "v4 shell.json installed" "$H1/.config/omarchy/shell.json"
assert_file_exists "toggles flags.lua seeded" "$H1/.local/state/omarchy/toggles/hypr/flags.lua"
assert_file_exists "empty legacy toggles flags.conf kept for the live session" \
  "$H1/.local/state/omarchy/toggles/hypr/flags.conf"
assert_file_exists "branding about.txt seeded" "$H1/.config/omarchy/branding/about.txt"
assert_file_exists "XCompose created when absent" "$H1/.XCompose"
assert_file_exists "shipped desktop launcher copied" \
  "$H1/.local/share/applications/Fixture.desktop"
assert_file_exists "finalize-user marker" "$H1/.local/state/omarchy/done/finalize-user"
assert_file_exists "first-run-user marker" "$H1/.local/state/omarchy/done/first-run-user"
[[ ! -e $H1/.local/state/omarchy/finalize-user.done ]] \
  && pass "legacy finalize marker absent" || fail "legacy finalize marker absent"
[[ ! -e $H1/.config/git/config ]] \
  && pass "git/config never created (protected)" || fail "git/config never created (protected)"
compgen -G "$H1/.config/systemd/user/*.wants/omarchy-sleep-lock.service" >/dev/null \
  && pass "v4 sleep-lock unit statically enabled" || fail "v4 sleep-lock unit statically enabled"

# ~/.bashrc untouched (the 3.8.2 block keeps working via the symlink).
grep -q "user content below" "$H1/.bashrc" && grep -q ">>> omedora >>>" "$H1/.bashrc" \
  && pass "~/.bashrc untouched" || fail "~/.bashrc untouched"

# Theme + live-session shim plumbing.
grep -q "omarchy-theme-set" "$MOCK_LOG" \
  && pass "theme refreshed with v4 templates" || fail "theme refreshed with v4 templates"
assert_file_exists "legacy theme hyprland.conf shim written" \
  "$H1/.local/state/omarchy/current/theme/hyprland.conf"
assert_file_exists "theme state moved to local state" \
  "$H1/.local/state/omarchy/current/theme.name"
[[ ! -e $H1/.config/omarchy/current ]] \
  && pass "legacy theme state path retired" || fail "legacy theme state path retired"
assert_equals "btop theme follows beta state path" \
  "$(readlink "$H1/.config/btop/themes/current.theme")" \
  "$H1/.local/state/omarchy/current/theme/btop.theme"
grep -q '~/.local/state/omarchy/current/theme/hyprland.conf' "$H1/.config/hypr/hyprland.conf" \
  && pass "legacy Hyprland theme source rewritten" \
  || fail "legacy Hyprland theme source rewritten"
assert_file_exists "rewritten Hyprland config backed up" \
  "$(compgen -G "$H1/.config/hypr/hyprland.conf.pre-omedora-4-*.bak" | head -1)"
grep -q '"custom":"keep"' "$H1/.config/omarchy/bar.json" \
  && pass "obsolete bar.json remains user-owned" || fail "obsolete bar.json remains user-owned"
grep -q '"extension":"bgpiichlckmfanooecilcjemknkcpngb"' \
  "$H1/.config/chromium/Default/Preferences" \
  && pass "Chromium Copy URL shortcut migrated to beta extension" \
  || fail "Chromium Copy URL shortcut migrated to beta extension"
compgen -G "$H1/.config/chromium/Default/Preferences.pre-omedora-4-*.bak" >/dev/null \
  && pass "Chromium shortcut preferences backed up" \
  || fail "Chromium shortcut preferences backed up"

for skill_root in .agents/skills .claude/skills .codex/skills .pi/agent/skills; do
  assert_equals "$skill_root uses beta skill tree" \
    "$(readlink "$H1/$skill_root/omarchy")" \
    "$PAYLOAD/default/agents/skills/omarchy"
done
assert_file_exists "WirePlumber beta default seeded" \
  "$H1/.config/wireplumber/wireplumber.conf.d/bluetooth-a2dp-autoconnect.conf"
grep -q 'omarchy-migrate' "$MOCK_LOG" \
  && pass "pending beta migrations invoked" || fail "pending beta migrations invoked"

# XR state and the standalone XR entry point survive byte-for-byte.
for xr_rel in \
  .config/hypr/hyprland-xr.conf \
  .config/hypxr/setup.env \
  .config/hypxrvoice/config.toml \
  .config/hypxrhud/hypxrhud.toml \
  .config/wivrn/config.json \
  .config/wivrn/known_keys.json \
  .config/openxr/1/active_runtime.json \
  .config/systemd/user/wivrn.service.d/override.conf \
  .config/systemd/user/monado-xreal.service.d/override.conf; do
  cmp -s "$H1/$xr_rel" "$H1/$xr_rel.pretest" \
    && pass "XR state preserved: $xr_rel" || fail "XR state preserved: $xr_rel"
done

# System transition handed to the installed, Fedora-gated setup.
grep -q -- "omarchy-setup-system --install-user $(id -un) --upgrade" "$MOCK_LOG" \
  && pass "system transition via omarchy-setup-system --upgrade" \
  || fail "system transition via omarchy-setup-system --upgrade"

# No session in this environment: quickshell hot-start skipped gracefully.
assert_output_contains "quickshell hot-start skipped without a session" "$out" \
  "No live Hyprland session"
grep -q "pkill -x waybar" "$MOCK_LOG" \
  && fail "retired processes not stopped without a verified shell" \
  || pass "retired processes not stopped without a verified shell"

# ===========================================================================
echo "# --- PART 4: re-run idempotency + iwd special case ---"
# ===========================================================================

out=$(run_upgrade "$H1" OMEDORA_PLAN_AUTOCONFIRM=1 OMEDORA_PLAN_FORCE_NONINTERACTIVE=1 2>&1) && rc=0 || rc=$?
assert_equals "re-run after upgrade exits 0" "0" "$rc"
assert_output_contains "re-run reports nothing to do" "$out" "Nothing to do"

H2="$SCRATCH/home2"; make_home "$H2"
out=$(IWD_ACTIVE_RC=0 run_upgrade "$H2" OMEDORA_PLAN_FORCE_NONINTERACTIVE=1 2>&1) && rc=0 || rc=$?
assert_equals "gate run (iwd active) still refuses without --yes" "1" "$rc"
assert_output_contains "active iwd is left alone with a warning" "$out" "leaving it in place"

echo
echo "# upgrade-to-4-test: all assertions passed"

# ===========================================================================
echo "# --- spec-set cross-check: v4_kept_packages can't silently desync ---"
# ===========================================================================
# Every spec in build-repo.sh's SPECS array (the canonical v4-served set) must
# appear in the upgrader's v4_kept_packages list — a future spec addition that
# forgets the upgrader would otherwise let the upgrade REMOVE a package the
# Omedora 4 COPR still serves.
spec_names=$(sed -n '/^SPECS=(/,/^)/p' "$ROOT/omedora/packaging/copr/build-repo.sh" \
  | sed 's/#.*//' | grep -oE '[a-zA-Z0-9._-]+\.spec' | sed 's/\.spec$//' | sort -u)
kept_names=$(sed -n '/^v4_kept_packages=(/,/^)/p' "$ROOT/bin/omedora-upgrade-to-4" \
  | sed '1d;$d;s/#.*//' | tr -s '[:space:]' '\n' | sed '/^$/d')
# On-demand specs the COPR serves but the upgrade must NOT force-install: they
# are installed only when the user opts in (e.g. clicking Install Dictation), so
# they are intentionally absent from v4_kept_packages. voxtype (+ its -cuda/
# -migraphx GPU subpackages, same spec) is the dictation engine — on-demand.
on_demand_specs=" voxtype "
missing=""
for s in $spec_names; do
  [[ $on_demand_specs == *" $s "* ]] && continue
  grep -qxF "$s" <<<"$kept_names" || missing="$missing $s"
done
if [[ -n $missing ]]; then
  echo "specs served by the v4 COPR but absent from v4_kept_packages:$missing" >&2
  fail "every build-repo.sh spec is covered by v4_kept_packages"
else
  pass "every build-repo.sh spec is covered by v4_kept_packages"
fi
