#!/bin/bash
#
# L1 unit tests for the finalize-user default-app gating.
#
# Verifies omedora's Fedora-gated "respect existing defaults" behavior in
# bin/omarchy-finalize-user (the browser/mailto claims), while keeping the
# Arch path byte-identical to upstream omarchy:
#
#   - Arch:   always forces chromium.desktop + HEY.desktop (upstream parity).
#   - Fedora, existing installed default (firefox/thunderbird): left alone.
#   - Fedora, no default set: Chromium / HEY claimed.
#   - Fedora, stale default pointing at an uninstalled app: claimed.
#
# PART 1 exercises install/user/default-apps-fedora.sh directly (the policy).
# PART 2 runs the real bin/omarchy-finalize-user end-to-end against a fixture
# OMARCHY_INSTALL whose user/all.sh is a stub, proving the dispatch wiring:
# Fedora sources the sibling; Arch runs the upstream lines.
#
# All external commands (xdg-settings, xdg-mime, xdg-user-dirs-update,
# omarchy-refresh-applications, omarchy-distro consumers) are stubbed onto
# PATH and log to $MOCK_LOG. Mock pattern ported from the 3.8.2
# mimetypes-browser-test.sh.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

POLICY="$ROOT/install/user/default-apps-fedora.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

BIN="$TMP/bin"
mkdir -p "$BIN"

# A fake XDG_DATA_HOME whose applications/ dir is where we plant (or omit) the
# "installed" .desktop files the policy probes for.
DATA_HOME="$TMP/data"
mkdir -p "$DATA_HOME/applications"

# --- Stub commands -----------------------------------------------------------
cat >"$BIN/xdg-settings" <<'EOF'
#!/bin/bash
printf 'xdg-settings %s\n' "$*" >>"$MOCK_LOG"
if [[ ${1:-} == get && ${2:-} == default-web-browser ]]; then
  [[ -n ${MOCK_XDG_GET_OUT-} ]] && printf '%s\n' "$MOCK_XDG_GET_OUT"
  exit "${MOCK_XDG_GET_RC:-0}"
fi
exit 0
EOF

cat >"$BIN/xdg-mime" <<'EOF'
#!/bin/bash
printf 'xdg-mime %s\n' "$*" >>"$MOCK_LOG"
if [[ ${1:-} == query && ${2:-} == default && ${3:-} == x-scheme-handler/mailto ]]; then
  [[ -n ${MOCK_XDG_MAILTO-} ]] && printf '%s\n' "$MOCK_XDG_MAILTO"
fi
exit 0
EOF

# Inert stubs for everything else finalize-user touches. NOTE on
# omarchy-refresh-applications: finalize-user sources env-bootstrap, which
# prepends $OMARCHY_PATH/bin to PATH (OMARCHY_PATH=$ROOT here) — so the REAL
# script can shadow our stub. Stub its leaf command too
# (update-desktop-database isn't on stock ubuntu CI runners), so it runs
# inertly against the isolated fixture $HOME either way.
for cmd in omarchy-refresh-applications xdg-user-dirs-update mise update-desktop-database; do
  printf '#!/bin/bash\nexit 0\n' >"$BIN/$cmd"
