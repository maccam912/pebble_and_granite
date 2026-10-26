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

## Held-state Android checkpoint

Clean `f2444cd` (model 3 / protocol 9 / rules 3 / input 4 / practice schema 3)
passed the expanded installed touch probe, including Home/background with a held
contact, unchanged pending journal on resume, regrip and a left finishing flick.
Both normal curl directions and the exact-once held hog fault also passed.
APK SHA-256: `f42820b2f3df24b1b3a9f0524a3373d66495f4b01ad8cc6e9c80fdfd86726016`.
Evidence: `build/probes/touch-2d6a3f3403244848948ef4f26ef90c4f/`.

A subsequent explicit Godot cancelled-touch test found an input path that could
release before a focus notification. Commit `e5b1e33` fixes that path and passes
local/online regression tests. Its final installed package validation follows.

## Corrected contact-cancellation package

Clean commit `5cd1808`, build 3, includes the cancelled-touch fix and passed the
expanded installed touch probe and all six native golden/JNI checks. SHA-256:
`5179039571c17f9ec5afaf2747f13867b9266f11a07d18ef262e423959d4086a`.
Touch evidence: `build/probes/touch-dedff4262b724bf6bfa8ceb0e91b5a3e/`.
The recorded interrupted plan retained 1732 mm/s target, -900 mm aim and 1951 ms
elapsed across background/resume, then accepted one left-curl finishing release.

The forced-relay Android↔macOS probe now begins a held plan, advances it for two
seconds and releases through ReleaseDelivery before the in-flight disconnect.
Both peers finished at `af5dbdcd7faad18c`; evidence is under
`build/probes/af29d0ef331b4ce5b399d75544c88524/`. The host verifies that the shot
used the held lifecycle. This covers Android replication of held commands and
in-flight restoration; in-hand reconnect remains validated on four desktop
endpoints, not yet on the installed Android client.

## Installed remote thrower held reconnect

Clean `13a3f31`, build 4, passed the two-delivery forced-relay probe on Android 35
ARM64. The client first reconnects during flight, then becomes the next thrower
and drives the actual online scene's push/regrip/finishing methods. Disconnect
during that held slide restored a suspended plan at 1900 ms, target 2050 mm/s,
aim -900 mm and centre -33.473909 m. The client verified the pose stayed unchanged
for 350 ms before regripping and finishing left. Both peers ended at
`d82d243a915944fa`. APK SHA-256:
`73bb46067bbce7ce389415fb3336ea74ef602ad6c9783039158a0051ffc4928d`.
Evidence: `build/probes/5671d030ca1346f099bf2a9eaa686286/result.json`.

This closes the installed in-hand reconnect gate. Gesture timing here is injected
through the actual online scene methods; separate touch probes cover Android
touchscreen routing. It is not a physical-device or uncontrolled-latency playtest.
