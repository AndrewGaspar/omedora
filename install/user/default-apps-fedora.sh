# Fedora-only: claim the default web browser and mailto handler ONLY IF UNSET.
# Sourced from bin/omarchy-provision-user's Fedora branch (never on Arch, where
# upstream's unconditional claims run byte-identically).
#
# On Fedora Workstation the user already has a default browser (Firefox) and
# may have a mail client wired to mailto:; forcing Chromium/HEY would silently
# clobber a real choice. So each handler is claimed only when nothing
# installed currently holds it. A stale handler pointing at an uninstalled app
# is NOT a choice we preserve. Ported from 3.8.2's install/config/mimetypes.sh
# helper pattern (desktop_id_is_installed + xdg-settings get / xdg-mime query).
# Disclosed at the install plan gate.

# True if $1 (a foo.desktop id) resolves to an installed application, i.e. the
# file exists under any XDG applications/ dir. Mirrors the lookup order the
# desktop spec uses ($XDG_DATA_HOME then $XDG_DATA_DIRS, defaulting per spec).
desktop_id_is_installed() {
  local id="$1" dir
  local home="${XDG_DATA_HOME:-$HOME/.local/share}"
  local dirs="${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  for dir in "$home" ${dirs//:/ }; do
    [[ -f "$dir/applications/$id" ]] && return 0
  done
  return 1
}

# --- default browser + http(s) handlers --------------------------------------
# `xdg-settings get` may fail, print an error, or emit an empty line when
# nothing is set — capture stdout only and trim whitespace.
current_browser="$(xdg-settings get default-web-browser 2>/dev/null | head -n1)"
current_browser="${current_browser//[[:space:]]/}"

if [[ -n $current_browser && $current_browser == *.desktop ]] &&
  desktop_id_is_installed "$current_browser"; then
  echo "Keeping existing default browser: $current_browser"
else
  echo "No default browser set; using Chromium."
  xdg-settings set default-web-browser chromium.desktop
  xdg-mime default chromium.desktop x-scheme-handler/http
  xdg-mime default chromium.desktop x-scheme-handler/https
fi

# --- mailto handler ------------------------------------------------------------
current_mailto="$(xdg-mime query default x-scheme-handler/mailto 2>/dev/null | head -n1)"
current_mailto="${current_mailto//[[:space:]]/}"

if [[ -n $current_mailto && $current_mailto == *.desktop ]] &&
  desktop_id_is_installed "$current_mailto"; then
  echo "Keeping existing mailto handler: $current_mailto"
else
  echo "No mailto handler set; using HEY."
  xdg-mime default HEY.desktop x-scheme-handler/mailto
fi
