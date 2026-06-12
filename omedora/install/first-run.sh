# First-run hooks (welcome notification, user systemd units, GNOME prefs,
# update/Wi-Fi toasts). Upstream autostarts omarchy-first-run from the
# Hyprland session (default/hypr/autostart.lua), and those steps need a live
# user session bus + notification server — which a fresh-install terminal (or
# a container) usually doesn't have. So: only run it now when a user bus
# exists; otherwise it runs automatically at the first Omedora login.

if [[ -S /run/user/$(id -u)/bus || -n ${DBUS_SESSION_BUS_ADDRESS:-} ]]; then
  echo -e "\n\e[32mOmedora: running first-run hooks (a user session bus is live)\e[0m"
  omarchy-first-run || true
else
  echo -e "\n\e[33mOmedora: no user session bus; first-run hooks will run at your first Omedora login.\e[0m"
fi
