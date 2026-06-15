#!/bin/bash
#
# L1 unit test for on-demand voxtype install on Fedora.
#
# Covers bin/fedora/voxtype-install-pkg (the omedora-owned sibling) and the
# Fedora/Arch dispatch in bin/omarchy-voxtype-install + bin/omarchy-voxtype-remove.
#
#   PART 1 — voxtype-install-pkg downloads the PINNED url/version, verifies the
#            rpm sha256 and ABORTS on mismatch (no dnf install), and on a
#            matching sha runs `dnf install` of the local rpm + `omarchy-pkg-add
#            wtype`; vulkan-loader is added ONLY when omarchy-hw-vulkan succeeds.
#   PART 2 — omarchy-voxtype-install dispatches to the sibling on Fedora and
#            runs `omarchy-pkg-add wtype voxtype-bin` VERBATIM on Arch.
#   PART 3 — omarchy-voxtype-remove runs `dnf remove ... voxtype` on Fedora and
#            `omarchy-pkg-drop voxtype-bin` on Arch (Arch path unchanged).
#   PART 4 — omarchy-voxtype-config (the bar mic click): on Fedora, OFFERS THE
#            INSTALL (launches omarchy-voxtype-install) when voxtype is absent,
#            and runs `voxtype configure` once it's installed.
#
# Everything external is stubbed on PATH + via the $OMEDORA_* seams; no network,
# no real dnf, no real download.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

SCRATCH="$(mktemp -d)"
trap '[[ -n $SCRATCH && -d $SCRATCH ]] && rm -rf "$SCRATCH"' EXIT

SHIM="$SCRATCH/shim"
mkdir -p "$SHIM"
MOCK_LOG="$SCRATCH/mock.log"
export MOCK_LOG

stub() { printf '#!/bin/bash\n%s\n' "$2" >"$SHIM/$1"; chmod +x "$SHIM/$1"; }

# Real tools the script genuinely uses (mktemp, sha256sum, awk, command, rm)
# come from the host PATH, appended after the shim dir.
stub sudo                'printf "sudo %s\n" "$*" >>"$MOCK_LOG"; "$@"'
stub dnf                 'printf "dnf %s\n" "$*" >>"$MOCK_LOG"'
stub omarchy-pkg-add     'printf "omarchy-pkg-add %s\n" "$*" >>"$MOCK_LOG"'
stub omarchy-pkg-drop    'printf "omarchy-pkg-drop %s\n" "$*" >>"$MOCK_LOG"'
stub omarchy-hw-vulkan   'exit 0'   # default: GPU present (overridden per-case)

export PATH="$SHIM:$ROOT/bin:$PATH"

PKG="$ROOT/bin/fedora/voxtype-install-pkg"

# The pin lives in the script — read it so the test tracks bumps automatically.
PINNED_VER=$(sed -n 's/^VOXTYPE_VERSION="\(.*\)"/\1/p' "$PKG")
PINNED_SHA=$(sed -n 's/^VOXTYPE_RPM_SHA256="\(.*\)"/\1/p' "$PKG")
[[ -n $PINNED_VER ]] || fail "could not read VOXTYPE_VERSION from the sibling"
[[ -n $PINNED_SHA ]] || fail "could not read VOXTYPE_RPM_SHA256 from the sibling"

# A fake downloader: records the url it was asked to fetch, then copies a fixture
# file into the destination. Which fixture depends on $FIXTURE_SRC (set per-case).
make_downloader() {
  local src="$1" out="$SCRATCH/fake-download"
  cat >"$out" <<EOF
#!/bin/bash
printf 'download %s\n' "\$1" >>"$MOCK_LOG"
cp "$src" "\$2"
EOF
  chmod +x "$out"
  printf '%s' "$out"
}

# ===========================================================================
echo "# --- PART 1: voxtype-install-pkg supply-chain gate + install ---"
# ===========================================================================

# The pin IS the supply-chain gate, so the script has no sha-override seam by
# design. To exercise the MATCH path offline we generate a fixture and run a copy
# of the script whose pinned sha is swapped to that fixture's real sha (see (b)).

