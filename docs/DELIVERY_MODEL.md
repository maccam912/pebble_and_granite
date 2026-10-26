# Delivery model work in progress

`curl-input::delivery` is a tested Rust foundation; it is not yet connected to
Godot or the match authority. The currently playable card still uses the original
stroke-to-fixed-release route. Do not claim hog-release enforcement in the game
until the integration items below are complete.

The model derives a slide from the measured drive speed. Target speed is at the
near hog; an integer square root derives an initial speed for a provisional
0.07 m/s² slide deceleration. Starting stone centre is at -37.8 m, ahead of the
hack. Position is in micrometres, speed in micrometres/second, and elapsed time is
quantized to 240 Hz. Read-only pose queries cannot change the release, irrespective
of render frequency. Quiet-hand queries complete a pending drive window on a copy,
so animation sampling does not become input or change weight.

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

## Integration required before enabling

- Add a seat-owned, journaled hog-violation command that consumes the delivery
  without moving existing stones, including end scoring and replay/replica tests.
- Pass actual release position and speed through the native and online boundaries.
  The existing sim accepts no release before -35 m and its old draw fixture uses a
  centre just behind the hog's inside edge. Correct those physical bounds explicitly,
  version affected contracts, regenerate intentional goldens, and preserve rejected
  old saves rather than silently clearing or misinterpreting them.
- Connect the 3D hand/body pose and warning to this model, with direct pointer
  interaction and no power meter. Never derive authoritative position from meshes.
- Handle thinking-clock cutoff at the delivery tee and background/cancel semantics
  coherently; a visual slide alone does not establish those rules.
- Add installed Android touch and full-match/network regression coverage before
  calling the new delivery path playable.
