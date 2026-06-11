#!/bin/bash
#
# L3-ish integration test: upgrading omedora FROM a known prior release.
#
# Simulates a real Fedora user who installed an earlier omedora release and then
# clicks the waybar "upgrade" button (which runs `omarchy-update`). It exercises
# the REAL update dispatch end to end in a throwaway fedora:44 podman container:
#
#     omarchy-update -y
#       └─ omarchy-update-git           (git pull → newer ref)
#       └─ omarchy-update-perform       (Fedora dispatch)
#            └─ omarchy-update-perform-fedora
#                 └─ omedora-update-pkgs   (dnf upgrade — STUBBED here)
#
# The actual `dnf upgrade` is stubbed via $OMEDORA_DNF_CMD (a fake dnf that just
# records its argv) so the test doesn't pull a multi-hundred-MB system upgrade —
# but everything UP TO and INCLUDING the dispatch into omedora-update-pkgs is the
# real code paths.
#
# ---------------------------------------------------------------------------
# Why this is subtle (the `script`-wrapper chicken-and-egg)
# ---------------------------------------------------------------------------
# v0.1.0 and v0.1.1 shipped a bug: bin/omarchy-update unconditionally re-execs
# itself under `script` (the PTY logger), which is ABSENT on a minimal Fedora 44
# (it lives in util-linux-script). So the old omarchy-update dies *before* it can
# git-pull the fix. The going-forward guard (command -v script) only helps once
# the user is ON fixed code — it does NOT retroactively fix an already-installed
# v0.1.0/v0.1.1 omarchy-update, because the running process is the OLD one.
#
# So this test models BOTH realities, per prior tag:
#
#   Scenario A — "existing user recovery":   installed = OLD release, `script`
#     PRESENT (the util-linux-script recovery, or simply that the box had it).
#     The OLD omarchy-update gets PAST the wrapper, git-pulls HEAD, and the
#     (now-on-disk, HEAD) perform-fedora → omedora-update-pkgs dnf step runs.
#
#   Scenario B — "going-forward fix":   installed = HEAD, `script` ABSENT.
#     The guarded omarchy-update runs UNLOGGED and completes the dispatch — i.e.
#     a fresh install with the fix no longer needs `script` at all.
#
# (Scenario A with `script` ABSENT is the broken case that motivated the fix; it
# is asserted to FAIL-to-dispatch in Scenario A-broken, documenting the recovery
# requirement: existing v0.1.0/v0.1.1 users must `git -C ~/.local/share/omarchy
# pull` ONCE — or install util-linux-script — to get unstuck.)
#
# ---------------------------------------------------------------------------
# Run (host is Arch; uses podman, NOT docker):
#   omedora/test/fedora/upgrade-from-release-test.sh
#   omedora/test/fedora/upgrade-from-release-test.sh --keep      # leave ctr up
#   FROM_TAGS="v0.1.1" omedora/test/fedora/upgrade-from-release-test.sh
#
# Needs the prior tags to exist locally (they do once the repo is cloned).

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
IMAGE="${OMEDORA_UPGRADE_IMAGE:-registry.fedoraproject.org/fedora:44}"
CTR="${OMEDORA_UPGRADE_CTR:-omedora-upgradetest-$$}"
FROM_TAGS="${FROM_TAGS:-v0.1.0 v0.1.1}"

# The remote branch the install "pulls" to get the fix. In a real install this
# is the default branch (the stable release line); here it's whatever branch the
# checkout is on (the upgrade-fix work).
FIX_BRANCH="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
FIX_SHA="$(git -C "$REPO" rev-parse HEAD)"

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

log() { printf '\033[1;34m[upgrade]\033[0m %s\n' "$*"; }

