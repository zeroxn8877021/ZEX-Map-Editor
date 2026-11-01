# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : water_tool.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name WaterTool
extends EditorTool
## Water like an object: tap a hollow -> lake that fills the basin to the chosen level (shore + depth colour automatic),
## Ocean sets a map-wide sea level, Pool places a fixed-depth rectangular water plane.
var _press := Vector2.ZERO

func _init() -> void:
	tool_name = "water"
	brush_color = Color(0.3, 0.8, 1.0)

func begin(pos: Vector2) -> void:
	super.begin(pos)
	_press = pos

func end() -> void:
	super.end()
	if _press.distance_to(ed.last_pointer) > 14.0 or not has_cursor: return
	var st := ed.undo.begin("Water")
	st.snapshot_waters()
	var mode: String = ed.P["water_mode"]
	var w := {"preset": ed.P["water_preset"], "kind": mode}
	match mode:
		"lake":
			w["level"] = ed.data.height_at(cursor.x, cursor.z) + ed.P["water_offset"]
			w["seed"] = [cursor.x, cursor.z]
		"ocean":
			w["level"] = ed.P["sea_level"]
			ed.data.waters = ed.data.waters.filter(func(x): return x["kind"] != "ocean")
		"plane":
			w["level"] = ed.data.height_at(cursor.x, cursor.z) + ed.P["water_offset"]
			w["center"] = [cursor.x, cursor.z]
			w["size"] = [ed.P["plane_w"], ed.P["plane_d"]]
			w["depth"] = ed.P["plane_depth"]
			w["yaw"] = ed.P["yaw"]
	ed.data.waters.append(w)
	var msg := "Water added"
	if mode == "lake":
		# if the basin overflows, lower the level step by step until it holds
		var base_h: float = ed.data.height_at(cursor.x, cursor.z)
		var off: float = ed.P["water_offset"]
		ed.water.rebuild_all()
		var tries := 0
		while ed.water.overflow and tries < 14:
			off *= 0.7; tries += 1
			w["level"] = base_h + off
			ed.water.rebuild_all()
		if ed.water.overflow:
			ed.data.waters.pop_back()
			ed.water.rebuild_all()
			ed.toast("No basin here - dig a hollow with the Terrain tool first")
			return
		if tries > 0: msg = "Basin overflows - filled to %.1f m instead" % off
	else:
		ed.water.rebuild_all()
	ed.selected_water = ed.data.waters.size() - 1
	ed.undo.commit(st)
	ed.data.waters_changed.emit()
	ed.toast(msg)
	ed.refresh_panel()
