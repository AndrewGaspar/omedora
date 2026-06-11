# Shared TAP-style helpers for omarchy/omedora test files.
#
# Source this file from any test script:
#   . "$(dirname -- "${BASH_SOURCE[0]}")/helpers.sh"
#
# All assertions emit TAP-style output (`ok - …` / `not ok - …`). Failures
# call `fail`, which exits non-zero, so a single failed assertion aborts
# the test file. This matches the style of test/omarchy-cli-test.sh.

pass() {
  printf 'ok - %s\n' "$1"
}

fail() {
  printf 'not ok - %s\n' "$1" >&2
  exit 1
}

# Assert that $output contains the literal substring $expected.
assert_output_contains() {
  local description="$1"
  local output="$2"
  local expected="$3"

  if [[ $output != *"$expected"* ]]; then
    printf 'Expected output to contain: %s\n' "$expected" >&2
    printf 'Actual output:\n%s\n' "$output" >&2
    fail "$description"
  fi

  pass "$description"
}

# Assert that $output does NOT contain the literal substring $unwanted.
assert_output_lacks() {
  local description="$1"
  local output="$2"
  local unwanted="$3"

  if [[ $output == *"$unwanted"* ]]; then
    printf 'Expected output NOT to contain: %s\n' "$unwanted" >&2
    printf 'Actual output:\n%s\n' "$output" >&2
    fail "$description"
  fi

  pass "$description"
}

# Assert that $actual equals $expected exactly.
assert_equals() {
  local description="$1"
  local actual="$2"
  local expected="$3"

  if [[ $actual != "$expected" ]]; then
    printf 'Expected: %s\n' "$expected" >&2
    printf 'Actual:   %s\n' "$actual" >&2
    fail "$description"
  fi

  pass "$description"
}

# Assert that a file exists.
assert_file_exists() {
  local description="$1"
  local path="$2"

  if [[ ! -e $path ]]; then
    printf 'Expected file to exist: %s\n' "$path" >&2
    fail "$description"
  fi

  pass "$description"
}

# Run a command and assert it exits with $expected_code.
# Usage: assert_exit_code "description" <expected_code> <command...>
assert_exit_code() {
  local description="$1"
  local expected_code="$2"
  shift 2

  set +e
  "$@" >/dev/null 2>&1
  local actual_code=$?
  set -e

  if (( actual_code != expected_code )); then
    printf 'Expected exit code: %d\n' "$expected_code" >&2
    printf 'Actual exit code:   %d\n' "$actual_code" >&2
    printf 'Command was:        %s\n' "$*" >&2
    fail "$description"
  fi

  pass "$description"
}
