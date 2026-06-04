#!/bin/bash
#
# L3 real-dnf test: foreign-repo package REPLACEMENT (omedora doctor --fix).
#
# Proves the replacement engine (bin/omedora-replace-foreign) works through REAL
# dnf5 against the LIVE COPRs — the part the unit test (coexistence-replace-test.sh)
# cannot cover because it stubs dnf with a logger. It exercises the actual
# `dnf swap` file-conflict resolution and provenance move:
#
#   1. Install a real FOREIGN Hyprland from lionheartp/Hyprland (omedora's old
#      upstream COPR) — a genuine third-party `hyprland` that owns /usr/bin/Hyprland.
#   2. `omarchy-doctor` must DETECT it as foreign-repo (real `dnf repoquery`).
#   3. `omedora-replace-foreign --yes` must `dnf swap` it for omedora's
#      hyprland-omedora (+ hyprland-no-session, which owns the same binary) from
#      agaspar/omedora-3.8.2, resolving the file conflict atomically.
#   4. After: the foreign `hyprland` is gone, hyprland-omedora + hyprland-no-session
#      are installed FROM the omedora COPR, /usr/bin/Hyprland is owned by
#      hyprland-no-session, and the doctor no longer flags hyprland.
#
# This is the test that caught two real bugs the mocked unit test masked:
#   - omarchy-doctor's repoquery --qf was missing '\n' (dnf5 emits one blob -> the
#     scan loop never ran -> every machine reported "clean").
#   - the engine passed --disablerepo for a non-enabled (historical) repo id,
#     which dnf5 hard-errors on.
#
# SLOW + needs network + the live COPRs (installs ~65 MB foreign Hyprland, then a
# ~51 MB omedora swap). NOT part of the fast L1 CI; run on demand / nightly:
#
#   omedora/test/fedora/replace-foreign-test.sh
#   omedora/test/fedora/replace-foreign-test.sh --keep   # leave the container up
#
# Host is Arch — uses a throwaway podman fedora:44 container (no systemd/DRM
# needed; this is pure package management).

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
FOREIGN_COPR="${REPLACE_FOREIGN_COPR:-lionheartp/Hyprland}"
OMEDORA_COPR="${REPLACE_OMEDORA_COPR:-$(OMARCHY_PATH="$REPO" "$REPO/bin/omedora-copr")}"
FOREIGN_REPO_ID="copr:copr.fedorainfracloud.org:${FOREIGN_COPR/\//:}"
OMEDORA_REPO_ID="copr:copr.fedorainfracloud.org:${OMEDORA_COPR/\//:}"
CTR="${REPLACE_FOREIGN_CTR:-omedora-replace-foreign-$$}"

export TMPDIR="${TMPDIR:-/var/tmp/podman-tmp}"
mkdir -p "$TMPDIR" 2>/dev/null || true

keep=false
for arg in "$@"; do
  case "$arg" in
    --keep) keep=true ;;
    --help|-h) grep '^# ' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

log() { printf '\033[1;34m[replace]\033[0m %s\n' "$*"; }

