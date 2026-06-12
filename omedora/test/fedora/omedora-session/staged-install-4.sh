#!/bin/bash
#
# Staged driver for the L4 v4 session build (run as omedora inside the logind
# session via `machinectl shell`). It sources the SAME omedora install steps,
# in the SAME order, as omedora/install-4.sh — but lets build-session.sh run
# them in two phases so the expensive packaging phase can be committed into a
# reusable intermediate image:
#
#   packages  → plan.sh + snapshot.sh + repos.sh + packages.sh  (the slow part:
#               COPR enable + dnf install of omedora + the whole mapped base
#               set + Flatpaks; commit this once)
#   config    → system.sh + adopt.sh + finalize.sh + first-run.sh  (the fast
#               part: re-runnable any time a setup/adopt/finalize script or
#               the config payload changes)
#   all       → packages then config (one process; == a full install-4.sh run)
#
# WHY THIS IS STILL FAITHFUL. install-4.sh's body is exactly:
#     source omedora/install/{plan,snapshot,repos,packages,system,adopt,
#                             finalize,first-run}.sh
# in that order, after the root/Fedora/x86_64/sudo guards. This driver sources
# the exact same eight files in the exact same order — the only difference is
# the phase split point between packages.sh and system.sh (the same boundary
# the omedora RPM install crosses: everything after it runs from the INSTALLED
# payload). No step logic is duplicated or reordered here. It does NOT touch
# install-4.sh, so it adds zero upstream-rebase surface.
#
# Repo selection: by default repos.sh enables the LIVE omedora COPR (resolved
# by bin/omedora-copr from the version file → agaspar/omedora-4 on this line).
# When build-session.sh --local-repo injected /etc/yum.repos.d/omedora-local.repo
# first, repos.sh skips the COPR enable and dnf resolves the omedora packages
# from the local overlay instead — the hermetic, branch-payload path.
#
# Usage (inside the container, as omedora):
#   staged-install-4.sh packages   # plan + repos + package payload only
#   staged-install-4.sh config     # system/adopt/finalize/first-run only
#   staged-install-4.sh all        # both (equivalent to running install-4.sh)
#
# Writes its real exit code to /tmp/install.exit (machinectl shell swallows
# the program's exit code) and tees all output to /var/log/omarchy-install.log
# (pre-created omedora-writable by Dockerfile.base) so build-session.sh can
# copy a clean log out of the container.

set -eEo pipefail

phase="${1:?usage: staged-install-4.sh <packages|config|all>}"

# Mirror install-4.sh's environment exactly (it derives OMEDORA_REPO_ROOT from
# its own location; the baked tree lives at ~/.local/share/omarchy).
export OMEDORA_REPO_ROOT="${OMEDORA_REPO_ROOT:-$HOME/.local/share/omarchy}"
export OMARCHY_BRAND="${OMARCHY_BRAND:-omedora}"
export PATH="$OMEDORA_REPO_ROOT/bin:$PATH"
# The L4 build is unattended: print the full plan, then proceed past the gate.
export OMEDORA_PLAN_AUTOCONFIRM=1

LOG_FILE=/var/log/omarchy-install.log
exec > >(tee -a "$LOG_FILE") 2>&1

STEPS="$OMEDORA_REPO_ROOT/omedora/install"

run_packages() {
  # Everything up to and including the package payload: the disclosed plan
  # (autoconfirmed), the btrfs snapshot offer (degrades to a notice on
  # overlayfs), repo enables (COPR or the injected local overlay + RPM Fusion +
  # Flathub), then dnf install omedora + the mapped omarchy-base set +
  # Flatpaks (the logind session gives flatpak a real user bus).
  source "$STEPS/plan.sh"
  source "$STEPS/snapshot.sh"
  source "$STEPS/repos.sh"
  source "$STEPS/packages.sh"
}

run_config() {
  # Everything after the packages landed, running from the INSTALLED payload:
  # root system setup (Fedora-gated upstream scripts), the $HOME adopt
  # (backup-then-write skel replay), per-user finalize, and the first-run
  # hooks (a user session bus exists in the logind session, so they run now).
  source "$STEPS/system.sh"
  source "$STEPS/adopt.sh"
  source "$STEPS/finalize.sh"
  source "$STEPS/first-run.sh"
}

rm -f /tmp/install.exit
rc=0
case "$phase" in
  packages) run_packages || rc=$? ;;
  config)   run_config   || rc=$? ;;
  all)      { run_packages && run_config; } || rc=$? ;;
  *) echo "unknown phase: $phase" >&2; rc=2 ;;
esac
echo "$rc" >/tmp/install.exit
exit "$rc"
