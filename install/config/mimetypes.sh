# xdg-mime / xdg-settings ship with xdg-utils. On Fedora it isn't always
# pulled in by the base set; guard so a missing xdg-utils degrades to "no
# MIME defaults configured" rather than aborting the install.
if ! command -v xdg-mime >/dev/null 2>&1; then
  echo "xdg-mime not installed; skipping MIME default setup."
  return 0 2>/dev/null || exit 0
fi

omarchy-refresh-applications
update-desktop-database ~/.local/share/applications

# Open directories in file manager
xdg-mime default org.gnome.Nautilus.desktop inode/directory

# Open all images with imv
xdg-mime default imv.desktop image/png
xdg-mime default imv.desktop image/jpeg
xdg-mime default imv.desktop image/gif
xdg-mime default imv.desktop image/webp
xdg-mime default imv.desktop image/bmp
xdg-mime default imv.desktop image/tiff

# Open PDFs with the Document Viewer
xdg-mime default org.gnome.Evince.desktop application/pdf

# Use Chromium as the default browser.
#
# On Arch (upstream omarchy) this is unconditional — byte-identical to upstream.
# On Fedora Workstation the user already has a default (Firefox), and forcing
# Chromium here silently clobbers their choice. So on Fedora we only claim the
# default-browser / http(s) handlers when nothing is set yet. An existing,
# installed default is respected and left alone. See omedora/architecture.md.
set_chromium_default_browser() {
  xdg-settings set default-web-browser chromium.desktop
  xdg-mime default chromium.desktop x-scheme-handler/http
  xdg-mime default chromium.desktop x-scheme-handler/https
}

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

if [[ "$(omarchy-distro 2>/dev/null || echo arch)" == "fedora" ]]; then
  # `xdg-settings get default-web-browser` may fail, print an error, or emit an
  # empty line when nothing is set — capture stdout only and trim whitespace.
  current_browser="$(xdg-settings get default-web-browser 2>/dev/null | head -n1)"
  current_browser="${current_browser//[[:space:]]/}"

  # Treat as "already chosen" only if it's a non-empty .desktop id that resolves
  # to an actually-installed application (a real existing choice). A stale id
  # pointing at an uninstalled app is not a choice we should preserve.
  if [[ -n $current_browser && $current_browser == *.desktop ]] &&
    desktop_id_is_installed "$current_browser"; then
    echo "Keeping existing default browser: $current_browser"
  else
    echo "No default browser set; using Chromium."
    set_chromium_default_browser
  fi
else
  set_chromium_default_browser
fi

# Open video files with mpv
xdg-mime default mpv.desktop video/mp4
xdg-mime default mpv.desktop video/x-msvideo
xdg-mime default mpv.desktop video/x-matroska
xdg-mime default mpv.desktop video/x-flv
xdg-mime default mpv.desktop video/x-ms-wmv
xdg-mime default mpv.desktop video/mpeg
xdg-mime default mpv.desktop video/ogg
xdg-mime default mpv.desktop video/webm
xdg-mime default mpv.desktop video/quicktime
xdg-mime default mpv.desktop video/3gpp
xdg-mime default mpv.desktop video/3gpp2
xdg-mime default mpv.desktop video/x-ms-asf
xdg-mime default mpv.desktop video/x-ogm+ogg
xdg-mime default mpv.desktop video/x-theora+ogg
xdg-mime default mpv.desktop application/ogg

# Use Hey for mailto: links
xdg-mime default HEY.desktop x-scheme-handler/mailto

# Open text files with nvim
xdg-mime default nvim.desktop text/plain
xdg-mime default nvim.desktop text/english
xdg-mime default nvim.desktop text/x-makefile
xdg-mime default nvim.desktop text/x-c++hdr
xdg-mime default nvim.desktop text/x-c++src
xdg-mime default nvim.desktop text/x-chdr
xdg-mime default nvim.desktop text/x-csrc
xdg-mime default nvim.desktop text/x-java
xdg-mime default nvim.desktop text/x-moc
xdg-mime default nvim.desktop text/x-pascal
xdg-mime default nvim.desktop text/x-tcl
xdg-mime default nvim.desktop text/x-tex
xdg-mime default nvim.desktop application/x-shellscript
xdg-mime default nvim.desktop text/x-c
xdg-mime default nvim.desktop text/x-c++
xdg-mime default nvim.desktop application/xml
xdg-mime default nvim.desktop text/xml
