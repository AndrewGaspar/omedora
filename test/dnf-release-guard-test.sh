#!/bin/bash
#
# L1 test for omedora/dnf/omedora-release-guard, the libdnf5 actions-plugin
# hook (goal_resolved, mode=json) that refuses a raw Fedora release change
# which would break the Omedora desktop.
#
# Two layers:
#   1. Decision logic through `--decide` (JSON facts on stdin, verdict out).
#   2. The json-mode protocol, with a fake actions plugin answering the
#      guard's requests: which requests it makes, when it sends `stop`, and
#      that it fails open on plugin errors and in the offline reboot phase.
#
# Real dnf behavior (the plugin firing in dnf, system-upgrade download,
# dnf5daemon, and the offline _execute phase) is covered by the Fedora
# container spike recorded in omedora/update-and-upgrade.md.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

GUARD="$ROOT/omedora/dnf/omedora-release-guard"
ACTIONS="$ROOT/omedora/dnf/omedora-release-guard.actions"
SPEC="$ROOT/omedora/packaging/copr/omedora-settings.spec"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

REPO="copr:copr.fedorainfracloud.org:agaspar:omedora-4"
OURS="Fedora Copr - user agaspar"

decide() {
  python3 "$GUARD" --decide
}

field() {
  python3 -c 'import json,sys; v=json.load(sys.stdin)[sys.argv[1]]; print(v if isinstance(v,str) else json.dumps(v))' "$1"
}

# --- decision logic ----------------------------------------------------------

out=$(decide <<<'{"override": true, "target": "46", "os_release": {"VERSION_ID": "44"}, "repo_ids": ["'"$REPO"'"], "repo_packages": 0, "probe": 1}')
assert_equals "override allows a dangerous release change" "$(field verdict <<<"$out")" "allow"
assert_equals "override skips the probe" "$(field probed <<<"$out")" "[]"

out=$(decide <<<'{"offline": true, "target": "45", "os_release": {"VERSION_ID": "44"}, "repo_ids": ["'"$REPO"'"], "repo_packages": 0, "probe": 1,
  "trans": [{"direction": "OUT", "action": "E", "name": "hyprland-no-session", "vendor": "'"$OURS"'"}]}')
assert_equals "offline reboot phase is always allowed" "$(field verdict <<<"$out")" "allow"
assert_equals "offline phase never probes the network" "$(field probed <<<"$out")" "[]"

out=$(decide <<<'{"target": "44", "os_release": {"VERSION_ID": "44"}, "repo_ids": ["'"$REPO"'"], "repo_packages": 0, "probe": 1,
  "trans": [{"direction": "OUT", "action": "E", "name": "quickshell", "vendor": "'"$OURS"'"}]}')
assert_equals "same-release transactions are never blocked (even removals)" "$(field verdict <<<"$out")" "allow"
assert_equals "same-release reason" "$(field reason <<<"$out")" "same-release"
assert_equals "same-release never probes" "$(field probed <<<"$out")" "[]"

out=$(decide <<<'{"target": "rawhide", "os_release": {"VERSION_ID": "46", "REDHAT_SUPPORT_PRODUCT_VERSION": "rawhide"}, "repo_ids": ["'"$REPO"'"], "repo_packages": 0, "probe": 1}')
assert_equals "rawhide releasever matches a rawhide install" "$(field reason <<<"$out")" "same-release"

out=$(decide <<<'{"target": "", "os_release": {"VERSION_ID": "44"}, "probe": 1}')
assert_equals "unknown target releasever fails open" "$(field verdict <<<"$out")" "allow"

out=$(decide <<<'{"target": "45", "os_release": {}, "probe": 1}')
assert_equals "unreadable os-release fails open" "$(field verdict <<<"$out")" "allow"

out=$(decide <<<'{"target": "45", "os_release": {"VERSION_ID": "44"}, "repo_ids": ["'"$REPO"'"], "repo_packages": 120, "probe": 1,
  "trans": [
    {"direction": "OUT", "action": "O", "name": "quickshell", "evr": "0.3.2-1.fc44", "vendor": "'"$OURS"'"},
    {"direction": "IN", "action": "U", "name": "quickshell", "evr": "0.3.2-1.fc45", "repo_id": "'"$REPO"'", "vendor": "'"$OURS"'"},
    {"direction": "OUT", "action": "O", "name": "hyprland-omedora", "evr": "1.0.0-1.fc44", "vendor": "'"$OURS"'"},
    {"direction": "IN", "action": "U", "name": "bash", "evr": "5.3-1.fc45", "repo_id": "fedora", "vendor": "Fedora Project"}]}')
