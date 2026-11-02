#!/bin/bash
#
# L1 static guard for omedora/packaging/copr/hyprpad.spec (+ .sources).
#
# hyprpad drives Hyprland from a Steam Controller or gamepad without giving up
# Steam Input. omedora builds it FROM SOURCE in the COPR as a HERMETIC,
# VENDORED cargo build at a pinned upstream commit — so it compiles in COPR's
# OFFLINE mock (crates
# come from `cargo vendor` tarballs, never crates.io at %build time). The
# twist vs the other Rust specs: hyprpad is TWO standalone crates (the root
# daemon + osk/, each with its own Cargo.lock), so there are two vendor
# tarballs. This audits the spec text so a rebase / edit can't silently break
# either offline seal, drop the broker units / udev rule / sysusers group the
# host integration needs, or desync the source pin. Pure bash + grep; no build.
#
# Asserts:
#   - spec + .sources + README sibling exist
#   - Version is a snapshot (base^<date>.git<shortcommit>) of %commit
#   - Source0 is the pinned commit archive; Source1 *-vendor.tar.* (root
#     crate); Source2 *-osk-deps.tar.* (standalone osk crate); Source3 is the
#     local README.package.md sibling
#   - %cargo_prep -v vendor seals root offline, and %prep writes the osk seal
#     (osk/.cargo/config.toml -> ../osk-vendor); NO crate fetch at %build;
#     %check runs upstream's suites for both crates; both crate trees' license
#     manifests ship as %license (osk's as osk/cargo-vendor.txt, so rpm's
#     bundled(crate()) generator sees it)
#   - the helpers' DEFAULT_SRC is rewritten to /usr/share/hyprpad/shell
#   - nothing is enabled: no systemctl enable / plugin enable in scriptlets
#   - %files owns all six /usr/bin helpers, the broker socket+service, the
#     user unit, the udev rule, the sysusers conf, and the shell plugin tree
#   - scriptlets register both unit scopes; the group is rpm-native sysusers
#   - Requires libwayland-client (dlopen'ed, invisible to auto-deps);
#     ExclusiveArch x86_64; License covers the Kenney CC0 art
#   - hyprpad.spec is registered in build-repo.sh's SPECS array
#   - hyprpad.spec.sources pins the sha for exactly Source0's basename

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SPEC="$ROOT/omedora/packaging/copr/hyprpad.spec"
SOURCES="$ROOT/omedora/packaging/copr/hyprpad.spec.sources"
README="$ROOT/omedora/packaging/copr/hyprpad.README.package.md"

assert_file_exists "hyprpad.spec exists" "$SPEC"
assert_file_exists "hyprpad.spec.sources exists" "$SOURCES"
assert_file_exists "hyprpad.README.package.md exists" "$README"

# --- commit-pinned source + two vendor tarballs + local README ----------------
grep -qE '^%global[[:space:]]+commit[[:space:]]+[0-9a-f]{40}[[:space:]]*$' "$SPEC" \
  && pass "spec pins a full-length %commit sha" \
  || fail "spec pins a full-length %commit sha"
grep -qE '^Source0:.*/%\{commit\}/%\{name\}-%\{commit\}\.tar\.gz[[:space:]]*$' "$SPEC" \
  && pass "Source0 is the commit-pinned upstream archive" \
  || fail "Source0 is the commit-pinned upstream archive"
grep -qE '^Source1:.*-vendor\.tar\.' "$SPEC" \
  && pass "Source1 is the root-crate *-vendor.tar.* (cargo-vendor tarball)" \
  || fail "Source1 is the root-crate *-vendor.tar.* (cargo-vendor tarball)"
grep -qE '^Source2:.*-osk-deps\.tar\.' "$SPEC" \
  && pass "Source2 is the osk-crate *-osk-deps.tar.* (second vendor tarball)" \
  || fail "Source2 is the osk-crate *-osk-deps.tar.* (second vendor tarball)"
grep -qE '^Source3:[[:space:]]+hyprpad\.README\.package\.md[[:space:]]*$' "$SPEC" \
  && pass "Source3 is the local README.package.md sibling" \
  || fail "Source3 is the local README.package.md sibling"

