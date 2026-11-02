#!/bin/bash
#
# L1 static guard for omedora/packaging/copr/basalt-xreal.spec (+ .sources).
#
# basalt-xreal is the Basalt VIT tracker monado-xreal dlopens for XREAL Air
# 6DoF. COPR's mock build is offline and commit archives carry no submodules,
# so every submodule the library build reads is its own pinned SourceN. This
# audits the spec text so an edit cannot silently move the library onto the
# linker path, unpin a submodule, or break the toml's config-path rewrite.
# Pure bash + grep; no build.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

COPR="$ROOT/omedora/packaging/copr"
SPEC="$COPR/basalt-xreal.spec"
SOURCES="$COPR/basalt-xreal.spec.sources"
PATCH="$COPR/basalt-xreal-library-build.patch"

assert_file_exists "basalt-xreal.spec exists" "$SPEC"
assert_file_exists "basalt-xreal.spec.sources exists" "$SOURCES"
assert_file_exists "basalt-xreal library-build patch exists" "$PATCH"

# --- pins ---------------------------------------------------------------------
grep -qE '^%global commit e3dec7b4477eb25629c7d3ebc509a7e6c2d15b86$' "$SPEC" \
  && pass "Basalt xreal-vit tip is pinned" || fail "Basalt xreal-vit tip is pinned"
grep -qE '^%global snapshot 20261015$' "$SPEC" \
  && pass "snapshot is the pinned commit's date" || fail "snapshot is the pinned commit's date"
grep -qE '^Version:[[:space:]]+0\^%\{snapshot\}\.git%\{shortcommit\}$' "$SPEC" \
  && pass "Version is a snapshot of the pinned commit" \
  || fail "Version is a snapshot of the pinned commit"
grep -qE '^URL:[[:space:]]+https://github\.com/AndrewGaspar/basalt$' "$SPEC" \
  && pass "URL is the user's Basalt fork" || fail "URL is the user's Basalt fork"

# Submodule gitlinks recorded in the Basalt / basalt-headers commits.
declare -A submodules=(
  [headers_commit]=e6db0fb84c69614bc4923fde6c52154c221c1768
  [sophus_commit]=d0b7315a0d90fc6143defa54596a3a95d9fa10ec
  [cli11_commit]=37bb6edc5317e99af72ef48405e65d9ca5218861
  [magic_enum_commit]=e046b69a3736d314fad813e159b1c192eaef92cd
)
for macro in "${!submodules[@]}"; do
  grep -qx "%global $macro ${submodules[$macro]}" "$SPEC" \
    && pass "$macro pins the recorded gitlink" || fail "$macro pins the recorded gitlink"
done

