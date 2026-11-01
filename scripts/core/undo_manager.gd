# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : undo_manager.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name UndoManager
extends RefCounted
## Stroke based undo / redo. A Stroke records the first-seen value of every height cell / splat pixel it touches, plus
## object add / remove / move lists and snapshots of the waters / paths arrays. 60 steps are kept.

signal stack_changed

class Stroke extends RefCounted:
	var data: MapData
	var h_old: Dictionary = {}          # idx -> old height
	var s_old0: Dictionary = {}         # pixel idx -> old rgba32 (splat0)
	var s_old1: Dictionary = {}
	var obj_added: Array = []
	var obj_removed: Array = []
	var obj_moved: Array = []           # [obj, old_xf]
	var water_before = null
	var paths_before = null
	var label := "edit"
	var h_new := PackedFloat32Array(); var h_idx := PackedInt32Array(); var h_old_arr := PackedFloat32Array()
	var s_idx := PackedInt32Array(); var s_o0 := PackedInt32Array(); var s_o1 := PackedInt32Array(); var s_n0 := PackedInt32Array(); var s_n1 := PackedInt32Array()
	var water_after = null
	var paths_after = null
	var moved_new: Array = []
	var dirty_rect := Rect2i()
	var tiles_before = null
	var tiles_after = null
	var full_old: Array = []            # whole-map splat snapshots (auto texture)
	var full_new: Array = []

	func _init(d: MapData, p_label: String = "edit") -> void:
		data = d
		label = p_label

	func touch_h(i: int) -> void:
		if not h_old.has(i): h_old[i] = data.heights[i]

	func touch_splat(px: int, pz: int) -> void:
		var k := pz * data.splat_res + px
		if not s_old0.has(k):
			s_old0[k] = data.splat[0].get_pixel(px, pz).to_rgba32()
			s_old1[k] = data.splat[1].get_pixel(px, pz).to_rgba32()

	func snapshot_splat_full() -> void:
		full_old = [data.splat[0].get_data(), data.splat[1].get_data()]

	func snapshot_tiles() -> void: tiles_before = data.tiles.duplicate()

	func snapshot_waters() -> void: water_before = data.waters.duplicate(true)
	func snapshot_paths() -> void: paths_before = data.paths.duplicate(true)

	func is_empty() -> bool:
		return h_old.is_empty() and s_old0.is_empty() and obj_added.is_empty() and obj_removed.is_empty() and obj_moved.is_empty() and water_before == null and paths_before == null and full_old.is_empty() and tiles_before == null

	func finish() -> void:
		for i in h_old:
			h_idx.append(i); h_old_arr.append(h_old[i]); h_new.append(data.heights[i])
		for k in s_old0:
			s_idx.append(k)
			s_o0.append(s_old0[k]); s_o1.append(s_old1[k])
			var px: int = k % data.splat_res; var pz: int = k / data.splat_res
			s_n0.append(data.splat[0].get_pixel(px, pz).to_rgba32()); s_n1.append(data.splat[1].get_pixel(px, pz).to_rgba32())
		for m in obj_moved:
			moved_new.append(m[0].xf)
		if tiles_before != null: tiles_after = data.tiles.duplicate()
		if not full_old.is_empty(): full_new = [data.splat[0].get_data(), data.splat[1].get_data()]
		if water_before != null: water_after = data.waters.duplicate(true)
		if paths_before != null: paths_after = data.paths.duplicate(true)

var undo_stack: Array = []
var redo_stack: Array = []
var data: MapData

func _init(d: MapData) -> void:
	data = d

func begin(label: String = "edit") -> Stroke:
	return Stroke.new(data, label)

func commit(s: Stroke) -> void:
	if s.is_empty(): return
	s.finish()
	undo_stack.append(s)
	if undo_stack.size() > 60: undo_stack.pop_front()
	redo_stack.clear()
	stack_changed.emit()

