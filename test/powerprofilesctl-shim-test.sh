#!/bin/bash
#
# L1 unit test for install/user/powerprofilesctl-shim-fedora.sh.
#
# Fedora Workstation rides tuned-ppd, which provides the PowerProfiles D-Bus
# API but not the /usr/bin/powerprofilesctl CLI omarchy shells out to. The
# install step copies omedora's shim into ~/.local/bin/powerprofilesctl, but
# ONLY when no real CLI is present (so a power-profiles-daemon box keeps the
# genuine binary). This test drives that logic with a stubbed filesystem.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SCRIPT="$ROOT/install/user/powerprofilesctl-shim-fedora.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A fake OMARCHY_PATH whose omedora/bin holds the shim source.
FAKE_PATH="$TMP/omarchy"
mkdir -p "$FAKE_PATH/omedora/bin"
printf '#!/bin/bash\n# fake shim\n' >"$FAKE_PATH/omedora/bin/powerprofilesctl-shim"

# The script is `return`-based (sourced in finalize-user) but also runs
# standalone under `bash`; we exercise it standalone with HOME + OMARCHY_PATH
# pinned. The "real CLI already present" guard checks the literal
# /usr/bin/powerprofilesctl, which we can't plant without root, so that branch
# is left to the L3/L4 tiers; here we cover the writing + no-op + wiring paths.

# --- no real CLI -> shim installed to ~/.local/bin/powerprofilesctl ----------
H1="$TMP/home1"; mkdir -p "$H1"
( export HOME="$H1" OMARCHY_PATH="$FAKE_PATH" OMEDORA_REAL_PPCTL="$TMP/nope"; source "$SCRIPT" )
if [[ -x "$H1/.local/bin/powerprofilesctl" ]]; then
  pass "shim installed to ~/.local/bin/powerprofilesctl when no real CLI present"
else
  fail "shim installed to ~/.local/bin/powerprofilesctl when no real CLI present"
fi
grep -q "fake shim" "$H1/.local/bin/powerprofilesctl" \
  && pass "installed file is the omedora shim" \
  || fail "installed file is the omedora shim"

# --- idempotent re-run -------------------------------------------------------
( export HOME="$H1" OMARCHY_PATH="$FAKE_PATH" OMEDORA_REAL_PPCTL="$TMP/nope"; source "$SCRIPT" )
pass "re-run is idempotent (no error)"

# --- missing shim source -> graceful no-op -----------------------------------
H2="$TMP/home2"; mkdir -p "$H2"
EMPTY="$TMP/empty-omarchy"; mkdir -p "$EMPTY"
( export HOME="$H2" OMARCHY_PATH="$EMPTY" OMEDORA_REAL_PPCTL="$TMP/nope"; source "$SCRIPT" )
[[ ! -e "$H2/.local/bin/powerprofilesctl" ]] \
  && pass "missing shim source is a graceful no-op (nothing written)" \
  || fail "missing shim source is a graceful no-op (nothing written)"

# --- finalize-user wiring: the Fedora block sources the shim step ------------
grep -q 'powerprofilesctl-shim-fedora.sh' "$ROOT/bin/omarchy-finalize-user" \
  && pass "finalize-user sources the shim step on Fedora" \
  || fail "finalize-user sources the shim step on Fedora"

# --- the omedora RPM spec ships the shim binary under the payload ------------
grep -q 'omedora/bin/powerprofilesctl-shim' "$ROOT/omedora/packaging/copr/omedora.spec" \
  && pass "omedora.spec ships the shim binary under the payload" \
  || fail "omedora.spec ships the shim binary under the payload"

echo "# all powerprofilesctl-shim tests passed"
