#!/bin/bash
#
# systemctl shim for the omedora-session test image.
#
# Fedora docker containers don't run systemd as PID 1, so the real systemctl
# fails on `enable`/`start`/`restart`/`daemon-reload`. This shim intercepts
# those calls during the install:
#
#   - enable / disable / mask / unmask: silently succeed (no symlinks created)
#   - daemon-reload / daemon-reexec: silently succeed
#   - start / stop / restart: silently succeed (we have nothing to start)
#   - is-active / is-enabled: report "inactive" / "disabled"
#   - status: succeed with minimal output
#   - everything else: forward to real systemctl (which will likely fail —
#     surfacing that is fine)
#
# The shim is ONLY active during the install build. The real session boot
# (in a future stage) needs real systemd via --systemd=true or equivalent.

case "${1:-}" in
  enable|disable|mask|unmask|reenable|preset|preset-all|set-default|edit|revert|link)
    exit 0
    ;;
  daemon-reload|daemon-reexec)
    exit 0
    ;;
  start|stop|restart|try-restart|reload|kill|set-property)
    exit 0
    ;;
  is-active)
    echo inactive
    exit 3
    ;;
  is-enabled)
    echo disabled
    exit 1
    ;;
  status)
    echo "shim: systemctl unavailable in container build context"
    exit 0
    ;;
  *)
    exec /usr/bin/systemctl "$@"
    ;;
esac
