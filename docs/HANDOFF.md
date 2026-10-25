# Pebble & Granite development log

## Current state

Foundation work started 25 October 2026. Original repository contained the design
bible only. Remote: `maccam912/pebble_and_granite`, main branch.

## Work order

- [x] Deterministic arithmetic/physics/ice and versioned replay contracts.
- [x] Godot mouse/trackpad/touch practice with resumable saves.
- [x] Local mixed doubles through complete games/rematches, with command-journal saves.
- [x] Rules/authority/seat ownership and four-peer Iroh lobby transport proof.
- [x] CI cross-platform core tests, native exports and published numbered releases.
- [ ] Online gameplay replication, replay transfer and room UI.
- [x] Installed Android golden/JNI probe using the one-use debug request route.
- [ ] 3D delivery/cameras, spatial scrubbing, measured calibration/performance and AI.

Latest local gates: 66 core Rust tests (plus native transport identity test), shared golden traces, Godot input/practice/match
save/full-game fixtures. Live network probes are separate from offline CI because
relay and code-directory availability are external dependencies. Four peers have
passed a full shot and in-flight reconnect with default and forced-relay transport, but the
playable scene is still local-only. The code-directory test revoked its own entry.

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

## Iroh transport and Android bridge

- Development Build 7 (1373b4a) passed every job and published all four platforms.
- Build 8 compiled all platforms; exported Linux/macOS golden checks passed.
  Windows produced identical simulation hashes but failed the in-app text comparison
  because checkout converted the fixture to CRLF. Added repository LF attributes.
- Imported the bounded racinggame Iroh adapter with project-specific ALPN and JNI
  identity, retaining upstream MIT license. Renamed connect methods that shadowed
  Godot Object.connect. Both native libraries build together.
- Local macOS direct/default and forced-relay tests passed four bidirectional packet
  channels, connect cancellation, and forced disconnect. Offline lab and session
  tests still pass; all 44 Rust tests and six golden fixtures pass.
- Added PebbleMobile Java plugin (compiled locally against Godot 4.7), Gradle export,
  manifest/DEX structural checks and native Android C compiler configuration. New
  cross-platform packaging must be checked in CI; Android runtime JNI remains open.
- Online rooms/seat binding/gameplay are not yet wired. The lab remains offline.
- Usage checkpoint: 10% used / 90% remaining. Work continues under requested cap.

## Android installed-app smoke evidence

- Verified Release 6 APK SHA256, installed it on emulator-5580, and launched its
  resolved Godot activity. Dismissed Android's fullscreen tutorial, inspected the
  landscape UI, toggled one-push through touch, and injected a touch stroke that
  released a stone. Screenshots: ignored build/evidence/android-release6*.png.
  This is emulator evidence for the older Release 6, not physical-device or new JNI
  validation. The emulator stays available for the next packaged self-test.
- d3f6b0b pushed the transport milestone; Actions run 40242472985 is in progress.
- Packaged self-test now also checks CurlTransport.available(), which on Android
  requires the registered Java singleton and successful native JNI initialization.
  Network connectivity still has its separate live transport probe.

## Mixed doubles lifecycle foundation

- Rules2026.pdf became accessible; inspected R17 and the power-play diagram.
  Detailed implementation scope and remaining audit live in docs/RULES.md.
- Added explicit placement phase, independent placement-choice owner, positioned
  stones, per-team one-use power plays, per-end throwing order, and correct blank
  end choice handling. Added rules schema 1 to compatibility metadata/checks.
- Authority transitions clear the field while retaining physical ice history and
  advancing a 60-second inter-end interval. Sheet-direction reversal remains open.
- New tests cover invalid/atomic placement, all guard positions and mirrored power
  plays, use/extra-end restrictions, throwing order, blank distinctions and a full
  ten-delivery end through next-end setup. These do not yet expose full matches in UI.

## Room ownership and recovery contract

