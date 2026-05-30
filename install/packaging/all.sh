run_logged $OMARCHY_INSTALL/packaging/base.sh
# Fedora-only: desktop runtime Arch pulls transitively but Fedora's package set
# doesn't guarantee, and that omedora's own features need (xdg-utils, pipewire).
if [[ $(omarchy-distro 2>/dev/null || echo arch) == "fedora" ]]; then
  run_logged $OMARCHY_INSTALL/packaging/fedora-baseline.sh
fi
run_logged $OMARCHY_INSTALL/packaging/fonts.sh
run_logged $OMARCHY_INSTALL/packaging/nvim.sh
run_logged $OMARCHY_INSTALL/packaging/icons.sh
run_logged $OMARCHY_INSTALL/packaging/webapps.sh
run_logged $OMARCHY_INSTALL/packaging/tuis.sh
run_logged $OMARCHY_INSTALL/packaging/npx.sh
run_logged $OMARCHY_INSTALL/packaging/asus-rog.sh
run_logged $OMARCHY_INSTALL/packaging/framework16.sh
run_logged $OMARCHY_INSTALL/packaging/dell-xps-touchpad-haptics.sh
run_logged $OMARCHY_INSTALL/packaging/surface.sh
