#!/bin/bash
#
# Update-flow unit tests for the Omarchy-4 (package-backed) line.
#
#   PART 1 — per-step Fedora dispatch in the omarchy-update pipeline:
#            keyring/aur/orphans are clean no-ops (no pacman/yay reached),
#            system-pkgs updates only the resolved Omedora-managed RPM set,
#            update-time restarts chronyd (and never aborts when it's absent),
#            snapshot `create` routes to omedora-snapshot.
#   PART 2 — bin/fedora/update-available writes the same state files the shell
#            widget reads and honors the upstream exit contract
#            (0 = updates listed on stdout, 1 = "System is up to date"),
#            driven through the $OMEDORA_DNF_CMD seam.
#   PART 3 — bin/omarchy-update-restart attributes kernels via rpm on Fedora
#            (pacman is absent there; a bare pacman probe would always prompt
#            for a reboot).
#   PART 4 — the Arch path of every gated step emits NO dnf calls
#            (dual-distro contract).
#
# Everything external is stubbed on PATH; no network, no real package manager.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SCRATCH="$(mktemp -d)"
trap '[[ -n $SCRATCH && -d $SCRATCH ]] && rm -rf "$SCRATCH"' EXIT

SHIM="$SCRATCH/shim"
mkdir -p "$SHIM"
MOCK_LOG="$SCRATCH/mock.log"
export MOCK_LOG

stub() { printf '#!/bin/bash\n%s\n' "$2" >"$SHIM/$1"; chmod +x "$SHIM/$1"; }

stub sudo             'printf "sudo %s\n" "$*" >>"$MOCK_LOG"; "$@"'
cat >"$SHIM/dnf" <<'EOF'
#!/bin/bash
printf 'dnf %s\n' "$*" >>"$MOCK_LOG"
case "$1" in
  repoquery)
    [[ ${UPDATE_FAIL_QUERY:-0} != 1 ]] || exit 55
    if [[ " $* " == *" --installed "* ]]; then
      if [[ -n ${UPDATE_INSTALLED_QUERY_COUNT_FILE:-} ]]; then
        count=$(($(cat "$UPDATE_INSTALLED_QUERY_COUNT_FILE" 2>/dev/null || echo 0) + 1))
        printf '%s\n' "$count" >"$UPDATE_INSTALLED_QUERY_COUNT_FILE"
        [[ $count != "${UPDATE_FAIL_INSTALLED_QUERY_AT:-}" ]] || exit 56
      fi
      if [[ -n ${UPDATE_INSTALLED_FILE:-} ]]; then
        cat "$UPDATE_INSTALLED_FILE"
      else
        printf '%s\n' "${UPDATE_INSTALLED:-}"
      fi
    elif [[ " $* " == *" --repo "* ]]; then
      printf '%s\n' "${UPDATE_CORE_CANDIDATES:-}"
    else
      printf '%s\n' "${UPDATE_MANAGED_CANDIDATES:-}"
    fi
    ;;
  copr)
    [[ ${UPDATE_FAIL_COPR:-0} != 1 ]]
    ;;
  install|reinstall)
    if [[ " $* " == *" omedora-"* && -n ${UPDATE_INSTALLED_FILE:-} && ${UPDATE_NO_STATE_CHANGE:-0} != 1 ]]; then
      printf '%s\n' "${UPDATE_POST_INSTALLED:-}" >"$UPDATE_INSTALLED_FILE"
    fi
    if [[ $1 == "install" && -n ${UPDATE_BASE_TO_MUTATE:-} && ! -e ${UPDATE_BASE_TO_MUTATE}.mutated ]]; then
      printf 'new-base\n' >>"$UPDATE_BASE_TO_MUTATE"
      touch "${UPDATE_BASE_TO_MUTATE}.mutated"
    fi
    ;;
