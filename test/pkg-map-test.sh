#!/bin/bash
#
# L1 unit tests for bin/omarchy-dev-validate-fedora-packages.
#
# Drives the validator against fixture TOML maps that exercise each
# schema rule (good and bad). The real map at install/packages/fedora.toml
# is also validated as a smoke check.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

VALIDATOR="$ROOT/bin/omarchy-dev-validate-fedora-packages"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

# Set up a stable installers dir (most fixtures don't use source=, but a couple do)
INSTALLERS_DIR="$TMPDIR/installers"
mkdir -p "$INSTALLERS_DIR"
echo '# placeholder' >"$INSTALLERS_DIR/install-walker.sh"

write_map() {
  local name="$1"
  local content="$2"
  local path="$TMPDIR/$name.toml"
  printf '%s\n' "$content" >"$path"
  printf '%s' "$path"
}

run_validator() {
  local map="$1"
  OMARCHY_FEDORA_MAP="$map" OMARCHY_FEDORA_INSTALLERS="$INSTALLERS_DIR" \
    "$VALIDATOR" 2>&1
}

# --- The real map ships valid -----------------------------------------------

real_output=$("$VALIDATOR" 2>&1)
assert_output_contains "real fedora.toml validates clean" "$real_output" "package(s) ok"

python3 - "$ROOT/install/packages/fedora.toml" <<'PY'
import sys
import tomllib

with open(sys.argv[1], "rb") as file:
  package_map = tomllib.load(file)

expected = {
  "herdr": ["herdr"],
  "libvips": ["vips-tools"],
  "omacalc": ["omacalc"],
  "ttfx": ["ttfx"],
  "quickshell-git": ["quickshell"],
}
for package, names in expected.items():
  entry = package_map.get(package)
  assert entry is not None, f"{package} is missing from the Fedora package map"
  assert entry.get("source") == "dnf", f"{package} should resolve through dnf"
  assert entry.get("names") == names, (
    f"{package} should resolve to {names}, got {entry.get('names')}"
  )
PY
pass "Quattro base additions have explicit Fedora dnf mappings"

# --- Valid fixtures: one of each tier --------------------------------------