# $REPO may be a git WORKTREE (its .git is a gitdir-file pointing into the main
# repo), which a container can't clone in isolation. Materialize a standalone
# "remote" repo in TMPDIR that contains the fix branch + the prior-release tags,
# and bind-mount THAT into the container as /repo. The omedora source tree the
# install clones therefore carries real history (the fix commits) and the
# v0.1.x tags the test checks out.
REMOTE="$TMPDIR/omedora-upgrade-remote-$$"
build_remote() {
  rm -rf "$REMOTE"
  git init -q "$REMOTE"
  git -C "$REMOTE" config receive.denyCurrentBranch ignore
  # Bring over the fix branch (as $FIX_BRANCH) and every prior-release tag.
  git -C "$REPO" push -q "$REMOTE" "HEAD:refs/heads/$FIX_BRANCH"
  for t in $FROM_TAGS; do
    git -C "$REPO" push -q "$REMOTE" "refs/tags/$t:refs/tags/$t"
  done
  # Make $FIX_BRANCH the checked-out HEAD so a plain `git clone` lands on it.
  git -C "$REMOTE" symbolic-ref HEAD "refs/heads/$FIX_BRANCH"
}

cleanup() {
  if $keep; then
    log "Container '$CTR' left running (--keep). Remove: podman rm -f $CTR"
    log "Remote staging dir left in place: $REMOTE"
  else
    podman rm -f "$CTR" >/dev/null 2>&1 || true
    rm -rf "$REMOTE" 2>/dev/null || true
  fi
}
trap cleanup EXIT

# --- TAP-ish assertions ------------------------------------------------------
n=0; passed=0; failed=0; failed_names=()
ok()  { n=$((n+1)); passed=$((passed+1)); echo "ok $n - $1"; }
nok() { n=$((n+1)); failed=$((failed+1)); failed_names+=("$1"); echo "not ok $n - $1"; [[ -n ${2:-} ]] && printf '%s\n' "$2" | sed 's/^/    /'; }

# Run a command in the container as the non-root 'tester' user with the omedora
# update env: OMARCHY_DISTRO=fedora, OMARCHY_PATH at the simulated install, the
# install's bin/ on PATH, and a stubbed dnf so the real `dnf upgrade` is skipped.
# /home/tester/shim is a tester-controlled PATH dir where we drop a fake `script`
# (for the "script present" case) and a transparent `sudo`/`systemctl` so the
# update steps don't need real root/systemd. It sits FIRST on PATH so it shadows
# the system. Toggling `script` presence is just adding/removing one file there —
# no system install, so scenarios don't leak state into each other.
in_ctr() { podman exec -u tester \
  -e HOME=/home/tester \
  -e OMARCHY_DISTRO=fedora \
  -e OMARCHY_PATH=/home/tester/.local/share/omarchy \
  -e OMARCHY_INSTALL=/home/tester/.local/share/omarchy/install \
  -e OMEDORA_DNF_CMD=/home/tester/fakednf \
  -e PATH=/home/tester/.local/share/omarchy/bin:/home/tester/shim:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  "$CTR" bash -lc "$1"; }

log "Building standalone remote (fix branch + prior tags) at $REMOTE..."
build_remote || { echo "Bail out! could not build the remote staging repo"; exit 1; }

log "Starting $IMAGE container '$CTR'..."
podman rm -f "$CTR" >/dev/null 2>&1 || true
podman run -d --name "$CTR" -v "$REMOTE:/repo:ro" "$IMAGE" sleep infinity >/dev/null \
  || { echo "Bail out! could not start container"; exit 1; }

