# shellcheck shell=bash
# Host-side helper: which checkout an L4 session image was built from.
#
# Sourced (never executed) by the L4 runners with $REPO set to the checkout
# root. build-session.sh copies the checkout into every build container right
# before each install phase (checkout_stream) and labels the images it commits
# with checkout_tree_id; the runners compare that label with the checkout they
# run from (checkout_image_check), so a session image built from another
# commit is reported instead of silently tested.

CHECKOUT_TREE_LABEL=omedora.tree

# checkout_files — NUL-separated paths of the files a build copies: tracked
# files plus untracked files that are not ignored (so uncommitted work is
# tested), minus tracked files deleted from the working tree. Ignored build
# output (packaging/copr/output*, repo*, test artifacts) and .git stay out.
checkout_files() {
  local f
  git -C "$REPO" ls-files -z --cached --others --exclude-standard |
    while IFS= read -r -d '' f; do
      [[ -e $REPO/$f || -L $REPO/$f ]] && printf '%s\0' "$f"
    done
}

# checkout_tree_id — HEAD's full sha, plus "-dirty-<hash>" of the uncommitted
# changes (tracked diff + untracked names) when there are any.
checkout_tree_id() {
  local head dirty
  head=$(git -C "$REPO" rev-parse HEAD)
  if [[ -n $(git -C "$REPO" status --porcelain 2>/dev/null) ]]; then
    dirty=$({ git -C "$REPO" diff HEAD; git -C "$REPO" ls-files --others --exclude-standard; } |
      sha256sum | cut -c1-12)
    printf '%s-dirty-%s\n' "$head" "$dirty"
  else
    printf '%s\n' "$head"
  fi
}

# checkout_stream — a tar stream of checkout_files on stdout.
checkout_stream() {
  checkout_files | tar -C "$REPO" --null -T - -cf -
}

# checkout_image_tree <image> — the checkout the image was built from ("" when
# it predates the label).
checkout_image_tree() {
  podman image inspect -f "{{index .Labels \"$CHECKOUT_TREE_LABEL\"}}" "$1" 2>/dev/null |
    sed 's/^<no value>$//'
}

# checkout_image_check <image> <rebuild-hint> — warn (stderr) when <image> was
# not built from this checkout. Never fails: an image built from another tree
# can be what the caller wants, but it must not pass silently.
checkout_image_check() {
  local image="$1" hint="$2" built current
  built=$(checkout_image_tree "$image")
  current=$(checkout_tree_id)
  [[ $built == "$current" ]] && return 0
  printf '\033[1;33mwarning:\033[0m %s was built from %s, but this checkout is %s.\n' \
    "$image" "${built:-an unrecorded tree (it predates the $CHECKOUT_TREE_LABEL label)}" "$current" >&2
  printf '  Its install scripts and config payload are not this checkout'"'"'s; rebuild with: %s\n' "$hint" >&2
}
