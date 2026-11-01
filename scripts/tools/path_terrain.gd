# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : path_terrain.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name PathTerrain
extends RefCounted
## "Apply to terrain": flattens + paints under roads / rails, carves river beds (all undoable via the stroke).

static func apply(d: MapData, p: Dictionary, st: UndoManager.Stroke) -> void:
	var pts: PackedVector3Array = p["points"]
	if pts.size() < 2: return
	var s := PathGeo.sample(pts, p.get("closed", false), 1.0)
	var pos: PackedVector3Array = s["pos"]
	var n := pos.size()
	var hw: float = float(p.get("width", 6.0)) * 0.5
	var shoulder: float = float(p.get("shoulder", 6.0))
	var typ: String = p["type"]
	if typ == "line": return
	# target heights along the path
	var target := PackedFloat32Array(); target.resize(n)
	var depth: float = float(p.get("depth", 1.8))
	if typ == "river":
		target = PathGeo.river_levels(s, d, depth)
		p["levels"] = target.duplicate()
	else:
		for i in n: target[i] = d.height_at(pos[i].x, pos[i].z)
		for pass_i in 6:     # moving-average smoothing
			var t2 := target.duplicate()
			for i in n:
				var a := maxi(0, i - 5); var b := mini(n - 1, i + 5)
				var sum := 0.0
				for j in range(a, b + 1): sum += target[j]
				t2[i] = sum / (b - a + 1)
			target = t2
	# best (nearest) sample per cell
	var best_w: Dictionary = {}; var best_t: Dictionary = {}; var best_d: Dictionary = {}
	var reach := hw + shoulder
	for i in n:
		var g := d.world_to_grid(pos[i].x, pos[i].z)
		var rc := reach / d.cell
		for gz in range(maxi(0, int(floor(g.y - rc))), mini(d.cells, int(ceil(g.y + rc))) + 1):
			for gx in range(maxi(0, int(floor(g.x - rc))), mini(d.cells, int(ceil(g.x + rc))) + 1):
				var wp := d.grid_to_world(gx, gz)
				var dist := Vector2(wp.x - pos[i].x, wp.y - pos[i].z).length()
				if dist > reach: continue
				var w := 1.0 if dist <= hw else 1.0 - smoothstep(hw, reach, dist)
				var k := gz * d.verts + gx
				if not d.vert_active(gx, gz): continue
				if not best_d.has(k) or dist < best_d[k]:
					best_d[k] = dist; best_w[k] = w; best_t[k] = target[i]
	var minx := d.cells; var minz := d.cells; var maxx := 0; var maxz := 0
	for k in best_w:
		var h := d.heights[k]
		var w: float = best_w[k]; var t: float = best_t[k]; var dist: float = best_d[k]
		var nh := h
		if typ == "river":
			if dist <= hw:
				var prof := 1.0 - pow(dist / maxf(hw, 0.01), 2.0)
				nh = lerpf(h, t - depth * prof, 1.0)
			else:
				var bank_t := t + (dist - hw) * 0.4
				nh = lerpf(h, minf(h, bank_t), w)
		else:
			nh = lerpf(h, t, w)
		if absf(nh - h) > 0.0001:
			st.touch_h(k)
			d.heights[k] = nh
			var x: int = k % d.verts; var z: int = k / d.verts
			minx = mini(minx, x); maxx = maxi(maxx, x); minz = mini(minz, z); maxz = maxi(maxz, z)
	if maxx >= minx:
		d.changed_region.emit(Rect2i(minx, minz, maxx - minx, maxz - minz))
	# paint
	var layer: int = int(p.get("paint_layer", 7 if typ == "road" else (5 if typ == "rail" else 6)))
	if layer < 0: return
	var ppm := d.splat_res / d.size
	var paint_w := hw * (1.12 if typ != "river" else 1.5)
	var soft := 1.6
	var pbest: Dictionary = {}
	for i in n:
		var c := d.splat_px(pos[i].x, pos[i].z)
		var rp := (paint_w + soft) * ppm
		for pz in range(maxi(0, int(c.y - rp)), mini(d.splat_res - 1, int(c.y + rp)) + 1):
			for px in range(maxi(0, int(c.x - rp)), mini(d.splat_res - 1, int(c.x + rp)) + 1):
				var wx := (px + 0.5) / ppm - d.size * 0.5
				var wz := (pz + 0.5) / ppm - d.size * 0.5
				var dist := Vector2(wx - pos[i].x, wz - pos[i].z).length()
				if dist > paint_w + soft: continue
				var a := 1.0 if dist <= paint_w else 1.0 - smoothstep(paint_w, paint_w + soft, dist)
				var key := pz * d.splat_res + px
				if not d.px_active(px, pz): continue
				if a > pbest.get(key, 0.0): pbest[key] = a
	for key in pbest:
		var px: int = key % d.splat_res; var pz: int = key / d.splat_res
		st.touch_splat(px, pz)
		var w := d.get_weights(px, pz)
		var a: float = pbest[key]
		for j in MapData.LAYERS: w[j] *= (1.0 - a)
		w[layer] += a
		d.set_weights(px, pz, w)
	d.splat_changed.emit()
