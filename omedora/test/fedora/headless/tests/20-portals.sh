#!/bin/bash
#
# L4-headless acceptance test for xdg-desktop-portal in the Omedora session.
#
# Guards two portal regressions seen in the L4 session (tasks #55 + the
# document-portal failure):
#
#   1. The MAIN portal (xdg-desktop-portal.service) must be reachable and active,
#      with BOTH backends loaded — xdg-desktop-portal-hyprland (Screenshot,
#      ScreenCast, GlobalShortcuts) and xdg-desktop-portal-gtk (file pickers).
#      The service is D-Bus-activated (Type=dbus, started on first call), and its
#      unit carries `Requisite=graphical-session.target`, so it only starts once
#      uwsm's graphical-session.target is active. We trigger activation with a
#      real introspect against the Desktop object, then assert the unit + both
#      backend names.
#
#   2. The document portal (xdg-document-portal.service) must start. It
#      FUSE-mounts a document store at $XDG_RUNTIME_DIR/doc, which needs both
#      /dev/fuse AND mount(2) privilege. Under rootless podman the user-ns drops
#      CAP_SYS_ADMIN, so the mount fails EPERM and the unit lands `failed` — a
#      pure HARNESS artifact, not an omedora defect (bare-metal Fedora's session
#      already has the capability). run-tests.sh re-grants it with
#      `--cap-add SYS_ADMIN` when /dev/fuse is present, so in a properly
#      provisioned run this unit is active. If the run lacks /dev/fuse entirely
#      we SKIP the doc-portal assertion rather than fail (it genuinely can't work
#      without the device) — but the main portal must work regardless.
#
# Convention: source ../lib.sh, attach to the session, then assert via TAP.
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
headless_session_env

# --- 1. main portal + backends ----------------------------------------------
# Trigger D-Bus activation of the main portal (idle dbus services read as
# `inactive` until first use; this is the file-picker / screenshot entry point).
busctl --user introspect org.freedesktop.portal.Desktop \
  /org/freedesktop/portal/desktop org.freedesktop.portal.Screenshot \
  >/dev/null 2>&1 || true

wait_for_unit_active xdg-desktop-portal.service 10
assert_unit_active xdg-desktop-portal.service \
  "main portal (xdg-desktop-portal) is active"

# The Screenshot impl backend (screenshots / screencast / global shortcuts).
wait_for_unit_active xdg-desktop-portal-hyprland.service 5
assert_unit_active xdg-desktop-portal-hyprland.service \
  "hyprland portal backend is active"
assert_dbus_name org.freedesktop.impl.portal.desktop.hyprland \
  "hyprland backend owns its D-Bus name"

# The GTK impl backend (file choosers — the Open/Save dialogs).
wait_for_unit_active xdg-desktop-portal-gtk.service 5
assert_unit_active xdg-desktop-portal-gtk.service \
  "gtk portal backend is active"
assert_dbus_name org.freedesktop.impl.portal.desktop.gtk \
  "gtk backend owns its D-Bus name"

# The Desktop object answers a real method introspect (proves the portal frontend
# is functional, not merely "started"). Screenshot.Screenshot is the method
# task #55 (screenshots) ultimately drives.
intro=$(busctl --user introspect org.freedesktop.portal.Desktop \
  /org/freedesktop/portal/desktop org.freedesktop.portal.Screenshot 2>/dev/null)
assert_output_contains "portal exposes the Screenshot method" "$intro" ".Screenshot"

# --- 2. document portal (harness-gated on /dev/fuse + CAP_SYS_ADMIN) ---------
if [[ -e /dev/fuse ]]; then
  # run-tests.sh adds --cap-add SYS_ADMIN whenever it passes /dev/fuse, so the
  # FUSE mount should succeed and the unit should be active.
  wait_for_unit_active xdg-document-portal.service 10
  assert_unit_active xdg-document-portal.service \
    "document portal is active (FUSE mount succeeded)"
  if mount 2>/dev/null | grep -q "$XDG_RUNTIME_DIR/doc"; then
    pass "document store is FUSE-mounted at \$XDG_RUNTIME_DIR/doc"
  else
    _fail_with_artifacts "document store is FUSE-mounted at \$XDG_RUNTIME_DIR/doc"
  fi
else
  # No /dev/fuse: document-portal cannot work and this is not an omedora bug.
  # Record skips so the plan count stays stable; the main portal still gates.
  pass "# SKIP document portal: no /dev/fuse in this run (device required)"
  pass "# SKIP document store mount: no /dev/fuse in this run (device required)"
fi