assert_equals "supported release change (COPR upgrades its own packages) is allowed" "$(field verdict <<<"$out")" "allow"
assert_equals "a loaded COPR repo needs no probe" "$(field probed <<<"$out")" "[]"

out=$(decide <<<'{"target": "46", "os_release": {"VERSION_ID": "44"}, "repo_ids": ["'"$REPO"'"], "repo_packages": 0, "probe": 1, "trans": []}')
assert_equals "COPR without a chroot for the target blocks" "$(field verdict <<<"$out")" "block"
assert_equals "probe asked about the target release" "$(field probed <<<"$out")" '["46"]'
msg=$(field message <<<"$out")
assert_output_contains "block message names the missing release" "$msg" "agaspar/omedora-4 has no Fedora 46 builds yet"
assert_output_contains "block message points at omedora-upgrade-fedora" "$msg" "omedora-upgrade-fedora"
assert_output_contains "block message documents the override" "$msg" "sudo OMEDORA_ALLOW_RELEASE_UPGRADE=1 dnf"

out=$(decide <<<'{"target": "46", "os_release": {"VERSION_ID": "44"}, "repo_ids": ["'"$REPO"'"], "repo_packages": 0, "probe": 2, "trans": []}')
assert_equals "probe could-not-check without losses warns and allows" "$(field verdict <<<"$out")" "warn"

out=$(decide <<<'{"target": "46", "os_release": {"VERSION_ID": "44"}, "repo_ids": [], "repo_packages": 0, "probe": 1, "trans": []}')
assert_equals "disabled COPR repo: no probe, nothing lost, allowed" "$(field verdict <<<"$out")" "allow"
assert_equals "disabled COPR repo is not probed" "$(field probed <<<"$out")" "[]"

# The broken-desktop transaction from the spike (--allowerasing, partial chroot).
out=$(decide <<<'{"target": "45", "os_release": {"VERSION_ID": "44"}, "repo_ids": ["'"$REPO"'"], "repo_packages": 17, "probe": 0,
  "trans": [
    {"direction": "OUT", "action": "E", "name": "hyprland-no-session", "evr": "0.56.2-1.fc44", "repo_id": "@System", "vendor": "'"$OURS"'"},
    {"direction": "OUT", "action": "O", "name": "quickshell", "evr": "0.3.2-1.fc44", "repo_id": "@System", "vendor": "'"$OURS"'"},
    {"direction": "IN", "action": "D", "name": "quickshell", "evr": "0.2.1-5.fc45", "repo_id": "fedora", "vendor": "Fedora Project"},
    {"direction": "OUT", "action": "O", "name": "hyprutils", "evr": "0.14.0-1.fc44", "repo_id": "@System", "vendor": "'"$OURS"'"},
    {"direction": "IN", "action": "U", "name": "hyprutils", "evr": "0.15.0-1.fc45", "repo_id": "fedora", "vendor": "Fedora Project"},
    {"direction": "OUT", "action": "O", "name": "uwsm", "evr": "0.27.1-1.fc44", "repo_id": "@System", "vendor": "'"$OURS"'"},
    {"direction": "IN", "action": "U", "name": "uwsm", "evr": "0.27.1-1.fc45", "repo_id": "'"$REPO"'", "vendor": "'"$OURS"'"},
    {"direction": "OUT", "action": "E", "name": "ghostty", "evr": "1.2-1.fc44", "repo_id": "@System", "vendor": "Fedora Copr - user scottames"}]}')
assert_equals "removal/downgrade of COPR packages blocks even when the chroot exists" "$(field verdict <<<"$out")" "block"
reason=$(field reason <<<"$out")
assert_output_contains "removed package is reported" "$reason" "hyprland-no-session (removed)"
assert_output_contains "downgrade to Fedora's copy is reported" "$reason" "quickshell (downgraded to 0.2.1-5.fc45 from fedora)"
assert_output_contains "hand-over to another vendor is reported" "$reason" "hyprutils (replaced by 0.15.0-1.fc45 from fedora)"
assert_output_lacks "COPR-to-COPR upgrade is not a loss" "$reason" "uwsm"
assert_output_lacks "another owner's COPR package is not Omedora's" "$reason" "ghostty"
assert_output_contains "loss count is exact" "$reason" "3 Omedora package(s)"

out=$(decide <<<'{"target": "46", "os_release": {"VERSION_ID": "44"}, "repo_ids": ["'"$REPO"'"], "repo_packages": 0, "probe": 2,
  "trans": [{"direction": "OUT", "action": "O", "name": "omedora-settings", "evr": "1-1.fc44", "vendor": "'"$OURS"'"}]}')
