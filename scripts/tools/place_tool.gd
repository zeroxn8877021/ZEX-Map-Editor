# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : place_tool.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name PlaceTool
extends EditorTool
## Single object placement: finger down shows a ghost that sticks to the terrain (position + slope aligned), move to
## adjust, lift to place. Two-finger gestures cancel it.
var _ghost: Node3D
var _ghost_asset := ""

func _init() -> void:
	tool_name = "place"
	brush_color = Color(0.5, 1.0, 0.5)

func deactivate() -> void:
	super.deactivate()
	_clear_ghost()

func _clear_ghost() -> void:
	if _ghost != null:
		_ghost.queue_free(); _ghost = null; _ghost_asset = ""

func _ensure_ghost() -> void:
	var a: String = ed.P["asset"]
	if a == "" or not ed.assets.entries.has(a):
		_clear_ghost(); return
	if _ghost != null and _ghost_asset == a: return
	_clear_ghost()
	_ghost = ed.assets.make_instance(a)
	for c in _ghost.get_children():
		(c as GeometryInstance3D).transparency = 0.45
		(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ed.add_child(_ghost)
	_ghost_asset = a

var _xf := Transform3D.IDENTITY

func _place_ghost() -> void:
	_ensure_ghost()
	if _ghost == null or not has_cursor:
		if _ghost: _ghost.visible = false
		return
	_ghost.visible = true
	_xf = ed.make_xf(cursor, ed.P["yaw"] if not ed.P["random_yaw"] else _ghost_yaw, 1.0 if not ed.P["random_scale"] else _ghost_scale)
	_ghost.global_transform = _xf

var _ghost_yaw := 0.0
var _ghost_scale := 1.0

func hover(pos: Vector2) -> void:
	update_cursor(pos)
	_place_ghost()

func begin(pos: Vector2) -> void:
	_roll()
	super.begin(pos)
	_place_ghost()

func drag(pos: Vector2) -> void:
	update_cursor(pos)
	_place_ghost()

func _roll() -> void:
	_ghost_yaw = randf() * TAU
	_ghost_scale = randf_range(ed.P["scale_min"], ed.P["scale_max"])

func end() -> void:
	super.end()
	if has_cursor and _ghost != null and _ghost.visible:
		var o := MapObject.make(ed.P["asset"], _xf)
		var st := ed.undo.begin("Place")
		st.obj_added.append(o)
		ed.data.add_object(o)
		ed.data.objects_added.emit([o])
		ed.undo.commit(st)
		ed.toast("Placed %s  (%d objects)" % [ed.P["asset"], ed.data.objects.size()])
		_roll()
		_place_ghost()

func cancel() -> void:
	active = false
	_clear_ghost()
