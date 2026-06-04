source $OMARCHY_INSTALL/preflight/guard.sh
source $OMARCHY_INSTALL/preflight/begin.sh
run_logged $OMARCHY_INSTALL/preflight/show-env.sh

# Fedora-only repo enablement (RPM Fusion + Hyprland COPR + Flathub).
# Inserted between show-env and the Arch-only pacman setup so it runs early
# enough that subsequent packaging stages can pull from the new repos.
if [[ $(omarchy-distro 2>/dev/null || echo arch) == "fedora" ]]; then
  run_logged $OMARCHY_INSTALL/preflight/fedora-repos.sh
  # Detect (and warn about) pre-existing foreign-repo Hyprland packages on a
  # lived-in Fedora machine before omedora installs its pinned stack over them.
  run_logged $OMARCHY_INSTALL/preflight/fedora-conflicts.sh
fi

run_logged $OMARCHY_INSTALL/preflight/pacman.sh
run_logged $OMARCHY_INSTALL/preflight/migrations.sh
run_logged $OMARCHY_INSTALL/preflight/first-run-mode.sh
run_logged $OMARCHY_INSTALL/preflight/disable-mkinitcpio.sh