esac
EOF
chmod +x "$SHIM/dnf"
stub pacman           'printf "pacman %s\n" "$*" >>"$MOCK_LOG"'
stub pacman-key       'printf "pacman-key %s\n" "$*" >>"$MOCK_LOG"'
stub yay              'printf "yay %s\n" "$*" >>"$MOCK_LOG"'
stub systemctl        'printf "systemctl %s\n" "$*" >>"$MOCK_LOG"'
stub rpm              'printf "rpm %s\n" "$*" >>"$MOCK_LOG"; [[ $1 == "-q" && ( $2 == "optional-rpm" || $2 == "unrelated-rpm" ) ]]'
stub omedora-snapshot 'printf "omedora-snapshot %s\n" "$*" >>"$MOCK_LOG"'
stub omarchy-pkg-missing 'exit 1'
stub gum              'exit 0'

export PATH="$SHIM:$ROOT/bin:$PATH"

run_fedora() { ( export OMARCHY_DISTRO=fedora; : >"$MOCK_LOG"; "$@" ); }

# ===========================================================================
echo "# --- PART 1: per-step Fedora dispatch ---"
# ===========================================================================

run_fedora bash "$ROOT/bin/omarchy-update-keyring" >/dev/null
grep -qE "pacman" "$MOCK_LOG" \
  && fail "keyring on Fedora is a no-op (no pacman)" \
  || pass "keyring on Fedora is a no-op (no pacman)"

UPDATE_MAP="$SCRATCH/update-map.toml"
UPDATE_BASE="$SCRATCH/base.packages"
UPDATE_BASELINE="$SCRATCH/baseline.packages"
cat >"$UPDATE_MAP" <<'EOF'
[mapped-base]
source = "dnf"
names = ["base-rpm"]

[optional]
source = "dnf"
names = ["optional-rpm"]

[skipped]
source = "skip"
reason = "fixture"
EOF
printf 'mapped-base\n' >"$UPDATE_BASE"
printf 'baseline-rpm\n' >"$UPDATE_BASELINE"

run_fedora env \
  OMARCHY_FEDORA_MAP="$UPDATE_MAP" \
  OMARCHY_BASE_PKGS="$UPDATE_BASE" \
  OMEDORA_BASELINE_PKGS="$UPDATE_BASELINE" \
  OMEDORA_COPR_PROJECT="test/omedora-4" \
  OMEDORA_COPR_REPO_ID="test-omedora-4" \
  UPDATE_CORE_CANDIDATES=$'omedora 2.0-1 omedora-0:2.0-1.noarch test-omedora-4\nomedora-settings 2.0-1 omedora-settings-0:2.0-1.noarch test-omedora-4' \
  UPDATE_INSTALLED=$'omedora 2.0-1 test-omedora-4\nomedora-settings 2.0-1 test-omedora-4' \
  UPDATE_MANAGED_CANDIDATES=$'base-rpm\nnew-base\nbaseline-rpm\noptional-rpm' \
  UPDATE_BASE_TO_MUTATE="$UPDATE_BASE" \
  bash "$ROOT/bin/omarchy-update-system-pkgs" >/dev/null
assert_equals "managed update re-resolves after the core RPM transaction" \
  "$(grep -c '^dnf install ' "$MOCK_LOG")" "2"
first_managed_line=$(grep '^dnf install ' "$MOCK_LOG" | head -1)
managed_line=$(grep '^dnf install ' "$MOCK_LOG" | tail -1)
assert_output_lacks "new base package is absent before the payload refresh" \
  "$first_managed_line" "new-base"
for package in base-rpm new-base baseline-rpm optional-rpm; do
  assert_output_contains "managed update includes $package" "$managed_line" "$package"
done
assert_output_lacks "managed update excludes an unrelated installed RPM" "$managed_line" "unrelated-rpm"
assert_output_contains "managed update refreshes dnf metadata" "$managed_line" "--refresh"
assert_output_contains "managed update avoids weak-dependency drift" "$managed_line" "--setopt=install_weak_deps=False"
assert_output_contains "managed update enables the version-scoped COPR" \
  "$(cat "$MOCK_LOG")" "dnf copr enable -y test/omedora-4"
assert_output_contains "managed update queries candidate provenance" \
  "$(cat "$MOCK_LOG")" "repoquery --available"
