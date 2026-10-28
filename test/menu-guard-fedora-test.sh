#!/bin/bash
#
# L1 test: the menu's package guards answer through the Fedora package map.
#
# The menu evaluates every `when:` / `disabled:` in one bash batch built by
# shell/plugins/menu/MenuModel.js guardScript(). Upstream shadows
# omarchy-pkg-present / -missing there with a set read from pacman, which on
# Fedora is empty: every Remove row gated on a package hid itself and no
# Install row ever read as installed. The carried Fedora branch rebuilds the
# set from `bin/fedora/pkg.py installed`, so the guards agree with the real
# helpers.
#
# The batch runs as the menu runs it, from this checkout's bin/, with stub
# rpm/flatpak (test/mocks) that report packages installed, and a pacman that
# records any call and knows nothing, so an answer that came from pacman would
# hide the rows asserted to show.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

# node builds the batch from MenuModel.js, as the menu does. It is not an
# Omarchy base package, so an installed system (the L3 smoke reruns this suite
# there) may lack it: skip there, but never in CI, where it is preinstalled.
if ! command -v node >/dev/null; then
  [[ -z ${CI:-} ]] || fail "node is required to build the menu guard batch"
  echo "ok - # SKIP node is not installed; the menu guard batch needs it"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

STUBS="$TMP/stubs"
mkdir -p "$STUBS"
cp "$ROOT/test/mocks/rpm" "$ROOT/test/mocks/flatpak" "$STUBS/"
cat >"$STUBS/pacman" <<'STUB'
#!/bin/bash
echo "pacman $*" >>"$PACMAN_LOG"
case "$1" in
-Qq) [[ -z ${PACMAN_INSTALLED:-} ]] || printf '%s\n' $PACMAN_INSTALLED ;;
-Qi) ;;
*) exit 1 ;;
esac
STUB
cat >"$STUBS/pacman-conf" <<'STUB'
#!/bin/bash
exit 1
STUB
chmod +x "$STUBS"/*

export MOCK_LOG="$TMP/mock.log"
export PACMAN_LOG="$TMP/pacman.log"
export OMEDORA_FEDORA_VERSION=44
export OMARCHY_FEDORA_MAP="$ROOT/install/packages/fedora.toml"
# No stored snapshot: the batch builds its set fresh every run.
export XDG_RUNTIME_DIR=""

# The guard batch for the named rows of the shipped menu.
guard_script() {
  ROWS="$*" node -e '
    const fs = require("fs")
    const path = require("path")
    const root = process.env.ROOT
    const menu = require(path.join(root, "shell/plugins/menu/MenuModel.js"))
    const items = menu.parseMenuJsonc(fs.readFileSync(path.join(root, "default/omarchy/omarchy-menu.jsonc"), "utf8"))
    const wanted = process.env.ROWS.split(" ")
    const picked = {}
    for (const id of wanted) {
      const item = items.find(entry => entry.id === id)
      if (!item) { console.error(`no menu row ${id}`); process.exit(1) }
      picked[id] = item
    }
    process.stdout.write(menu.guardScript(picked))
  '
}
export ROOT

# Runs a batch under the given distro and prints its sorted answers.
run_batch() {
  local distro="$1" script="$2"
  : >"$MOCK_LOG"
  : >"$PACMAN_LOG"
  OMARCHY_DISTRO="$distro" PATH="$STUBS:$ROOT/bin:$PATH" bash -c "$script" | sort
}

ROWS=(remove.dictation remove.dictation.voxtype remove.dictation.superwhisper install.ai.openclaw remove.ai.openclaw install.ai.grok-bot remove.ai.grok-bot install.service.slack)
script=$(guard_script "${ROWS[@]}")

# --- Fedora: every RPM and Flatpak reports installed ------------------------

answers=$(MOCK_RPM_INSTALLED="*" MOCK_FLATPAK_INSTALLED="com.slack.Slack" run_batch fedora "$script")

assert_output_contains "Fedora: Remove > Dictation shows with voxtype installed" "$answers" "remove.dictation:w:1"
assert_output_contains "Fedora: Remove > Dictation > Voxtype shows (voxtype-bin → voxtype RPM)" "$answers" "remove.dictation.voxtype:w:1"
assert_output_contains "Fedora: Install > AI > OpenClaw is disabled once the openclaw RPM is installed" "$answers" "install.ai.openclaw:d:1"
assert_output_contains "Fedora: Remove > AI > OpenClaw shows once the openclaw RPM is installed" "$answers" "remove.ai.openclaw:w:1"
assert_output_contains "Fedora: a Flathub-mapped app reads as installed (slack-desktop → com.slack.Slack)" "$answers" "install.service.slack:d:1"

# A skip-mapped package has nothing installed on Fedora, so its Remove row must
# not show even when every RPM query answers yes.
assert_output_contains "Fedora: skip-mapped superwhisper-bin never shows Remove > Dictation > Superwhisper" "$answers" "remove.dictation.superwhisper:w:0"
assert_output_contains "Fedora: skip-mapped grok-bot never shows Remove > AI > Grok Bot" "$answers" "remove.ai.grok-bot:w:0"
assert_output_contains "Fedora: skip-mapped grok-bot never reads as installed" "$answers" "install.ai.grok-bot:d:0"

grep -q '^rpm -q --qf' "$MOCK_LOG" || fail "Fedora: the guard batch asks rpm once, batched"
(( $(grep -c '^rpm ' "$MOCK_LOG") == 1 )) || { cat "$MOCK_LOG" >&2; fail "Fedora: the guard batch makes exactly one rpm query"; }
pass "Fedora: one batched rpm query answers every package guard"
(( $(grep -c '^flatpak list' "$MOCK_LOG") == 1 )) || { cat "$MOCK_LOG" >&2; fail "Fedora: the guard batch lists Flatpaks once"; }
pass "Fedora: one flatpak listing answers every Flathub-mapped guard"

# --- Fedora: nothing installed ----------------------------------------------

answers=$(MOCK_RPM_INSTALLED="" MOCK_FLATPAK_INSTALLED="" run_batch fedora "$script")
assert_output_contains "Fedora: Remove > Dictation > Voxtype hides without voxtype" "$answers" "remove.dictation.voxtype:w:0"
assert_output_contains "Fedora: Install > AI > OpenClaw stays enabled without openclaw" "$answers" "install.ai.openclaw:d:0"

# --- Fedora: the shadows agree with the real helpers ------------------------
# A name no guard spelled out (built at run time) goes to the real helper.

dynamic=$(ROWS=x node -e '
  const path = require("path")
  const menu = require(path.join(process.env.ROOT, "shell/plugins/menu/MenuModel.js"))
  process.stdout.write(menu.guardScript({
    dyn: { id: "dyn", when: "p=voxtype-bin; omarchy-pkg-present $p" },
    lit: { id: "lit", when: "omarchy-pkg-present openclaw" },
    miss: { id: "miss", when: "omarchy-pkg-missing openclaw superwhisper-bin" }
  }))
')
answers=$(MOCK_RPM_INSTALLED="voxtype openclaw" run_batch fedora "$dynamic")
assert_equals "Fedora: literal, run-time and missing guards agree with the real helpers" \
  "$(tr '\n' ' ' <<<"$answers")" "dyn:w:1 lit:w:1 miss:w:1 "

# --- Arch: the upstream pacman snapshot, unchanged --------------------------

answers=$(PACMAN_INSTALLED="voxtype-bin openclaw" MOCK_RPM_INSTALLED="*" run_batch arch "$script")
assert_output_contains "Arch: Remove > Dictation > Voxtype shows from pacman" "$answers" "remove.dictation.voxtype:w:1"
assert_output_contains "Arch: Install > AI > OpenClaw is disabled from pacman" "$answers" "install.ai.openclaw:d:1"
assert_output_contains "Arch: superwhisper-bin absent from pacman hides its Remove row" "$answers" "remove.dictation.superwhisper:w:0"
grep -q '^pacman -Qq' "$PACMAN_LOG" || fail "Arch: the guard batch reads pacman"
pass "Arch: the guard batch reads its package set from pacman"
[[ ! -s $MOCK_LOG ]] || { cat "$MOCK_LOG" >&2; fail "Arch: the guard batch never asks rpm or flatpak"; }
pass "Arch: the guard batch never asks rpm or flatpak"

# --- the Fedora branch is one guarded block --------------------------------

arch_script=$(guard_script remove.dictation.voxtype)
grep -q 'pacman -Qq' <<<"$arch_script" || fail "the batch still carries upstream's pacman snapshot"
pass "the batch still carries upstream's pacman snapshot"
(( $(grep -c 'fedora/pkg.py" installed' <<<"$arch_script") == 1 )) || fail "the batch asks pkg.py once"
pass "the batch asks pkg.py once, inside the Fedora branch"