# --- hermetic vendored / offline build (COPR mock has no network at %build) ---
grep -qE '^%cargo_prep[[:space:]].*-v[[:space:]]+vendor' "$SPEC" \
  && pass "%cargo_prep -v vendor writes the offline .cargo/config.toml seal" \
  || fail "%cargo_prep -v vendor writes the offline .cargo/config.toml seal"
grep -qF 'osk/.cargo/config.toml' "$SPEC" \
  && pass "%prep writes the osk crate's own offline seal" \
  || fail "%prep writes the osk crate's own offline seal"
grep -qF '../osk-vendor' "$SPEC" \
  && pass "osk seal points at the standalone ../osk-vendor dir" \
  || fail "osk seal points at the standalone ../osk-vendor dir"
# No online crate fetch may sneak into the build phase.
if grep -qE '^[[:space:]]*cargo[[:space:]]+(fetch|update|vendor)\b' "$SPEC"; then
  fail "spec must not run cargo fetch/update/vendor at %build (offline mock)"
else
  pass "no cargo fetch/update/vendor at %build (offline mock safe)"
fi

# --- snapshot version of the pinned commit ------------------------------------
grep -qE '^Version:[[:space:]]+[0-9.]+\^%\{snapshot\}\.git%\{shortcommit\}[[:space:]]*$' "$SPEC" \
  && pass "Version is a snapshot of the pinned commit" \
  || fail "Version is a snapshot of the pinned commit"

# --- upstream test suites + both license manifests -----------------------------
grep -qE '^%cargo_test\b' "$SPEC" \
  && pass "%check runs upstream's cargo test suites" \
  || fail "%check runs upstream's cargo test suites"
for lic in LICENSE.dependencies cargo-vendor.txt \
           '%{_licensedir}/%{name}/osk/LICENSE.dependencies' \
           '%{_licensedir}/%{name}/osk/cargo-vendor.txt'; do
  grep -qF "%license $lic" "$SPEC" \
    && pass "%files ships $lic" \
    || fail "%files ships $lic"
done

# --- helpers install the plugins from the packaged copy ------------------------
grep -qF 'DEFAULT_SRC="/usr/share/hyprpad/shell/$PLUGIN_ID"' "$SPEC" \
  && pass "helpers' DEFAULT_SRC is rewritten to /usr/share/hyprpad/shell" \
  || fail "helpers' DEFAULT_SRC is rewritten to /usr/share/hyprpad/shell"
for plugin in hyprpad.cheatsheet hyprpad.status; do
  grep -qF "$plugin" "$SPEC" \
    && pass "spec installs the $plugin shell plugin" \
    || fail "spec installs the $plugin shell plugin"
done

# --- the package enables nothing ------------------------------------------------
if grep -qE '^[^#]*(systemctl[[:space:]].*enable|omarchy[- ]plugin[- ]enable)' "$SPEC"; then
  fail "spec must not enable units or plugins on install"
else
  pass "spec enables no units or plugins on install"
fi

# --- %files owns the binaries -------------------------------------------------
for bin in hyprpad hyprpad-osk hyprpad-osk-build-model hyprpad-steam hyprpad-cheatsheet hyprpad-statusbar; do
  grep -qE "^%\\{_bindir\\}/$bin[[:space:]]*$" "$SPEC" \
    && pass "%files owns /usr/bin/$bin" \
    || fail "%files owns /usr/bin/$bin"
done

# --- %files owns the host-integration payload ---------------------------------
grep -qE '^%\{_unitdir\}/hyprpad-broker\.service[[:space:]]*$' "$SPEC" \
  && pass "%files owns the broker service unit" \
  || fail "%files owns the broker service unit"
grep -qE '^%\{_unitdir\}/hyprpad-broker\.socket[[:space:]]*$' "$SPEC" \
  && pass "%files owns the broker socket unit" \
  || fail "%files owns the broker socket unit"
grep -qE '^%\{_userunitdir\}/hyprpad\.service[[:space:]]*$' "$SPEC" \
  && pass "%files owns the user service unit" \
  || fail "%files owns the user service unit"
