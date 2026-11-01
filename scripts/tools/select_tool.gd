# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : select_tool.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name SelectTool
extends EditorTool
## Tap an object to select it; drag it to move (stays on the ground). Rotation / scale / delete / duplicate live in the panel.
var _press_pos := Vector2.ZERO
var _moving := false
var _grab := Vector3.ZERO
var _moved_stroke: UndoManager.Stroke

func _init() -> void:
	tool_name = "select"

func begin(pos: Vector2) -> void:
	super.begin(pos)
	_press_pos = pos
	_moving = false
	var sel: MapObject = ed.selected
	if sel != null:
		var sp := ed.cam.cam.unproject_position(sel.xf.origin + Vector3(0, 1.0, 0))
		if sp.distance_to(pos) < 70.0 and has_cursor:
			_moving = true
			_grab = sel.xf.origin - cursor
			_moved_stroke = ed.undo.begin("Move")
			_moved_stroke.obj_moved.append([sel, sel.xf])

func drag(pos: Vector2) -> void:
	update_cursor(pos)
	if _moving and has_cursor and ed.selected != null:
		var o: MapObject = ed.selected
		var old_chunk := ed.data.obj_chunk(o.xf.origin)
		var np := cursor + Vector3(_grab.x, 0, _grab.z)
		np.y = ed.data.height_at(np.x, np.z) + (o.xf.origin.y - ed.data.height_at(o.xf.origin.x, o.xf.origin.z))
		var xf := o.xf
		xf.origin = np
		ed.data.move_object(o, xf)
		ed.data.objects_changed.emit([old_chunk, ed.data.obj_chunk(np)])
		ed.update_selection_marker()

func end() -> void:
	super.end()
	if _moving and _moved_stroke != null:
		ed.undo.commit(_moved_stroke)
		_moved_stroke = null
	elif _press_pos.distance_to(ed.last_pointer) < 14.0:
		ed.select_at(_press_pos)
	_moving = false

func cancel() -> void:
	super.cancel()
	_moving = false