# --- (a) sha MISMATCH -> abort, no dnf install -------------------------------
BAD_FIX="$SCRATCH/bad.rpm"
printf 'this is not the pinned rpm' >"$BAD_FIX"
: >"$MOCK_LOG"
rc=0
( export OMARCHY_DISTRO=fedora \
         OMEDORA_DNF_CMD=dnf \
         OMEDORA_VOXTYPE_RPM_URL="https://example.invalid/$(basename "$BAD_FIX")" \
         OMEDORA_VOXTYPE_DOWNLOAD_CMD="$(make_downloader "$BAD_FIX")"
  bash "$PKG" ) >/dev/null 2>&1 || rc=$?
[[ $rc -ne 0 ]] \
  && pass "sha256 mismatch aborts with non-zero exit" \
  || fail "sha256 mismatch aborts with non-zero exit"
grep -q "^dnf install" "$MOCK_LOG" \
  && fail "no dnf install runs on sha mismatch" \
  || pass "no dnf install runs on sha mismatch"

# --- (b) sha MATCH -> dnf install + wtype + (gpu) vulkan-loader --------------
# Build a fixture and a script-copy whose pin equals the fixture's real sha, so
# the MATCH path runs fully offline. The download-url assertion still targets the
# REAL pinned version (we don't override the url here, so the default pinned URL
# is what the downloader records).
GOOD_FIX="$SCRATCH/good.rpm"
printf 'pretend-voxtype-rpm-payload' >"$GOOD_FIX"
GOOD_SHA=$(sha256sum "$GOOD_FIX" | awk '{print $1}')
PKG_MATCH="$SCRATCH/voxtype-install-pkg.match"
sed "s/^VOXTYPE_RPM_SHA256=.*/VOXTYPE_RPM_SHA256=\"$GOOD_SHA\"/" "$PKG" >"$PKG_MATCH"
chmod +x "$PKG_MATCH"

: >"$MOCK_LOG"
( export OMARCHY_DISTRO=fedora \
         OMEDORA_DNF_CMD=dnf \
         OMEDORA_VOXTYPE_DOWNLOAD_CMD="$(make_downloader "$GOOD_FIX")"
  bash "$PKG_MATCH" ) >/dev/null 2>&1

# Downloaded the PINNED url/version (default url, not overridden above).
grep -q "^download https://github.com/peteonrails/voxtype/releases/download/v${PINNED_VER}/voxtype-${PINNED_VER}-1.x86_64.rpm$" "$MOCK_LOG" \
  && pass "downloads the pinned voxtype $PINNED_VER release url" \
  || { cat "$MOCK_LOG" >&2; fail "downloads the pinned voxtype $PINNED_VER release url"; }
grep -q "^omarchy-pkg-add wtype$" "$MOCK_LOG" \
  && pass "installs wtype via omarchy-pkg-add" \
  || { cat "$MOCK_LOG" >&2; fail "installs wtype via omarchy-pkg-add"; }
grep -qE "^dnf install -y .*voxtype-${PINNED_VER}-1.x86_64.rpm$" "$MOCK_LOG" \
  && pass "dnf install -y of the local pinned rpm" \
  || { cat "$MOCK_LOG" >&2; fail "dnf install -y of the local pinned rpm"; }
grep -q "^omarchy-pkg-add vulkan-loader$" "$MOCK_LOG" \
  && pass "adds vulkan-loader when omarchy-hw-vulkan succeeds" \
  || { cat "$MOCK_LOG" >&2; fail "adds vulkan-loader when omarchy-hw-vulkan succeeds"; }

# --- (c) no GPU -> vulkan-loader NOT added -----------------------------------
stub omarchy-hw-vulkan 'exit 1'
: >"$MOCK_LOG"
( export OMARCHY_DISTRO=fedora \
         OMEDORA_DNF_CMD=dnf \
         OMEDORA_VOXTYPE_DOWNLOAD_CMD="$(make_downloader "$GOOD_FIX")"
  bash "$PKG_MATCH" ) >/dev/null 2>&1
grep -q "vulkan-loader" "$MOCK_LOG" \
  && fail "vulkan-loader NOT added when omarchy-hw-vulkan fails" \
  || pass "vulkan-loader NOT added when omarchy-hw-vulkan fails"