grep -q 'omedora/install/fedora-baseline.packages' "$ROOT/omedora/packaging/copr/omedora.spec" \
  && pass "core RPM ships the Fedora baseline consumed by installed updates" \
  || fail "core RPM ships the Fedora baseline consumed by installed updates"
grep -qE '^dnf (upgrade|update)( |$)' "$MOCK_LOG" \
  && { cat "$MOCK_LOG" >&2; fail "system-pkgs on Fedora never runs an unscoped upgrade"; } \
  || pass "system-pkgs on Fedora never runs an unscoped upgrade"
grep -q "pacman" "$MOCK_LOG" \
  && fail "system-pkgs on Fedora never reaches pacman" \
  || pass "system-pkgs on Fedora never reaches pacman"

VERSION_MAP="$SCRATCH/version-map.toml"
VERSION_BASE="$SCRATCH/version-base.packages"
VERSION_BASELINE="$SCRATCH/version-baseline.packages"
cat >"$VERSION_MAP" <<'EOF'
[future-base]
source = "dnf"
names = ["future-base-rpm"]
since = "45"

[former-base]
source = "dnf"
names = ["former-base-rpm"]
until = "45"

[future-optional]
source = "dnf"
names = ["optional-rpm"]
since = "45"
EOF
printf 'future-base\nformer-base\n' >"$VERSION_BASE"
: >"$VERSION_BASELINE"

managed_f44=$(OMEDORA_FEDORA_VERSION=44 \
  OMARCHY_FEDORA_MAP="$VERSION_MAP" \
  OMARCHY_BASE_PKGS="$VERSION_BASE" \
  OMEDORA_BASELINE_PKGS="$VERSION_BASELINE" \
  python3 "$ROOT/bin/fedora/managed_packages.py")
assert_output_contains "managed resolver applies an until entry on Fedora 44" \
  "$managed_f44" "former-base-rpm"
assert_output_lacks "managed resolver omits a future base mapping on Fedora 44" \
  "$managed_f44" "future-base"
assert_output_lacks "managed resolver excludes inactive optional entries on Fedora 44" \
  "$managed_f44" "optional-rpm"

managed_f45=$(OMEDORA_FEDORA_VERSION=45 \
  OMARCHY_FEDORA_MAP="$VERSION_MAP" \
  OMARCHY_BASE_PKGS="$VERSION_BASE" \
  OMEDORA_BASELINE_PKGS="$VERSION_BASELINE" \
  python3 "$ROOT/bin/fedora/managed_packages.py")
assert_output_contains "managed resolver applies a since entry on Fedora 45" \
  "$managed_f45" "future-base-rpm"
assert_output_lacks "managed resolver omits an expired base mapping on Fedora 45" \
  "$managed_f45" "former-base"
assert_output_contains "managed resolver includes active installed optional entries" \
  "$managed_f45" "optional-rpm"

# Resolver failures must abort before dnf. Process substitution used to detach
# these statuses and turn malformed or missing inputs into successful no-ops.
BROKEN_MAP="$SCRATCH/broken-map.toml"
printf '[broken\n' >"$BROKEN_MAP"
: >"$MOCK_LOG"
if run_fedora env \
  OMARCHY_FEDORA_MAP="$BROKEN_MAP" \
  OMARCHY_BASE_PKGS="$UPDATE_BASE" \
  OMEDORA_BASELINE_PKGS="$UPDATE_BASELINE" \
  bash "$ROOT/bin/omarchy-update-system-pkgs" >/dev/null 2>&1; then
  fail "malformed package map fails closed"
else
  pass "malformed package map fails closed"
fi
[[ ! -s $MOCK_LOG ]] && pass "malformed map attempts no dnf transaction" \
  || fail "malformed map attempts no dnf transaction"

: >"$MOCK_LOG"
if run_fedora env \
  OMARCHY_FEDORA_MAP="$SCRATCH/missing-map.toml" \
  OMARCHY_BASE_PKGS="$UPDATE_BASE" \
  OMEDORA_BASELINE_PKGS="$UPDATE_BASELINE" \
  bash "$ROOT/bin/omarchy-update-system-pkgs" >/dev/null 2>&1; then
  fail "missing package map fails closed"
