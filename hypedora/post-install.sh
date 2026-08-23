#!/bin/bash
# hypedora post-install: idempotent. (1) overlay-ul personal din hypedora/overlay/
# (copiat peste ~/.config, cu backup .pre-hypedora); (2) sub VM, cursor software —
# același tweak pe care omedora îl face pentru nouveau (install/user/hardware/fix-nouveau-cursor.sh),
# pentru că virtio-gpu/virgl nu afișează de regulă planul de cursor hardware.
set -euo pipefail
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"

# (1) overlay
if [[ -d "$HERE/overlay" ]] && find "$HERE/overlay" -type f | grep -q .; then
  while IFS= read -r -d '' f; do
    rel="${f#"$HERE/overlay/"}"; dst="$CFG/$rel"
    mkdir -p "$(dirname "$dst")"
    if [[ -f "$dst" ]] && ! cmp -s "$f" "$dst"; then cp -a "$dst" "$dst.pre-hypedora-$(date +%s)"; fi
    cp -a "$f" "$dst"
    echo "overlay: $rel"
  done < <(find "$HERE/overlay" -type f -print0)
fi

# (2) tweak de VM
if systemd-detect-virt --quiet 2>/dev/null; then
  virt=$(systemd-detect-virt 2>/dev/null || echo vm)
  mkdir -p "$CFG/hypr"; lf="$CFG/hypr/looknfeel.lua"; touch "$lf"
  if ! grep -q 'no_hardware_cursors = true' "$lf"; then
    cat >> "$lf" <<'EOF'

-- hypedora: rulăm într-o mașină virtuală; virtio-gpu/virgl nu afișează de regulă
-- cursorul hardware → îl randăm software (același tweak ca fix-nouveau-cursor.sh).
hl.config({ cursor = { no_hardware_cursors = true } })
EOF
    echo "vm ($virt): cursor software activat în hypr/looknfeel.lua"
  else
    echo "vm ($virt): tweak de cursor deja prezent"
  fi
fi
