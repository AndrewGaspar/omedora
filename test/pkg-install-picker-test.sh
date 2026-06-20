#!/bin/bash
#
# L1 unit tests for the Install → Package / AUR picker paths on Fedora.
#
# Covers the additive Fedora dispatch added to the free-form install helpers:
#   - bin/fedora/pkg-install builds its picker from `dnf repoquery` and installs
#     the selection via `sudo dnf install -y`.
#   - bin/omarchy-pkg-install dispatches to that sibling when OMARCHY_DISTRO=fedora,
#     and leaves the Arch (pacman) path untouched.
#   - bin/omarchy-pkg-aur-install no-ops with a notice on Fedora (no yay).
#
# Mocks dnf/fzf/sudo/gum + omarchy-sudo-keepalive/omarchy-show-done via PATH so
# no real package manager, fuzzy finder, or sudo prompt is ever touched. Runs
# from any host (Arch, Fedora, CI on Ubuntu).

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

MOCK_LOG="$TMPDIR/mock.log"
export MOCK_LOG

# Extra mocks live alongside the shared test/mocks (dnf, sudo, pacman, …). We
# add a no-op fzf (echoes a canned selection), a no-op gum, and stubs for the
# sourced/called omarchy-sudo-keepalive + omarchy-show-done helpers so the
# picker flow runs end-to-end without a TTY.
EXTRA_BIN="$TMPDIR/bin"
mkdir -p "$EXTRA_BIN"

# fzf mock: echo whatever MOCK_FZF_SELECT holds (newline-separated), ignoring
# stdin/args. Default selects two packages.
cat >"$EXTRA_BIN/fzf" <<'EOF'
#!/bin/bash
cat >/dev/null   # drain the piped candidate list
# Use ${x-default} (no colon) so an explicitly-empty MOCK_FZF_SELECT means
# "user selected nothing" (emit nothing, mimicking a cancelled picker), not
# "fall back to the default".
sel="${MOCK_FZF_SELECT-htop}"
[[ -n $sel ]] && printf '%s\n' "$sel"
exit 0
EOF
chmod +x "$EXTRA_BIN/fzf"

# gum mock: no-op (omarchy-show-done shells out to `gum spin … read`).
cat >"$EXTRA_BIN/gum" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$EXTRA_BIN/gum"

# omarchy-sudo-keepalive is `source`d by the picker; stub it to a no-op so it
# never runs `sudo -v` / spawns a background keepalive loop.
cat >"$EXTRA_BIN/omarchy-sudo-keepalive" <<'EOF'
#!/bin/bash
:
EOF
chmod +x "$EXTRA_BIN/omarchy-sudo-keepalive"

# omarchy-show-done shells out to gum; stub to a no-op for determinism.
cat >"$EXTRA_BIN/omarchy-show-done" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$EXTRA_BIN/omarchy-show-done"

# PATH: extra stubs first, then shared mocks (dnf/sudo/…), then the real bin/
# (for omarchy-distro and the helpers under test), then the host PATH.
export PATH="$EXTRA_BIN:$ROOT/test/mocks:$ROOT/bin:$PATH"

reset_log() { : >"$MOCK_LOG"; }
log_contains() { grep -qF "$1" "$MOCK_LOG"; }
log_lacks()    { ! grep -qF "$1" "$MOCK_LOG"; }

# The dnf mock emits MOCK_DNF_OUT for *every* dnf call; the picker only consumes
# stdout from the `dnf repoquery` step (the result is fed to fzf, which we
# override anyway), so a canned candidate list is harmless for the install step.
export MOCK_DNF_OUT=$'htop\njq\nripgrep'

# --- bin/fedora/pkg-install: builds picker from dnf repoquery, installs via dnf ---

reset_log
MOCK_FZF_SELECT=$'htop\njq' "$ROOT/bin/fedora/pkg-install" >/dev/null 2>&1 || true

if log_contains "dnf -q repoquery --available --qf %{name}"; then
  pass "fedora/pkg-install builds the picker from 'dnf repoquery --available'"
else
  cat "$MOCK_LOG" >&2
  fail "fedora/pkg-install → expected a 'dnf repoquery --available' call"
fi

if log_contains "sudo dnf install -y htop jq"; then
  pass "fedora/pkg-install installs the fzf selection via 'sudo dnf install -y'"
else
  cat "$MOCK_LOG" >&2
  fail "fedora/pkg-install → expected 'sudo dnf install -y htop jq'"
fi

# --- empty selection is a clean no-op (no install) ---

reset_log
MOCK_FZF_SELECT="" "$ROOT/bin/fedora/pkg-install" >/dev/null 2>&1 || true
if log_lacks "dnf install"; then
  pass "fedora/pkg-install with empty selection → no install call"
else
  cat "$MOCK_LOG" >&2
  fail "fedora/pkg-install empty selection → unexpectedly tried to install"
fi

# --- bin/omarchy-pkg-install: dispatches to the Fedora sibling on Fedora ---

reset_log
OMARCHY_DISTRO=fedora MOCK_FZF_SELECT="ripgrep" \
  "$ROOT/bin/omarchy-pkg-install" >/dev/null 2>&1 || true
if log_contains "dnf -q repoquery --available --qf %{name}" \
   && log_contains "sudo dnf install -y ripgrep"; then
  pass "omarchy-pkg-install dispatches to the dnf picker on Fedora"
else
  cat "$MOCK_LOG" >&2
  fail "omarchy-pkg-install (Fedora) → expected dnf repoquery + install"
fi
if log_lacks "pacman"; then
  pass "omarchy-pkg-install (Fedora) emits NO pacman calls"
else
  cat "$MOCK_LOG" >&2
  fail "omarchy-pkg-install (Fedora) leaked a pacman call"
fi

# --- Arch path preserved: OMARCHY_DISTRO=arch still routes to pacman ---

reset_log
OMARCHY_DISTRO=arch MOCK_FZF_SELECT="cowsay" \
  "$ROOT/bin/omarchy-pkg-install" >/dev/null 2>&1 || true
if log_contains "pacman -Slq"; then
  pass "omarchy-pkg-install (Arch) routes to pacman (Arch path preserved)"
else
  cat "$MOCK_LOG" >&2
  fail "omarchy-pkg-install (Arch) → expected a pacman call"
fi
if log_lacks "dnf"; then
  pass "omarchy-pkg-install (Arch) emits NO dnf calls (dual-distro contract)"
else
  cat "$MOCK_LOG" >&2
  fail "omarchy-pkg-install (Arch) leaked a dnf call"
fi

# --- bin/omarchy-pkg-aur-install: no-ops with a notice on Fedora ---

reset_log
set +e
aur_out=$(OMARCHY_DISTRO=fedora "$ROOT/bin/omarchy-pkg-aur-install" 2>&1)
aur_code=$?
set -e
assert_equals "omarchy-pkg-aur-install (Fedora) → non-zero exit (no-op)" "$aur_code" "1"
assert_output_contains "omarchy-pkg-aur-install (Fedora) → prints a notice" \
  "$aur_out" "Install → Package"
if log_lacks "yay"; then
  pass "omarchy-pkg-aur-install (Fedora) runs NO yay"
else
  cat "$MOCK_LOG" >&2
  fail "omarchy-pkg-aur-install (Fedora) leaked a yay call"
fi
