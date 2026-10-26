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
- [x] Online replication, replay transfer, room UI and initial playable controls.
- [x] Full online room/match/rematch flow on four local Iroh endpoints.
- [x] Installed Android ↔ macOS short-shot/reconnect probes, default and forced relay.
- [ ] Physical-device tests, Android full-match latency profiling and input refinement.
- [x] Installed Android golden/JNI probe using the one-use debug request route.
- [x] Direct-on-ice 3D delivery/cameras, finishing flick, and local held saves.
- [ ] Spatial scrubbing, measured calibration/performance and AI.

Latest local gates: 100 core Rust tests (plus native transport identity test), shared golden traces, Godot input/practice/match
save/full-game fixtures. Live network probes are separate from offline CI because
relay and code-directory availability are external dependencies. Four peers have
passed a full shot and in-flight reconnect with default and forced-relay transport, but the
playable scene now includes experimental online rooms. The code-directory test revoked its own entry.

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
- Resolved in the journal-format-2 milestone below: the original 20,000
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

## Compact bounded match journals

- Match format 2 seals 256 validated input records per compressed block; an active
  tail retains the existing step/think run compaction. State copies share immutable
  sealed blocks instead of copying the entire match history. Saves remain bounded
  to 16 MiB, 2 million records and 4 million simulated flight ticks.
- Legacy format-1 saves still load and verify through replay, then save as format 2.
  Protocol 4 isolates new reconnect journals from older room builds. Model 2 and
  all golden physics traces are unchanged.
- A storage-capacity fixture representing 80 thirty-second throws, two independently
  varying brush streams sampled at 60 Hz and intervening steps produced 432,001
  records in 5,421,862 bytes. This is a codec workload, not a whole-game physics or
  network latency benchmark. Actual recorded sweeps and compressed reconnect chunks
  also restore to identical hashes, including late-input history.
- Decompression is capped at 128 KiB per block; malformed encoding, oversized
  expansion and invalid counts reject the save. Native match restore/replica checks,
  69 core tests, golden traces and clippy pass.
- Synchronous reconstruction and live simulation-copy costs still need Android
  profiling. Input sampling/continuous brush-span semantics must be finalized when
  the online input route is wired; the capacity fixture does not approve feel.

## Playable online room and match interface

- Added Host/Join by four-character code, team/player roster, Ready/Start,
  reconnect, code expiry/renewal and Leave. Late registration after cancellation
  revokes its own code; explicit Leave revokes the current code. Closing the app
  relies on the service's ten-minute TTL. Tokens are not persisted.
- Online matches reuse the local renderer and integer stroke mapper through a
  shared native presentation boundary. Controls follow authenticated seats;
  placement, first/last throwers, deliveries, next ends and host-offered rematches
  route to the authority. Online state never overwrites local practice/match saves.
- Protocol 5 adds 1–12-tick brush spans so a 20-Hz hold stream applies effort on
  every 240-Hz simulation tick. Late spans resimulate once, overlapping spans reject
  atomically, and defending spans begin at authorized receipt time after the tee.
  UI assigns the delivering teammate as the single sweeper; the defending skip
  may sweep behind the tee. Spatial scrubbing remains future work.
- Native UI test covers room validation, seat-owned setup, stroke delivery,
  shot completion, wrong-seat input rejection and rematch readiness. Added to CI.
  Live four-peer test includes brush-span replication and in-flight restore.
  Existing input and local end-flow tests pass; 71 core tests and goldens pass.
- Captured and visually inspected `build/evidence/online-room.png`; corrected
  overlapping roster text and made the modal opaque. The host simulation continues
  while its room panel is shown. Old-epoch commits arriving across channels after
  a rematch snapshot are ignored instead of breaking the new replica.
- Still required: full room-UI-to-network match test, cross-device Android play,
  late-span/resimulation profiling, rendering interpolation, explicit host-stall
  UX and refinements for Android background/resume. This is an early online slice,
  not a claim of production-ready multiplayer or approved curling feel.

## Rewind performance and full live match validation