else
  pass "missing package map fails closed"
fi
[[ ! -s $MOCK_LOG ]] && pass "missing map attempts no dnf transaction" \
  || fail "missing map attempts no dnf transaction"

EMPTY_RESOLVER="$SCRATCH/empty-resolver"
printf '#!/bin/bash\nexit 0\n' >"$EMPTY_RESOLVER"
chmod +x "$EMPTY_RESOLVER"
: >"$MOCK_LOG"
run_fedora env OMEDORA_MANAGED_RESOLVER="$EMPTY_RESOLVER" \
  bash "$ROOT/bin/omarchy-update-system-pkgs" >/dev/null
[[ ! -s $MOCK_LOG ]] && pass "valid empty resolution is a clean no-op" \
  || fail "valid empty resolution is a clean no-op"

SECOND_FAIL_RESOLVER="$SCRATCH/second-fail-resolver"
SECOND_FAIL_STATE="$SCRATCH/second-fail-state"
cat >"$SECOND_FAIL_RESOLVER" <<EOF
#!/bin/bash
if [[ -e $SECOND_FAIL_STATE ]]; then
  exit 42
fi
touch $SECOND_FAIL_STATE
printf 'omedora\nomedora-settings\nbase-rpm\n'
EOF
chmod +x "$SECOND_FAIL_RESOLVER"
: >"$MOCK_LOG"
if run_fedora env \
  OMEDORA_MANAGED_RESOLVER="$SECOND_FAIL_RESOLVER" \
  OMEDORA_COPR_PROJECT="test/omedora-4" \
  OMEDORA_COPR_REPO_ID="test-omedora-4" \
  UPDATE_CORE_CANDIDATES=$'omedora 2.0-1 omedora-0:2.0-1.noarch test-omedora-4\nomedora-settings 2.0-1 omedora-settings-0:2.0-1.noarch test-omedora-4' \
  UPDATE_INSTALLED=$'omedora 2.0-1 test-omedora-4\nomedora-settings 2.0-1 test-omedora-4' \
  UPDATE_MANAGED_CANDIDATES=$'base-rpm' \
  bash "$ROOT/bin/omarchy-update-system-pkgs" >/dev/null 2>&1; then
  fail "second resolver pass fails closed"
else
  pass "second resolver pass fails closed"
fi
assert_equals "second resolver failure permits only the completed first transaction" \
  "$(grep -c '^dnf install ' "$MOCK_LOG")" "1"

# Missing candidates and wrong core provenance must fail before dnf can accept
# an installed stale package as "Nothing to do".
for scenario in missing-candidate wrong-provenance ambiguous-core; do
  rm -f "$SECOND_FAIL_STATE"
  : >"$MOCK_LOG"
  if [[ $scenario == "missing-candidate" ]]; then
    candidates=""
    core_candidates=$'omedora 2.0-1 omedora-0:2.0-1.noarch test-omedora-4\nomedora-settings 2.0-1 omedora-settings-0:2.0-1.noarch test-omedora-4'
  elif [[ $scenario == "wrong-provenance" ]]; then
    candidates=$'base-rpm'
    core_candidates=$'omedora 2.0-1 omedora-0:2.0-1.noarch foreign-repo\nomedora-settings 2.0-1 omedora-settings-0:2.0-1.noarch test-omedora-4'
  else
    candidates=$'base-rpm'
    core_candidates=$'omedora 2.0-1 omedora-0:2.0-1.noarch test-omedora-4\nomedora 2.0-1 omedora-0:2.0-1.noarch test-omedora-4\nomedora-settings 2.0-1 omedora-settings-0:2.0-1.noarch test-omedora-4'
  fi
  if run_fedora env \
    OMEDORA_MANAGED_RESOLVER="$SECOND_FAIL_RESOLVER" \
    OMEDORA_COPR_PROJECT="test/omedora-4" \
    OMEDORA_COPR_REPO_ID="test-omedora-4" \
    UPDATE_CORE_CANDIDATES="$core_candidates" \
    UPDATE_INSTALLED=$'omedora 2.0-1 test-omedora-4\nomedora-settings 2.0-1 test-omedora-4' \
    UPDATE_MANAGED_CANDIDATES="$candidates" \
    bash "$ROOT/bin/omarchy-update-system-pkgs" >/dev/null 2>&1; then
    fail "$scenario fails closed"
  else
    pass "$scenario fails closed"
  fi
  grep -q '^dnf install ' "$MOCK_LOG" \
    && fail "$scenario reaches no install transaction" \
    || pass "$scenario reaches no install transaction"
  rm -f "$SECOND_FAIL_STATE"
