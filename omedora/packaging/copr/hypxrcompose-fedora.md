# hypxrcompose on Fedora

This RPM patches the upstream defaults to use the `libsvtav1` encoder supplied
by Fedora's `ffmpeg-free` build. The packaged default is not `libx264` or
`libx265`; examples and performance notes in the upstream README that name
those encoders describe other ffmpeg builds. SVT-AV1 uses CRF quality control
with its fast preset 10.

You may pass `--codec` to select another encoder exposed by the installed
`/usr/bin/ffmpeg`, but availability and licensing depend on that ffmpeg
provider. The RPM requires the `/usr/bin/ffmpeg` and `/usr/bin/ffprobe`
capabilities rather than a package name, so Fedora's `ffmpeg-free` and RPM
Fusion's full `ffmpeg` can both satisfy it.

SVT-AV1 cannot write H.264/HEVC frame-packing SEI. Consequently, a stereo
side-by-side MP4 produced with the Fedora packaged default has no embedded
stereo signal. Use Matroska (`.mkv`), whose `StereoMode=left_right` metadata is
supported with SVT-AV1, when automatic stereo detection is required. MP4
frame-packing SEI is available only with a capable `libx264` or `libx265`
encoder and is not a feature of the Fedora default.
