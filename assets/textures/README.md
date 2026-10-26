# Material provenance

`curling-granite.png`, `curling-ice.png`, and `curling-oak.png` are original generated artwork, created on 26 October 2026
using the built-in OpenAI image generation tool for this project. No downloaded
photography or third-party texture is included. These three are albedo textures;
roughness, contact shadows and ice markings are original
procedural shaders in `render/`. The ice texture supplies subtle albedo detail
under the procedural markings. All three albedos use mipmaps and VRAM compression.

The granite is now mapped at 22 cm after comparing the rendered mineral size
against the manufacturer reference; the original generated image is unchanged.

The PNGs are tracked with Git LFS. Run `git lfs pull` after checkout; CI fetches LFS
objects before import/export. No repository history was rewritten.

## Procedural pebble material

`curling-pebble.png` is an original mathematical material generated with
`python3 tools/ice_pebble_material.py` (NumPy and Pillow). It does not sample any
photograph or generated albedo. A fixed seed scatters 10,000 shallow, overlapping,
slightly elliptical ice droplets over a seamless 50 cm square. The base diameters
span 2-6 mm; the nipped tops are roughly 30% of each base diameter. The shape is
informed by [measured nipped curling ice](https://www.nature.com/articles/s41598-024-62247-0),
and is a visual approximation rather than a calibrated simulation surface.

The linear RGBA channels store world X/Z normal components, varying frost on the
sloping banks, and flattened-top coverage. `render/ice.gdshader` converts the
normals to the BoxMesh tangent basis and uses the coverage to break up the sheen
and show a thin frozen layer over the markings. Anisotropic mip filtering retains
detail at oblique game camera angles without the old procedural distance cutoff.

The 1024-square packed map is imported losslessly with mipmaps (about 5.33 MiB
uncompressed including mips). Alpha is material data, so alpha-border repair,
premultiplication, normal-map channel stripping and automatic VRAM compression
are disabled. This preserves all four channels and shallow normal precision.
It replaces the runtime nine-cell cap search with one additional filtered texture
sample. It is tracked with the existing PNG Git LFS rule.

The [visible-pebble photograph by Felix](https://commons.wikimedia.org/wiki/File:Curling_stones_on_rink_with_visible_pebble.jpg)
was consulted for appearance only; it is not included in game assets.

## Granite generation prompt

Create a single square 1024x1024 seamless tileable photorealistic PBR BASE COLOR
texture of polished Ailsa Craig common green curling-stone granite. This is a
flat material scan for a 3D curling game, NOT a picture of a curling stone. The
entire image must be the same continuous granite material, orthographic straight
overhead, even cross-polarized diffuse illumination, zero perspective, no object,
no seams, no borders, no cast shadows, no specular highlights, no text. Dense
natural interlocking small feldspar and quartz grains in medium neutral cool grey
with a very slight green cast, irregular fine charcoal mica flecks, a few
off-white mineral crystals. Subtle low-contrast cloudy mineral variation at
larger scales. Real polished Scottish curling-stone granite: predominantly
medium-light grey, fine irregular salt-and-pepper crystalline grain. Physical
area depicted about 35x35 centimetres, individual mineral crystals about 1-3mm,
many hundreds of grains. Avoid uniform digital random noise, large veins,
terrazzo, pavement, pebble stones, dramatic contrast, artificial scratches or
baked lighting. Natural photographic surface microdetail. Pixel edges must tile
seamlessly left-to-right and top-to-bottom.

## Ice generation prompt

A single square seamless tileable 1024x1024 physically based material texture of
real indoor curling ice, photographed perfectly straight down as a
cross-polarized material scan, covering a 50 centimetre square. BASE COLOR ONLY,
neutral diffuse flat even lighting with no directional illumination, no specular
glare, no shadows, no gradients or vignette. Off-white translucent frozen water
over white painted rink base, delicate irregular stippled pebble from sprayed
water droplets, tightly spaced tiny rounded bumps of about 1mm, tiny gray dots
and silvery-white cloudy microstructure. Scattered barely visible thin
curling-broom scratches, faint and irregular, predominantly along vertical
direction, at slightly varying angles and lengths. Dry frosted fine curling
pebble, NOT wet shiny skating ice, NOT snow, NOT cracks, NOT stone or concrete.
Almost entirely off-white with very subtle low contrast light cool gray detail.
Natural fine photographic microstructure, no large marks, no footprints, no rink
lines, no rings, no logos, no text or borders. All edges tile seamlessly
horizontally and vertically. This image will be a tileable ice surface albedo in
a photorealistic curling video game.

## Oak generation prompt

Use case: photorealistic-natural. Asset type: seamless PBR base-color texture for the wooden boards and benches of a 3D curling club. Generate one square 1024x1024 photorealistic material scan of gently worn, clear-finished pale honey oak. Perfectly straight-on orthographic view of one continuous wood surface, representing 60 by 60 centimetres. Fine natural long oak grain runs vertically from top to bottom, with subtle irregular curved growth bands, tiny pores, a few restrained natural knots, and small variations in warm beige/tan color. Neutral moderately light honey oak, not orange or dark brown. Matte diffuse cross-polarized flat illumination, no specular glare, no shadows, no gradients, no perspective, no beveled edges. Base color only, no baked lighting. No separate planks, no plank seams, no borders, no text or logo, no objects. All four edges must tile seamlessly; vertical grain must connect at top and bottom. Natural photographic detail with restrained contrast suitable for repeating along long rink boards; avoid striped digital noise, extreme knots, strong discoloration, large cracks, rustic distressing or water stains.

The built-in image generation tool produced this original base-color texture.
`render/oak.gdshader` projects it at world scale, with grain aligned separately
for the long rink boards and crosswise benches/trim. Mipmaps and anisotropic
filtering keep the distant grain stable. No reference photograph was supplied
to generation or redistributed with the game.