- Added `tests/online_room_flow.gd`: actual room-code registration/resolution,
  three UI joins, readiness, placement and continuous teammate sweeping. It
  revokes its code and removes only its own test identities. One initial join
  attempt timed out; subsequent complete flows passed, so external discovery
  reliability remains a monitored dependency rather than a claimed solved issue.
- The initial four-view debug flow took 171.279 s for 25.404 s of simulation.
  A pure release-core probe measured 5,355.890 ms for 520 late brush spans.
- Added up to four immutable rewind checkpoints covering the 24-tick late window,
  invalidated after changed input. Release snapshots and cache entries share Arc
  ownership across copies. The cache is derived, excluded from saves/hashes, and
  checked against full-release replay across all accepted late offsets.
- The identical release-core probe now takes 83.673 ms, worst span 0.146 ms, with
  unchanged authority hash `0f60680c408b6903`. See `docs/PERFORMANCE.md` for scope.
  This is a measured workload improvement, not an FPS multiplier claim.
- Four-view release-native room flow ran in real time: 25.446 s wall / 25.404 s
  simulated, maximum observed process-frame gap 8.470 ms. The accelerated follow-on
  test completed nine ends, 4:4 after eight and 5:4 after nine, then synchronized
  all four players into epoch-2 rematch readiness. No gameplay requests rejected.
- Native developer builds now default to release optimization; `--debug` remains
  available for debugging but is unsuitable for gameplay timing. New protocol 6
  rejects brush timestamps from before the current delivery so stale packets cannot
  retime into a later end reusing the same stone ID. Normal post-settlement brush
  arrivals consume their sequence without showing a spurious user-facing error.
- Core suite now has 73 passing tests plus one opt-in timing probe. Full golden
  traces remain model 2. Cross-device Android performance, forced-relay full-match
  latency, host-stall UX and asynchronous long-journal reconstruction remain open.

## Responsive network reconstruction

- Snapshot byte assembly stays bounded on the receiving thread; checksum checking,
  archive decoding and deterministic reconstruction now run in a Rust worker.
  No Godot objects cross the worker boundary. Only a verified final authority is
  installed by main-thread polling, after which the client acknowledges its hash.
- The room displays receive/replay progress and remains usable while rebuilding.
  Leaving cancels between bounded records/blocks without waiting on a thread join.
  A process-wide four-worker cap includes cancelled jobs until they finish. The
  existing total 60-second synchronization deadline remains enforced.
- Added cancellation/progress checks across compressed blocks and worker rejection
  of checksum/state-hash corruption. 75 core tests, every-tick goldens and clippy
  pass. Offline native recovery of a 300-span compressed in-flight journal yielded
  nine frames; the largest observed packet handler took 29 microseconds in one
  optimized macOS probe. This is not a long-match or Android latency guarantee.
- Forced-relay four-player placement, full-shot and in-flight reconnect pass with
  worker reconstruction. The real room-UI flow also passes all nine ends, scores
  5:4 after the extra end, and synchronizes a ready epoch-2 rematch. Its initial
  swept shot took 25.460 s wall for 25.404 s simulated in four local views.
- Local practice/match autosave reconstruction is still synchronous. Android
  long-match profiling and local-load cancellation remain follow-up work. Also
  stress cross-channel stale commits during snapshot transfer under jitter.
- Both ec86c7c and d4fc29c release pipelines passed all jobs. The 68278dd rewind
  milestone is pushed and its pipeline is still running at this checkpoint.
- Usage checkpoint: 26% used / 74% remaining; requested work continues.

## Android-to-desktop live transport

- Added a repeatable installed-APK probe with an isolated identity and a bounded,
  consumed-once development request. Android joins three desktop peers, readies,
  reconnects in flight, verifies reconstruction, and sends its own team's
  concession. The host and Android final hashes must match. No local saves or
  player identity are used. A separate-process desktop rehearsal also passed.
- Default-route Android 35 ARM64 emulator probe passed with final host/client hash
  `571ae17d15022973`. Evidence: `build/probes/8ef64ce6e89543bb8e73821b82f6a740/result.json`.
  APK SHA-256: `e966a2cc9e7da25355a11caf33116fae0f98329896f57808f83b4c6aa45d4acc`.
