#!/bin/bash
#
# Register + build the omedora package set on COPR, in dependency order.
#
# COPR does not guarantee build order within a project, but the Hyprland stack
# has deep intra-stack BuildRequires (each -devel must be published to the
# project repo before the next spec builds). We therefore register every spec as
# an SCM / make_srpm package (so COPR drives our .copr/Makefile), then build them
# ONE AT A TIME in the order build-repo.sh already encodes, waiting for each to
# finish before the next. This is the COPR analogue of build-repo.sh's
# incremental "fold each RPM into the local repo before the next build" loop.
#
# Usage:
#   copr-submit.sh register      # (re)register all packages (idempotent)
#   copr-submit.sh build         # build all, in order, waiting on each
#   copr-submit.sh all           # register, then build
#   copr-submit.sh build walker.spec swayosd.spec   # just these (still ordered)
#
#   # The Omarchy-4 line, later:
#   PROJECT=omedora-4 BRANCH=4-omedora copr-submit.sh all
#
# claude-code is intentionally excluded — it isn't in build-repo.sh's SPECS
# array (proprietary binary; redistribution undecided), so it never registers.

set -euo pipefail

COPR_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd -- "$COPR_DIR/../../.." && pwd)
# Default the project from the single source of truth (omedora-copr derives it
# from the Omarchy base version), stripping the owner/ prefix; override with
# PROJECT=... for a one-off (e.g. a new base line before `version` is bumped).
PROJECT="${PROJECT:-$(OMARCHY_PATH="$REPO_ROOT" "$REPO_ROOT/bin/omedora-copr" | cut -d/ -f2)}"
BRANCH="${BRANCH:-omarchy-4-omedora}"
CLONE_URL="${CLONE_URL:-https://github.com/AndrewGaspar/omedora.git}"
SUBDIR="omedora/packaging/copr"

# The canonical build order is build-repo.sh's SPECS array — parse it out so this
# stays DRY (and inherits the claude-code exclusion + the Hyprland-stack order).
# Strip comments first: claude-code.spec is named in a comment inside the array
# (intentionally NOT built — proprietary), so it must not leak into the build set.
mapfile -t ALL_SPECS < <(sed -n '/^SPECS=(/,/^)/p' "$COPR_DIR/build-repo.sh" \
  | sed 's/#.*//' | grep -oE '[a-zA-Z0-9._-]+\.spec')
(( ${#ALL_SPECS[@]} )) || { echo "no specs parsed from build-repo.sh" >&2; exit 1; }

# Optional exclusions, space-separated spec names — e.g. to skip an already-built
# package or one whose build policy is still open:
#   SKIP="walker.spec omarchy-nvim.spec" copr-submit.sh all
if [[ -n "${SKIP:-}" ]]; then
  declare -A _skip=(); for s in $SKIP; do _skip["$s"]=1; done
  _kept=(); for s in "${ALL_SPECS[@]}"; do [[ -z "${_skip[$s]:-}" ]] && _kept+=("$s"); done
  echo "skipping: $SKIP  (building ${#_kept[@]} of ${#ALL_SPECS[@]})"
  ALL_SPECS=("${_kept[@]}")
fi

register_one() {
  local spec="$1" name="${1%.spec}"
  # Upsert: add-package-scm creates (errors if it exists); edit-package-scm edits
  # (errors if it doesn't). Try add, fall back to edit — idempotent either way.
  local args=(
    --name "$name"
    --clone-url "$CLONE_URL"
    --commit "$BRANCH"
    --subdir "$SUBDIR"
    --spec "$spec"
    --type git
    --method make_srpm
    --timeout 18000
    --webhook-rebuild off
  )
  if copr-cli add-package-scm "$PROJECT" "${args[@]}" >/dev/null 2>&1; then
    echo "  added:  $name"
  elif copr-cli edit-package-scm "$PROJECT" "${args[@]}" >/dev/null 2>&1; then
    echo "  edited: $name"
  else
    echo "  FAILED to register: $name" >&2
    return 1
  fi
}

# Build one package and BLOCK until it reaches a terminal state, so the next
# (dependent) spec sees this one's RPMs in the project repo.
build_one() {
  local name="${1%.spec}"
  echo "==> building $name ($PROJECT) ..."
  copr-cli build-package "$PROJECT" --name "$name"
}

cmd="${1:-all}"; shift || true
# Optional explicit subset (still applied in canonical order).
if (( $# )); then
  declare -A want=(); for s in "$@"; do want["$s"]=1; done
  specs=(); for s in "${ALL_SPECS[@]}"; do [[ -n "${want[$s]:-}" ]] && specs+=("$s"); done
else
  specs=("${ALL_SPECS[@]}")
fi

case "$cmd" in
  register) for s in "${specs[@]}"; do register_one "$s"; done ;;
  build)    for s in "${specs[@]}"; do build_one "$s"; done ;;
  all)      for s in "${specs[@]}"; do register_one "$s"; done
            for s in "${specs[@]}"; do build_one "$s"; done ;;
  *) echo "usage: $0 {register|build|all} [<name>.spec ...]" >&2; exit 2 ;;
esac

echo "done ($cmd, ${#specs[@]} package(s), project $PROJECT)"
