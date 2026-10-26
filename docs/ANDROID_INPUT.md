# Installed Android input validation

The direct-on-ice scene was tested on the Android 35 ARM64 emulator
`emulator-5580`, at 2400×1080 landscape. The game fits its 1280×800 logical canvas
at scale 1.35 with a 336-pixel horizontal offset. This is emulator evidence;
physical-device feel, latency and GPU performance remain unmeasured.

The locally packaged APK came from clean commit `eecf858`, using the installed
Godot 4.7 Android templates, with model 3 / protocol 8 / rules 3 / input 3:

`be865178b57908107fae5dba959dec8f935954f6a728257b37565e6c1fcc929f`

The installed native simulation matched all six every-tick golden traces and the
Android transport/JNI availability check passed. Real Android touchscreen events
then exercised the visible 3D handle, pull-back, forward drive, held slide and
left/right finishing movement. The saved release records had the corresponding
negative/positive spin; holding through the hog line produced exactly one removed
stone, and lifting afterward did not add or change a delivery.

Evidence from this machine:

- `build/probes/touch-8caff5c6cace4ebf99bcc7e4e5f7bd72/result.json`: APK hash,
  Android SDK, event timing, accepted release data and hog fault.
- The same directory contains held/released screenshots and saved journals.
- `build/evidence/direct-android/before-practice-session.json` preserves the
  prior model-2 emulator session; the app rejected it without overwriting it.
- `build/evidence/android-self-test.json`: native golden/JNI probe result.

## Repeat the probe

Use an explicitly selected test emulator with the observed layout. It installs the
specified APK, saves copies of existing practice files, starts the game, uses
Fresh ice between cases and leaves a fresh practice session at completion. It does
not clear application storage, match saves or network identity.

```sh
python3 tools/android_touch_probe.py build/download/pebble-and-granite-1-android.apk --serial emulator-5580
```

The probe requires moving touch contacts before UP; changing only the coordinates
of an injected UP event did not exercise the Android moving-touch path. The final
flick therefore includes two MOVE samples and then UP. Each probe writes a new
`build/probes/touch-<nonce>/` directory. Update the observed coordinate profile if
the screen layout changes; this script deliberately rejects other pixel sizes.

The native/core tests cover bounded forward/back weight trim and frame-independent
input mapping. The installed touch probe checks physical input routing and spin
signs, not exact gesture-speed reproducibility across ADB command timings.

## Cross-device regression

The same APK passed an Android-to-macOS forced-relay shot and in-flight reconnect.
Both peers finished at hash `1f145c13ee8ae46b`. Evidence:
`build/probes/9f0c034758d3408e8a520e876afb5b3a/result.json`.

```sh
GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot python3 tools/network_probe.py --apk build/download/pebble-and-granite-1-android.apk --serial emulator-5580 --relay-only
```

This probe uses a controlled release and validates transport/replay across the
installed ARM64 app and desktop; the direct gesture routing is covered separately
by the touchscreen probe above. It does not yet validate an in-hand reconnect.
