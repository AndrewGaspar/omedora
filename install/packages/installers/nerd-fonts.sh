echo "Installing Nerd Fonts (CascadiaCode + JetBrainsMono) from ryanoasis/nerd-fonts..."

# Fedora's main repos ship plain JetBrains Mono and Cascadia Code, but NOT the
# Nerd Font-patched variants that carry the icon glyphs omedora's waybar,
# terminal, and prompts rely on. Without them, every icon renders as tofu
# (□). Fetch the patched archives from the upstream Nerd Fonts release and drop
# them into the user font dir.
#
# Arch equivalent: ttf-jetbrains-mono-nerd + ttf-cascadia-mono-nerd.

set -euo pipefail

NERD_VERSION="v3.4.0"
FONTS=("CascadiaCode" "JetBrainsMono")
DEST="$HOME/.local/share/fonts"
MARKER_DIR="$HOME/.local/state/omedora/installed-versions"

# Idempotent: skip if we already installed this exact version.
if [[ -f "$MARKER_DIR/ttf-jetbrains-mono-nerd" ]] &&
   [[ "$(cat "$MARKER_DIR/ttf-jetbrains-mono-nerd" 2>/dev/null)" == "$NERD_VERSION" ]]; then
  echo "Nerd Fonts $NERD_VERSION already installed; skipping."
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$DEST"
for font in "${FONTS[@]}"; do
  url="https://github.com/ryanoasis/nerd-fonts/releases/download/$NERD_VERSION/$font.tar.xz"
  echo "  fetching $font..."
  curl -fL --retry 3 -o "$tmp/$font.tar.xz" "$url"
  # Extract only the actual font files; skip the bundled READMEs/licenses.
  tar -xJf "$tmp/$font.tar.xz" -C "$DEST" --wildcards '*.ttf' '*.otf' 2>/dev/null || \
    tar -xJf "$tmp/$font.tar.xz" -C "$DEST"
done

# Rebuild the font cache so the new families are discoverable immediately.
fc-cache -f "$DEST" >/dev/null 2>&1 || fc-cache -f >/dev/null 2>&1 || true

# Version markers for both Arch package names this installer covers, so the
# update flow's drift check (is_installed_source) sees them as present.
mkdir -p "$MARKER_DIR"
printf '%s\n' "$NERD_VERSION" >"$MARKER_DIR/ttf-jetbrains-mono-nerd"
printf '%s\n' "$NERD_VERSION" >"$MARKER_DIR/ttf-cascadia-mono-nerd"

echo "Nerd Fonts $NERD_VERSION installed to $DEST."
