# ZEX Map Editor
Developed by Zex Interactive | Paras Sharma

Touch-first, Surveyor-style map editor for Godot 4.3 (Mobile renderer, landscape).

## Tools
- **Terrain**: raise, lower, smooth, flatten, rough, level-to-height. Radius / strength / hardness sliders.
- **Paint**: 8 texture layers, paint / erase / smart (slope) brush, auto-texture whole map, material picker, create materials from image or colour (tile size + tint).
- **Objects**: asset library with thumbnails, tap-slide-lift placement, auto snap to ground + slope align, size / rotation / sink.
- **Trees**: scatter brush (spacing, slope, height limits, avoids water and roads), remove brush, auto-fill any painted layer.
- **Select**: pick, drag, rotate, scale, lift, duplicate, delete.
- **Water**: lake (flood-fills a hollow, shore + depth automatic), ocean, pool plane; GTA V clear / ocean / river / swamp / pool looks.
- **Routes**: road, rail, river, object line (any asset along a curve). Tap to add, tap line to insert, drag to move, Apply to terrain (level + paint / carve).
- Undo / redo, save / open, autosave, walk preview, GLB export, data export (heightmap r16, splat PNG, objects.json, used assets).

## Assets
Models are loaded at runtime. PC: drop .glb into `import_assets/`. Phone: Menu > Import assets (copied into app storage).
Wrong-unit models are auto-fitted by category; use "Asset size correction" if needed.

## Camera
Two fingers: pan, pinch zoom, twist. Top bar "Orbit" = one-finger orbit. Desktop: RMB orbit, MMB pan, wheel zoom, WASD.

## Export
GLB: terrain with the texture blend baked, water, routes, objects (LOD-reduced, default 35%).
Saved to Downloads/ZEXMaps (or app folder). Android: enable storage permissions in the export preset.

## Tests
`xvfb-run godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 res://tools/selftest.tscn`
Not yet measured: real-device FPS (only software renderer available here).

## Ground tiles (Trainz style)
- A new map starts as ONE flat 50 x 50 m plate with the prototype grid texture.
- Use the "Ground +" tool: tap a green "+" to add a plate next to existing ground; shared edges snap automatically. "Remove" deletes a plate.
- Streaming: only ground, trees and objects within the Draw distance of the camera are loaded (Ground + panel slider).
- Textures: Paint > "Change material of this layer..." > import textures from your device.

Developed by Zex Interactive | Paras Sharma
