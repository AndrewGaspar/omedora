#!/bin/bash
#
# L1 unit tests for how the Fedora updater (bin/fedora/update-system-pkgs,
# reached through omarchy-update-system-pkgs) handles a Fedora release the
# Omedora COPR doesn't build for, and for its post-transaction rebuild check:
#
#   - `dnf copr enable` fails and `omedora-copr --chroot-available` says the
#     running release has no chroot -> a clear "Omedora doesn't support
#     Fedora N yet; nothing was changed" message instead of dnf's error, and
#     no package transaction
#   - the probe couldn't check -> dnf's own error plus a generic message
#   - the probe never runs on the happy path, nor for an overridden project
#   - after a successful update, Omedora packages still tagged for an older
#     Fedora are listed as a warning (omedora-upgrade-fedora --post-check),
#     without failing the update
#
# Everything external is stubbed on PATH (style: test/update-flow-test.sh).

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SCRATCH="$(mktemp -d)"
trap '[[ -n $SCRATCH && -d $SCRATCH ]] && rm -rf "$SCRATCH"' EXIT

SHIM="$SCRATCH/shim"
mkdir -p "$SHIM"
MOCK_LOG="$SCRATCH/mock.log"
export MOCK_LOG
# The updater scopes dnf with systemd-run on a systemd-booted host; keep these
# fixtures host-independent (update-flow-test.sh covers the scope contract).
export OMEDORA_SYSTEMD_RUNTIME_DIR="$SCRATCH/not-booted"

stub() { printf '#!/bin/bash\n%s\n' "$2" >"$SHIM/$1"; chmod +x "$SHIM/$1"; }

stub sudo 'printf "sudo %s\n" "$*" >>"$MOCK_LOG"; "$@"'
cat >"$SHIM/dnf" <<'EOF'
#!/bin/bash
printf 'dnf %s\n' "$*" >>"$MOCK_LOG"
case "$1" in
  copr)
    if [[ ${COPR_FAIL:-0} == 1 ]]; then
      echo "Chroot not found in the given Copr project (fedora-46-x86_64)." >&2
      exit 1
    fi
    echo "Enabling a Copr repository."
    ;;
  repoquery)
    if [[ " $* " == *" --installed "* ]]; then
      printf '%s\n' "${INSTALLED:-}"
    else
      printf 'base-rpm\n'
    fi
    ;;
esac
exit 0
EOF
chmod +x "$SHIM/dnf"
cat >"$SHIM/omedora-copr" <<'EOF'
#!/bin/bash
printf 'omedora-copr %s\n' "$*" >>"$MOCK_LOG"
case "${1:-}" in
  --repo-id) echo "copr:copr.fedorainfracloud.org:agaspar:omedora-4" ;;
  --chroot-available)
    [[ -n ${PROBE_ERR:-} ]] && printf '%s\n' "$PROBE_ERR" >&2
    exit "${PROBE_RC:-0}"
    ;;
  "") echo "agaspar/omedora-4" ;;
esac
EOF
chmod +x "$SHIM/omedora-copr"

RESOLVER="$SCRATCH/resolver"
printf '#!/bin/bash\nprintf "base-rpm\\n"\n' >"$RESOLVER"
chmod +x "$RESOLVER"

OS_F46="$SCRATCH/os-release-46"
printf 'ID=fedora\nVERSION_ID=46\n' >"$OS_F46"
OS_F45="$SCRATCH/os-release-45"
printf 'ID=fedora\nVERSION_ID=45\n' >"$OS_F45"

export PATH="$SHIM:$ROOT/bin:$PATH"
export OMARCHY_DISTRO=fedora
export OMEDORA_MANAGED_RESOLVER="$RESOLVER"

# update [env...] — run the updater; sets update_rc / update_out
update() {
  : >"$MOCK_LOG"
  update_rc=0
  update_out=$(env "$@" bash "$ROOT/bin/omarchy-update-system-pkgs" 2>&1) || update_rc=$?
}

echo "# --- no chroot for the running release ---"

update OMEDORA_OS_RELEASE="$OS_F46" COPR_FAIL=1 PROBE_RC=1 \
  PROBE_ERR="omedora-copr: agaspar/omedora-4 has no fedora-46-x86_64 chroot; available Fedora releases: 44 45"