done
chmod +x "$BIN"/*

export PATH="$BIN:$ROOT/bin:$PATH"
# Isolate BOTH XDG dirs: desktop_id_is_installed probes $XDG_DATA_HOME *and*
# $XDG_DATA_DIRS; without pinning DATA_DIRS a host that ships firefox.desktop
# would make the "isn't installed" cases resolve as installed.
export XDG_DATA_HOME="$DATA_HOME"
export XDG_DATA_DIRS="$DATA_HOME"

MOCK_LOG="$TMP/mock.log"
export MOCK_LOG

log_has() { grep -qF "$1" "$MOCK_LOG"; }

assert_browser_forced() {
  if log_has 'xdg-settings set default-web-browser chromium.desktop' &&
    log_has 'xdg-mime default chromium.desktop x-scheme-handler/http' &&
    log_has 'xdg-mime default chromium.desktop x-scheme-handler/https'; then
    pass "$1"
  else
    printf 'Expected the three chromium default-browser calls in:\n' >&2
    cat "$MOCK_LOG" >&2
    fail "$1"
  fi
}
assert_browser_not_forced() {
  if log_has 'xdg-settings set default-web-browser chromium.desktop'; then
    printf 'Did not expect chromium to be claimed. Log:\n' >&2; cat "$MOCK_LOG" >&2
    fail "$1"
  fi
  pass "$1"
}
assert_mailto_forced() {
  if log_has 'xdg-mime default HEY.desktop x-scheme-handler/mailto'; then
    pass "$1"
  else
    printf 'Expected HEY to be claimed. Log:\n' >&2; cat "$MOCK_LOG" >&2
    fail "$1"
  fi
}
assert_mailto_not_forced() {
  if log_has 'xdg-mime default HEY.desktop x-scheme-handler/mailto'; then
    printf 'Did not expect HEY to be claimed. Log:\n' >&2; cat "$MOCK_LOG" >&2
    fail "$1"
  fi
  pass "$1"
}

# ===========================================================================
echo "# --- PART 1: the only-if-unset policy (default-apps-fedora.sh) ---"
# ===========================================================================
run_policy() {  # $1 browser-get-out  $2 browser-get-rc  $3 mailto-query-out
  : >"$MOCK_LOG"
  (
    export MOCK_XDG_GET_OUT="$1" MOCK_XDG_GET_RC="$2" MOCK_XDG_MAILTO="${3-}"
    bash "$POLICY"
  )
}

# Existing, installed defaults -> respected.
: >"$DATA_HOME/applications/firefox.desktop"
: >"$DATA_HOME/applications/thunderbird.desktop"
out=$(run_policy "firefox.desktop" 0 "thunderbird.desktop")
assert_browser_not_forced "Fedora keeps an existing installed default browser"
assert_mailto_not_forced "Fedora keeps an existing installed mailto handler"
assert_output_contains "logs the kept browser" "$out" "Keeping existing default browser: firefox.desktop"
assert_output_contains "logs the kept mailto handler" "$out" "Keeping existing mailto handler: thunderbird.desktop"

# Nothing set -> claimed.
out=$(run_policy "" 0 "")
assert_browser_forced "Fedora claims the browser when none is set"
assert_mailto_forced "Fedora claims mailto when none is set"
assert_output_contains "logs the chromium fallback" "$out" "No default browser set; using Chromium."
assert_output_contains "logs the HEY fallback" "$out" "No mailto handler set; using HEY."

# xdg-settings get errors -> claimed.
out=$(run_policy "xdg-settings: command failed" 1 "")
assert_browser_forced "Fedora claims the browser when xdg-settings get errors"

# Stale defaults pointing at UNINSTALLED apps -> claimed.
rm -f "$DATA_HOME/applications/firefox.desktop" "$DATA_HOME/applications/thunderbird.desktop"
out=$(run_policy "firefox.desktop" 0 "thunderbird.desktop")
assert_browser_forced "Fedora claims the browser when the existing default isn't installed"
assert_mailto_forced "Fedora claims mailto when the existing handler isn't installed"

# ===========================================================================
echo "# --- PART 2: bin/omarchy-finalize-user dispatch wiring ---"
# ===========================================================================
# Fixture OMARCHY_INSTALL: stub user/all.sh (no theme/mise/keyring side
# effects) + the REAL default-apps-fedora.sh, so the dispatch in the real
# finalize-user is what's under test.
FIXTURE="$TMP/install"
mkdir -p "$FIXTURE/user"
printf '# stub: no user-stage side effects in this test\n' >"$FIXTURE/user/all.sh"
cp "$POLICY" "$FIXTURE/user/default-apps-fedora.sh"
# finalize-user's Fedora block also sources the powerprofilesctl shim step;
# the real script no-ops cleanly here (OMARCHY_PATH has no shim source), but
# it must EXIST to be sourced.
cp "$ROOT/install/user/powerprofilesctl-shim-fedora.sh" "$FIXTURE/user/powerprofilesctl-shim-fedora.sh"
# ...and the nvim bootstrap step. We stub it (the real one clones from GitHub +
# runs Lazy sync, which we don't want in an L1 unit test); the dispatch wiring
# is what PART 2 proves, and nvim-fedora-test.sh covers the real script.
printf '# stub: real nvim bootstrap exercised in nvim-fedora-test.sh\n' \
  >"$FIXTURE/user/nvim-fedora.sh"

run_finalize() {  # $1 distro  $2 browser-get-out  $3 mailto-query-out
  : >"$MOCK_LOG"
  (
    export HOME="$TMP/home-$1"
    rm -rf "$HOME"; mkdir -p "$HOME"
    export OMARCHY_DISTRO="$1" OMARCHY_PATH="$ROOT" OMARCHY_INSTALL="$FIXTURE"
    export MOCK_XDG_GET_OUT="$2" MOCK_XDG_GET_RC=0 MOCK_XDG_MAILTO="${3-}"
    bash "$ROOT/bin/omarchy-finalize-user" --force
  )
}

# Arch: upstream parity — unconditional claims even when defaults exist.
: >"$DATA_HOME/applications/firefox.desktop"
: >"$DATA_HOME/applications/thunderbird.desktop"
out=$(run_finalize arch "firefox.desktop" "thunderbird.desktop")
# (Upstream's Arch lines set the browser + mailto; the http(s) handler claims
# are part of the Fedora policy file only.)
if log_has 'xdg-settings set default-web-browser chromium.desktop'; then
  pass "Arch finalize forces chromium even when a default exists (upstream parity)"
else
  cat "$MOCK_LOG" >&2
  fail "Arch finalize forces chromium even when a default exists (upstream parity)"
fi
assert_mailto_forced "Arch finalize forces HEY even when a handler exists (upstream parity)"

# Fedora: existing installed defaults respected end-to-end.
out=$(run_finalize fedora "firefox.desktop" "thunderbird.desktop")
assert_browser_not_forced "Fedora finalize keeps the existing browser end-to-end"
assert_mailto_not_forced "Fedora finalize keeps the existing mailto handler end-to-end"
assert_output_contains "Fedora finalize completes" "$out" "User finalization complete."

# Fedora: nothing set -> claimed end-to-end.
out=$(run_finalize fedora "" "")
assert_browser_forced "Fedora finalize claims the browser when none is set end-to-end"
assert_mailto_forced "Fedora finalize claims mailto when none is set end-to-end"

echo "# all finalize-defaults tests passed"