done

CORE_RESOLVER="$SCRATCH/core-resolver"
cat >"$CORE_RESOLVER" <<'EOF'
#!/bin/bash
printf 'omedora\nomedora-settings\nbase-rpm\n'
EOF
chmod +x "$CORE_RESOLVER"
CORE_CANDIDATES=$'omedora 2.0-1 omedora-0:2.0-1.noarch test-omedora-4\nomedora-settings 2.0-1 omedora-settings-0:2.0-1.noarch test-omedora-4'
CORE_POST=$'omedora 2.0-1 test-omedora-4\nomedora-settings 2.0-1 test-omedora-4'
CORE_STATE="$SCRATCH/core-installed"

run_core_case() {
  local initial="$1"
  printf '%s\n' "$initial" >"$CORE_STATE"
  run_fedora env \
    OMEDORA_MANAGED_RESOLVER="$CORE_RESOLVER" \
    OMEDORA_COPR_PROJECT="test/omedora-4" \
    OMEDORA_COPR_REPO_ID="test-omedora-4" \
    UPDATE_CORE_CANDIDATES="$CORE_CANDIDATES" \
    UPDATE_INSTALLED_FILE="$CORE_STATE" \
    UPDATE_POST_INSTALLED="$CORE_POST" \
    UPDATE_MANAGED_CANDIDATES=$'base-rpm' \
    bash "$ROOT/bin/omarchy-update-system-pkgs" >/dev/null
}

run_core_case $'omedora 1.0-1 test-omedora-4\nomedora-settings 1.0-1 test-omedora-4'
core_install=$(grep '^dnf install .*omedora-0:2.0-1.noarch' "$MOCK_LOG")
assert_output_contains "old expected build selects exact latest expected-COPR NEVRA" \
  "$core_install" "omedora-0:2.0-1.noarch"
assert_output_contains "core transaction constrains source while allowing dependencies" \
  "$core_install" "--from-repo=test-omedora-4"
assert_output_contains "core transaction explicitly permits local-newer reconciliation" \
  "$core_install" "--allow-downgrade"
assert_equals "old expected build is replaced by selected expected build" \
  "$(cat "$CORE_STATE")" "$CORE_POST"

run_core_case $'omedora 2.0-1 foreign-repo\nomedora-settings 2.0-1 foreign-repo'
assert_output_contains "same-EVR foreign core is reinstalled from expected COPR" \
  "$(cat "$MOCK_LOG")" "dnf reinstall --refresh"
assert_output_contains "same-EVR reinstall is source constrained" \
  "$(grep '^dnf reinstall ' "$MOCK_LOG")" "--from-repo=test-omedora-4"
assert_equals "same-EVR foreign provenance becomes expected provenance" \
  "$(cat "$CORE_STATE")" "$CORE_POST"

run_core_case $'omedora 4.0-1 @commandline\nomedora-settings 4.0-1 @commandline'
assert_output_contains "locally newer core build is explicitly downgraded to selected NEVRA" \
  "$(grep '^dnf install .*omedora-0:2.0-1.noarch' "$MOCK_LOG")" "--allow-downgrade"
assert_equals "locally newer core does not remain installed" "$(cat "$CORE_STATE")" "$CORE_POST"

