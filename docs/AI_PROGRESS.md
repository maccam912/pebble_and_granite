# Solo teams and role presentation

Requested 26 October 2026. Work in scoped, validated commits and push each
checkpoint. Check weekly usage at milestones; below 50% remaining, finish the
current change, commit/push and stop. Starting usage: 19% used / 81% remaining.

## Current work

- [ ] Solo club teams: one human position, seven AI players, complete 16-stone ends.
- [ ] Club / Competitive / Elite execution accuracy using shared physics.
- [ ] AI shot planning, legal outcomes, sweep decisions and resumable match journals.
- [ ] Optional opponent fast forward strictly between the hog lines.
- [x] First-person skip and sweeper viewpoints, closer delivery/skip views.
- [x] Persistent FOV setting and inspection zoom button.
- [x] Verify broom/thrower orientation with projection and native release checks.
- [ ] Skip calls with visible text/icons for silent play.

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
