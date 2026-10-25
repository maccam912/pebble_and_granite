# Rules implementation audit

Source: [World Curling, 1 September 2026](https://worldcurling.org/wp-content/uploads/2026/08/Rules2026.pdf), R17 and placement diagrams pages 29–30. The PDF became accessible on the second retrieval attempt. Rules schema 1 is tracked separately from physics model 2.

Implemented mixed-doubles boundaries: placement choice independent of hammer;
positioned stones with four selectable guard marks and either side of each mark;
one power play per team, unavailable in extra ends; per-end first/last thrower;
protected removal; empty-house versus equal-measure blanks; scoring and end progression.
Guard configuration is fixed for a match. Power-play offsets use the diagram's
metric measurements. Coordinates remain the simulation's receiving-end frame.

A complete ten-delivery authority test covers settlement, scoring, retained ice,
idle cooling time, clear field, and new placement before the next end. Placement
and end transition validate on clones before committing mutations.

Still open: full clause audit beyond these rules; timeout/break UI; physical
alternation of sheet ends and their ice coordinates; match command persistence;
last-stone draw; full multi-brush and moved-own-stone sweeping; burned stones;
wrong-delivery remedies and the player-facing placement/role controls.
