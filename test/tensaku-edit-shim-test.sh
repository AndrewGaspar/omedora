#!/bin/bash
#
# L1 unit test for install/user/tensaku-edit-shim-fedora.sh + the tensaku-edit
# satty shim.
#
# The quattro line swapped Omarchy's screenshot/clipboard annotation editor from
# satty to `tensaku-edit` (the `tensaku` package). omedora now packages tensaku
# natively (omedora/packaging/copr/tensaku.spec, tensaku-spec-test.sh), which
# provides the real /usr/bin/tensaku-edit — but it ALSO keeps satty and this
# tensaku-edit -> satty wrapper as a self-deactivating FALLBACK: the wrapper
# installs into ~/.local/bin ONLY when no genuine tensaku-edit is present, so a
# native tensaku auto-wins. This test drives that logic with a stubbed
# filesystem, mirroring powerprofilesctl-shim-test.sh.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SCRIPT="$ROOT/install/user/tensaku-edit-shim-fedora.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# A fake OMARCHY_PATH whose omedora/bin holds the real shim source.
FAKE_PATH="$TMP/omarchy"
mkdir -p "$FAKE_PATH/omedora/bin"
cp "$ROOT/omedora/bin/tensaku-edit" "$FAKE_PATH/omedora/bin/tensaku-edit"

# --- the shim itself wraps satty (restores omarchy's pre-quattro editor) -----
grep -q 'exec satty --filename' "$ROOT/omedora/bin/tensaku-edit" \
  && pass "tensaku-edit shim execs satty --filename" \
  || fail "tensaku-edit shim execs satty --filename"
grep -q 'save-to-clipboard' "$ROOT/omedora/bin/tensaku-edit" \
  && pass "tensaku-edit shim preserves omarchy's save-to-clipboard satty flags" \
  || fail "tensaku-edit shim preserves omarchy's save-to-clipboard satty flags"

# --- no real tensaku-edit -> shim installed to ~/.local/bin ------------------
H1="$TMP/home1"; mkdir -p "$H1"
( export HOME="$H1" OMARCHY_PATH="$FAKE_PATH" OMEDORA_REAL_TENSAKU="$TMP/nope"; source "$SCRIPT" )
if [[ -x "$H1/.local/bin/tensaku-edit" ]]; then
  pass "shim installed to ~/.local/bin/tensaku-edit when no real tensaku present"
else
  fail "shim installed to ~/.local/bin/tensaku-edit when no real tensaku present"
fi
grep -q 'exec satty' "$H1/.local/bin/tensaku-edit" \
  && pass "installed file is the omedora satty wrapper" \
  || fail "installed file is the omedora satty wrapper"

# --- idempotent re-run -------------------------------------------------------
( export HOME="$H1" OMARCHY_PATH="$FAKE_PATH" OMEDORA_REAL_TENSAKU="$TMP/nope"; source "$SCRIPT" )
pass "re-run is idempotent (no error)"

# --- a genuine tensaku-edit present -> do NOT shadow it ----------------------
H3="$TMP/home3"; mkdir -p "$H3"
REAL="$TMP/real-tensaku"; printf '#!/bin/bash\n' >"$REAL"; chmod +x "$REAL"
( export HOME="$H3" OMARCHY_PATH="$FAKE_PATH" OMEDORA_REAL_TENSAKU="$REAL"; source "$SCRIPT" )
[[ ! -e "$H3/.local/bin/tensaku-edit" ]] \
  && pass "a genuine tensaku-edit is not shadowed (shim skipped)" \
  || fail "a genuine tensaku-edit is not shadowed (shim skipped)"

# --- missing shim source -> graceful no-op -----------------------------------
H2="$TMP/home2"; mkdir -p "$H2"
EMPTY="$TMP/empty-omarchy"; mkdir -p "$EMPTY"
( export HOME="$H2" OMARCHY_PATH="$EMPTY" OMEDORA_REAL_TENSAKU="$TMP/nope"; source "$SCRIPT" )
[[ ! -e "$H2/.local/bin/tensaku-edit" ]] \
  && pass "missing shim source is a graceful no-op (nothing written)" \
  || fail "missing shim source is a graceful no-op (nothing written)"

# --- finalize-user wiring: the Fedora block sources the shim step ------------
grep -q 'tensaku-edit-shim-fedora.sh' "$ROOT/bin/omarchy-finalize-user" \
  && pass "finalize-user sources the tensaku-edit shim step on Fedora" \
  || fail "finalize-user sources the tensaku-edit shim step on Fedora"

# --- the omedora RPM spec ships the shim binary under the payload ------------
grep -q 'omedora/bin/tensaku-edit' "$ROOT/omedora/packaging/copr/omedora.spec" \
  && pass "omedora.spec ships the tensaku-edit shim under the payload" \
  || fail "omedora.spec ships the tensaku-edit shim under the payload"

# --- the new quattro base apps are all mapped so install can't wedge ---------
for p in tensaku omacut omawrite; do
  grep -q "^\[$p\]" "$ROOT/install/packages/fedora.toml" \
    && pass "fedora.toml maps [$p] (quattro base package)" \
    || fail "fedora.toml maps [$p] (quattro base package)"
done

# tensaku is now packaged natively (dnf from the COPR), providing the real
# /usr/bin/tensaku-edit that self-deactivates the satty shim above. omacut (a
# video-trim tool) and omawrite (a writing app) are out of scope for the
# screenshot flow and stay skip-mapped.
awk '/^\[tensaku\]/{f=1;next} /^\[/{f=0} f' "$ROOT/install/packages/fedora.toml" \
  | grep -qE '^source = "dnf"' \
  && pass "fedora.toml maps [tensaku] to source=dnf (native COPR package)" \
  || fail "fedora.toml maps [tensaku] to source=dnf (native COPR package)"

echo "# all tensaku-edit-shim tests passed"
