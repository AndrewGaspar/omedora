#!/bin/bash
#
# L1 unit tests for bin/omedora-upgrade-fedora (in-place Fedora release
# upgrade guarded against breaking Omedora).
#
#   PART 1 — guards: non-Fedora, target not newer, default target = N+1.
#   PART 2 — preflight decisions against canned dnf5 dry-run transactions:
#            no chroot (refuse, no dry run), unverifiable chroot (refuse),
#            Omedora package removed / downgraded (refuse, listed), solver
#            failure (refuse), other packages removed (refuse unless
#            --allowerasing), clean (pass), not-yet-rebuilt (warn), the
#            harness repo omedora-local counts as Omedora's, and --check
#            never changes anything.
#   PART 3 — the upgrade itself: snapshot, dnf upgrade, system-upgrade
#            download, offline reboot, in order; --allowerasing only when
#            asked; a declined reboot prompt doesn't reboot.
#   PART 4 — --post-check: older dist tags on Omedora packages are listed.
#
# Everything external is stubbed on PATH (style: test/update-flow-test.sh).

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

UPGRADE="$ROOT/bin/omedora-upgrade-fedora"

SCRATCH="$(mktemp -d)"
trap '[[ -n $SCRATCH && -d $SCRATCH ]] && rm -rf "$SCRATCH"' EXIT

SHIM="$SCRATCH/shim"
mkdir -p "$SHIM"
MOCK_LOG="$SCRATCH/mock.log"
export MOCK_LOG

COPR_ID="copr:copr.fedorainfracloud.org:agaspar:omedora-4"

stub() { printf '#!/bin/bash\n%s\n' "$2" >"$SHIM/$1"; chmod +x "$SHIM/$1"; }

# dnf: the dry run prints $DRYRUN (a file) and exits 1 like `--assumeno`;
# `repoquery --installed` prints $INSTALLED; everything else just logs.
cat >"$SHIM/dnf" <<'EOF'
#!/bin/bash
printf 'dnf %s\n' "$*" >>"$MOCK_LOG"
case " $* " in
  *" distro-sync "*)
    cat "$DRYRUN"
    [[ ${DRYRUN_RC:-1} == 0 ]] || exit "${DRYRUN_RC:-1}"
    ;;
  *" repoquery "*)
    printf '%s\n' "${INSTALLED:-}"
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
stub omedora-snapshot 'printf "omedora-snapshot %s\n" "$*" >>"$MOCK_LOG"'
stub findmnt 'echo "${ROOT_FSTYPE:-ext4}"'
# gum reads the answer from stdin (prompts come from stdin in tests).
stub gum 'read -r answer || answer=n; [[ $answer == y ]]'

export PATH="$SHIM:$PATH"
export OMEDORA_DNF_CMD="dnf"
export OMEDORA_UPGRADE_PROMPT_STDIN=1

OS_F44="$SCRATCH/os-release-44"
printf 'NAME="Fedora Linux"\nID=fedora\nVERSION_ID=44\n' >"$OS_F44"
OS_F45="$SCRATCH/os-release-45"
printf 'NAME="Fedora Linux"\nID=fedora\nVERSION_ID=45\n' >"$OS_F45"
OS_UBUNTU="$SCRATCH/os-release-ubuntu"
printf 'ID=ubuntu\nVERSION_ID="24.04"\n' >"$OS_UBUNTU"
export OMEDORA_OS_RELEASE="$OS_F44"

INSTALLED_DEFAULT="hyprland-no-session 0.56.2-1.fc44 $COPR_ID
quickshell 0.3.2-1.fc44 $COPR_ID
hyprutils 0.14.0-1.fc44 $COPR_ID
bash 5.3.0-2.fc44 updates"
export INSTALLED="$INSTALLED_DEFAULT"

# Canned dnf5 dry-run transactions, in dnf5's table layout.
HEADER='Updating and loading repositories:
Repositories loaded.
Package                     Arch   Version              Repository                                          Size'
SUMMARY='
Transaction Summary:
 Upgrading:          3 packages
 Replacing:          3 packages

Total size of inbound packages is 80 MiB. Need to download 80 MiB.
Operation aborted by the user.'

CLEAN="$SCRATCH/dryrun-clean"
cat >"$CLEAN" <<EOF
$HEADER
Upgrading:
 bash                       x86_64 0:5.3.0-4.fc45       fedora                                              8.1 MiB
   replacing bash           x86_64 0:5.3.0-2.fc44       updates                                             8.1 MiB
 hyprland-no-session        x86_64 0:0.56.2-1.fc45      $COPR_ID  66.5 MiB
   replacing hyprland-no-session x86_64 0:0.56.2-1.fc44 $COPR_ID  66.5 MiB
 hyprutils                  x86_64 0:0.14.0-1.fc45      $COPR_ID 394.9 KiB
   replacing hyprutils      x86_64 0:0.14.0-1.fc44      $COPR_ID 394.9 KiB
 quickshell                 x86_64 0:0.3.2-1.fc45       $COPR_ID   6.2 MiB
   replacing quickshell     x86_64 0:0.3.2-1.fc44       $COPR_ID   6.2 MiB
