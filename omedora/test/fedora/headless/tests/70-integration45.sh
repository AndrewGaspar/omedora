#!/bin/bash
#
# L4-headless: Omarchy 4.5 desktop integration that depends on Fedora's
# package layout.
#
#   1. Dock pins: every id in config/omarchy/shell.json's dock.pinned resolves
#      to an installed .desktop file. Dock.qml drops a pin with no desktop
#      entry, so an unresolved id silently vanishes from the dock.
#   2. Chromium: Fedora ships chromium-browser; omedora/install/chromium-bridge.sh
#      provides the chromium.desktop the pin names. A running Chromium window
#      must map back to that entry (app id == pin, or the entry's
#      StartupWMClass), or the dock shows a second, unpinned icon.
#   3. fcitx5: QT_IM_MODULE=fcitx needs the Qt 6 input-context plugin, and
#      omarchy-theme-set-fcitx5 copies glyphs from the packaged default theme.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
headless_session_env

desktop_file_for() {
  local id=$1 dir
  local -a dirs=("${XDG_DATA_HOME:-$HOME/.local/share}")
  IFS=: read -r -a system_dirs <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
  dirs+=("${system_dirs[@]}" "$HOME/.local/share/flatpak/exports/share" /var/lib/flatpak/exports/share)
  for dir in "${dirs[@]}"; do
    [[ -f $dir/applications/$id.desktop ]] && { printf '%s\n' "$dir/applications/$id.desktop"; return 0; }
  done
  return 1
}

# --- 1. dock pins resolve --------------------------------------------------------
shell_json=$HOME/.config/omarchy/shell.json
[[ -f $shell_json ]] || shell_json=$OMARCHY_PATH/config/omarchy/shell.json
mapfile -t pins < <(jq -r '.dock.pinned[]?' "$shell_json" 2>/dev/null)
(( ${#pins[@]} > 0 )) || _fail_with_artifacts "the dock config lists pinned apps ($shell_json)"
missing=()
for pin in "${pins[@]}"; do
  file=$(desktop_file_for "$pin") || { missing+=("$pin"); continue; }
  echo "# pin $pin -> $file"
done
(( ${#missing[@]} == 0 )) \
  && pass "every dock pin resolves to a desktop entry (${pins[*]})" \
  || _fail_with_artifacts "dock pins without a desktop entry: ${missing[*]}"

# --- 2. Chromium's window maps back to its pin -------------------------------------
if [[ " ${pins[*]} " == *" chromium "* ]] && chromium_desktop=$(desktop_file_for chromium); then
  profile=$(mktemp -d)
  exec_line=$(sed -n 's/^Exec=//p' "$chromium_desktop" | head -1)
  read -r -a exec_words <<<"${exec_line//%U/}"
  setsid "${exec_words[@]}" --user-data-dir="$profile" --no-first-run --no-default-browser-check \
    about:blank >"$ARTIFACTS/chromium.log" 2>&1 &
  app_id=""
  for _ in $(seq 1 60); do
    app_id=$(hyprctl clients -j 2>/dev/null | jq -r '[.[] | select(.class | test("chrom"; "i"))][0].class // empty')
    [[ -n $app_id ]] && break
    sleep 0.5
  done
  wm_class=$(sed -n 's/^StartupWMClass=//p' "$chromium_desktop" | head -1)
  echo "# chromium window app id: ${app_id:-none}; chromium.desktop StartupWMClass: ${wm_class:-unset}"
  if [[ -z $app_id ]]; then
    _fail_with_artifacts "Chromium opens a window from the pinned chromium.desktop"
  elif [[ ${app_id,,} == "chromium" || ( -n $wm_class && ${app_id,,} == "${wm_class,,}" ) ]]; then
    pass "Chromium's window ($app_id) maps to the pinned chromium entry"
  else
    _fail_with_artifacts "Chromium's window ($app_id) maps to the pinned chromium entry (StartupWMClass=${wm_class:-unset})"
  fi
  pkill -f -- "--user-data-dir=$profile" 2>/dev/null || true
  sleep 1
  rm -rf "$profile"
else
  pass "# SKIP Chromium window class: chromium is not pinned or has no desktop entry"
fi

# --- 3. fcitx5 Qt 6 plugin and packaged theme glyphs --------------------------------
plugin=$(ls /usr/lib64/qt6/plugins/platforminputcontexts/libfcitx5platforminputcontextplugin.so 2>/dev/null)
[[ -n $plugin ]] \
  && pass "the fcitx5 Qt 6 input-context plugin is installed ($(rpm -qf "$plugin" 2>/dev/null))" \
  || _fail_with_artifacts "the fcitx5 Qt 6 input-context plugin is installed"
shopt -s nullglob
glyphs=(/usr/share/fcitx5/themes/default/*.svg)
(( ${#glyphs[@]} > 0 )) \
  && pass "fcitx5's default theme ships SVG glyphs (${#glyphs[@]})" \
  || _fail_with_artifacts "fcitx5's default theme ships SVG glyphs (/usr/share/fcitx5/themes/default/*.svg)"
