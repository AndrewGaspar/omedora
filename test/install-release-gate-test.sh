#!/bin/bash
#
# L1 unit tests for the fresh-install release-support gate
# (omedora/install/release.sh, sourced first by omedora/install/plan.sh):
#   - supported release (probe exit 0)           -> continue
#   - no COPR chroot for the release (exit 1)    -> refuse, exit 1, before the
#                                                   plan is computed or shown
#   - OMEDORA_ALLOW_UNSUPPORTED_RELEASE=1        -> warn, continue
#   - probe couldn't check (exit 2)              -> warn, continue
#   - harness local repo injected                -> probe skipped entirely
# plus one end-to-end run through the real omedora-copr probe (fixture seam).
#
# Offline: the probe is a stub selected through OMEDORA_COPR_CMD.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

export OMEDORA_REPO_ROOT="$ROOT"
export OMARCHY_DISTRO=fedora
GATE="$ROOT/omedora/install/release.sh"
PLAN="$ROOT/omedora/install/plan.sh"

SCRATCH="$(mktemp -d)"
trap '[[ -n $SCRATCH && -d $SCRATCH ]] && rm -rf "$SCRATCH"' EXIT

PROBE_LOG="$SCRATCH/probe.log"
export PROBE_LOG
PROBE="$SCRATCH/omedora-copr-stub"
cat >"$PROBE" <<'EOF'
#!/bin/bash
printf 'probe %s\n' "$*" >>"$PROBE_LOG"
if [[ ${1:-} == "--chroot-available" ]]; then
  [[ -n ${PROBE_ERR:-} ]] && printf '%s\n' "$PROBE_ERR" >&2
  exit "${PROBE_RC:-0}"
fi
echo "agaspar/omedora-4"
EOF
chmod +x "$PROBE"

OS_F46="$SCRATCH/os-release"
printf 'ID=fedora\nVERSION_ID=46\n' >"$OS_F46"
export OMEDORA_OS_RELEASE="$OS_F46"
export OMEDORA_LOCAL_REPO_FILE="$SCRATCH/no-local.repo"

# gate <expected rc> <description> [env...]  — runs release.sh standalone
gate() {
  local expected=$1 description=$2
  shift 2
  local rc=0
  : >"$PROBE_LOG"
  gate_out=$(env OMEDORA_COPR_CMD="$PROBE" "$@" bash "$GATE" 2>&1) || rc=$?
  if (( rc != expected )); then
    printf 'Expected rc %s, got %s; output:\n%s\n' "$expected" "$rc" "$gate_out" >&2
    fail "$description"
  fi
  pass "$description"
}

echo "# --- probe outcomes ---"

gate 0 "a supported release passes the gate" PROBE_RC=0
assert_output_contains "the supported release is reported" "$gate_out" "Fedora 46 is supported"
assert_output_contains "the gate probes the running release" "$(cat "$PROBE_LOG")" "probe --chroot-available"

gate 1 "a release without a COPR chroot is refused" PROBE_RC=1 \
  PROBE_ERR="omedora-copr: agaspar/omedora-4 has no fedora-46-x86_64 chroot; available Fedora releases: 44 45"
assert_output_contains "the refusal names the release" "$gate_out" "doesn't support Fedora 46 yet"
assert_output_contains "the refusal names the COPR" "$gate_out" "agaspar/omedora-4 has no packages built for it"
assert_output_contains "the refusal relays the supported releases" "$gate_out" "available Fedora releases: 44 45"
assert_output_contains "the refusal says nothing changed" "$gate_out" "nothing was changed"
assert_output_contains "the refusal mentions the escape hatch" "$gate_out" "OMEDORA_ALLOW_UNSUPPORTED_RELEASE=1"

gate 0 "OMEDORA_ALLOW_UNSUPPORTED_RELEASE=1 overrides the refusal" PROBE_RC=1 \
  OMEDORA_ALLOW_UNSUPPORTED_RELEASE=1
assert_output_contains "the override still warns" "$gate_out" "is not supported"

gate 0 "a probe that couldn't check warns and continues" PROBE_RC=2 \
  PROBE_ERR="omedora-copr: could not reach the COPR API to check for fedora-46-x86_64"
assert_output_contains "the couldn't-check warning is shown" "$gate_out" "couldn't verify"
assert_output_contains "the couldn't-check warning relays the probe error" "$gate_out" "could not reach the COPR API"

