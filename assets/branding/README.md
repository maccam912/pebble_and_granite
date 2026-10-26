# Original project mark

`icon.svg` is original geometric artwork authored for Pebble & Granite on
26 October 2026. It contains no font, downloaded image or third-party artwork.
The gold handle, granite body and house echo the game palette.

`splash.png` is rendered from that SVG using Godot's own SVG loader, because the
engine boot splash requires a PNG. Reproduce it with:

```sh
python3 tools/godot.py --headless --path . --script tools/render_branding.gd
```

The PNG is stored in Git LFS. The editable vector remains ordinary text.
