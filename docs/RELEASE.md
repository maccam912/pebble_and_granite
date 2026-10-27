New solo matches now have two visible sweepers with individual effort and fatigue.
Your brush stays manual while your partner follows the skip's calls. Player roles
rotate with the thrower; the call panel names the active sweepers and shows when
they tire. OFF stops called AI effort. New sessions use model 4 / protocol 12;
all online peers need matching builds. Existing model-3/rules-4 practice and match
saves retain their original behavior and exact replay hashes.

AI difficulty now changes strategy as well as accuracy. Competitive considers
opponent replies to two different shot intentions; Elite considers four and
checks execution risk. Match score, end and hammer affect choices, including
early blanks and final-end winning draws. These are bounded game heuristics.

Menu now groups modes and restart actions, leaving the rink clearer. Local play
pauses in the menu; active shots must finish before switching modes. One-push,
next-stone and sweeping controls appear in the phases where they are useful.

Learn to play now guides broom aim, draw weight, finishing curl and sweeping on
a separate practice sheet. Lessons grade actual input/results, offer retries and
skipping, and preserve the game you return to, including held deliveries.

Solo callers now drag the broom and choose explicit in-turn/out-turn controls.
The curl arrow shows direction, leaving the finish for you to judge. An optional
ghost broom and ring recall your previous contact-free shot while its stone
remains in place. Caller line, turn and weight survive save/resume.

New stone, brush and contact sounds have a separate mute and volume control.
Settings scroll while Done stays accessible. Escape opens Settings safely, even
during a held slide. Local play pauses in menus, and replacing an ongoing session
requires confirmation. Online stone travel continues while Settings is open.

Hammer, remaining stones and counting rings make the score easier to read.
End results show points, totals and the next hammer. Solo can wait after your
team's shots so you can review before continuing. Shot reports use left/right
and short/behind descriptions, and local travel has a measured hog-to-hog clock.
Scrubbing now explains off-path or stationary brush input.

Settings now offers a steady overhead view after release when Camera is Auto.
It keeps the travel camera fixed while retaining the ready delivery viewpoint
and manual camera selection.

Drills now includes takeouts and hog-to-hog timing. Alternate takeout targets
reward removal and staying in the house; timing rounds compare your actual
crossings against five time goals. Existing drill best scores are preserved.

Solo teams now handle centre-guard no-tick remedies: choose Accept or Restore for
Gold; Cyan chooses automatically. AI shot planning accounts for the opponent’s
remedy. Pending choices resume from saves. A clock forfeit during a moving early
release now ends travel and exposes Rematch.

Full team and Calling only now complement individual solo positions. Call keys
H/C/O can be remapped in Settings; active keys appear on the call buttons.
Settings and ice-board dialogs keep keyboard focus inside them. A visible weight
zone legend supports silent play; manual spoken calls respond immediately when
an English device voice is available.

Ice board now shows recent actual paths against the release ray, observed curl,
contacts, true hog-to-hog splits and per-position delivery statistics. Select a
path to save an ice note. It pauses local play while open. Paths and statistics
rebuild from the normal journal; annotations have separate bounded backup saves.

Solo 4 vs 4 now lets one human play Lead, Second, Vice or Skip alongside seven AI
players. Settings offers Club / Competitive / Elite shot accuracy and optional
4× opponent travel between the hog lines. Skip/vice can review and send shots,
then call HARD / CLEAN / OFF. Text and symbols always show calls; optional device
speech uses an available English voice. Solo matches save separately.

Cameras are closer to the thrower, sweeper and skip behind the broom. Settings
adjusts field of view; Zoom / Z inspects the house. Both broom directions are
covered by native release and camera alignment checks.

Drills adds five-shot rounds for tee weight, front guards, alternating draw line
and sweeping a light shot home. Targets, 0–3 star grading, best scores and
interrupted-round saves use the shared physics and real settled outcomes.

Early Pebble & Granite 3D feel slice. Aim the broom, grip the handle directly on
the ice, pull back, push, hold the slide, then flick left/right to release with curl.
Pullback and push now move the stone sideways, and the push direction affects
aim around the broom. Once sliding, a gentle left/right finish adds curl, with
live direction feedback and a short grace period before lifting. The hand moves
smoothly from pullback into the slide. The delivery camera faces the broom.
Indoor arena fixtures replace the outdoor directional light, with subtler shadows.
A small forward/back finish trims weight. Scrub ahead of a moving stone to sweep,
or use Hold to sweep for steady effort. Tap another eligible moving stone to select
it; a gold disc marks it and the Sweeper camera follows it. Mouse, held-click trackpad and Android touch share the
same stroke mapper. One-push delivery is available. Next stone keeps the stones and evolving ice;
Fresh ice starts a new session. Practice auto-saves and can restore interrupted shots.

The deterministic Rust core is shared with a headless replay verifier; Windows,
Linux and both macOS architectures check every-tick golden traces before builds.
The Godot bridge has a native integration check. Android packages are signed with
a stable development key, not a store publishing identity. macOS is ad-hoc signed,
not notarized. Windows is unsigned.

On macOS, extract the ZIP and move Pebble & Granite.app to Applications. If the
first launch is blocked, use System Settings → Privacy & Security → Open Anyway.
Mac packages now repair the exporter's ampersand escaping and pass Apple's strict
signature verification for both architectures before the exported runtime test.

Mixed doubles is now playable locally: positioned stones, power plays, player rotation, scoring, thinking clocks, extra ends and rematches. Local matches autosave separately from practice, including interrupted throws. Choose Mixed doubles to resume. Online rooms now expose Host/Join by Code, readiness, seat-restricted play, continuous hold sweeping and reconnect. This is an early online prototype; full cross-device match and latency validation remain open.
Mixed doubles now gives each player a brush/fatigue identity and lets both teammates
sweep before the tee, with one contributor per team afterward. Rules-3 match saves
are preserved but incompatible with rules 4; practice saves are unchanged.
Physics calibration, human curler feel approval, and physical Android validation
remain open. See repository docs/HANDOFF.md for current evidence and next work.
