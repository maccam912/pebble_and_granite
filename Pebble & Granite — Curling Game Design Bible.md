# Pebble & Granite — Curling Game Design Bible

Oct 25, 2026 · @Matthew Koski

## Vision and pillars

Build the curling game where weight, line, ice reading and sweeping decide every shot, and where real curlers say "that's curling." Underneath sits one deterministic stone simulation shared by the client, the server, the AI and replays; Godot only draws it.

**Pillars**

- **Weight is the skill.** Release speed consistency dominates real curling. Input must be analog, learnable and honest, with noise the player can read after each throw.
- **No sliders.** Nothing in play is set with a slider, meter or power bar. Every throw is a hand-like stroke on the stone, and every choice is a gesture on the stone, the broom or the ice, or a call.
- **The ice is a character.** Speed and curl differ by path and drift through a game. Reading and re-reading it is rewarded.
- **Sweeping is agency during the wait.** A stone takes roughly 25 seconds to reach the target ([Uppsala](https://www.uu.se/en/press/press-releases/2013/2013-05-13-the-mechanism-that-puts-the-curl-in-the-curling-stone-revealed)); sweepers and the skip act through all of it.
- **Chess on ice.** Hammer, free guard zone, no-tick and thinking time make strategy real. The AI plays real strategy, not rubber-banding.
- **Every throw is reproducible.** A throw is a release record plus sweep inputs. Same inputs, same result, bit for bit, on every platform.
- **Spirit of curling.** Handshakes, concession, self-reported burned stones and opponent sweeping behind the tee line are part of play, not flavour text.

**What "feel" means here** — three testable things:

1. Stone motion hits calibrated targets (draw times, curl, rotations, collisions) within set tolerances.
2. The same input gives the same output; execution noise is small, consistent and explained after the throw.
3. Camera, audio, haptics and readouts are driven by the sim state (speed over pebble, sweep heat, impulse), so the senses agree with the physics.

**Audience and platforms**: sports-sim players, club and competitive curlers, and friends playing couch or online. PC first with trackpad and mouse, then touch on mobile; gamepad support is optional and later. "Pebble & Granite" is a working title.

## Curling as a skill system

A shot has four controllable parts — weight, line, turn and sweeping — split across a thrower, two sweepers and a skip. The game must expose each part as its own skill with its own feedback, because that division of labour is what makes curling a team sport.

**Core loop for one stone**

1. The skip reads the house and the ice, calls the shot (type, weight, turn) and sets the broom as the target line.
2. The thrower pushes from the hack, slides, and releases before the near hog line with a set rotation.
3. Sweepers time the stone, judge weight, and sweep or hold; the skip judges line and calls sweeping.
4. Stones collide and settle; the rules engine resolves hogged, out-of-play and free-guard-zone violations.
5. Both teams update their picture of that path ("falling," "keener than we thought").

An end is 16 stones (10 in mixed doubles, plus 2 positioned); a game is 8 or 10 ends with a thinking-time clock per team.

| Skill | Real-world form | In-game expression | Feedback shown after |
| --- | --- | --- | --- |
| Weight | Release speed; draw release is about 2.0–2.1 m/s on decent ice ([Paulley, citing Yang et al.](https://glennpaulley.ca/curling/2026/07/06/mapping-delivery-split-times-to-hog-to-hog-times/)) | Analog leg drive and arm extension | Release speed, back-line-to-hog split, hog-to-hog time |
| Line | Aim at the skip's broom | Body alignment and steadiness through the slide | Line error at the far hog, in cm |
| Turn | In-turn or out-turn; about 2–3 rotations per trip ([Uppsala](https://www.uu.se/en/press/press-releases/2013/2013-05-13-the-mechanism-that-puts-the-curl-in-the-curling-stone-revealed)) | Turn choice plus handle twist at release | Rotation count, under/over-turn flag |
| Weight judgment | Sweepers' read of speed, helped by split times | Sweeper estimate of stop zone | Called zone versus actual zone |
| Sweeping | Heat and clean ice in front of the stone | Rhythm, pressure and position input | Distance and curl added by sweeping |
| Ice reading | Path-by-path notes on speed and curl | Team ice board and personal path notes | Predicted versus actual path overlay |
| Strategy | Shot calling with hammer, score and end | Skip call screen and broom placement | Win probability before and after the shot |

## Game modes

Every mode is the same match engine with a different assignment of roles to humans and AI. Mixed doubles is the first online mode to ship: two players per side cover thrower, sweeper and skip naturally, and it needs only four humans.

| Mode | Humans | Human controls | AI controls |
| --- | --- | --- | --- |
| Full control (single player) | 1 vs AI | Every throw, sweep and call | Opponent team |
| Skip mode | 1 vs AI | Calls, broom, sweep calls | Throwers and sweepers, by skill rating |
| Position mode | 1 vs AI | One position (for example lead): own throws, sweeping for teammates | Rest of both teams |
| Practice and drills | 1 | Draws to targets, takeouts, last stone draw, split-time trainer | Optional sweepers |
| Scenarios | 1 | Late-end puzzles from a set position, ice and clock | Opponent |
| Daily challenge | 1 | Same seeded ice and scenario for everyone | Opponent |
| Career | 1 vs AI | Full control or skip mode through club, bonspiels, provincials, nationals, worlds | Opponents, travelling ice conditions |
| 1v1 versus | 2 | Each player runs a whole team | Optional AI sweepers |
| Mixed doubles | 2v2 | One player throws stones 1 and 5, the other 2–4; the non-thrower holds the broom, and both may sweep after release | None |
| Team (4v4) | Up to 8 | Lead, second, vice, skip; thrower, two sweepers, broom holder each stone | Fills empty seats |
| Couch | 2–4 local | Any of the above, split by role | Fills gaps |
| Spectate and replay | Any | Camera, timeline, overlays | — |

**Role rotation in team play.** Each player throws two consecutive stones per end. The two non-throwing, non-broom players sweep. When the skip throws, the vice holds the broom ([WCF Rules R3–R4](https://worldcurling.org/wp-content/uploads/2026/08/Rules2026.pdf)).

**Non-delivering team.** Its skip or vice may sweep the opponent's stone, but only once it passes the tee line ([R8](https://worldcurling.org/wp-content/uploads/2026/08/Rules2026.pdf)). This gives the defending skip a real-time input in every throw.

**Mixed doubles specifics** ([R17](https://worldcurling.org/wp-content/uploads/2026/08/Rules2026.pdf)): 5 delivered stones per team per end, 8 ends, two positioned stones placed before each end, one Power Play per team per game, and no stone may be removed from play before the fourth delivered stone.

## Delivery and controls

The delivery is one continuous stroke — press, pull back, push, hold, lift — where the pointer or finger is the hand on the handle. Trackpad, mouse and touch share the same stroke. Nothing like a meter, slider or number appears during the throw; players read it from the thrower's body and the slide, as a curler does.

**No-sliders rule.** No sliders, meters or power bars anywhere in play. Every choice is direct manipulation of the stone, the broom, the ice or the thrower, or a call. Sliders exist only in the settings menu (audio volume) and in developer builds.

**The stroke**

1. **Set up.** Tap the left or right side of the handle to choose in-turn or out-turn; the handle swings to 10 or 2 o'clock. The thrower lines up on the skip's broom automatically. When skipping, you aim by dragging the broom itself on the ice. Right-handers deliver from the left hack ([R5c](https://worldcurling.org/wp-content/uploads/2026/08/Rules2026.pdf)).
2. **Grip and pull back.** Click and hold (or put a finger on the stone), then drag toward you. The body rocks back in the hack. This sets rhythm, not weight.
3. **Drive.** Reverse into a forward stroke. How fast the finger moves through the drive sets leg drive, which is most of the weight. Speed matters, not distance, so a small trackpad is no limit.
4. **Slide.** Out of the hack, the body glides and slows on its own; the player holds steady. Small forward or back nudges extend or pull the arm, worth a few percent of weight. Sideways drift turns the body off line.
5. **Lift.** Let go before the near hog line, or the stone is removed ([R5e](https://worldcurling.org/wp-content/uploads/2026/08/Rules2026.pdf)). A still finger at release gives a clean 2–3 rotations. Still pushing forward at release adds speed and scatter — the real "pushing the stone" fault — so the game teaches actual technique.

The skill — the gentle QWOP — is a repeatable drive speed and a quiet slide. Weight is the hard part, as in real curling.

**Devices**

| Device | Grip | Release | Notes |
| --- | --- | --- | --- |
| Trackpad (primary) | Held click: physical press, tap-and-drag, or three-finger drag on macOS | Let go of the click | A trackpad cannot report finger lift unless a click is held |
| Mouse | Click and drag | Button up | Most travel; same stroke |
| Touch (mobile) | Finger on the stone | Finger up | Real finger-down and finger-up; the finger is literally on the handle |
| Gamepad (optional, later) | Hold a trigger; stick for pull and push | Trigger up | Not required; same stroke mapped to stick and trigger |

**What keeps it from being masochistic**

- Line is aimed at the broom for you, and small sideways drift falls inside a dead zone sized by the difficulty preset.
- More rotation does not give more curl ([The Conversation](https://theconversation.com/the-slippery-science-of-olympic-curling-we-still-dont-know-how-it-works-176463)), so a "good enough" release really is good enough.
- Releasing early costs nothing; the hog line glows and ticks as the thrower approaches.
- After each throw, the stroke is drawn as a faint trace beside the trace of the player's last good draw. That comparison is how players learn to repeat a speed.

**Input pipeline: from stroke to release**

1. Read pointer or touch motion every frame, normalized to physical distance so screen size and DPI do not change weight.
2. At each 240 Hz sim tick, hold the latest sample and quantize it to integers. From here on everything is fixed-point and deterministic. Godot updates input once per rendered frame, so several ticks may share a sample; all mapping runs in ticks, never frame time, so 30 fps and 144 fps give the same weight for the same motion.
3. Drive speed is forward travel over the drive window divided by its duration — an average, not a peak — passed through a response curve that spends most of a comfortable stroke range on guard-to-back-house weights and puts hit weights at the top.
4. Slide nudges add a small arm-extension trim.
5. At lift, remaining forward finger speed adds push (speed plus noise), and sideways speed adds line error and lowers rotation.
6. Only the resulting release record (integer velocity, angle, spin) goes to the network; the stroke itself never does.

**Why averaging matters.** Weight is extremely sensitive: by a constant-deceleration estimate (2 m/s release, 0.07 m/s²), each 0.01 m/s of release speed moves the stopping point about 28 cm. Landing in the button (±15 cm) needs about 0.005 m/s, roughly 0.25% of release speed. Averaging a whole stroke gives that resolution and rewards smooth motion over a lucky instant.

**Calibration through play, not settings.** Operating-system pointer acceleration and device differences make raw finger speed inconsistent between machines. Pre-game practice throws fit a per-device gain so a comfortable medium stroke is draw weight, mirroring real pre-game practice. Calibration updates quietly whenever the device changes.

**Execution noise.** Add small noise to release speed, line and rotation, scaled by the difficulty preset and by stroke smoothness (jerk). Never add hidden noise the player cannot attribute to something they did.

**Release report** after the stone comes to rest: release speed, back-line-to-hog split, hog-to-hog time, rotations, and line error at the far hog. Curlers already use splits as a speed proxy, and mapping splits to hog-to-hog times depends on ice friction ([Paulley](https://glennpaulley.ca/curling/2026/07/06/mapping-delivery-split-times-to-hog-to-hog-times/)), so the report doubles as an ice-reading lesson.

**Aids by preset**: Arcade draws a predicted path on the ice before the throw and widens the line dead zone. Club shows the broom, the stroke trace and a split timer. Sim shows only the release report.

**Developer tuning (never shipped)**: device gain, response-curve shape, drive window, slide deceleration, arm-trim range, line dead zone, noise sigmas, and release-cue timing. Tune these with real curlers in the room.

## Sweeping

Model sweeping as heat added to a field of ice cells in front of the stone, which lowers friction and curl under the running band as it passes. That one mechanism gives the real behaviour for free: sweeping carries a stone further and straighter, and sweeping late in the path matters more for curl because curl concentrates at low speed.

**What the evidence says**

- Sweeping raises the ice surface temperature, which lowers stone–ice friction; temperature is the dominant effect and polishing is minor ([leancurling summary of Marmo et al. 2006](https://leancurling.com/sweeping-science/why-do-we-sweep)).
- Even vigorous sweeping does not melt the ice; it warms the surface by about 1.5 °C ([Physics World on Jenkyn](https://physicsworld.com/a/sweeping-away-myths-about-curl/)).
- Sweeping along the stone's direction of travel increased stone distance 33% more than sweeping across it, in a study of elite Korean athletes ([Kim et al. 2021, summarised by Lean Curling](https://www.leancurling.com/sweeping-angle/)).
- Directional "steering" with aggressive fabrics was curtailed by World Curling's 2016 brush rules, so model only small directional effects ([leancurling](https://www.leancurling.com/why-sweep/)).
- Sweeping lowers curl in the improved pivot-slide model ([Mancini and de Schoulepnikoff 2019](https://infoscience.epfl.ch/record/272732)).

**Heat-field model** (per ice cell, in the sim)

```latex
\Delta T_{cell} \mathrel{+}= k_s \cdot P \cdot r \cdot c \cdot \Delta t \qquad \Delta T_{cell} \leftarrow \Delta T_{cell} \cdot e^{-\Delta t/\tau}
```

P is brush pressure, r stroke rate, c the fraction of the cell covered by the brush head, and τ a cooling time constant. Cap ΔT near the measured ceiling (about 1.5 °C). The stone's friction and curl terms read the mean ΔT under the running band.

**Input per sweeper**

- **Scrub.** Hold a click (or a finger on touch) and scrub back and forth on the ice just ahead of the stone. Scrub rate maps to stroke rate r; scrub length and speed map to effort P.
- **Position.** Where you scrub matters: heat only helps if the running band passes over it before it cools, so scrub close ahead of the stone and centred on its path.
- **Fatigue.** Sustained hard sweeping tires the sweeper. It shows in breathing and a slowing brush, never a bar, and recovers between stones, so teams budget effort across an end.
- **Clean.** Short, light scrubs clear debris and frost with little heat.
- **Hold-to-sweep.** For accessibility or preference, hold the click to sweep at steady effort and let go to stop.
- In full-control single player, one scrub drives both brushes. A gamepad, if added later, uses stick oscillation for the same inputs.

**Calls**: "Hurry" and "hard" (sweep), "off" and "whoa" (stop), "clean." Sweepers call weight in zones; the skip calls line.

**Rules enforced** ([R8](https://worldcurling.org/wp-content/uploads/2026/08/Rules2026.pdf)): own team anywhere in front of the far tee line; behind it, one sweeper per team, and only the skip or vice of the non-delivering team; opponents may start only once the stone reaches the tee line; sweeping must finish to the side and must not leave debris in front of the stone.

**Single-player support**: AI sweepers judge weight from a noisy split-time estimate and obey the player's calls, so a player in skip mode controls sweeping by voice-style commands alone.

## Communication and team play

Give teams a small, fast call vocabulary that works without voice chat and sounds like a curling rink when used. Strangers online should be able to play a coordinated end with quick-calls alone; friends on voice get the same calls as on-screen confirmation.

| Call type | Who makes it | When | Input | What others see and hear |
| --- | --- | --- | --- | --- |
| Shot call | Skip (vice when skip throws) | Before delivery | Call wheel: shot type, weight zone, turn | Card over the house; skip's voice line |
| Broom target | Skip | Before delivery | Place the broom on the ice | Broom marker the thrower aims at |
| Line call | Skip | During travel | Hold: sweep / off | Shouted "hurry" or "off"; icon on stone |
| Weight call | Either sweeper | During travel | Tap zone 1–10 | Zone number over sweeper |
| Sweep effort | Sweepers | During travel | Their own sweep input | Brush animation and audio |
| Ice note | Anyone | Between stones | Pin a note to a path | Team ice board, persists through the game |
| Time-out | Any player on the delivering team | When their clock runs | Menu | 60 s team time-out ([C7](https://worldcurling.org/wp-content/uploads/2026/08/Rules2026.pdf)) |

**Weight zones.** Use a 1–10 scale for stop position: low numbers for guard zones short of the house, higher numbers moving back through the house, with hit weights named separately (board, control, peel). Show the zone legend in the tutorial and on the call wheel.

**Shared ice board.** A per-team chalkboard of the sheet where each path carries notes and the last few observed curls. AI teammates write to it too, which teaches players to read ice by example.

**Etiquette as mechanics.** A handshake before and after; concede only on your own delivery turn ([R12i](https://worldcurling.org/wp-content/uploads/2026/08/Rules2026.pdf)); a prompt to self-report a burned stone, with the non-offending team choosing the remedy as the rules provide.

## Stone physics model

Use a calibrated empirical model of stone motion, not a first-principles one. Science has not settled why stones curl — scratch-guiding, pivot-slide and left–right friction asymmetry all have experimental support — so the game needs a model that reproduces the measured behaviour and exposes tunable parameters.

**Competing explanations** (for the research track, not the runtime)

- Scratch-guiding: the stone's rough band scratches the pebble and the scratches steer it ([Nyberg et al. 2013, Uppsala](https://www.uu.se/en/press/press-releases/2013/2013-05-13-the-mechanism-that-puts-the-curl-in-the-curling-stone-revealed); supported by [Honkanen et al. 2018](https://link.springer.com/10.1038/s41598-018-26595-y)).
- Pivot-slide: the band briefly sticks to pebbles and pivots thousands of times per trip ([Shegelski and Lozowski, via UNBC](https://www.unbc.ca/newsroom/unbc-stories/researchers-discover-why-curling-rocks-curl)); refined so curl depends on velocity ([Mancini and de Schoulepnikoff 2019](https://infoscience.epfl.ch/record/272732)).
- Left–right asymmetry: friction rises as speed falls, so the slower side forms pivot points ([Murata 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC9440934)).

**Behaviour any model must reproduce**

- A clockwise stone curls right — the opposite of a spun glass on a table ([The Conversation](https://theconversation.com/the-slippery-science-of-olympic-curling-we-still-dont-know-how-it-works-176463)).
- More rotation does not give more curl; spun too hard, a stone barely curls (same source).
- About 2–3 rotations over a roughly 25 s trip ([Uppsala](https://www.uu.se/en/press/press-releases/2013/2013-05-13-the-mechanism-that-puts-the-curl-in-the-curling-stone-revealed)).
- Lower release speed gives more final curl; sweeping gives less ([Mancini and de Schoulepnikoff 2019](https://infoscience.epfl.ch/record/272732)).
- Friction coefficient between about 0.006 and 0.016, falling as speed rises ([Li et al. 2022](https://doaj.org/article/e3e504e211f546ae8ffe3acb573e39c4)).

**State per stone**: position (x, y), velocity (vx, vy), angular velocity ω, handle angle θ (for rendering), and fixed per-stone constants: mass (17.24–19.96 kg allowed, [R2](https://worldcurling.org/wp-content/uploads/2026/08/Rules2026.pdf)), radius 0.142 m (World Curling's official measuring radius, [C8](https://worldcurling.org/wp-content/uploads/2026/08/Rules2026.pdf)), and running-band multipliers for friction and curl.

**Equations of motion** (v = speed, t̂ = direction of travel, n̂ = its left normal)

```latex
\mathbf{a} = -\mu(v,\,\text{ice},\,\Delta T)\, g\, \hat{t} \;+\; \operatorname{sgn}(\omega)\, K(\text{ice},\,\text{stone},\,\Delta T)\, f(v)\, h(|\omega|)\, \hat{n}
```

```latex
\mu(v) = \mu_0 \left(1 + \frac{c_\mu}{v + v_0}\right) \qquad f(v) = \frac{1}{v + v_1} \qquad \frac{d\omega}{dt} = -\beta(v)\,\omega
```

Sign convention: clockwise ω (seen from above) curls right. h(|ω|) is near 1 across normal rotation rates, drops toward 0 for very fast spin, and turns noisy for near-zero spin (a "dumped" handle). All terms are rational functions so the fixed-point sim needs no transcendental math.

**Why friction must rise at low speed.** With constant deceleration of 0.07 m/s², a draw to the tee crosses hog-to-hog in 14.9 s but takes 28.5 s from hog to stop (computed for this doc from WCF sheet geometry). Club "ice times" from hog to stop run about 18–25 s ([Cedar Rapids Curling Club](https://cedarrapidscurling.com/index.php/component/content/category/14-curling-info)), and a good draw takes 24–25 s on good ice ([Scottish Curling-Ice Group](https://mail.gncc.org/images/pdfs/Training/SCIG_Good_Ice_November2006.pdf)), so real stones stop faster at the end.

**Collisions.** Impulse-based circle–circle contact with swept-circle time of impact, so no speed can tunnel through a stone. Add tangential friction at the striking band so contact transfers spin and bends the struck stone's path ("throw"), which matters for hit-and-rolls, doubles and runbacks. Resolve simultaneous contacts in a fixed order (by stone id) so results are deterministic. No reliable published restitution value turned up; textbook problems use 0.8 ([example](https://vaia.com/en-us/textbooks/physics/engineering-mechanics-dynamics-14-edition/chapter-15/?page=4)), so measure it from video.

**Integration.** Semi-implicit Euler at 240 Hz, fixed step. A stone snaps to rest below a small speed threshold, and its ω is zeroed with it.

**Calibration targets** (golden tests in CI; tolerances to be set after first playtests)

| Target | Value | Source |
| --- | --- | --- |
| Draw release speed | 2.0–2.1 m/s on decent ice | [Paulley, citing Yang et al. 2023](https://glennpaulley.ca/curling/2026/07/06/mapping-delivery-split-times-to-hog-to-hog-times/) |
| Draw hog-to-hog time | About 14–15 s typical; about 15 s at Beijing 2022 | [Paulley](https://glennpaulley.ca/curling/2026/07/06/mapping-delivery-split-times-to-hog-to-hog-times/) |
| Back-line-to-hog split for a draw | 3.5–4.3 s range; about 4.1 s for a 15 s hog-to-hog | [Paulley](https://glennpaulley.ca/curling/2026/07/06/mapping-delivery-split-times-to-hog-to-hog-times/) |
| Curl on a draw | 3–4 ft (0.9–1.2 m); 4 ft on good ice | [Curling Canada](https://www.curling.ca/wp-content/uploads/2025/01/Week5-LineofDelivery.pdf), [SCIG](https://mail.gncc.org/images/pdfs/Training/SCIG_Good_Ice_November2006.pdf) |
| Rotations per trip | 2–3 | [Uppsala](https://www.uu.se/en/press/press-releases/2013/2013-05-13-the-mechanism-that-puts-the-curl-in-the-curling-stone-revealed) |
| Friction coefficient | 0.006–0.016, falling with speed | [Li et al. 2022](https://doaj.org/article/e3e504e211f546ae8ffe3acb573e39c4) |
| Sweep surface warming | Up to about 1.5 °C | [Physics World](https://physicsworld.com/a/sweeping-away-myths-about-curl/) |
| Restitution, spin transfer | Unknown — measure | Club stream video (see below) |

**Calibration data: the club's streams.** Wausau Curling TV streams every game on every sheet ([example: Sheet 4, 17 March 2026](https://www.youtube.com/watch?v=es9urvYvLiE)). Each frame carries two near-overhead house cameras plus two angled end views. A test on one 1280×720 frame found both rings and all five visible stones automatically, at about 13 mm per pixel (a stone is about 21 px across). On the unobstructed house, the 12-ft-to-4-ft ring ratio came out at 3.02 against the rules' 3.00, so the overhead views are close to true top-down.

What the streams can supply:

- **Collisions in the house**: restitution, spin transfer and throw angles — the data no published paper provides.
- **Low-speed friction and late curl**: the last few metres of a draw, where friction rises and curl concentrates, sit inside the house view.
- **Rest positions after every stone**: a large dataset of club-level shot outcomes and execution scatter for the AI.
- **Ice change through a game**, path by path.

**Limits.** The overhead views show only the house, so release speed and hog-to-hog times need the angled end views (not yet confirmed) or separate filming. Rotation rate is marginal at this resolution. Players and brooms hide stones, so ring and stone fits must be robust to occlusion (one house in the test was partly blocked by a player and gave a ring ratio of 2.83).

**Getting the video.** Downloads from cloud servers hit YouTube's bot check. The cleanest source is the club itself: raw recordings without overlays or stream compression, with permission for bulk use. Fit parameters in Python against the tracks; the [Digital Curling](https://minerva.cs.uec.ac.jp/cgi-bin/curling/wiki.cgi?page=SI_02) fcv1 simulator is a second reference for shot outcomes.

## The ice

The ice is deterministic state: a global climate plus a grid of cells over the sheet, both evolving from a seed and from every stone and sweep. Paths therefore change through a game in reproducible ways, and reading them is a skill — the same thing real teams do between shots.

**Global climate** (per venue, drifting slowly through a game)

- Ice surface temperature: about −4.0 °C averaged over 300 games at Gangneung ([Kim et al. 2021](https://pmc.ncbi.nlm.nih.gov/articles/PMC7835804)); −4.5 °C in World Curling's arena example ([Curling Ice Explained, arena chapter](https://www.curling.ca/wp-content/uploads/2010/01/Arena_Curling.pdf)).
- Air temperature at 1.5 m and humidity, giving a dew point. The arena example pairs 8 °C air with a dew point of −4.3 °C (same source).
- Frost forms when the dew point sits above the ice surface temperature; ice technicians aim to keep the two equal ([USA Curling ice techs via Fluke](https://fluke.com/en/learn/blog/hvac/a-slippery-slope-not-for-curlings-ice-technologists)). Crowds, open doors and wet weather push humidity up.

**Per-cell fields** (5 cm cells give about 914 × 95 ≈ 87,000 cells on a 45.72 × 4.75 m sheet)

| Field | What changes it | Effect on a stone passing over | Basis |
| --- | --- | --- | --- |
| Pebble height and density | Seeded at pebbling; worn by stones and brushes | Curl potential and base friction | Pebble abrasion by brushing alters later shots on the same path ([Paulley](https://glennpaulley.ca/curling/2026/07/06/mapping-delivery-split-times-to-hog-to-hog-times/)) |
| Frost thickness | Grows when dew point > ice temperature; cleared by stones and sweeping | Raises friction (heavy ice); adds debris for picks | Frosty ice gives short ice times ([Cedar Rapids](https://cedarrapidscurling.com/index.php/component/content/category/14-curling-info)) |
| Sweep heat ΔT | Sweeping; decays over seconds | Lowers friction and curl | See Sweeping |
| Debris | Frost flakes, brush fibres; cleared by "clean" sweeping | Small chance of a pick | Debris includes frost and brush material ([WCF glossary](https://worldcurling.org/wp-content/uploads/2026/08/Rules2026.pdf)) |
| Level (slope) | Fixed per sheet and seed | Slow drift toward the low side ("falls") | Design choice |

**Design choices to tune, not facts.** The direction and size of pebble-wear effects (straighter, faster or slower paths) need club measurement. Expose them as per-venue profile parameters and calibrate.

**Picks.** A pick is debris caught under the running band that throws a stone off line. Model it as a rare, seeded event whose chance rises with debris in the cell and falls with clean sweeping. Ranked play offers Off, Rare and Realistic.

**Stones.** Each stone carries friction and curl multipliers from its running band, and stones are matched in pairs. Players can learn that "stone 6 runs swingy" — a real pre-game practice habit.

**Ice profiles**

| Profile | Character | Variability through the game |
| --- | --- | --- |
| Club | Heavier; frost at the edges; uneven paths | High |
| Arena | Crowd heat and humidity; frost risk late | Medium to high |
| Championship | Keen and true; about a 4 ft draw curl | Low |

**Between games and ends.** Pre-game practice is 9 minutes per team at World Curling events (7 for mixed doubles), and the slide path may be re-pebbled after it ([C4](https://worldcurling.org/wp-content/uploads/2026/08/Rules2026.pdf)). Make practice a playable phase where teams gather ice notes before the last stone draw.

**Visual tells.** Frost haze where traffic is light, polished shine on heavily used paths, and pebble sparkle under the lights let an observant player read the ice before throwing.

## Determinism and the sim core

Write the stone and ice simulation as a standalone, fixed-point library outside Godot's physics, and let Godot only render it. Curling needs custom friction, curl and sweep forces that no rigid-body engine provides, and the same code must run in the client, a headless server, the AI's search rollouts and the replay checker.

**Options, weighed on their merits**

| Option | Determinism basis | Strengths | Weaknesses |
| --- | --- | --- | --- |
| Rust crate + [godot-rust (gdext)](https://github.com/godot-rust/gdext) | Integer fixed-point (Q32.32 in i64) | Native speed for AI search; same crate builds the client extension, a server with no Godot, and Python bindings for calibration | Extra build pipeline per platform; FFI boundary to design |
| C# + [Klotho](https://godotengine.org/asset-library/asset/5234) | 32.32 fixed-point, seeded RNG, state hashing | Rollback, lockstep, authoritative server, replay and a plain .NET server out of the box | Needs Godot .NET; young project (0.2.x, June 2026) |
| C++ GDExtension | Integer fixed-point | Full control, no extra language | Most room for undefined behaviour; slower iteration |
| GDScript only | 64-bit floats | Fastest to prototype | Too slow for AI search; float determinism across platforms not guaranteed |
| [Godot Rapier](https://godot.rapier.rs/) | IEEE-754 float, cross-platform deterministic mode | Drop-in rigid bodies | Curling forces are custom anyway; relies on compiler float discipline |

**Recommendation: the Rust crate.** The deciding factor is the AI: shot search needs tens of thousands of simulated throws per decision, and the server should not need an engine. Klotho is the strongest alternative if you would rather stay in C#. Prototype the model in GDScript or Python first, then port once the curl law is tuned.

**Why Godot's own physics is out.** Community guidance is not to rely on Godot physics for determinism, especially across platforms and compiler settings ([Godot forum](https://forum.godotengine.org/t/making-physics-fully-deterministic/22575)).

**Number format.** Q16.16 resolves only 15 µm and can drift up to 11 cm over a 30 s throw at 240 Hz (7,200 steps of one-unit rounding). Q32.32 in i64 resolves 0.23 nm and leaves ample headroom; use i128 for intermediate products. Integer square root is exact and portable.

**Determinism rules for the crate**

- No floats in sim state or sim math. Floats exist only on the render side (interpolation, rotation visuals).
- No transcendental functions in the step. Per-tick decay factors (sweep cooling, spin decay) are precomputed fixed-point constants.
- One seeded PRNG stream per throw (for picks and execution noise), keyed by match seed and stone index.
- Fixed iteration order everywhere: stones by id, contacts sorted by (time of impact, id pair).
- Fixed tick of 240 Hz; render interpolates between the last two ticks.

**Crate API sketch**

```rust
struct ThrowSpec { stone: StoneId, release_tick: u32, pos: Vec2Fx, vel: Vec2Fx, omega: Fx }
struct SweepInput { tick: u32, sweeper: u8, pressure: u8, rate: u8, offset: i8 }

impl Sim {
    fn new(ice: IceSeed, stones: &[StoneParams]) -> Self;
    fn release(&mut self, t: ThrowSpec);
    fn step(&mut self, sweeps: &[SweepInput]) -> StepEvents; // contacts, line crossings, rest
    fn snapshot(&self) -> Snapshot;
    fn restore(&mut self, s: &Snapshot);
    fn hash(&self) -> u64; // over canonical bytes
}
```

**Verification.** CI runs golden throws on Windows, Linux, macOS (x86 and ARM) and wasm, and compares per-tick hashes. Any mismatch fails the build. Property tests check conservation in collisions and that no stone ever overlaps another after a step.

## Netcode

Replicate inputs, not positions, and re-simulate each throw from its release tick whenever a late input arrives. Curling is turn-based with exactly one real-time input stream per throw — sweeping — so this is far simpler than general rollback and needs no snapshot ring buffer.

**What goes over the wire**

- **Release record** (tens of bytes): stone id, release tick, position, velocity, ω, sent by the thrower's client the moment the stone leaves the hand.
- **Sweep inputs**: per sweeper per tick, pressure, rate and offset, batched every few ticks and stamped in ticks since release.
- **Rules events** between throws: score, violations, choices offered and taken, clock state.
- **State hash** when all stones rest, from every peer.

**How a throw plays out**

1. The thrower's client simulates the delivery and stone immediately — zero latency for the one person in control.
2. Everyone else receives the release record about half a round trip later. They play the delivery animation from the record with a short spectator delay; nobody else has input during delivery, so the delay is invisible.
3. Each sweeper's own inputs apply locally at once (prediction). Remote sweep inputs arrive late; on arrival the client restores the release snapshot and re-runs every tick to now with the full input log.
4. Sweep effects per tick are tiny, so corrections should be small; measure their size in playtests. Blend the rendered stone toward the corrected position over a few frames instead of snapping.
5. When all stones rest, peers exchange hashes. The authority's state wins on mismatch, and a desync report is logged with the input log attached.

&#91;embedded content: one throw on the wire · 5 steps\]

Step 4 is the trick: a late sweep input costs a re-run of the throw's ticks, not a rollback buffer.

**Re-sim cost.** A full throw is at most 7,200 ticks at 240 Hz over 30 s. Usually one or two stones move; idle stones are skipped until struck. Measure the worst case (a late input at second 25 with a multi-stone collision) on the slowest target device, and fall back to snapshots every second if it ever exceeds a frame budget.

**Authority and anti-cheat**

- Ranked: a headless dedicated server built from the same Rust crate, with no Godot. Casual: a listen-server host.
- The authority orders and stamps all inputs. Inputs older than a fixed window are applied at arrival time rather than retroactively, which blocks "sweeping the past" exploits.
- Clients never send positions. The server validates stroke rates, pressure and fatigue against human limits.

**Connectivity.** Godot's ENet for desktop, WebRTC for browser builds. [netfox](https://github.com/foxssake/netfox) bundles noray for NAT punch-through and relay. Its rollback core is a good general tool, but with a custom sim the resim-from-release scheme above is a small amount of code and fits curling better.

**Replays and spectators.** A replay is the ice seed plus every release record, sweep log and rules choice — kilobytes per game. Spectators and reconnecting players fast-forward from the start of the current end.

**Clocks.** Thinking time runs on the authority. A team's clock stops once its stone reaches the tee line at the delivery end ([C6](https://worldcurling.org/wp-content/uploads/2026/08/Rules2026.pdf)).

## AI

Split the AI into a strategist that chooses shots and executors that throw and sweep them, and make difficulty come from execution noise, search budget and ice-learning speed — never from altered physics. Curling AI is an established research area, so lean on its published methods.

**Prior art worth building on**

- [Digital Curling](https://minerva.cs.uec.ac.jp/cgi-bin/curling/wiki.cgi?page=SI_02): a shared simulator and server for curling AI tournaments since 2015; the third generation (DigitalCurling3, fcv1 simulator) ran the 2025 SIT Cup.
- KR-UCT: Monte Carlo tree search with kernel regression for continuous actions with execution uncertainty, tested in a curling simulator ([Yee, Lisý and Bowling, IJCAI 2016](https://www.ijcai.org/Abstract/16/104)).
- Policy and value networks plus kernel-based MCTS, trained by self-play, won an international digital curling contest ([Lee et al., ICML 2018](https://icml.cc/virtual/2018/poster/2461)).
- Curly, a physical robot using adaptive deep RL to cope with changing ice, won three of four official matches against expert teams ([Won, Müller and Lee, Science Robotics 2020](https://scholar.korea.ac.kr/handle/2021.sw.korea/53093)).

**Strategist**

1. **Candidate shots** from a catalogue: draw, guard (centre, corner), freeze, tap-back, raise, hit-and-stay, hit-and-roll, peel, double, runback, come-around. Filter by rules state (free guard zone, no-tick before the sixth stone).
2. **Inverse solve** each candidate: find release speed and angle for the chosen turn that produce the intended outcome, by root-finding on the deterministic sim. Cache per ice state; re-solve as the ice model updates.
3. **Evaluate under noise**: sample the executor's release and sweep noise, simulate, and score resulting positions with an end-outcome model.
4. **Search** two to four plies with KR-UCT or expectimax; deeper search is a difficulty knob.
5. **Value** positions by win probability over (end, score difference, hammer, stones left). Sanity check: World Curling data shows a tied team with hammer coming home wins close to 90% of the time ([CBC](https://amp.cbc.ca/lite/story/1.6393200)).

**Speed.** Search needs tens of thousands of simulated throws per decision. Use a coarser-step or surrogate model for the bulk of rollouts and confirm the top few candidates with the exact sim, so the AI never chooses a shot the real physics would not deliver.

**Executors**

- **Thrower:** samples release noise (σ of speed, line and rotation) from its rating, plus a pressure term late in close games.
- **Sweepers:** estimate weight from a noisy split time and the skip's calls; sweep with fatigue like humans.
- **Ice learning:** each AI team keeps its own Bayesian estimate of path speed and curl and updates it from observed throws, as Curly adapts to changing ice. Stronger teams learn faster.

**Difficulty tiers**

| Tier | Execution noise | Search | Ice learning | Style |
| --- | --- | --- | --- | --- |
| Club | High | Greedy, one ply | Slow | Simple draws and hits |
| Competitive | Medium | Two plies | Medium | Uses guards and freezes |
| Elite | Low | Three to four plies | Fast | Full strategy, end management, blanks |

Personality sliders (aggressive versus conservative, hits versus draws) give opponents character at the same tier.

**Teammates and coaching.** AI teammates take your calls, report how a stone felt ("heavy, didn't curl"), and write ice notes. An optional coach overlay shows the strategist's top shots with estimated success rates; it is off in ranked play.

## Rules engine

Implement World Curling's rules (edition of 1 September 2026) as a pure state machine fed by sim events — line crossings, contacts, rests — with every variant a config flag. Where the rules give the non-offending team a choice, the engine pauses and asks that team, exactly as on the ice.

| Area | Rule (WCF 2026) | Game handling |
| --- | --- | --- |
| Sheet | Tee line 17.375 m from mid-sheet; hog line inside edge 6.401 m from tee; back line outside edge 1.829 m behind tee; house radii 1.829 / 1.219 / 0.610 / ≥ 0.152 m; centre line runs 3.658 m past each tee to the hack line (R1) | Exact geometry in the sim; hog-to-hog is 21.948 m between inside edges |
| Stones | Circumference ≤ 914 mm, height ≥ 114 mm, mass 17.24–19.96 kg (R2a) | Per-stone mass within range; matched pairs |
| Out of play | Not fully past the far hog line unless it struck a stone; fully across the back line; touching a side line or divider; rolled over (R2) | Removed instantly, with a short animation |
| Delivery | Release before the near hog line; correct hack for handedness; in play once at the delivery-end tee line; touching granite after that tee line burns it (R5) | Electronic hog-line check; wrong-hack and hog violations remove the stone |
| Free guard zone | Before the sixth stone, no opposition FGZ stone may be removed from play, directly or indirectly; violation restores positions (R6) | Engine snapshots positions before each delivery for restores |
| No-tick | Before the sixth stone, an opposition FGZ stone touching the centre line may not be moved off it; offended team chooses remedy (R7) | Choice dialog for the offended team |
| Sweeping | As in the Sweeping section (R8) | Enforced by input gating; violations offer remedies |
| Touched or displaced stones | Remedies depend on where, by whom, and whether the stone affected the outcome (R9, R10) | Choice dialogs; "would have come to rest" uses the sim re-run without the touch |
| Scoring | Points for each stone closer to the tee than the opponent's best; measure to the nearest part of the stone; unresolvable ties blank the end or stop counting (R12) | Exact distances from sim; measurement cut-scene when within a few mm |
| Conceding | Only when your team is delivering (R12i) | Concede button gated to delivery turn |
| Thinking time | 38 min for 10 ends, 30 min for 8 ends, 22 min for mixed doubles; 4:30 per extra end; one 60 s time-out per game plus one per extra end (C6, C7) | Authority-run clocks |
| Last stone draw | Two stones by different players, one clockwise and one counter-clockwise; distance to centre using a 142 mm radius; misses record 1.996 m (C8) | Pre-game LSD sets hammer and feeds a draw-shot challenge for ranking |
| Mixed doubles | 5 stones per team per end; positioned stones A and B; one Power Play per game; nothing removed before the fourth delivered stone; 8 ends (R17) | Separate ruleset preset |

All rules: [The Rules of Curling, 1 September 2026](https://worldcurling.org/wp-content/uploads/2026/08/Rules2026.pdf).

**Presets**: World Curling 10-end, 8-end (as in the Grand Slams), club 6-end with a time limit, mixed doubles, and wheelchair (no sweeping, 8 ends, delivery from a stationary chair). House-rule toggles cover four-rock versus five-rock guard zones and no-tick on or off.

## Presentation: camera, audio, haptics, feedback

Drive every sensory channel from sim state rather than from canned animation, so what the player sees, hears and feels agrees with the physics. The "roaring game" nickname is a hint: sound and vibration carry much of the feel.

**Cameras**

| Camera | Used for | Notes |
| --- | --- | --- |
| Delivery | The throw | Low, behind the thrower; slight push-in through the slide; horizon locked |
| Sweeper | Travel | Just above and behind the stone; brushes in view so sweep position is readable |
| Skip | Travel and calls | From the house looking back up the sheet; best view of line and curl |
| House (overhead) | Strategy, scoring | Top-down, orthographic option; measuring view |
| Replay director | After shots and ends | Auto-cuts plus free timeline scrub |

**Audio**

- Stone rumble synthesized from speed and the pebble field under the band: louder and grainier on fresh pebble, smoother on worn paths.
- Granite-on-granite crack scaled by contact impulse; soft kiss for freezes.
- Brush strokes in rhythm with each sweeper's input; breath and effort layered with fatigue.
- Calls as voiced lines ("hurry hard," "off," zone numbers) with sheet-position panning and arena reverb.
- Venue beds: quiet club, arena crowd that reacts to win probability swings.

**Haptics.** On phones, short vibrations mark release, a hog-line warning and collisions. Trackpads and mice have no general-purpose haptics, so sound carries that job there: the slider's hiss and the stone's rumble rise and fall with speed. If a gamepad is added later, rumble tracks stone speed over pebble during the slide.

**Visuals.** Pebble sparkle, frost haze, polished path shine, breath fog, a visibly rotating handle (players can count turns), and the hog-line sensor light on the handle. Keep the screen nearly clear during travel.

**Feedback readouts**

- Release report (see Delivery) after each throw.
- Path overlay after the stone rests: called path, predicted path and actual path, with sweep segments marked.
- Team ice board between stones.
- End summary: shot percentages per player, a common curling statistic, plus weight-consistency per player.

## Progression, difficulty and accessibility

Progress the player's skill, not their stats: in competitive play every player and every brush is performance-equal, and what improves is measured consistency. Presets change aids and ice behaviour, never the underlying physics.

| Preset | Aids | Ice behaviour | Picks |
| --- | --- | --- | --- |
| Arcade | Predicted path drawn on the ice before the throw, wider line dead zone, auto-sweep option | Stable, uniform paths | Off |
| Club | Broom, stroke trace, split timer, release report | Moderate drift, some frost | Rare |
| Sim | Release report only | Full drift, path wear, venue climate | Realistic or rare |

**Skill progression**

- Personal stats from real input: release-speed spread on draws, line error spread, sweep-call accuracy, ice-read accuracy (predicted versus actual curl).
- Career unlocks venues, ice profiles and cosmetic gear; ranked uses only cosmetic differences.
- Drills unlock in a sequence that mirrors learn-to-curl programmes: weight, then line, then turn, then sweeping, then calling.

**Accessibility**

- One-push delivery for players who cannot make the full stroke: click or touch the stone and push it forward once; push speed sets weight, with no pull-back or slide. Paired with the wheelchair preset, it uses wheelchair rules (stationary delivery, no sweeping, 8 ends, [R14](https://worldcurling.org/wp-content/uploads/2026/08/Rules2026.pdf)).
- Hold-to-sweep instead of scrubbing, to avoid strain.
- Stone handles distinguished by pattern as well as colour.
- Subtitles and icons for every voiced call, remappable keyboard shortcuts for calls, and adjustable camera motion.

## Tech stack and project structure

One Rust workspace owns all game truth — sim, ice, rules, AI and protocol — and Godot is a presentation shell over it. The same crates build the Godot extension, the headless server, the AI training harness and Python calibration bindings.

&#91;embedded content: crate architecture · 3 consumers over one core\]

curl-sim is the heart; the client, server and Python tools are thin consumers of the same core.

**Engine version.** Target the Godot 4.7 line, current stable as of this writing (4.7.0 in June 2026, 4.7.2 in August 2026, per [release listings](https://www.apkmirror.com/apk/godot-foundation/godot-engine-4-2/godot-engine-4-4-6-2-stable-release/godot-engine-4-4-6-2-stable-android-apk-download/)). Pin the version per milestone.

**Rust workspace**

| Crate | Owns | Used by |
| --- | --- | --- |
| `curl-fx` | Q32.32 fixed-point scalar and vector types, integer sqrt, PRNG | Everything below |
| `curl-sim` | Stone dynamics, collisions, ice fields, sweep heat | Client, server, AI, tools |
| `curl-rules` | Rules state machine, scoring, clocks, presets | Client, server, AI |
| `curl-ai` | Shot catalogue, inverse solver, search, executors | Client (offline), server (bots) |
| `curl-proto` | Release records, sweep inputs, rules events, hashes; serde-based wire format | Client, server, replays |
| `curl-server` | Headless match authority binary | Ranked and hosted play |
| `curl-godot` | gdext bindings: nodes exposing sim state and input sinks | Godot client |
| `curl-py` | PyO3 bindings | Calibration notebooks |

**Godot project**

- `scenes/` venue, sheet, stone, player rigs, cameras.
- `render/` interpolation from the last two sim ticks; pebble, frost and polish shaders reading ice-field textures uploaded from the sim.
- `audio/` granular stone rumble driven by speed and pebble samples; call voice system.
- `input/` device schemes from the Delivery section, all mapped to the same sim inputs.
- `ui/` call wheel, ice board, release report, clocks, rules choice dialogs.
- `net/` transport (ENet, WebRTC), session and lobby; no game logic.

**Tooling**

- Physics lab scene: single sheet, parameter sliders, golden-throw runner with overlays of target versus simulated paths.
- Replay viewer that loads any input log, steps tick by tick and shows per-tick hashes.
- CI determinism matrix (see Determinism) plus nightly AI-versus-AI tournaments to catch strategy regressions.

## Roadmap

Build in five phases, each ending at a gate that must pass before the next starts; the feel gate is the one that matters most. Nothing past the feel slice gets built until curlers say the throw and the sweep feel right.

&#91;embedded content: roadmap · 5 phases, each with a gate\]

Phases are ordered by risk: physics and feel first, because they are the hardest to fix late and everything else sits on them.

## Risks and open questions

The biggest risk is feel, and the only cure is real curlers playing the physics lab early and often. The second is missing calibration data for collisions and pebble wear, which only club measurements can fill.

| Risk | Why it matters | Mitigation |
| --- | --- | --- |
| The curl law feels "gamey" | Curlers will notice in one end | Blind playtests with curlers from the first lab build; tune h(ω), f(v) and μ(v) against their reads |
| No published restitution or spin-transfer data | Hit shots are half the game | Track collisions in the club's overhead house cameras; fit e and band friction |
| Pebble-wear direction unknown | Ice drift could feel arbitrary | Keep wear effects small until measured; expose per-venue parameters |
| Sweep input causes strain | Scrubbing for 20 s, many times per game | Hold-to-sweep option; fatigue that rewards pacing over speed |
| Re-sim worst case on low-end hardware | Hitches during late collisions | Measure on target devices; snapshots each second as fallback |
| Retroactive sweeping exploit | Cheating in ranked | Late-input window and server validation (see Netcode) |
| Rust extension on web and consoles | Platform build friction | Prove wasm and one console devkit build in the first milestone |
| Team mode needs 8 humans | Thin matchmaking | Ship mixed doubles online first; AI fills empty team seats |
| Rules and branding | Trademark exposure | Implement rules generically; fictional teams, venues and events |

**Open questions**

- [ ] Will the club share raw recordings from its stream cameras, and at what resolution and frame rate?
- [ ] Target tolerances for each calibration target (for example ±0.3 s hog-to-hog)?
- [ ] Should hidden execution noise apply in human-versus-human play, or only to AI and difficulty presets?
- [ ] Is VR or motion-controlled delivery in scope after launch?
- [ ] Does the stroke need a landscape-only layout on phones?

## Sources

**Rules and ice**

- [World Curling — The Rules of Curling and Rules of Competition, 1 September 2026](https://worldcurling.org/wp-content/uploads/2026/08/Rules2026.pdf)
- [World Curling — Curling Ice Explained, arena chapter (via Curling Canada)](https://www.curling.ca/wp-content/uploads/2010/01/Arena_Curling.pdf)
- [Scottish Curling-Ice Group — Good Ice (2006)](https://mail.gncc.org/images/pdfs/Training/SCIG_Good_Ice_November2006.pdf)
- [Fluke — USA Curling ice technicians on dew point and frost](https://fluke.com/en/learn/blog/hvac/a-slippery-slope-not-for-curlings-ice-technologists)
- [Cedar Rapids Curling Club — weight and ice timing](https://cedarrapidscurling.com/index.php/component/content/category/14-curling-info)
- [Curling Canada — Getting Started, Week 5: Line of Delivery](https://www.curling.ca/wp-content/uploads/2025/01/Week5-LineofDelivery.pdf)
- [CBC — WCF no-tick trial and hammer win rates (2022)](https://amp.cbc.ca/lite/story/1.6393200)

**Stone physics and sweeping**

- [Uppsala University — scratch-guiding mechanism (Nyberg et al., 2013)](https://www.uu.se/en/press/press-releases/2013/2013-05-13-the-mechanism-that-puts-the-curl-in-the-curling-stone-revealed)
- [Honkanen et al. — scratch-guiding evidence, Scientific Reports 2018](https://link.springer.com/10.1038/s41598-018-26595-y)
- [UNBC — Shegelski and Lozowski pivot-slide model](https://www.unbc.ca/newsroom/unbc-stories/researchers-discover-why-curling-rocks-curl)
- [Mancini and de Schoulepnikoff — Improved pivot-slide model, Canadian Journal of Physics 2019](https://infoscience.epfl.ch/record/272732)
- [Murata — precision kinematic measurements of curling stone motion, Scientific Reports 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC9440934)
- [The Conversation — we still don't know how curling works (2022)](https://theconversation.com/the-slippery-science-of-olympic-curling-we-still-dont-know-how-it-works-176463)
- [Li et al. — ice–stone friction at the Beijing 2022 venue, Lubricants 2022](https://doaj.org/article/e3e504e211f546ae8ffe3acb573e39c4)
- [Glenn Paulley — mapping split times to hog-to-hog times (2026)](https://glennpaulley.ca/curling/2026/07/06/mapping-delivery-split-times-to-hog-to-hog-times/)
- [Kim et al. — sweeping effect by sweeping condition, IJERPH 2021](https://pmc.ncbi.nlm.nih.gov/articles/PMC7835804)
- [Lean Curling — sweeping angle studies](https://www.leancurling.com/sweeping-angle/)
- [Lean Curling — why sweep (Marmo et al. summary)](https://leancurling.com/sweeping-science/why-do-we-sweep)
- [Physics World — sweeping raises ice temperature about 1.5 °C](https://physicsworld.com/a/sweeping-away-myths-about-curl/)

**AI**

- [UEC — Digital Curling tournaments, DigitalCurling3 and fcv1](https://minerva.cs.uec.ac.jp/cgi-bin/curling/wiki.cgi?page=SI_02)
- [Yee, Lisý and Bowling — MCTS in continuous action spaces with execution uncertainty, IJCAI 2016](https://www.ijcai.org/Abstract/16/104)
- [Lee et al. — deep RL in continuous action spaces: simulated curling, ICML 2018](https://icml.cc/virtual/2018/poster/2461)
- [Won, Müller and Lee — Curly curling robot, Science Robotics 2020](https://scholar.korea.ac.kr/handle/2021.sw.korea/53093)

**Engine and networking**

- [Godot forum — making physics fully deterministic](https://forum.godotengine.org/t/making-physics-fully-deterministic/22575)
- [godot-rust (gdext)](https://github.com/godot-rust/gdext)
- [Klotho — deterministic multiplayer for Godot .NET](https://godotengine.org/asset-library/asset/5234)
- [Godot Rapier — physics plugin with cross-platform determinism](https://godot.rapier.rs/)
- [netfox — Godot multiplayer addons](https://github.com/foxssake/netfox)
- [Godot release listing (4.6–4.7 dates)](https://www.apkmirror.com/apk/godot-foundation/godot-engine-4-2/godot-engine-4-4-6-2-stable-release/godot-engine-4-4-6-2-stable-android-apk-download/)