grep -qE "^dnf install -y .*\.rpm$" "$MOCK_LOG" \
  && pass "still installs the rpm without a GPU" \
  || fail "still installs the rpm without a GPU"
stub omarchy-hw-vulkan 'exit 0'  # restore default

# ===========================================================================
echo "# --- PART 2: omarchy-voxtype-install dispatch ---"
# ===========================================================================
# Stub the shared setup tools so the script runs past the dispatch hermetically.
stub gum                     'exit 0'   # confirm yes
stub voxtype                 'printf "voxtype %s\n" "$*" >>"$MOCK_LOG"; exit 0'
stub omarchy-hyprland-toggle 'printf "toggle %s\n" "$*" >>"$MOCK_LOG"'
stub omarchy-restart-shell   ':'
stub omarchy-notification-send ':'
# The Fedora arm execs "$(dirname)/fedora/voxtype-install-pkg" (relative), whose
# FIRST action is `omarchy-pkg-add wtype` — emitted before the sha gate. We feed
# the seams so the sibling reaches that point hermetically; the real pinned sha
# won't match the tiny fixture, so the sibling aborts AFTER the traced
# pkg-add+download, which is exactly the dispatch evidence we assert on (we don't
# need the full install to complete here — PART 1 already proved the match path).
FAKE_OMARCHY="$SCRATCH/omarchy"
mkdir -p "$FAKE_OMARCHY/default/voxtype"
printf 'cfg\n' >"$FAKE_OMARCHY/default/voxtype/config.toml"

: >"$MOCK_LOG"
( export OMARCHY_DISTRO=fedora OMARCHY_PATH="$FAKE_OMARCHY" HOME="$SCRATCH/home-fed" \
         OMEDORA_DNF_CMD=dnf \
         OMEDORA_VOXTYPE_DOWNLOAD_CMD="$(make_downloader "$GOOD_FIX")"
  mkdir -p "$HOME"
  bash "$ROOT/bin/omarchy-voxtype-install" ) >/dev/null 2>&1 || true
# The Fedora arm runs the sibling, whose first traced action is omarchy-pkg-add wtype
# (NOT the Arch "omarchy-pkg-add wtype voxtype-bin" line).
grep -q "^omarchy-pkg-add wtype$" "$MOCK_LOG" \
  && pass "Fedora install dispatches to the sibling (omarchy-pkg-add wtype)" \
  || { cat "$MOCK_LOG" >&2; fail "Fedora install dispatches to the sibling (omarchy-pkg-add wtype)"; }
grep -q "^download https://github.com/peteonrails/voxtype/releases/download/v${PINNED_VER}/" "$MOCK_LOG" \
  && pass "Fedora install reaches the sibling's pinned download" \
  || { cat "$MOCK_LOG" >&2; fail "Fedora install reaches the sibling's pinned download"; }
grep -q "^omarchy-pkg-add wtype voxtype-bin$" "$MOCK_LOG" \
  && fail "Fedora install does NOT run the Arch voxtype-bin line" \
  || pass "Fedora install does NOT run the Arch voxtype-bin line"

# --- Arch path: verbatim omarchy-pkg-add wtype voxtype-bin -------------------
: >"$MOCK_LOG"
( export OMARCHY_DISTRO=arch OMARCHY_PATH="$FAKE_OMARCHY" HOME="$SCRATCH/home-arch"
  mkdir -p "$HOME"
  bash "$ROOT/bin/omarchy-voxtype-install" ) >/dev/null 2>&1 || true
grep -q "^omarchy-pkg-add wtype voxtype-bin$" "$MOCK_LOG" \
  && pass "Arch install runs omarchy-pkg-add wtype voxtype-bin verbatim" \
  || { cat "$MOCK_LOG" >&2; fail "Arch install runs omarchy-pkg-add wtype voxtype-bin verbatim"; }
grep -q "^download " "$MOCK_LOG" \
  && fail "Arch install never downloads the rpm" \
  || pass "Arch install never downloads the rpm"

