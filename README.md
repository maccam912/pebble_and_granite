# Pebble & Granite

A curling game in Godot with a shared deterministic Rust simulation. The first
playable milestone is a 3D club feel slice: aim the broom, pull back, push, hold the slide, and flick to release,
then sweep during travel and inspect the release report. No power sliders.

## Run

Install Rust 1.98.1 and Godot 4.7, then:

```sh
python3 tools/build_native.py
godot --path .
```

The native build defaults to optimized code for playable simulation performance.
Use `python3 tools/build_native.py --debug` only for native debugging; it is much slower.

`python3 tools/godot.py --path .` downloads the hash-pinned official editor if
Godot is not installed. Mouse and held-click trackpad use the same stroke as
Android touch. Drag the broom in the house to aim. Grip the stone handle directly on the ice, pull back, push forward and hold while
sliding. Finish with a left/right flick for curl; a small forward/back finish adjusts
weight. A quiet lift gives neutral rotation. One-push skips the initial pullback.
Cycle Camera for delivery, sweeper, skip or overhead house views; drag the broom in House view to aim. The separate `scenes/lab.tscn` scene retains the diagnostic 2D view. Hold the ice or the sweep button to sweep; release to stop. Next stone retains the field and evolving ice; Fresh ice starts a new session.
Practice saves automatically, including held slides and interrupted shots, with a previous-save backup. Choose Mixed doubles for a local pass-and-play game: select positioned stones, power plays and first/last throwers, then play through scoring and extra ends. Local matches autosave separately from practice; choose Mixed doubles again to resume, including interrupted shots. Choose Online rooms to host or join by four-character code. Four players ready up for online mixed doubles; the host stays open. Online play is an early prototype: four local peers pass full-game, rematch and in-flight reconnect tests, while cross-device match and Android latency/feel testing remain open. Reconnect recovery runs in the background with visible progress. Held deliveries
freeze during interruptions and wait for the thrower to regrip after synchronization.

## Check

```sh
python3 tools/check.py
python3 tools/build_native.py
godot --headless --path . --script tests/lab_smoke.gd
cargo run --release -p curl-server -- example build/throw.json
cargo run --release -p curl-server -- replay build/throw.json
cargo run --release -p curl-server -- verify-session /path/to/practice-session.json
cargo run --release -p curl-server -- verify-match /path/to/match-session.json
```

The CLI is currently a replay verifier, not a network listener. Simulation uses
Q32.32 arithmetic at 240 Hz and versioned release/sweep records. Replay traces
include the canonical hash after every tick, including ice and brush fatigue.
Floating point is limited to presentation and diagnostic output.

See [handoff](docs/HANDOFF.md), [architecture decisions](docs/DECISIONS.md), and the
original **Pebble & Granite — Curling Game Design Bible.md**. Physics coefficients
are provisional. Human feel testing and measured calibration remain necessary.
