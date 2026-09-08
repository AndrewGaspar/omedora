#!/bin/bash

# L1 static contract for the complete Quattro HypXR package wave.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

COPR="$ROOT/omedora/packaging/copr"
HYPXR="$COPR/hypxrland.spec"
STACK="$COPR/hypxrland-stack.spec"
WIVRN="$COPR/wivrn-hypxr.spec"
VOICE="$COPR/hypxrvoice.spec"

for file in \
  hyprland.spec hypxrland.spec hypxrland-legacy-config.spec \
  hypxrpaper.spec hypxrva.spec hypxrhud.spec hypxrcompose.spec \
  hypxrvoice-model-base-en.spec hypxrvoice.spec wivrn-hypxr.spec \
  monado-xreal.spec hypxrland-stack.spec hypxrland-omedora.spec; do
  assert_file_exists "$file exists" "$COPR/$file"
done

grep -qE '^Version:[[:space:]]+0\.56\.2$' "$COPR/hyprland.spec" \
  && pass "stable Hyprland is 0.56.2" || fail "stable Hyprland is 0.56.2"
grep -qE '^%global commit 67200a838356a206c4819595a2f733299ab4da63$' "$HYPXR" \
  && pass "HypXRland current branch tip is pinned" || fail "HypXRland current branch tip is pinned"
grep -qE '^%global snapshot 20260821\.2$' "$HYPXR" \
  && pass "HypXRland uses the second Aug 21 candidate revision" \
  || fail "HypXRland uses the second Aug 21 candidate revision"
grep -qF 'e93c5f7eb7b363d9744641e9368de7025700a9e1c5683392e79af7fc03c68954  hypxrland-67200a838356a206c4819595a2f733299ab4da63.tar.gz' \
  "$COPR/hypxrland.spec.sources" \
  && pass "HypXRland current archive checksum is pinned" \
  || fail "HypXRland current archive checksum is pinned"
grep -qE '^%global base_version 0\.56\.2$' "$HYPXR" \
  && pass "HypXRland declares the 0.56.2 base" || fail "HypXRland declares the 0.56.2 base"
grep -qE '^Release:[[:space:]]+1%\{\?dist\}$' "$HYPXR" \
  && pass "HypXRland refreshed snapshot starts at release 1" \
  || fail "HypXRland refreshed snapshot starts at release 1"
grep -qF '%{__cmake_builddir}/hyprctl/hyprctl' "$HYPXR" \
  && pass "HypXRland installs private hyprctl" || fail "HypXRland installs private hyprctl"
grep -qF 'export PATH="/usr/libexec/hypxrland:$PATH"' "$COPR/hypxrland-session" \
  && pass "XR session injects private hyprctl PATH" || fail "XR session injects private hyprctl PATH"
grep -qF 'hypr/hyprland-xr.lua' "$COPR/hypxrland-session" \
  && pass "XR session loads the Lua entry point" || fail "XR session loads the Lua entry point"
grep -qF 'Exec=/usr/bin/omarchy-xr-session' "$COPR/omedora-xr.desktop" \
  && pass "XR greeter entry seeds config through the wrapper" || fail "XR greeter entry seeds config through the wrapper"
for seeded in omarchy-setup-hypxrland omarchy-xr-session hyprland-xr.lua; do
  [[ -f "$COPR/$seeded" ]] \
    && pass "XR seeder ships $seeded" || fail "XR seeder ships $seeded"
done
grep -qF 'Source3:        hyprland-xr.lua' "$COPR/hypxrland-omedora.spec" \
  && pass "XR session package carries the Lua template" || fail "XR session package carries the Lua template"
grep -qE '^Requires:[[:space:]]+hypxrland-legacy-config >= ' "$HYPXR" \
  && pass "HypXRland versions the classic config bridge" || fail "HypXRland versions the classic config bridge"

for requirement in hypxrland hypxrcompose hypxrhud hypxrpaper hypxrva \
  hypxrvoice hypxrvoice-model-base-en wivrn-hypxr; do
  grep -qE "^Requires:[[:space:]]+$requirement >= " "$STACK" \
    && pass "stack versions $requirement" || fail "stack versions $requirement"
done

grep -qE '^Requires:[[:space:]]+/usr/bin/ffmpeg$' "$COPR/hypxrcompose.spec" \
  && pass "compose uses ffmpeg capability" || fail "compose uses ffmpeg capability"
