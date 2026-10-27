# Solo four-player teams

Choose **Solo 4 vs 4**. Gold has one human and three AI players; Cyan has four
AI players. **Settings → Your solo position** selects Lead, Second, Vice or Skip.
Each position delivers two stones per end, with six scheduled ends and extra
ends when tied. The existing club rules, thinking clocks, scoring and remedies
apply. Human deliveries keep the direct pull/push/slide/flick input.

When you are the skip (vice while the skip delivers), review the proposed shot,
use House camera to adjust the broom, choose the turn, then **Send called shot**.
During travel **HARD**, **CLEAN**, and **OFF** control AI brushing. In other
positions, follow the AI skip's text/symbol call and scrub or hold to sweep.
Device speech is optional and depends on an installed English voice; the visual
call is always present. Lead/second/vice use the sweeper view during teammate
shots; the caller watches from behind the broom. Camera remains manually selectable.

**AI shot accuracy** has three tiers. All use the same physics and the same
bounded one-ply search over draws, center guards and hits. The executor adds
centered triangular speed, line and rotation scatter with these maximum bounds:

| Tier | Speed | Line at tee | Rotation |
| --- | --- | --- | --- |
| Club | 100 mm/s | 360 mm | 0.045 turns/s |
| Competitive | 40 mm/s | 150 mm | 0.022 turns/s |
| Elite | 12 mm/s | 45 mm | 0.008 turns/s |

These are provisional game tuning values, not measured human accuracy ratings.
The planner inverse-solves the current ice, then confirms candidates against the
whole board through the shared authority. Planning runs off the render thread.
Protected-stone remedies participate in evaluation. Actual releases and brush
commands are saved in the normal validated match journal; derived AI plans are
recomputed between shots. Solo metadata/target and match data save together in a
separate `solo-teams.json`, with a previous-save backup.

Enable **Fast opponent travel between hog lines (4×)** to accelerate watching
Cyan. Fixed simulation dt stays 1/240 s. It starts only after the entire stone
passes the near hog and returns to normal before the far hog/house. Own shots
run at normal speed. Zoom / Z is inspection only and gripping returns to normal
FOV. FOV, speech, accuracy, role and fast travel preferences persist on the device.

## Scope still open

The current team authority has one combined brush per team. AI partner effort
and human input contribute to that brush, with its existing fatigue. Independent
four-player brush/fatigue identities, individual teammate personalities, advanced
multi-ply strategy, Bayesian ice learning, doubles/runbacks/freezes, coaching and
career remain future work. Mixed-doubles online continues to use its existing
separate per-player brushes. No simulation, rules or journal version changes
are needed for this first solo implementation.

Physical Android performance/feel, human curling judgement and measured ice
calibration remain separate validation gates.
