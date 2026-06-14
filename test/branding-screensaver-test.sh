#!/bin/bash
#
# L1 guard: omedora-settings.spec must seed the screensaver + the show-logo
# wordmark from Omedora's wordmark, not upstream Omarchy's.
#
# logo.txt is the wide WORDMARK rendered by omarchy-show-logo, the screensaver
# (bin/omarchy-screensaver -> ~/.config/omarchy/branding/screensaver.txt), and
# `omarchy branding screensaver reset` (cp $OMARCHY_PATH/logo.txt). It's a
# user-facing surface omedora rebrands (omedora/branding.md). The v4 port of
# 3.8.2's install/config/branding.sh lives in this spec, so two install lines
# must point at omedora/branding/logo.txt:
#   1. /usr/share/omarchy/logo.txt              (show-logo + branding reset)
#   2. /etc/skel/.config/omarchy/branding/screensaver.txt  (new-user seed)
# A rebase that re-grows the upstream `install ... logo.txt %{buildroot}.../`
# line (top-level Omarchy art) would silently restore Omarchy branding — this
# test fails loudly if either destination stops coming from the Omedora wordmark.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SPEC="$ROOT/omedora/packaging/copr/omedora-settings.spec"
WORDMARK="$ROOT/omedora/branding/logo.txt"

[[ -f $SPEC ]] || fail "spec exists: $SPEC"
[[ -f $WORDMARK ]] || fail "omedora wordmark exists: $WORDMARK"

# The Omedora wordmark file must not be the upstream art (sanity: they differ).
if cmp -s "$WORDMARK" "$ROOT/logo.txt"; then
  fail "omedora/branding/logo.txt must differ from upstream logo.txt"
fi
pass "omedora/branding/logo.txt is a distinct Omedora wordmark"

# 1. /usr/share/omarchy/logo.txt is installed from the Omedora wordmark.
if grep -Eq '^[[:space:]]*install .*omedora/branding/logo\.txt .*%\{(buildroot|_datadir)\}.*omarchy/logo\.txt' "$SPEC"; then
  pass "spec installs /usr/share/omarchy/logo.txt from omedora/branding/logo.txt"
else
  grep -nE 'omarchy/logo\.txt' "$SPEC" >&2 || true
  fail "spec must install %{_datadir}/omarchy/logo.txt from omedora/branding/logo.txt"
fi

# 2. screensaver.txt skel seed comes from the Omedora wordmark.
if grep -Eq '^[[:space:]]*install .*omedora/branding/logo\.txt .*branding/screensaver\.txt' "$SPEC"; then
  pass "spec seeds skel screensaver.txt from omedora/branding/logo.txt"
else
  grep -nE 'branding/screensaver\.txt' "$SPEC" >&2 || true
  fail "spec must seed /etc/skel/.config/omarchy/branding/screensaver.txt from omedora/branding/logo.txt"
fi

# 3. No install line copies the upstream top-level logo.txt into the buildroot
#    (that would restore Omarchy art at either destination). Allowlisted: lines
#    that name omedora/branding/logo.txt as the source.
if grep -E '^[[:space:]]*install ' "$SPEC" | grep -E ' logo\.txt ' | grep -vq 'omedora/branding/logo\.txt'; then
  grep -nE '^[[:space:]]*install .* logo\.txt ' "$SPEC" | grep -v 'omedora/branding' >&2
  fail "spec must not install the upstream top-level logo.txt into the buildroot"
fi
pass "spec installs no upstream-art logo.txt into the buildroot"

echo "# all branding-screensaver checks passed"
