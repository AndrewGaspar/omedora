#!/bin/bash
#
# L1: upstream migrations that assume Arch are gated so they can't wedge the
# Fedora migration pipeline.
#
# WHY THIS MATTERS. bin/omarchy-migrate runs each migrations/*.sh under
# `bash -euo pipefail` and only writes the migration's completion marker AFTER
# it exits 0. A migration that fails on Fedora (pacman/snapper/limine/an
# unpackaged path) therefore aborts, never marks itself done, and re-fails on
# every login/update — bricking the pipeline for every later migration too.
#
# Upstream keeps adding migrations, so this is a RECURRING rebase hazard. This
# test is the safety net: any migration that contains a hard Arch token
# (pacman, snapper, limine, mkinitcpio, omarchy-nvim) MUST carry a Fedora gate
# that exits before the Arch work. When the pin rotates and a new Arch migration
# lands ungated, CI fails here instead of the user's login wedging.
#
# SCOPE. This catches the hard-token class statically. It cannot catch the
# "omarchy-pkg-add <name> where <name> is unmapped and absent from Fedora repos"
# class (that needs dnf) — the L3 container gate (running omarchy-migrate on a
# real Fedora install) is the catch-all for that. Keep both.

set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/helpers.sh"
cd "$ROOT"

MIGRATIONS_DIR="$ROOT/migrations"
[[ -d $MIGRATIONS_DIR ]] || { pass "# SKIP no migrations/ directory"; exit 0; }

# Hard Arch tokens that break on Fedora when executed (matched on non-comment
# lines only, so a token in a comment doesn't trip the lint).
ARCH_TOKEN_RE='(^|[^[:alnum:]_])(pacman|snapper|mkinitcpio)([^[:alnum:]_]|$)|limine|omarchy-nvim'

# Reviewed-safe exceptions: migrations that MENTION an Arch token but execute no
# Arch binary and no failing command on Fedora (the token is only in a HOME-local
# filename, a `|| true`-guarded call, etc.). Keyed by basename → one-line reason.
# Add here only after confirming the migration truly cannot wedge on Fedora.
declare -A REVIEWED_SAFE
REVIEWED_SAFE["1782049344.sh"]='limine appears only in a $HOME/.config/autostart filename and a `|| true`-guarded systemctl --user unit name; writes a Hidden autostart, executes no limine binary.'

# A migration is "gated" if it short-circuits on Fedora before the Arch work.
is_gated() { grep -Eq 'fedora.*exit 0|== "fedora" \]\] && exit 0|fedora\)' "$1"; }

# Strip comment lines and blank lines, then test for a hard Arch token.
has_uncommented_arch_token() {
  grep -vE '^[[:space:]]*#' "$1" | grep -Eq "$ARCH_TOKEN_RE"
}

# --- static lint: every Arch-touching migration is gated --------------------
checked=0
for f in "$MIGRATIONS_DIR"/*.sh; do
  [[ -e $f ]] || continue
  checked=$((checked + 1))
  base=$(basename "$f")
  if has_uncommented_arch_token "$f"; then
    if is_gated "$f"; then
      pass "$base: touches Arch (pacman/snapper/limine/…) and is Fedora-gated"
    elif [[ -n ${REVIEWED_SAFE[$base]:-} ]]; then
      pass "$base: Arch token reviewed-safe (${REVIEWED_SAFE[$base]})"
    else
      grep -vE '^[[:space:]]*#' "$f" | grep -En "$ARCH_TOKEN_RE" >&2 || true
      fail "$base: contains a hard Arch token but has NO Fedora gate — it will wedge the Fedora migration pipeline. Add an early '[[ \"\$(omarchy-distro)\" == fedora ]] && exit 0' (or a body guard), or add it to REVIEWED_SAFE with a reason if it truly cannot wedge."
    fi
  else
    pass "$base: no hard Arch token (Fedora-safe as-is)"
  fi
done
(( checked > 0 )) || fail "no migrations scanned (glob failed?)"

# --- runtime: the known Arch-only migrations no-op cleanly on Fedora ---------
# Stub the Arch tooling to FAIL (as it is absent on Fedora) and confirm each
# gated migration still exits 0 without invoking any of it.
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
BIN="$TMP/bin"; mkdir -p "$BIN"
MOCK_LOG="$TMP/mock.log"

# omarchy-distro reports fedora; Arch tooling errors if ever reached.
printf '#!/bin/bash\necho fedora\n' >"$BIN/omarchy-distro"
for c in pacman snapper limine-mkinitcpio mkinitcpio omarchy-pkg-add omarchy-pkg-drop install; do
  printf '#!/bin/bash\nprintf "%s %%s\\n" "$*" >>"%s"\nexit 1\n' "$c" "$MOCK_LOG" >"$BIN/$c"
done
chmod +x "$BIN"/*

for base in 1781984677.sh 1781286586.sh 1781587663.sh 1786567036.sh 1786605598.sh; do
  f="$MIGRATIONS_DIR/$base"
  [[ -e $f ]] || { pass "# SKIP $base absent (pin rotated past it)"; continue; }
  : >"$MOCK_LOG"
  set +e
  ( export PATH="$BIN:$PATH" OMARCHY_DISTRO=fedora HOME="$TMP/home"
    mkdir -p "$TMP/home"
    bash -euo pipefail "$f" ) >"$TMP/out" 2>&1
  rc=$?
  set -e
  assert_equals "$base: exits 0 on Fedora (no pipeline wedge)" "$rc" "0"
  if [[ -s $MOCK_LOG ]]; then
    cat "$MOCK_LOG" >&2
    fail "$base: Fedora gate must run BEFORE any pacman/snapper/pkg-add/install call"
  else
    pass "$base: Fedora path invokes no Arch tooling"
  fi

  if [[ $base == "1786567036.sh" || $base == "1786605598.sh" ]]; then
    : >"$MOCK_LOG"
    continuation="$TMP/$base.sourced"
    set +e
    ( export PATH="$BIN:$PATH" OMARCHY_DISTRO=fedora HOME="$TMP/home"
      source "$f"
      touch "$continuation" ) >"$TMP/out" 2>&1
    rc=$?
    set -e
    assert_equals "$base: can be sourced on Fedora without exiting its caller" "$rc" "0"
    assert_file_exists "$base: sourced Fedora gate returns to its caller" "$continuation"
    if [[ -s $MOCK_LOG ]]; then
      cat "$MOCK_LOG" >&2
      fail "$base: sourced Fedora gate must invoke no Arch tooling"
    else
      pass "$base: sourced Fedora path invokes no Arch tooling"
    fi
  fi
done

echo "# all migration-gating tests passed"
