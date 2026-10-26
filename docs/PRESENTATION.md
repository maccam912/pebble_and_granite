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
