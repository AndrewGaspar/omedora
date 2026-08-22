#!/bin/bash
# L1 (hypedora): branch-ul hypedora e ADITIV față de upstream/omedora-4 —
# singurele fișiere modificate/șterse în afara hypedora/ și test/hypedora-* sunt
# cele listate explicit în hypedora/upstream-patches.txt (PR-uri upstream în curs).
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

ALLOW="$ROOT/hypedora/upstream-patches.txt"
[[ -f "$ALLOW" ]] || fail "hypedora/upstream-patches.txt există"
pass "hypedora/upstream-patches.txt există"

BASE="${HYPEDORA_BASE_REF:-upstream/omedora-4}"
git -C "$ROOT" rev-parse -q --verify "$BASE" >/dev/null || fail "ref de bază $BASE există (git fetch upstream)"
pass "ref de bază $BASE există"

# Fișiere modificate/șterse (nu adăugate) față de bază, în afara zonelor noastre.
mapfile -t changed < <(git -C "$ROOT" diff --name-only --diff-filter=MDRT "$BASE" -- . \
  ':(exclude)hypedora/' ':(exclude)test/hypedora-*' )
bad=()
for f in "${changed[@]}"; do
  grep -qxF -- "$f" <(grep -v '^\s*#' "$ALLOW" | sed '/^\s*$/d') || bad+=("$f")
done
if (( ${#bad[@]} )); then
  printf 'fișiere upstream modificate fără a fi în upstream-patches.txt:\n' >&2
  printf '  %s\n' "${bad[@]}" >&2
  fail "toate modificările upstream sunt în allowlist"
fi
pass "toate modificările upstream sunt în allowlist (${#changed[@]} fișiere, toate listate)"
