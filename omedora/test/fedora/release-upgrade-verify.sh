#!/bin/bash
#
# L3 Fedora release-upgrade verification. Runs as root INSIDE the test image
# for the release being upgraded FROM (omedora-test:fedora<N>); invoked by
# run-release-upgrade.sh.
#
#   1. fresh bootstrap of Omedora from the live COPR, then one clean update
#   2. omedora-upgrade-fedora --check refuses a release the COPR doesn't build
#      and accepts the target release
#   3. the real dnf5 offline upgrade: `dnf system-upgrade download`, then the
#      same `dnf5 offline _execute` the reboot would run (the trigger symlink
#      and "ready" state are set by hand; the trailing reboot request fails
#      without D-Bus, which is expected here)
#   4. every package that came from the Omedora COPR is still installed, still
#      from the COPR, rebuilt for the new release, and not downgraded
#   5. `omarchy update` passes twice on the new release
#
# OMEDORA_UPGRADE_CODE selects whose Omedora code drives steps 2 and 5:
#   checkout  (default) the bind-mounted checkout, linked the way
#             `omarchy dev link` does it (OMARCHY_PATH, PATH and sudo's
#             secure_path); the pre-push gate for unreleased code
#   installed the omedora RPM payload from the COPR; the post-release gate
#
# OMEDORA_UPGRADE_TO picks the target release (default: current + 1).

set -euo pipefail

REPO="${REPO:-/repo}"
CODE_MODE="${OMEDORA_UPGRADE_CODE:-checkout}"
FROM_RELEASE=$(. /etc/os-release && echo "$VERSION_ID")
TO_RELEASE="${OMEDORA_UPGRADE_TO:-$((FROM_RELEASE + 1))}"
OFFLINE_DIR=/usr/lib/sysimage/libdnf5/offline
LOG_DIR=/tmp/release-upgrade
mkdir -p "$LOG_DIR"

ok() { echo "ok - $1"; }
die() {
  echo "not ok - $1" >&2
  if [[ -n ${2:-} && -f $2 ]]; then
    tail -40 "$2" >&2
  fi
  exit 1
}

[[ -d $REPO/bin ]] || die "repo bind-mounted at $REPO"
(( EUID == 0 )) || die "runs as container root (got uid $EUID)"
[[ $CODE_MODE == "checkout" || $CODE_MODE == "installed" ]] \
  || die "OMEDORA_UPGRADE_CODE is checkout or installed (got '$CODE_MODE')"
(( TO_RELEASE > FROM_RELEASE )) || die "target $TO_RELEASE is newer than $FROM_RELEASE"
echo "==> release upgrade: Fedora $FROM_RELEASE -> $TO_RELEASE (Omedora code: $CODE_MODE)"

# omarchy-update runs `sudo -v` under a pty; Fedora's stock %wheel rule still
# matches alongside the image's NOPASSWD drop-in, so sudo would prompt. Same
# fix as update-verify.sh: the test user never authenticates.
printf 'Defaults:omedora !authenticate\n' >/etc/sudoers.d/zz-omedora-test-noauth
chmod 0440 /etc/sudoers.d/zz-omedora-test-noauth

# In checkout mode the dev link points at a container-local snapshot of the
# checkout, never at the bind mount: `omarchy update` runs `git pull` on a
# dev-linked checkout, and the host's repo is not the test's to change. The
# snapshot is its own git repo with no upstream, so the update skips the pull.
CHECKOUT=/opt/omedora-checkout

as_user() {
  # `su -c` gets no login environment, and 4.5's omarchy-update refuses to run
  # unless OMARCHY_PATH names the code it runs from.
  local env_prefix="OMARCHY_PATH=/usr/share/omarchy"
  if [[ $CODE_MODE == "checkout" ]]; then
    env_prefix="OMARCHY_PATH=$CHECKOUT PATH=$CHECKOUT/bin:\$PATH"
  fi
  su omedora -c "$env_prefix $*"
}

snapshot_checkout() {
  mkdir -p "$CHECKOUT"
  tar -C "$REPO" --exclude=./.git \
    --exclude='./omedora/packaging/copr/repo*' --exclude='./omedora/packaging/copr/output*' \
    --exclude=./omedora/test/fedora/headless/artifacts --exclude='./omedora/test/fedora/vm/artifacts*' \
    -cf - . | tar -C "$CHECKOUT" -xf -
  chown -R omedora:omedora "$CHECKOUT"
  su omedora -c "git -C $CHECKOUT init -q && git -C $CHECKOUT add -A && \
    git -C $CHECKOUT -c user.name=test -c user.email=test@localhost commit -qm 'checkout snapshot'"
}

# --- 1. install on the old release --------------------------------------------
su omedora -c "OMEDORA_PLAN_AUTOCONFIRM=1 bash $REPO/omedora/install-4.sh" \
  >"$LOG_DIR/install.log" 2>&1 || die "bootstrap on Fedora $FROM_RELEASE" "$LOG_DIR/install.log"
ok "bootstrap on Fedora $FROM_RELEASE ($(rpm -q omedora))"

if [[ $CODE_MODE == "checkout" ]]; then
  snapshot_checkout || die "snapshot the checkout into $CHECKOUT"
  # What `omarchy dev link` writes, minus the reboot: root resolves omarchy-*
  # from the checkout too.
  printf 'Defaults secure_path="%s/bin:/usr/local/sbin:/usr/local/bin:/usr/bin"\n' "$CHECKOUT" \
    >/etc/sudoers.d/omarchy-dev-path
  chmod 0440 /etc/sudoers.d/omarchy-dev-path
fi

