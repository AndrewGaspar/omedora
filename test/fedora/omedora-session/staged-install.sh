#!/bin/bash
#
# Staged driver for the L4 session build (run as omedora inside the logind
# session via `machinectl shell`). It sources the SAME real install stages, in
# the SAME order, as the upstream install.sh — but lets build-session.sh run
# them in two phases so the expensive packaging phase can be committed into a
# reusable intermediate image:
#
#   packages  → preflight/all.sh + packaging/all.sh   (the slow ~3 min part:
#               dnf install of the whole package set; commit this once)
#   config    → config/all.sh                         (the fast ~10 s part:
#               re-runnable any time you edit a config script)
#   all       → packages then config (one process; == a full install.sh run)
#
# WHY THIS IS STILL FAITHFUL. install.sh's body is just:
#     source helpers/all.sh; source preflight/all.sh
#     source packaging/all.sh; source config/all.sh
# (login/ + post-install/ are Arch-only and skipped on Fedora). This driver
# sources the exact same four all.sh files in the exact same order — the only
# difference is the phase split point. No stage logic is duplicated or
# reordered here; it just calls into the upstream/omedora install tree. So the
# committed images are byte-equivalent to what a plain `install.sh` produces,
# and the default build path (test/fedora/build-session.sh with no flags) still
# runs the whole thing in one go.
#
# It does NOT touch install.sh, so it adds zero upstream-rebase surface.
#
# Usage (inside the container, as omedora):
#   staged-install.sh packages   # preflight + packaging only
#   staged-install.sh config     # config only (against an already-packaged fs)
#   staged-install.sh all        # both (equivalent to running install.sh)
#
# Writes its real exit code to /tmp/install.exit (machinectl shell swallows the
# program's exit code), exactly like build-session.sh's old inline invocation.

set -eEo pipefail

phase="${1:?usage: staged-install.sh <packages|config|all>}"

export OMARCHY_PATH="$HOME/.local/share/omarchy"
export OMARCHY_INSTALL="$OMARCHY_PATH/install"
export OMARCHY_INSTALL_LOG_FILE="/var/log/omarchy-install.log"
export PATH="$OMARCHY_PATH/bin:$PATH"

# helpers/all.sh defines run_logged + the logging/error scaffolding every stage
# expects; it must be sourced before any stage in every phase.
source "$OMARCHY_INSTALL/helpers/all.sh"

run_packages() {
  # preflight/all.sh sources guard.sh + begin.sh (which calls start_install_log,
  # printing the "=== Started ===" banner and starting the live log tail), then
  # the fedora-repos / pacman / migrations / first-run preflight scripts, then
  # packaging/all.sh (base.sh = the big dnf install + the per-feature packaging).
  source "$OMARCHY_INSTALL/preflight/all.sh"
  source "$OMARCHY_INSTALL/packaging/all.sh"
}

run_config() {
  # config/all.sh re-applies the user-level config (config.sh, theme.sh,
  # walker-elephant.sh, the fedora default-terminal/-browser, ...). Idempotent:
  # mkdir -p / symlink / copy — safe to re-run against an already-packaged fs.
  #
  # In the `config`-only phase the packaging phase already ran in a *previous*
  # container, so the logging scaffolding from begin.sh isn't active here. Make
  # sure the log file exists + the start marker is present so run_logged and the
  # error handler behave; begin.sh's live-tail UI isn't needed for a commit.
  if ! grep -q '=== Omarchy Installation Started' "$OMARCHY_INSTALL_LOG_FILE" 2>/dev/null; then
    sudo touch "$OMARCHY_INSTALL_LOG_FILE"
    sudo chmod 666 "$OMARCHY_INSTALL_LOG_FILE"
    echo "=== Omarchy Installation Started (config-only): $(date '+%Y-%m-%d %H:%M:%S') ===" \
      >>"$OMARCHY_INSTALL_LOG_FILE"
  fi
  source "$OMARCHY_INSTALL/config/all.sh"
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
