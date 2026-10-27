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

### Control modes and accessible calls

Added Full team (all eight Gold throws, manual brush/call control) and Calling only
(all AI throws, human Gold calls), alongside four individual positions. Call keys
H/C/O are remappable with duplicate-key swapping; Z stays zoom, Esc cancels/closes,
and held-key repeats do not issue calls. Main/shortcut/ice-board modals contain
keyboard focus. Visual buttons display current keys. Manual spoken calls bypass
the automatic chatter delay; muting stops device speech. The weight-zone mapping
now matches the displayed 1–3 guard / 4–6 front / 7 tee / 8–10 back legend.

The native input fixture covers real key capture, focus containment, reserved
keys, swaps, Esc, remapped calls, settings isolation, calling-only save metadata,
and a full 16-stone Full team end. An unswept reference hash checks Full team
never adds automatic brushing. Position changes remain disabled during held/live
stones. AI accuracy tiers and the normal position default remain available.

### Installed Android UI probe preparation

Added a one-use development observer (schema-3 diagnostics request) that exports
real control geometry and state, with normal save/settings persistence disabled
before scene setup. It accepts no game commands. The adb driver uses actual menu
selections/taps for Calling only, Elite, fast watching, guard selection/zoom,
Send, HARD/OFF, and ice-board pause. It retrieves the accepted match journal for
shared-core verification and compares all normal save/preference files before/
after. Desktop bootstrap/consumption/no-persistence tests pass. Installed evidence
will be recorded only after a clean APK run.

### Installed checkpoint complete

Clean f573bdc / local Android build 75 passed installed golden/JNI, actual solo
menu/call/zoom/board/fast-forward input, desktop verification of its two-delivery
journal (`cb90ff1fc182d9c9`), and the original touch/sweep/background/regrip/hog
suite. UI-probe normal saves/preferences were unchanged; original practice files
were restored after the separate Fresh ice touch fixture. Exact APK provenance
and evidence paths are recorded in ANDROID_INPUT.md. Android exposes speech and
English voices, but no-audio emulator operation is not audible approval.

All requested feature checkboxes above have native/installed evidence. Additional
bible work completed: target drills, shot cards, local ice notes/paths/statistics,
Full team / Calling only and remappable accessible calls. Advanced strategy,
independent team brushes, online boards/calls, career and physical calibration
remain explicitly open. Weekly usage: 22% used / 78% remaining; the below-50%
remaining cutoff has not been reached.

Rendered installed screens were inspected. A small follow-up caption now labels
the next thrower explicitly while the previous stone rests, avoiding attribution
of the previous result to the next team. This UI-only change follows the installed
f573bdc evidence and is covered by the native solo flow; input/physics are unchanged.

### No-tick remedy recovery

Final rules review found that club teams could enter the existing no-tick Choice
phase without a UI route to continue. Gold now chooses Accept current positions
or Restore original positions; Cyan evaluates both and chooses automatically.
The AI planner also evaluates the opponent's best remedy during search, rather
than scoring the unresolved no-tick board. No-tick messages distinguish pending,
accepted and restored states; the chosen delivery counts exactly once.

A real glancing-contact fixture reaches Choice through two normal releases.
Core/native tests cover both human remedies, a saved pending choice, exact journal/
review replay, duplicate rejection, and Cyan automatic continuation. A prefixed
hog fault reverses the teams for the AI-owned choice case. Existing rule/journal
versions retain their meanings; this adds the missing frontend command path.

The updated AI/full-game gate completed seven ends / 112 deliveries, including a
six-end tie, extra-end winner, full review/journal reconstruction and rematch.
The remedy camera now frames the house plus free-guard zone; the explanatory
panel narrows so it does not obscure that decision area.

The same FSM audit caught a clock forfeit during an early, still-moving release.
Local travel now ends when match authority leaves InFlight, exposes Rematch, and
saves that terminal state. A nearly-expired-clock fixture verifies recovery and
rematch. The new team_rules.gd gate covers these terminal/choice branches.

### Takeout and split-time training

Added two five-shot drills from the bible. Takeouts alternate sides and place a
Gold target using an ordinary recorded AI draw. Player grades distinguish removal
with retention in the house (3), removal (2), displacement of at least 45 cm (1),
and miss/fault (0). Displacement uses the actual setup finish. Setup never counts
as a player attempt. Replays reconstruct the target and evolving ice normally.

Timing training shows attainable 14–16 second goals and grades the measured
whole-stone near/far hog interval within 0.20 / 0.50 / 1.00 seconds. Missing either
crossing earns zero; timing alone can score a stone that later runs out the back.
Goals and tolerances are game training values on the current model, not measured
ice calibration. Positional rings are hidden for this drill. Old four-drill
wrappers upgrade their best scores to the new six-drill wrapper without changing
native journal compatibility.

Core tests cover actual target setup/hits/faults, atomic setup rejection, exact
setup/outcome replay, real early-release hog timing, thresholds and attainability
of all five time goals. Native tests cover five takeout attempts, no setup grade,
ready-target/in-flight timing restore, legacy scores and malformed metrics.
Weekly usage: 23% used / 77% remaining; work continues.
