#!/bin/bash
#
# L1 static guard for omedora/packaging/copr/voxtype.spec (+ .sources).
#
# voxtype is hosted in the omedora COPR as a SUBPACKAGED binary-repackage of
# upstream's official Fedora RPM: one spec emits a slim base 'voxtype' (CPU +
# Vulkan + ONNX-CPU) plus opt-in voxtype-cuda (NVIDIA) and voxtype-migraphx (AMD)
# GPU add-ons. This audits the spec text so a rebase / edit can't silently
# collapse the split, leak the heavyweight GPU trees into the slim base, drop the
# subpackage version-lock, or desync the source pin. Pure bash + grep; no build.
#
# Asserts:
#   - the spec declares `%package cuda` and `%package migraphx`
#   - the base %files excludes the cuda-*/migraphx variant trees
#   - each subpackage %files owns its variant tree
#   - each subpackage Requires: voxtype = %{version}-%{release} (cascade lock)
#   - the base Requires: vulkan-loader (a HARD dep — pkg.py installs with
#     weak-deps off, so it must not be a Recommends)
#   - voxtype.spec.sources pins the sha for exactly Source0's basename

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SPEC="$ROOT/omedora/packaging/copr/voxtype.spec"
SOURCES="$ROOT/omedora/packaging/copr/voxtype.spec.sources"

assert_file_exists "voxtype.spec exists" "$SPEC"
assert_file_exists "voxtype.spec.sources exists" "$SOURCES"

# --- subpackage declarations -------------------------------------------------
grep -qE '^%package[[:space:]]+cuda\b' "$SPEC" \
  && pass "spec declares %package cuda" \
  || fail "spec declares %package cuda"
grep -qE '^%package[[:space:]]+migraphx\b' "$SPEC" \
  && pass "spec declares %package migraphx" \
  || fail "spec declares %package migraphx"

# --- carve the %files sections (base / cuda / migraphx) ----------------------
# awk splits the spec into per-section blobs keyed by the %files header.
files_section() {
  # $1 = "" for base (%files with no arg), else the subpackage name.
  awk -v want="$1" '
    /^%files([[:space:]]|$)/ {
      # capture the arg after %files (may be empty)
      arg = $2
      cur = (arg == want)
      next
    }
    /^%(package|description|changelog|prep|build|install|post|files)\b/ && !/^%files/ {
      cur = 0
    }
    cur { print }
  ' "$SPEC"
}

BASE_FILES="$(files_section "")"
CUDA_FILES="$(files_section "cuda")"
MIGRAPHX_FILES="$(files_section "migraphx")"

[[ -n $BASE_FILES ]]     || fail "could not locate the base %files section"
[[ -n $CUDA_FILES ]]     || fail "could not locate the %files cuda section"
[[ -n $MIGRAPHX_FILES ]] || fail "could not locate the %files migraphx section"

# --- base %files must NOT carry the GPU trees --------------------------------
if grep -qiE 'cuda|migraphx|rocm' <<<"$BASE_FILES"; then
  printf '%s\n' "$BASE_FILES" >&2
  fail "base %files excludes cuda-*/migraphx/rocm trees"
else
  pass "base %files excludes cuda-*/migraphx/rocm trees"
fi

# Base must still own the wrapper + the slim variant binaries.
grep -qE '%\{_bindir\}/voxtype\b' <<<"$BASE_FILES" \
  && pass "base %files owns the /usr/bin/voxtype wrapper" \
  || fail "base %files owns the /usr/bin/voxtype wrapper"
grep -qE 'voxtype-avx2\b' <<<"$BASE_FILES" \
  && pass "base %files owns the avx2 variant" \
  || fail "base %files owns the avx2 variant"
grep -qE 'voxtype-vulkan\b' <<<"$BASE_FILES" \
  && pass "base %files owns the vulkan variant" \
  || fail "base %files owns the vulkan variant"

# --- each subpackage owns its variant tree -----------------------------------
grep -qE '/lib/voxtype/cuda-12\b' <<<"$CUDA_FILES" && grep -qE '/lib/voxtype/cuda-13\b' <<<"$CUDA_FILES" \
  && pass "voxtype-cuda %files owns the cuda-12 + cuda-13 trees" \
  || fail "voxtype-cuda %files owns the cuda-12 + cuda-13 trees"
grep -qE '/lib/voxtype/migraphx\b' <<<"$MIGRAPHX_FILES" \
  && pass "voxtype-migraphx %files owns the migraphx tree" \
  || fail "voxtype-migraphx %files owns the migraphx tree"

# --- subpackage version-lock (cascade on remove) -----------------------------
# Both subpackages must Requires: voxtype = %{version}-%{release}.
for sub in cuda migraphx; do
  # Pull the lines of the %package <sub> stanza (header up to the next %... block).
  stanza="$(awk -v want="$sub" '
    $0 ~ ("^%package[[:space:]]+" want "([[:space:]]|$)") { cur=1; next }
    /^%(package|description|prep|build|install|post|files|changelog)\b/ { cur=0 }
    cur { print }
  ' "$SPEC")"
  grep -qE '^Requires:[[:space:]]+voxtype[[:space:]]*=[[:space:]]*%\{version\}-%\{release\}' <<<"$stanza" \
    && pass "voxtype-$sub Requires: voxtype = %{version}-%{release}" \
    || { printf '%s\n' "$stanza" >&2; fail "voxtype-$sub Requires: voxtype = %{version}-%{release}"; }
done

# --- base hard Requires: vulkan-loader ---------------------------------------
# Anchored at the top-level preamble (before the first %package). pkg.py installs
# with weak deps OFF, so this MUST be a Requires, not a Recommends.
PREAMBLE="$(awk '/^%package/ {exit} {print}' "$SPEC")"
grep -qE '^Requires:[[:space:]]+vulkan-loader\b' <<<"$PREAMBLE" \
  && pass "base Requires: vulkan-loader (hard dep, weak-deps-off safe)" \
  || fail "base Requires: vulkan-loader (hard dep, weak-deps-off safe)"
grep -qiE '^Recommends:[[:space:]]+vulkan-loader\b' <<<"$PREAMBLE" \
  && fail "vulkan-loader is NOT a Recommends (would be skipped with weak-deps off)" \
  || pass "vulkan-loader is NOT a Recommends"

# --- .sources pins exactly Source0's basename --------------------------------
src0="$(grep -E '^Source0:' "$SPEC" | head -1)"
[[ -n $src0 ]] || fail "spec declares Source0:"
# Macro-expand %{version} from the spec's Version: into the Source0 basename.
ver="$(grep -E '^Version:' "$SPEC" | head -1 | awk '{print $2}')"
[[ -n $ver ]] || fail "spec declares Version:"
src0_expanded="${src0//%\{version\}/$ver}"
src0_base="$(basename "$src0_expanded")"
pin_file="$(awk 'NF && $1 !~ /^#/ {print $2; exit}' "$SOURCES")"
pin_hash="$(awk 'NF && $1 !~ /^#/ {print $1; exit}' "$SOURCES")"
assert_equals ".sources pins exactly Source0's basename ($src0_base)" "$pin_file" "$src0_base"
[[ $pin_hash =~ ^[0-9a-f]{64}$ ]] \
  && pass ".sources pin is a 64-hex sha256" \
  || fail ".sources pin is a 64-hex sha256 (got: $pin_hash)"

echo "# all voxtype-spec tests passed"