(( update_rc != 0 )) && pass "an unsupported release fails the update" \
  || fail "an unsupported release fails the update"
assert_output_contains "the message names the release and the COPR" \
  "$update_out" "Omedora doesn't support Fedora 46 yet: agaspar/omedora-4 has no packages built for it."
assert_output_contains "the message relays the supported releases" \
  "$update_out" "available Fedora releases: 44 45"
assert_output_contains "the message says nothing was changed" "$update_out" "Nothing was changed"
assert_output_contains "the message points at the release upgrader" "$update_out" "omedora-upgrade-fedora"
assert_output_lacks "dnf's raw chroot error is replaced by the explanation" \
  "$update_out" "Chroot not found in the given Copr project"
assert_output_contains "the diagnosis probes the running release" \
  "$(cat "$MOCK_LOG")" "omedora-copr --chroot-available"
grep -qE '^dnf (install|reinstall|upgrade|distro-sync)' "$MOCK_LOG" \
  && { cat "$MOCK_LOG" >&2; fail "an unsupported release reaches no package transaction"; } \
  || pass "an unsupported release reaches no package transaction"

echo "# --- COPR enable fails for another reason ---"

update OMEDORA_OS_RELEASE="$OS_F46" COPR_FAIL=1 PROBE_RC=2 \
  PROBE_ERR="omedora-copr: could not reach the COPR API to check for fedora-46-x86_64"
(( update_rc != 0 )) && pass "an unverifiable COPR failure still fails the update" \
  || fail "an unverifiable COPR failure still fails the update"
assert_output_contains "dnf's own error is shown when the cause is unknown" \
  "$update_out" "Chroot not found in the given Copr project"
assert_output_contains "a generic message says no transaction was attempted" \
  "$update_out" "no package transaction was attempted"
assert_output_lacks "an unknown cause isn't blamed on the release" "$update_out" "doesn't support Fedora"

update OMEDORA_OS_RELEASE="$OS_F46" COPR_FAIL=1 PROBE_RC=1 OMEDORA_COPR_PROJECT="test/omedora-4" \
  OMEDORA_COPR_REPO_ID="test-omedora-4"
(( update_rc != 0 )) && pass "an overridden project's enable failure fails the update" \
  || fail "an overridden project's enable failure fails the update"
assert_output_lacks "an overridden project is never probed" "$(cat "$MOCK_LOG")" "--chroot-available"

echo "# --- happy path ---"

update OMEDORA_OS_RELEASE="$OS_F45" PROBE_RC=1 \
  INSTALLED=$'hyprland-no-session 0.56.2-1.fc45 copr:copr.fedorainfracloud.org:agaspar:omedora-4'
assert_equals "a supported release updates normally" "$update_rc" "0"
assert_output_lacks "the probe never runs when the COPR enables" "$(cat "$MOCK_LOG")" "--chroot-available"
assert_output_contains "the managed transaction runs" "$(cat "$MOCK_LOG")" "dnf install --refresh -y"
assert_output_contains "the COPR enable output is still shown" "$update_out" "Enabling a Copr repository."
assert_output_lacks "current-release builds raise no rebuild warning" "$update_out" "older Fedora"

echo "# --- post-transaction rebuild check ---"

update OMEDORA_OS_RELEASE="$OS_F45" \
  INSTALLED=$'hyprland-no-session 0.56.2-1.fc44 copr:copr.fedorainfracloud.org:agaspar:omedora-4\nquickshell 0.3.2-1.fc45 copr:copr.fedorainfracloud.org:agaspar:omedora-4\nbash 5.3-1.fc44 fedora'
assert_equals "stale Omedora builds don't fail the update" "$update_rc" "0"
assert_output_contains "a stale Omedora build is listed" "$update_out" "hyprland-no-session-0.56.2-1.fc44"
assert_output_lacks "a current Omedora build isn't listed" "$update_out" "quickshell-0.3.2"
assert_output_lacks "a non-Omedora package isn't listed" "$update_out" "bash-5.3"
assert_output_contains "the warning says how to pick up the rebuilds" \
  "$update_out" "sudo dnf upgrade --refresh hyprland-no-session"