- The diagnostic APK was built locally from d392ab6 plus this milestone's edits;
  metadata explicitly records `source_dirty: true` and installed Android templates.
  The optional local installed-template route now feeds the same archive into the
  JNI plugin build. CI retains its pinned download/default behavior.
- The first rehearsal failures identified harness sequencing: repeated Ready packets
  outlived lobby start, and the placement sender's unpause view lagged the host.
  The harness now sends readiness once and awaits all local views before placement.
- Normal lab/input fixtures and the original one-use golden-probe route still pass.
  Physical-device touch feel, Android full-match/long-journal performance,
  background/resume and room-code UI on Android remain open.
- Rewind milestone 68278dd passed every CI job; d392ab6's pipeline is running.

- Forced-relay Android probe also passed with the same exact hash; evidence:
  `build/probes/92eacfacdbc54c5a9063bcc59c386bb6/result.json`. The same installed APK
  passed all six golden traces and JNI readiness again; latest evidence is
  `build/evidence/android-self-test.json`.
- Usage checkpoint: 28% used / 72% remaining. Continue toward the requested cutoff.
- Next priorities: develop the bible's 3D delivery/camera/brush feel slice atop
  these verified input/authority boundaries; preserve the 2D lab for diagnostics.
  Local async loading, jitter/stall UX and long Android recovery remain tracked
  reliability work, alongside physical-device and curler evaluation.

## Shared 3D rink and camera slice

- Added a presentation-only `CurlRinkView` used by the default practice scene and
  online game. It renders the shared authoritative frame into a separate viewport:
  three-sheet club geometry, exact house/hog/back/tee markings, stable stone IDs,
  rotating team handles, broom and an accessible held-brush animation.
- Auto, Delivery, Sweeper, Skip and orthographic House cameras are available.
  Projected broom dragging in House view changes the existing integer aim input.
  Camera buttons cannot accidentally begin sweeping. The original 2D lab remains
  available; both views retain the same mouse/held-trackpad/touch delivery mapper.
- Position smoothing is presentation-only. Reset/end changes remove stale meshes;
  rendering/camera cycling cannot change the authoritative hash. New offline tests
  cover projection round-trip, aim, delivery, camera-input isolation and reset,
  and join the desktop CI gates. Existing input and online-UI checks pass.
- Captured and inspected delivery/sweeper/skip/house frames under Compatibility
  rendering. Adjusted lighting and removed overhead roof obstruction. Images are
  under `build/evidence/rink-*.png`. This is procedural prototype art, not final art.
- The right-side delivery card remains for now. The bible's body/slide model,
  direct 3D hand interaction, hog-release timing and spatial brush input are still
  required; no physical feel or Android GPU performance claim is made here.
- d392ab6 asynchronous reconstruction passed all CI jobs. caa6ae1 Android-probe
  pipeline remains in progress. Weekly checkpoint remains 72% available.

- The live four-room flow passed after the router restart with 3D scene integration:
  nine ends, 5:4 final score, and synchronized rematch readiness. The initial swept
  shot took 25.450 s wall / 25.404 s simulation in four headless views; this is a
  networking/scene regression check, not a rendering benchmark.
- Reused stone IDs refresh team colors and snap on end changes. Camera switching
  is blocked during a held pointer gesture, so a second touch cannot redirect aim.

- Installed the 7bbb9fa local Android build and visually inspected the actual
  Compatibility renderer on Android 35 ARM64. Camera taps, overhead broom drag
  across the tee, and a one-push touch release all worked; the automatic follow
  camera tracked the travelling stone. Evidence: `build/evidence/rink-android*.png`.
  This is an emulator render/input check, not a physical-device or FPS benchmark.
  APK SHA-256: `9a3f3c3ec0f41d064c5a24bdff71703f312d23c6a141ae94538ae02c86d2c5d9`;
  package metadata records clean 7bbb9fa sources and installed Android templates.
- Added `docs/PRESENTATION.md` with the coordinate/render-input boundary and the
  still-missing delivery mechanics. Weekly checkpoint: 30% used / 70% remaining.