- 8ab077c pushed the mixed-doubles lifecycle. Added room authority core next:
  fixed authenticated seats, compatibility gate, four-player readiness, host-only
  start/end/rematch, strict bounded command envelopes, replay-resistant sequence
  window that still admits reordered sweep packets, and rematch epochs.
- Disconnects reserve active-game seats and pause simulation/clocks. Rejoining the
  same identity must confirm full simulation/rules/pending-input hash before play
  resumes. No host migration. Actual replay transfer/identity persistence/UI remain.
- Six room tests pass, including hostile envelope fields, identity/role spoofing,
  reordered sweep acceptance, reconnect pause/hash/sequence behavior and stale
  rematch rejection. Clippy passes. The UI still exposes only practice.
- Transport pipeline d3f6b0b: Linux package succeeded; Windows/macOS/Android still
  building at this checkpoint. Later queued runs may supersede pending revisions.

## Playable local mixed doubles

- Connected Authority to the native CurlSession presentation/input boundary, keeping
  all physics, turn ownership, scoring, placement and remedies in Rust.
- Added a local pass-and-play mode with positioned-stone choices, power-play side,
  per-team first/last thrower, score/end/role display, thinking clocks, next end and
  rematch. Practice remains independently saved. Local match persistence is pending
  and the UI explicitly says it is not saved yet; no online-room claim.
- Godot match_flow runs a complete end, power-play setup, complete game and rematch.
  Passed headless; native-window setup captured and inspected. Existing pointer/touch
  routes and practice restore tests also passed. New full-game gate added to CI.
- Fixed presentation handling when a rules remedy removes the delivered stone.
- d3f6b0b transport packages passed Linux/Windows/Android; macOS still building.
  Android artifact download to build/run9-android started for installed-app proof.

- Thinking time now advances idle ice cooling with an integer fractional-tick
  remainder; one 1001 ms update and 1001 one-ms updates produce identical state.
  Full core gate: 57 tests plus unchanged golden traces pass. Full Godot match,
  input routes and practice restore pass; bridge/core clippy passes.
- Usage checkpoint: 14% used / 86% remaining.

## Verified match journals and autosave

- Added match schema 1 command journals: placement, role choices, releases, compact
  sweep/step spans, thinking time, late sweep inputs, rules choices and end changes.
  Restore validates bounds/versions, replays the authority, and verifies full state
  including release snapshot/pending sweeps/clocks. It never trusts a serialized Sim.
- Local matches autosave separately from practice, using atomic temp/backup handling.
  Entering Mixed doubles resumes its save. New match replaces it explicitly. Disk
  tests cover interrupted continuation, backup recovery, invalid-load atomicity and
  keeping practice unchanged. CLI now supports verify-match FILE.
- Constant-sweep journal compression and full-end/next-placement replay tests pass.
  Parsing has a total replay-tick budget. Replay is currently synchronous, and live
  step batches clone authority for transactional failure handling; seek checkpoints
  and measured low-end Android performance remain open.
- Development Build 9 (d3f6b0b) published all four platforms successfully. Its actual
  Android APK installed on emulator-5580, but the original self-test intent approach
  did not run: 4.7 launcher dropped extras and direct game activity is unexported.
  Added a one-use request in the debug app's own sandbox; source route passes.
  Requires a newly built APK before claiming Android golden/JNI runtime success.

## Live lobby and short-code integration proof

- Added CurlRoom native bridge and a bounded typed lobby/control codec. Iroh's
  authenticated connection metadata determines identity; Hello cannot claim a seat.
- CurlOnline handles deadlines, readiness/start, state coalescing, per-peer queue
  limits and disconnect pause. Native signal callbacks defer close/state work until
  poll returns, avoiding reentrant GDExtension borrows.
- Four real Iroh peers passed ready/start, disconnect reservation/pause and host-loss
  cleanup. Default and forced-relay routing passed. Readiness burst coverage checks
  that repeated updates coalesce rather than exhaust the host's queue.