# ===========================================================================
echo "# --- PART 3: omarchy-voxtype-remove dispatch ---"
# ===========================================================================
stub voxtype 'exit 0'  # omarchy-cmd-present voxtype -> true
stub systemctl ':'

: >"$MOCK_LOG"
( export OMARCHY_DISTRO=fedora HOME="$SCRATCH/home-rm-fed" OMEDORA_DNF_CMD=dnf
  mkdir -p "$HOME"
  bash "$ROOT/bin/omarchy-voxtype-remove" ) >/dev/null 2>&1 || true
grep -q "^dnf remove -y voxtype$" "$MOCK_LOG" \
  && pass "Fedora remove runs dnf remove -y voxtype" \
  || { cat "$MOCK_LOG" >&2; fail "Fedora remove runs dnf remove -y voxtype"; }
grep -q "omarchy-pkg-drop" "$MOCK_LOG" \
  && fail "Fedora remove does NOT call omarchy-pkg-drop" \
  || pass "Fedora remove does NOT call omarchy-pkg-drop"

: >"$MOCK_LOG"
( export OMARCHY_DISTRO=arch HOME="$SCRATCH/home-rm-arch"
  mkdir -p "$HOME"
  bash "$ROOT/bin/omarchy-voxtype-remove" ) >/dev/null 2>&1 || true
grep -q "^omarchy-pkg-drop voxtype-bin$" "$MOCK_LOG" \
  && pass "Arch remove runs omarchy-pkg-drop voxtype-bin" \
  || { cat "$MOCK_LOG" >&2; fail "Arch remove runs omarchy-pkg-drop voxtype-bin"; }
grep -q "dnf remove" "$MOCK_LOG" \
  && fail "Arch remove never calls dnf" \
  || pass "Arch remove never calls dnf"

# ===========================================================================
echo "# --- PART 4: omarchy-voxtype-config mic-click dispatch ---"
# ===========================================================================
# The bar mic (shell/plugins/bar/indicators/Dictation.qml) runs
# omarchy-voxtype-config on click. On Fedora, when voxtype isn't installed yet,
# that must OFFER THE INSTALL (launch omarchy-voxtype-install in a floating
# terminal) rather than the old dead-end "no Fedora build yet" notice; once
# voxtype is installed it runs `voxtype configure` (the upstream Arch path).
stub omarchy-launch-floating-terminal-with-presentation 'printf "launch %s\n" "$*" >>"$MOCK_LOG"'
stub omarchy-restart-shell ':'

# --- (a) Fedora + voxtype MISSING -> offers the install ----------------------
rm -f "$SHIM/voxtype"   # voxtype absent from PATH
: >"$MOCK_LOG"
( export OMARCHY_DISTRO=fedora
  bash "$ROOT/bin/omarchy-voxtype-config" ) >/dev/null 2>&1 || true
grep -q "^launch omarchy-voxtype-install$" "$MOCK_LOG" \
  && pass "Fedora mic-click offers the install when voxtype is missing" \
  || { cat "$MOCK_LOG" >&2; fail "Fedora mic-click offers the install when voxtype is missing"; }
grep -q "voxtype configure" "$MOCK_LOG" \
  && fail "Fedora mic-click does NOT run 'voxtype configure' when voxtype missing" \
  || pass "Fedora mic-click does NOT run 'voxtype configure' when voxtype missing"

# --- (b) Fedora + voxtype PRESENT -> runs voxtype configure ------------------
stub voxtype 'exit 0'   # voxtype now on PATH
: >"$MOCK_LOG"
( export OMARCHY_DISTRO=fedora
  bash "$ROOT/bin/omarchy-voxtype-config" ) >/dev/null 2>&1 || true
grep -q "^launch voxtype configure$" "$MOCK_LOG" \
  && pass "Fedora mic-click runs 'voxtype configure' once voxtype is installed" \
  || { cat "$MOCK_LOG" >&2; fail "Fedora mic-click runs 'voxtype configure' once installed"; }
grep -q "omarchy-voxtype-install" "$MOCK_LOG" \
  && fail "Fedora mic-click does NOT re-offer install when voxtype present" \
  || pass "Fedora mic-click does NOT re-offer install when voxtype present"

echo "# all voxtype-install tests passed"
