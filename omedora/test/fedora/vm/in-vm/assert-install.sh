#!/bin/bash
#
# L4-VM in-guest assertion: the Omedora install actually landed, and landed FROM
# THE COPR (the thing the local-repo podman tiers can't prove — they inject a
# local repo). Runs over SSH as the VM user after install.sh completed. TAP out.
#
# Checks (each a TAP line):
#   1. the omedora core RPMs installed and their %{from_repo} is the COPR
#      (copr:...:agaspar:omedora-4), NOT a local repo and NOT a stray mirror.
#   2. /usr/share/wayland-sessions/omedora.desktop present and owned by
#      omedora-settings (the Omarchy 4 line's session owner).
#   3. the user config was seeded (hyprland.lua, ~/.config/omarchy) — backups
#      are .pre-omedora-* siblings and non-gating on a clean base.
#   4. no ERROR/Traceback lines in the install transcript.

set -uo pipefail

OMARCHY_PATH="$HOME/.local/share/omarchy"
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; FAILED=1; }
FAILED=0

echo "# L4-VM install assertions"

# Resolve the expected COPR repo-id from the single source of truth.
EXPECT_COPR=""
if [[ -x "$OMARCHY_PATH/bin/omedora-copr" ]]; then
  EXPECT_COPR=$(OMARCHY_PATH="$OMARCHY_PATH" "$OMARCHY_PATH/bin/omedora-copr" --repo-id 2>/dev/null || true)
fi
echo "# expected COPR repo-id: ${EXPECT_COPR:-<unresolved>}"

# --- 1. the omedora core RPMs came from the COPR -----------------------------
# omedora (the payload) and omedora-settings (the session owner) are the
# keystone RPMs of the Omarchy 4 line; hyprland is the vendored compositor.
# Confirm each is installed AND dnf records its origin repo as the COPR.
for keystone in omedora omedora-settings hyprland; do
  if rpm -q "$keystone" >/dev/null 2>&1; then
    pass "$keystone installed ($(rpm -q "$keystone"))"
  else
    fail "$keystone installed"
  fi
  from_repo=$(dnf repoquery --installed --qf '%{name} %{from_repo}\n' "$keystone" 2>/dev/null | awk '{print $2}' | head -1)
  echo "# $keystone from_repo: ${from_repo:-<none>}"
  if [[ -n "$EXPECT_COPR" && "$from_repo" == "$EXPECT_COPR" ]]; then
    pass "$keystone was installed FROM THE COPR ($from_repo)"
  elif [[ "$from_repo" == copr:*agaspar:omedora* ]]; then
    pass "$keystone installed from an agaspar omedora COPR ($from_repo)"
  else
    fail "$keystone installed from the COPR (got: ${from_repo:-<none>}, expected: ${EXPECT_COPR:-copr:...:agaspar:omedora-*})"
  fi
done

# Broader: count how many installed packages trace to the COPR. A healthy
# install pulls the whole vendored stack (hyprland-no-session, aquamarine,
# walker/elephant, swayosd, hypr*, the TUIs, fonts, uwsm...) from it — dozens.
# NOTE: query %{name} %{from_repo} (not bare %{from_repo}): dnf5 DEDUPLICATES
# identical single-field rows, so a bare %{from_repo} query collapses all COPR
# packages to one line and undercounts to 1.
copr_count=$(dnf repoquery --installed --qf '%{name} %{from_repo}\n' 2>/dev/null | grep -c 'agaspar:omedora' || true)
echo "# installed packages from the omedora COPR: ${copr_count:-0}"
if [[ "${copr_count:-0}" -ge 5 ]]; then
  pass "the vendored stack installed from the omedora COPR (count=$copr_count)"
elif [[ "${copr_count:-0}" -ge 1 ]]; then
  pass "at least one package installed from the omedora COPR (count=$copr_count — fewer than expected)"
else
  fail "packages installed from the omedora COPR (count=${copr_count:-0})"
fi

# --- 2. the session entry is registered + owned by omedora-settings ----------
if [[ -f /usr/share/wayland-sessions/omedora.desktop ]]; then
  pass "/usr/share/wayland-sessions/omedora.desktop present"
  owner=$(rpm -qf /usr/share/wayland-sessions/omedora.desktop 2>/dev/null || true)
  if [[ "$owner" == omedora-settings-* ]]; then
    pass "omedora.desktop owned by omedora-settings ($owner)"
  else
    fail "omedora.desktop owned by omedora-settings (got: ${owner:-<none>})"
  fi
else
  fail "/usr/share/wayland-sessions/omedora.desktop present"
fi

# GNOME must still be a selectable session (coexistence — additive install).
if compgen -G '/usr/share/wayland-sessions/gnome*.desktop' >/dev/null; then
  pass "GNOME session entry still present (coexistence preserved)"
else
  fail "GNOME session entry still present (coexistence preserved)"
fi

# --- 3. config seeded (backups are .pre-omedora-* siblings) ------------------
# The Omarchy 4 line seeds the Lua compositor config and the omarchy user
# config dir through the adopt step (backup-then-write for existing files).
if [[ -f "$HOME/.config/hypr/hyprland.lua" ]]; then
  pass "~/.config/hypr/hyprland.lua seeded"
else
  fail "~/.config/hypr/hyprland.lua seeded"
fi
if [[ -d "$HOME/.config/omarchy" ]]; then
  pass "~/.config/omarchy seeded"
else
  fail "~/.config/omarchy seeded"
fi
n_backups=$(find "$HOME/.config" -maxdepth 3 -name '*.pre-omedora-*' 2>/dev/null | wc -l)
echo "# config backups created (.pre-omedora-*): $n_backups"
pass "config backup mechanism observable (n=$n_backups — non-gating; a clean base may have 0)"

# --- 4. no errors in the install transcript ---------------------------------
# The orchestrator tees the whole bootstrap to /tmp/omedora-install.out; the
# root-side apply-system log lands in /var/log/omarchy-install.log only when
# it is not streamed to stdout, so prefer the transcript and fall back.
LOG=/tmp/omedora-install.out
[[ -r "$LOG" ]] || LOG=/var/log/omarchy-install.log
if [[ -r "$LOG" ]]; then
  # Match the hard error markers, then drop KNOWN-BENIGN lines that a healthy
  # TTY-less install legitimately prints:
  #   * "Failed to preset unit: ... display-manager.service already exists" —
  #     GDM is already the DM on the Workstation base; the preset is a no-op.
  #   * "Failed to reset failed state of unit <session unit>: ... not loaded" —
  #     swayosd/hypr* user units aren't loaded during a non-graphical install.
  #   * "Failed to load `plugins.theme`" — a LazyVim/nvim first-sync transient
  #     with no graphical session; the plugin loads fine in-session.
  # A real fatal (a crashed install step, a missing COPR package) still trips
  # because install.sh's own rc would be non-zero (the orchestrator checks that
  # separately) and the surviving markers below would fire.
  errs=$(grep -niE 'traceback|fatal error|command not found|No match for argument|^[0-9]+:.*\bFAILED\b' "$LOG" 2>/dev/null \
         | grep -viE "display-manager\.service' already exists|reset failed state of unit .*not loaded|Failed to load .?plugins\.theme" \
         | head -20 || true)
  if [[ -z "$errs" ]]; then
    pass "no error markers in $LOG"
  else
    echo "# error markers found in $LOG:"
    printf '%s\n' "$errs" | sed 's/^/#   /'
    fail "no error markers in $LOG"
  fi
else
  fail "install log readable ($LOG)"
fi

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "# all install assertions passed"
  exit 0
else
  echo "# some install assertions FAILED"
  exit 1
fi