Downgrading:
 ca-certificates            noarch 0:2026.2.90-1.fc45   fedora                                              2.6 MiB
   replacing ca-certificates noarch 0:2026.3.1-1.fc44   updates                                             2.6 MiB
$SUMMARY
EOF

BROKEN="$SCRATCH/dryrun-broken"
cat >"$BROKEN" <<EOF
$HEADER
Removing dependent packages:
 hyprland-no-session        x86_64 0:0.56.2-1.fc44      $COPR_ID  66.5 MiB
Downgrading:
 hyprutils                  x86_64 0:0.7.1-4.fc43       fedora                                            245.7 KiB
   replacing hyprutils      x86_64 0:0.14.0-1.fc44      $COPR_ID 394.9 KiB
 quickshell                 x86_64 0:0.2.1^git20260209.dacfa9d-5.fc45 fedora                            5.7 MiB
   replacing quickshell     x86_64 0:0.3.2-1.fc44       $COPR_ID   6.2 MiB
Upgrading:
 bash                       x86_64 0:5.3.0-4.fc45       fedora                                              8.1 MiB
   replacing bash           x86_64 0:5.3.0-2.fc44       updates                                             8.1 MiB
$SUMMARY
EOF

OTHER_REMOVED="$SCRATCH/dryrun-other-removed"
cat >"$OTHER_REMOVED" <<EOF
$HEADER
Removing dependent packages:
 legacy-tool                x86_64 0:1.0-1.fc44         @commandline                                        1.0 MiB
$(sed -n '/^Upgrading:/,/^Downgrading:/p' "$CLEAN" | sed '$d')
$SUMMARY
EOF

UNRESOLVED="$SCRATCH/dryrun-unresolved"
cat >"$UNRESOLVED" <<'EOF'
Updating and loading repositories:
Repositories loaded.
Failed to resolve the transaction:
Problem 1: installed package aquamarine-0.14.0-1.fc44.x86_64 requires libhyprutils.so.13()(64bit), but none of the providers can be installed
  - problem with installed package
You can try to add to command line:
  --skip-broken to skip uninstallable packages
EOF

NOT_REBUILT="$SCRATCH/dryrun-not-rebuilt"
grep -v -e '^ quickshell' -e '^   replacing quickshell' "$CLEAN" >"$NOT_REBUILT"

