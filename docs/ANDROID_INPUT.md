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

## Rules-4 / per-player sweeping package

Clean `ea1ee40`, local build 5, is model 3 / protocol 10 / rules 4 / input 4.
APK SHA-256: `5a1598eb27e51b0ae4862926fe8b8a00013e750df051564dc3fdfed8c9391c49`.
It passed all six installed native golden/JNI traces, the complete direct-touch
probe (both curl signs, Home/pause/regrip and exact-once hog fault), and the
two-delivery forced-relay probe with continuous sweeping by the remote thrower.

- Touch: `build/probes/touch-fb7b55c23dad4a0a96870bee55f3cfaa/`.
- Relay: `build/probes/1376eefd8bd943ceb945e748ff2153e2/result.json`; host/client
  hash `27700e67832af91f`, both held/in-flight reconnect flags and
  `swept_as_thrower` true.

Desktop full-match coverage also swept with both teammates. The installed probe
does not establish a physical two-device full-match/performance result. Local
APK build numbers are diagnostic labels; GitHub release numbers are independent.

## Spatial sweeping / analog delivery package

Clean `12849e6`, local build 6, is model 3 / protocol 11 / rules 4 / input 5.
It uses the existing installed Godot 4.7 Android templates; package metadata
records `source_dirty: false`. APK SHA-256:
`5e1d0212fb9fdc3b6ca9a0632e9aa3145421fdff51c4f2ca2460df5a811e8027`.

Installed on Android 35 ARM64 `emulator-5580`, it passed all six native golden
traces/JNI checks, both direct-touch curl directions, Home/pause/regrip and the
exact-once held hog fault. The expanded touch probe also drove actual moving
touch contacts ahead of the stone. Its journal recorded 22 spatial brush spans,
effort 59–255, and lateral offsets -124/+139 mm. The saved sweep spans stopped
changing after UP. A separate real touchscreen hold on the GUI button produced
255 effort at 0 mm lateral / 180 mm ahead.

Evidence: `build/probes/touch-c3719bed70544f69b4f616a3a6519023/result.json`,
the journal files/screenshots beside it, and `build/evidence/android-self-test.json`.
The Android Sweeper view and selection disc were visually inspected. This is
installed emulator input evidence, not physical-device feel or GPU performance.

The same APK passed the Android↔macOS forced-relay two-delivery probe, including
held/in-flight reconnect, suspended analog position, regrip/release and continuous
thrower sweeping. Host/client hash: `b932c1c5128ec7cd`. Evidence:
`build/probes/2f0cc14f4cf842038562725e5360c2d6/result.json`.


## Solo/control/camera installed checkpoint — 27 October 2026

Clean source `f573bdc5234a924050d62c666846e5c79ba0dbbc`, local Android build 75,
Godot 4.7 with existing installed Android templates (`template_source=installed-android`).
APK: `build/android/pebble-and-granite.apk`; exact manifest:
`build/download/pebble-and-granite-75-android.json` (`source_dirty=false`).
SHA256: `1349ca9af2de416ec2d1d563c924f54239ce0d365572cbbf094eb38163ca1da4`.
Android v2 signature verification passed. This local build number is separate
from the numbered GitHub release pipeline.

Dedicated `pebble_granite_lab`, emulator-5580, Android 35 ARM64, 2400x1080 landscape:

- Installed shared golden-trace/JNI self-test passed (`build/solo-android-runtime.log`).
- Actual adb menu/touch flow selected Calling only, Elite and opponent fast travel;
  changed the shot to guard, inspected it with zoom, sent the AI delivery, and
  issued HARD then OFF through the real GUI buttons.
- Opened the observed ice board, verified a frozen authoritative hash while open,
  resumed, observed opponent-only fast travel, and reached the next Gold approval.
- Two accepted AI deliveries / two review paths; exported Android match journal
  replay-verified on desktop at hash `cb90ff1fc182d9c9`. All normal practice/match/
  solo/drill saves, preferences and note sidecars were unchanged by this UI probe.
- Evidence: `build/probes/solo-ui-396e7af610404eb8a2f4a64c98d0871d/` contains result,
  actual taps, eight screenshots, exported journal and desktop verifier output.
  Two earlier terminal attempts exposed a fixture assumption: touch-opened Android
  popups have no keyboard-focused row, so the first Down selects row zero. The adb
  driver was corrected; this did not require a gameplay/APK change.
