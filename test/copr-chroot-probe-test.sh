#!/bin/bash
#
# L1 unit tests for `omedora-copr --chroot-available [RELEASE]`, the probe the
# install gate, the updater and omedora-upgrade-fedora use to ask "does the
# Omedora COPR build for this Fedora release?". Exit-status contract:
#   0 = the project has fedora-RELEASE-ARCH
#   1 = it does not (available releases on stderr), or the project is missing
#   2 = could not check (network/API error, bad reply, no Fedora release)
#
# Offline: answers come from the OMEDORA_COPR_API_FIXTURE seam, or from a curl
# stub on PATH to exercise the real HTTP status handling.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

PROBE="$ROOT/bin/omedora-copr"

SCRATCH="$(mktemp -d)"
trap '[[ -n $SCRATCH && -d $SCRATCH ]] && rm -rf "$SCRATCH"' EXIT

SHIM="$SCRATCH/shim"
mkdir -p "$SHIM"
CURL_LOG="$SCRATCH/curl.log"
export CURL_LOG

FIXTURE="$SCRATCH/project.json"
cat >"$FIXTURE" <<'EOF'
{"name": "omedora-4", "full_name": "agaspar/omedora-4", "repo_priority": 90,
 "chroot_repos": {
   "fedora-44-x86_64": "https://download.copr.fedorainfracloud.org/results/agaspar/omedora-4/fedora-44-x86_64/",
   "fedora-45-x86_64": "https://download.copr.fedorainfracloud.org/results/agaspar/omedora-4/fedora-45-x86_64/",
   "fedora-45-aarch64": "https://download.copr.fedorainfracloud.org/results/agaspar/omedora-4/fedora-45-aarch64/"
 }}
EOF

OS_F45="$SCRATCH/os-release-f45"
printf 'NAME="Fedora Linux"\nID=fedora\nVERSION_ID=45\n' >"$OS_F45"
OS_F46="$SCRATCH/os-release-f46"
printf 'NAME="Fedora Linux"\nID=fedora\nVERSION_ID=46\n' >"$OS_F46"
OS_UBUNTU="$SCRATCH/os-release-ubuntu"
printf 'NAME="Ubuntu"\nID=ubuntu\nVERSION_ID="24.04"\n' >"$OS_UBUNTU"

