#!/bin/bash
#
# L1 static guard for the specs Omedora added for Omarchy 4.5's omacom apps:
# omasnap and owe (base packages) plus hype, monologue, signed and disktree
# (removable preinstalls / the dua-cli replacement). Pure bash + grep; no build.
#
# For every spec:
#   - spec + .sources exist, and .sources pins exactly Source0's basename
#   - Release is 1%{?dist}, ExclusiveArch x86_64, the top %changelog entry
#     matches Version-Release
#   - %files owns the binary install/packages/fedora.toml and Omarchy invoke
#   - the Arch name maps to the package in fedora.toml as a dnf source
#   - build-repo.sh builds it, and omedora-upgrade-to-4 keeps it
# Plus the per-package runtime contract Omarchy relies on.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

COPR="$ROOT/omedora/packaging/copr"
MAP="$ROOT/install/packages/fedora.toml"

# spec : binary : Arch package name
apps=(
  "omasnap:omasnap:omasnap"
  "owe:owed:owe"
  "hype:hype:hype"
  "monologue:monologue:monologue"
  "signed:signed:signed"
  "disktree:disktree:disktree-bin"
)

kept=$(sed -n '/^v4_kept_packages=(/,/^)/p' "$ROOT/bin/omedora-upgrade-to-4")
specs=$(sed -n '/^SPECS=(/,/^)/p' "$COPR/build-repo.sh" | sed 's/#.*//')

for entry in "${apps[@]}"; do
  IFS=: read -r spec bin arch <<<"$entry"
  file="$COPR/$spec.spec"
  sources="$COPR/$spec.spec.sources"
  assert_file_exists "$spec.spec exists" "$file"
  assert_file_exists "$spec.spec.sources exists" "$sources"

  name=$(awk '/^Name:/ {print $2; exit}' "$file")
  ver=$(awk '/^Version:/ {print $2; exit}' "$file")
  rel=$(awk '/^Release:/ {print $2; exit}' "$file")
  assert_equals "$spec: Name matches the spec file" "$name" "$spec"
  assert_equals "$spec: Release is 1%{?dist}" "$rel" '1%{?dist}'
  grep -qE '^ExclusiveArch:[[:space:]]+x86_64\b' "$file" \
    && pass "$spec: ExclusiveArch x86_64" || fail "$spec: ExclusiveArch x86_64"

  src0=$(awk '/^Source0:/ {print $2; exit}' "$file")
  src0=${src0//%\{version\}/$ver}
  src0=${src0//%\{name\}/$name}
  pinned=$(awk 'NF && $1 !~ /^#/ {print $2; exit}' "$sources")
  assert_equals "$spec: .sources pins Source0's basename" "$pinned" "$(basename "$src0")"
  sha=$(awk 'NF && $1 !~ /^#/ {print $1; exit}' "$sources")
  [[ $sha =~ ^[0-9a-f]{64}$ ]] && pass "$spec: .sources holds a sha256" \
    || fail "$spec: .sources holds a sha256"

  top=$(sed -n '/^%changelog/{n;p;q}' "$file")
  assert_output_contains "$spec: top %changelog entry is $ver-1" "$top" "- $ver-1"

  grep -qE "^%\\{_bindir\\}/$bin[[:space:]]*\$" "$file" \
    && pass "$spec: %files owns /usr/bin/$bin" || fail "$spec: %files owns /usr/bin/$bin"

  block=$(awk -v key="[$arch]" '$0 == key {on=1; next} /^\[/ {on=0} on' "$MAP")
  grep -qx 'source = "dnf"' <<<"$block" && grep -qF "\"$name\"" <<<"$block" \
    && pass "fedora.toml maps $arch to the $name RPM" \
    || fail "fedora.toml maps $arch to the $name RPM"

  grep -qw "$spec.spec" <<<"$specs" \
    && pass "build-repo.sh builds $spec.spec" || fail "build-repo.sh builds $spec.spec"
  grep -qw "$name" <<<"$kept" \
    && pass "omedora-upgrade-to-4 keeps $name" || fail "omedora-upgrade-to-4 keeps $name"
done

# --- per-package runtime contracts --------------------------------------------
grep -qE '^Requires:[[:space:]]+tesseract-langpack-eng\b' "$COPR/omasnap.spec" \
  && pass "omasnap: Requires the English OCR data" || fail "omasnap: Requires the English OCR data"
grep -qE '^%\{_datadir\}/owe/10-owe-sync$' "$COPR/owe.spec" \
  && pass "owe: ships the theme-set hook at the path first-run installs" \
  || fail "owe: ships the theme-set hook at the path first-run installs"
grep -qE '^%\{_userunitdir\}/owed\.service$' "$COPR/owe.spec" \
  && pass "owe: ships owed.service for first-run to enable" \
  || fail "owe: ships owed.service for first-run to enable"
for spec in hype monologue; do
  grep -qE '^Requires:[[:space:]]+/usr/bin/ffmpeg\b' "$COPR/$spec.spec" \
    && pass "$spec: Requires ffmpeg by path" || fail "$spec: Requires ffmpeg by path"
done

echo "# all omarchy45-apps-spec tests passed"