# Each SourceN's fetched basename is pinned, and nothing else is.
expand() {
  local value=$1 macro
  value=${value//%\{url\}/https://github.com/AndrewGaspar/basalt}
  value=${value//%\{commit\}/e3dec7b4477eb25629c7d3ebc509a7e6c2d15b86}
  for macro in "${!submodules[@]}"; do
    value=${value//%\{$macro\}/${submodules[$macro]}}
  done
  printf '%s\n' "$value"
}
want=$(grep -E '^Source[0-9]+:' "$SPEC" | sed -E 's/^[^:]+:[[:space:]]*//' \
  | while read -r src; do basename "$(expand "$src")"; done | sort)
got=$(awk 'NF && $1 !~ /^#/ {print $2}' "$SOURCES" | sort)
assert_equals ".sources pins exactly the declared sources" "$got" "$want"
(( $(grep -cE '^Source[0-9]+:' "$SPEC") == 5 )) \
  && pass "five sources: Basalt + four submodules" || fail "five sources: Basalt + four submodules"
awk 'NF && $1 !~ /^#/ { if ($1 !~ /^[0-9a-f]{64}$/ || NF != 2) exit 1 }' "$SOURCES" \
  && pass ".sources has immutable SHA-256 pins" || fail ".sources has immutable SHA-256 pins"
if grep -qiE '^Source[0-9]+:.*(pangolin|opengv|ros_comm|roscpp|fastcdr|eigen|cereal)' "$SPEC"; then
  fail "no unneeded or system-provided submodule is fetched"
else
  pass "no unneeded or system-provided submodule is fetched"
fi

# --- submodules land where Basalt's CMake looks, and the patch applies after --
for path in thirdparty/basalt-headers thirdparty/basalt-headers/thirdparty/Sophus \
  thirdparty/CLI11 thirdparty/magic_enum; do
  grep -qE "^tar -xzf %\\{SOURCE[1-4]\\} --strip-components=1 -C $path\$" "$SPEC" \
    && pass "%prep unpacks a submodule into $path" \
    || fail "%prep unpacks a submodule into $path"
done
grep -qE '^%autosetup -N ' "$SPEC" && grep -qx '%autopatch -p1' "$SPEC" \
  && pass "patches apply after the submodules are unpacked" \
  || fail "patches apply after the submodules are unpacked"
grep -qF '+++ b/thirdparty/basalt-headers/CMakeLists.txt' "$PATCH" \
  && grep -qF '+if(NOT BASALT_BUILD_SHARED_LIBRARY_ONLY)' "$PATCH" \
  && pass "patch skips opengv and accepts the system cereal" \
  || fail "patch skips opengv and accepts the system cereal"

# --- bundled vs system --------------------------------------------------------
for bundled in basalt-headers sophus cli11 magic_enum json vit; do
  grep -qE "^Provides:[[:space:]]+bundled\\($bundled\\)" "$SPEC" \
    && pass "declares bundled($bundled)" || fail "declares bundled($bundled)"
done
for flag in -DBASALT_BUILTIN_EIGEN=OFF -DBASALT_BUILTIN_CEREAL=OFF \
  -DBASALT_BUILTIN_SOPHUS=ON '-DEIGEN_ROOT=%{_includedir}/eigen3'; do
  grep -qF -- "$flag" "$SPEC" && pass "cmake $flag" || fail "cmake $flag"
done
grep -qE '^BuildRequires:[[:space:]]+eigen3-devel >= 5\.0\.1$' "$SPEC" \
  && pass "builds against Fedora's Eigen 5.0.1 (the submodule's version)" \
  || fail "builds against Fedora's Eigen 5.0.1 (the submodule's version)"
grep -qE '^BuildRequires:[[:space:]]+cereal-devel >= 1\.3\.2$' "$SPEC" \
  && pass "builds against Fedora's cereal 1.3.2 (the submodule's version)" \
  || fail "builds against Fedora's cereal 1.3.2 (the submodule's version)"

# --- library-only float build, no GUI, portable code generation ---------------
for flag in -DBASALT_BUILD_SHARED_LIBRARY_ONLY=ON -DBASALT_BUILD_VISUALIZATION=OFF \
  -DBASALT_ENABLE_ROSBAG2=OFF -DBASALT_INSTANTIATIONS_DOUBLE=OFF \
  -DBASALT_INSTANTIATIONS_FLOAT=ON -DCXX_MARCH=x86-64-v3; do
  grep -qF -- "$flag" "$SPEC" && pass "cmake $flag" || fail "cmake $flag"
done
grep -qF 'export CXXFLAGS="%{build_cxxflags} -march=x86-64-v3"' "$SPEC" \
  && pass "x86-64-v3 follows Fedora's -march in the passed flags" \
  || fail "x86-64-v3 follows Fedora's -march in the passed flags"
grep -qE '^ninja-build -C %\{__cmake_builddir\} -j"\$jobs" basalt$' "$SPEC" \
  && pass "builds only the library, with memory-capped jobs" \
  || fail "builds only the library, with memory-capped jobs"
grep -qx '%global _lto_cflags %{nil}' "$SPEC" \
  && pass "LTO is off for the template-heavy build" || fail "LTO is off for the template-heavy build"

# --- private layout -----------------------------------------------------------
for file in '%{_libdir}/basalt-xreal/libbasalt.so.%{vit_version}' \
  '%{_libdir}/basalt-xreal/libbasalt.so.%{vit_major}' \
  '%{_libdir}/basalt-xreal/libbasalt.so' '%{_datadir}/basalt-xreal/'; do
  grep -qxF "$file" "$SPEC" && pass "%files owns $file" || fail "%files owns $file"
done
if grep -qE '^%\{_libdir\}/libbasalt|^%\{_datadir\}/basalt/|^%\{_includedir\}|pkgconfig' "$SPEC"; then
  fail "nothing lands on the linker path or as a devel file"
else
  pass "nothing lands on the linker path or as a devel file"
fi
grep -qx '%global vit_major 2' "$SPEC" && grep -qx '%global vit_version 2.0.1' "$SPEC" \
  && pass "VIT 2.0.1, SONAME libbasalt.so.2" || fail "VIT 2.0.1, SONAME libbasalt.so.2"

# --- the toml's config-path points at the installed json ----------------------
grep -qF "sed 's|^config-path=.*\$|config-path=\"%{_datadir}/basalt-xreal/xreal_air_config.json\"|'" "$SPEC" \
  && pass "%install rewrites the toml's config-path to the private json" \
  || fail "%install rewrites the toml's config-path to the private json"
grep -qF "grep -qx 'config-path=\"%{_datadir}/basalt-xreal/xreal_air_config.json\"' \"\$toml\"" "$SPEC" \
  && pass "%check verifies the rewritten config-path" \
  || fail "%check verifies the rewritten config-path"
grep -qF 'data/xreal/xreal_air_config.json' "$SPEC" \
  && pass "ships the XREAL pipeline json" || fail "ships the XREAL pipeline json"
for check in vit_api_get_version basalt_vit_restartable './vit-smoke'; do
  grep -qF "$check" "$SPEC" && pass "%check covers $check" || fail "%check covers $check"
done

# --- build order --------------------------------------------------------------
order=$(sed -n '/^SPECS=(/,/^)/p' "$COPR/build-repo.sh" | sed 's/#.*//' | tr -s '[:space:]' ' ')
[[ $order == *" basalt-xreal.spec"*" monado-xreal.spec "* ]] \
  && pass "basalt-xreal builds before monado-xreal" \
  || fail "basalt-xreal builds before monado-xreal"

grep -qE '^ExclusiveArch:[[:space:]]+x86_64$' "$SPEC" \
  && pass "ExclusiveArch: x86_64" || fail "ExclusiveArch: x86_64"

echo "# all basalt-xreal-spec tests passed"
