#!/bin/bash
#
# Byte-identity audit: the omedora stack must touch upstream files ADDITIVELY.
#
# Omedora is a port that layers on top of an upstream omarchy-4 pin tag. To keep
# the rebase surface small and the upstream contract honest, our changes to
# files that ALSO exist upstream are constrained: every modified upstream file's
# diff against the pin must be ADDITIVE-ONLY (new lines, no deleted lines),
# EXCEPT for a small, explicitly documented per-file allowlist of deleted lines.
#
# The only legitimate deletions are the documented "if/else relocations": a few
# install/update scripts wrap an upstream action in a distro gate
#   -  <upstream unconditional action>
#   +  if fedora; then <fedora variant>; else <the same upstream action>; fi
# so the original UNCONDITIONAL line is deleted and re-added inside the Arch
# (else) branch. We allowlist exactly those deleted line texts, per file, so the
# relocation is permitted but a NEW, undocumented deletion (e.g. someone quietly
# dropping an upstream behavior) trips the audit.
#
# We deliberately keep ZERO shell/ patches: the one we briefly carried
# (Background.qml's updatesEnabled guard, for Fedora's old quickshell) was
# dropped once quickshell 0.3.0 was vendored — vendoring fixed the root cause,
# so the file is byte-identical to upstream again and isn't in the audit set.
#
# Maintenance: when you add a NEW gated relocation that deletes an upstream line,
# add the deleted line text to ALLOW["<path>"] below with a one-line note. When
# the pin tag rotates (rebase), the test re-derives it from architecture.md, so
# no edit is needed here unless the relocation set itself changes.
#
# Runs in CI (L1 job). Pure git + bash; no container.

set -euo pipefail

. "$(dirname -- "${BASH_SOURCE[0]}")/helpers.sh"

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO"

# --- resolve the upstream pin tag --------------------------------------------
# Single source of truth: omedora/architecture.md records the current pin so the
# audit auto-tracks rebases. Allow an override for local experiments.
PIN="${OMEDORA_BASE_TAG:-}"
if [[ -z $PIN ]]; then
  PIN=$(grep -oE 'omedora-base-[0-9]+-omarchy4-[0-9a-f]+' omedora/architecture.md | head -1 || true)
fi
if [[ -z $PIN ]]; then
  fail "could not determine the upstream pin tag (set OMEDORA_BASE_TAG or fix omedora/architecture.md)"
fi
if ! git rev-parse -q --verify "refs/tags/$PIN" >/dev/null 2>&1 && ! git rev-parse -q --verify "$PIN" >/dev/null 2>&1; then
  # In a shallow CI checkout the pin tag may be absent. Skip rather than fail so
  # the gate is a no-op where it can't run, and meaningful where it can.
  pass "# SKIP byte-identity audit: pin '$PIN' not present in this checkout (shallow clone?)"
  exit 0
fi
echo "# auditing against pin: $PIN"

# --- per-file allowlist of PERMITTED deleted lines ---------------------------
# Key: repo-relative path. Value: newline-separated EXACT deleted line texts
# (leading whitespace significant; the diff '-' marker is stripped before
# matching). Every other deleted line in that file => audit failure. A file not
# listed here must be PURELY additive (zero deletions).
#
# Each entry is a documented if/else relocation: the upstream line moved into the
# Arch branch of a Fedora-gate, so it shows up as a deletion at the old site.
declare -A ALLOW

ALLOW["bin/omarchy-finalize-user"]='xdg-settings set default-web-browser chromium.desktop
xdg-mime default HEY.desktop x-scheme-handler/mailto'

# voxtype install: the upstream unconditional package line moved into the Arch
# arm of a distro case (verbatim) so Fedora dispatches to the omedora flavor
# installer (base voxtype RPM + auto-detected GPU add-on) instead of the Arch
# voxtype-bin package. The REMOVE script is byte-identical to upstream again
# (`omarchy-pkg-drop voxtype-bin` -> dnf remove voxtype, which cascades to the
# installed -cuda/-migraphx subpackages), so it has NO allowlist entry.
ALLOW["bin/omarchy-voxtype-install"]='  omarchy-pkg-add wtype voxtype-bin'

