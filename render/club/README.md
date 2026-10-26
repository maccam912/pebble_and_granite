# Original club lighting

`club.tscn` contains the original geometry from `CurlRinkView.build_club()`,
converted to ArrayMesh with UV2 at 0.25 metre texel spacing. `club.exr` and
`club.lmbake` were generated locally by the pinned Godot 4.7 editor. They contain
no third-party artwork and are stored in Git LFS.

The reviewed bake uses 24 sources aligned with the existing ceiling fixtures,
energy 1.5, high bake quality, four bounces, non-directional lighting, and an
interior environment at energy 0.12. It shades 248 static meshes. The three ice
sheets retain their existing real-time reflective shader; baking their direct
diffuse light removed the glancing highlights that make the ice readable.
Only eight soft center lights remain at runtime, at the original energy 0.15.
Moving stones and props use dynamic GI and are excluded from the static probe.

## Regeneration

Keep the game on its Compatibility renderer. Baking alone needs a renderer with
RenderingDevice support. On macOS:

```sh
python3 tools/godot.py --headless --path . --script tools/club_lighting.gd
python3 tools/godot.py --path . --editor --single-window --rendering-method forward_plus --rendering-driver metal build/club-lighting/club.tscn
```

Select `LightmapGI` and click **Bake Lightmaps**. If the macOS toolbar ignores
input, enter full-screen mode through the native Window menu, activate the
scene tree, and reselect the node after the window settles. A completed bake
prints `Done baking lightmaps` and replaces the atlas; selection or a click
alone does not confirm it happened. Save the bake to
`render/club/club.lmbake` if asked, then save the scene and close the editor.
The preparation step does not replace the reviewed runtime scene or atlas.
The editor bake replaces the atlas/data, so review and finalize it together.

```sh
python3 tools/godot.py --headless --path . --script tools/club_lighting.gd -- --finalize
python3 tools/godot.py --path . --script tools/visual_review.gd
python3 tools/godot.py --headless --path . --script tests/rink_view.gd
```

Finalization removes the extra bake lights and any preview camera/environment,
restores eight runtime fixtures, preserves the baked UV mappings, excludes ice
from those mappings, and writes `render/club/club.tscn`. Keep the atlas import
uncompressed (`compress/mode=0`): seven 256 by 256 HDR layers use about 2.6 MiB
without requiring unsupported compressed-HDR fallbacks on Compatibility.
Commit the scene, data, atlas, and import settings together after reviewing the
desktop and installed Android result. Recheck `project.godot` for incidental
editor normalization before staging.
