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

Before your delivery, the AI skip now calls a shot for you too. The **SKIP'S CALL**
card stays visible through the slide and shows the shot type, named weight,
target distance left/right and short of/behind the tee, and requested curl.
Its overhead map marks the intended target with a gold cross and the broom with
a dark bar; these can differ because the stone curls. Left/right is viewed from
your delivery end. The card includes the solved near-hog pace; slide feedback
compares your push with it as light, close (within 0.06 m/s), or heavy. This is
push feedback; release timing and the finishing gesture still affect the shot.
A gold ring also marks the target on the rink. Wait for the
call, then throw with the usual gesture; the call never releases your stone.
The call and target survive an interrupted held delivery. After release, the
skip's sweeping calls take over and use that intended target.

When you are the skip (vice while the skip delivers), **drag the broom** to
choose the line. Call **Draw weight**, **Guard weight**, or **Takeout weight** and
select **In-turn · curl right** or **Out-turn · curl left** (right-handed delivery,
directions viewed from the delivery end). A short arrow beside the broom shows
curl direction only: there is no predicted path or landing marker. Changing turn
or weight preserves your broom placement. The standard weight calls use the
existing solver for tee draw, centre guard depth, or takeout pace; judging the
line remains your job. The wider house view includes the guard area.
**Suggest a shot** optionally asks the AI to place a broom and choose weight/turn;
you can adjust that suggestion. **Send called shot** delivers.

A faint ghost broom and dashed ring recall your team's most recent clean shot's
actual broom and resting stone, with weight and curl direction in the caption.
The result includes whatever sweeping happened. Any contact during that delivery
suppresses its reference; a later moved/removed stone, new end, new match or
reload clears it. These are session-only observation aids, not forecast markers.

After a Gold shot, the result waits for **Continue**, with the thinking clocks
paused so you can inspect the house or open the ice board. **Settings → Wait
after your team's shots** restores the old two-second automatic continuation
when switched off. Cyan's shots still continue automatically. This also works
when a settled shot is restored from a save. End cards wait for Next end/Rematch.

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