as_user "timeout 1800 omarchy-update -y" >"$LOG_DIR/update-before.log" 2>&1 \
  || die "omarchy update on Fedora $FROM_RELEASE" "$LOG_DIR/update-before.log"
ok "omarchy update on Fedora $FROM_RELEASE"

copr_repo_id=$(OMARCHY_PATH="$REPO" "$REPO/bin/omedora-copr" --repo-id)

# name, EVR and arch of everything installed from the Omedora COPR.
copr_inventory() {
  dnf repoquery --installed --qf '%{name} %{evr} %{arch} %{from_repo}\n' \
    | awk -v repo="$copr_repo_id" '$4 == repo { print $1, $2, $3 }' | sort
}

copr_inventory >"$LOG_DIR/before.txt"
(( $(wc -l <"$LOG_DIR/before.txt") > 10 )) \
  || die "inventory found the COPR packages (got $(wc -l <"$LOG_DIR/before.txt"))" "$LOG_DIR/before.txt"
ok "$(wc -l <"$LOG_DIR/before.txt") packages installed from $copr_repo_id"

# --- 2. preflight ------------------------------------------------------------------
unsupported=$((TO_RELEASE + 1))
probe_rc=0
OMARCHY_PATH="$REPO" "$REPO/bin/omedora-copr" --chroot-available "$unsupported" >/dev/null 2>&1 \
  || probe_rc=$?
if (( probe_rc == 1 )); then
  if as_user "omedora-upgrade-fedora --check --releasever $unsupported" \
    >"$LOG_DIR/check-unsupported.log" 2>&1; then
    die "preflight refuses Fedora $unsupported, which the COPR does not build" "$LOG_DIR/check-unsupported.log"
  fi
  ok "preflight refuses Fedora $unsupported, which the COPR does not build"
else
  echo "# skip: the COPR answered $probe_rc for Fedora $unsupported, so it can't stand in for an unsupported release"
fi

as_user "omedora-upgrade-fedora --check --releasever $TO_RELEASE" \
  >"$LOG_DIR/check.log" 2>&1 || die "preflight accepts Fedora $TO_RELEASE" "$LOG_DIR/check.log"
ok "preflight accepts Fedora $TO_RELEASE"

# --- 3. the offline upgrade ---------------------------------------------------------
# No --allowerasing: a removal the resolver needs is a failure, not a fix.
dnf -y system-upgrade download --releasever="$TO_RELEASE" \
  >"$LOG_DIR/download.log" 2>&1 || die "system-upgrade download" "$LOG_DIR/download.log"
ok "system-upgrade download for Fedora $TO_RELEASE"

# `dnf offline reboot` marks the state ready and creates the trigger symlink;
# systemd then runs `dnf5 offline _execute` early in the next boot.
sed -i 's/^status = .*/status = "ready"/' "$OFFLINE_DIR/offline-transaction-state.toml"
ln -sfn "$OFFLINE_DIR" /system-update
dnf5 offline _execute >"$LOG_DIR/execute.log" 2>&1 || true
if grep -qE '^Error:|Transaction failed' "$LOG_DIR/execute.log"; then
  die "offline transaction ran cleanly" "$LOG_DIR/execute.log"
fi
now=$(. /etc/os-release && echo "$VERSION_ID")
[[ $now == "$TO_RELEASE" ]] || die "offline transaction reached Fedora $TO_RELEASE (os-release says $now)" "$LOG_DIR/execute.log"
ok "offline transaction upgraded the system to Fedora $TO_RELEASE"

# --- 4. Omedora packages survived the upgrade -----------------------------------------
copr_inventory >"$LOG_DIR/after.txt"
dist=".fc$TO_RELEASE"
problems=0
while read -r name evr arch; do
  read -r new_evr new_arch < <(awk -v n="$name" '$1 == n { print $2, $3 }' "$LOG_DIR/after.txt") || true
  if [[ -z ${new_evr:-} ]]; then
    echo "  $name: no longer installed from $copr_repo_id (was $evr; now: $(rpm -q "$name" 2>&1 | head -1))" >&2
    problems=1
    continue
  fi
  if [[ $new_evr != *"$dist"* ]]; then
    echo "  $name: $new_evr is not a $dist build" >&2
    problems=1
  fi
  if (( $(rpm --eval "%{lua: print(rpm.vercmp('$new_evr', '$evr'))}") < 0 )); then
    echo "  $name: downgraded $evr -> $new_evr" >&2
    problems=1
  fi
  new_evr=""
done <"$LOG_DIR/before.txt"
(( problems == 0 )) || die "every COPR package is kept, rebuilt for $dist and not downgraded"
ok "every COPR package is kept, rebuilt for $dist and not downgraded"

stale=$(dnf repoquery --installed --qf '%{name}-%{evr}\n' | grep -F ".fc$FROM_RELEASE" \
  | grep -E '^(omedora|hypr|quickshell|uwsm|aquamarine|xdg-desktop-portal-hyprland)' || true)
[[ -z $stale ]] || die "no Omedora-stack package still carries .fc$FROM_RELEASE: $stale"
ok "no Omedora-stack package still carries .fc$FROM_RELEASE"

# --- 5. the updater on the new release ---------------------------------------------
for run in 1 2; do
  as_user "timeout 1800 omarchy-update -y" >"$LOG_DIR/update-after-$run.log" 2>&1 \
    || die "omarchy update run $run on Fedora $TO_RELEASE" "$LOG_DIR/update-after-$run.log"
  ok "omarchy update run $run on Fedora $TO_RELEASE"
done

echo "# release upgrade Fedora $FROM_RELEASE -> $TO_RELEASE: ALL GREEN"
