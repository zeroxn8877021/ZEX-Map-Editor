# ZEX Map Editor - Feature List
Touch-first 3D map editor for Godot 4.3 (Trainz Surveyor style). Mobile renderer, landscape.

## Ground
- Starts as one flat 50 x 50 m plate with a prototype grid texture
- "+" button adds plates next to existing ground, edges snap automatically; Remove plate; up to 31 x 31 plates
- Draw-distance streaming: only ground, trees and objects near the camera are loaded; distance LOD

## Terrain sculpt
- Raise, lower, smooth, flatten brushes with radius / strength; hills / mountains / island generators

## Texture painting
- 8 texture layers, paint / erase / smart slope brush, auto-texture whole map
- Material picker, create materials from image or colour, import your own textures

## Objects and vegetation
- Asset library that auto-lists imported GLB / GLTF files, thumbnails
- Tap-slide-lift placement, auto snap to ground + slope align, size / rotation / sink
- Tree / vegetation scatter brush, select / move / delete

## Water
- Lake (fills dug basins), ocean, pool plane
- GTA V style looks: clear, deep ocean, river, swamp, pool; depth colour and shore foam

## Routes
- Road, rail, river and object-line (fences, poles...) along smooth curves
- Apply to terrain: flatten, paint and carve

## Project tools
- Undo / redo, save / load maps, walk-mode preview
- Export whole map as GLB (baked terrain texture, decimated objects) or data (heightmap, splat, objects.json)

Developed by Zex Interactive | Paras Sharma