## Reverts an uncommitted stroke (used when a second finger turns the gesture into a camera move).
func undo_stroke_now(s: Stroke) -> void:
	s.finish()
	_apply(s, true)

func can_undo() -> bool: return not undo_stack.is_empty()
func can_redo() -> bool: return not redo_stack.is_empty()

func undo() -> void:
	if undo_stack.is_empty(): return
	var s: Stroke = undo_stack.pop_back()
	_apply(s, true)
	redo_stack.append(s)
	stack_changed.emit()

func redo() -> void:
	if redo_stack.is_empty(): return
	var s: Stroke = redo_stack.pop_back()
	_apply(s, false)
	undo_stack.append(s)
	stack_changed.emit()

func _apply(s: Stroke, back: bool) -> void:
	if s.tiles_before != null:
		data.tiles = (s.tiles_before if back else s.tiles_after).duplicate()
		data._rebuild_mask()
		data.tiles_changed.emit()
	# heights
	if s.h_idx.size() > 0:
		var minx := 1 << 30; var minz := 1 << 30; var maxx := -1; var maxz := -1
		var src := s.h_old_arr if back else s.h_new
		for j in s.h_idx.size():
			var i := s.h_idx[j]
			data.heights[i] = src[j]
			var x := i % data.verts; var z := i / data.verts
			minx = mini(minx, x); maxx = maxi(maxx, x); minz = mini(minz, z); maxz = maxi(maxz, z)
		data.changed_region.emit(Rect2i(minx, minz, maxx - minx, maxz - minz))
	# splat
	if s.s_idx.size() > 0:
		var a0 := s.s_o0 if back else s.s_n0
		var a1 := s.s_o1 if back else s.s_n1
		var sx0 := 1 << 30; var sz0 := 1 << 30; var sx1 := -1; var sz1 := -1
		for j in s.s_idx.size():
			var k := s.s_idx[j]
			var px := k % data.splat_res; var pz := k / data.splat_res
			sx0 = mini(sx0, px); sx1 = maxi(sx1, px); sz0 = mini(sz0, pz); sz1 = maxi(sz1, pz)
			data.splat[0].set_pixel(px, pz, Color.hex(a0[j] & 0xFFFFFFFF))
			data.splat[1].set_pixel(px, pz, Color.hex(a1[j] & 0xFFFFFFFF))
		data.splat_region_changed.emit(Rect2i(sx0, sz0, sx1 - sx0, sz1 - sz0))
	if not s.full_old.is_empty():
		var src: Array = s.full_old if back else s.full_new
		for i in 2:
			data.splat[i] = Image.create_from_data(data.splat_res, data.splat_res, false, Image.FORMAT_RGBA8, src[i])
		data.splat_changed.emit()
	# objects
	if not s.obj_added.is_empty() or not s.obj_removed.is_empty() or not s.obj_moved.is_empty():
		var chunks: Dictionary = {}
		var add_list := s.obj_removed if back else s.obj_added
		var rem_list := s.obj_added if back else s.obj_removed
		for o in rem_list:
			chunks[data.obj_chunk(o.xf.origin)] = true
			data.remove_object(o)
		for o in add_list:
			data.add_object(o)
			chunks[data.obj_chunk(o.xf.origin)] = true
		for j in s.obj_moved.size():
			var o: MapObject = s.obj_moved[j][0]
			chunks[data.obj_chunk(o.xf.origin)] = true
			data.move_object(o, s.obj_moved[j][1] if back else s.moved_new[j])
			chunks[data.obj_chunk(o.xf.origin)] = true
		data.objects_changed.emit(chunks.keys())
	if s.water_before != null:
		data.waters = (s.water_before if back else s.water_after).duplicate(true)
		data.waters_changed.emit()
	if s.paths_before != null:
		data.paths = (s.paths_before if back else s.paths_after).duplicate(true)
		data.paths_changed.emit()
