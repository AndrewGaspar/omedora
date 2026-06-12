# Fedora-only: bridge Chromium's Arch↔Fedora naming AND its launch flags.
# Ported from 3.8.2's install/config/default-browser-fedora.sh; sourced from
# omedora/install/finalize.sh (runs as the user). Disclosed at the plan gate.
#
# Two Fedora gaps vs Arch:
#  1. Naming: Fedora's chromium package installs the binary as
#     `chromium-browser` and the desktop entry as `chromium-browser.desktop`,
#     but omarchy hardcodes `chromium` / `chromium.desktop` (e.g.
#     bin/omarchy-launch-webapp falls back to `chromium.desktop`).
#  2. Flags: Arch's chromium launcher reads ~/.config/chromium-flags.conf and
#     applies it (that's where omarchy puts --ozone-platform=wayland etc.).
#     Fedora's chromium-browser is a plain binary that ignores the file — so
#     chromium falls back to X11 and fails to start in a Wayland session.
#
# Fix both with a `chromium` wrapper that reads the flags file (like Arch's
# launcher) and a chromium.desktop that points at it.

if command -v chromium >/dev/null 2>&1; then
  : # a real `chromium` entry point exists (e.g. user-installed); nothing to bridge
elif ! command -v chromium-browser >/dev/null 2>&1; then
  echo "chromium-browser not installed; skipping the Chromium bridge."
else
  # `chromium` wrapper: apply ~/.config/chromium-flags.conf, then exec Fedora's
  # binary. One flag per line; '#' comments and blanks skipped; '~' expanded.
  # rm -f first so re-runs don't write *through* a prior symlink/file.
  mkdir -p ~/.local/bin
  rm -f ~/.local/bin/chromium
  cat >~/.local/bin/chromium <<'WRAP'
#!/bin/bash
flags=()
conf="$HOME/.config/chromium-flags.conf"
if [[ -f $conf ]]; then
  while IFS= read -r line; do
    [[ -z $line || $line == \#* ]] && continue
    flags+=("${line//\~/$HOME}")
  done <"$conf"
fi
exec /usr/bin/chromium-browser "${flags[@]}" "$@"
WRAP
  chmod +x ~/.local/bin/chromium

  # chromium.desktop → the wrapper (absolute path, so uwsm-app/systemd scopes
  # resolve it regardless of their PATH).
  mkdir -p ~/.local/share/applications
  src=/usr/share/applications/chromium-browser.desktop
  dst=~/.local/share/applications/chromium.desktop
  if [[ -f $src ]]; then
    # Replace only the primary Exec= (leave [Desktop Action ...] Execs alone).
    sed "0,/^Exec=/s#^Exec=.*#Exec=$HOME/.local/bin/chromium %U#" "$src" >"$dst"
  fi

  # Hide Fedora's chromium-browser.desktop so the launcher shows one Chromium
  # (ours, Wayland-enabled) rather than two.
  cat >~/.local/share/applications/chromium-browser.desktop <<'EOF'
[Desktop Entry]
Hidden=true
EOF
  echo "Chromium bridge installed (~/.local/bin/chromium + chromium.desktop)."
fi