grep -qE '^%\{_udevrulesdir\}/72-hyprpad-puck\.rules[[:space:]]*$' "$SPEC" \
  && pass "%files owns the udev puck rule" \
  || fail "%files owns the udev puck rule"
grep -qE '^%\{_sysusersdir\}/hyprpad\.conf[[:space:]]*$' "$SPEC" \
  && pass "%files owns the sysusers group conf" \
  || fail "%files owns the sysusers group conf"
grep -qE '^%\{_datadir\}/hyprpad/shell[[:space:]]*$' "$SPEC" \
  && pass "%files owns the shell plugin tree" \
  || fail "%files owns the shell plugin tree"

# --- scriptlets: sysusers group + both unit scopes ----------------------------
# The group comes from rpm's native sysusers handling of the shipped
# sysusers.d file (owned above), so no compat scriptlet (an empty %pre on F44+).
if grep -qE '^%sysusers_create_compat' "$SPEC"; then
  fail "no %sysusers_create_compat (rpm creates the group natively)"
else
  pass "no %sysusers_create_compat (rpm creates the group natively)"
fi
grep -qE '^%systemd_post[[:space:]]+hyprpad-broker\.service' "$SPEC" \
  && pass "broker units registered with %systemd_post" \
  || fail "broker units registered with %systemd_post"
grep -qE '^%systemd_user_post[[:space:]]+hyprpad\.service' "$SPEC" \
  && pass "user unit registered with %systemd_user_post" \
  || fail "user unit registered with %systemd_user_post"

# --- Requires: libwayland-client is dlopen'ed, invisible to auto-deps --------
grep -qE '^Requires:[[:space:]]+libwayland-client\b' "$SPEC" \
  && pass "Requires: libwayland-client (dlopen'ed by both binaries)" \
  || fail "Requires: libwayland-client (dlopen'ed by both binaries)"

# --- License covers the bundled Kenney CC0 art --------------------------------
grep -qE '^License:.*CC0-1\.0' "$SPEC" \
  && pass "License aggregates CC0-1.0 (Kenney input-prompts art)" \
  || fail "License aggregates CC0-1.0 (Kenney input-prompts art)"

# --- ExclusiveArch x86_64 ------------------------------------------------------
grep -qE '^ExclusiveArch:[[:space:]]+x86_64\b' "$SPEC" \
  && pass "ExclusiveArch: x86_64" \
  || fail "ExclusiveArch: x86_64"

# --- registered in the COPR build order ----------------------------------------
grep -qE '^[[:space:]]*hyprpad\.spec[[:space:]]*$' "$ROOT/omedora/packaging/copr/build-repo.sh" \
  && pass "hyprpad.spec is registered in build-repo.sh SPECS" \
  || fail "hyprpad.spec is registered in build-repo.sh SPECS"

# --- .sources pins exactly Source0's basename ----------------------------------
src0="$(grep -E '^Source0:' "$SPEC" | head -1)"
[[ -n $src0 ]] || fail "spec declares Source0:"
commit="$(grep -E '^%global[[:space:]]+commit' "$SPEC" | head -1 | awk '{print $3}')"
[[ -n $commit ]] || fail "spec declares %commit:"
name="$(grep -E '^Name:' "$SPEC" | head -1 | awk '{print $2}')"
[[ -n $name ]] || fail "spec declares Name:"
src0_expanded="${src0//%\{commit\}/$commit}"
src0_expanded="${src0_expanded//%\{name\}/$name}"
src0_base="$(basename "$src0_expanded")"
pin_file="$(awk 'NF && $1 !~ /^#/ {print $2; exit}' "$SOURCES")"
pin_hash="$(awk 'NF && $1 !~ /^#/ {print $1; exit}' "$SOURCES")"
assert_equals ".sources pins exactly Source0's basename ($src0_base)" "$pin_file" "$src0_base"
[[ $pin_hash =~ ^[0-9a-f]{64}$ ]] \
  && pass ".sources pin is a 64-hex sha256" \
  || fail ".sources pin is a 64-hex sha256 (got: $pin_hash)"

echo "# all hyprpad-spec tests passed"