# probe <expected rc> <description> [env...] -- [args...]
probe() {
  local expected=$1 description=$2
  shift 2
  local -a envs=()
  while (( $# )) && [[ $1 != "--" ]]; do envs+=("$1"); shift; done
  [[ ${1:-} == "--" ]] && shift
  local rc=0
  probe_err=$(env OMEDORA_COPR_ARCH=x86_64 "${envs[@]}" "$PROBE" --chroot-available "$@" 2>&1 >"$SCRATCH/stdout") || rc=$?
  probe_out=$(<"$SCRATCH/stdout")
  if (( rc != expected )); then
    printf 'Expected rc %s, got %s; stderr:\n%s\n' "$expected" "$rc" "$probe_err" >&2
    fail "$description"
  fi
  pass "$description"
}

echo "# --- fixture-backed answers ---"

probe 0 "explicit release with a chroot exits 0" OMEDORA_COPR_API_FIXTURE="$FIXTURE" -- 44
assert_equals "a positive answer prints nothing on stdout" "$probe_out" ""
probe 0 "fedora-45 present exits 0" OMEDORA_COPR_API_FIXTURE="$FIXTURE" -- 45
probe 1 "release without a chroot exits 1" OMEDORA_COPR_API_FIXTURE="$FIXTURE" -- 46
assert_output_contains "missing chroot names the chroot" "$probe_err" "fedora-46-x86_64"
assert_output_contains "missing chroot lists the available releases for this arch" \
  "$probe_err" "available Fedora releases: 44 45"

probe 0 "release defaults to the running VERSION_ID (45)" \
  OMEDORA_COPR_API_FIXTURE="$FIXTURE" OMEDORA_OS_RELEASE="$OS_F45"
probe 1 "running release without a chroot (46) exits 1" \
  OMEDORA_COPR_API_FIXTURE="$FIXTURE" OMEDORA_OS_RELEASE="$OS_F46"
probe 2 "a non-Fedora host can't be checked (exit 2)" \
  OMEDORA_COPR_API_FIXTURE="$FIXTURE" OMEDORA_OS_RELEASE="$OS_UBUNTU"
probe 2 "a non-numeric release can't be checked (exit 2)" \
  OMEDORA_COPR_API_FIXTURE="$FIXTURE" -- rawhide

probe 0 "arch is part of the chroot (aarch64 has 45)" \
  OMEDORA_COPR_API_FIXTURE="$FIXTURE" OMEDORA_COPR_ARCH=aarch64 -- 45
probe 1 "arch is part of the chroot (aarch64 lacks 44)" \
  OMEDORA_COPR_API_FIXTURE="$FIXTURE" OMEDORA_COPR_ARCH=aarch64 -- 44
assert_output_contains "aarch64 availability lists only aarch64 releases" \
  "$probe_err" "available Fedora releases: 45"

probe 2 "an unreadable fixture simulates a network failure (exit 2)" \
  OMEDORA_COPR_API_FIXTURE="$SCRATCH/missing.json" -- 45
printf 'not json' >"$SCRATCH/garbage.json"
probe 2 "an unparsable API reply exits 2" OMEDORA_COPR_API_FIXTURE="$SCRATCH/garbage.json" -- 45
printf '{"name": "omedora-4"}' >"$SCRATCH/no-chroots.json"
probe 2 "a reply without chroot_repos exits 2" OMEDORA_COPR_API_FIXTURE="$SCRATCH/no-chroots.json" -- 45

echo "# --- the real HTTP path, with curl stubbed ---"

cat >"$SHIM/curl" <<'EOF'
#!/bin/bash
printf 'curl %s\n' "$*" >>"$CURL_LOG"
case ${CURL_MODE:-ok} in
  ok)   cat "$CURL_FIXTURE"; printf '\n200' ;;
  404)  printf '{"error": "Project agaspar/omedora-4 does not exist."}\n404' ;;
  500)  printf 'Internal Server Error\n500' ;;
  down) echo "curl: (6) Could not resolve host: copr.fedorainfracloud.org" >&2; exit 6 ;;
esac
EOF
chmod +x "$SHIM/curl"

probe 0 "HTTP 200 with the chroot exits 0" PATH="$SHIM:$PATH" CURL_FIXTURE="$FIXTURE" -- 45
assert_output_contains "the probe queries the project endpoint for the derived COPR" \
  "$(cat "$CURL_LOG")" "/api_3/project?ownername=agaspar&projectname=omedora-"
probe 1 "HTTP 200 without the chroot exits 1" PATH="$SHIM:$PATH" CURL_FIXTURE="$FIXTURE" -- 46
probe 1 "HTTP 404 (project missing) exits 1" PATH="$SHIM:$PATH" CURL_MODE=404 -- 45
assert_output_contains "a missing project is named" "$probe_err" "does not exist"
probe 2 "HTTP 500 exits 2" PATH="$SHIM:$PATH" CURL_MODE=500 -- 45
probe 2 "an unreachable API exits 2" PATH="$SHIM:$PATH" CURL_MODE=down -- 45
assert_output_contains "an unreachable API says it could not check" "$probe_err" "could not reach the COPR API"

: >"$CURL_LOG"
probe 0 "OMEDORA_COPR_OWNER flows into the API query" \
  PATH="$SHIM:$PATH" CURL_FIXTURE="$FIXTURE" OMEDORA_COPR_OWNER=someone -- 45
assert_output_contains "the owner override reaches the query" "$(cat "$CURL_LOG")" "ownername=someone&"

echo "# --- existing modes are unchanged ---"
assert_output_contains "default mode still prints owner/project" "$("$PROBE")" "agaspar/omedora-"
assert_output_contains "--repo-id still prints the dnf repo id" \
  "$("$PROBE" --repo-id)" "copr:copr.fedorainfracloud.org:agaspar:omedora-"
assert_exit_code "an unknown argument still exits 2" 2 "$PROBE" --bogus