- CurlRendezvous uses the same user-owned four-character directory as racinggame,
  with Pebble-specific compatibility/golden identity. Register/resolve/revoke passed;
  no persistent test room or token was left behind. Tokens are kept in memory.
- ad4f4f9 local-match pipeline passed all jobs and published. The 011bab9 journal /
  Android probe revision is next in CI. Online gameplay and UI remain unimplemented.

## Persistent reconnect identity

- Online clients now retain a native Iroh signing key in their own user-data folder.
  New files are owner-only on Unix, synchronized to disk before use, and never
  overwritten on malformed/read failure. No private key appears in lobby packets.
- Native persistence/corruption/permissions test and transport clippy pass.
- Four-peer forced-relay test reconnected a player under a new connection ID into
  the reserved seat. The game correctly stayed paused pending replay verification.
- First default-route lobby attempt timed out before handshake; relay route and
  subsequent default-route lobby/reconnect and four-channel transport probes passed.
  External discovery/relay availability remains a dependency, not an offline CI gate.
- Usage checkpoint: 17% used / 83% remaining. Work continues toward the requested cap.

## Shared host/client command replication

- Protocol 2 adds ordered, hash-checked host commits and bounded journal-transfer
  primitives. Rooms now use RecordedMatch, preserving the same authoritative
  decisions and save/replay rules as local play; concession is journaled too.
- Host updates stop at the exact settled tick. Replicas reproduce a complete shot
  and late sweeps before/after an in-flight restore with identical full hashes.
  Duplicate/gapped/old-epoch/corrupt updates leave visible replica state unchanged.
- Native CurlRoom/CurlReplica/CurlSnapshot bridge and offline Godot fixture pass;
  the fixture is now included in desktop export CI. Core suite: 66 tests + goldens.
- The live lobby still needs gameplay channel routing, transfer deadlines,
  synchronized-start/reconnect acknowledgement, frame presentation and room UI.
- Snapshot reconstruction is synchronous; copy/trial cost and long-match latency
  remain profiling work. Do not claim finished online gameplay from these probes.
- Before full online games, compress sampled sweep histories: the current 20,000
  record / 16 MiB journal limits can be reached by long high-frequency network
  sweeping. Local held-brush Step spans already compact; individual network Sweep
  records do not. This is a required replication capacity gate, not polish.

## Live authoritative gameplay and Android runtime gate

- Protocol 3 routes control on reliable channel 0, commands/commits on channel 1,
  and bounded reconnect journals on channel 2. Start/reconnect pauses until every
  client acknowledges the exact epoch, revision and full hash. Transfers have
  60-second deadlines and per-peer send limits; disconnected peers cannot leave
  queued packets that tear down the host's room.
- Four real Iroh endpoints passed placement, release, a complete simulated shot,
  in-flight seat recovery and identical final hashes under default and forced
  relay routing. The latest default-route fixture also sends a late sweep.
  Client command sequence floors survive reconnect via the authenticated roster.
- The live network module is still not exposed in the game scene. Room UI,
  presentation frames, input routing and complete-match network testing are next.
- Build 14 (`011bab9`) published on all platforms. Installed its 97 MiB ARM64 APK
  on the dedicated Android 35 emulator. All six golden traces matched, and the
  JNI networking plugin reported ready. APK SHA-256:
  `bc931cc36f720404b7c7917110bd88037aaca429f268645311799abdb584219b`.
  Evidence: `build/evidence/android-self-test.json` (local, ignored).
- Fixed probe stdin delivery: `adb exec-out` does not forward the request body;
  `exec-in` with an exact-byte-count write works. The one-use request is consumed
  before the native test and cannot trigger on subsequent ordinary launches.
- Android evidence covers simulation/JNI initialization on an emulator. Actual
  cross-device Iroh play, physical touch feel and store signing remain unverified.
- Usage checkpoint: 18% used / 82% remaining.