broad_install=$(grep '^dnf install .*base-rpm' "$MOCK_LOG" | tail -1)
assert_output_contains "broad managed transaction excludes omedora" "$broad_install" "--exclude=omedora"
assert_output_contains "broad managed transaction excludes omedora-settings" "$broad_install" "--exclude=omedora-settings"
assert_output_lacks "broad transaction contains no exact core package spec" "$broad_install" "omedora-0:"
assert_output_contains "core candidate query is constrained to expected repo" \
  "$(grep '^dnf repoquery --available --repo ' "$MOCK_LOG" | head -1)" \
  "--repo test-omedora-4"

printf '%s\n' $'omedora 1.0-1 test-omedora-4\nomedora-settings 1.0-1 test-omedora-4' >"$CORE_STATE"
if run_fedora env \
  OMEDORA_MANAGED_RESOLVER="$CORE_RESOLVER" \
  OMEDORA_COPR_PROJECT="test/omedora-4" \
  OMEDORA_COPR_REPO_ID="test-omedora-4" \
  UPDATE_CORE_CANDIDATES="$CORE_CANDIDATES" \
  UPDATE_INSTALLED_FILE="$CORE_STATE" \
  UPDATE_POST_INSTALLED="$CORE_POST" \
  UPDATE_MANAGED_CANDIDATES=$'base-rpm' \
  UPDATE_NO_STATE_CHANGE=1 \
  bash "$ROOT/bin/omarchy-update-system-pkgs" >/dev/null 2>&1; then
  fail "post-transaction EVR mismatch fails closed"
else
  pass "post-transaction EVR mismatch fails closed"
fi

printf '%s\n' $'omedora 1.0-1 test-omedora-4\nomedora-settings 1.0-1 test-omedora-4' >"$CORE_STATE"
if run_fedora env \
  OMEDORA_MANAGED_RESOLVER="$CORE_RESOLVER" \
  OMEDORA_COPR_PROJECT="test/omedora-4" \
  OMEDORA_COPR_REPO_ID="test-omedora-4" \
  UPDATE_CORE_CANDIDATES="$CORE_CANDIDATES" \
  UPDATE_INSTALLED_FILE="$CORE_STATE" \
  UPDATE_POST_INSTALLED=$'omedora 2.0-1 foreign-repo\nomedora-settings 2.0-1 foreign-repo' \
  UPDATE_MANAGED_CANDIDATES=$'base-rpm' \
  bash "$ROOT/bin/omarchy-update-system-pkgs" >/dev/null 2>&1; then
  fail "post-transaction foreign provenance fails closed"
else
  pass "post-transaction foreign provenance fails closed"
fi

QUERY_COUNT="$SCRATCH/installed-query-count"
printf '0\n' >"$QUERY_COUNT"
printf '%s\n' "$CORE_POST" >"$CORE_STATE"
if run_fedora env \
  OMEDORA_MANAGED_RESOLVER="$CORE_RESOLVER" \
  OMEDORA_COPR_PROJECT="test/omedora-4" \
  OMEDORA_COPR_REPO_ID="test-omedora-4" \
  UPDATE_CORE_CANDIDATES="$CORE_CANDIDATES" \
  UPDATE_INSTALLED_FILE="$CORE_STATE" \
  UPDATE_INSTALLED_QUERY_COUNT_FILE="$QUERY_COUNT" \
  UPDATE_FAIL_INSTALLED_QUERY_AT=3 \
  UPDATE_MANAGED_CANDIDATES=$'base-rpm' \
  bash "$ROOT/bin/omarchy-update-system-pkgs" >/dev/null 2>&1; then
  fail "post-transaction provenance query failure fails closed"
else
  pass "post-transaction provenance query failure fails closed"
fi

rm -f "$SECOND_FAIL_STATE"
: >"$MOCK_LOG"
if run_fedora env \
  OMEDORA_MANAGED_RESOLVER="$SECOND_FAIL_RESOLVER" \
  OMEDORA_COPR_PROJECT="test/omedora-4" \
  OMEDORA_COPR_REPO_ID="test-omedora-4" \
  UPDATE_FAIL_COPR=1 \
  bash "$ROOT/bin/omarchy-update-system-pkgs" >/dev/null 2>&1; then
  fail "unavailable version-scoped COPR fails closed"
else
  pass "unavailable version-scoped COPR fails closed"
