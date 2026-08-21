# hypxrhud on Fedora

The upstream documentation includes source-tree and user-local installation
examples. Do not repeat those steps for this RPM. Fedora owns these paths:

* `/usr/bin/hypxrhud`: D-Bus-activated HUD daemon
* `/usr/bin/hypxrhud-battery`: WiVRn and UPower battery producer
* `/usr/bin/hypxrhud-keys`: ShowMeTheKey keystroke producer
* `/usr/bin/hypxrhud-cmdlog`: typed `hyprctl` command producer
* `/usr/lib/systemd/user/hypxrhud*.service`: package-owned user units
* `/usr/share/hypxrhud/examples`: reference producer configuration
* `/usr/share/hypxrhud/shim/hyprctl`: optional command-ticker PATH shim

The daemon starts through D-Bus when a producer creates a panel. The battery
producer is suitable for normal enablement:

```sh
systemctl --user enable --now hypxrhud-battery.service
```

The keys and command-log producers are privacy-visible filming aids. Their
units are static by design, so start and stop them explicitly:

```sh
systemctl --user start hypxrhud-keys.service hypxrhud-cmdlog.service
systemctl --user stop hypxrhud-keys.service hypxrhud-cmdlog.service
```

`hypxrhud-keys` only works when the external `/usr/bin/showmethekey-cli`
backend is installed. This RPM does not provide or start that backend.

The command ticker sees only invocations that pass through its shim. Omedora XR
prepends its private XR-aware `hyprctl` to PATH, so do not replace that session
client with the generic `/usr/bin/hyprctl`. To opt in while preserving the XR
client, place the ticker shim earlier in PATH and point it at the private client:

```sh
install -Dpm0755 /usr/share/hypxrhud/shim/hyprctl ~/.local/bin/hyprctl
export HYPXR_CMD_HUD_REAL=/usr/libexec/hypxrland/hyprctl
hash -r
systemctl --user start hypxrhud-cmdlog.service
```

Absolute client calls, direct IPC clients, and compositor keybinds bypass the
ticker. Remove `~/.local/bin/hyprctl` or set `HYPXR_CMD_HUD=0` to disable it;
the real command's arguments, streams, and exit status are otherwise preserved.
