source $OMARCHY_INSTALL/preflight/guard.sh

# Fedora coexistence gate: aggregate everything the install will back up /
# replace (config files, foreign-repo Hyprland packages, the ~/.bashrc block)
# and get ONE up-front confirmation BEFORE any change. This MUST run before
# begin.sh: it's the only interactive zone — every run_logged script after
# begin.sh has stdin=/dev/null and its output goes to the log, so a prompt there
# can neither be answered nor seen. Abort here exits with nothing touched.
if [[ $(omarchy-distro 2>/dev/null || echo arch) == "fedora" ]]; then
  source $OMARCHY_INSTALL/preflight/fedora-plan.sh
fi

source $OMARCHY_INSTALL/preflight/begin.sh
run_logged $OMARCHY_INSTALL/preflight/show-env.sh

# Pre-install btrfs snapshot, if opted into at the gate (OMEDORA_SNAPSHOT=1).
# FIRST thing after begin.sh — before the COPR is enabled or any package/config
# change — so it captures the pristine state. No-op otherwise.
if [[ $(omarchy-distro 2>/dev/null || echo arch) == "fedora" ]]; then
  run_logged $OMARCHY_INSTALL/preflight/fedora-snapshot.sh
fi

# Fedora-only repo enablement (RPM Fusion + omedora COPR + Flathub).
# Inserted between show-env and the Arch-only pacman setup so it runs early
# enough that subsequent packaging stages can pull from the new repos.
if [[ $(omarchy-distro 2>/dev/null || echo arch) == "fedora" ]]; then
  run_logged $OMARCHY_INSTALL/preflight/fedora-repos.sh
  # If the gate recorded a "Replace" choice, swap the foreign-repo Hyprland
  # packages for omedora's now that the omedora repos are enabled. No-op
  # otherwise. Must run AFTER fedora-repos.sh (needs the omedora COPR).
  run_logged $OMARCHY_INSTALL/preflight/fedora-swap.sh
fi

run_logged $OMARCHY_INSTALL/preflight/pacman.sh
run_logged $OMARCHY_INSTALL/preflight/migrations.sh
run_logged $OMARCHY_INSTALL/preflight/first-run-mode.sh
run_logged $OMARCHY_INSTALL/preflight/disable-mkinitcpio.sh
