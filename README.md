# Pebble & Granite

A curling game in Godot with a shared deterministic Rust simulation. The first
playable milestone is a feel lab: aim the broom, pull/push/settle/lift the stone,
then sweep during travel and inspect the release report. No power sliders.

## Run

Install Rust 1.98.1 and Godot 4.7, then:

```sh
python3 tools/build_native.py
godot --path .
```

`python3 tools/godot.py --path .` downloads the hash-pinned official editor if
Godot is not installed. Mouse and held-click trackpad use the same stroke as
Android touch. Drag the broom in the house to aim. Grip the large stone, pull
back, push upward, settle, then lift. One-push removes the pull/settle requirement.
Hold the ice or the sweep button to sweep; release to stop. New stone resets the
practice ice. This is an early lab, not a finished match mode.

## Check

```sh
python3 tools/check.py
python3 tools/build_native.py
godot --headless --path . --script tests/lab_smoke.gd
cargo run --release -p curl-server -- example build/throw.json
cargo run --release -p curl-server -- replay build/throw.json
```

The CLI is currently a replay verifier, not a network listener. Simulation uses
Q32.32 arithmetic at 240 Hz and versioned release/sweep records. Replay traces
include the canonical hash after every tick, including ice and brush fatigue.
Floating point is limited to presentation and diagnostic output.

See [handoff](docs/HANDOFF.md), [architecture decisions](docs/DECISIONS.md), and the
original **Pebble & Granite — Curling Game Design Bible.md**. Physics coefficients
are provisional. Human feel testing and measured calibration remain necessary.
