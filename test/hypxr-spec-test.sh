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
grep -qE '^%global commit 7ac272db9ac77dee5c1ddab0d78ecb9885b7b204$' "$HYPXR" \
  && pass "HypXRland current branch tip is pinned" || fail "HypXRland current branch tip is pinned"
grep -qE '^%global snapshot 20261111\.1$' "$HYPXR" \
  && pass "HypXRland uses the Nov 11 snapshot revision" \
  || fail "HypXRland uses the Nov 11 snapshot revision"
grep -qF '6f55c050fb6116d1cea62538968d249d9d55379dddca3ef8ad570db25caa02f3  hypxrland-7ac272db9ac77dee5c1ddab0d78ecb9885b7b204.tar.gz' \
  "$COPR/hypxrland.spec.sources" \
  && pass "HypXRland current archive checksum is pinned" \
  || fail "HypXRland current archive checksum is pinned"
grep -qE '^%global base_version 0\.56\.2$' "$HYPXR" \
  && pass "HypXRland declares the 0.56.2 base" || fail "HypXRland declares the 0.56.2 base"
grep -qE '^Release:[[:space:]]+1%\{\?dist\}$' "$HYPXR" \
  && pass "HypXRland snapshot is release 1" \
  || fail "HypXRland snapshot is release 1"
grep -qF "grep -qx 'HYPXR_PLUGIN_DIR:STRING=%{_prefix}/lib/hypxrland/plugins'" "$HYPXR" \
  && grep -qF -- '-DHYPXR_PLUGIN_DIR=%{_prefix}/lib/hypxrland/plugins' "$HYPXR" \
  && pass "HypXRland redirects stock plugin paths to /usr/lib/hypxrland/plugins" \
  || fail "HypXRland redirects stock plugin paths to /usr/lib/hypxrland/plugins"
sed -n '/^%package[[:space:]]*devel$/,/^%description/p' "$HYPXR" | grep -qE '^Requires:[[:space:]]+pkgconfig\(openxr\)$' \
  && pass "hypxrland-devel requires the OpenXR headers" \
  || fail "hypxrland-devel requires the OpenXR headers"
grep -qE '^%package[[:space:]]+devel$' "$HYPXR" && grep -qE '^%files devel$' "$HYPXR" \
  && pass "HypXRland ships a devel subpackage" || fail "HypXRland ships a devel subpackage"
grep -qF "sed -E 's|^prefix=.*$|prefix=%{_prefix}/lib/hypxrland/include|'" "$HYPXR" \
  && pass "hypxrland-devel's pkg-config file points at its private headers" \
  || fail "hypxrland-devel's pkg-config file points at its private headers"
if grep -qE '^%\{_includedir\}|%\{_datadir\}/pkgconfig' "$HYPXR"; then
  fail "hypxrland-devel stays clear of hyprland-devel's paths"
else
  pass "hypxrland-devel stays clear of hyprland-devel's paths"
fi
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
[[ $order == *"hyprland.spec"*"omarchy-hyprland-titlebars.spec"*"hypxrhud.spec hypxrcompose.spec"*"hypxrvoice.spec"*"wivrn-hypxr.spec"*"hypxrland.spec hypxrland-stack.spec"*"omarchy-hyprland-titlebars-hypxr.spec hyprshare.spec"*"hypxrland-omedora.spec"* ]] \
  && pass "canonical build order contains the complete XR wave" \
  || fail "canonical build order contains the complete XR wave"

# Plugins load only into the exact compositor build they were compiled against,
# so each pins the exact version-release of the -devel it builds with.
hypxr_evr="$(sed -nE 's/^%global base_version (.*)$/\1/p' "$HYPXR")^$(sed -nE 's/^%global snapshot (.*)$/\1/p' "$HYPXR").git$(sed -nE 's/^%global commit (.{9}).*$/\1/p' "$HYPXR")-$(sed -nE 's/^Release:[[:space:]]+([0-9]+)%\{\?dist\}$/\1/p' "$HYPXR")%{?dist}"
hypxr_lua=$(sed -nE 's/^%global lua_version (.*)$/\1/p' "$HYPXR")
for plugin in omarchy-hyprland-titlebars-hypxr hyprshare; do
  spec="$COPR/$plugin.spec"
  assert_file_exists "$plugin spec exists" "$spec"
  grep -qxF "%global hypxrland_evr $hypxr_evr" "$spec" \
    && pass "$plugin pins the current hypxrland build" || fail "$plugin pins the current hypxrland build ($hypxr_evr)"
  grep -qE '^BuildRequires:[[:space:]]+hypxrland-devel = %\{hypxrland_evr\}$' "$spec" \
    && pass "$plugin builds against hypxrland-devel" || fail "$plugin builds against hypxrland-devel"
  grep -qE '^Requires:[[:space:]]+hypxrland%\{\?_isa\} = %\{hypxrland_evr\}$' "$spec" \
    && pass "$plugin requires the exact hypxrland build" || fail "$plugin requires the exact hypxrland build"
  grep -qxF "%global lua_version $hypxr_lua" "$spec" \
    && pass "$plugin uses HypXRland's bundled Lua headers" || fail "$plugin uses HypXRland's bundled Lua headers"
  grep -qF '%{_prefix}/lib/hypxrland/plugins/' "$spec" \
    && pass "$plugin installs under the HypXRland plugin directory" || fail "$plugin installs under the HypXRland plugin directory"