- Android reports the device speech feature and 51 English voices. The emulator
  used no-audio mode; this is voice availability, not audible/human approval.

The same APK passed the existing direct-touch suite: both curl signs, spatial
scrubbing, no extra heat after lift, accessible hold, held Home/pause/regrip and
exact-once hog handling. Evidence:
`build/probes/touch-e66eb845ed6247fd8d49a61c9bf87018/`, log
`build/solo-android-touch.log`. The original dedicated-emulator practice primary
and backup were restored byte-for-byte after the fixture's Fresh ice cases.

This verifies installed emulator behavior and cross-core replay. It does not
approve physical Android feel, latency/thermals, audio quality, or measured ice
calibration. The latest source release/CI state is tracked in AI_PROGRESS.md.

The subsequent checkpoint only adjusts the resting-shot caption to identify the
next thrower explicitly, alongside host-fixture/docs changes. Installed evidence
above remains tied to f573bdc; the caption change has local native coverage.

## Team-rule follow-up — 27 October 2026

Clean source `2851fef375051167f25b276358af8b33f705bb57`, local Android 76,
installed Android templates, `source_dirty=false`. APK SHA256:
`d7fd285189bf1fb9f2c82a0a90555000de5ec49c33d519655e8fdc72323dd2fe`.
Manifest: `build/download/pebble-and-granite-76-android.json`.
Installed golden/JNI self-test passed; actual solo UI probe passed all menu/call/
zoom/board/opponent-fast/next-approval checks and confirmed unchanged normal saves.
Two-delivery journal verified on desktop: `1fbba44ef7e65df2`.
Evidence: `build/probes/solo-ui-6c9f768a6ada42948892cf3ca9f03e0b/`;
logs `build/team-rules-android-runtime.log` and
`build/team-rules-android-solo-repeat.log`. One preceding UI run reached the final
approval but its verifier hit a concurrently edited local compile; its exported
journal was verified separately, then the complete probe was rerun successfully.
No installed no-tick collision fixture was driven: both remedies, pending restore,
AI choice and moving-clock rematch have desktop native/core coverage. Existing
direct-touch evidence above remains tied to build 75. New drill work follows this
APK and requires its own installed validation.

## Takeout/timing installed checkpoint

Clean source `af72dfbd758d39ddd962d3702570269c7c804c4b`, local Android 77,
installed templates, `source_dirty=false`, APK SHA256:
`dd9ffc905f48bc02b99549a140dea1d0c07de04f1604a1e5c76f10ed1301d879`.
Golden/JNI runtime check passed. Actual menu selections and touchscreen delivery
strokes produced a 3-star takeout (target removed, shooter retained in the house)
and a measured 6.191 s hog split, correctly graded zero for a 14 s goal. Next
advanced to another takeout target and a 15 s timing goal. Cross-core practice
replay hashes: takeout `73d41544dbdbd424`, timing `bbf9a4c9551bc8fc`.
Normal saves/preferences/notes were unchanged. Evidence:
`build/probes/drills-ui-4be51f6fdead479a89a81701b7614d81/`, log
`build/expanded-drills-android-ui-third.log`. Two preceding fixture runs were too
light to cross both hog lines: the small first forward nudge consumed the native
120 ms drive window during adb command latency. The driver now sends one clear
forward push. Gameplay/input mapping did not change. The early takeout screenshot
preceded the next rendered UI frame; a presentation wait was added to future
captures. The report/state/journal all contain the validated 3-star grade.
The new steady-camera setting follows this APK and has separate native evidence.

## Steady-camera and combined installed checkpoint

Clean source `da21863bc73bb19d2d32af4dd63425fbc58565ca`, local Android 78,
installed templates, `source_dirty=false`. APK SHA256:
`a065c136a42e0f1264491ea8d4454f3f7ee77e9783a9292d9503b8bfc4bb75b5`.
Golden/JNI runtime and both actual installed UI probes passed. Solo selected
Calling only/Elite/fast watching, sent a guard, zoomed, issued HARD/OFF, toggled
steady overhead through Settings during travel, paused/resumed with the ice
board, watched the opponent fast, and reached the next Gold call. Its accepted
match journal replayed exactly at `c61a8247754e7170`.

