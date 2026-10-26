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
