#!/bin/bash
#
# L1 guard: BuildRequires on hypr libraries we vendor must carry a version floor.
#
# Fedora ships stale copies of these libraries under the same names (hyprutils
# 0.7.1, hyprlang 0.6.4, ...). An unversioned BuildRequires is satisfied by
# Fedora's copy, so a fresh COPR chroot that builds a consumer before our
# library lands links against the stale ABI without failing. The floor makes
# that build fail instead. It must not exceed the version we ship, or the
# stack becomes unbuildable.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

COPR_DIR="$ROOT/omedora/packaging/copr"
LIBS=(hyprutils hyprlang hyprcursor hyprgraphics hyprland-protocols hyprwayland-scanner)

version_le() {
  [[ $(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1) == "$1" ]]
}

for lib in "${LIBS[@]}"; do
  shipped=$(awk '/^Version:/ {print $2; exit}' "$COPR_DIR/$lib.spec")
  [[ -n $shipped ]] || fail "$lib.spec declares a Version"

  while IFS= read -r hit; do
    spec=${hit%%:*}
    spec=${spec##*/}
    line=${hit#*:}
    floor=$(sed -nE "s/.*\($lib\)[[:space:]]*>=[[:space:]]*([0-9][0-9.]*).*/\1/p" <<<"$line")
    if [[ -z $floor ]]; then
      fail "$spec: BuildRequires on $lib has a version floor"
    elif ! version_le "$floor" "$shipped"; then
      fail "$spec: $lib floor $floor does not exceed the shipped $shipped"
    else
      pass "$spec: $lib floor $floor is set and buildable (ships $shipped)"
    fi
  done < <(grep -HE "^BuildRequires:[[:space:]]+(pkgconfig|cmake)\($lib\)" "$COPR_DIR"/*.spec || true)
done

echo "# all hypr-buildrequires-floor tests passed"