# run [env...] -- [args...] — sets run_rc / run_out; resets the mock log
run() {
  local -a envs=()
  while (( $# )) && [[ $1 != "--" ]]; do envs+=("$1"); shift; done
  [[ ${1:-} == "--" ]] && shift
  : >"$MOCK_LOG"
  run_rc=0
  run_out=$(env "${envs[@]}" bash "$UPGRADE" "$@" </dev/null 2>&1) || run_rc=$?
}

mutations() { grep -E '^dnf (upgrade|system-upgrade|offline)|^omedora-snapshot' "$MOCK_LOG" || true; }

# ===========================================================================
echo "# --- PART 1: guards ---"
# ===========================================================================

run OMEDORA_OS_RELEASE="$OS_UBUNTU" DRYRUN="$CLEAN" -- --check
assert_equals "a non-Fedora host is refused" "$run_rc" "1"
assert_output_contains "the refusal says Fedora only" "$run_out" "only supported on Fedora"

run DRYRUN="$CLEAN" -- --check --releasever 44
assert_equals "the running release is not an upgrade target" "$run_rc" "1"
assert_output_contains "a non-newer target is explained" "$run_out" "is not newer than the running Fedora 44"

run DRYRUN="$CLEAN" -- --check --releasever abc
assert_equals "a non-numeric target is refused" "$run_rc" "1"

run DRYRUN="$CLEAN" -- --check
assert_output_contains "the target defaults to the next release" \
  "$(cat "$MOCK_LOG")" "omedora-copr --chroot-available 45"

run DRYRUN="$CLEAN" -- --bogus
assert_equals "an unknown option is refused" "$run_rc" "1"

# ===========================================================================
echo "# --- PART 2: preflight decisions ---"
# ===========================================================================

run DRYRUN="$CLEAN" PROBE_RC=1 \
  PROBE_ERR="omedora-copr: agaspar/omedora-4 has no fedora-46-x86_64 chroot; available Fedora releases: 44 45" \
  -- --check --releasever 46
assert_equals "a target without a COPR chroot is refused" "$run_rc" "1"
assert_output_contains "the refusal names the unsupported target" "$run_out" "doesn't support Fedora 46 yet"
assert_output_contains "the refusal relays the supported releases" "$run_out" "available Fedora releases: 44 45"
assert_output_lacks "no dry run without a chroot" "$(cat "$MOCK_LOG")" "distro-sync"

run DRYRUN="$CLEAN" PROBE_RC=2 -- --check
assert_equals "an unverifiable chroot is refused (fails closed)" "$run_rc" "1"
assert_output_contains "the unverifiable refusal says so" "$run_out" "Couldn't verify"
assert_output_lacks "no dry run when the chroot can't be verified" "$(cat "$MOCK_LOG")" "distro-sync"

run DRYRUN="$BROKEN" -- --check
assert_equals "a dry run that removes/downgrades Omedora packages is refused" "$run_rc" "1"
assert_output_contains "a removed Omedora package is listed" "$run_out" "hyprland-no-session-0.56.2-1.fc44"
assert_output_contains "removals are labelled" "$run_out" "would REMOVE"
assert_output_contains "a downgraded Omedora package is listed with its replacement" \
  "$run_out" "quickshell-0.3.2-1.fc44 -> 0.2.1^git20260209.dacfa9d-5.fc45 (fedora)"
assert_output_contains "downgrades are labelled" "$run_out" "would DOWNGRADE"
assert_output_lacks "a non-Omedora upgrade isn't reported" "$run_out" "bash-5.3"
assert_output_contains "the dry run targets the requested release" \
  "$(cat "$MOCK_LOG")" "dnf --releasever=45 distro-sync --refresh --assumeno --allowerasing"
assert_equals "a refused preflight changes nothing" "$(mutations)" ""

run DRYRUN="$UNRESOLVED" -- --check
assert_equals "an unresolvable dry run is refused" "$run_rc" "1"
assert_output_contains "the solver problems are shown" "$run_out" "Problem 1: installed package aquamarine"

printf 'Updating and loading repositories:\nCurl error (6): Could not resolve host\n' >"$SCRATCH/dryrun-error"
run DRYRUN="$SCRATCH/dryrun-error" -- --check
assert_equals "a dry run that never produced a transaction is refused" "$run_rc" "1"

run DRYRUN="$OTHER_REMOVED" -- --check
assert_equals "removing non-Omedora packages needs --allowerasing" "$run_rc" "1"
assert_output_contains "the blocking package is listed with its repo" "$run_out" "legacy-tool-1.0-1.fc44 (@commandline)"
assert_output_contains "the refusal suggests --allowerasing" "$run_out" "--allowerasing"

run DRYRUN="$OTHER_REMOVED" -- --check --allowerasing
assert_equals "--allowerasing accepts non-Omedora removals" "$run_rc" "0"

run DRYRUN="$CLEAN" -- --check
assert_equals "a clean dry run passes the preflight" "$run_rc" "0"
assert_output_contains "the pass counts the kept Omedora packages" "$run_out" "keeps all 3 installed Omedora packages"
assert_output_lacks "a clean dry run warns about nothing" "$run_out" "Warning"
assert_equals "--check changes nothing" "$(mutations)" ""

run DRYRUN="$NOT_REBUILT" -- --check
assert_equals "a missing rebuild alone doesn't refuse" "$run_rc" "0"
assert_output_contains "a missing rebuild is warned about" "$run_out" "No Fedora 45 build yet"
assert_output_contains "the package without a rebuild is named" "$run_out" "quickshell-0.3.2-1.fc44"

LOCAL_BROKEN="$SCRATCH/dryrun-local"
sed "s/$COPR_ID/omedora-local/g" "$BROKEN" >"$LOCAL_BROKEN"
run DRYRUN="$LOCAL_BROKEN" INSTALLED="${INSTALLED_DEFAULT//$COPR_ID/omedora-local}" -- --check
assert_equals "the harness repo omedora-local counts as Omedora's" "$run_rc" "1"
assert_output_contains "an omedora-local removal is listed" "$run_out" "hyprland-no-session-0.56.2-1.fc44"

# ===========================================================================
echo "# --- PART 3: the upgrade ---"
# ===========================================================================

run DRYRUN="$CLEAN" ROOT_FSTYPE=btrfs -- --yes
assert_equals "an unattended upgrade completes" "$run_rc" "0"
order=$(grep -E '^dnf (upgrade|system-upgrade|offline)|^omedora-snapshot|distro-sync' "$MOCK_LOG" | sed -E 's/^(dnf (--releasever=45 )?[a-z-]+|omedora-snapshot).*/\1/')
assert_equals "preflight, snapshot, update, download, reboot run in order" "$order" \
"dnf --releasever=45 distro-sync
omedora-snapshot
dnf upgrade
dnf system-upgrade
dnf offline"
assert_output_contains "the snapshot is labelled for the target" "$(cat "$MOCK_LOG")" "omedora-snapshot create pre-fedora-45"
assert_output_contains "the running release is updated first" "$(cat "$MOCK_LOG")" "dnf upgrade --refresh -y"
assert_output_contains "the download targets the release" \
  "$(cat "$MOCK_LOG")" "dnf system-upgrade download --releasever=45 -y"
assert_output_lacks "the download never adds --allowerasing on its own" \
  "$(grep 'system-upgrade' "$MOCK_LOG")" "--allowerasing"
assert_output_contains "--yes reboots into the offline upgrade" "$(cat "$MOCK_LOG")" "dnf offline reboot -y"
assert_output_contains "the /boot caveat is printed" "$run_out" "not /boot"

run DRYRUN="$OTHER_REMOVED" -- --yes --allowerasing --no-snapshot
assert_equals "an --allowerasing upgrade completes" "$run_rc" "0"
assert_output_contains "--allowerasing reaches the download" \
  "$(cat "$MOCK_LOG")" "dnf system-upgrade download --releasever=45 --allowerasing -y"
assert_output_lacks "--no-snapshot takes no snapshot" "$(cat "$MOCK_LOG")" "omedora-snapshot"

: >"$MOCK_LOG"
run_rc=0
run_out=$(printf 'y\nn\n' | env DRYRUN="$CLEAN" ROOT_FSTYPE=ext4 bash "$UPGRADE" 2>&1) || run_rc=$?
assert_equals "an interactive upgrade with a declined reboot exits 0" "$run_rc" "0"
assert_output_contains "the upgrade is downloaded after the confirmation" "$(cat "$MOCK_LOG")" "dnf system-upgrade download --releasever=45"
assert_output_lacks "a declined reboot prompt doesn't reboot" "$(cat "$MOCK_LOG")" "offline reboot"
assert_output_contains "a declined reboot says how to reboot later" "$run_out" "sudo dnf offline reboot"
assert_output_lacks "a non-btrfs root offers no snapshot" "$(cat "$MOCK_LOG")" "omedora-snapshot"

: >"$MOCK_LOG"
run_rc=0
run_out=$(printf 'n\n' | env DRYRUN="$CLEAN" bash "$UPGRADE" 2>&1) || run_rc=$?
assert_equals "declining the upgrade exits 1" "$run_rc" "1"
assert_equals "declining the upgrade changes nothing" "$(mutations)" ""

: >"$MOCK_LOG"
run_rc=0
run_out=$(env -u OMEDORA_UPGRADE_PROMPT_STDIN DRYRUN="$CLEAN" setsid -w bash "$UPGRADE" </dev/null 2>&1) || run_rc=$?
assert_equals "no terminal and no --yes refuses" "$run_rc" "1"
assert_output_contains "the no-terminal refusal suggests --yes" "$run_out" "--yes"
assert_equals "the no-terminal refusal changes nothing" "$(mutations)" ""

# ===========================================================================
echo "# --- PART 4: --post-check ---"
# ===========================================================================

run OMEDORA_OS_RELEASE="$OS_F45" -- --post-check
assert_equals "old-release Omedora builds fail the post-check" "$run_rc" "1"
assert_output_contains "a stale Omedora build is listed" "$run_out" "hyprutils-0.14.0-1.fc44"
assert_output_lacks "a non-Omedora package is never listed" "$run_out" "bash-5.3"
assert_output_contains "the post-check suggests picking up rebuilds" \
  "$run_out" "sudo dnf upgrade --refresh hyprland-no-session hyprutils quickshell"
assert_equals "the post-check changes nothing" "$(mutations)" ""

run OMEDORA_OS_RELEASE="$OS_F44" -- --post-check
assert_equals "current-release builds pass the post-check" "$run_rc" "0"
assert_equals "a clean post-check is silent" "$run_out" ""

run OMEDORA_OS_RELEASE="$OS_UBUNTU" -- --post-check
assert_equals "the post-check is a no-op off Fedora" "$run_rc" "0"

run OMEDORA_OS_RELEASE="$OS_F45" OMEDORA_COPR_REPO_ID="other-repo" -- --post-check
assert_equals "OMEDORA_COPR_REPO_ID selects the repo to check" "$run_rc" "0"
