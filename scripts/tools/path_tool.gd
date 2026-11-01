# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : path_tool.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name PathTool
extends EditorTool
## Trainz-style route drawing: tap to drop control points (they snap to the terrain), tap on the line to insert, drag a point
## to move it. Road / Rail / River / Object-line (any library asset along the curve: fence, wall, poles ...).
var _press := Vector2.ZERO
var _drag_pt := -1
var _stroke_pts: UndoManager.Stroke
var _acc := 0.0

func _init() -> void:
	tool_name = "path"
	brush_color = Color(1.0, 0.6, 0.2)

func _pts() -> PackedVector3Array:
	if ed.active_path < 0 or ed.active_path >= ed.data.paths.size(): return PackedVector3Array()
	return ed.data.paths[ed.active_path]["points"]

func begin(pos: Vector2) -> void:
	super.begin(pos)
	_press = pos
	_drag_pt = -1
	var pts := _pts()
	for i in pts.size():
		var sp := ed.cam.cam.unproject_position(pts[i])
		if not ed.cam.cam.is_position_behind(pts[i]) and sp.distance_to(pos) < 46.0:
			_drag_pt = i
			ed.sel_point = i
			_stroke_pts = ed.undo.begin("Move point")
			_stroke_pts.snapshot_paths()
			ed.update_path_markers()
			return

func drag(pos: Vector2) -> void:
	update_cursor(pos)
	if _drag_pt >= 0 and has_cursor:
		var pts := _pts()
		pts[_drag_pt] = Vector3(cursor.x, ed.data.height_at(cursor.x, cursor.z), cursor.z)
		ed.data.paths[ed.active_path]["points"] = pts
		_acc = 0.0
		ed.path_dirty = true
		ed.update_path_markers()

func end() -> void:
	super.end()
	if _drag_pt >= 0:
		if _stroke_pts != null:
			ed.undo.commit(_stroke_pts); _stroke_pts = null
		ed.rebuild_active_path()
		_drag_pt = -1
		return
	if _press.distance_to(ed.last_pointer) > 14.0 or not has_cursor: return
	# tap: add / insert a point
	var st := ed.undo.begin("Path point")
	st.snapshot_paths()
	if ed.active_path < 0 or ed.active_path >= ed.data.paths.size():
		ed.new_path()
	var pts := _pts()
	var np := Vector3(cursor.x, ed.data.height_at(cursor.x, cursor.z), cursor.z)
	var insert_at := pts.size()
	var best := 20.0
	for i in pts.size() - 1:
		var a := ed.cam.cam.unproject_position(pts[i]); var b := ed.cam.cam.unproject_position(pts[i + 1])
		var cp := Geometry2D.get_closest_point_to_segment(_press, a, b)
		var dd := cp.distance_to(_press)
		if dd < best: best = dd; insert_at = i + 1
	pts.insert(insert_at, np)
	ed.data.paths[ed.active_path]["points"] = pts
	ed.sel_point = insert_at
	ed.undo.commit(st)
	ed.rebuild_active_path()
	ed.update_path_markers()
	ed.refresh_panel()
