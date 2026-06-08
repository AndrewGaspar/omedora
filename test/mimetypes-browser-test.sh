#!/bin/bash
#
# L1 unit tests for install/config/mimetypes.sh default-browser handling.
#
# Verifies omedora's Fedora-gated "respect existing default browser" behavior
# while keeping the Arch path byte-identical to upstream omarchy:
#
#   - Arch:   always forces chromium.desktop as the default browser (upstream).
#   - Fedora, existing installed default (e.g. firefox.desktop): left alone.
#   - Fedora, no default set (empty/error from xdg-settings get): Chromium set.
#   - Fedora, stale default pointing at an uninstalled app: Chromium set.
#
# All external commands the script calls (xdg-settings, xdg-mime, omarchy-*,
# update-desktop-database) are stubbed onto PATH and log their args to
# $MOCK_LOG. No real MIME database or desktop files are touched. Distro is
# selected via OMARCHY_DISTRO so the test runs offline on any host.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SCRIPT="$ROOT/install/config/mimetypes.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

BIN="$TMPDIR/bin"
mkdir -p "$BIN"

# A fake XDG_DATA_HOME whose applications/ dir is where we plant (or omit) the
# "installed" .desktop files the script probes for.
DATA_HOME="$TMPDIR/data"
mkdir -p "$DATA_HOME/applications"

# --- Stub commands -----------------------------------------------------------
# xdg-settings: `get default-web-browser` echoes $MOCK_XDG_GET_OUT and exits
# $MOCK_XDG_GET_RC; everything else (e.g. `set ...`) just logs.
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
# `query default x-scheme-handler/mailto` echoes $MOCK_XDG_MAILTO (the user's
# existing mailto handler, if any) so the Fedora only-if-unset path can be tested.
if [[ ${1:-} == query && ${2:-} == default && ${3:-} == x-scheme-handler/mailto ]]; then
  [[ -n ${MOCK_XDG_MAILTO-} ]] && printf '%s\n' "$MOCK_XDG_MAILTO"
fi
exit 0
EOF

# Inert stubs for the other commands mimetypes.sh invokes.
for cmd in omarchy-refresh-applications update-desktop-database; do
  cat >"$BIN/$cmd" <<'EOF'
