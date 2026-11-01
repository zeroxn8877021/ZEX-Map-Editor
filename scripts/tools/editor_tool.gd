# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : editor_tool.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name EditorTool
extends RefCounted
## Base class: one finger tool. The editor feeds begin/drag/end with screen positions; tools read shared brush settings
## from ed.P (a Dictionary the UI sliders write into).
var ed: MapEditor
var active := false
var cursor := Vector3.ZERO
var has_cursor := false
var stroke: UndoManager.Stroke
var tool_name := "tool"
var brush_color := Color(1.0, 0.85, 0.2)

func setup(e: MapEditor) -> void: ed = e
func activate() -> void: pass
func deactivate() -> void:
	active = false
	ed.terrain.set_brush(Vector3.ZERO, 1.0, false)

func ground(pos: Vector2) -> Variant:
	return ed.cam.screen_to_ground(pos)

func update_cursor(pos: Vector2) -> void:
	var g = ground(pos)
	has_cursor = g != null
	if has_cursor: cursor = g
	_show_brush()

func _show_brush() -> void:
	if has_cursor and uses_brush():
		ed.terrain.set_brush(cursor, ed.P["radius"], true, brush_color)
	else:
		ed.terrain.set_brush(Vector3.ZERO, 1.0, false)

func uses_brush() -> bool: return false
func begin(pos: Vector2) -> void: active = true; update_cursor(pos)
func drag(pos: Vector2) -> void: update_cursor(pos)
func end() -> void: active = false
func cancel() -> void:
	active = false
	if stroke != null:
		ed.undo.undo_stroke_now(stroke)
		stroke = null
func tick(_dt: float) -> void: pass
func hover(pos: Vector2) -> void: update_cursor(pos)

static func falloff(d: float, r: float, hardness: float) -> float:
	if d >= r: return 0.0
	var t := d / r
	return 1.0 - smoothstep(hardness * 0.85, 1.0, t)