assert_equals "obsoleted with nothing from the COPR coming in is a loss" "$(field verdict <<<"$out")" "block"

# --- json protocol, against a fake actions plugin ----------------------------

cat >"$TMP/fake-plugin.py" <<'EOF'
import json, os, subprocess, sys

scenario = json.load(open(sys.argv[1]))
cmd = [sys.executable, sys.argv[2]] + scenario.get("args", [])
proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
requests, stop = [], None
for line in proc.stdout:
  msg = json.loads(line)
  op, domain, args = msg.get("op"), msg.get("domain"), msg.get("args", {})
  if op == "stop":
    stop = args.get("message")
    proc.stdin.close()
    break
  if op == "log":
    requests.append("log:" + args.get("level", ""))
    proc.stdin.write(json.dumps({"op": "reply", "requested_op": "log", "domain": "log", "status": "OK"}) + "\n")
    proc.stdin.flush()
    continue
  key = args.get("key") or args.get("name") or ""
  requests.append("%s:%s:%s" % (op, domain, key))
  if scenario.get("error_on") == domain:
    reply = {"op": "reply", "requested_op": op, "domain": domain, "status": "ERROR", "message": "boom"}
  elif domain == "conf" and key == "cacheonly":
    reply = {"status": "OK", "return": {"keys_val": [{"key": "cacheonly", "value": scenario.get("cacheonly", "none")}]}}
  elif domain == "conf" and key == "*.enabled":
    reply = {"status": "OK", "return": {"keys_val": [{"key": r + ".enabled", "value": "1"} for r in scenario.get("repos", [])]}}
  elif domain == "conf":
    reply = {"status": "OK", "return": {"keys_val": [{"key": r + ".enabled", "value": "1"} for r in scenario.get("repos", []) if r.startswith("copr:") and ":omedora-" in r]}}
  elif domain == "vars":
    reply = {"status": "OK", "return": {"vars": [{"name": "releasever", "value": scenario["releasever"]}]}}
  elif domain == "packages":
    reply = {"status": "OK", "return": {"packages": [{"name": "x"}] * scenario.get("repo_packages", 0)}}
  elif domain == "trans_packages":
    reply = {"status": "OK", "return": {"trans_packages": scenario.get("trans", [])}}
  else:
    reply = {"status": "ERROR", "message": "unexpected"}
  reply.update({"op": "reply", "requested_op": op, "domain": domain})
  proc.stdin.write(json.dumps(reply) + "\n")
  proc.stdin.flush()
try:
  proc.stdin.close()
except Exception:
  pass
err = proc.stderr.read()
rc = proc.wait(timeout=30)
print(json.dumps({"rc": rc, "stop": stop, "requests": requests, "stderr": err}))
EOF

# A stub omedora-copr on PATH; records each probe.
mkdir -p "$TMP/bin"
cat >"$TMP/bin/omedora-copr" <<EOF
#!/bin/bash
echo "\$*" >>"$TMP/probe.log"
exit \${STUB_PROBE_EXIT:-1}
EOF
chmod +x "$TMP/bin/omedora-copr"
printf 'NAME="Fedora Linux"\nVERSION_ID=44\n' >"$TMP/os-release"

protocol() {
  local scenario=$1
  printf '%s' "$scenario" >"$TMP/scenario.json"
  rm -f "$TMP/probe.log"
  PATH="$TMP/bin:$PATH" OMEDORA_OS_RELEASE="$TMP/os-release" python3 "$TMP/fake-plugin.py" "$TMP/scenario.json" "$GUARD"
}

probed() {
  [[ -f $TMP/probe.log ]] && cat "$TMP/probe.log" || true
}

out=$(protocol '{"releasever": "44", "repos": ["fedora", "'"$REPO"'"]}')
assert_equals "protocol: same-release exits 0" "$(field rc <<<"$out")" "0"
assert_equals "protocol: same-release sends no stop" "$(field stop <<<"$out")" "null"
assert_output_lacks "protocol: same-release never lists packages" "$(field requests <<<"$out")" "trans_packages"
assert_equals "protocol: same-release never probes" "$(probed)" ""

out=$(protocol '{"releasever": "46", "repos": ["fedora", "'"$REPO"'"], "repo_packages": 0, "trans": []}')
assert_output_contains "protocol: missing chroot sends stop" "$(field stop <<<"$out")" "no Fedora 46 builds yet"
assert_equals "protocol: probe called with the target release" "$(probed)" "--chroot-available 46"

out=$(protocol '{"releasever": "45", "repos": ["fedora", "'"$REPO"'"], "repo_packages": 9,
  "trans": [{"direction": "OUT", "action": "E", "name": "hyprland-no-session", "evr": "1-1.fc44", "repo_id": "@System", "vendor": "'"$OURS"'"}]}')
