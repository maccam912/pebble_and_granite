# Pebble & Granite

A curling game in Godot with a shared deterministic Rust simulation. The first
playable milestone is a 3D club feel slice: aim the broom, pull back, push, hold the slide, and flick to release,
then sweep during travel and inspect the release report. No power sliders.

## Run

Install Rust 1.98.1 and Godot 4.7, then:

```sh
git lfs pull
python3 tools/build_native.py
godot --path .
```

Install Git LFS before cloning. Original generated material textures are stored
in LFS; their provenance and exact generation prompts are in
[assets/textures/README.md](assets/textures/README.md).

The native build defaults to optimized code for playable simulation performance.
Use `python3 tools/build_native.py --debug` only for native debugging; it is much slower.

`python3 tools/godot.py --path .` downloads the hash-pinned official editor if
Godot is not installed. Mouse and held-click trackpad use the same stroke as
Android touch. Drag the broom in the house to aim. Grip the stone handle directly on the ice, pull back, push forward and hold while
sliding. Before the slide, sideways movement moves the stone and the direction of
your push adjusts the delivery line around the broom. Once sliding, a small
left/right finish adds curl; the live label shows the recognized direction. A
small forward/back finish adjusts weight. A quiet lift gives neutral rotation. One-push skips the initial pullback.
**Menu → Learn to play** opens four guided steps for broom aim, draw weight, finishing
curl and sweeping. Each step responds to your real input and offers retries or
Skip; Return to game restores your paused session. Lessons use a separate sheet
and never replace your saves or preferences.
Menu also switches between Practice, Drills, Solo, Mixed doubles and Online rooms.
Local play pauses while it is open. Finish a held or moving shot before changing
modes; Resume returns immediately. Fresh ice/New match lives in this menu.
Delivery and sweep buttons appear only when relevant; Ice board stays beside the rink.
Settings adjusts field of view (40–85°). Zoom or Z inspects the house closely;
gripping the handle returns to the normal delivery view. The skip stands behind
the broom and the sweeper follows beside the moving stone.
Cycle Camera for delivery, sweeper, skip or overhead house views; drag the broom in House view to aim. The separate `scenes/lab.tscn` scene retains the diagnostic 2D view. Scrub back and forth on the ice just ahead of the moving stone; motion sets effort
and brush position matters. Tap another eligible moving stone to select it. A gold
disc marks the selection, and the Sweeper camera follows it. The **Hold to sweep**
button follows the selected stone at steady effort. Lift to stop.
Scrubbing feedback explains when your brush is behind or beside the useful path.
A live local hog-to-hog stopwatch measures the actual crossings during travel.
Escape opens Settings and pauses local play; close it and regrip to resume a held
delivery. Fresh ice and New match ask before replacing an ongoing session.
Next stone retains the field and evolving ice; Fresh ice starts a new session.
Practice saves automatically, including held slides and interrupted shots, with a previous-save backup. Choose **Solo 4 vs 4** to play one position with seven AI players. Settings
selects your position (or Full team / Calling only), three AI difficulty tiers,
remappable H/C/O call keys, spoken calls and optional 4×
opponent travel between the hog lines. Skip/vice can send called shots and call
HARD/CLEAN/OFF; text and symbols support silent play. Your deliveries show the skip's
requested weight, target, broom and curl in a persistent call card with an overhead map.
As skip, drag the broom and select in-turn/out-turn; the arrow shows curl direction
without revealing a landing spot. A ghost broom and highlighted stone recall your
last contact-free result. Settings can mute the new stone/brush sounds separately
from spoken calls. Solo matches save separately. Between deliveries, hammer and remaining stones show
beside the rink; cream rings mark counting stones. End cards explain the score
and lead into the next end or rematch.
Club plans one shot; Competitive and Elite consider opponent replies, with a
wider search and execution-risk check for Elite. Score, end and hammer matter.
New solo matches have two visible sweepers with separate effort and fatigue.
AI learns line/weight from observed clean draws; it cannot read hidden ice.
Existing model-3 saves retain their original physics and brush behavior.
See [solo teams](docs/SOLO_TEAMS.md) for controls and current AI scope.
**Drills** offers five-shot rounds for tee weight, front guards, alternating line
and sweeping, plus takeouts and hog-to-hog timing. Gold target rings mark
15/45/90 cm scoring zones; weight drills grade depth only. Takeouts reward
removal and staying in the house; timing drills show a target time and actual
crossing error. Rounds and best scores save separately from free practice.
**Ice board** shows recent actual paths against the release ray, true hog-to-hog
splits, observed curl and delivery totals by position. Select a path to save a
short ice note. Opening it pauses local play; online boards are future work.
Choose Mixed doubles for a local pass-and-play game: select positioned stones, power plays and first/last throwers, then play through scoring and extra ends. Local matches autosave separately from practice; choose Mixed doubles again to resume, including interrupted shots. Choose Online rooms to host or join by four-character code. Four players ready up for online mixed doubles; the host stays open. Both teammates
may sweep before the far tee, with per-player fatigue; only one contributes per
team behind it. Online play is an early prototype: four local peers pass full-game, rematch and in-flight reconnect tests, while cross-device match and Android latency/feel testing remain open. Reconnect recovery runs in the background with visible progress. A saved Reconnect
shortcut survives client restarts while the host stays open; Forget room removes
it. Paused play identifies which players are missing or synchronizing. Held deliveries
freeze during interruptions and wait for the thrower to regrip after synchronization.

## Downloaded macOS builds

Extract the Mac ZIP and move **Pebble & Granite.app** to Applications.
Development builds are ad-hoc signed, but not notarized by Apple. If macOS blocks
the first launch, open **System Settings → Privacy & Security → Open Anyway**
after attempting to open the app.

Build 40 contains malformed XML caused by the ampersand in the
game name, which macOS reports as a damaged app. From a source checkout, repair
the extracted app with:

```sh
python3 tools/macos_package.py "$HOME/Downloads/pebble-and-granite-40-macos/Pebble & Granite.app"
```

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
