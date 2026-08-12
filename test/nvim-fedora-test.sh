#!/bin/bash
#
# L1 unit test for install/user/nvim-fedora.sh.
#
# On Fedora, omarchy-nvim is skip-mapped (its COPR build can't bake the plugin
# cache offline), so /etc/skel never seeds ~/.config/nvim and Neovim has no
# LazyVim/omarchy config (issue #106). This step bootstraps the same
# commit-pinned LazyVim+omarchy config on the user's networked machine and runs
# a headless Lazy sync. This test drives that logic with stubbed git + nvim so
# it stays offline, asserting:
#   - the distro gate (no-op on Arch),
#   - the prerequisite guards (no nvim / no git -> graceful skip),
#   - idempotency (skips when ~/.config/nvim/lazyvim.json already exists),
#   - the config is built from the starter base + omarchy overrides,
#   - the backup-don't-destroy behavior for an existing config AND for stray
#     ~/.local/share|state/.cache nvim trees,
#   - the headless Lazy sync is invoked,
#   - the finalize-user Fedora-block wiring (grep).
#
# Stub/tracer style ported from test/powerprofilesctl-shim-test.sh and
# test/update-flow-test.sh.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SCRIPT="$ROOT/install/user/nvim-fedora.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BIN="$TMP/bin"
mkdir -p "$BIN"

# --- Stub git -----------------------------------------------------------------
# The script does: clone --no-checkout into a workdir, then `git -C <dir>
# checkout <commit>`. Our stub creates the expected tree on checkout so the
# bootstrap can copy from it without touching the network. The "starter" clone
# gets a marker file; the "omarchy-pkgs" clone gets the pkgbuilds/omarchy-nvim
# overrides (lua/config/options.lua, plugin/, lazyvim.json).
cat >"$BIN/git" <<'EOF'
#!/bin/bash
printf 'git %s\n' "$*" >>"$MOCK_LOG"
# Find the clone target dir (last arg of a clone) or the -C dir (of checkout).
case "$1" in
  clone)
    # last positional arg is the destination
    for a in "$@"; do dest="$a"; done
    mkdir -p "$dest"
    # Remember which kind of repo this dest is, by URL.
    for a in "$@"; do
      case "$a" in
        *omarchy-pkgs*) echo pkgs   >"$dest/.stub-kind" ;;
        *LazyVim/starter*) echo starter >"$dest/.stub-kind" ;;
      esac
    done
    ;;
  -C)
    dir="$2"
    # $3 is the subcommand (checkout)
    if [[ ${3:-} == checkout ]]; then
      kind=$(cat "$dir/.stub-kind" 2>/dev/null || echo "")
      if [[ $kind == starter ]]; then
        mkdir -p "$dir/lua/config"
        # The real LazyVim starter ships lua/plugins/ (where the theme link lands).
        mkdir -p "$dir/lua/plugins"
        printf '%s\n' '-- starter base' >"$dir/lua/config/options.lua"
        printf 'starter\n' >"$dir/STARTER_MARKER"
        mkdir -p "$dir/.git"  # the script rm -rf's this; prove it does
      elif [[ $kind == pkgs ]]; then
        mkdir -p "$dir/pkgbuilds/omarchy-nvim/lua/config"
        mkdir -p "$dir/pkgbuilds/omarchy-nvim/plugin"
        printf '%s\n' '-- omarchy override' \
          >"$dir/pkgbuilds/omarchy-nvim/lua/config/options.lua"
        printf '%s\n' '-- omarchy plugin' \
          >"$dir/pkgbuilds/omarchy-nvim/plugin/omarchy.lua"
        printf '{"override":true}\n' \
          >"$dir/pkgbuilds/omarchy-nvim/lazyvim.json"
      fi
    fi
    ;;
esac
exit 0
EOF

# --- Stub nvim (tracer for the headless Lazy sync) ---------------------------
cat >"$BIN/nvim" <<'EOF'
#!/bin/bash
printf 'nvim %s\n' "$*" >>"$MOCK_LOG"
exit 0
EOF

# --- Stub omarchy-distro (drives the gate) -----------------------------------
cat >"$BIN/omarchy-distro" <<'EOF'
#!/bin/bash
printf '%s\n' "${MOCK_DISTRO:-fedora}"
EOF