assert_output_contains "protocol: COPR package removal sends stop" "$(field stop <<<"$out")" "hyprland-no-session (removed)"
assert_equals "protocol: loaded COPR repo is not probed" "$(probed)" ""

out=$(STUB_PROBE_EXIT=1 protocol '{"releasever": "46", "cacheonly": "all", "repos": [], "repo_packages": 0,
  "trans": [{"direction": "OUT", "action": "E", "name": "quickshell", "vendor": "'"$OURS"'"}]}')
assert_equals "protocol: offline replay (cacheonly=all, no repos) is allowed" "$(field stop <<<"$out")" "null"
assert_equals "protocol: offline replay never probes" "$(probed)" ""
assert_output_lacks "protocol: offline replay never reads releasever" "$(field requests <<<"$out")" "vars"

# Offline detection via dnf's own argv (`dnf5 offline _execute`).
python3 -c 'import time; time.sleep(30)' offline _execute &
fake_dnf=$!
out=$(protocol '{"args": ["'"$fake_dnf"'"], "releasever": "46", "repos": ["'"$REPO"'"], "repo_packages": 0,
  "trans": [{"direction": "OUT", "action": "E", "name": "quickshell", "vendor": "'"$OURS"'"}]}')
kill "$fake_dnf" 2>/dev/null || true
assert_equals "protocol: dnf5 offline _execute parent is allowed" "$(field stop <<<"$out")" "null"
assert_equals "protocol: dnf5 offline _execute never probes" "$(probed)" ""

out=$(OMEDORA_ALLOW_RELEASE_UPGRADE=1 protocol '{"releasever": "46", "repos": ["'"$REPO"'"], "repo_packages": 0,
  "trans": [{"direction": "OUT", "action": "E", "name": "quickshell", "vendor": "'"$OURS"'"}]}')
assert_equals "protocol: override env var bypasses the guard" "$(field stop <<<"$out")" "null"
assert_equals "protocol: override makes no plugin queries" "$(field requests <<<"$out")" '["log:DEBUG"]'

out=$(protocol '{"releasever": "46", "repos": ["'"$REPO"'"], "repo_packages": 0, "error_on": "trans_packages"}')
assert_equals "protocol: plugin error fails open (exit 0)" "$(field rc <<<"$out")" "0"
assert_equals "protocol: plugin error fails open (no stop)" "$(field stop <<<"$out")" "null"
assert_output_contains "protocol: plugin error is reported on stderr" "$(field stderr <<<"$out")" "internal error, allowing transaction"

out=$(STUB_PROBE_EXIT=2 protocol '{"releasever": "46", "repos": ["'"$REPO"'"], "repo_packages": 0, "trans": []}')
assert_equals "protocol: probe exit 2 without losses allows" "$(field stop <<<"$out")" "null"
assert_output_contains "protocol: probe exit 2 warns" "$(field stderr <<<"$out")" "could not check"

# --- packaging wiring ---------------------------------------------------------

grep -qE '^goal_resolved:::.*enabled=host-only' "$ACTIONS" \
  && pass "actions line hooks goal_resolved, host only" \
  || fail "actions line hooks goal_resolved, host only"
grep -qE '^goal_resolved:::.*mode=json' "$ACTIONS" \
  && pass "actions line uses json mode" \
  || fail "actions line uses json mode"
if grep -E '^goal_resolved' "$ACTIONS" | grep -q 'raise_error=1'; then
  fail "actions line keeps raise_error=0 (guard crashes fail open)"
fi
pass "actions line keeps raise_error=0 (guard crashes fail open)"
grep -qE '^goal_resolved:::[^:]*:/usr/libexec/omedora/omedora-release-guard( |$)' "$ACTIONS" \
  && pass "actions line runs the packaged guard path" \
  || fail "actions line runs the packaged guard path"
grep -q '^Requires:[[:space:]]*libdnf5-plugin-actions' "$SPEC" \
  && pass "omedora-settings requires libdnf5-plugin-actions" \
  || fail "omedora-settings requires libdnf5-plugin-actions"
grep -q '^%{_libexecdir}/omedora/omedora-release-guard$' "$SPEC" \
  && pass "omedora-settings packages the guard" \
  || fail "omedora-settings packages the guard"
grep -q '^%config(noreplace) %{_sysconfdir}/dnf/libdnf5-plugins/actions.d/omedora-release-guard.actions$' "$SPEC" \
  && pass "omedora-settings packages the actions drop-in as config" \
  || fail "omedora-settings packages the actions drop-in as config"

echo "# all dnf release-guard checks passed"