ALLOW["bin/omarchy-update"]='if [[ -z ${OMARCHY_UPDATE_LOGGED:-} ]]; then
trap '"'"'echo ""; echo -e "\033[0;31mSomething went wrong during the update!\n\nPlease review the output above carefully, correct the error, and retry the update.\n\nIf you need assistance, get help from the community at https://omarchy.org/discord\033[0m"'"'"' ERR'

ALLOW["bin/omarchy-update-confirm"]='  "What'"'"'s new: https://github.com/basecamp/omarchy/releases/latest"'

ALLOW["bin/omarchy-update-restart"]='  if [[ -f $kernel ]] && pacman -Qo "$kernel" &>/dev/null; then'

# omarchy-debug: the inline expac/pacman package-list moved into the Arch arm of
# a distro case (verbatim) so Fedora can use rpm/dnf; the heredoc now prints
# $PKG_LIST.
ALLOW["bin/omarchy-debug"]='$({ expac -S '"'"'%n %v (%r)'"'"' $(pacman -Qqe) 2>/dev/null; comm -13 <(pacman -Sql | sort) <(pacman -Qqe | sort) | xargs -r expac -Q '"'"'%n %v (AUR)'"'"'; } | sort)'

# The About (fastfetch) OS line is brand-aware on Fedora (shows the Omedora +
# Fedora versions); the Arch branch reproduces the upstream line verbatim.
ALLOW["etc/fastfetch/config.jsonc"]='      "text": "version=$(omarchy-version) && echo \"Omarchy $version\""'


# --- the audit ---------------------------------------------------------------
# Modified upstream files = files that differ from the pin AND exist on the pin
# (so omedora-ADDED files like bin/omedora-* are out of scope — they have no
# upstream to diverge from).
modified_upstream=()
while IFS= read -r f; do
  [[ -n $f ]] || continue
  git cat-file -e "$PIN:$f" 2>/dev/null && modified_upstream+=("$f")
done < <(git diff --name-only "$PIN")

if (( ${#modified_upstream[@]} == 0 )); then
  fail "no modified upstream files found vs $PIN — the audit found nothing to check (bad pin?)"
fi
echo "# modified upstream files: ${#modified_upstream[@]}"

# For one file, return its deleted lines (diff '-' body lines, marker stripped).
deleted_lines() {
  git diff "$PIN" -- "$1" | sed -n 's/^-\([^-].*\)$/\1/p; s/^-$//p'
}

# Membership test: is $line in the (newline-separated) allowlist blob $2?
allowed() {
  local line="$1" blob="$2" entry
  # Compare line-by-line for an exact match (handles lines with special chars).
  while IFS= read -r entry; do
    [[ "$line" == "$entry" ]] && return 0
  done <<<"$blob"
  return 1
}

violations=0
for f in "${modified_upstream[@]}"; do
  blob="${ALLOW[$f]:-}"
  file_bad=0
  bad_lines=()
  while IFS= read -r dl; do
    # An empty deleted line (a removed blank line) is benign whitespace churn;
    # treat it as allowed implicitly.
    [[ -z $dl ]] && continue
    if ! allowed "$dl" "$blob"; then
      file_bad=1
      bad_lines+=("$dl")
    fi
  done < <(deleted_lines "$f")

  if (( file_bad )); then
    violations=$((violations + 1))
    printf '# UNALLOWED deletion(s) in %s:\n' "$f" >&2
    printf '#   - %s\n' "${bad_lines[@]}" >&2
    printf 'not ok - %s is additive-only (or allowlisted deletions)\n' "$f" >&2
  else
    if [[ -n $blob ]]; then
      pass "$f: deletions limited to the allowlisted relocations"
    else
      pass "$f: additive-only (no deleted lines)"
    fi
  fi
done

# Guard against allowlist rot: an ALLOW entry for a file that is no longer
# modified (or no longer deletes that line) is dead config — flag it so the table
# stays honest as relocations are unwound.
for f in "${!ALLOW[@]}"; do
  found=0
  for m in "${modified_upstream[@]}"; do [[ "$m" == "$f" ]] && found=1 && break; done
  if (( ! found )); then
    echo "# WARNING: allowlist has a stale entry (file no longer modified vs pin): $f" >&2
  fi
done

if (( violations > 0 )); then
  fail "byte-identity audit: $violations file(s) have undocumented upstream deletions"
fi

pass "byte-identity audit: all ${#modified_upstream[@]} modified upstream files are additive-only or allowlisted"
