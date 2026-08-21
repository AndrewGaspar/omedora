# WiVRn HypXR capture compatibility on Fedora

This RPM contains only the host server, OpenXR runtime, and `wivrnctl`. It does
not contain an Android APK. The stock WiVRn client from the Meta Store or the
upstream nightly channel does not provide HypXR recorder/device-take support.

## Mandatory custom client

Headset passthrough-camera or raw-microphone capture requires a custom APK built
from the same immutable source as this host package:

* repository: `https://github.com/AndrewGaspar/WiVRn.git`
* branch provenance: `hypxr`
* required commit: `3729c7b3106c66a69b88d812ebd6eba9c4fe4744`
* required protocol version: `0x31fb598ecb986230`
* required build capability: `-Phypxr_recorder_probe=ON`

Omedora does not publish or redistribute this APK. Build it from source:

```sh
git clone --branch hypxr https://github.com/AndrewGaspar/WiVRn.git WiVRn-hypxr
cd WiVRn-hypxr
git checkout --detach 3729c7b3106c66a69b88d812ebd6eba9c4fe4744
test "$(git rev-parse HEAD)" = 3729c7b3106c66a69b88d812ebd6eba9c4fe4744
export ANDROID_HOME="$HOME/Android"
export JAVA_HOME=/path/to/jdk17-or-jdk21
./gradlew assembleReleaseDebuggable -Phypxr_recorder_probe=ON
adb install -r build/outputs/apk/releaseDebuggable/WiVRn-releaseDebuggable.apk
```

Follow upstream `docs/building.md` for Android SDK, CMake 3.31.5, KTX `toktx`,
signing, and ADB setup. Keep a rollback copy of the previous APK. The APK and
host must move together; a successful handshake alone does not prove capture.

Camera capture additionally requires headset Passthrough Camera Access through
the raw Camera2 path (Horizon OS v76 or newer for this implementation),
passthrough enabled, and camera permission. Raw microphone capture requires the
WiVRn microphone to be enabled and actively streaming.

## Stock-client behavior

With a stock or otherwise unsupported client, `wivrnctl take start` can still
record the host half: composited eye buffers, application audio, pose/FOV
telemetry, and the host/device clock series. Camera or microphone requests
degrade explicitly to host-only, and the manifest marks those sources false.

Device capture remains experimental. Validate generated manifests and media on
the target headset and OS; do not infer camera or microphone success from an
APK build, install, pairing, or host-only recording.
