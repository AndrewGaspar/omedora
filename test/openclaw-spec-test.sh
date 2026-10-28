#!/bin/bash
#
# L1 static guard for omedora/packaging/copr/openclaw.spec (+ .sources).
#
# Since Omarchy 4.0.6 the openclaw package is the SEED for a self-updating
# OpenClaw under ~/.openclaw, not OpenClaw itself: omarchy-install-openclaw-cli,
# omarchy-install-ai-openclaw and migration 1792334754 read the npm release
# tarball, upstream's install-cli.sh and the Control UI icon from fixed paths
# under /usr/share/openclaw. The spec reproduces the Arch package's layout file
# for file so those upstream scripts run unchanged on Fedora. This guard keeps
# the spec's payload on exactly the paths the scripts read, keeps anything off
# PATH (the runtime's link must be the only openclaw a session finds, or
# omarchy-install-openclaw-cli refuses), keeps the build an offline copy of the
# pinned tarball, and keeps the package wired in as on-demand. Pure bash + grep;
# no build.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SPEC="$ROOT/omedora/packaging/copr/openclaw.spec"
SOURCES="$ROOT/omedora/packaging/copr/openclaw.spec.sources"

assert_file_exists "openclaw.spec exists" "$SPEC"
assert_file_exists "openclaw.spec.sources exists" "$SOURCES"

ver="$(grep -E '^Version:' "$SPEC" | head -1 | awk '{print $2}')"
rel="$(grep -E '^Release:' "$SPEC" | head -1 | awk '{print $2}')"
[[ -n $ver ]] || fail "spec declares Version:"
assert_equals "Release is 1%{?dist}" "$rel" '1%{?dist}'
top="$(sed -n '/^%changelog/{n;p;q}' "$SPEC")"
assert_output_contains "top %changelog entry is ${ver}-1" "$top" "- ${ver}-1"

# --- Source0 is the npm release tarball, sha-pinned -------------------------
src0="$(grep -E '^Source0:' "$SPEC" | head -1 | awk '{print $2}')"
assert_equals "Source0 is the npm registry release tarball" "$src0" \
  'https://registry.npmjs.org/%{name}/-/%{name}-%{version}.tgz'
pinned="$(awk '{print $2}' "$SOURCES")"
assert_equals ".sources pins openclaw-${ver}.tgz and nothing else" "$pinned" "openclaw-${ver}.tgz"
if grep -qE '^[0-9a-f]{64}  openclaw-' "$SOURCES"; then
  pass ".sources carries a sha256 pin"
else
  fail ".sources line is not '<sha256>  <file>'"
fi

# --- offline copy: noarch, no npm/node at build time -------------------------
grep -qE '^BuildArch:\s+noarch' "$SPEC" && pass "BuildArch noarch" || fail "BuildArch noarch"
if sed -n '/^%prep/,/^%files/p' "$SPEC" | grep -vE '^\s*#' | grep -qE '\b(npm|npx|node|pnpm|curl|wget)\b'; then
  fail "build sections stay offline (no npm/node/curl in %prep..%check)"
else
  pass "build sections stay offline (no npm/node/curl in %prep..%check)"
fi
grep -qF 'install-cli.sh --help' "$SPEC" && pass "%check loads the shipped installer" \
  || fail "%check loads the shipped installer"

# --- the seed sits exactly where Omarchy's scripts read it -------------------
seed_dir=/usr/share/openclaw
assert_output_contains "omarchy-install-openclaw-cli reads the seed from $seed_dir" \
  "$(cat "$ROOT/bin/omarchy-install-openclaw-cli")" "seed=$seed_dir"
for f in install-cli.sh openclaw.tgz; do
  assert_output_contains "omarchy-install-openclaw-cli uses \$seed/$f" \
    "$(cat "$ROOT/bin/omarchy-install-openclaw-cli")" "\$seed/$f"
  assert_output_contains "migration 1792334754 gates on $seed_dir/$f" \
    "$(cat "$ROOT/migrations/1792334754.sh")" "$seed_dir/$f"
done
assert_output_contains "omarchy-install-ai-openclaw takes the icon from $seed_dir/openclaw.png" \
  "$(cat "$ROOT/bin/omarchy-install-ai-openclaw")" "$seed_dir/openclaw.png"

files="$(sed -n '/^%files/,/^%changelog/p' "$SPEC")"
for path in '%{_datadir}/%{name}/%{name}.tgz' '%{_datadir}/%{name}/install-*.sh' '%{_datadir}/%{name}/%{name}.png'; do
  assert_output_contains "%files owns $path" "$files" "$path"
done
grep -qE "^Name:\s+openclaw$" "$SPEC" && pass "Name is openclaw (%{_datadir}/%{name} = $seed_dir)" \
  || fail "Name is openclaw"

# Nothing on PATH: the runtime's ~/.local/bin link must be the only openclaw.
assert_output_lacks "%files puts nothing in %{_bindir}" "$files" '%{_bindir}'
assert_output_lacks "%files puts nothing in /usr/bin" "$files" '/usr/bin'
assert_output_lacks "%files ships no /usr/lib/node_modules copy" "$files" 'node_modules'

# --- the installer's hard runtime needs (pkg.py installs weak deps off) -------
for dep in bash curl git-core tar gzip coreutils; do
  grep -qE "^Requires:\s+$dep\s*$" "$SPEC" && pass "Requires $dep" || fail "Requires $dep"
done

# --- wiring: map entry, served set, on-demand --------------------------------
entry="$(sed -n '/^\[openclaw\]/,/^\[/p' "$ROOT/install/packages/fedora.toml")"
assert_output_contains "fedora.toml maps openclaw via dnf" "$entry" 'source = "dnf"'
assert_output_contains "fedora.toml maps openclaw to the openclaw RPM" "$entry" 'names = ["openclaw"]'
grep -qE '^\s+openclaw\.spec\s*$' "$ROOT/omedora/packaging/copr/build-repo.sh" \
  && pass "build-repo.sh SPECS builds openclaw.spec" || fail "build-repo.sh SPECS builds openclaw.spec"
on_demand="$(grep -E '^on_demand_specs=' "$ROOT/test/upgrade-to-4-test.sh")"
assert_output_contains "openclaw is an on-demand spec for the upgrader cross-check" "$on_demand" ' openclaw '
kept="$(sed -n '/^v4_kept_packages=(/,/^)/p' "$ROOT/bin/omedora-upgrade-to-4")"
if grep -qw openclaw <<<"$kept"; then
  fail "openclaw is not force-kept by omedora-upgrade-to-4 (on-demand)"
else
  pass "openclaw is not force-kept by omedora-upgrade-to-4 (on-demand)"
fi
if grep -qxF openclaw "$ROOT/install/omarchy-base.packages"; then
  fail "openclaw is not a base package"
else
  pass "openclaw is not a base package"
fi
