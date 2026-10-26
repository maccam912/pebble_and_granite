# Material provenance

`curling-granite.png` and `curling-ice.png` are original generated artwork, created on 26 October 2026
using the built-in OpenAI image generation tool for this project. No downloaded
photography or third-party texture is included. It is an albedo texture, mapped
with triplanar sampling; roughness, contact shadows, ice and oak are original
procedural shaders in `render/`. The ice texture supplies subtle albedo detail
under the procedural markings. Both textures use mipmaps and VRAM compression.

The PNG is tracked with Git LFS. Run `git lfs pull` after checkout; CI fetches LFS
objects before import/export. No repository history was rewritten.

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
