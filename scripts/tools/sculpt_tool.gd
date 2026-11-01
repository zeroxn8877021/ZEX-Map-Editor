# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : sculpt_tool.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name SculptTool
extends EditorTool
## Terrain brushes: raise / lower / smooth / flatten / noise / level (to a typed height) / ramp-free "pinch" is left out.
var _flat_h := 0.0
var _noise := FastNoiseLite.new()
var _acc := 0.0

func _init() -> void:
	tool_name = "sculpt"
	_noise.frequency = 0.08
	_noise.fractal_octaves = 3

func uses_brush() -> bool: return true

func begin(pos: Vector2) -> void:
	super.begin(pos)
	stroke = ed.undo.begin("Sculpt")
	if has_cursor:
		_flat_h = ed.data.height_at(cursor.x, cursor.z) if ed.P["sculpt_mode"] != "level" else float(ed.P["level_h"])
	_acc = 1.0   # apply immediately

func drag(pos: Vector2) -> void:
	update_cursor(pos)

func end() -> void:
	super.end()
	if stroke != null:
		ed.undo.commit(stroke)
		stroke = null

func tick(dt: float) -> void:
	if not active or not has_cursor or stroke == null: return
	_acc += dt
	if _acc < 1.0 / 30.0: return
	var step := _acc
	_acc = 0.0
	apply(cursor, step)

func apply(c: Vector3, dt: float) -> void:
	var d: MapData = ed.data
	var r: float = ed.P["radius"]
	var k: float = ed.P["strength"]
	var hard: float = ed.P["hardness"]
	var mode: String = ed.P["sculpt_mode"]
	var g := d.world_to_grid(c.x, c.z)
	var rc := r / d.cell
	var x0 := maxi(0, int(floor(g.x - rc))); var x1 := mini(d.cells, int(ceil(g.x + rc)))
	var z0 := maxi(0, int(floor(g.y - rc))); var z1 := mini(d.cells, int(ceil(g.y + rc)))
	if x1 < x0 or z1 < z0: return
	var w := x1 - x0 + 1; var hgt := z1 - z0 + 1
	var src := PackedFloat32Array(); src.resize(w * hgt)      # snapshot for smoothing
	for iz in hgt:
		for ix in w:
			src[iz * w + ix] = d.heights[(z0 + iz) * d.verts + x0 + ix]
	for iz in hgt:
		for ix in w:
			var gx := x0 + ix; var gz := z0 + iz
			var wp := d.grid_to_world(gx, gz)
			var f := falloff(Vector2(wp.x - c.x, wp.y - c.z).length(), r, hard)
			if f <= 0.0 or not d.vert_active(gx, gz): continue
			var i := gz * d.verts + gx
			var h := src[iz * w + ix]
			var nh := h
			match mode:
				"raise": nh = h + k * 9.0 * dt * f
				"lower": nh = h - k * 9.0 * dt * f
				"smooth":
					var s := 0.0; var cnt := 0
					for oz in range(-1, 2):
						for ox in range(-1, 2):
							var sx := clampi(ix + ox, 0, w - 1); var sz := clampi(iz + oz, 0, hgt - 1)
							s += src[sz * w + sx]; cnt += 1
					nh = lerpf(h, s / cnt, clampf(k * 10.0 * dt * f, 0.0, 1.0))
				"flatten", "level":
					nh = lerpf(h, _flat_h, clampf(k * 10.0 * dt * f, 0.0, 1.0))
				"noise":
					nh = h + _noise.get_noise_2d(wp.x, wp.y) * k * 14.0 * dt * f
			if nh != h:
				stroke.touch_h(i)
				d.heights[i] = nh
	d.changed_region.emit(Rect2i(x0, z0, x1 - x0, z1 - z0))
