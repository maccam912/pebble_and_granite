# Presentation boundary

`scenes/rink_view.gd` owns an isolated Godot viewport/world. It receives the same
frame dictionary used by the diagnostic lab and online view. It creates no physics
bodies, runs no gameplay collision queries, and never changes native authority.

Simulation `(x, y)` maps to Godot `(x, height, -y)`: the far tee is the world origin,
and positive simulation travel points toward negative world Z. Rotation is applied
only to the rendered handle. Team color is refreshed when a reused stone ID changes
team. Missing IDs remove their meshes; new ends and rewinds snap to the current
state rather than smoothing an obsolete position.

Between authoritative updates, stone positions use exponential presentation
smoothing. This introduces a small visual delay, not predicted gameplay. Camera
movement follows those rendered positions. No smoothed values enter release,
sweep, scoring, save, or replay data. Camera/presentation tests assert the native
state hash does not change.

House aiming projects a pointer ray onto the ice plane, clamps horizontal target
to the existing ±2.2 m aim range, and passes integer millimeters through the normal
delivery route. Camera changes are blocked during an active pointer gesture;
camera/view buttons cannot start a sweep. Mouse, held-click trackpad and touch
still share the timestamped stroke mapper.

The main scene now uses the full-width 3D ice view. Delivery starts by gripping
the projected handle from the curler's viewpoint behind the hack. Pull/push input
moves the in-hand preview; the camera follows the deterministic slide. A simple
glove/forearm is presentation only. The separate delivery card and turn toggle are
absent from this view; the diagnostic 2D lab remains a separate test scene.

Before sliding, sideways hand movement moves the held stone and the push slope
sets the launch line. During the slide, a small left/right finish sets rotation
and a small forward/back finish trims speed. Quiet-hand release is neutral rotation. Coarse Soft/Draw/Firm
feedback and the current Curl left / Curl right / No curl state appear in a
compact lower-left label during the slide, including the hog warning. Full delivery instructions appear before gripping. Procedural art, gain thresholds,
rotation magnitude, hand animation and feedback need curler/device iteration.
Spatial scrubbing uses the shared timestamped effort mapper. Prediction and
polished camera transitions remain open.

`tests/rink_view.gd` verifies aiming, camera isolation, shared delivery, stone
identity/reset and end transitions. Running without `--headless` captures the
camera views under `build/evidence/`. Installed Android emulator render/touch
checks are recorded in the handoff; physical-device feel and GPU profiling remain
separate gates.

The delivery camera faces the called broom rather than the center line. It stays
steady during the initial hand stroke so lateral movement is visible, then
smoothly follows the lateral slide. The hand's forward/back preview offset blends
into the slide instead of being discarded at the drive boundary. These camera and
offset blends remain presentation-only; authoritative lateral positions arrive in
the held frame and are used unchanged for release.

Arena lighting comes from eight overlapping downward spot fixtures at 3.40 m,
below the visible lamps and ceiling beams. Their shadows have 22% opacity and
ambient fill is 0.55. There is no directional outdoor light. Light nodes stay
outside the ceiling mesh group so the overhead House camera hides the beams
without extinguishing the indoor lighting. The eight-light limit also fits the
Compatibility renderer's default per-mesh spotlight budget. Shadow blur uses the
standard filter; PCSS is not required. See [Godot lighting documentation](https://docs.godotengine.org/en/stable/tutorials/3d/lights_and_shadows.html).

During travel, a gold disc identifies the selected eligible moving stone. Tapping
another eligible stone selects it; the Sweeper camera follows that selection.
Scrub input intersects the visible ice plane and computes offsets relative to the
rendered stone and authoritative velocity direction. Those offsets become integer
millimetres before entering the existing native brush boundary. Smoothing changes
neither stones nor the input effort calculation. Off-path input produces no brush;
it is not clamped back onto the stone's path. The brush displays the submitted
position; accessible hold animates about the centered position. These are local
intent cues, not confirmation that the host accepted a contribution.


## Skip judgement and ice sound pass

Solo callers get a short, fixed-size curl glyph anchored beside the broom. Its
horizontal direction is projected through the current camera, not assumed to be
screen-right. It is never scaled by the physics or drawn to a forecast endpoint.
The caller's house camera includes the guard area. The thrower's existing call
card and drills retain their intention/target displays.

`ui/shot_reference.gd` records the actual broom, turn and settled stone per team.
The authoritative per-shot contact count conservatively rejects every contacted
shot. Later stone movement/removal and end changes invalidate old observations.
No history marker enters match saves, the simulator or network commands.

`ui/ice_audio.gd` generates original PCM textures with its own seeded RNG:
speed-dependent stone rumble, effort-dependent brushing, and short granite
contacts. Effects use frame speed, brush intent, and the native contact counter.
Impact loudness currently uses pre-contact maximum speed as a bounded proxy,
not individual contact impulse. Textures are synthesized once per scene; no
per-tick audio buffers or external audio assets are loaded. Settings → Ice sounds
persists separately from speech. Effects stop on mute, suspension and local
settings/ice-board/online-room overlays. No venue ambience, spatial panning,
pebble-wear modulation, fatigue breath or phone haptics in this pass.

Validation: `tests/called_shots.gd` checks touch broom aiming, no skip endpoint,
line preservation under weight/turn changes and clean-shot recording.
`tests/skip_polish.gd` checks reference invalidation and sound lifecycle/settings.
Rendered desktop/mobile-layout captures use `tools/solo_review.gd`.


Local Settings now pause practice and mixed doubles as well as solo/drills, with
no accumulated travel debt on close. Fresh ice/New match/Restart drill is blocked
during a live or held delivery. Replacing an existing session opens a focus-trapped
review with Keep playing selected; Escape restores the prior focus and session.
The next-end and completed-match rematch actions remain immediate. Online settings
do not pause the remote authority. `tests/local_menus.gd` covers pause/resume,
restart cancellation/confirmation, held-delivery protection and modal input.


Between match deliveries, a compact readout identifies hammer, each team's stones
still to play, and the settled house count. It hides during travel and held slides.
Solid cream rings mark the actual counting stones; a pending no-tick choice hides
them until the remedy is accepted. Counts and ring IDs come from the native
fixed-point scoring routine, including exact ties and biter eligibility, rather
than a second float-based UI interpretation. Positioned doubles stones do not
consume delivery inventory. Extra ends are labelled explicitly.

Completed ends show scorer/points, total score, next hammer and a Next end action;
finished matches show the winner and Rematch. A thinking-clock forfeit is labelled
as such. The action inherits existing online host/readiness restrictions. Duplicate
delivery controls hide while this result card is shown. `tests/match_readout.gd`
checks scoring, inventory, native replay, blank ends, clock expiry and next-end
reset; captures live in build/evidence/match-readout. No authority or journal
schema changed; these are derived presentation fields.


Settings now scroll internally while Done and Call shortcuts remain fixed.
Keyboard focus follows the scrolled control. The separate Ice volume slider
changes all three effect layers and persists independently of the mute toggle.
Solo defaults to waiting after Gold's settled shots; Continue advances without
charging the opponent's thinking clock during review. The optional setting
restores two-second auto continuation. `tests/shot_review_pause.gd` checks the
pause, saved-result restoration, opponent continuation and scrolled volume access.
