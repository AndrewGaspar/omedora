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
grep -qE '^%global commit 9097b3c02bc996d8aa4ac348700727877ac4aa39$' "$HYPXR" \
  && pass "HypXRland current branch tip is pinned" || fail "HypXRland current branch tip is pinned"
grep -qE '^%global snapshot 20261016\.1$' "$HYPXR" \
  && pass "HypXRland uses the Oct 16 snapshot revision" \
  || fail "HypXRland uses the Oct 16 snapshot revision"
grep -qF 'fc3041fd892c8a4ec88c7fd9fd1e5394201d5a3f2076c773a4bb576745666cf0  hypxrland-9097b3c02bc996d8aa4ac348700727877ac4aa39.tar.gz' \
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

# XREAL is the session's primary hardware. Omedora installs with weak deps
# off, so the runtime and the 2D/3D helper are hard dependencies of the session
# package (#13).
SESSION="$COPR/hypxrland-omedora.spec"
for requirement in monado-xreal xreal-ctl; do
  grep -qE "^Requires:[[:space:]]+$requirement >= " "$SESSION" \
    && pass "XR session requires $requirement" || fail "XR session requires $requirement"
done
if grep -qE '^(Recommends|Suggests):' "$SESSION"; then
  fail "XR session declares no weak dependencies (Omedora installs without them)"
else
  pass "XR session declares no weak dependencies (Omedora installs without them)"
fi

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

MONADO_UNIT="$COPR/monado-xreal.service"
grep -qF -- '-DXRT_IPC_MSG_SOCK_FILENAME=monado-xreal/comp_ipc' "$COPR/monado-xreal.spec" \
  && pass "monado-xreal keeps its socket under monado-xreal/" \
  || fail "monado-xreal keeps its socket under monado-xreal/"
grep -qx 'RuntimeDirectory=monado-xreal' "$MONADO_UNIT" \
  && pass "monado-xreal unit creates the socket directory" \
  || fail "monado-xreal unit creates the socket directory"
grep -qx 'RuntimeDirectoryMode=0700' "$MONADO_UNIT" \
  && pass "monado-xreal socket directory is private to the user" \
  || fail "monado-xreal socket directory is private to the user"

# Resource control (#11). A user unit can raise its CPU weight (the user
# manager has cpu delegated) and oomd honors the preference under Fedora's
# per-user-slice defaults. IOWeight= stays out: user@.service delegates no io
# controller, so the line would be a no-op.
grep -qx 'CPUWeight=1000' "$MONADO_UNIT" \
  && pass "monado-xreal unit raises its CPU weight" \
  || fail "monado-xreal unit raises its CPU weight"
grep -qx 'ManagedOOMPreference=avoid' "$MONADO_UNIT" \
  && pass "monado-xreal unit asks systemd-oomd to avoid it" \
  || fail "monado-xreal unit asks systemd-oomd to avoid it"
if grep -qE '^IOWeight=' "$MONADO_UNIT"; then
  fail "monado-xreal unit carries no no-op IOWeight="
else
  pass "monado-xreal unit carries no no-op IOWeight="
fi
# #15: uresourced manages every unit in app.slice and resets CPUWeight= there,
# so the runtime must run elsewhere: session.slice, beside the compositor.
assert_equals "monado-xreal unit picks exactly one slice" \
  "$(grep -c '^Slice=' "$MONADO_UNIT")" "1"
grep -qx 'Slice=session.slice' "$MONADO_UNIT" \
  && pass "monado-xreal unit runs in session.slice, out of uresourced's app.slice" \
  || fail "monado-xreal unit runs in session.slice, out of uresourced's app.slice"

MONADO="$COPR/monado-xreal.spec"
grep -qx '%global commit 613d8eeb1e29be2b208a3b0eff2f5826f4bef983' "$MONADO" \
  && pass "monado-xreal pins the fork's hypxrland tip" \
  || fail "monado-xreal pins the fork's hypxrland tip"
grep -qx '%global snapshot 20261016.2' "$MONADO" \
  && pass "monado-xreal snapshot sorts above the previous Oct 16 pin" \
  || fail "monado-xreal snapshot sorts above the previous Oct 16 pin"
grep -qF '9d170f5b20fdab8c89d5a527b3155b311544cb24ce77e86b0c163099bf05476a  monado-xreal-613d8eeb1e29be2b208a3b0eff2f5826f4bef983.tar.gz' \
  "$COPR/monado-xreal.spec.sources" \
  && pass "monado-xreal archive checksum is pinned" \
  || fail "monado-xreal archive checksum is pinned"
# 6DoF works once enabled (the packaged Basalt is installed and wired in the
# unit; basalt-xreal-spec-test.sh checks those paths), but stays opt-in.
grep -qE '^Requires:[[:space:]]+basalt-xreal >= ' "$MONADO" \
  && pass "monado-xreal requires the packaged Basalt tracker" \
  || fail "monado-xreal requires the packaged Basalt tracker"
grep -q '^Environment=VIT_SYSTEM_LIBRARY_PATH=/usr/lib64/basalt-xreal/' "$MONADO_UNIT" \
  && pass "monado-xreal unit points VIT at basalt-xreal" \
  || fail "monado-xreal unit points VIT at basalt-xreal"
if grep -qE '^Environment=XREAL_AIR_(SLAM|PLANES)=' "$MONADO_UNIT"; then
  fail "monado-xreal unit leaves 6DoF and planes off"
else
  pass "monado-xreal unit leaves 6DoF and planes off"
fi
grep -qF -- '-DXRT_FEATURE_SLAM=ON' "$MONADO" \
  && grep -qF -- '-DXRT_FEATURE_OPENXR_PLANE_DETECTION=ON' "$MONADO" \
  && pass "monado-xreal builds the SLAM and plane detection paths" \
  || fail "monado-xreal builds the SLAM and plane detection paths"
grep -qF '%{buildroot}%{_libexecdir}/monado-xreal/monado-cli' "$MONADO" \
  && pass "monado-xreal installs monado-cli privately" \
  || fail "monado-xreal installs monado-cli privately"
# The service binary must never gain file capabilities (they put the Vulkan
# loader in secure-execution mode). rpm runs %check under `sh -e`, which never
# fails on a `! cmd` line, so the check has to exit by hand.
monado_check=$(sed -n '/^%check/,/^%post/p' "$MONADO")
if grep -qE '^[[:space:]]*! ' <<<"$monado_check"; then
  fail "monado-xreal %check has no bare negated commands (they never fail the build)"
else
  pass "monado-xreal %check has no bare negated commands (they never fail the build)"
fi
grep -qF 'caps=$(getcap %{buildroot}%{_libexecdir}/monado-xreal/monado-service)' <<<"$monado_check" \
  && grep -qx 'if \[\[ -n $caps \]\]; then' <<<"$monado_check" \
  && pass "monado-xreal %check fails on file capabilities" \
  || fail "monado-xreal %check fails on file capabilities"
grep -qE '^Source3:[[:space:]]+monado-xreal\.README\.package\.md$' "$MONADO" \
  && grep -qF 'Environment=XREAL_AIR_SLAM=1' "$COPR/monado-xreal.README.package.md" \
  && grep -qF 'Environment=XREAL_AIR_PLANES=1' "$COPR/monado-xreal.README.package.md" \
  && pass "monado-xreal README documents enabling 6DoF and planes" \
  || fail "monado-xreal README documents enabling 6DoF and planes"

echo "# all HypXR spec tests passed"