## Deterministic slide foundation (integration pending)

- Added `curl-input::delivery`: integer 240 Hz slide poses, position-dependent
  release speed, tee crossing, near-hog warning, and explicit late-release result.
  Read-only camera/render queries do not alter the underlying stroke or outcome.
  A stationary hand continues the provisional slide without injecting render-time
  samples into weight. Long holds remain hog faults, not cancelled retries.
- Six new tests cover release timing/position, exact hog boundary, 30/60/144 Hz pose
  queries, cancellation/invalid input and immutable completion. 81 core tests and
  all existing model-2 goldens pass; clippy and the 3D regression test pass.
- This module is intentionally not wired to the playable scene yet. The next
  implementation must connect a journaled seat-owned fault, expanded release
  geometry, native/network mapping and 3D hand/body interaction together. See
  `docs/DELIVERY_MODEL.md` for the exact pending contract and compatibility work.
- Rechecked the local September 2026 rulebook. Corrected visual hog stripes to
  102 mm with the specified inside edges, and tee/back/centre lines to 13 mm.
- caa6ae1 and 7bbb9fa pipelines passed all jobs. 945e780 is still running.

## Model 3 delivery authority checkpoint

- Added a seat-owned HogViolation command and replay record. It consumes exactly
  one delivery, leaves existing stones/ice/fatigue intact, and runs normal turn/end
  scoring. Inactive consumed IDs prevent reuse in practice.
- Added atomic wrong-seat/in-flight rejection, ten-fault end scoring, replica
  commit/reconnect, practice replay and native save-restore coverage.
- Release centres now accept -37.8 m through strictly before -28.593 m; default
  diagnostic draw moved 244 mm toward the hack. Model 3, rules 2, protocol 7 and
  practice schema 2 reject older development logs instead of interpreting them
  under changed physics. Existing rejected-save preservation remains in place.
- Golden traces intentionally regenerated for model 3. Previous performance and
  Android/network evidence above was measured on model 2 and is historical.
- Still pending: wire Delivery into the gesture, variable-origin native/online
  release, visible body/hand travel and warning, thinking-clock tee cutoff,
  background semantics, and updated installed Android validation. The current
  playable gesture still uses its fixed diagnostic origin; no claim that the
  body-slide controls are enabled yet.

Validation for this checkpoint: 84 core tests, six every-tick golden traces,
workspace clippy, and nine Godot gates including complete local match, 3D view,
async replica restore and practice hog-fault save roundtrip passed. The model-3
late-brush probe simulated 26.012 seconds in 91.152 ms, worst span 0.323 ms on the
local macOS machine (headless core workload, not a device/render benchmark).
Weekly usage at this checkpoint: 68% remaining; continue substantive work.

## Playable delivery-slide integration

- Replaced the playable native stroke with the deterministic Delivery model;
  lift reports actual micrometre position/speed and an explicit hog-fault outcome.
  Local deliver_slide and online slide_packet share a validated integer factory.
  Diagnostic fixed-origin APIs remain available for controlled physics fixtures.
- Local and online card controls submit those variable-origin releases. Holding
  through the line consumes a delivery automatically, including replica state.
  The 3D preview and Delivery camera follow the slide, starting ahead of the hack.
  Input mapping metadata is now version 2.
- Added delivery_slide Godot gate to CI: early/late timing, native/packet origin
  equality, invalid boundary rejection, visible slide pose, automatic fault and
  exactly-once handling. Core 84 tests, goldens, clippy and all ten native/Godot
  gates passed. Rendered hack/slide screenshots were inspected on macOS.
- Updated the live room-flow probe to use the real gesture for its first release
  and a held-pointer hog fault on the next turn before completing the match.
- Next critical foundation: synchronize the in-hand lifecycle so thinking time
  stops at delivery-tee crossing and suspend/disconnect cannot silently cancel an
  in-play stone. Direct 3D hand/body interaction, Android validation of this new
  path, and device/curler calibration remain open. These are not covered by the
  older model-2 Android evidence.

