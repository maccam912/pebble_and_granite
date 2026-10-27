# Solo four-player teams

Choose **Solo 4 vs 4**. Gold has one human and three AI players; Cyan has four
AI players. **Settings → Your solo control** selects Lead, Second, Vice or Skip.
**Full team** gives you all eight Gold deliveries and manual brushing/calls.
**Calling only** delegates every delivery to AI and lets you call all Gold shots.
Each position delivers two stones per end, with six scheduled ends and extra
ends when tied. The existing club rules, thinking clocks, scoring and remedies
apply. After a no-tick violation, Gold can accept the current positions or restore
the original stones and remove the delivered stone. Cyan chooses its own remedy
automatically. Pending choices survive saves without losing the delivery. Human deliveries keep the direct pull/push/slide/flick input.

When you are the skip (vice while the skip delivers), review the proposed shot.
Choose **Draw**, **Guard**, or **Hit**. **Place target** lets you tap the intended
landing point, or a stone for a hit. A small gold ring marks that intention; the
AI solves release weight and broom line on the current ice. Changing turn solves
the line again. You can still drag the broom to make your own correction.
**Ask AI skip** requests another strategy suggestion; **Send called shot** delivers.
During travel **HARD**, **CLEAN**, and **OFF** control AI brushing. Default keys
are H / C / O; **Settings → Call shortcuts** remaps them. Key repeats are ignored.
A manual call speaks immediately when device speech is enabled; turning speech
off stops the current utterance. Visual calls always remain. Weight zones 1–3
are guards, 4–6 the front rings, 7 tee, and 8–10 the back rings. In other
positions, follow the AI skip's text/symbol call and scrub or hold to sweep.
Device speech is optional and depends on an installed English voice; the visual
call is always present. Lead/second/vice use the sweeper view during teammate
shots; the caller watches from behind the broom. Camera remains manually selectable. Settings → Steady overhead after release
(Auto) keeps the traveling-stone view stationary when Auto is selected. Ready
and held delivery views keep the handle visible; explicit manual cameras still
work. This preference is independent of FOV, zoom and fast watching.

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
