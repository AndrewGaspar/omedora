# shellcheck shell=bash
# Fedora Cloud Base image selection for the VM tier — sourced by run-vm-test.sh
# and run-snapshot-vm-test.sh after omedora/test/fedora/lib/release.sh.
#
# Maps OMEDORA_FEDORA_RELEASE to a Generic Cloud Base qcow2, in this order:
#
#   1. Overrides: OMEDORA_VM_BASE_URL (full qcow2 URL) and/or
#      OMEDORA_VM_BASE_NAME (cache file name; defaults to the URL's basename).
#      OMEDORA_VM_BASE_SHA256 pins the expected digest of a fresh download.
#   2. A pinned GA compose from OMEDORA_VM_PINNED_IMAGES below. Add a release's
#      GA image here once it ships (releases/<N>/Cloud/x86_64/images/).
#   3. The newest image for the release already in the cache — so a machine that
#      has one keeps using it offline and the test base does not churn with
#      every nightly. OMEDORA_VM_BASE_REFRESH=1 skips this and rediscovers.
#   4. Discovery: list releases/<N>/ (GA), then development/<N>/ (pre-GA
#      nightlies, e.g. Generic-45-20261021.n.0) on dl.fedoraproject.org and take
#      the highest-versioned Generic qcow2.
#
# Downloads land in $IMAGES/<name>.part, are verified against the directory's
# CHECKSUM file (or OMEDORA_VM_BASE_SHA256), and only then move into place.

OMEDORA_VM_FEDORA_MIRROR="${OMEDORA_VM_FEDORA_MIRROR:-https://dl.fedoraproject.org/pub/fedora/linux}"

# release -> pinned GA image URL.
declare -A OMEDORA_VM_PINNED_IMAGES=(
  [44]="https://download.fedoraproject.org/pub/fedora/linux/releases/44/Cloud/x86_64/images/Fedora-Cloud-Base-Generic-44-1.7.x86_64.qcow2"
)

# Print the newest Generic qcow2 basename listed at <dir_url> for the release.
_vm_base_newest_in_listing() {
  local dir_url=$1
  curl -fsSL --max-time 30 "$dir_url" 2>/dev/null |
    grep -oE "Fedora-Cloud-Base-Generic-$OMEDORA_FEDORA_RELEASE-[A-Za-z0-9._]+\.x86_64\.qcow2" |
    sort -uV | tail -n1
}

# resolve_base_image — sets BASE_IMG_NAME, BASE_IMG_URL and BASE_IMG ($IMAGES
# must be set). BASE_IMG_URL is empty when a cached image is used as-is.
resolve_base_image() {
  local rel=$OMEDORA_FEDORA_RELEASE kind dir_url name cached
  BASE_IMG_URL="${OMEDORA_VM_BASE_URL:-}"
  BASE_IMG_NAME="${OMEDORA_VM_BASE_NAME:-}"

  if [[ -z $BASE_IMG_URL && -n ${OMEDORA_VM_PINNED_IMAGES[$rel]:-} ]]; then
    BASE_IMG_URL=${OMEDORA_VM_PINNED_IMAGES[$rel]}
  fi

  if [[ -z $BASE_IMG_URL && -z $BASE_IMG_NAME && ${OMEDORA_VM_BASE_REFRESH:-0} != "1" ]]; then
    cached=$(find "$IMAGES" -maxdepth 1 -type f \
      -name "Fedora-Cloud-Base-Generic-$rel-*.x86_64.qcow2" -printf '%f\n' 2>/dev/null | sort -V | tail -n1)
    [[ -n $cached ]] && BASE_IMG_NAME=$cached
  fi

  if [[ -z $BASE_IMG_URL && -z $BASE_IMG_NAME ]]; then
    for kind in releases development; do
      dir_url="$OMEDORA_VM_FEDORA_MIRROR/$kind/$rel/Cloud/x86_64/images/"
      name=$(_vm_base_newest_in_listing "$dir_url")
      if [[ -n $name ]]; then
        BASE_IMG_URL="$dir_url$name"
        break
      fi
    done
  fi

  [[ -z $BASE_IMG_NAME && -n $BASE_IMG_URL ]] && BASE_IMG_NAME=${BASE_IMG_URL##*/}
  if [[ -z $BASE_IMG_NAME ]]; then
    echo "no Fedora $rel Cloud Base image cached or found under $OMEDORA_VM_FEDORA_MIRROR/{releases,development}/$rel/Cloud/x86_64/images/;" \
      "set OMEDORA_VM_BASE_URL" >&2
    return 1
  fi
  BASE_IMG="$IMAGES/$BASE_IMG_NAME"
}

# Print the expected sha256 for BASE_IMG_NAME from the CHECKSUM file(s) next to
# BASE_IMG_URL (Fedora publishes "SHA256 (<name>) = <hex>" lines).
_vm_base_expected_sha256() {
  local dir_url=${BASE_IMG_URL%/*}/ checksum_file
  [[ -n ${OMEDORA_VM_BASE_SHA256:-} ]] && { echo "$OMEDORA_VM_BASE_SHA256"; return; }
  # download.fedoraproject.org redirects to a mirror; list the CHECKSUM from the
  # same directory, which every mirror carries alongside the image.
  for checksum_file in $(curl -fsSL --max-time 30 "$dir_url" 2>/dev/null |
    grep -oE '[A-Za-z0-9._-]+-CHECKSUM' | sort -u); do
    curl -fsSL --max-time 30 "$dir_url$checksum_file" 2>/dev/null |
      sed -nE "s/^SHA256 \\($BASE_IMG_NAME\\) = ([0-9a-f]{64})$/\\1/p" | head -n1
  done | head -n1
}

# ensure_base_image <log-fn> — download + verify BASE_IMG if it isn't cached.
ensure_base_image() {
  local log_fn=${1:-echo} want got
  [[ -f $BASE_IMG ]] && return 0
  [[ -n $BASE_IMG_URL ]] || { echo "base image $BASE_IMG missing and no URL to fetch it" >&2; return 1; }

  "$log_fn" "base image not cached; downloading Fedora $OMEDORA_FEDORA_RELEASE Cloud Base $BASE_IMG_NAME (~600MB)..."
  curl -fSL -o "$BASE_IMG.part" "$BASE_IMG_URL" || { rm -f "$BASE_IMG.part"; echo "base image download failed: $BASE_IMG_URL" >&2; return 1; }

  want=$(_vm_base_expected_sha256)
  if [[ -n $want ]]; then
    got=$(sha256sum "$BASE_IMG.part" | awk '{print $1}')
    if [[ $got != "$want" ]]; then
      rm -f "$BASE_IMG.part"
      echo "base image checksum mismatch for $BASE_IMG_NAME (want $want, got $got)" >&2
      return 1
    fi
    "$log_fn" "base image sha256 verified"
  else
    echo "WARNING: no published SHA256 found for $BASE_IMG_NAME; using it unverified" >&2
  fi
  mv "$BASE_IMG.part" "$BASE_IMG"
}
