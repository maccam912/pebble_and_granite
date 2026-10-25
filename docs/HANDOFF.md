# Pebble & Granite development log

## Current state

Foundation work started 25 October 2026. Original repository contained the design
bible only. Remote: `maccam912/pebble_and_granite`, main branch.

## Work order

- [x] Initial deterministic arithmetic/physics/ice and versioned single-shot replay contracts.
- [x] Initial Godot delivery/sweep lab with unified pointer/touch event routes.
  Native runtime checked; Android package/device checks remain pending.
- [ ] Rules boundaries and mixed-doubles turn ownership.
- [ ] Authority/input validation and multiplayer transport proof.
- [ ] CI cross-platform tests, native builds, Godot exports and numbered releases.
- [ ] Local and remote integration checks; calibration and performance reports.

## Owner follow-up / gates

- Real curlers must evaluate throw and sweeping feel; record device and ice profile.
- Collision coefficients and path wear need measurements, not invented certainty.
- Physical Android testing and publisher/store signing remain separate gates.
- Career, full team roles, polished art/audio, advanced AI and public hosting follow
  the feel slice. Missing roadmap embeds are replaced by the explicit work order.

## Usage checkpoints

- Start: weekly 4% used / 96% remaining. Continue until remaining is below 50%,
  checking at milestones. No reset or paid usage purchase is authorized.


## Milestone 1 — initial feel lab

- `61fbf53`: fixed-point core and architectural decisions pushed to main.
- 21 Rust tests pass: arithmetic, sqrt/PRNG/hash vectors, contacts, snapshots,
  sweep carry, hostile release/replay boundaries and device-neutral stroke input.
- Godot 4.7 native window and headless lab integration passed on macOS ARM64.
  Captured and inspected `build/evidence/lab.png` (ignored local artifact).
- First editor import crashed at shutdown; repeat import and runtime both passed.
  Keep watching the pinned editor rather than claiming the crash was explained.
- Unswept 2.05 m/s probe: 24.67 seconds, 0.91 m curl, 2.79 turns; sweep adds 1.34 m.
  Swept absolute curl is not yet lower, so sweep/curl calibration needs work.
- Lab currently uses overhead views, accessible hold sweeping, one stone/reset,
  and no hidden release noise. Real scrubbing, persistent ice across throws,
  full delivery body/slide model, interpolation and 3D cameras are next steps.
- Rules crate is reserved but unimplemented; server CLI verifies replays only.
  No multiplayer feature is claimed yet. Four-character Iroh rooms remain planned.
- CI and desktop/Android package configuration authored; remote result pending.
- Usage checkpoint: 5% used / 95% remaining.

## Milestone 2 — authority/rules and first remote gates

- `29cc46c` pushed the playable lab, replay checker and release workflow.
- GitHub run 40240006046: all four core jobs passed (Linux, Windows, macOS ARM64,
  macOS Intel), including every-tick canonical traces. Initial package jobs failed:
  Android setup requested removed SDK package `tools`; Linux encountered first-import
  GDExtension editor shutdown race. Fixes use explicit platform-tools and the upstream
  documented frame-delay workaround (godotengine/godot#111048), with a fresh-cache
  reproduction test. A preloaded extension cache also passed, but is not the chosen fix.
- Development Android keystore is stored outside the repo under
  `~/.local/share/pebble-and-granite/signing/` and in the repository Actions secret.
- Added 10 rules tests and 5 transport-independent authority tests. Mixed doubles
  matches/positioned stones are not yet exposed in the lab; no online product claim.
- 2026 rulebook URL returned 403. Rules currently implement the supplied bible;
  complete clause audit (including changed 2026 positioned guard locations) remains.
- Authority admits one brush stream per team in this slice, validates ownership,
  deduplicates per tick/team, allows a 100 ms late-input window, and retimes older
  samples to arrival. Opponent sweeping cannot be retroactively authorized by a
  later tee crossing. Full role-specific multi-brush play is deferred.

## Model 2 — contact sign and sweep behavior

- Added physical spin-transfer direction/energy and packed-chain separation tests.
  They caught a reversed tangential contact sign; corrected before gameplay grows.
- Increased provisional sweep curl suppression so the same release goes longer
  **and** straighter: swept x=0.824 m vs unswept x=0.910 m, +1.347 m carry.
- Simulation version is now 2; metadata lives in compatibility.json and CI checks
  it against Rust constants. Old model replays are rejected rather than reinterpreted.
- Golden traces now cover three seeded draws, sweeping, reverse turn and runback.
- Initial Android setup and editor import fixes are rerunning remotely. Windows
  executable-name and Android host-extension import fixes are in `2e4ca7f`.
- Local universal macOS bridge compiled for ARM64/x64. Full template download is
  unusually slow locally; no local packaged macOS result is claimed yet.

- Second CI run: Linux package/native Godot test passed. macOS and Android exports
  exposed the required project-wide ETC2/ASTC import setting; enabled for both.
  Windows failure was the already-fixed executable-name typo. All platforms remain
  gated together, so no partial release was published. Latest usage: 7% used / 93% remaining.

## Input route verification

- Added Godot-level mouse/held-click and touch event fixtures. Identical timestamped
  strokes produce identical release reports; extra fingers and emulated mouse-up
  events cannot steal or release the active finger. Focus loss cancels without throwing.
- Enabled touch-to-mouse emulation for native GUI buttons, while explicitly ignoring
  emulated mouse events in the stroke route. Verified accessibility button via actual
  Input.parse_input_event in both a native window and a scaled headless viewport.
- Disabled accumulated input so OS motion events reach the mapper without waiting
  for render-frame aggregation. This does not claim to undo OS pointer acceleration.


## Persistent practice / session foundation

- Added compressed tick-exact session logs with model/schema validation, bounded
  records/spans, completed-shot hashes, idle cooling time and clear-stone commands.
  Interrupted shots restore and continue identically; invalid restores are atomic.
- Native practice now retains stones/ice across shots, alternates patterned handle
  colors, and clears the field after 16 stones without re-pebbling. Fresh ice resets.
- Added autosave with previous-save backup and a disk roundtrip fixture that checks
  interrupted continuation, two throws, retained ice, corrupted-primary recovery and
  rejected malformed loads. Test saves are isolated from the player's save file.
- `curl-server verify-session FILE` verifies the whole recorded practice through the
  same core. Session replay remains synchronous; long-match seek snapshots are future work.
- CI run 40240829890 built and verified ALL FOUR packages successfully, including
  Android signing. Publish alone failed with GitHub integration permissions when
  creating a tag through the release API. Adopting racinggame's explicit tag/verify
  flow and superseded-workflow guard; no full release success claimed yet.


## First published release and packaged runtime checks

- Development Build 6 (`v0.0.6-dev`, commit `c0f4263`) published all four packages
  after all core/native integration jobs passed. The earlier publish 403 was on a
  superseded workflow revision; keep the explicit tag guard added for that case.
- Created a separate `pebble_granite_lab` Android 35 ARM64 emulator on port 5580;
  no existing AVD was modified. Release 6 APK download is in progress.
- Added a compiled-app `--self-test` route sharing six every-tick golden fixtures
  with the headless server. Desktop packages must now run their exported binary
  against these fixtures; Android has an explicit-serial install/probe tool.
- Cancelled the obsolete local universal export while its 1.2 GB template download
  was still slow. Both architecture libraries had compiled, but CI is the package
  evidence. Partial archives are ignored cache files, never release artifacts.
