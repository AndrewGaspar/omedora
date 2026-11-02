# monado-xreal Fedora package notes

`monado-xreal` is HypXRland's private Monado runtime for XREAL Air glasses. Its
service binary, libraries, IPC socket and OpenXR manifest have private names,
so it installs alongside the WiVRn runtime:

- service: `/usr/libexec/monado-xreal/monado-service`, run by the user unit
  `monado-xreal.service`
- manifest: `/usr/share/openxr/1/openxr_monado-xreal.json`
- tools: `/usr/libexec/monado-xreal/monado-cli`

Tracking is 3DoF unless you turn 6DoF on.

## 6DoF (positional tracking)

6DoF runs visual-inertial SLAM on the glasses' stereo cameras through the
Basalt tracker in `basalt-xreal`, which this package pulls in. The unit already
points Monado at it:

- `VIT_SYSTEM_LIBRARY_PATH=/usr/lib64/basalt-xreal/libbasalt.so.2`
- `XREAL_AIR_SLAM_CONFIG=/usr/share/basalt-xreal/xreal_air.toml`

To turn it on, add a drop-in and restart the service:

```bash
mkdir -p ~/.config/systemd/user/monado-xreal.service.d
printf '[Service]\nEnvironment=XREAL_AIR_SLAM=1\n' \
  > ~/.config/systemd/user/monado-xreal.service.d/20-xreal-6dof.conf
systemctl --user daemon-reload
systemctl --user restart monado-xreal.service
```

`journalctl --user -u monado-xreal.service` shows the tracker loading. If
Basalt cannot load, Monado logs the error and stays on 3DoF.

The camera calibration comes from the glasses. `xreal_air.toml` holds only the
pipeline settings. Basalt is built for x86-64-v3 (AVX2/FMA) CPUs.

## Plane detection

Plane detection (`XR_EXT_plane_detection`, horizontal surfaces such as tables
and the floor) needs 6DoF. Add it to the same drop-in:

```ini
[Service]
Environment=XREAL_AIR_SLAM=1
Environment=XREAL_AIR_PLANES=1
```

The tuning variables (`XREAL_AIR_SLAM_*`, `XREAL_AIR_PLANES_*`) are documented
in the fork's `src/xrt/drivers/xreal_air/xreal_air_slam.h`.

## Using your own Basalt build

Point `VIT_SYSTEM_LIBRARY_PATH` at your library in a drop-in. The unit's
`XREAL_AIR_SLAM_CONFIG` still selects the packaged settings. Set it to your
own `xreal_air.toml`, or set it empty (`Environment=XREAL_AIR_SLAM_CONFIG=`)
to use the `share/basalt/xreal_air.toml` next to your library.

## Replaying a recording

`monado-cli xreal-slam-replay` runs an XREAL EuRoC recording through the
driver's 6DoF path. It does not read the unit's environment, so pass the
library and settings yourself:

```bash
VIT_SYSTEM_LIBRARY_PATH=/usr/lib64/basalt-xreal/libbasalt.so.2 \
XREAL_AIR_SLAM_CONFIG=/usr/share/basalt-xreal/xreal_air.toml \
  /usr/libexec/monado-xreal/monado-cli xreal-slam-replay <dataset_dir> <out_dir>
```

Add `XREAL_AIR_PLANES=1` to also report the planes it finds.