cleanup() {
  if $keep; then
    log "Container '$CTR' left running (--keep). Remove: podman rm -f $CTR"
  else
    podman rm -f "$CTR" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

# --- TAP-ish assertions on the running container -----------------------------
n=0; passed=0; failed=0; failed_names=()
ok()  { n=$((n+1)); passed=$((passed+1)); echo "ok $n - $1"; }
nok() { n=$((n+1)); failed=$((failed+1)); failed_names+=("$1"); echo "not ok $n - $1"; [[ -n ${2:-} ]] && printf '%s\n' "$2" | sed 's/^/    /'; }
# in_ctr: run a command in the container as root with the omedora env set.
in_ctr() { podman exec \
  -e OMARCHY_DISTRO=fedora -e OMARCHY_PATH=/repo -e OMARCHY_INSTALL=/repo/install \
  -e PATH=/repo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  -e OMEDORA_DNF_CMD=dnf "$CTR" bash -c "$1"; }

log "Starting fedora:44 container '$CTR'..."
podman rm -f "$CTR" >/dev/null 2>&1 || true
podman run -d --name "$CTR" -v "$REPO:/repo:ro" registry.fedoraproject.org/fedora:44 sleep infinity >/dev/null

log "Enabling COPRs + installing the FOREIGN Hyprland (from $FOREIGN_COPR)..."
in_ctr '
set -e
dnf install -y dnf-plugins-core >/dev/null 2>&1
dnf -y copr enable '"$OMEDORA_COPR"' >/dev/null 2>&1
dnf -y copr enable '"$FOREIGN_COPR"' >/dev/null 2>&1
# Force foreign provenance: disable the omedora COPR for this install so plain
# `hyprland` resolves from the foreign COPR (both ship hyprland 0.55.2).
dnf install -y --setopt=install_weak_deps=False \
  --disablerepo='"$OMEDORA_REPO_ID"' \
  hyprland >/dev/null 2>&1
' || { echo "Bail out! foreign hyprland install failed"; exit 1; }

# 1) Foreign hyprland is installed from the foreign COPR.
prov="$(in_ctr 'dnf -q repoquery --installed hyprland --qf "%{from_repo}" 2>/dev/null')"
[[ "$prov" == "$FOREIGN_REPO_ID" ]] \
  && ok "foreign hyprland installed from $FOREIGN_COPR" \
  || nok "foreign hyprland installed from $FOREIGN_COPR" "got: $prov"

# 2) The doctor detects it (real dnf repoquery) — exit 1 + names hyprland.
det="$(in_ctr 'omarchy-doctor --list 2>/dev/null')"
echo "$det" | grep -q "^hyprland	$FOREIGN_REPO_ID$" \
  && ok "omarchy-doctor --list flags the foreign hyprland" \
  || nok "omarchy-doctor --list flags the foreign hyprland" "list: $det"

# 3) Run the real replacement.
log "Running the real swap (omedora-replace-foreign --yes)..."
in_ctr 'omedora-replace-foreign --yes >/tmp/replace.log 2>&1' \
  && ok "omedora-replace-foreign --yes exits 0" \
  || nok "omedora-replace-foreign --yes exits 0" "$(in_ctr 'tail -20 /tmp/replace.log')"

# 4) Foreign hyprland is gone.
in_ctr 'rpm -q hyprland >/dev/null 2>&1' \
  && nok "foreign hyprland removed" "hyprland still installed" \
  || ok "foreign hyprland removed"

# 5) omedora's packages are installed FROM the omedora COPR.
for p in hyprland-omedora hyprland-no-session; do
  pr="$(in_ctr "dnf -q repoquery --installed $p --qf '%{from_repo}' 2>/dev/null")"
  [[ "$pr" == "$OMEDORA_REPO_ID" ]] \
    && ok "$p installed from the omedora COPR" \
    || nok "$p installed from the omedora COPR" "got: ${pr:-<not installed>}"
done

# 6) The compositor binary is now owned by omedora's hyprland-no-session.
owner="$(in_ctr 'rpm -qf /usr/bin/Hyprland 2>/dev/null')"
[[ "$owner" == hyprland-no-session-* ]] \
  && ok "/usr/bin/Hyprland owned by hyprland-no-session (swap resolved the file conflict)" \
  || nok "/usr/bin/Hyprland owned by hyprland-no-session" "owner: $owner"

# 7) The doctor no longer flags hyprland (libyaml etc. container-base artifacts
#    may remain; we assert specifically that hyprland is resolved).
post="$(in_ctr 'omarchy-doctor --list 2>/dev/null')"
echo "$post" | grep -q "^hyprland	" \
  && nok "doctor no longer flags hyprland after replacement" "still: $post" \
  || ok "doctor no longer flags hyprland after replacement"

# --- summary -----------------------------------------------------------------
echo
echo "1..$n"
echo "# pass $passed / fail $failed"
if (( failed > 0 )); then
  echo "# failed: ${failed_names[*]}"
  exit 1
fi
log "all $passed assertions passed"
exit 0