fi
grep -q '^dnf install ' "$MOCK_LOG" \
  && fail "COPR enable failure reaches no install transaction" \
  || pass "COPR enable failure reaches no install transaction"

rm -f "$SECOND_FAIL_STATE"
: >"$MOCK_LOG"
if run_fedora env \
  OMEDORA_MANAGED_RESOLVER="$SECOND_FAIL_RESOLVER" \
  OMEDORA_COPR_PROJECT="test/omedora-4" \
  OMEDORA_COPR_REPO_ID="test-omedora-4" \
  UPDATE_FAIL_QUERY=1 \
  bash "$ROOT/bin/omarchy-update-system-pkgs" >/dev/null 2>&1; then
  fail "candidate query failure fails closed"
else
  pass "candidate query failure fails closed"
fi
grep -q '^dnf install ' "$MOCK_LOG" \
  && fail "candidate query failure reaches no install transaction" \
  || pass "candidate query failure reaches no install transaction"

run_fedora bash "$ROOT/bin/omarchy-update-aur-pkgs" >/dev/null
grep -qE "yay|pacman" "$MOCK_LOG" \
  && fail "aur-pkgs on Fedora is a no-op" \
  || pass "aur-pkgs on Fedora is a no-op"

run_fedora bash "$ROOT/bin/omarchy-update-orphan-pkgs" >/dev/null
grep -qE "pacman|dnf" "$MOCK_LOG" \
  && fail "orphan-pkgs on Fedora is a no-op" \
  || pass "orphan-pkgs on Fedora is a no-op"

run_fedora bash "$ROOT/bin/omarchy-update-time" >/dev/null
grep -q "systemctl restart chronyd" "$MOCK_LOG" \
  && pass "update-time on Fedora restarts chronyd" \
  || { cat "$MOCK_LOG" >&2; fail "update-time on Fedora restarts chronyd"; }
grep -q "timesyncd" "$MOCK_LOG" \
  && fail "update-time on Fedora never touches systemd-timesyncd" \
  || pass "update-time on Fedora never touches systemd-timesyncd"

run_fedora bash "$ROOT/bin/omarchy-snapshot" create >/dev/null
grep -q "omedora-snapshot create pre-update" "$MOCK_LOG" \
  && pass "snapshot create on Fedora routes to omedora-snapshot" \
  || { cat "$MOCK_LOG" >&2; fail "snapshot create on Fedora routes to omedora-snapshot"; }

# ===========================================================================
echo "# --- PART 2: bin/fedora/update-available state contract ---"
# ===========================================================================
export XDG_STATE_HOME="$SCRATCH/state"

# A dnf whose check-upgrade reports two updates (dnf exit 100). It also records
# its own argv so we can assert the check is SCOPED to the omedora COPR repo
# (#108) — the indicator must mean "an omedora update is available", not "any
# pending dnf update".
DNF_ARGS_LOG="$SCRATCH/dnf-args.log"
FAKE_DNF="$SCRATCH/fake-dnf-updates"
cat >"$FAKE_DNF" <<EOF
#!/bin/bash
printf '%s\n' "\$*" >"$DNF_ARGS_LOG"
printf 'omedora.noarch 0.2.0~alpha.1 copr:...:omedora-4\nfoo.x86_64 1.2-3.fc44 updates\n'
exit 100
EOF
chmod +x "$FAKE_DNF"

SCOPED_REPO_ID="copr:copr.fedorainfracloud.org:agaspar:omedora-4"
out=$(OMARCHY_DISTRO=fedora OMEDORA_DNF_CMD="$FAKE_DNF" \
      OMEDORA_COPR_REPO_ID="$SCOPED_REPO_ID" \
      bash "$ROOT/bin/omarchy-update-available") \
  && rc=0 || rc=$?
assert_equals "updates available -> exit 0" "0" "$rc"
assert_output_contains "stdout lists the updates" "$out" "omedora.noarch"
assert_output_contains "check-upgrade is scoped to the omedora COPR repo (#108)" \
  "$(cat "$DNF_ARGS_LOG")" "--repo $SCOPED_REPO_ID"
