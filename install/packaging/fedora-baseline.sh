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

omarchy-pkg-add xdg-utils pipewire pipewire-pulseaudio pipewire-alsa
