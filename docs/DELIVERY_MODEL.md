# Delivery model work in progress

`curl-input::delivery` now drives the direct-on-ice handle gesture in both local and
online scenes. `lift` returns actual integer release position and speed; both
native simulation and the online packet builder share the same validated factory.
A held pointer crossing the hog line automatically submits a consumed-stone fault.
The 3D preview and delivery camera follow the read-only pose, without feeding
rendered coordinates back into simulation. The default view grips the 3D handle directly and renders a simple hand/forearm.
Local and online play both use a persisted authority-held delivery plan.

The model derives a slide from the measured drive speed. Target speed is at the
near hog; an integer square root derives an initial speed for a provisional
0.07 m/s² slide deceleration. Starting stone centre is at -37.8 m, ahead of the
hack. Position is in micrometres, speed in micrometres/second, and elapsed time is
quantized to 240 Hz. Read-only pose queries cannot change the release, irrespective
of render frequency. Read-only pose queries leave the gesture unchanged; accepted input/quiet-drive
closure fixes the weight independently of later finishing motion.

The near hog's inside edge is -28.349 m; its 102 mm painted width extends toward
the delivery tee. The conservative R5(e) release boundary is when the stone's
142 mm leading radius reaches the near edge: centre -28.593 m. Equality is a
violation. A warning begins 0.8 m earlier. These geometry semantics follow the
1 September 2026 rulebook; the biomechanical coefficients still need curler/device
calibration. R5(g)'s delivery-end tee crossing is exposed as `in_play`.

Release returns either Cancelled, Released, or HogViolation, with an immutable
pose and bounded arm-speed trim. Holding indefinitely cannot turn a late release
into a retry. Malformed input and cancelled gestures do not produce a valid shot.
Tests cover early/late releases, exact boundary ticks, render-frequency independence,
stationary-hand continuation, cancellation, invalid input and repeated release.

## Integration status

- [x] Seat-owned, journaled hog-violation command consumes the delivery without
  moving existing stones, including end scoring and replay/replica tests.
- [x] Pass actual release position and speed through the native and online boundaries.
  Model 3 now accepts centres from -37.8 m up to (excluding) -28.593 m.
  The diagnostic fixed release moved 244 mm earlier to obey this bound.
  Model 3 / rules 2 / protocol 7 / practice schema 2 explicitly reject old
  development records; existing restore guards preserve those files. No model-2
  migration is implemented. Every-tick goldens were regenerated intentionally.
- [x] Connect the 3D hand/body pose and warning to this model, with direct pointer
  interaction and no power meter. Never derive authoritative position from meshes.
- [x] Local: handle thinking-clock cutoff at the delivery tee and background/cancel semantics
  coherently; a visual slide alone does not establish those rules.
- [x] Installed Android touch and full-match/network regression coverage for the
  direct gesture; repeat lifecycle-specific Android and network checks after integration.

Input mapping metadata is version 4; delivery mapping is version 4. The old fixed-origin `deliver` and
`delivery_packet` entry points remain diagnostic fixture APIs; playable local
and online scenes use held lifecycle commands. `slide_packet` remains diagnostic. No power meter was added.
The main interaction surface is the projected 3D handle. A sideways finish of four logical pixels selects rotation during the slide,
with a 350 ms grace period before lift. Forward/back speed trim still uses the
last 120 ms and is bounded to ±70 mm/s. A quiet hand releases without rotation. Curl flicks
do not also change the broom aim. Spatial sweeping remains unimplemented.

## Authority lifecycle integration

Protocol 8 / rules 3 introduced BeginDelivery, ReleaseDelivery and CancelDelivery records.
The host advances an InHand plan, charges thinking time only until the delivery
tee, automatically consumes a held stone at the hog deadline, and rejects returns
to the hack after tee crossing. Journals preserve the exact elapsed state. Tests
cover millisecond/frame batching, replay, cancellation ownership and clock expiry.
Rotation and bounded weight trim are chosen in ReleaseDelivery, preserving
the requested finishing flick instead of locking rotation at the hack.

Early free releases now keep their thinking clock running through flight until
tee crossing. Past sweep samples that could move that clock boundary are retimed
to authority arrival; normal downstream rewind remains available. Local practice, local matches and online scenes now route through held state.
Online BeginDelivery and ReleaseDelivery use consecutive reliable commands; the
host derives position from accepted elapsed time instead of trusting client release
coordinates. Replicas display the same held pose.

Practice schema 3 stores a bounded pending delivery alongside the shot journal.
Only idle ice time is appended during a held slide; adjacent idle records coalesce.
Model-3 schema-2 practice saves without pending state upgrade in memory. Invalid
or incompatible files remain preserved by the existing save guards.

Local focus loss, application pause and orderly window close save the pending
state. The slide does not advance until the player regrips the handle. Returning
to the hack is available before tee crossing and rejected afterward. Regrip keeps
the original weight, aim and position while starting a fresh finishing-motion
window, so the player can still choose curl and a bounded weight trim.

A quiet drive closes after its fixed 120 ms measurement window plus a 50 ms input
event grace period. The same closure runs before late motion/release events,
preventing render polling or a much later finishing flick from redefining the
initial drive. The legacy diagnostic Stroke mapper remains independently tested.

Protocol 9 adds the seat-owned SuspendDelivery command. Focus loss or opening the
room panel suspends a held online slide; a disconnected room member causes the
host to journal suspension before broadcasting the paused room. Reconnection must
complete hash-checked synchronization, then the thrower must regrip to resume.
Suspended authority time cannot advance ice, clocks, or the hog deadline. Only the
thrower can resume or finish, and finishing while suspended is rejected. Historical
non-suspended held records retain their serialized bytes and hashes.

Online pose updates currently arrive at 20 Hz. There is no latency prediction or
rewind of the held slide; release uses host receipt time. Physical-device latency
and feel tuning remain an explicit follow-up, alongside spatial sweeping.

## Analog launch and gentle curl (26 October 2026)

Protocol 11 adds `BeginAnalogDelivery`, carrying a bounded `DeliveryLine` with
`x_mm` (±450 mm) and `aim_mm` (±1500 mm relative to the called broom). Pullback and
push move the stone sideways at 6 mm per logical pixel. At the fixed drive-window
end, the mapper freezes the lateral origin and push slope; the latter maps a
sideways/forward ratio to a target offset with gain 3000 mm. Both are provisional
feel coefficients. A straight push follows the selected broom. Off-axis pushes
change aim even when a later finishing gesture applies the opposite curl.

Held x follows the straight ray from that captured origin toward the adjusted
broom, using authoritative y/time. Practice and match release start at that same
x/y and use the same ray, so lifting cannot snap the stone to the center line.
Finish line trim is rejected for analog plans: after slide start, lateral motion
only selects curl. The live curl label and handle preview use the same read-only
recognizer as the release. Small jitter remains neutral; old gestures expire and
regrip starts a fresh finishing window without changing the held launch line.

Old `BeginDelivery` journals and pending saves keep their exact behavior via an
absent optional line field. Their serialized bytes/hashes and physics goldens are
unchanged. Match/practice schemas, rules 4 and physics model 3 remain unchanged;
protocol 11 prevents mixed-version rooms from accepting the new command.