#!/bin/bash
exit 0
EOF
done
chmod +x "$BIN"/*

export PATH="$BIN:$ROOT/bin:$PATH"
export XDG_DATA_HOME="$DATA_HOME"

MOCK_LOG="$TMPDIR/mock.log"
export MOCK_LOG

# Run mimetypes.sh in a clean subshell with the given distro + xdg-get behavior,
# returning combined stdout for log-line assertions. $MOCK_LOG is reset first.
run_mimetypes() {
  : >"$MOCK_LOG"
  (
    export OMARCHY_DISTRO="$1"
    export MOCK_XDG_GET_OUT="$2"
    export MOCK_XDG_GET_RC="$3"
    export MOCK_XDG_MAILTO="${4-}"
    bash "$SCRIPT"
  )
}

log_has()  { grep -qF "$1" "$MOCK_LOG"; }

assert_mailto_forced() {
  local desc="$1"
  if log_has 'xdg-mime default HEY.desktop x-scheme-handler/mailto'; then
    pass "$desc"
  else
    printf 'Expected HEY to be set as the mailto handler. Log:\n' >&2
    cat "$MOCK_LOG" >&2
    fail "$desc"
  fi
}

assert_mailto_not_forced() {
  local desc="$1"
  if log_has 'xdg-mime default HEY.desktop x-scheme-handler/mailto'; then
    printf 'Did not expect HEY to be set as the mailto handler. Log:\n' >&2
    cat "$MOCK_LOG" >&2
    fail "$desc"
  fi
  pass "$desc"
}

assert_chromium_forced() {
  local desc="$1"
  if log_has 'xdg-settings set default-web-browser chromium.desktop' &&
    log_has 'xdg-mime default chromium.desktop x-scheme-handler/http' &&
    log_has 'xdg-mime default chromium.desktop x-scheme-handler/https'; then
    pass "$desc"
  else
    printf 'Expected the three chromium default-browser calls in:\n' >&2
    cat "$MOCK_LOG" >&2
    fail "$desc"
  fi
}

assert_chromium_not_forced() {
  local desc="$1"
  if log_has 'xdg-settings set default-web-browser chromium.desktop'; then
    printf 'Did not expect chromium to be set as default browser. Log:\n' >&2
    cat "$MOCK_LOG" >&2
    fail "$desc"
  fi
  pass "$desc"
}

# --- Arch: always forces chromium, regardless of any existing default --------
out=$(run_mimetypes arch "firefox.desktop" 0)
assert_chromium_forced "Arch forces chromium even when a default exists (upstream parity)"

out=$(run_mimetypes arch "" 0)
assert_chromium_forced "Arch forces chromium when no default is set"

# --- Fedora: respects an existing, installed default -------------------------
: >"$DATA_HOME/applications/firefox.desktop"  # firefox "installed"
out=$(run_mimetypes fedora "firefox.desktop" 0)
assert_chromium_not_forced "Fedora keeps an existing installed default (firefox)"
assert_output_contains "Fedora logs that it keeps the existing default" "$out" \
  "Keeping existing default browser: firefox.desktop"

# --- Fedora: no default set (empty output) -> Chromium -----------------------
out=$(run_mimetypes fedora "" 0)
assert_chromium_forced "Fedora sets Chromium when no default is configured"
assert_output_contains "Fedora logs that it falls back to Chromium" "$out" \
  "No default browser set; using Chromium."

# --- Fedora: xdg-settings get errors out -> Chromium -------------------------
out=$(run_mimetypes fedora "xdg-settings: command failed" 1)
assert_chromium_forced "Fedora sets Chromium when xdg-settings get errors"

# --- Fedora: stale default pointing at an UNINSTALLED app -> Chromium --------
rm -f "$DATA_HOME/applications/firefox.desktop"
out=$(run_mimetypes fedora "firefox.desktop" 0)
assert_chromium_forced "Fedora sets Chromium when the existing default isn't installed"

# --- mailto -> HEY only-if-unset --------------------------------------------
# Arch: HEY is always forced as the mailto handler (upstream parity), regardless
# of any existing handler.
out=$(run_mimetypes arch "" 0 "thunderbird.desktop")
assert_mailto_forced "Arch forces HEY as mailto handler even when one exists (upstream parity)"

out=$(run_mimetypes arch "" 0 "")
assert_mailto_forced "Arch forces HEY as mailto handler when none is set"

# Fedora: respects an existing, installed mailto handler.
: >"$DATA_HOME/applications/thunderbird.desktop"  # thunderbird "installed"
out=$(run_mimetypes fedora "" 0 "thunderbird.desktop")
assert_mailto_not_forced "Fedora keeps an existing installed mailto handler (thunderbird)"
assert_output_contains "Fedora logs that it keeps the existing mailto handler" "$out" \
  "Keeping existing mailto handler: thunderbird.desktop"

# Fedora: no mailto handler set -> HEY.
out=$(run_mimetypes fedora "" 0 "")
assert_mailto_forced "Fedora sets HEY when no mailto handler is configured"
assert_output_contains "Fedora logs that it falls back to HEY" "$out" \
  "No mailto handler set; using HEY."

# Fedora: stale mailto handler pointing at an UNINSTALLED app -> HEY.
rm -f "$DATA_HOME/applications/thunderbird.desktop"
out=$(run_mimetypes fedora "" 0 "thunderbird.desktop")
assert_mailto_forced "Fedora sets HEY when the existing mailto handler isn't installed"

echo "# all mimetypes-browser tests passed"
