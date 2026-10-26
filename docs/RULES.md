# Rules implementation audit

Source: [World Curling, 1 September 2026](https://worldcurling.org/wp-content/uploads/2026/08/Rules2026.pdf), R17 and placement diagrams pages 29–30. The PDF became accessible on the second retrieval attempt. Rules version 4 is tracked separately from physics model 3 (wire protocol 11).

Implemented mixed-doubles boundaries: placement choice independent of hammer;
positioned stones with four selectable guard marks and either side of each mark;
one power play per team, unavailable in extra ends; per-end first/last thrower;
protected removal; empty-house versus equal-measure blanks; scoring and end progression.
Guard configuration is fixed for a match. Power-play offsets use the diagram's
metric measurements. Coordinates remain the simulation's receiving-end frame.

A complete ten-delivery authority test covers settlement, scoring, retained ice,
idle cooling time, clear field, and new placement before the next end. Placement
and end transition validate on clones before committing mutations.

Implemented since the initial audit: match command persistence, placement/role
controls, held delivery with tee-line clock cutoff, hog-release violation,
interruption/regrip, and mixed-doubles per-player brush identities.

R8/R17(l): both teammates may sweep moving own stones before the far tee.
Opponents' stones require tee crossing, and behind the tee only one player per
team contributes per simulation tick. The non-delivering side uses its designated
skip (player 2 in this mixed-doubles slice). If both delivering players request
the same behind-tee tick, player 1 wins the tie; either can sweep alone. This
choice is stable across packet order. Future spans and late-input replay evaluate
eligibility against the simulated stone position at each tick, not the later
rendered position. Ignored/zero-effort brushes do not add heat or fatigue. Retimed span overlap
replaces only the player's unconsumed future intent; past samples already covered by a span are
retained unchanged, and duplicate effort never stacks.

Fatigue is attached to the four mixed-doubles seats and persists across match
releases; accepted idle time recovers it. Standalone practice's single-shot sim
retains its existing fatigue reset behavior. Rules-3 match journals are preserved
and rejected rather than silently replayed with new brush identities; model-3
practice saves are unchanged.

Still open: full clause audit beyond these rules; timeout/break UI; physical
alternation of sheet ends and their ice coordinates; last-stone draw; spatial
selection of moved-own-stone sweep targets (authority supports them); full-team
multi-brush roles; burned stones; wrong-delivery remedies; calibrated fatigue
animation/audio. Current online UI follows the delivered stone for sweeping.
