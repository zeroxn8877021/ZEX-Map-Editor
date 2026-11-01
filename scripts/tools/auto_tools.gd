# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : auto_tools.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name AutoTools
extends RefCounted
## One-tap automation: rule based terrain texturing and "fill this texture layer with trees / rocks".

## Texture the whole map from height + slope rules. layers = slot indices.
static func auto_texture(ed: MapEditor, rules: Dictionary) -> void:
	var d: MapData = ed.data
	var st: UndoManager.Stroke = ed.undo.begin("Auto texture")
	st.snapshot_splat_full()
	var n := FastNoiseLite.new(); n.frequency = 0.02; n.seed = 3
	var n2 := FastNoiseLite.new(); n2.frequency = 0.007; n2.seed = 9
	var slope := rules["slope"] as float
	var res := d.splat_res
	var cs := d.cell
	# per-cell slope (degrees) so the pixel loop stays cheap
	var sg := PackedFloat32Array(); sg.resize(d.verts * d.verts)   # (active tiles only matter)
	for iz in d.verts:
		for ix in d.verts:
			var dx := d.h_cell(ix + 1, iz) - d.h_cell(ix - 1, iz)
			var dz := d.h_cell(ix, iz + 1) - d.h_cell(ix, iz - 1)
			sg[iz * d.verts + ix] = rad_to_deg(atan(Vector2(dx, dz).length() / (2.0 * cs)))
	var ppm := res / d.size
	var lf := maxi(d.slot_of("grass"), 0); var ld := maxi(d.slot_of("dirt"), 0); var lr := maxi(d.slot_of("rock"), 0)
	var ls := d.slot_of("snow"); var lsd := maxi(d.slot_of("sand"), 0)
	for pz in res:
		for px in res:
			if not d.px_active(px, pz): continue
			var wx := (px + 0.5) / ppm - d.size * 0.5
			var wz := (pz + 0.5) / ppm - d.size * 0.5
			var g := d.world_to_grid(wx, wz)
			var gi := clampi(roundi(g.y), 0, d.cells) * d.verts + clampi(roundi(g.x), 0, d.cells)
			var h := d.heights[gi]
			var sl := sg[gi]
			var w := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
			var rock := smoothstep(slope - 6.0, slope + 6.0, sl)
			var snow := smoothstep(rules["snow_h"] - 4.0, rules["snow_h"] + 4.0, h + n.get_noise_2d(wx, wz) * 5.0) * (1.0 - rock * 0.8)
			var sand := (1.0 - smoothstep(rules["sand_h"], rules["sand_h"] + 1.3, h)) * (1.0 - rock)
			var dirt: float = smoothstep(0.15, 0.55, n2.get_noise_2d(wx, wz) + 0.2) * rules["dirt"] * (1.0 - rock) * (1.0 - snow)
			var base := maxf(0.0, 1.0 - rock - snow - sand - dirt)
			w[lf] += base
			w[ld] += dirt
			w[lr] += rock
			if ls >= 0: w[ls] += snow
			else: w[lr] += snow
			w[lsd] += sand
			var tot := 0.0
			for v in w: tot += v
			if tot < 0.0001: w[lf] = 1.0; tot = 1.0
			for i in 8: w[i] /= tot
			d.set_weights(px, pz, w)
		if pz % 48 == 0:
			ed.toast("Auto texture %d%%" % int(100.0 * pz / res))
			await ed.get_tree().process_frame
	ed.undo.commit(st)
	d.splat_changed.emit()
	ed.toast("Auto texture done")

## Scatter assets over every place where a splat layer dominates.
static func fill_layer(ed: MapEditor, layer: int, pool: Array, density: float) -> void:
	if pool.is_empty():
		ed.toast("Select assets in the Scatter library first"); return
	var d: MapData = ed.data
	var st: UndoManager.Stroke = ed.undo.begin("Fill layer")
	var attempts := int(density * d.size * d.size / 100.0)
	var added := 0
	var fresh: Array = []
	var spacing: float = ed.P["spacing"]
	for i in attempts:
		var x := randf_range(-d.size * 0.5, d.size * 0.5)
		var z := randf_range(-d.size * 0.5, d.size * 0.5)
		var p := d.splat_px(x, z)
		var w := d.get_weights(int(p.x), int(p.y))
		if w[layer] < 0.55: continue
		var h := d.height_at(x, z)
		if d.slope_at(x, z) > ed.P["slope_max"] or h < ed.P["min_h"] or h > ed.P["max_h"]: continue
		var pos := Vector3(x, h, z)
		if ed.is_blocked(pos): continue
		if d.nearest_object_dist(pos, spacing) < spacing: continue
		var xf: Transform3D = ed.make_xf(pos, randf() * TAU, randf_range(ed.P["scale_min"], ed.P["scale_max"]))
		var o := MapObject.make(pool[randi() % pool.size()], xf)
		d.add_object(o)
		st.obj_added.append(o)
		fresh.append(o)
		added += 1
		if i % 1500 == 0:
			ed.toast("Filling... %d%%  (%d placed)" % [int(100.0 * i / attempts), added])
			d.objects_added.emit(fresh); fresh = []
			await ed.get_tree().process_frame
	d.objects_added.emit(fresh)
	ed.undo.commit(st)
	ed.toast("Placed %d objects" % added)