log "Provisioning container (git, gum, a non-root user, a fake dnf)..."
podman exec "$CTR" bash -c '
set -e
dnf install -y --setopt=install_weak_deps=False git gum >/dev/null 2>&1
useradd -m -s /bin/bash tester
# The bind-mounted /repo is owned by the host UID; tell git to trust it (both
# root and the tester user) so clone/pull do not trip the dubious-ownership guard.
git config --system --add safe.directory /repo
git config --system --add safe.directory "*"
# Fake dnf: record its argv to a log, never touch the system.
cat >/home/tester/fakednf <<EOF
#!/bin/bash
echo "FAKE-DNF \$*" >>/home/tester/dnf.log
EOF
chmod +x /home/tester/fakednf
# tester-owned shim dir: transparent sudo + a no-op systemctl so the update
# steps (omarchy-update-time, omarchy-update-restart) do not need real root or a
# running systemd in this throwaway container. (chronyd restart becomes a no-op;
# the point of the test is the GIT-PULL + dnf-dispatch flow, not NTP.)
mkdir -p /home/tester/shim
cat >/home/tester/shim/sudo <<EOF
#!/bin/bash
exec "\$@"
EOF
# Emulate a REAL Fedora systemctl: chronyd exists, systemd-timesyncd does NOT
# (Fedora rides chronyd). This is what makes the OLD omarchy-update-time fail on
# Fedora — and is exactly the second blocker the fix addresses. A no-op
# systemctl would falsely let the buggy old update succeed.
cat >/home/tester/shim/systemctl <<EOF
#!/bin/bash
case " \$* " in
  *" systemd-timesyncd "*|*" systemd-timesyncd.service "*)
    echo "Failed to restart systemd-timesyncd.service: Unit systemd-timesyncd.service not found." >&2
    exit 5 ;;
esac
exit 0
EOF
chmod +x /home/tester/shim/sudo /home/tester/shim/systemctl
chown -R tester:tester /home/tester/fakednf /home/tester/shim
' || { echo "Bail out! provisioning failed"; exit 1; }

# Toggle the `script` PTY logger's presence for the tester. fedora:44 base does
# NOT ship it, so "absent" is the default; "present" drops a fake `script` shim
# (mimicking `script -qefc <cmd> <log>`) into the tester shim dir.
set_script() {
  case "$1" in
    present)
      in_ctr 'cat >~/shim/script <<EOF
#!/bin/bash
cmd=""
while [[ \$# -gt 0 ]]; do
  if [[ \$1 == "-qefc" ]]; then cmd="\$2"; shift 2; continue; fi
  shift
done
eval "\$cmd"
EOF
chmod +x ~/shim/script' ;;
    absent)
      in_ctr 'rm -f ~/shim/script' ;;
  esac
}

# (re)create a fresh simulated install in ~/.local/share/omarchy: clone the
# standalone /repo, check out $1 ("HEAD" → the fix branch tip, else a tag) on a
# branch that TRACKS the fix branch, so a later `git pull` fast-forwards to the
# fix. $2 toggles `script` presence (present|absent).
setup_install() {
  local at="$1" script_mode="${2:-absent}" ref
  if [[ $at == HEAD ]]; then ref="origin/$FIX_BRANCH"; else ref="$at"; fi
  in_ctr "
    set -e
    rm -rf ~/.local/share/omarchy ~/dnf.log
    mkdir -p ~/.local/share
    git clone -q /repo ~/.local/share/omarchy
    cd ~/.local/share/omarchy
    git config user.email t@t; git config user.name t
    git checkout -q -B installed '$ref'
    git branch --set-upstream-to=origin/'$FIX_BRANCH' installed >/dev/null 2>&1
  " || return 1
  set_script "$script_mode"
}

head_of()   { in_ctr 'git -C ~/.local/share/omarchy rev-parse HEAD' 2>/dev/null; }
dnflog_of() { in_ctr 'cat ~/dnf.log 2>/dev/null' || true; }

