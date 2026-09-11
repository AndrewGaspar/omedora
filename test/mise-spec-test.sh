#!/bin/bash
#
# L1 static guard for omedora/packaging/copr/mise.spec (+ .sources).
#
# mise is Omedora's binary-repackage of the upstream linux-x64 release tarball
# (Arch Omarchy ships the same release as mise-bin). Upstream Omarchy's
# install/user/mise.sh and migrations/1787215483.sh both run
# `mise settings set upgrade.auto_prune false`; that setting exists from mise
# 2026.8.10, and an older mise rejects it as an unknown setting, which aborts
# fresh installs and every `omedora update` on Fedora. This guard keeps the
# packaged version at or above that floor and keeps the source pin in sync with
# the spec. Pure bash + grep; no build.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SPEC="$ROOT/omedora/packaging/copr/mise.spec"
SOURCES="$ROOT/omedora/packaging/copr/mise.spec.sources"
MIN_VERSION="2026.8.10"

assert_file_exists "mise.spec exists" "$SPEC"
assert_file_exists "mise.spec.sources exists" "$SOURCES"

ver="$(grep -E '^Version:' "$SPEC" | head -1 | awk '{print $2}')"
rel="$(grep -E '^Release:' "$SPEC" | head -1 | awk '{print $2}')"
[[ -n $ver ]] || fail "spec declares Version:"
assert_equals "Release is 1%{?dist}" "$rel" '1%{?dist}'

# --- version floor: the setting install/user/mise.sh and the migration write ---
if [[ "$(printf '%s\n%s\n' "$MIN_VERSION" "$ver" | sort -V | head -1)" == "$MIN_VERSION" ]]; then
  pass "Version $ver >= $MIN_VERSION (upgrade.auto_prune is a known setting)"
else
  fail "Version $ver is older than $MIN_VERSION: 'mise settings set upgrade.auto_prune' would abort the install"
fi

# The floor exists because these two upstream files use the setting; if they
# stop, the floor can be revisited (the guard says so rather than rotting).
for f in install/user/mise.sh migrations/1787215483.sh; do
  if grep -q 'upgrade.auto_prune' "$ROOT/$f"; then
    pass "$f still sets upgrade.auto_prune (floor is load-bearing)"
  else
    fail "$f no longer sets upgrade.auto_prune; revisit MIN_VERSION in this test"
  fi
done

# --- %changelog top entry matches Version-Release ----------------------------
top="$(sed -n '/^%changelog/{n;p;q}' "$SPEC")"
assert_output_contains "top %changelog entry is ${ver}-1" "$top" "- ${ver}-1"

# --- Source0 is the upstream linux-x64 release tarball -----------------------
src0="$(grep -E '^Source0:' "$SPEC" | head -1 | awk '{print $2}')"
assert_equals "Source0 is the versioned linux-x64 release tarball" "$src0" \
  '%{url}/releases/download/v%{version}/mise-v%{version}-linux-x64.tar.gz'

# --- .sources pins exactly that tarball for exactly this version -------------
pinned="$(awk '{print $2}' "$SOURCES")"
assert_equals ".sources pins mise-v${ver}-linux-x64.tar.gz and nothing else" "$pinned" "mise-v${ver}-linux-x64.tar.gz"
if grep -qE '^[0-9a-f]{64}  ' "$SOURCES"; then
  pass ".sources carries a sha256 pin"
else
  fail ".sources line is not '<sha256>  <file>'"
fi

# --- payload: the binary, man page and fish activation snippet ---------------
for path in '%{_bindir}/mise' '%{_mandir}/man1/mise.1*' '%{_datadir}/fish/vendor_conf.d/mise-activate.fish'; do
  if grep -qF "$path" "$SPEC"; then
    pass "%files owns $path"
  else
    fail "%files owns $path"
  fi
done
grep -qE '^ExclusiveArch:\s+x86_64' "$SPEC" && pass "ExclusiveArch x86_64" || fail "ExclusiveArch x86_64"
