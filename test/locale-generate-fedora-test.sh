#!/bin/bash
#
# L1: omarchy-locale-generate on Fedora installs the glibc langpack for a
# registry language instead of running Arch's locale-gen, validates the code
# exactly like the Arch helper, and does nothing when the locale exists.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
SHIM="$SCRATCH/shim"
mkdir -p "$SHIM"
MOCK_LOG="$SCRATCH/mock.log"
export MOCK_LOG

stub() { printf '#!/bin/bash\n%s\n' "$2" >"$SHIM/$1"; chmod +x "$SHIM/$1"; }
stub sudo 'printf "sudo %s\n" "$*" >>"$MOCK_LOG"'
stub locale-gen 'printf "locale-gen %s\n" "$*" >>"$MOCK_LOG"'
stub locale 'printf "C\nC.utf8\nen_US.utf8\nPOSIX\n"'

run() {
  : >"$MOCK_LOG"
  OMARCHY_DISTRO=fedora OMARCHY_LOCALE_REGISTRY="$ROOT/default/i18n/locales.json" \
    PATH="$SHIM:$ROOT/bin:/usr/bin:/bin" bash "$ROOT/bin/omarchy-locale-generate" "$@" \
    >"$SCRATCH/out" 2>&1
}

run de && rc=0 || rc=$?
assert_equals "German exits 0" "0" "$rc"
grep -qx 'sudo dnf install -y glibc-langpack-de' "$MOCK_LOG" \
  && pass "German installs glibc-langpack-de" \
  || { cat "$MOCK_LOG" >&2; fail "German installs glibc-langpack-de"; }
grep -q 'locale-gen' "$MOCK_LOG" \
  && fail "Fedora never runs locale-gen" || pass "Fedora never runs locale-gen"

run no >/dev/null && rc=0 || rc=$?
grep -qx 'sudo dnf install -y glibc-langpack-nb' "$MOCK_LOG" \
  && pass "Norwegian installs the nb langpack the registry locale names" \
  || { cat "$MOCK_LOG" >&2; fail "Norwegian installs the nb langpack the registry locale names"; }

run en && rc=0 || rc=$?
assert_equals "an available locale exits 0" "0" "$rc"
[[ ! -s $MOCK_LOG ]] && pass "an available locale installs nothing" \
  || { cat "$MOCK_LOG" >&2; fail "an available locale installs nothing"; }

for bad in xx 'de;rm' '' 'de de'; do
  # shellcheck disable=SC2086
  run $bad && rc=0 || rc=$?
  [[ $rc != 0 && ! -s $MOCK_LOG ]] && pass "rejects '$bad' without installing" \
    || { cat "$MOCK_LOG" >&2; fail "rejects '$bad' without installing"; }
done

echo "# all locale-generate-fedora tests passed"
