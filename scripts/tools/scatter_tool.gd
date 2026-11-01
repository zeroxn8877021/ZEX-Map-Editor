# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : scatter_tool.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name ScatterTool
extends EditorTool
## Tree / vegetation / rock brush: paint to scatter the selected assets with spacing, slope and height rules
## (never inside water or on roads), or erase them again. Everything lands on the terrain with its normal.
var _last_pos := Vector3(1e9, 0, 0)
var _acc := 0.0
var _held := 0.0

func _init() -> void:
	tool_name = "scatter"
	brush_color = Color(0.45, 1.0, 0.45)

func uses_brush() -> bool: return true

func begin(pos: Vector2) -> void:
	super.begin(pos)
	stroke = ed.undo.begin("Scatter")
	_last_pos = Vector3(1e9, 0, 0)
	_acc = 1.0; _held = 0.0

func end() -> void:
	super.end()
	if stroke != null:
		ed.undo.commit(stroke)
		stroke = null

func tick(dt: float) -> void:
	if not active or not has_cursor or stroke == null: return
	_acc += dt
	_held += dt
	if _acc < 0.1: return
	var moved := Vector2(cursor.x - _last_pos.x, cursor.z - _last_pos.z).length()
	var r: float = ed.P["radius"]
	if moved >= r * 0.3 or _last_pos.x > 1e8 or _held > 0.5:
		_acc = 0.0
		if moved >= r * 0.3 or _last_pos.x > 1e8: _held = 0.0
		else: _held = 0.0
		_last_pos = cursor
		if ed.P["scatter_mode"] == "erase": erase_at(cursor)
		else: scatter_at(cursor)

func asset_pool() -> Array:
	var pool: Array = []
	for a in ed.P["scatter_assets"]:
		if ed.assets.entries.has(a): pool.append(a)
	if pool.is_empty() and ed.P["asset"] != "" and ed.assets.entries.has(ed.P["asset"]):
		pool.append(ed.P["asset"])
	return pool

func scatter_at(c: Vector3) -> int:
	var pool := asset_pool()
	if pool.is_empty():
		ed.toast("Pick one or more assets in the library first"); return 0
	var d: MapData = ed.data
	var r: float = ed.P["radius"]
	var count := clampi(int(ed.P["density"] * PI * r * r / 100.0), 1, 160)
	var spacing: float = ed.P["spacing"]
	var added := 0
	var fresh: Array = []
	for i in count * 2:
		if added >= count: break
		var a := randf() * TAU
		var rr := sqrt(randf()) * r
		var x := c.x + cos(a) * rr
		var z := c.z + sin(a) * rr
		if not d.inside(x, z): continue
		var h := d.height_at(x, z)
		if d.slope_at(x, z) > ed.P["slope_max"]: continue
		if h < ed.P["min_h"] or h > ed.P["max_h"]: continue
		if ed.is_blocked(Vector3(x, h, z)): continue
		if d.nearest_object_dist(Vector3(x, h, z), spacing) < spacing: continue
		var aid: String = pool[randi() % pool.size()]
		var xf: Transform3D = ed.make_xf(Vector3(x, h, z), randf() * TAU if ed.P["random_yaw"] else ed.P["yaw"], randf_range(ed.P["scale_min"], ed.P["scale_max"]))
		var o := MapObject.make(aid, xf)
		d.add_object(o)
		stroke.obj_added.append(o)
		fresh.append(o)
		added += 1
	if added > 0: d.objects_added.emit(fresh)
	return added

func erase_at(c: Vector3) -> void:
	var d: MapData = ed.data
	var only: bool = ed.P["erase_selected_only"]
	var pool := asset_pool()
	var chunks: Dictionary = {}
	for o in d.query_objects(c, ed.P["radius"]):
		if only and not pool.has(o.asset): continue
		chunks[d.obj_chunk(o.xf.origin)] = true
		d.remove_object(o)
		stroke.obj_removed.append(o)
	if not chunks.is_empty(): d.objects_changed.emit(chunks.keys())