touch "$SCRATCH/omedora-local.repo"
gate 0 "the harness local repo skips the gate" PROBE_RC=1 \
  OMEDORA_LOCAL_REPO_FILE="$SCRATCH/omedora-local.repo"
[[ ! -s $PROBE_LOG ]] && pass "the local repo means the COPR probe never runs" \
  || fail "the local repo means the COPR probe never runs"

# install-4.sh sources plan.sh (and so release.sh) under set -eEo pipefail:
# the warn-and-continue paths must not leak a failing status into it.
for rc_case in 0 2; do
  sourced_out=$(env OMEDORA_COPR_CMD="$PROBE" PROBE_RC=$rc_case \
    bash -c 'set -eEo pipefail; source "$1"; echo "sourced-continued"' _ "$GATE" 2>&1 || true)
  assert_output_contains "sourcing the gate under set -e continues (probe exit $rc_case)" \
    "$sourced_out" "sourced-continued"
done
sourced_out=$(env OMEDORA_COPR_CMD="$PROBE" PROBE_RC=1 OMEDORA_ALLOW_UNSUPPORTED_RELEASE=1 \
  bash -c 'set -eEo pipefail; source "$1"; echo "sourced-continued"' _ "$GATE" 2>&1 || true)
assert_output_contains "sourcing the gate under set -e continues (override)" \
  "$sourced_out" "sourced-continued"

echo "# --- the gate runs first in plan.sh ---"

STUB_PATH="$SCRATCH/shim"
mkdir -p "$STUB_PATH"
for tool in dnf rpm flatpak sudo; do
  printf '#!/bin/bash\nprintf "%s %%s\\n" "$*" >>"%s"\nexit 1\n' "$tool" "$SCRATCH/system.log" >"$STUB_PATH/$tool"
  chmod +x "$STUB_PATH/$tool"
done

: >"$SCRATCH/system.log"
rc=0
plan_out=$(env PATH="$STUB_PATH:$PATH" OMEDORA_COPR_CMD="$PROBE" PROBE_RC=1 \
  OMEDORA_PLAN_SKIP_PKGS=1 OMEDORA_PLAN_AUTOCONFIRM=1 bash "$PLAN" 2>&1) || rc=$?
assert_equals "plan.sh exits 1 on an unsupported release" "$rc" "1"
assert_output_lacks "plan.sh refuses before printing the plan" "$plan_out" "Omedora install plan"
[[ ! -s $SCRATCH/system.log ]] && pass "plan.sh refuses before touching dnf/rpm/flatpak/sudo" \
  || { cat "$SCRATCH/system.log" >&2; fail "plan.sh refuses before touching dnf/rpm/flatpak/sudo"; }

rc=0
plan_out=$(env PATH="$STUB_PATH:$PATH" OMEDORA_COPR_CMD="$PROBE" PROBE_RC=0 \
  OMEDORA_PLAN_SKIP_PKGS=1 OMEDORA_PLAN_AUTOCONFIRM=1 \
  OMEDORA_PLAN_SOURCE="$SCRATCH/empty-src" OMEDORA_PLAN_DEST="$SCRATCH/home/.config" \
  bash "$PLAN" 2>&1) || rc=$?
assert_equals "plan.sh proceeds on a supported release" "$rc" "0"
assert_output_contains "plan.sh then shows the plan" "$plan_out" "Omedora install plan"

echo "# --- end to end through the real probe ---"

FIXTURE="$SCRATCH/project.json"
printf '%s' '{"chroot_repos": {"fedora-44-x86_64": "x", "fedora-45-x86_64": "y"}}' >"$FIXTURE"
rc=0
real_out=$(env -u OMEDORA_COPR_CMD OMEDORA_COPR_API_FIXTURE="$FIXTURE" OMEDORA_COPR_ARCH=x86_64 \
  bash "$GATE" 2>&1) || rc=$?
assert_equals "the real probe refuses Fedora 46 against a 44/45 project" "$rc" "1"
assert_output_contains "the real probe's release list reaches the user" "$real_out" "available Fedora releases: 44 45"

printf 'ID=fedora\nVERSION_ID=45\n' >"$SCRATCH/os-release-45"
rc=0
real_out=$(env -u OMEDORA_COPR_CMD OMEDORA_COPR_API_FIXTURE="$FIXTURE" OMEDORA_COPR_ARCH=x86_64 \
  OMEDORA_OS_RELEASE="$SCRATCH/os-release-45" bash "$GATE" 2>&1) || rc=$?
assert_equals "the real probe accepts Fedora 45 against a 44/45 project" "$rc" "0"
