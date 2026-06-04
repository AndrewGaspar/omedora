#!/bin/bash
#
# L4-headless coexistence test for the FEDORA WORKSTATION base (run-tests.sh
# --workstation). Validates the invariants that only exist when Omedora is layered
# on top of a real Fedora Workstation package set — the base most users actually
# install onto, and the one the minimal fedora:44 test base can't represent:
#
#   * Login-layer coexistence (the GNOME fallback): Omedora's Fedora session
#     install is additive (it keeps the existing DM and only adds its own
#     wayland-session entry — now shipped by the hyprland-omedora package, was a
#     sudo-cp), so GDM offers BOTH "GNOME" and "Omedora (Hyprland uwsm)" and the
#     user can log out of Hyprland into GNOME.
#   * Power coexistence: Omedora skips power-profiles-daemon and ships a
#     powerprofilesctl shim driving the Workstation ppd-service provider
#     (tuned-ppd). See install/packages/fedora.toml [power-profiles-daemon].
#   * Portal competition: xdg-desktop-portal-gnome is now installed alongside
#     xdg-desktop-portal-hyprland (the "hyprland wins" assertion is owned by
#     20-portals, which runs in the same suite; here we just confirm the GNOME
#     competitor is present).
#   * The Omedora/Hyprland session still comes up on the heavier base.
#
# This test is GATED: on the standard (non-Workstation) base there's no GNOME, so
# it emits TAP SKIPs and exits 0. That lets the single tests/ dir serve both
# `run-tests.sh` (90 SKIPs) and `run-tests.sh --workstation` (90 runs for real).
#
# Convention: source ../lib.sh, attach to the session, then assert via TAP.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

# --- gate: only meaningful on the Workstation base ---------------------------
# gnome-shell is the canonical marker that workstation-product-environment was
# installed (Dockerfile.workstation). Absent => standard base => SKIP, don't fail.
if ! rpm -q gnome-shell >/dev/null 2>&1; then
  pass "# SKIP workstation coexistence: not a --workstation base (no gnome-shell)"
  exit 0
fi

headless_session_env

# Diagnostics (not assertions) — record what actually landed, esp. the ppd
# provider, since which one the group pulled is the key real-world variable.
echo "# default target: $(systemctl get-default 2>/dev/null)"
echo "# ppd providers:  tuned-ppd=$(systemctl is-active tuned-ppd 2>/dev/null) ppd=$(systemctl is-active power-profiles-daemon 2>/dev/null)"
dump_state "90-workstation"

# --- 1. the Workstation set really landed ------------------------------------
# Guards against a silent fallback to the minimal image (which would make every
# coexistence assertion below vacuous).
if rpm -q gnome-shell gdm >/dev/null 2>&1; then
  pass "Workstation set present (gnome-shell + gdm installed)"
else
  _fail_with_artifacts "Workstation set present (gnome-shell + gdm installed)"
fi

# --- 2. login-layer coexistence: GNOME stays a selectable session ------------
# Both wayland-session entries must be registered so a real GDM greeter lists
# both. Omedora's entry is now shipped by the hyprland-omedora package (pulled in
# when `hyprland` remaps to hyprland-omedora on Fedora), not a sudo-cp.
if [[ -f /usr/share/wayland-sessions/omedora.desktop ]]; then
  pass "Omedora session entry registered (/usr/share/wayland-sessions/omedora.desktop)"
else
  _fail_with_artifacts "Omedora session entry registered (/usr/share/wayland-sessions/omedora.desktop)"
fi

if compgen -G '/usr/share/wayland-sessions/gnome*.desktop' >/dev/null; then
  pass "GNOME session entry still registered (GNOME selectable as a fallback)"
else
  _fail_with_artifacts "GNOME session entry still registered (GNOME selectable as a fallback)"
fi

# GDM must remain installed + UNMASKED so a real boot would present the greeter
# with both sessions. (Dockerfile.workstation only changes the default target; it
# does not mask GDM.) A masked unit could never run — that would defeat the point.
if [[ "$(systemctl is-enabled gdm.service 2>/dev/null)" != "masked" ]]; then
  pass "GDM present + not masked (greeter would list GNOME + Omedora)"
else
  _fail_with_artifacts "GDM present + not masked (greeter would list GNOME + Omedora)"
fi

# GNOME is actually launchable (backs run-session.sh --workstation --gnome).
if gnome-shell --version >/dev/null 2>&1; then
  pass "GNOME Shell is launchable ($(gnome-shell --version 2>/dev/null))"
else
  _fail_with_artifacts "GNOME Shell is launchable"
fi

# --- 3. power coexistence (the exact VM bug class) ---------------------------
# Omedora's contract is the powerprofilesctl CLI working against whatever
# ppd-service the base provides (tuned-ppd on Workstation), via its shim — WITHOUT
# power-profiles-daemon's own daemon running (the two mutually Conflict).
if command -v powerprofilesctl >/dev/null 2>&1 && powerprofilesctl get >/dev/null 2>&1; then
  pass "powerprofilesctl works ($(powerprofilesctl get 2>/dev/null) via the shim/tuned-ppd D-Bus API)"
else
  _fail_with_artifacts "powerprofilesctl works against the Workstation ppd-service"
fi

if [[ "$(systemctl is-active power-profiles-daemon.service 2>/dev/null)" != "active" ]]; then
  pass "power-profiles-daemon's own daemon is not the active provider (kept Fedora's tuned-ppd)"
else
  _fail_with_artifacts "power-profiles-daemon's own daemon is not the active provider"
fi

# --- 4. portal competitor is present -----------------------------------------
# The GNOME portal backend is now installed; that's the competition 20-portals
# verifies hyprland still wins over. Here we just confirm the competitor exists,
# so a green 20-portals on this base is a meaningful coexistence result.
if rpm -q xdg-desktop-portal-gnome >/dev/null 2>&1; then
  pass "xdg-desktop-portal-gnome installed (portal competition is real on this base)"
else
  _fail_with_artifacts "xdg-desktop-portal-gnome installed (portal competition is real on this base)"
fi

# --- 5. the Omedora/Hyprland session still came up ---------------------------
# Workstation packages must not have broken the default session.
assert_monitor "Omedora/Hyprland session up on the Workstation base"
