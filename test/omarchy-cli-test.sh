#!/bin/bash

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
CLI="$ROOT/bin/omarchy"
TMPDIR=""

export PATH="$ROOT/bin:$PATH"

# Shared TAP helpers (pass, fail, assert_output_contains, etc.)
. "$ROOT/test/helpers.sh"

cleanup() {
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
}
trap cleanup EXIT

# Default (no brand override): dispatcher renders as Omarchy.
# Explicitly unset OMARCHY_BRAND so the test is hermetic across CI environments.
unset OMARCHY_BRAND

output=$("$CLI" --help)
assert_output_contains "main help renders" "$output" "Omarchy command center"
assert_output_contains "main help includes hardware group" "$output" "hw"
assert_output_contains "main help includes package group" "$output" "pkg"
if grep -Eq '^  [a-z0-9-]+[[:space:]].*\([0-9]+\)$' <<<"$output"; then
  fail "main help does not show group counts"
fi
pass "main help does not show group counts"

output=$("$CLI" commands)
assert_output_contains "commands lists documented commands" "$output" "omarchy theme set <theme-name>"

"$CLI" commands --json | jq -e '.ok == true and (.commands | length >= 200)' >/dev/null
pass "commands --json is valid JSON with full bin coverage"

"$CLI" commands --json | jq -e 'all(.commands[]; .summary != "undocumented")' >/dev/null
pass "all included commands have summaries"

"$CLI" commands --json | jq -e 'all(.commands[]; has("binary") and has("filename_route") and has("routes") and (has("legacy") | not) and (has("usage") | not) and (has("visibility") | not) and (has("mutates") | not) and (has("interactive") | not))' >/dev/null
pass "JSON uses binary/routes and omits legacy/usage/extra metadata"

"$CLI" commands --check >/dev/null
pass "commands --check passes"

"$CLI" commands --all >/dev/null
pass "commands --all does not crash"

"$CLI" commands --all --json | jq -e '.commands[] | select(.route == "omarchy hyprland window gaps toggle" and .summary != "undocumented")' >/dev/null
pass "fallback commands are inferred and documented"

"$CLI" commands --all --json | jq -e '.commands[] | select(.route == "omarchy dev benchmark")' >/dev/null
pass "benchmark command is discoverable in all commands"

"$CLI" commands --json | jq -e '.commands[] | select(.binary == "omarchy-pkg-add" and .route == "omarchy pkg add" and .filename_route == "omarchy pkg add" and (.routes | index("omarchy pkg add")))' >/dev/null
pass "JSON exposes direct pkg add route"

"$CLI" commands --json | jq -e '.commands[] | select(.binary == "omarchy-refresh-pacman" and .requires_sudo == true)' >/dev/null
pass "sudo metadata marks sudo commands"

output=$("$CLI" theme --help)
assert_output_contains "group help renders" "$output" "Theme commands"

output=$("$CLI" install --help)
assert_output_contains "install group help renders" "$output" "Install commands"
assert_output_contains "install group includes browser route" "$output" "omarchy install browser"

output=$("$CLI" install)
assert_output_contains "bare group renders help instead of picker" "$output" "Install commands"
assert_output_contains "bare group includes browser route" "$output" "omarchy install browser"

output=$("$CLI" toggle)
assert_output_contains "bare root command with children renders help" "$output" "Toggle commands"
assert_output_contains "bare toggle help includes child route" "$output" "omarchy toggle waybar"

output=$("$CLI" pkg --help)
assert_output_contains "package group includes pkg add fallback route" "$output" "omarchy pkg add <packages...>"

output=$("$CLI" restart --help)
assert_output_contains "restart group includes inferred commands" "$output" "omarchy restart btop"
assert_output_contains "restart group includes all restart commands" "$output" "omarchy restart wifi"

output=$("$CLI" hw --help)
assert_output_contains "hardware group help renders" "$output" "omarchy hw asus rog"
assert_output_contains "hardware group includes touchpad" "$output" "omarchy hw touchpad"

output=$("$CLI" hw asus)
assert_output_contains "partial hardware prefix renders matching commands" "$output" "omarchy hw asus rog"
assert_output_contains "partial hardware prefix includes nested match" "$output" "omarchy hw asus zenbook ux5406aa"

output=$("$CLI" menu --help)
assert_output_contains "menu group includes share fallback route" "$output" "omarchy menu share"

output=$("$CLI" share)
assert_output_contains "bare required-arg alias renders CLI help" "$output" "Usage:"
assert_output_contains "bare share help uses canonical route" "$output" "omarchy share <clipboard|file|folder> [path...]"

output=$("$CLI" menu share)
assert_output_contains "bare required-arg filename route renders CLI help" "$output" "omarchy share <clipboard|file|folder> [path...]"

