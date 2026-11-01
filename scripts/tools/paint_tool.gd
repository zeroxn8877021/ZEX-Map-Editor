# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : paint_tool.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name PaintTool
extends EditorTool
## Texture brushes on the 8-layer splat map: paint / erase / smart (slope based: flat layer on flat ground, rock layer on cliffs).
var _acc := 0.0

func _init() -> void:
	tool_name = "paint"
	brush_color = Color(0.4, 0.9, 1.0)

func uses_brush() -> bool: return true

func begin(pos: Vector2) -> void:
	super.begin(pos)
	stroke = ed.undo.begin("Paint")
	_acc = 1.0

func end() -> void:
	super.end()
	if stroke != null:
		ed.undo.commit(stroke)
		stroke = null

func tick(dt: float) -> void:
	if not active or not has_cursor or stroke == null: return
	_acc += dt
	if _acc < 1.0 / 25.0: return
	var step := _acc
	_acc = 0.0
	apply(cursor, step)

func apply(c: Vector3, dt: float) -> void:
	var d: MapData = ed.data
	var r: float = ed.P["radius"]
	var k: float = ed.P["strength"]
	var hard: float = ed.P["hardness"]
	var mode: String = ed.P["paint_mode"]
	var layer: int = ed.P["layer"]
	var p := d.splat_px(c.x, c.z)
	var ppm := d.splat_res / d.size        # pixels per metre
	var rp := r * ppm
	var x0 := maxi(0, int(floor(p.x - rp))); var x1 := mini(d.splat_res - 1, int(ceil(p.x + rp)))
	var z0 := maxi(0, int(floor(p.y - rp))); var z1 := mini(d.splat_res - 1, int(ceil(p.y + rp)))
	for pz in range(z0, z1 + 1):
		for px in range(x0, x1 + 1):
			var wx := (px + 0.5) / ppm - d.size * 0.5
			var wz := (pz + 0.5) / ppm - d.size * 0.5
			var f := falloff(Vector2(wx - c.x, wz - c.z).length(), r, hard)
			if f <= 0.0 or not d.px_active(px, pz): continue
			var target := layer
			var amt := clampf(k * 6.0 * dt * f, 0.0, 1.0)
			if mode == "smart":
				var sl := d.slope_at(wx, wz)
				var steep_t := float(ed.P["smart_slope"])
				target = int(ed.P["smart_steep_layer"]) if sl > steep_t else layer
				amt = clampf(amt * 1.6, 0.0, 1.0)
			stroke.touch_splat(px, pz)
			var w := d.get_weights(px, pz)
			if mode == "erase":
				# remove the selected layer, give the weight back to the strongest other layer
				var take := w[layer] * amt
				w[layer] -= take
				var best := 0 if layer != 0 else 1
				for i in MapData.LAYERS:
					if i != layer and w[i] > w[best]: best = i
				w[best] += take
			else:
				for i in MapData.LAYERS:
					w[i] *= (1.0 - amt)
				w[target] += amt
			d.set_weights(px, pz, w)
	ed.terrain.mark_splat(Rect2i(x0, z0, x1 - x0, z1 - z0))