Live validation completed: four local Iroh peers accepted the slide gesture and
held hog fault, finished nine ends (5:4), and synchronized rematch. The first
continuously swept slide shot took 27.037 s wall / 27.046 s simulated; observed
maximum headless frame gap 10.151 ms. This is not Android/GPU performance evidence.
Weekly remaining usage: 67%; continue development.

## Direct-on-ice delivery correction

User clarified the intended interaction: curler's perspective from the hack,
pull back directly on the stone, push forward, hold while sliding, then flick left
or right for curl with a small forward/back finish for weight trim. Prioritize
this over the separate gesture card.

- Default local and online scenes now use a full-width ice viewport and projected
  3D handle picking. Removed the gesture card and turn-toggle control from that
  view. Added a simple glove/forearm and pullback motion; house aiming returns
  automatically to the delivery camera.
- Recent 120 ms finishing motion selects left/right rotation; no flick means
  neutral rotation. Forward/back finish trims speed by at most ±70 mm/s. Curl
  flick does not also deflect the broom aim. Coarse weight feedback appears over
  the ice, with a release-now warning near the hog line.
- Added matching direct mouse and touch gestures, both curl directions, weight
  trim and on-screen handle tests. Rendered full-width slide was inspected.
- Authority groundwork in curl-match/delivery.rs now journals an in-hand plan,
  stops thinking time at the tee, rejects cancellation after that point, and
  consumes held stones at the hog deadline. Four new core tests cover boundaries,
  replay, chunking and expiry. Early free-release clocks also run until the tee.
- IMPORTANT NEXT: route the actual UI through this authority plan,
  persist/recover held practice
  deliveries, and restore/regrip after focus loss or reconnect. Those lifecycle
  commands are not yet used by the new direct-on-ice gesture. Physical feel and
  installed Android validation of the revised gesture remain open.

Validation for this checkpoint: 89 core tests, six deterministic traces, workspace
clippy and ten Godot gates passed against the final rebuilt native library. Direct
mouse/trackpad and touch gestures matched; both flick directions and forward trim
passed. A rendered slide was inspected. Four live peers completed the revised
first delivery, automatic hog fault, nine ends (4:5) and rematch. First-shot timing
was 27.337 s wall / 27.308 s simulated, max headless frame gap 10.181 ms; this is
not physical Android performance evidence. Weekly remaining usage: 64%.

## Installed direct-on-ice Android validation

Clean `eecf858` was built and installed on Android 35 ARM64. All six golden
traces/JNI checks passed. Actual touchscreen MOVE/UP sequences verified direct
handle grip, pull/push/held slide, both curl directions, and exactly one hog fault
when held too long. Existing emulator practice files were preserved before tests.
Added tools/android_touch_probe.py for repeatable, explicitly selected emulator
runs; see docs/ANDROID_INPUT.md for APK provenance, evidence and layout constraints.
This does not establish physical-device feel or Android frame-time performance.

The same APK also passed Android↔macOS forced-relay shot/in-flight reconnect;
final hashes matched at 1f145c13ee8ae46b. Result is under
build/probes/9f0c034758d3408e8a520e876afb5b3a/. The first runner invocation was
stopped before host launch because it attempted an unnecessary editor download;
the successful run explicitly used GODOT_BIN for the installed editor.

## Local held-delivery persistence

- Practice and local matches now begin an explicit held delivery, advance it with
  accepted elapsed time, and release from its actual position. Local-match
  thinking time stops at the delivery tee; practice journals coalesce idle time.
- Pause/focus loss/orderly close preserve the held state. Restore waits for a
  regrip at the same 3D handle position; no second push or free return to the hack
  is allowed after tee crossing. Regrip preserves weight/aim and accepts a fresh
  curl/weight finishing gesture. The Return to hack button is available pre-tee.
- Practice schema 3 stores pending state and upgrades model-3 schema-2 saves in
  memory. Malformed pending states and conflicts with in-flight stones fail
  atomically. Added quiet-drive closure so late finishing motion cannot alter the
  initial measured weight. Input mapping is 4, Delivery mapping is 3.