assert_file_exists "packages state file written" "$XDG_STATE_HOME/omarchy/updates/packages"
assert_file_exists "available state file written" "$XDG_STATE_HOME/omarchy/updates/available"
assert_file_exists "checked-at state file written" "$XDG_STATE_HOME/omarchy/updates/checked-at"
[[ -f "$XDG_STATE_HOME/omarchy/updates/aur" && ! -s "$XDG_STATE_HOME/omarchy/updates/aur" ]] \
  && pass "aur state file exists and is empty on Fedora" \
  || fail "aur state file exists and is empty on Fedora"
[[ ! -e "$XDG_STATE_HOME/omarchy/updates/error" ]] \
  && pass "no error state file on success" \
  || fail "no error state file on success"

# A dnf that reports no updates (exit 0).
stub_uptodate="$SCRATCH/fake-dnf-current"
printf '#!/bin/bash\nexit 0\n' >"$stub_uptodate"; chmod +x "$stub_uptodate"
out=$(OMARCHY_DISTRO=fedora OMEDORA_DNF_CMD="$stub_uptodate" bash "$ROOT/bin/omarchy-update-available") \
  && rc=0 || rc=$?
assert_equals "up to date -> exit 1" "1" "$rc"
assert_output_contains "up-to-date message" "$out" "System is up to date"
[[ ! -s "$XDG_STATE_HOME/omarchy/updates/available" ]] \
  && pass "available state cleared when current" \
  || fail "available state cleared when current"

: >"$DNF_ARGS_LOG"
out=$(OMARCHY_DISTRO=fedora OMEDORA_DNF_CMD="$FAKE_DNF" \
      OMEDORA_COPR_REPO_ID="" \
      bash "$ROOT/bin/omarchy-update-available" 2>&1) \
  && rc=0 || rc=$?
assert_equals "missing COPR identity reports no updates" "1" "$rc"
assert_output_contains "missing COPR identity fails closed" "$out" \
  "Could not resolve the version-scoped Omedora repository"
[[ ! -s $DNF_ARGS_LOG ]] \
  && pass "missing COPR identity never runs an unscoped dnf check" \
  || fail "missing COPR identity never runs an unscoped dnf check"

# ===========================================================================
echo "# --- PART 3: update-restart kernel attribution via rpm ---"
# ===========================================================================
# Build a fake /usr/lib/modules with one kernel that "rpm owns" and matches
# uname -r, so NO reboot prompt is needed; pacman must never be called.
# update-restart inspects /usr/lib/modules directly, so run it in a mount-free
# way: stub uname + point the loop via a chroot-like PATH... the script
# hardcodes /usr/lib/modules; instead verify the probe dispatch by behavior:
# on Fedora with rpm stubbed exit 0 and a real /usr/lib/modules (if any), the
# script must not call pacman. (Kernel-state assertions live in the L2 suite.)
stub gum 'printf "gum %s\n" "$*" >>"$MOCK_LOG"; exit 1'  # decline any prompt
run_fedora bash "$ROOT/bin/omarchy-update-restart" >/dev/null 2>&1 || true
grep -q "pacman" "$MOCK_LOG" \
  && fail "update-restart on Fedora never calls pacman" \
  || pass "update-restart on Fedora never calls pacman"

# ===========================================================================
echo "# --- PART 4: Arch paths emit no dnf (dual-distro contract) ---"
# ===========================================================================
for cmd in omarchy-update-keyring omarchy-update-system-pkgs omarchy-update-aur-pkgs \
           omarchy-update-orphan-pkgs omarchy-update-time; do
  : >"$MOCK_LOG"
  ( export OMARCHY_DISTRO=arch; bash "$ROOT/bin/$cmd" >/dev/null 2>&1 ) || true
  if grep -q "^dnf\|omedora-snapshot" "$MOCK_LOG"; then
    cat "$MOCK_LOG" >&2
    fail "Arch path of $cmd emits no dnf/omedora calls"
  else
    pass "Arch path of $cmd emits no dnf/omedora calls"
  fi
done

echo "# all update-flow tests passed"