output=$("$CLI" branch set)
assert_output_contains "bare required-choice route renders CLI help" "$output" "omarchy branch set <master|rc|dev>"

CLI="$CLI" python3 <<'PY'
import json
import os
import subprocess
import sys

cli = os.environ['CLI']
commands = json.loads(subprocess.check_output([cli, 'commands', '--json'], text=True))['commands']
by_group = {}
for command in commands:
  binary = command['binary']
  stem = binary.removeprefix('omarchy-')
  group = stem.split('-', 1)[0]
  filename_route = 'omarchy ' + stem.replace('-', ' ')
  by_group.setdefault(group, []).append((binary, filename_route, command['route']))

missing = []
for group, rows in sorted(by_group.items()):
  proc = subprocess.run([cli, group, '--help'], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
  output = proc.stdout + proc.stderr
  if proc.returncode != 0:
    missing.append((group, '<group-help-failed>', f'exit {proc.returncode}'))
    continue
  for binary, filename_route, canonical_route in rows:
    if filename_route not in output and canonical_route not in output and binary not in output:
      missing.append((group, binary, filename_route))

if missing:
  for row in missing:
    print('\t'.join(row), file=sys.stderr)
  sys.exit(1)
PY
pass "every filename-derived group help represents its bins"

output=$(timeout 5 "$CLI" theme set --help)
assert_output_contains "command help renders without executing" "$output" "Binary:"
assert_output_contains "theme set help names binary" "$output" "omarchy-theme-set"

output=$(timeout 5 "$CLI" update --help)
assert_output_contains "mutating command help does not execute target" "$output" "omarchy-update"
assert_output_contains "root command help shows related child commands" "$output" "omarchy update perform"

output=$("$CLI" screenshot --help)
assert_output_contains "root alias resolves to command help" "$output" "omarchy-capture-screenshot"

"$CLI" commands --json | jq -e '.commands[] | select(.binary == "omarchy-capture-screenshot") | .aliases | index("omarchy screenshot")' >/dev/null
pass "aliases are included in JSON metadata"

output=$("$CLI" pkg add --help)
assert_output_contains "pkg add help resolves" "$output" "omarchy-pkg-add"
assert_output_contains "pkg add help shows direct route" "$output" "omarchy pkg add <packages...>"

output=$("$CLI" system reboot --help)
assert_output_contains "system command help is safe" "$output" "omarchy-system-reboot"

output=$("$CLI" dev benchmark --repeat=1)
assert_output_contains "benchmark command runs" "$output" "Omarchy CLI benchmark"

"$CLI" theme list >/dev/null
pass "safe dispatch works for theme list"

"$CLI" theme current >/dev/null
pass "safe dispatch works for theme current"

"$CLI" font list >/dev/null
pass "safe dispatch works for font list"

"$CLI" font current >/dev/null
pass "safe dispatch works for font current"

for binary in \
  omarchy-update \
  omarchy-theme-set \
  omarchy-capture-screenshot \
  omarchy-system-reboot \
  omarchy-pkg-add; do
  [[ -x $ROOT/bin/$binary ]] || fail "binary is executable: $binary"
  pass "binary is executable: $binary"
done

while IFS= read -r binary_path; do
  header=$(awk '
    NR == 1 && /^#!/ { next }
    /^[[:space:]]*$/ { if (seen) print; next }
    /^[[:space:]]*#/ { seen=1; print; next }
    { exit }
  ' "$binary_path")

  grep -q '^# omarchy:summary=' <<<"$header" || fail "metadata summary is present: $binary_path"
  ! grep -q '^# omarchy:binary=' <<<"$header" || fail "metadata does not repeat inferred binary: $binary_path"
  ! grep -q '^# omarchy:args=$' <<<"$header" || fail "metadata does not include empty args: $binary_path"
  ! grep -Eq '^# omarchy:(legacy|usage|visibility|mutates|interactive)=' <<<"$header" || fail "metadata avoids removed fields: $binary_path"
  ! grep -Eq '^# omarchy:requires-sudo=false$' <<<"$header" || fail "metadata omits false booleans: $binary_path"
done < <(find "$ROOT/bin" -maxdepth 1 -type f -executable -name 'omarchy-*' | sort)
pass "all executable bins have slim self-documenting metadata"

TMPDIR=$(mktemp -d)
ln -s "$CLI" "$TMPDIR/omarchy"

{
  printf '#!/bin/bash\n\n'
  printf '# ordinary comments are fine\n'
  printf '# omarchy:this malformed line should be ignored\n'
  printf '# omarchy:group=weird\n'
  printf '# omarchy:name=test\n'
  printf '# omarchy:summary=Survives malformed metadata comments\n'
  printf '# omarchy:made-up=value\n'
  printf 'echo weird-ok\n'
} >"$TMPDIR/omarchy-weird-test"
chmod +x "$TMPDIR/omarchy-weird-test"

{
  printf '#!/bin/bash\n\n'
  printf '# a partial metadata header should not destroy fallback routing\n'
  printf '# omarchy:summary=Partial metadata keeps inferred route\n'
  printf '# omarchy:made-up=value\n'
  printf 'echo partial-ok\n'
} >"$TMPDIR/omarchy-partial-meta-test"
chmod +x "$TMPDIR/omarchy-partial-meta-test"

{
  printf '#!/bin/bash\n\n'
  printf 'echo body-metadata-ok\n'
  printf '# omarchy:group=wrong\n'
  printf '# omarchy:name=wrong\n'
} >"$TMPDIR/omarchy-body-metadata-test"
chmod +x "$TMPDIR/omarchy-body-metadata-test"

"$TMPDIR/omarchy" commands --all --json | jq -e '.commands[] | select(.route == "omarchy weird test" and .summary == "Survives malformed metadata comments")' >/dev/null
pass "unknown metadata values are non-fatal"

"$TMPDIR/omarchy" commands --all --json | jq -e '.commands[] | select(.route == "omarchy partial meta test" and .summary == "Partial metadata keeps inferred route")' >/dev/null
pass "partial metadata keeps inferred fallback route"

"$TMPDIR/omarchy" commands --all --json | jq -e '.commands[] | select(.route == "omarchy body metadata test" and .summary == "Run the body metadata test command")' >/dev/null
pass "metadata-looking comments after script body are ignored"

output=$("$TMPDIR/omarchy" weird test)
assert_output_contains "temporary metadata command dispatches" "$output" "weird-ok"

output=$("$TMPDIR/omarchy" partial meta test)
assert_output_contains "partial metadata command dispatches" "$output" "partial-ok"

output=$("$TMPDIR/omarchy" body metadata test)
assert_output_contains "body metadata command dispatches by filename" "$output" "body-metadata-ok"

# ============================================================================
# Brand-shim assertions (omedora) — see omedora/architecture.md §10.
# ============================================================================

# Default invocation as `omarchy` retains upstream branding (regression check).
output=$("$CLI" --help)
assert_output_contains "default brand renders Omarchy header" "$output" "Omarchy command center"
assert_output_lacks "default brand does NOT mention Omedora" "$output" "Omedora command center"
assert_output_contains "default brand example uses 'omarchy theme'" "$output" "omarchy theme list"
assert_output_lacks "default brand example does NOT use 'omedora theme'" "$output" "omedora theme list"

# OMARCHY_BRAND env override → Omedora branding everywhere.
output=$(OMARCHY_BRAND=omedora "$CLI" --help)
assert_output_contains "OMARCHY_BRAND=omedora renders Omedora header" "$output" "Omedora command center"
assert_output_contains "OMARCHY_BRAND=omedora example uses 'omedora theme'" "$output" "omedora theme list"
assert_output_lacks "OMARCHY_BRAND=omedora example does NOT use 'omarchy theme'" "$output" "omarchy theme list"

# bin/omedora symlink → invoked as `omedora` → Omedora branding via basename.
if [[ -L "$ROOT/bin/omedora" ]]; then
  link_target=$(readlink "$ROOT/bin/omedora")
  assert_equals "bin/omedora is a symlink to omarchy" "$link_target" "omarchy"

  output=$("$ROOT/bin/omedora" --help)
  assert_output_contains "invoked as omedora → Omedora header (via basename)" "$output" "Omedora command center"
fi

# Unknown command on omedora brand uses omedora in the error message.
unknown_output=$(OMARCHY_BRAND=omedora "$CLI" nonexistent-command 2>&1 || true)
assert_output_contains "unknown command error uses Omedora brand" "$unknown_output" "Unknown Omedora command"
assert_output_lacks "unknown command error does NOT mention Omarchy" "$unknown_output" "Unknown Omarchy command"

# JSON output includes brand-substituted routes for omedora.
json_output=$(OMARCHY_BRAND=omedora "$CLI" commands --json)
echo "$json_output" | jq -e '.commands[] | select(.binary == "omarchy-theme-set" and (.route | startswith("omedora ")))' >/dev/null
pass "OMARCHY_BRAND=omedora JSON routes start with 'omedora '"

# Routing works via either name regardless of brand: `omedora theme list` and
# `omarchy theme list` both resolve to the same binary. (Smoke check; the safe
# `theme list` dispatch is exercised above.)
omedora_output=$("$ROOT/bin/omedora" theme list)
omarchy_output=$("$CLI" theme list)
assert_equals "omedora theme list output == omarchy theme list output" \
  "$omedora_output" "$omarchy_output"
