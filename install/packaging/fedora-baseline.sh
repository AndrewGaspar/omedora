#!/bin/bash

# Fedora-only: install desktop runtime that Arch pulls in transitively but
# Fedora's package set doesn't guarantee, and that omedora's own features
# depend on. A real Fedora Workstation already ships these; installing them
# here means omedora works on any Fedora base (minimal, Server, Workstation),
# not just Workstation. (System *config* — sysctl, services policy — remains
# the administrator's job; this is desktop runtime, not config.)
#
#   xdg-utils            xdg-settings / xdg-mime / xdg-open. Without it the
#                        default-browser + MIME setup (install/config/
#                        mimetypes.sh) silently skips and omarchy-launch-browser
#                        can't resolve the browser.
#   pipewire             the audio server daemon. Fedora installs wireplumber
#                        (session manager) but not always the daemon itself.
#   pipewire-pulseaudio  PulseAudio compat (pactl + the pulse socket) that
#                        waybar's audio module and swayosd talk to.
#   pipewire-alsa        ALSA compat — expected on a desktop.
#   util-linux-script    the `script` PTY logger. On Arch it ships in util-linux
#                        (base); Fedora 44 split it out of util-linux-core, so a
#                        minimal base lacks it. omarchy-update re-execs itself
#                        under `script` to log the session to
#                        /tmp/omarchy-update.log — without it the update runs
#                        unlogged (bin/omarchy-update guards on `command -v
#                        script`). Installing it here restores the logged path.

omarchy-pkg-add xdg-utils pipewire pipewire-pulseaudio pipewire-alsa util-linux-script

# Fedora wifi TUI: impala (omarchy's Super+Ctrl+W panel) needs iwd, which Fedora
# Workstation doesn't run — it rides NetworkManager. gazelle-tui is a
# NetworkManager wifi TUI that fills the same slot (and adds 802.1X enterprise
# support); omarchy-launch-wifi launches it in impala's place on Fedora.
omarchy-pkg-add gazelle-tui
