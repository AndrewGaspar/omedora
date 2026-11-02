#!/bin/bash
#
# L1 static guard for omedora/packaging/copr/xreal-ctl.spec (+ .sources).
#
# xreal-ctl is the XREAL Air 2D/3D HID helper from HypXRland's contrib/xreal.
# The spec builds that one C file from the commit archive hypxrland.spec
# already pins, so the two specs must keep pinning the same commit and the
# same sha. This audits the spec text so a hypxrland bump cannot strand
# xreal-ctl on an older archive, and the helper cannot lose its device-access
# dependency or its usage-error %check. Pure bash + grep; no build.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

COPR="$ROOT/omedora/packaging/copr"
SPEC="$COPR/xreal-ctl.spec"
SOURCES="$COPR/xreal-ctl.spec.sources"
HYPXR="$COPR/hypxrland.spec"

assert_file_exists "xreal-ctl.spec exists" "$SPEC"
assert_file_exists "xreal-ctl.spec.sources exists" "$SOURCES"

# --- the pin is hypxrland's -----------------------------------------------------
macro() { sed -n "s/^%global $1 //p" "$2"; }
commit=$(macro commit "$SPEC")
[[ -n $commit && $commit == "$(macro commit "$HYPXR")" ]] \
  && pass "xreal-ctl pins hypxrland's commit" || fail "xreal-ctl pins hypxrland's commit"
[[ -n $(macro snapshot "$SPEC") && $(macro snapshot "$SPEC") == "$(macro snapshot "$HYPXR")" ]] \
  && pass "xreal-ctl uses hypxrland's snapshot" || fail "xreal-ctl uses hypxrland's snapshot"
grep -qE '^Version:[[:space:]]+0\^%\{snapshot\}\.git%\{shortcommit\}$' "$SPEC" \
  && pass "Version is a snapshot of the pinned commit" \
  || fail "Version is a snapshot of the pinned commit"
grep -qE '^URL:[[:space:]]+https://github\.com/AndrewGaspar/Hyprland$' "$SPEC" \
  && [[ $(sed -n 's/^URL:[[:space:]]*//p' "$SPEC") == "$(sed -n 's/^URL:[[:space:]]*//p' "$HYPXR")" ]] \
  && pass "URL is hypxrland's fork" || fail "URL is hypxrland's fork"
grep -qE '^Source0:[[:space:]]+%\{url\}/archive/%\{commit\}/hypxrland-%\{commit\}\.tar\.gz$' "$SPEC" \
  && pass "Source0 is hypxrland's archive file name" \
  || fail "Source0 is hypxrland's archive file name"
(( $(grep -cE '^Source[0-9]+:' "$SPEC") == 1 )) \
  && pass "Source0 is the only source" || fail "Source0 is the only source"
archive="hypxrland-$commit.tar.gz"
pin=$(awk -v f="$archive" '$2 == f' "$SOURCES")
[[ -n $pin && $(wc -l <"$SOURCES") -eq 1 && $pin == "$(awk -v f="$archive" '$2 == f' "$COPR/hypxrland.spec.sources")" ]] \
  && pass "the archive sha is hypxrland's" || fail "the archive sha is hypxrland's"
awk 'NF { if ($1 !~ /^[0-9a-f]{64}$/ || NF != 2) exit 1 }' "$SOURCES" \
  && pass ".sources has immutable SHA-256 pins" || fail ".sources has immutable SHA-256 pins"

# --- build only the helper --------------------------------------------------------
grep -qE '^BuildRequires:[[:space:]]+pkgconfig\(hidapi-hidraw\)$' "$SPEC" \
  && pass "builds against hidapi-hidraw" || fail "builds against hidapi-hidraw"
grep -qF 'Hyprland-%{commit}/LICENSE Hyprland-%{commit}/contrib/xreal' "$SPEC" \
  && pass "%prep unpacks only LICENSE and contrib/xreal" \
  || fail "%prep unpacks only LICENSE and contrib/xreal"
grep -qF '%make_build -C contrib/xreal' "$SPEC" \
  && pass "builds with the fork's contrib/xreal Makefile" \
  || fail "builds with the fork's contrib/xreal Makefile"
grep -qF '%{build_ldflags}' "$SPEC" \
  && pass "links with Fedora's hardening flags" || fail "links with Fedora's hardening flags"
grep -qF 'install -Dpm0755 contrib/xreal/xreal-ctl %{buildroot}%{_bindir}/xreal-ctl' "$SPEC" \
  && pass "installs /usr/bin/xreal-ctl" || fail "installs /usr/bin/xreal-ctl"

# --- device access + %check -----------------------------------------------------
# xr-hardware's 70-xrhardware.rules grants seat access to 3318:0424/0426/0428/0432.
grep -qE '^Requires:[[:space:]]+xr-hardware >= 1\.1\.2$' "$SPEC" \
  && pass "requires the xr-hardware uaccess rules" \
  || fail "requires the xr-hardware uaccess rules"
grep -qF "grep -qF 'Are the xr-hardware udev rules installed?'" "$SPEC" \
  && pass "%prep's hint rewrite is verified" || fail "%prep's hint rewrite is verified"
grep -qF "usage: xreal-ctl mode 2d|3d" "$SPEC" \
  && pass "%check covers the usage text" || fail "%check covers the usage text"
grep -qF '$ctl detect' "$SPEC" \
  && pass "%check covers detect without a device" || fail "%check covers detect without a device"
# rpm runs %check under `sh -e`, which never fails on a `! cmd` line.
if sed -n '/^%check/,/^%files/p' "$SPEC" | grep -qE '^[[:space:]]*! '; then
  fail "%check has no bare negated commands (they never fail the build)"
else
  pass "%check has no bare negated commands (they never fail the build)"
fi

# --- wiring -----------------------------------------------------------------------
grep -qE '^Release:[[:space:]]+[0-9]+%\{\?dist\}$' "$SPEC" \
  && pass "Release carries the dist tag" || fail "Release carries the dist tag"
order=$(sed -n '/^SPECS=(/,/^)/p' "$COPR/build-repo.sh" | sed 's/#.*//' | tr '\n' ' ')
[[ $order == *"xreal-ctl.spec"*"hypxrland-omedora.spec"* ]] \
  && pass "build-repo.sh builds xreal-ctl before hypxrland-omedora" \
  || fail "build-repo.sh builds xreal-ctl before hypxrland-omedora"
grep -qF '| `xreal-ctl` |' "$ROOT/omedora/packages.md" \
  && pass "packages.md documents xreal-ctl" || fail "packages.md documents xreal-ctl"

echo "# all xreal-ctl spec tests passed"