valid=$(write_map valid '
[dnf-pkg]
source = "dnf"
names = ["dnf-pkg-fedora"]

[copr-pkg]
source = "copr"
copr = "scottames/ghostty"
names = ["copr-pkg"]

[flathub-pkg]
source = "flathub"
app_id = "com.example.App"

[source-pkg]
source = "source"
installer = "install-walker.sh"

[skip-pkg]
source = "skip"
reason = "not applicable on fedora"
')

assert_exit_code "valid map of all 5 tiers exits 0" 0 \
  env OMARCHY_FEDORA_MAP="$valid" OMARCHY_FEDORA_INSTALLERS="$INSTALLERS_DIR" "$VALIDATOR"

# --- Missing source key fails ----------------------------------------------

missing_source=$(write_map missing-source '
[bad]
names = ["bad"]
')

assert_exit_code "missing source key exits 1" 1 \
  env OMARCHY_FEDORA_MAP="$missing_source" OMARCHY_FEDORA_INSTALLERS="$INSTALLERS_DIR" "$VALIDATOR"
output=$(run_validator "$missing_source" || true)
assert_output_contains "missing source surfaces error" "$output" "missing required key: source"

# --- Invalid source value fails --------------------------------------------

invalid_source=$(write_map invalid-source '
[bad]
source = "yum"
names = ["bad"]
')

output=$(run_validator "$invalid_source" || true)
assert_output_contains "invalid source value surfaces error" "$output" "invalid source 'yum'"

# --- source=dnf without names fails ----------------------------------------

dnf_no_names=$(write_map dnf-no-names '
[bad]
source = "dnf"
')

output=$(run_validator "$dnf_no_names" || true)
assert_output_contains "source=dnf requires names" "$output" "requires non-empty 'names' array"

# --- source=copr with un-allowlisted COPR fails ----------------------------

bad_copr=$(write_map bad-copr '
[bad]
source = "copr"
copr = "rando/repo"
names = ["bad"]
')

output=$(run_validator "$bad_copr" || true)
assert_output_contains "un-allowlisted COPR fails" "$output" "not in the allowlist"

# --- source=copr without copr field fails ----------------------------------

copr_no_repo=$(write_map copr-no-repo '
[bad]
source = "copr"
names = ["bad"]
')

output=$(run_validator "$copr_no_repo" || true)
assert_output_contains "source=copr requires copr field" "$output" "requires 'copr' string"

# --- source=copr with bad format fails -------------------------------------

copr_bad_format=$(write_map copr-bad-format '
[bad]
source = "copr"
copr = "notslashed"
names = ["bad"]
')

output=$(run_validator "$copr_bad_format" || true)
assert_output_contains "source=copr requires owner/repo format" "$output" "owner/repo format"

# --- source=flathub without app_id fails -----------------------------------

flathub_no_id=$(write_map flathub-no-id '
[bad]
source = "flathub"
')

output=$(run_validator "$flathub_no_id" || true)
assert_output_contains "source=flathub requires app_id" "$output" "requires 'app_id' string"

# --- source=flathub with non-reverse-DNS app_id fails ----------------------

flathub_bad_id=$(write_map flathub-bad-id '
[bad]
source = "flathub"
app_id = "myapp"
')

output=$(run_validator "$flathub_bad_id" || true)
assert_output_contains "source=flathub requires reverse-DNS app_id" "$output" "reverse-DNS"

# --- source=source with missing installer file fails -----------------------

missing_installer=$(write_map missing-installer '
[bad]
source = "source"
installer = "install-does-not-exist.sh"
')

output=$(run_validator "$missing_installer" || true)
assert_output_contains "missing installer file fails" "$output" "not found at"

# --- source=skip without reason fails --------------------------------------

skip_no_reason=$(write_map skip-no-reason '
[bad]
source = "skip"
')

output=$(run_validator "$skip_no_reason" || true)
assert_output_contains "source=skip requires reason" "$output" "requires 'reason' string"

# --- since/until invalid range fails ---------------------------------------

bad_range=$(write_map bad-range '
[pkg]
source = "dnf"
names = ["pkg"]
since = "45"
until = "44"
')

output=$(run_validator "$bad_range" || true)
assert_output_contains "since >= until fails" "$output" "must be <"

# --- unknown key warns but does not fail -----------------------------------

unknown_key=$(write_map unknown-key '
[pkg]
source = "dnf"
names = ["pkg"]
typo = "value"
')

assert_exit_code "unknown key does not fail" 0 \
  env OMARCHY_FEDORA_MAP="$unknown_key" OMARCHY_FEDORA_INSTALLERS="$INSTALLERS_DIR" "$VALIDATOR"
output=$(run_validator "$unknown_key")
assert_output_contains "unknown key produces warning" "$output" "unknown key 'typo'"

# --- --json output is valid JSON with ok flag -------------------------------

json_output=$(OMARCHY_FEDORA_MAP="$valid" OMARCHY_FEDORA_INSTALLERS="$INSTALLERS_DIR" \
  "$VALIDATOR" --json)
echo "$json_output" | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["ok"] is True, f"ok should be true, got {data}"
assert data["package_count"] == 5, f"package_count should be 5, got {data}"
assert data["errors"] == [], f"errors should be empty, got {data}"
'
pass "--json output is structured and reports ok=true for valid map"

# --- --json on bad map reports ok=false ------------------------------------

json_bad=$(OMARCHY_FEDORA_MAP="$missing_source" OMARCHY_FEDORA_INSTALLERS="$INSTALLERS_DIR" \
  "$VALIDATOR" --json 2>/dev/null || true)
echo "$json_bad" | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert data["ok"] is False, f"ok should be false, got {data}"
assert len(data["errors"]) > 0, f"errors should be non-empty, got {data}"
'
pass "--json on bad map reports ok=false with errors"
