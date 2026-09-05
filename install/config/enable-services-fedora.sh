# Fedora sibling of install/config/enable-services.sh (dispatched from its top
# gate; runs as root under omarchy-setup-system).
#
# Coexistence rules vs the Arch body:
#   - Only enable units that actually exist on this machine (the component may
#     be skipped in the package map) and aren't already enabled — Fedora
#     Workstation already runs NetworkManager, systemd-resolved, bluetooth etc.
#   - NOT enabled here, deliberately:
#       NetworkManager.service / systemd-resolved.service  Fedora's network
#         stack is already configured; flipping it is the user's call.
#       power-profiles-daemon.service  Fedora ships tuned-ppd (which provides
#         the same D-Bus API); swapping power daemons is out of scope.
#       sddm.service  omedora stays on GDM — the packaged wayland-session
#         entry is how the Omedora session appears at login.
#       linux-modules-cleanup.service  an Arch packaging artifact; no Fedora
#         equivalent unit.

enable_if_present() {
  local unit="$1" state
  state="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
  case "$state" in
    "" | not-found) ;;                    # unit doesn't exist here — skip
    enabled | enabled-runtime | static | alias) ;; # already on — leave alone
    masked) ;;                            # admin-masked — respect it
    *) systemctl enable "$unit" ;;
  esac
}

enable_if_present cups.service
enable_if_present cups-browsed.service
enable_if_present avahi-daemon.service
enable_if_present docker.socket
