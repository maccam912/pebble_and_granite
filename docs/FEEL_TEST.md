# Delivery and sweeping feel check

Status: human testing pending. Automated mouse/touch equivalence and installed
Android emulator checks have passed; they do not establish comfort, perceived
latency or repeatability on a physical phone/trackpad. No input gains were changed
in this review without human evidence.

Use Menu → Learn to play for a first introduction, then Practice or Drills for
repeatable attempts. Keep one device, camera/FOV and input method per run. Record
the build/commit, device model, OS, refresh rate, pointer acceleration settings
(desktop), and whether one-push or hold sweeping was enabled.

## A short session

1. **Grip and weight.** Throw ten tee-weight draws with the same broom and turn.
   Note missed grips, accidental releases, short/heavy finishes and any hand
   strain. Use Ice board to compare actual split times and finish depths. First
   establish whether similar gestures produce similar outcomes; accuracy can
   improve with practice.
2. **Separate line from curl.** Throw three gentle left finishes and three right
   finishes. Verify that the displayed turn agrees with your intention before
   lifting. Then try three quiet lifts; note unintended rotation. Repeat with a
   sideways pullback followed by the opposite finishing curl. The finish should
   not change the line captured before sliding.
3. **Sweep and stop.** Use the sweeping lesson's supplied draw. Compare short
   light strokes, sustained brisk strokes and the hold button. Check that brush
   position is readable, off-path feedback is helpful, and lifting stops effort.
   Record whether maintaining useful strokes is tiring or awkward.
4. **Interrupt and recover.** Open Settings during a held slide, return, and
   regrip. Repeat by briefly backgrounding the phone. The stone should remain at
   the same point until regripped, with no accidental release or extra throw.
5. **Sustained play.** Play an end. Note camera discomfort, thermal slowdown,
   delayed button responses and audio problems separately from gesture problems.
   Compare Auto with Steady overhead and the normal stroke with One-push.

For each problem report: intended action, what happened, frequency (for example
3 of 10), relevant settings and whether it also happens in the tutorial. A short
recording is useful if available, but subjective comfort notes matter too.

## How to use the results

- Missed grips point first to projected hit areas, finger occlusion or framing.
- Repeatable short/heavy outcomes with comfortable strokes point to drive gains;
  inconsistent outcomes need input timing/sample inspection before changing gain.
- Unwanted curl or missed gentle finishes point to the finish threshold/window.
- Brush effort that is difficult to maintain points to scrub gain/decay; a brush
  that looks correctly placed but is rejected points to projection/offsets.
- Problems confined to online play need transport/host timing measurements rather
  than changing the shared local gesture mapping.

Change one parameter at a time and repeat the same attempts on both input routes.
Record before/after evidence. Review input/protocol compatibility for any mapping
change and run the core, delivery-slide, held-resume, input-route and sweep gates.
Keep the existing pre-slide line/post-slide curl separation and the accessible
one-push/hold alternatives.

Current source of truth: `crates/curl-input/src/delivery.rs`,
`crates/curl-input/src/sweep.rs`, `input/sweeping.gd`, and `compatibility.json`.