# =============================================================================
# Scenario A — REALITY for existing v0.1.0/v0.1.1 users.
#
# Their installed omarchy-update is the OLD (buggy) one. Running it does NOT
# self-recover, because it dies BEFORE the git pull — first at the unconditional
# `script` wrapper (script absent on a minimal Fedora), and even with `script`
# present, at omarchy-update-time's `systemctl restart systemd-timesyncd` (no
# such unit on Fedora) under `set -e`. So the fix on the remote can never reach
# them through `omarchy update` itself. We assert that, for BOTH script states.
#
# The actual recovery: ONE manual `git -C ~/.local/share/omarchy pull` lands the
# fix; AFTER that, `omarchy update` (now the fixed code on disk) completes the
# real dispatch into the Fedora dnf step.
# =============================================================================
for from in $FROM_TAGS; do
  for smode in present absent; do
    log "Scenario A ($from, script $smode): existing (old) install does NOT self-recover"
    if ! setup_install "$from" "$smode"; then
      nok "A[$from/$smode]: setup_install" "clone/checkout failed"; continue
    fi
    in_ctr 'omarchy-update -y >/dev/null 2>&1' || true
    if [[ "$(head_of)" != "$FIX_SHA" ]]; then
      ok "A[$from/$smode]: old \`omarchy update\` stays stuck on the old ref (does NOT self-heal)"
    else
      nok "A[$from/$smode]: old update unexpectedly self-healed to the fix ref"
    fi
  done

  # Recovery path: one manual git pull, then the now-fixed update works.
  log "Scenario A-recovery ($from): manual \`git pull\`, then \`omarchy update\`"
  setup_install "$from" absent
  in_ctr 'git -C ~/.local/share/omarchy pull --autostash -q' >/dev/null 2>&1
  [[ "$(head_of)" == "$FIX_SHA" ]] \
    && ok "A-recovery[$from]: manual \`git pull\` lands the fix ref" \
    || nok "A-recovery[$from]: manual git pull recovery" "HEAD=$(head_of)"
  # Now the on-disk omarchy-update is the FIXED one; run it (script still absent).
  out_rec="$(in_ctr 'omarchy-update -y 2>&1' || true)"
  if [[ $out_rec == *"No such file or directory"* && $out_rec == *script* ]]; then
    nok "A-recovery[$from]: post-pull update survives the \`script\` wrapper" "$out_rec"
  else
    ok "A-recovery[$from]: post-pull update survives the \`script\` wrapper"
  fi
  [[ "$(dnflog_of)" == *"upgrade -y --refresh"* ]] \
    && ok "A-recovery[$from]: post-pull update reaches the dnf step (\`dnf upgrade -y --refresh\`)" \
    || nok "A-recovery[$from]: post-pull update reaches the dnf step" "dnf.log: $(dnflog_of)"
done

# =============================================================================
# Scenario B — going-forward fix: a FRESH install AT HEAD, `script` ABSENT.
# The guarded omarchy-update runs UNLOGGED and completes the REAL dispatch
# (omarchy-update → -git → -perform → -perform-fedora → omedora-update-pkgs).
# This is what every fresh Fedora install gets after the fix ships.
# =============================================================================
log "Scenario B (HEAD, script ABSENT): going-forward guard end-to-end"
if setup_install HEAD absent; then
  out_b="$(in_ctr 'omarchy-update -y 2>&1' || true)"
  if [[ $out_b == *"No such file or directory"* && $out_b == *script* ]]; then
    nok "B: fresh HEAD install updates without \`script\`" "$out_b"
  else
    ok "B: fresh HEAD install updates without \`script\`"
  fi
  [[ "$(dnflog_of)" == *"upgrade -y --refresh"* ]] \
    && ok "B: fresh HEAD install reaches the dnf upgrade step" \
    || nok "B: fresh HEAD install reaches the dnf upgrade step" "dnf.log: $(dnflog_of)"
else
  nok "B: setup HEAD install" "clone/checkout failed"
fi

# Scenario B-logged — fresh HEAD with `script` PRESENT must still dispatch (the
# logged path), proving the guard didn't break the normal logged flow.
log "Scenario B-logged (HEAD, script PRESENT): logged path still dispatches"
if setup_install HEAD present; then
  in_ctr 'omarchy-update -y >/dev/null 2>&1' || true
  [[ "$(dnflog_of)" == *"upgrade -y --refresh"* ]] \
    && ok "B-logged: fresh HEAD install (script present) reaches the dnf upgrade step" \
    || nok "B-logged: fresh HEAD install (script present) reaches the dnf upgrade step" "dnf.log: $(dnflog_of)"
else
  nok "B-logged: setup HEAD install" "clone/checkout failed"
fi

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