grep -qE '^Requires:[[:space:]]+/usr/bin/ffprobe$' "$COPR/hypxrcompose.spec" \
  && pass "compose uses ffprobe capability" || fail "compose uses ffprobe capability"
grep -qF 'Patch0:         hypxrcompose-fedora-codec.patch' "$COPR/hypxrcompose.spec" \
  && grep -qF 'videoCodec  = "libsvtav1"' "$COPR/hypxrcompose-fedora-codec.patch" \
  && grep -qF '"-svtav1-params", "lossless=1", "-g", "1"' "$COPR/hypxrcompose-fedora-codec.patch" \
  && grep -qF 'EXPECT_EQ(matroskaTag(SBS_MKV), "left_right")' "$COPR/hypxrcompose-fedora-codec.patch" \
  && pass "compose uses Fedora-available SVT-AV1 default" \
  || fail "compose uses Fedora-available SVT-AV1 default"
grep -qE '^Requires:[[:space:]]+/usr/bin/ffmpeg$' "$WIVRN" \
  && pass "WiVRn uses ffmpeg capability" || fail "WiVRn uses ffmpeg capability"
! grep -qE '^Requires:[[:space:]]+ffmpeg(-free)?([[:space:]]|$)' \
  "$COPR/hypxrcompose.spec" "$WIVRN" \
  && pass "runtime avoids ffmpeg package identities" || fail "runtime avoids ffmpeg package identities"

grep -q 'foreach(target transfer-pacer fov-watch take-bundle)' "$WIVRN" \
  && pass "WiVRn enables assertions per test target" || fail "WiVRn enables assertions per test target"
! grep -q 'add_compile_options(-UNDEBUG)' "$WIVRN" \
  && pass "WiVRn production server keeps Release assertions disabled" \
  || fail "WiVRn production server keeps Release assertions disabled"
grep -q 'test "$test_count" -eq 7' "$WIVRN" \
  && pass "WiVRn asserts all seven host tests ran" || fail "WiVRn asserts all seven host tests ran"

grep -q "section == \"asr\"" "$VOICE" && grep -q "section == \"intent\"" "$VOICE" \
  && pass "voice validates ASR and intent sections" || fail "voice validates ASR and intent sections"
grep -q 'intent = (\$0 ~ /\^model = ""/)' "$VOICE" \
  && pass "voice keeps optional intent model empty" || fail "voice keeps optional intent model empty"

MODEL="$COPR/hypxrvoice-model-base-en.spec"
grep -qF 'resolve/5359861c739e955e79d9a303bcbc70fb988958b1/ggml-base.en.bin' "$MODEL" \
  && pass "voice model source uses an immutable Hugging Face revision" \
  || fail "voice model source uses an immutable Hugging Face revision"
grep -qF 'a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002  ggml-base.en.bin' \
  "$COPR/hypxrvoice-model-base-en.spec.sources" \
  && pass "voice model source retains its verified LFS checksum" \
  || fail "voice model source retains its verified LFS checksum"

order=$(sed -n '/^SPECS=(/,/^)/p' "$COPR/build-repo.sh" | sed 's/#.*//' | tr '\n' ' ')
[[ $order == *"hyprland.spec"*"hypxrhud.spec hypxrcompose.spec"*"hypxrvoice.spec"*"wivrn-hypxr.spec"*"hypxrland.spec hypxrland-stack.spec hypxrland-omedora.spec"* ]] \
  && pass "canonical build order contains the complete XR wave" \
  || fail "canonical build order contains the complete XR wave"

if grep -RE 'Requires:.*(omedora-3|hyprland-omedora)' \
  "$COPR"/{hypxrland,hypxrland-stack,hypxrland-omedora,hypxrcompose,hypxrhud,hypxrvoice,wivrn-hypxr}.spec; then
  fail "Quattro XR specs contain no Omedora 3 package dependencies"
else
  pass "Quattro XR specs contain no Omedora 3 package dependencies"
fi

for manifest in "$COPR"/{hyprland,hypxrland,hypxrpaper,hypxrva,hypxrhud,hypxrcompose,hypxrvoice,hypxrvoice-model-base-en,wivrn-hypxr,monado-xreal}.spec.sources; do
  awk 'NF && $1 !~ /^#/ { if ($1 !~ /^[0-9a-f]{64}$/ || NF != 2) exit 1 }' "$manifest" \
    && pass "$(basename "$manifest") has immutable SHA-256 pins" \
    || fail "$(basename "$manifest") has immutable SHA-256 pins"
done

echo "# all HypXR spec tests passed"
