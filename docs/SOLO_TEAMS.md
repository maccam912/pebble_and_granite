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

**AI difficulty** has three tiers. All use the same physics and a bounded
catalogue of draws, guards and contact shots (see the catalogue below). Club
evaluates one shot. Competitive
checks the opponent's best reply to its two strongest distinct shot intentions;
Elite checks four and penalizes brittle shots with four fixed execution samples.
Both turns are evaluated before shortlisting each target/type. Search ends at the
end boundary; there is no full-game tree or calibrated win probability.

Position values account for match score, end number, hammer and stones left, with
actual terminal wins taking priority. Early blanks can retain hammer; a final-end
winning point overrides that preference. Guard value changes with the stone
owner's lead. These are explicit game heuristics, not measured curling odds.
The executor adds
centered bounded speed, line and rotation scatter with these maximum bounds:

| Tier | Speed | Line at tee | Rotation |
| --- | --- | --- | --- |
| Club | 100 mm/s | 360 mm | 0.045 turns/s |
| Competitive | 40 mm/s | 150 mm | 0.022 turns/s |
| Elite | 12 mm/s | 45 mm | 0.008 turns/s |

These are provisional game tuning values, not measured human accuracy ratings.
The planner forecasts the visible board on a standard-sheet estimate and
calibrates delivery from observed clean draws; it cannot read hidden ice cells. Planning runs off the render thread.
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

New matches give every player a separate brush and fatigue history. Two sweepers
work ahead of the stone, with the thrower and caller normally leaving the two
remaining teammates to brush. A human who is not calling can still follow their
own delivery; the fresher available teammate at release partners them for the
whole shot. Human input keeps its own effort and position, while the AI partner
obeys the skip's call. You can select a moving contact stone while your partner
continues brushing the delivered stone. Calling-only controls two AI sweepers. Full-team mode has
manual brushing and explicit calls, with no automatic effort after OFF.

Both brush heads are visible and the call panel names the active players, marking
them as tiring when fatigue is high. Animation and brush sound use each player's
accepted effort/fatigue. Rest recovers fatigue; it carries across deliveries and
ends, and restores from the journal. Behind the tee, the authority accepts only
one brush per team, with stable player ordering.

New sessions use model 4 and online protocol 12. Existing model-3/rules-4 saves
continue with their original combined team brush and exact replay hashes; start
a new match to get independent team brushes. Archived installed Android practice
and solo journals and every-tick model-3 traces guard this compatibility.

Individual teammate personalities, deeper stochastic strategy, richer uncertainty
models, coaching and career remain future work. Mixed-doubles online retains its
separate per-player brushes. Fatigue strength and audible quality still need
human evaluation and measured calibration.

Physical Android performance/feel, human curling judgement and measured ice
calibration remain separate validation gates.

### Physical shot catalogue (27 October 2026)

The bounded search now also offers corner guards, freezes, tap-backs,
hit-and-rolls, peels, doubles and runbacks. It keeps at most 32 candidate releases
per board. These are geometry proposals validated through the same authoritative
physics and legal remedies as ordinary play. A proposed roll must remove its
opponent and leave the shooter in the house with at least 30 cm lateral movement;
a peel must remove both; a double must remove both named opponents. A runback
requires an actual first-to-second contact and removal or at least 30 cm movement
of the second stone. Freeze gaps are at most 15 mm with less than 8 cm target
movement; taps move their target 15 cm to 1.5 m forward. Failed intentions are
excluded, even if they happen to have a useful score. Execution scatter can still
miss the selected intention.

Contact options use a bounded selection of nearby house stones and guards, not
an exhaustive search of every combination. Calls retain their names through held
save/restore, use the existing three weight categories, and show the solved pace.
Human callers still choose their own draw/guard/takeout line and turn. No new
command, replay, physics or multiplayer protocol version is required.

### Observed ice learning (27 October 2026)

Planning and live weight advice no longer read the real ice seed, heat or wear.
Tactical search uses a standard-sheet forecast. After choosing an intention,
the skip adjusts line and draw weight using up to eight clean observed draws
within 80 cm of the target lane, from this or the previous end. It compares the
observed endpoint and curl against a standard-sheet rollout with that shot's
actual release, so inaccurate player aim is not mistaken for an ice error.
Two prior-equivalent observations reduce corrections when evidence is sparse.
Weight corrections are bounded to 0.10 m/s and line corrections to 25 cm before
projection to the broom; ordinary input bounds still apply. Hit weight stays
fixed, while its line can adapt. This is a local calibration heuristic, not a
Bayesian surface map or a probability of making the shot.

Swept shots, contacts, faults, out-of-play outcomes and unusual release weights
or rotations do not train the estimate. Accepted late brush commands also mark
a shot as swept. The call card says “still learning” or shows the number of clean
draws used. Observations rebuild from accepted journals, so reloads do not forget
them; new matches start empty. Call names and observation counts survive held
save/restore, while older saves remain supported.

A synthetic warm-sheet fixture reduced a 383 mm miss to 145 mm after four
observations. Tests verify hidden-ice independence at all three tiers, rejection
of contaminated/old/distant observations, and identical learning after journal
replay. These are simulation tests, not measured real-ice calibration or human
playtest approval. Rapid local heating can still surprise this limited model.
