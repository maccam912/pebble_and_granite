# Solo teams and role presentation

Requested 26 October 2026. Work in scoped, validated commits and push each
checkpoint. Check weekly usage at milestones; below 50% remaining, finish the
current change, commit/push and stop. Starting usage: 19% used / 81% remaining.

## Current work

- [x] Solo club teams: one human position, seven AI players, complete 16-stone ends.
- [x] Club / Competitive / Elite execution accuracy using shared physics.
- [x] AI shot planning, legal outcomes, sweep decisions and resumable match journals.
- [x] Optional opponent fast forward strictly between the hog lines.
- [x] First-person skip and sweeper viewpoints, closer delivery/skip views.
- [x] Persistent FOV setting and inspection zoom button.
- [x] Verify broom/thrower orientation with projection and native release checks.
- [x] Skip calls with visible text/icons for silent play.

## Follow-on design bible work

After the requested features, choose substantive missing items from the bible,
record scope/evidence here and in HANDOFF.md, and continue until the usage cutoff.
Candidates: target drills, call vocabulary/weight zones, ice notes, shot stats.
Advanced multi-ply AI, measured ice calibration, career, public hosting and human
feel/physical-device approval remain separate work.

## Validation boundaries

Rust owns simulation/rules/accepted commands; presentation and accelerated watching
must not alter fixed dt. Existing saves/journals retain their meanings. Desktop
native/rendered tests do not certify physical Android or human playtest feel.

### Camera checkpoint

Persistent 40–85° FOV (52° default), 2.8× inspection zoom / Z, closer delivery
and sweeper views, and skip eye position directly behind the broom. House zoom
narrows orthographic size. Broom/native release tests verify both aim signs;
the underlying release sign was correct. Camera tests also verify alignment and
that changing view/zoom never mutates simulation. Native rendered delivery/skip/sweeper/house captures inspected; rink, input and
online UI regression gates passed. Physical-device feel remains open.

### Solo checkpoint

One human position and seven AI players, six scheduled team ends with extra ends,
16 deliveries, AI shot search on a native worker, three release-scatter tiers,
noisy weight advice, HARD/CLEAN/OFF text/symbol calls and optional device speech.
Separate atomic solo save/backup retains role, difficulty and called target.
Opponent-only 4× watching uses normal fixed ticks, bounded between the hog lines.

Validation: full 16-stone Godot end; skip approval/calls; human seat assignments;
in-flight solo restore and corrupt-primary backup recovery; normal/accelerated
watching with identical final match hashes; inverse draws on both sides; release
and actual landing scatter comparisons; journal restore through an entire team
end; core/golden and all-target Clippy gates; existing desktop integration gates.
Desktop and mobile-sized rendered settings/call/zoom/skip/sweeper screens inspected.
Independent team brush identities and multi-ply search remain open, documented in
SOLO_TEAMS.md. Weekly usage: 20% used / 80% remaining; work continues.

### Target drills checkpoint

Implemented four five-shot drills: weight to tee (depth only), front guard,
alternating left/right line, and sweeping a reachable underweight draw home.
Core scoring uses actual settled positions and zero stars for out-of-play stones;
15/45/90 cm rings mark the three thresholds. Current round, best scores and the
validated practice journal save atomically in their own file. Interrupted shots
and the settlement-before-grading boundary restore without double scoring.

Core scoring, five-shot completion/restart, target mirroring, in-flight restore,
malformed-metadata rejection and rendered target/score tests pass. New scripts
join CI. Timed split-training, takeout fixtures, unlock sequences and historical
personal statistics remain open. No physics/rules/replay compatibility changes.

A complete six-end solo game passed with 96 deliveries, a declared winner,
completed-journal replay hash equality and a working solo rematch. This full-game
gate now joins desktop CI. The camera checkpoint's complete pipeline succeeded
(run 40447872379); solo checkpoint c93cead's pipeline is still running.

### Skip shot card

Human skip/vice can select draw, guard or hit; tap a target/stone in House view;
and change turn. A worker inverse-solves the selected call on the shared ice.
A small gold ring shows the intended target while the broom remains separately
adjustable. Reversing turn re-solves the broom line instead of reusing the old
line with opposite curl. Ask AI skip restores automatic strategy suggestions.
Core guard/hit inverse tests cover both sides/turns; native target picking,
turn reversal, guard release, retained sweep target and rejected-call atomicity
pass. The positive target save bound also now includes legal back-house stones.

### Observed ice board and true splits

Rust now rebuilds the last 32 actual paths, true hog-to-hog timing, observed curl,
contacts and release statistics from accepted journals. Per-position totals and
release spread include every delivery even when old paths leave the bounded
recent list. The local ice board plots actual path versus release ray and saves
optional annotations against exact observed-shot fingerprints in separate bounded
sidecars with backup recovery. Solo shows the human team's board; local mixed
play can select a team. Opening the board pauses local play and clears live brush
input. No full trajectory is claimed to predict a called shot.

Tests cover early release timing, practice/match review reconstruction, bounded
history with complete stats, late-sweep path reconciliation, protected-stone
remedies and unchanged canonical hashes. Native UI/annotation backup recovery and
rendered desktop/mobile-sized inspection pass. Core/golden and all-target Clippy
pass. Physics/rules/journal versions stay unchanged because reviews are derived.
Online ice boards, team note replication and Bayesian AI ice learning remain open.
The last usage check was 21% used / 79% remaining.

Release distinction: camera/solo pipelines passed, but newer workflow revisions
superseded their publish steps. Their tested packages are CI artifacts. The latest
verified downloadable release remains Build 88 at 79f5615 until a later complete
run publishes; a passing pipeline alone is not a newly published release.

The full six-end / 96-delivery solo gate passed again with the observer enabled:
32 retained paths, all 96 deliveries in per-position totals, identical rebuilt
observations and canonical hash after restore, and working rematch. Fourteen
existing/new desktop integration gates also passed after the board integration.