- Added held_resume Godot CI gate for practice/local-match pause, save, restore,
  in-play cancellation rejection, regrip, final flick and stopped thinking clock.
- NEXT: online_game explicitly keeps authoritative_delivery=false until its host
  accepted BeginDelivery/ReleaseDelivery commands, replicated held pose, pending
  release acknowledgement and reconnect/regrip behavior are connected. The local
  native API and existing authority records are ready for that integration.
- Installed Android evidence above is for eecf858, before these lifecycle changes;
  repeat installed pause/resume and cross-device probes after integration.

Validation: 92 core tests, six unchanged model-3 every-tick traces, workspace
clippy and all eleven Godot gates passed against the rebuilt native library.
Weekly usage remaining: 59%.

## Online held delivery and interruption recovery

- Online gesture now sends BeginDelivery at accepted push weight and ReleaseDelivery
  at the finishing flick. Consecutive reliable requests support lifting before the
  begin acknowledgement; clients never choose authoritative release position.
- Host/replicas expose held pose, tee state and hog warning. The host handles the
  thinking-clock cutoff and automatic hog fault; return to hack is pre-tee only.
- Protocol 9 adds seat-owned SuspendDelivery. Background/focus loss and opening the
  room panel freeze a held online delivery. Any room disconnect journals suspension;
  restored peers must synchronize, then the thrower explicitly regrips to resume.
  Frozen state includes ice and thinking clocks; a paused release is rejected.
- Added core interruption/journal/seat tests and expanded the online UI fixture to
  cover pause, long frozen time, regrip and a finishing flick after tee crossing.
- Existing Android APK evidence predates this integration. Repeat installed touch,
  pause/resume and forced-relay probes with a clean new build before claiming those.
- Host receipt time currently determines release position, with 20 Hz held pose
  updates and no prediction. Device/latency feel tuning remains open.

Validation for this checkpoint: 94 core tests and six unchanged model-3 traces,
workspace/all-target clippy, and eleven Godot gates passed. Four real local Iroh
peers passed held disconnect/sync/regrip, nine ends (5:4) and rematch. A second live
run verified remote lift before begin acknowledgement, then an automatic held hog
fault. First-shot wall/simulation were 27.128/27.138 s in that run, max headless
frame gap 10.176 ms; not a physical-device performance claim. Added the Android
pause/regrip probe case, pending a clean APK run. Weekly remaining usage: 58%.

## OS-cancelled contacts

An explicit InputEventScreenTouch.canceled event reproduced an unintended release
after a valid held slide. The input router now treats cancellation as interruption,
preserves the held plan and allows regrip without waiting for a focus notification.
Other fingers cannot cancel the active delivery. Local practice/match and online
fixtures cover this path; online cancellation journals suspension. Room-panel exit
shares the same interruption path. Held resume, online UI, input routing and
delivery slide gates passed. Installed Android rerun follows the clean build.

Installed clean f2444cd passed expanded Android direct touch, Home/background,
frozen held-journal resume, regrip/flick and exact-once hog checks. Evidence is in
build/probes/touch-2d6a3f3403244848948ef4f26ef90c4f/. The e5b1e33 cancellation fix
needs the subsequent installed rerun. Added the editor-generated held_resume UID
so future clean local packages do not report that test resource as untracked.

## Installed cancellation fix and held-command relay regression

Clean 5cd1808 Android build 3 passed direct touch, both curl signs, held
background/resume/regrip, exact-once hog removal and all six native golden/JNI
checks. APK and evidence provenance are in docs/ANDROID_INPUT.md. The updated
cross-device host probe now uses BeginDelivery, two seconds of accepted held time
and ReleaseDelivery; the installed Android replica passed that flow and an
in-flight forced-relay reconnect, matching desktop hash af5dbdcd7faad18c.

Next useful work: installed Android *in-hand* reconnect (current installed probe
reconnects during flight), compact weight feedback, spatial sweeping, and measured
input/performance tuning. Keep the authority/presentation boundary and compatibility
contracts intact. Physical-device feel, real-ice coefficients, publisher signing,
career/AI/content and polished art/audio remain explicitly deferred. Weekly usage
last checked at 57% remaining; continue the authorized goal until below 50%.

