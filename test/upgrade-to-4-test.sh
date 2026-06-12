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
REPOQUERY_OUT="$SCRATCH/repoquery.out"
export MOCK_LOG RPM_STATE REPOQUERY_OUT

stub() { printf '#!/bin/bash\n%s\n' "$2" >"$SHIM/$1"; chmod +x "$SHIM/$1"; }

stub sudo 'printf "sudo %s\n" "$*" >>"$MOCK_LOG"
while [[ ${1:-} == -* ]]; do shift; done   # swallow sudo flags (-n/-v probes)
[[ $# -gt 0 ]] || exit 0
exec "$@"'
stub dnf  'printf "dnf %s\n" "$*" >>"$MOCK_LOG"; exit 0'
stub rpm  'if [[ ${1:-} == -q ]]; then printf "rpm %s\n" "$*" >>"$MOCK_LOG"; grep -qxF "${2:-}" "$RPM_STATE" 2>/dev/null; exit $?; fi; exit 0'
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
# 4 line) AND hyprland/hyprutils (kept — same names continue on omedora-4);
# git/bash come from Fedora repos and must never be touched.
copr3="copr:copr.fedorainfracloud.org:agaspar:omedora-3"
cat >"$REPOQUERY_OUT" <<EOF
walker $copr3
swayosd $copr3
hyprland $copr3
hyprutils $copr3
git updates
bash anaconda
EOF
# rpm -q state: 3.8.2-era Fedora-proper extras that v4 retires + iwd.
printf 'waybar\nmako\niwd\n' >"$RPM_STATE"

# --- the fixture v4 payload (the OMEDORA_UPGRADE_PAYLOAD seam) ----------------
PAYLOAD="$SCRATCH/payload"
mkdir -p "$PAYLOAD/install/packages" "$PAYLOAD/bin/fedora" \
  "$PAYLOAD/default/hypr/toggles" "$PAYLOAD/default/omarchy-skill" \
  "$PAYLOAD/applications" "$PAYLOAD/shell"
cp -r "$ROOT/config" "$PAYLOAD/config"
cp -r "$ROOT/default/systemd" "$PAYLOAD/default/systemd"
cp "$ROOT/default/hypr/toggles/flags.lua" "$PAYLOAD/default/hypr/toggles/flags.lua"
cp "$ROOT/install/packages/fedora.toml" "$PAYLOAD/install/packages/fedora.toml"
cp "$ROOT/bin/fedora/pkg.py" "$PAYLOAD/bin/fedora/pkg.py"
printf 'quickshell\nfoot\n' >"$PAYLOAD/install/omarchy-base.packages"
printf 'icon\n' >"$PAYLOAD/icon.txt"
printf 'logo\n' >"$PAYLOAD/logo.txt"
touch "$PAYLOAD/default/omarchy-skill/SKILL.md"
printf '[Desktop Entry]\nName=Fixture\nType=Application\nExec=true\n' \
  >"$PAYLOAD/applications/Fixture.desktop"
for b in omarchy-setup-system omarchy-theme-set omarchy-restart-terminal; do
  printf '#!/bin/bash\nprintf "%s %%s\\n" "$*" >>"$MOCK_LOG"\nexit 0\n' "$b" >"$PAYLOAD/bin/$b"
  chmod +x "$PAYLOAD/bin/$b"
done

# --- a fake 3.8.2-line $HOME ---------------------------------------------------
# Legacy file contents are synthesized (CI checkouts are shallow; no `git show
# 3.8.2-omedora:` available). Hash-matched fixtures use files this repo ships
# whose sha256 IS in the upgrader's known-default table (verified):
#   config/btop/btop.conf        -> a known `refresh` hash
#   etc/fastfetch/config.jsonc   -> a known `retire` hash
make_home() {
  local h="$1"
  mkdir -p "$h/.config/hypr" "$h/.config/systemd/user" "$h/.local/share" "$h/.local/bin"

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
    REPOQUERY_OUT="$REPOQUERY_OUT" \
    IWD_ACTIVE_RC="${IWD_ACTIVE_RC:-3}" \
    OMEDORA_OS_RELEASE="$SCRATCH/os-fedora" \
    OMEDORA_DNF_CMD="$FAKE_DNF_QUERY" \
    OMEDORA_UPGRADE_PAYLOAD="$PAYLOAD" \
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
assert_output_lacks "plan keeps hyprland (still served on omedora-4)" "$out" $'\nhyprland '
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
grep -q "dnf -y copr disable agaspar/omedora-3" "$MOCK_LOG" \
  && pass "omedora-3 COPR disabled after success" || fail "omedora-3 COPR disabled after success"

remove_line=$(grep "dnf remove --noautoremove -y" "$MOCK_LOG" | head -1)
assert_output_contains "retired removal includes walker" "$remove_line" "walker"
assert_output_contains "retired removal includes swayosd" "$remove_line" "swayosd"
assert_output_contains "retired removal includes waybar" "$remove_line" "waybar"
assert_output_contains "retired removal includes mako" "$remove_line" "mako"
assert_output_contains "retired removal includes iwd (inactive)" "$remove_line" "iwd"
assert_output_lacks "retired removal keeps hyprland" "$remove_line" "hyprland"
assert_output_lacks "retired removal keeps hyprutils" "$remove_line" "hyprutils"
assert_output_lacks "retired removal never touches git" "$remove_line" " git"

# New base deps resolved through the v4 map (pkg.py dry-run seam).
assert_output_contains "v4 base set resolved through pkg.py" "$out" "[dry-run] sudo dnf install"
assert_output_contains "missing base package quickshell resolved" "$out" "quickshell"

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
assert_file_exists "finalize-user.done marker" "$H1/.local/state/omarchy/finalize-user.done"
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
  "$H1/.config/omarchy/current/theme/hyprland.conf"

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