Actual touch drills produced another three-star retained takeout (journal
`028998ff45180508`) and a 5.858 s split, correctly zero stars against 14 s
(journal `707d7720028365df`). Both practice journals replayed exactly. Normal
practice/match/solo/drill saves, preferences and ice-note sidecars stayed unchanged.
The corrected capture wait shows the rendered three-star result, not the prior
settlement frame. Steady overhead and takeout/timing screenshots were inspected.

Evidence: `build/probes/solo-ui-53e00f6fa7824538abb06fcae6665498/` and
`build/probes/drills-ui-3499e4de058040148f2d688e5e00e654/`; logs
`build/steady-camera-android-{runtime,solo,drills}.log`. The dedicated hidden
emulator was stopped after testing. Physical-device feel, latency/thermal behavior,
audible quality and real-ice coefficients remain unverified.


## Skip polish installed checkpoint — 27 October 2026

Clean source `0985aa0bd0c9d92c129f4a736cbf2e876a47cb77`, local Android 79,
installed templates, SHA256
`cd5493cb725080719e22e5b7881ca9b9dfc34fa63d1b8085837f589c3587521a`.
Dedicated `pebble_granite_lab` emulator-5580 passed the actual-touch solo and
both takeout/timing drill probes. Solo now verifies in/out-turn without moving
the broom, a real drag that changes the line, absence of target rings, retained
House view, HARD/OFF, Settings and ice-board pauses, and opponent fast travel.
The accepted journals replayed and normal player saves/preferences stayed intact.
Evidence: `build/probes/solo-ui-a8f05d70a16a4e69a8a73eb7ac8f989c/` and
`build/probes/drills-ui-a3d11a6125f24ba18bd68e129f581786/`.
The later scrolling Settings/shot-review pacing work is not in this APK.
A separate desktop full-match check completed 112 deliveries through an extra
end and passed journal reconstruction/rematch. Physical feel and audible mix
remain unvalidated on real devices.

## Play-feedback installed checkpoint — 27 October 2026

Clean source `9107e031269da46bb33fed72eb5ce5e365ed4370`, local Android 80,
installed templates, SHA256
`e3f1e02d57f2fcfa7f3d8ec0586d352deff4c35b2d023164ea29e9ca88a16575`.
The dedicated emulator passed actual-touch solo and takeout/timing drills again.
This build includes scrolling Settings, volume, Gold-shot review/Continue, saved
caller setup, clearer finish reports, sweep cues and the live local split clock.
The solo probe continued from Gold review and reached the next manual call with
its previous weight/turn/broom retained. Both journals rebuilt exactly, and
normal saves/preferences stayed unchanged. Installed captures of the manual
caller, ghost reference and accelerated stopwatch were inspected.

Evidence: `build/probes/solo-ui-f39b10c5a181451b9644c44676c7919f/` and
`build/probes/drills-ui-ccc8c0045e7f4e2a8515bb7694ea1180/`; logs
`build/polish-android-80-{solo,drills}.log`. A later wording correction changes
“4× replay” to “4× travel” in the stopwatch; no timing behavior changed.

The Android 80 full direct-touch probe also passed: both finishing curls,
spatial scrubbing, stopped heat after lift, accessible steady sweeping,
background/regrip recovery and exactly-once hog faults. Restart now waits for a
settled journal and confirms replacement; clean first launches are supported.
Evidence: `build/probes/touch-010609c4b4824c9fa4038d961590f678/` and
`build/polish-android-80-touch.log`. The wrapper restored the original practice
save and backup byte for byte and removed its temporary file. The installed
hold-sweep/stopwatch capture was inspected. Physical-device and audible-mix
validation remain open.

The Settings swipe check exposed a mobile-only issue in Android 80: the
free-positioned content swallowed drag events. Android 81 fixes propagation and
makes toggle changes occur on release so a scroll does not toggle them. Clean
source `89a9e326dcaa7cdb60c06b7f79be47674761df52`, APK SHA256
`590ace82bf7a317b80ad7e10637f6a13ff7f537b54959cbbcd588311cbb2a536`.
Actual Android swipes reached the lower settings; taps set Ice volume to 35%,
muted/unmuted, and Escape closed/reopened the panel. Captures were inspected and
normal saves/preferences stayed unchanged. Evidence:
`build/evidence/android-80-settings-9621afecebb24de2aaee5f6c7b4ab789/`
(the probe directory retains its previous build prefix), and
`build/polish-android-81-settings-final.log`. The desktop pan event check passes
with the graphical display; headless checks retain the keyboard-scroll test.
