# Presentation review — 26 October 2026

Scope: polish the existing practice, local setup and online screens toward a
photographic club presentation. No gameplay, rules, physics or network contracts
change. Keep touch, trackpad and the accessible sweep button.

## Baseline critique

Fresh native Compatibility captures in `build/evidence/visual-baseline/` showed
cyan, featureless ice; spherical grey rocks with square handles; very dark empty
walls; floating ring geometry; and default buttons without hierarchy. Instructions
partly covered the stone. Long release reports could exceed the fixed panel.

Visual references (viewed for material/shape reference only, not redistributed):

- [Wausau Curling Club photography](https://www.visitwausau.com/blog/post/hit-the-ice-with-the-wausau-curling-club-for-winter-fun/)
- [Campbellton Curling Club photography](https://www.campbelltoncurling.com/history)

Recommended order: correct the stone profile and materials, bring the rink into
a neutral photographic palette, add the missing architectural finish and fixture
reflections, then improve menu hierarchy and clear the delivery sightline.

## First iteration

- Original lathed stone body, polished crown, rough striking band, rounded molded
  team handles and restrained contact shadows. One original generated granite
  texture, with provenance/prompt in `assets/textures/README.md`, stored in LFS.
- One continuous ice shader, including antialiased painted rings/lines, subtle
  pebble, cloudy ice and fine scratches. No layered floating ring cylinders.
- Finished walls, windows, benches, sheet signs, ceiling and three rows of strip
  fixtures, sharing cached materials. A static reflection probe excludes the
  moving stones. Eight soft indoor spotlights retained.
- Shared menu theme with deliberate hover, press, disabled and keyboard focus
  states; warm primary actions, quieter secondary actions and distinct sweep
  controls. Existing match/online controls retain their behavior.
- Separate branding/status hierarchy, aligned footer actions, and an instruction
  panel that sizes to the actual wrapped text and clears the delivery handle.

Rendered critique led to lower specular strength and light energy after the
first pass looked wet/overexposed, removal of a tone mapper that crushed the walls,
and a shorter room-code placeholder after a native screenshot showed clipping.

## Reproduce the review

```sh
git lfs pull
python3 tools/build_native.py
python3 tools/godot.py --headless --path . --editor --import --quit
python3 tools/godot.py --path . --script tools/visual_review.gd
```

The fixture does not save, contact other players or create a directory entry.
It captures delivery, slide feedback, a six-stone material fixture, overhead
house, match setup, lobby and validation feedback in `build/evidence/polish/`.
The six-stone arrangement is a presentation fixture, not evidence of a simulated
match. Images/logs stay in ignored `build/`; no screenshot binaries enter Git.

Validation for the first pass: core/golden traces and the existing Godot rink,
input routing, analog delivery, held resume, spatial sweeping, online UI, match
flow, practice restore and match restore gates pass locally. The rendered review
checks report containment and compiles the shaders on native OpenGL Compatibility.
A native rink test lost brush input during one focus interruption; the subsequent
native run and headless input gates passed. No physical Android or other GPU
performance claim follows from the Mac captures. Cross-platform CI is separate.

## Second iteration

Comparison with [Kays' own stone photography](https://kaysscotland.com/) exposed
the remaining bracket-shaped handle and dark striking band. Replaced them with
an original swept cantilever grip, a wider molded cap and a lighter rough band.
Shared cap/grip meshes also reduce per-stone draw calls. Generated a second
original texture for the ice; its subtle irregular detail replaces repetitive
procedural scratch lines. Added restrained cladding seams/occlusion and desktop
ambient occlusion, keeping Android's two-sample antialiasing and avoiding the
desktop post-process there.

The review fixture caught a first-frame report sizing race after fonts/layout
settled. The panel now relayouts on minimum-size changes; all seven native
captures pass containment. Rink, online UI and input routing gates pass again.
Checkpoint `12f133a` was also installed and visually inspected on the Android
emulator; the full updated material pass still needs a fresh export/install.

## Third iteration

The Android launch capture exposed the default engine logo. Added an original
editable SVG mark and reproducible PNG boot splash, plus adaptive Android icons
with a dark background matching the game. No new splash scene or timed delay.
The online roster now has aligned team/player/status columns and team colors.
The existing end/score values have a dedicated compact display in the header,
leaving the status, seat identity and clocks readable below it.

Updated the existing Android touch probe's observed coordinates for the polished
layout. A cold first launch compiled shaders after the original five-second test
delay, so the probe now accepts an explicit warm-up duration. A subsequent run
recorded real right-curl delivery, spatial scrub and accessible hold sweeps; its
left-shot read collided with an autosave write. The probe now retries only
incomplete JSON reads. These are harness fixes, not changes to input or saves.
The complete rerun passed: `ANDROID_DIRECT_TOUCH_OK`, evidence and accepted
input journals in `build/probes/touch-03773ecf5c504d72b4a65412898c63be/`.
Both curl directions, spatial scrubbing, lift-to-stop, accessible hold sweeping,
pause/regrip and exactly one hog violation passed on the installed local APK.
Native review now includes an eighth capture for two-digit score spacing.

The final phone readability pass raises action height to 64 logical pixels and
button/report text to 22/20, with tighter 52-pixel setup rows to retain spacing.
It does not change the ice viewport, camera projection, coordinate conversion,
gesture gains or simulation. Clean local Android export 46 records source
`9ae52d1`, `source_dirty: false`, SHA-256
`6fb33a478f13e4c985f30f5b69c784eeb7ab402ecfef8d034687ef655d0223cb`.
It was installed and passed the complete touch probe again, with evidence in
`build/probes/touch-b278e08f2cb54f0e89c21069da59b46b/`.

## Startup review

Timed Android screenshots in `build/evidence/polish/android-final/` verified the
new mark and larger controls, but exposed a white system splash despite the dark
adaptive-icon background. Inspection of the pinned Godot 4.7 exporter showed
that the splash background needs its own explicit color; an image-valued
fallback did not color the system backdrop. Set both Android window and system
splash colors to the game background, with an explicit splash mark.

On this emulator the UI appeared by the five-second capture and the 3D image
between five and ten seconds on a launch after reinstall. This is a shader
warm-up observation, not a physical-device startup or frame-rate benchmark.
Compatibility does not support the export shader baker. No arbitrary timed
delay or new loading/gameplay flow was added.

Clean local Android export 47 (`b10c95b`, `source_dirty: false`, SHA-256
`b32087781b080bb13cc7368ce671cd8c4f1d3c4dedba0b6c08b376909ddaa17e`)
was installed. Its actual system splash is dark; APK resource inspection confirms
`windowSplashScreenBackground=#ff0b1820`. Phone captures of the lobby and setup
are in `build/evidence/polish/android-47/`.

That phone setup capture caught overlapping rows: lowering a Button's minimum
height did not shrink its existing size. Set the actual setup/camera sizes too.
The review now supports `-- --mobile-ui` for a native preview of phone typography
and control sizes in `build/evidence/polish-mobile/`, and checks row separation.
This preview is a Mac render of the mobile layout, separate from installed-APK
evidence. The corrected preview passes all eight captures; rink/match gates pass.

## Next photographic critique

The major remaining gap is the room's illumination: materials and stone shapes
are more convincing, but the ceiling/walls still lack realistic indirect bounce
and structural shadows. Investigate baked static club lighting while retaining
the Compatibility renderer and existing input/simulation. This is art/rendering
work; no gameplay or quality-options menu is authorized by this polish task.

[LightmapGI](https://docs.godotengine.org/en/stable/classes/class_lightmapgi.html)
is a candidate: baked lighting is suitable for mobile runtime, but baking requires
an editor with a RenderingDevice renderer. Existing generated PrimitiveMeshes
would first need ArrayMesh conversion and UV2 unwrap; LightmapGI baking is an
editor operation, not an exposed runtime GDScript method. Keep experiments
isolated until they produce a reviewed improvement, and repeat Android rendering
checks before publishing a lighting change.

## Verified layout checkpoint

Local Android export 48 is a clean build of `f907bff` (`source_dirty: false`,
SHA-256 `1c250adc763507a04b137d61f0a461c9342dde21141289d527aa9881d8c79bda`).
It was installed on `emulator-5554`; the actual corrected setup capture is
`build/evidence/polish/android-48/match-setup.png`, reviewed without row overlap.
The emulator's original practice/match files and backups were restored byte for
byte after testing; the app is stopped. The test AVD `pebble_granite_lab` remains
running for subsequent rendering checks. LFS integrity passes.

All code through this checkpoint is pushed. Current core/native/rendered checks
pass; the newest GitHub workflow is queued behind the prior in-progress build,
so no CI/release completion is claimed. Weekly usage last reports 4% used / 96%
remaining. The polish goal remains active for the lighting critique above.

Also review static reflection culling during that pass: stones use layer 2, but
the broom/brush/hand meshes still default to layer 1 and can enter the one-time
club probe. Exclude those transient props before reviewing the final cubemap.

## Static room lighting pass

Reviewed six isolated Compatibility renders in `build/evidence/lighting/`.
The first was too dark. Strong emission from the small lamp meshes produced
blotchy illumination; increasing the eight center sources instead blew out the
center sheet while leaving the side walls dark. The selected bake aligns 24
offline sources with the existing visible fixtures, at energy 1.5, high quality
and four bounces. This adds soft wall illumination and structural shadows.

A full diffuse bake made the ice look dull. Keep the three reflective ice
materials under their existing real-time lighting, with 248 room meshes using
the lightmap. The finalized native review preserves the ice highlights and stone
readability while giving the room more depth. All eight review captures pass.
The lightmap is an original Godot-generated HDR atlas (seven 256-square layers),
not a downloaded asset. Its uncompressed import avoids compressed-HDR fallback
warnings on this Mac. Runtime still uses Compatibility and eight soft lights.

`tools/club_lighting.gd` prepares and finalizes future editor bakes; the workflow
and provenance are in `render/club/README.md`. Moving props now share the stones'
reflection exclusion layer and dynamic GI mode. The test verifies that all
baked paths resolve, ice has no diffuse lightmap, and props remain excluded.
Installed Android validation is pending at this source checkpoint. No claim of
photorealism, physical-device performance, or completed remote CI is made.

Clean Android build 49 (`d06a0ef`, SHA-256
`7740d2a8b2084a8c4612d23d3e64c05eeef5e705b78d9efee16b95555cee35ce`)
was installed and reviewed on `emulator-5554`. The baked room renders correctly.
The complete touch probe passed both curl directions, scrub/stop, accessible
hold, pause/regrip, and the one-time hog violation check. Evidence is in
`build/probes/touch-43678eb08cbe44b6b1bbaac85c637a03/`; original practice files
were restored byte for byte afterward and the app stopped.

## Material highlight comparison

Compared the new room against the [Carleton Place club photograph](https://cpcurling.ca/index.php/about-the-club/club-photos)
and [Richmond lighting photographs](https://www.bchydro.com/news/conservation/2021/richmond-curling-lighting-savings.html).
These are visual references only, downloaded into ignored `build/reference/`;
no reference photograph is shipped. The ice needed a clearer glancing sheen and
the plastic cap had a distracting white hotspot. Lower ice roughness from
0.42-0.55 to 0.30-0.42, raise cap roughness from 0.22 to 0.32, and reduce the
point-source specular contribution from 0.65 to 0.35. The room probe retains
the broad reflections. All eight native screenshots pass after comparing three
material variants. The base lighting captures are retained in
`build/evidence/lighting/integrated-base/`. Android validation of these material
adjustments remains pending at this checkpoint. Weekly quota is 94% remaining.

## Original oak comparison

The next review found uniform stripes in the procedural wood, especially along
the near boards. Generated an original honey-oak base-color texture with the
built-in image tool, saved as `assets/textures/curling-oak.png`; its complete
prompt and provenance are in `assets/textures/README.md`. No third-party image is
included. The material uses world-scale projection with grain aligned to each
board or bench, and the caps now share the wood material. Regenerated and baked
the club again (5.05 seconds in this local editor), finalized it, and reviewed
all eight native captures. The rink test passes, with 248 valid baked meshes.
Android review of this source is pending. The offline editor reported seven
texture RIDs at shutdown; the Compatibility runtime review reports no renderer
warnings or errors. Existing gameplay and input contracts remain unchanged.

## Roof reflection visibility

House view previously hid the roof globally to see through it. If it was the
first rendered camera, the one-time room reflection could also lose its roof
and fixtures. Give roof geometry layer 3 and hide that layer only from the House
camera; the probe retains room/roof layers 1 and 3 while excluding moving props
on layer 2. The camera projection and input geometry stay unchanged. The rink
test checks roof/probe masks and all eight native review captures pass.

Clean Android build 51 (`63815c7`, SHA-256
`591a2453f982f257d6deb5ba60a88fc99d8edb7ddd0f76a12dd27c66e7c9a1a1`)
was installed on the test emulator. Reviewed delivery, all camera buttons, the
new oak material, and the unobstructed House view. Captures and the app log are
in `build/evidence/polish/android-51/`; the captured app log contains no Godot
warning/error. All four original practice/match files and backups were restored
byte for byte, with the app stopped. This validates the installed renderer,
separate from the complete gesture probe that passed on build 49.

## Held delivery presentation

The real build-49 held-delivery capture exposed a prominent flat end on the
cylindrical sleeve, with the hand reading as a ball. Refine the existing prop
into a tapered sleeve extending out of frame, a cuff, and a gloved palm with
curled fingers/thumb. Original procedural fabric shading supplies restrained
weave and high roughness. No arm animation, input mapping, hit target or delivery
state changed. All new meshes stay on the dynamic prop layer.

The native review now includes `02b-held-delivery.png` (nine captures total), so
this existing pose cannot be missed in later art passes. Reviewed the held view;
rink, held-resume and delivery-slide checks pass. Android review of this newest
prop is pending at this checkpoint.

Build 52 is a clean export of `2594b0f` (SHA-256
`b9a48fc7980254d89db12f4433866e5762f70e87c6d4a25c50c6e746b490c01e`).
The first installed probe did not record its first drag; a warm rerun passed the
complete probe, including both curl directions and pause/regrip. Failure evidence
is in `build/probes/touch-4751958468d24a5d97b4461e0738fdd0/`, and the passing
rerun in `build/probes/touch-d97c5c70ae3d4f24b9db63b5240cd497/`.
This does not prove the cause of the first failure. To avoid adding another
first-use shader variant for negligible visible detail, retain the new geometry
with the existing matte StandardMaterial3D instead of the cloth shader. Native
review remains visually consistent and passes. Original practice files restored.

## Fresh-cache input validation

A fresh Godot shader-cache run of build 53 also missed its first drag. A
temporary diagnostic APK (54, never published) traced the real touch route:
coordinates and pointer selection were correct, but all drag events reached
Godot within roughly one millisecond after a long startup stall. The probe had
started its timed stroke before the Fresh ice reset was processed. Diagnostic
logging was removed from the source immediately after building that APK.

The probe now waits for the reset's autosave timestamp to change before timing
the stroke, with a bounded timeout. It retains all gesture timings and gameplay
assertions. Production build 53 (`f1530c8`, `source_dirty: false`, SHA-256
`099b7f26317f80dc9dbb4a66888c0653b9dd7249ea96eb83412ea2222094429f`)
then passed the full installed probe with a fresh Godot shader cache. The first
reset took 6.49 seconds to acknowledge after the 30-second test startup wait;
later resets took about 0.45 seconds. This is an emulator startup observation,
not a physical-device startup benchmark. No product input/physics fix or added
loading flow was introduced.

Passing evidence: `build/probes/touch-1d6b8804febd4522a346bf31a2bcd1f0/` and
`build/android-matte-cold-ack-probe.log`. Reviewed the actual held-delivery image.
All four original practice/match files and backups were restored byte for byte;
the original shader cache was restored, temporary caches removed, and app stopped.
The local review now includes a close Sweeper fixture (ten captures), which also
shows the new wood and room lighting near the benches. Native sweeping passes.
Weekly quota remains 93%. Current source is pushed; newest CI is queued behind
the earlier packaging run, so latest-head CI/release completion remains open.

## Next photographic critique

The boards and bench seats still have mathematically sharp edges. Review a small
rounded-edge treatment on those existing wooden pieces before deciding whether
it earns another geometry/lightmap pass. Keep all simulation geometry, input and
camera contracts unchanged. The broader photographic polish goal remains active.

## Rounded timber review

Replaced only the existing wooden pieces' sharp long edges with 4-9 mm roundovers,
using original generated meshes inside the same dimensions. The near rails and
bench rims now have softer silhouettes and edge highlights. No collision,
simulation, input, camera or material parameters changed. The mesh check verifies
the exact bounds, non-degenerate faces and clockwise winding for both board axes.

Reprepared the source and baked/finalized the room (3.50 seconds locally). The
atlas remains seven 256-square HDR layers, and all 248 baked mesh references
resolve. All ten native review views and the rink gate pass. The before images
and original club are retained in ignored `build/bevel-review/base-screenshots/`
and `base-club/`. Compared Delivery and the close Sweeper view before retaining
the change. The offline editor again reports seven texture RIDs at shutdown;
the finalized Compatibility runtime is clean. Installed Android review is next.


## Rounded timber on Android

Clean Android build 55 (`6ec771c`, `source_dirty: false`, SHA-256
`87515c590f4df4e76912a15ffc2d558bb99612d836d71181ebf14641ac2ef3ab`)
was installed on the existing test emulator. Reviewed Delivery and four camera
captures, including the rounded rails/bench edges. Evidence is in
`build/evidence/polish/android-55/` and `build/android-55-review.log`.
No Godot warnings/errors appeared in the captured app log. All four original
practice/match files and backups were restored byte for byte, and the app stopped.
This was a renderer/camera review; the complete gesture probe remains the separate
build-53 result above.

## Upper glazing material

The flat blue panes read as solid wall panels. The upper glazing in the
[Banff recreation centre reference](https://www.athleticbusiness.com/project-galleries/architectural-showcase/j6ZYVJdHWQ/banff-community-recreation-centre-renovation-and-addition-banff-alta)
suggested a restrained vertical light gradient and diffusing edges. The photo
was viewed only as reference in ignored `build/reference/`; it is not an asset.
The new glass shader is original procedural code, shared by all fourteen panes.

Reviewed the material on the existing baked meshes. It retains the geometry,
UV2, atlas and baked-data bytes exactly. A thinner frame/pane geometry variant
was prepared but not finalized: the native editor accepted node selection yet
did not activate its bake command, including after a normal reopen. That variant
stays out of the shipped source. The material has modest emission to suggest
light through diffuse glazing, without adding a runtime light or exterior image.
Ten native captures and the rink gate pass, with clean runtime logs. Before
images remain in `build/glazing-review/base-screenshots/`. Installed Android review
of this shader follows the source commit. Weekly quota remaining: 92 percent.