chmod +x "$BIN"/*
export PATH="$BIN:$PATH"

MOCK_LOG="$TMP/mock.log"
export MOCK_LOG

# Run the script as a sourced step (its real call site), with HOME pinned to a
# fresh fixture and the distro forced.
LAST_HOME=""
OUT_FILE="$TMP/out"
# Runs the bootstrap with a fresh $HOME; sets LAST_HOME and writes the script's
# combined output to $OUT_FILE (read back into `out`). Not run in a
# command-substitution subshell so LAST_HOME survives.
run_bootstrap() {  # $1 distro
  : >"$MOCK_LOG"
  LAST_HOME="$TMP/home-$1-$RANDOM$RANDOM"
  mkdir -p "$LAST_HOME"
  (
    export HOME="$LAST_HOME" MOCK_DISTRO="$1" OMARCHY_DISTRO="$1"
    source "$SCRIPT"
  ) >"$OUT_FILE" 2>&1
  out=$(cat "$OUT_FILE")
}

log_has() { grep -qF "$1" "$MOCK_LOG"; }

# ===========================================================================
echo "# --- distro gate ---"
# ===========================================================================
run_bootstrap arch
if log_has 'git clone'; then
  fail "Arch run must be a no-op (no clone)"
else
  pass "Arch run is a no-op (no clone, no config built)"
fi
[[ ! -e "$LAST_HOME/.config/nvim" ]] \
  && pass "Arch run writes no ~/.config/nvim" \
  || fail "Arch run writes no ~/.config/nvim"

# ===========================================================================
echo "# --- happy path: Fedora bootstrap builds the config ---"
# ===========================================================================
run_bootstrap fedora
H="$LAST_HOME"
cfg="$H/.config/nvim"
assert_file_exists "starter base copied (STARTER_MARKER present)" "$cfg/STARTER_MARKER"
[[ ! -e "$cfg/.git" ]] \
  && pass "starter .git stripped from the config" \
  || fail "starter .git stripped from the config"
assert_file_exists "omarchy plugin override layered in" "$cfg/plugin/omarchy.lua"
assert_file_exists "omarchy lazyvim.json layered in" "$cfg/lazyvim.json"
grep -q '"override":true' "$cfg/lazyvim.json" \
  && pass "lazyvim.json is the omarchy override, not the starter's" \
  || fail "lazyvim.json is the omarchy override, not the starter's"
# options.lua gets the omarchy override copy PLUS the two appended settings.
grep -q 'omarchy override' "$cfg/lua/config/options.lua" \
  && pass "options.lua is the omarchy override layer" \
  || fail "options.lua is the omarchy override layer"
grep -q 'vim.opt.relativenumber = false' "$cfg/lua/config/options.lua" \
  && pass "relativenumber=false appended to options.lua" \
  || fail "relativenumber=false appended to options.lua"
grep -q 'vim.g.autoformat = false' "$cfg/lua/config/options.lua" \
  && pass "autoformat=false appended to options.lua" \
  || fail "autoformat=false appended to options.lua"
[[ -L "$cfg/lua/plugins/theme.lua" ]] \
  && pass "omarchy theme symlink created" \
  || fail "omarchy theme symlink created"
log_has 'nvim --headless +Lazy! sync +qa!' \
  && pass "headless Lazy sync invoked" \
  || fail "headless Lazy sync invoked"
assert_output_contains "logs completion" "$out" "Neovim config bootstrap complete."

# ===========================================================================
echo "# --- idempotency: existing lazyvim.json -> skip ---"
# ===========================================================================
: >"$MOCK_LOG"
H="$TMP/home-idem"; mkdir -p "$H/.config/nvim"
printf '{"version":8}\n' >"$H/.config/nvim/lazyvim.json"
out=$(
  export HOME="$H" MOCK_DISTRO=fedora OMARCHY_DISTRO=fedora
  source "$SCRIPT"
)
assert_output_contains "skips when config already present" "$out" \
  "already present"
if log_has 'git clone'; then
  fail "idempotent run must NOT re-clone"
else
  pass "idempotent run does not re-clone"
fi
# The pre-existing file is untouched (the omarchy override would set override:true).
grep -q '"version":8' "$H/.config/nvim/lazyvim.json" \
  && pass "existing lazyvim.json left untouched" \
  || fail "existing lazyvim.json left untouched"

# ===========================================================================
echo "# --- backup-don't-destroy: existing config + data/state/cache ---"
# ===========================================================================
: >"$MOCK_LOG"
H="$TMP/home-backup"; mkdir -p "$H"
# An existing nvim config with NO lazyvim.json (so the idempotency guard does
# not catch it) plus user plugin data/state/cache that must be preserved.
mkdir -p "$H/.config/nvim"
printf 'MY PRECIOUS CONFIG\n' >"$H/.config/nvim/init.lua"
mkdir -p "$H/.local/share/nvim/lazy"; printf 'PLUGINS\n' >"$H/.local/share/nvim/lazy/marker"
mkdir -p "$H/.local/state/nvim"; printf 'STATE\n' >"$H/.local/state/nvim/marker"
mkdir -p "$H/.cache/nvim"; printf 'CACHE\n' >"$H/.cache/nvim/marker"
out=$(
  export HOME="$H" MOCK_DISTRO=fedora OMARCHY_DISTRO=fedora
  source "$SCRIPT"
)
# The original config is backed up (timestamped), not destroyed.
backup=$(find "$H/.config" -maxdepth 1 -name 'nvim.backup.*' -type d | head -1)
[[ -n $backup ]] && grep -q 'MY PRECIOUS CONFIG' "$backup/init.lua" \
  && pass "existing config backed up (timestamped), not destroyed" \
  || fail "existing config backed up (timestamped), not destroyed"
# data/state/cache moved aside, not deleted.
for d in "share" "state"; do
  b=$(find "$H/.local/$d" -maxdepth 1 -name 'nvim.backup.*' -type d | head -1)
  [[ -n $b ]] \
    && pass ".local/$d/nvim backed up, not destroyed" \
    || fail ".local/$d/nvim backed up, not destroyed"
done
cb=$(find "$H/.cache" -maxdepth 1 -name 'nvim.backup.*' -type d | head -1)
[[ -n $cb ]] && grep -q 'CACHE' "$cb/marker" \
  && pass ".cache/nvim backed up, not destroyed" \
  || fail ".cache/nvim backed up, not destroyed"
# And a fresh config was still built.
assert_file_exists "fresh config built after backup" "$H/.config/nvim/lazyvim.json"

# ===========================================================================
echo "# --- prerequisite guards: missing nvim / git -> graceful skip ---"
# ===========================================================================
# The guards (command -v nvim / git) fire before any external command other
# than the omarchy-distro gate, so a PATH holding ONLY the stub git +
# omarchy-distro (no nvim, no system bins) is enough — and crucially keeps the
# REAL /usr/bin/nvim from being found and run.
#
# --- no nvim on PATH -> graceful skip ---
NONVIM="$TMP/no-nvim-bin"; mkdir -p "$NONVIM"
cp "$BIN/git" "$BIN/omarchy-distro" "$NONVIM/"
chmod +x "$NONVIM"/*
: >"$MOCK_LOG"
H="$TMP/home-nonvim"; mkdir -p "$H"
out=$(
  export HOME="$H" PATH="$NONVIM" MOCK_DISTRO=fedora OMARCHY_DISTRO=fedora
  source "$SCRIPT" 2>&1  # the skip notice goes to stderr
)
assert_output_contains "missing nvim -> graceful skip" "$out" \
  "nvim not installed"
[[ ! -e "$H/.config/nvim" ]] \
  && pass "missing nvim writes no config" \
  || fail "missing nvim writes no config"

# --- no git on PATH -> graceful skip ---
NOGIT="$TMP/no-git-bin"; mkdir -p "$NOGIT"
cp "$BIN/nvim" "$BIN/omarchy-distro" "$NOGIT/"
chmod +x "$NOGIT"/*
: >"$MOCK_LOG"
H="$TMP/home-nogit"; mkdir -p "$H"
out=$(
  export HOME="$H" PATH="$NOGIT" MOCK_DISTRO=fedora OMARCHY_DISTRO=fedora
  source "$SCRIPT" 2>&1  # the skip notice goes to stderr
)
assert_output_contains "missing git -> graceful skip" "$out" \
  "git not installed"
[[ ! -e "$H/.config/nvim" ]] \
  && pass "missing git writes no config" \
  || fail "missing git writes no config"

# ===========================================================================
echo "# --- finalize-user wiring: the Fedora block sources the step ---"
# ===========================================================================
grep -q 'nvim-fedora.sh' "$ROOT/bin/omarchy-provision-user" \
  && pass "finalize-user sources the nvim bootstrap step on Fedora" \
  || fail "finalize-user sources the nvim bootstrap step on Fedora"
# It must live inside the Fedora branch (not the Arch else / unconditionally).
awk '/== "fedora" \]\]; then/{f=1} /^else$/{f=0} f && /nvim-fedora.sh/{found=1} END{exit !found}' \
  "$ROOT/bin/omarchy-provision-user" \
  && pass "nvim bootstrap is inside the Fedora branch of finalize-user" \
  || fail "nvim bootstrap is inside the Fedora branch of finalize-user"

# ===========================================================================
echo "# --- pins match the retired omarchy-nvim.spec ---"
# ===========================================================================
SPEC="$ROOT/omedora/packaging/copr/omarchy-nvim.spec"
if [[ -f $SPEC ]]; then
  pkgs=$(grep -oE 'pkgs_commit [0-9a-f]+' "$SPEC" | awk '{print $2}')
  lazy=$(grep -oE 'lazyvim_commit [0-9a-f]+' "$SPEC" | awk '{print $2}')
  grep -q "OMARCHY_NVIM_PKGS_COMMIT=\"$pkgs\"" "$SCRIPT" \
    && pass "pkgs_commit pin matches the omarchy-nvim.spec" \
    || fail "pkgs_commit pin matches the omarchy-nvim.spec (spec=$pkgs)"
  grep -q "OMARCHY_NVIM_LAZYVIM_COMMIT=\"$lazy\"" "$SCRIPT" \
    && pass "lazyvim_commit pin matches the omarchy-nvim.spec" \
    || fail "lazyvim_commit pin matches the omarchy-nvim.spec (spec=$lazy)"
else
  pass "# SKIP spec pin cross-check (retired spec not present)"
fi

echo "# all nvim-fedora tests passed"