## Remote thrower held-reconnect probe and quieter feedback

The cross-device probe now plays two deliveries: the first reconnects during
flight; the second belongs to the fourth/remote seat. It drives the real online
scene through push, disconnects while held, checks a frozen restored pose for
350 ms, regrips the visible handle and finishes with a left flick. Only after both
shots finish does the owning team concede. The desktop forced-relay rehearsal
passed at f2992688912f3b68, evidence build/probes/eb84c2a186984980874fbbe43772f822/.
One earlier fixture run used the wrong team's concession and was corrected;
another failed before lobby setup because endpoint address discovery was not yet
available. That terminal attempt was retried; no duplicate live probe remained.

During the slide, feedback is now a small Soft/Draw/Firm label at the lower left,
widening only for the hog warning. Full instructions remain before the gesture.
Rendered view inspected; delivery slide, held resume, online UI, input routes and
rink view gates passed. Installed Android validation of the new remote-thrower
probe follows the clean package.

Installed 13a3f31 build 4 passed the two-delivery forced-relay flow on Android,
including the remote thrower's in-hand disconnect, frozen restore, visible-handle
regrip and left finishing flick. Final host/client hash d82d243a915944fa; full
provenance in docs/ANDROID_INPUT.md. f2444cd GitHub Actions completed successfully
(run 40261578313); later checkpoints are still queued/running.

Next foundational rules gap identified from the actual R8/R17 text: mixed doubles
permits either/both teammates to sweep in front of the far tee. Current authority
has one brush stream per team and UI only allows the non-thrower. Before adding
spatial scrub controls, give mixed-doubles brushes stable per-player identities,
allow both teammates, and enforce one sweeper per team behind the tee at each
actual simulation tick, including future spans and rewind. Moving own stones are
also a documented unimplemented sweep target. Current rule/sim versions must not
silently reinterpret old match journals. Weekly usage remaining: 54%.

## Mixed-doubles brush ownership and tee boundary

Rules 4 / protocol 10 give the four mixed-doubles players separate brush/fatigue
identities. Both teammates can hold to sweep; the host chooses one contributing
brush per team behind the tee at each actual simulation tick. Stable player order
resolves simultaneous behind-tee requests. Future spans and rewind use the same
rule filter. Moving own stones are accepted by the authority, though UI target
selection still follows the delivered stone. Stationary targets stop contributing
without blocking subsequent match steps. Match release preserves fatigue and
idle time recovers it; standalone practice retains its existing reset semantics.

Old rules-3 match saves remain preserved but cannot be resumed under new brush
mapping. Model-3 practice records and six single-shot goldens are unchanged. Full
team multi-brush roles, spatial target/scrub input and fatigue presentation remain
open. See docs/RULES.md for precise implemented boundaries.

The first new relay sweep test exposed retimed spans colliding with a previous
span's future tail. Span commands now replace only the same player's unconsumed
future intent; they never stack heat or rewrite already simulated duplicates.
Raw duplicate samples remain rejected. Span overlap retains already consumed
samples instead of applying them twice. A dedicated journal/replay test covers two entirely overlapping retimed
spans followed by partial future overlap. Installed validation follows rebuild.

Validation for this rules checkpoint: 100 core tests and six unchanged model-3
traces passed, plus all-target workspace clippy. Eleven Godot gates passed for the
new brush mapping; replica, online UI and full local match were rerun after the
span-overlap fix. Four live local peers swept with both teammates, completed eight
ends (4:5) and rematch. The first shot ran 25.481 s wall / 25.496 s simulated, max
headless frame gap 16.533 ms (not Android/GPU performance evidence).

The final desktop forced-relay two-reconnect probe also passed continuous sweeping
by the thrower, after two earlier runs exposed the consumed/future span overlap
cases now covered in tests. Evidence: build/probes/1b775e5277c247c198ee78ddf6a6d906/.
Installed Android rules-4 validation follows the clean build. Weekly remaining
usage at this checkpoint: 51%; prioritize final validation and handoff.
