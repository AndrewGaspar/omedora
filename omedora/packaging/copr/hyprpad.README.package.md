# hyprpad Fedora package notes

The package installs the daemon, the on-screen keyboard, the helper scripts,
and every host integration file from upstream `packaging/`, with paths
rewritten from a source checkout to `/usr/bin`. Nothing is enabled for you.

## Host integration (root, once)

Installing the package creates the `hyprpad` group (via sysusers) and installs
the udev rule to `/usr/lib/udev/rules.d/72-hyprpad-puck.rules`. The rule only
applies to controller nodes that appear afterwards, so reload udev, re-trigger
once, enable the broker socket, and join the group:

```bash
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=hidraw
sudo systemctl enable --now hyprpad-broker.socket
sudo usermod -aG hyprpad "$USER"
```

Then log out and back in. Group membership only reaches processes started
after it is granted, and that includes the systemd user manager.

## Running at login (per user)

```bash
systemctl --user enable --now hyprpad.service
```

The packaged user unit lives in `/usr/lib/systemd/user/hyprpad.service`.
`hyprpad setup --check` currently looks for it only under
`~/.config/systemd/user`, so it reports the unit as missing even while it is
running; the "daemon under the unit" line is the one that tells the truth.

## Steam masking and the Omarchy shell

Steam itself is not in Fedora's repositories; the masked launcher works with
whatever Steam you run (RPM Fusion, Flatpak, or Valve's own installer):

```bash
hyprpad setup                 # prints the Steam wrapper install; nothing runs
hyprpad-cheatsheet install    # copies the plugin from /usr/share/hyprpad/shell
omarchy plugin enable hyprpad.cheatsheet
hyprpad-statusbar install
omarchy plugin enable hyprpad.status
```

Example configuration is in `/usr/share/doc/hyprpad/hyprpad.lua` and the
compositor-side rules in `/usr/share/doc/hyprpad/hyprpad-rules.lua`. The
on-screen keyboard runs without a prediction model; see
`/usr/share/doc/hyprpad/README.osk.md` for building one (the
`hyprpad-osk-build-model` binary is in this package).
