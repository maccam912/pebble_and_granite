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

Finishing left/right sets rotation from recent motion, and a small forward/back
finish trims speed. Quiet-hand release is neutral rotation. Coarse Soft/Draw/Firm
feedback appears as a small lower-left label during the slide; it widens for the
hog warning. Full delivery instructions appear before gripping. Procedural art, gain thresholds,
rotation magnitude, hand animation and feedback need curler/device iteration.
Spatial scrubbing, prediction and polished camera transitions remain open.

`tests/rink_view.gd` verifies aiming, camera isolation, shared delivery, stone
identity/reset and end transitions. Running without `--headless` captures the
camera views under `build/evidence/`. Installed Android emulator render/touch
checks are recorded in the handoff; physical-device feel and GPU profiling remain
separate gates.
