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
