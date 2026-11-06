#!/bin/bash
#
# L1 unit test for the Fedora updater's managed-candidate check
# (bin/fedora/update-system-pkgs, verify_managed_candidates): a managed target
# can be arch-qualified (the lib32 map entries resolve to
# mesa-vulkan-drivers.i686), and dnf reports such a candidate by name, so the
# check must accept it instead of refusing the update as a stale no-op. A
# target no enabled repository provides must still be refused.
#
# Everything external is stubbed on PATH (style: test/update-unsupported-release-test.sh).

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SCRATCH="$(mktemp -d)"
trap '[[ -n $SCRATCH && -d $SCRATCH ]] && rm -rf "$SCRATCH"' EXIT

SHIM="$SCRATCH/shim"
mkdir -p "$SHIM"
MOCK_LOG="$SCRATCH/mock.log"
export MOCK_LOG
export OMEDORA_SYSTEMD_RUNTIME_DIR="$SCRATCH/not-booted"

stub() { printf '#!/bin/bash\n%s\n' "$2" >"$SHIM/$1"; chmod +x "$SHIM/$1"; }

stub sudo 'printf "sudo %s\n" "$*" >>"$MOCK_LOG"; "$@"'
# dnf repoquery --available formats each candidate through --qf the way dnf5
# does: %{name} is the bare name, also for an arch-qualified request.
cat >"$SHIM/dnf" <<'EOF2'
#!/bin/bash
printf 'dnf %s\n' "$*" >>"$MOCK_LOG"
case "$1" in
  copr) echo "Enabling a Copr repository." ;;
  repoquery)
    shift
    if [[ " $* " == *" --installed "* ]]; then
      printf '%s\n' "${INSTALLED:-}"
      exit 0
    fi
    qf='%{name}\n'
    specs=()
    while (( $# )); do
      case "$1" in
        --qf) qf=$2; shift ;;
        --repo) shift ;;
        -*) ;;
        *) specs+=("$1") ;;
      esac
      shift
    done
    for spec in "${specs[@]}"; do
      [[ " ${UNAVAILABLE:-} " == *" $spec "* ]] && continue
      name=$spec arch=x86_64
      if [[ $spec =~ ^(.+)\.(i686|x86_64|noarch)$ ]]; then
        name=${BASH_REMATCH[1]} arch=${BASH_REMATCH[2]}
      fi
      out=${qf//'%{name}'/$name}
      printf '%b' "${out//'%{arch}'/$arch}"
    done
    ;;
esac
exit 0
EOF2
chmod +x "$SHIM/dnf"
cat >"$SHIM/omedora-copr" <<'EOF2'
#!/bin/bash
case "${1:-}" in
  --repo-id) echo "copr:copr.fedorainfracloud.org:agaspar:omedora-4" ;;
  --chroot-available) exit 0 ;;
  "") echo "agaspar/omedora-4" ;;
esac
EOF2
chmod +x "$SHIM/omedora-copr"

RESOLVER="$SCRATCH/resolver"
printf '#!/bin/bash\nprintf "%%s\\n" $MANAGED\n' >"$RESOLVER"
chmod +x "$RESOLVER"

OS_F45="$SCRATCH/os-release-45"
printf 'ID=fedora\nVERSION_ID=45\n' >"$OS_F45"

export PATH="$SHIM:$ROOT/bin:$PATH"
export OMARCHY_DISTRO=fedora
export OMEDORA_MANAGED_RESOLVER="$RESOLVER"

update() {
  : >"$MOCK_LOG"
  update_rc=0
  update_out=$(env OMEDORA_OS_RELEASE="$OS_F45" "$@" bash "$ROOT/bin/omarchy-update-system-pkgs" 2>&1) || update_rc=$?
}

echo "# --- an arch-qualified managed target ---"

update MANAGED="base-rpm mesa-vulkan-drivers.i686"
assert_equals "an available arch-qualified target updates normally" "$update_rc" "0"
assert_output_lacks "it is not refused as a stale no-op" "$update_out" "refusing a stale no-op update"
assert_output_contains "the managed transaction runs" "$(cat "$MOCK_LOG")" "dnf install --refresh -y"
assert_output_contains "the arch-qualified target is in the transaction" \
  "$(grep '^dnf install' "$MOCK_LOG")" "mesa-vulkan-drivers.i686"

echo "# --- a managed target no repository provides ---"

update MANAGED="base-rpm mesa-vulkan-drivers.i686" UNAVAILABLE="mesa-vulkan-drivers.i686"
(( update_rc != 0 )) && pass "an unavailable arch-qualified target still fails the update" \
  || fail "an unavailable arch-qualified target still fails the update"
assert_output_contains "the refusal names the target" "$update_out" \
  "No enabled repository provides managed package 'mesa-vulkan-drivers.i686'"

update MANAGED="base-rpm gone-rpm" UNAVAILABLE="gone-rpm"
(( update_rc != 0 )) && pass "an unavailable plain target still fails the update" \
  || fail "an unavailable plain target still fails the update"
grep -qE '^dnf install --refresh' "$MOCK_LOG" \
  && fail "a refused update reaches no managed transaction" \
  || pass "a refused update reaches no managed transaction"