done
grep -qE '^Requires:[[:space:]]+omarchy-hyprland-titlebars-hypxr$' "$COPR/hypxrland-omedora.spec" \
  && pass "the XR session package pulls in the XR titlebars" || fail "the XR session package pulls in the XR titlebars"
grep -qE '^Requires:[[:space:]]+omarchy-hyprland-titlebars$' "$COPR/omarchy-hyprland-titlebars-hypxr.spec" \
  && pass "XR titlebars keep the stock file Omarchy checks for" || fail "XR titlebars keep the stock file Omarchy checks for"
grep -qF 'nm -D --defined-only %{_libexecdir}/hypxrland/Hyprland' "$COPR/hyprshare.spec" \
  && pass "hyprshare checks its Lua symbols against the compositor" || fail "hyprshare checks its Lua symbols against the compositor"

TITLEBARS="$COPR/omarchy-hyprland-titlebars.spec"
stock_evr="$(sed -nE 's/^Version:[[:space:]]+([0-9.]+)$/\1/p' "$COPR/hyprland.spec" | head -n1)-$(sed -nE 's/^Release:[[:space:]]+([0-9]+)%\{\?dist\}$/\1/p' "$COPR/hyprland.spec" | head -n1)%{?dist}"
grep -qxF "%global hyprland_evr $stock_evr" "$TITLEBARS" \
  && pass "stock titlebars pin the current hyprland build" || fail "stock titlebars pin the current hyprland build ($stock_evr)"
grep -qE '^BuildRequires:[[:space:]]+hyprland-devel = %\{hyprland_evr\}$' "$TITLEBARS" \
  && grep -qE '^Requires:[[:space:]]+hyprland-no-session%\{\?_isa\} = %\{hyprland_evr\}$' "$TITLEBARS" \
  && pass "stock titlebars require the exact hyprland build" || fail "stock titlebars require the exact hyprland build"
grep -qxF "%global lua_version $(sed -nE 's/^%global lua_version (.*)$/\1/p' "$COPR/hyprland.spec")" "$TITLEBARS" \
  && pass "stock titlebars use Hyprland's bundled Lua headers" || fail "stock titlebars use Hyprland's bundled Lua headers"
grep -qF '%{_prefix}/lib/%{name}/titlebars.so' "$TITLEBARS" \
  && pass "stock titlebars install where workspace-modes.lua loads them" || fail "stock titlebars install where workspace-modes.lua loads them"

XDPH="$COPR/xdg-desktop-portal-hyprland.spec"
grep -qxF '%global commit 540fb9237d29c4c2aee5b0b42688ef31e097d2ce' "$XDPH" \
  && pass "portal builds the share-switch commit" || fail "portal builds the share-switch commit"
grep -qxF '6a68f9c6f89270504df4f31a2a41996c46fb2a618023e6e0428e75ed7df188fb  xdg-desktop-portal-hyprland-540fb9237d29c4c2aee5b0b42688ef31e097d2ce.tar.gz' "$XDPH.sources" \
  && pass "portal archive checksum is pinned" || fail "portal archive checksum is pinned"
grep -qxF 'Epoch:          1' "$XDPH" \
  && pass "portal keeps Epoch 1" || fail "portal keeps Epoch 1"

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
grep -qx '%global commit 76c63baca9771d77c3455c3eff81a3cd3fd20402' "$MONADO" \
  && pass "monado-xreal pins the fork's hypxrland tip" \
  || fail "monado-xreal pins the fork's hypxrland tip"
grep -qx '%global snapshot 20261102.1' "$MONADO" \
  && pass "monado-xreal uses the Nov 2 snapshot" \
  || fail "monado-xreal uses the Nov 2 snapshot"
grep -qF '6c4cfa27ab0b3dfe9edeeee2a927661bf29de6341ca3314e51c042813f0d1f69  monado-xreal-76c63baca9771d77c3455c3eff81a3cd3fd20402.tar.gz' \
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
# Real-time render thread (#11, AndrewGaspar/monado#1): rtkit through sd-bus,
# no socket activation, and still no file capabilities.
grep -qF -- '-DXRT_HAVE_SYSTEMD=ON' "$MONADO" \
  && grep -qF -- '-DXRT_FEATURE_SERVICE_SYSTEMD=OFF' "$MONADO" \
  && grep -qE '^BuildRequires:[[:space:]]+pkgconfig\(libsystemd\)$' "$MONADO" \
  && pass "monado-xreal builds rtkit support without socket activation" \
  || fail "monado-xreal builds rtkit support without socket activation"
grep -qE '^Requires:[[:space:]]+rtkit$' "$MONADO" \
  && pass "monado-xreal requires rtkit (weak deps are off)" \
  || fail "monado-xreal requires rtkit (weak deps are off)"
grep -qx 'Environment=XRT_COMPOSITOR_THREAD_REALTIME=true' "$MONADO_UNIT" \
  && pass "monado-xreal unit turns on the real-time render thread" \
  || fail "monado-xreal unit turns on the real-time render thread"
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
