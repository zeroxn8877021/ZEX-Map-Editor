# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : editor_ui.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name EditorUI
extends CanvasLayer
## Surveyor-style touch UI: top bar, tool column, contextual right panel, modals.
var ed: MapEditor
var root: Control
var _panel_box: VBoxContainer
var _panel_wrap: PanelContainer
var _toast: Label
var _toast_t := 0.0
var _status: Label
var _undo_btn: Button
var _redo_btn: Button
var _tool_btns: Dictionary = {}
var _cur_panel := ""
var _lib_cat := "All"
var _walk_ui: Control
var _fps: Label
var _auto := {"slope": 34.0, "snow_h": 70.0, "sand_h": 1.5, "dirt": 0.5, "l_flat": 0, "l_dirt": 1, "l_rock": 2, "l_snow": 4, "l_sand": 3}
var _gen := {"style": "hills", "cells": 256, "seed": 7.0, "amp": 30.0}

const TOOLS := [["ground", "Ground +"], ["sculpt", "Terrain"], ["paint", "Paint"], ["place", "Objects"], ["scatter", "Trees"], ["select", "Select"], ["water", "Water"], ["path", "Routes"], ["map", "Map"]]

func _ready() -> void:
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIKit.make_theme()
	add_child(root)
	_build_top()
	_build_left()
	_build_right()
	_build_misc()
	ed.assets.changed.connect(func(): if _cur_panel in ["place", "scatter", "path"]: _deferred_refresh())
	ed.assets.thumb_ready.connect(func(_i): if _cur_panel in ["place", "scatter", "path"]: _deferred_refresh())
	refresh_undo()

var _refresh_queued := false
func _deferred_refresh() -> void:
	if _refresh_queued: return
	_refresh_queued = true
	await get_tree().create_timer(0.25).timeout
	_refresh_queued = false
	refresh_panel()

# ------------------------------------------------------------------ layout
func _anchor(c: Control, preset: int) -> void:
	c.set_anchors_preset(preset)

func _build_top() -> void:
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_TOP_WIDE)
	pc.offset_left = 8; pc.offset_right = -8; pc.offset_top = 8; pc.offset_bottom = 68
	root.add_child(pc)
	var h := HBoxContainer.new(); pc.add_child(h)
	h.add_child(UIKit.btn("Menu", _open_menu, false, 44))
	_undo_btn = UIKit.btn("Undo", func(): ed.undo.undo(), false, 44); h.add_child(_undo_btn)
	_redo_btn = UIKit.btn("Redo", func(): ed.undo.redo(), false, 44); h.add_child(_redo_btn)
	h.add_child(UIKit.btn("Save", func(): ed.save_map(), false, 44))
	_status = Label.new(); _status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 16)
	_status.add_theme_color_override("font_color", UIKit.DIM)
	h.add_child(_status)
	var cam_b := UIKit.btn("Orbit", func(on): ed.P["cam_mode"] = on, true, 44)
	cam_b.tooltip_text = "One-finger camera orbit"
	h.add_child(cam_b)
	h.add_child(UIKit.btn("Grid", func(on): ed.P["grid"] = on; ed.terrain.set_grid(on), true, 44))
	h.add_child(UIKit.btn("Walk", func(): ed.enter_walk(), false, 44))
	h.add_child(UIKit.btn("Panel", func(): _panel_wrap.visible = not _panel_wrap.visible, false, 44))
	_fps = Label.new(); _fps.add_theme_font_size_override("font_size", 14); h.add_child(_fps)

func _build_left() -> void:
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	pc.offset_left = 8; pc.offset_top = 78; pc.offset_bottom = -8; pc.offset_right = 104
	pc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.add_child(pc)
	var v := VBoxContainer.new(); pc.add_child(v)
	v.add_theme_constant_override("separation", 6)
	var grp := ButtonGroup.new()
	for t in TOOLS:
		var b := Button.new()
		b.text = t[1]
		b.toggle_mode = true
		b.button_group = grp
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 62)
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 17)
		var id: String = t[0]
		b.pressed.connect(func(): _pick_tool(id))
		v.add_child(b)
		_tool_btns[id] = b
	_tool_btns["ground"].button_pressed = true

func _pick_tool(id: String) -> void:
	if id == "map":
		show_tool_panel("map")
	else:
		ed.set_tool(id)

func _build_right() -> void:
	_panel_wrap = PanelContainer.new()
	_panel_wrap.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel_wrap.offset_left = -352; _panel_wrap.offset_right = -8; _panel_wrap.offset_top = 78; _panel_wrap.offset_bottom = -8
	root.add_child(_panel_wrap)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel_wrap.add_child(sc)
	_panel_box = VBoxContainer.new()
	_panel_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_box.custom_minimum_size = Vector2(318, 0)
	sc.add_child(_panel_box)

func _build_misc() -> void:
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_toast.offset_top = -80; _toast.offset_bottom = -30; _toast.offset_left = -330; _toast.offset_right = 330
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_stylebox_override("normal", UIKit.box(Color(0, 0, 0, 0.78), 12))
	_toast.modulate.a = 0.0
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_toast)
	_walk_ui = Control.new()
	_walk_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_walk_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_walk_ui.visible = false
	root.add_child(_walk_ui)
	var ex := UIKit.btn("Exit walk", func(): ed.exit_walk(), false, 54)
	ex.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ex.offset_left = -190; ex.offset_right = -16; ex.offset_top = 16
	_walk_ui.add_child(ex)
	var hint := UIKit.hint("Left half: move  |  Right half: look")
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM); hint.offset_top = -60; hint.offset_left = -170
	_walk_ui.add_child(hint)

func set_walk(on: bool) -> void:
	_walk_ui.visible = on
	for c in root.get_children():
		if c != _walk_ui and c != _toast: c.visible = not on if c != _panel_wrap else not on

func toast(msg: String) -> void:
	_toast.text = msg
	_toast.modulate.a = 1.0
	_toast_t = 2.6

func _process(dt: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= dt
		if _toast_t < 0.5: _toast.modulate.a = maxf(_toast_t / 0.5, 0.0)
	if Engine.get_frames_drawn() % 20 == 0:
		_fps.text = "%d fps" % Engine.get_frames_per_second()
		var s := "%s   |   %d objects" % [ed.data.map_name, ed.data.objects.size()]
		if ed.tool != null and ed.tool.has_cursor:
			s += "   |   x %.0f  z %.0f  h %.1f m" % [ed.tool.cursor.x, ed.tool.cursor.z, ed.tool.cursor.y]
		_status.text = s

func refresh_undo() -> void:
	if _undo_btn == null: return
	_undo_btn.disabled = not ed.undo.can_undo()
	_redo_btn.disabled = not ed.undo.can_redo()

func on_map_changed() -> void:
	refresh_undo()
	show_tool_panel(_cur_panel if _cur_panel != "" else "ground")

func refresh_panel() -> void:
	show_tool_panel(_cur_panel)

# ------------------------------------------------------------------ panels
func _clear() -> void:
	for c in _panel_box.get_children():
		_panel_box.remove_child(c)
		c.queue_free()

func show_tool_panel(id: String) -> void:
	_cur_panel = id
	_clear()
	if _tool_btns.has(id): _tool_btns[id].button_pressed = true
	match id:
		"ground": _p_ground()
		"sculpt": _p_sculpt()
		"paint": _p_paint()
		"place": _p_place()
		"scatter": _p_scatter()
		"select": _p_select()
		"water": _p_water()
		"path": _p_path()
		"map": _p_map()

func _add(c: Control) -> Control:
	_panel_box.add_child(c)
	return c

func _brush_sliders(with_hardness := true) -> void:
	_add(UIKit.slider("Radius", ed.P, "radius", 2.0, 90.0, 1.0, Callable(), " m"))
	_add(UIKit.slider("Strength", ed.P, "strength", 0.05, 1.0, 0.05))
	if with_hardness: _add(UIKit.slider("Edge hardness", ed.P, "hardness", 0.0, 1.0, 0.05))

func _p_ground() -> void:
	_add(UIKit.header("GROUND TILES (50 x 50 m)"))
	_add(UIKit.mode_row([["add", "Add (+)"], ["remove", "Remove"]], ed.P["ground_mode"], func(m):
		ed.P["ground_mode"] = m
		ed.tools["ground"].refresh_ghosts()
		refresh_panel()))
	if ed.P["ground_mode"] == "add":
		_add(UIKit.hint("Tap a green + to add a ground plate next to the existing ground. Edges snap automatically."))
		_add(UIKit.btn("Add plates on all sides", func(): ed.tools["ground"].add_ring()))
	else:
		_add(UIKit.hint("Tap a ground plate to remove it (its data is kept hidden)."))
	var b := ed.data.active_bounds()
	_add(UIKit.hint("%d plates  |  %d x %d m  |  max %d x %d plates" % [ed.data.tiles.size(), int(b.size.x), int(b.size.y), MapData.MAX_T, MapData.MAX_T]))
	_add(UIKit.header("LOADING"))
	_add(UIKit.slider("Draw distance", ed.P, "view_range", 100.0, 1500.0, 25.0, func(v):
		ed.terrain.view_range = v
		ed.objects.radius = v
		ed.terrain.update_stream(), " m"))
	_add(UIKit.hint("Only ground, trees and objects inside this distance from the camera are loaded. Lower = faster on phones. Built plates now: %d" % ed.terrain.built_count()))

func _p_sculpt() -> void:
	_add(UIKit.header("TERRAIN BRUSH"))
	_add(UIKit.mode_row([["raise", "Raise"], ["lower", "Lower"], ["smooth", "Smooth"], ["flatten", "Flatten"], ["noise", "Rough"], ["level", "Level to"]], ed.P["sculpt_mode"], func(m): ed.P["sculpt_mode"] = m; refresh_panel()))
	_brush_sliders()
	if ed.P["sculpt_mode"] == "level":
		_add(UIKit.slider("Target height", ed.P, "level_h", -20.0, 150.0, 0.5, Callable(), " m"))
	_add(UIKit.hint("Hold and drag on the terrain. Two fingers: move / pinch zoom / twist. Tip: 'Orbit' in the top bar = one-finger camera."))

func _p_paint() -> void:
	_add(UIKit.header("TEXTURE BRUSH"))
	_add(UIKit.mode_row([["paint", "Paint"], ["erase", "Erase"], ["smart", "Smart"]], ed.P["paint_mode"], func(m): ed.P["paint_mode"] = m; refresh_panel()))
	_brush_sliders()
	if ed.P["paint_mode"] == "smart":
		_add(UIKit.slider("Cliff slope", ed.P, "smart_slope", 10.0, 70.0, 1.0, Callable(), " deg"))
		_add(UIKit.hint("Smart brush paints the selected layer on flat ground and the layer below on cliffs."))
		_add(UIKit.header("CLIFF LAYER"))
		_add(_layer_grid("smart_steep_layer"))
	_add(UIKit.header("PAINT LAYER  (tap = select, long list below)"))
	_add(_layer_grid("layer"))
	_add(UIKit.btn("Change material of this layer...", func():
		MaterialDialog.open(root, ed, ed.data.layer_mats[ed.P["layer"]], func(id):
			var slot: int = ed.P["layer"]
			if ed.data.layer_mats[slot] != id:
				ed.data.layer_mats[slot] = id
				ed.terrain.refresh_layer(slot)
			else:
				ed.terrain.refresh_tiling()
			refresh_panel())))
	_add(UIKit.header("AUTOMATION"))
	_add(UIKit.slider("Cliff angle", _auto, "slope", 15.0, 60.0, 1.0, Callable(), " deg"))
	_add(UIKit.slider("Snow above", _auto, "snow_h", 10.0, 200.0, 1.0, Callable(), " m"))
	_add(UIKit.slider("Sand below", _auto, "sand_h", -5.0, 20.0, 0.5, Callable(), " m"))
	_add(UIKit.slider("Dirt patches", _auto, "dirt", 0.0, 1.0, 0.05))
	_add(UIKit.btn("Auto-texture whole map", func(): AutoTools.auto_texture(ed, _auto)))
	_add(UIKit.hint("Uses layers: grass / dirt / rock / sand / snow slots (1,2,3,4,5)."))

func _layer_grid(key: String) -> Control:
	var g := GridContainer.new(); g.columns = 4
	g.add_theme_constant_override("h_separation", 6); g.add_theme_constant_override("v_separation", 6)
	var grp := ButtonGroup.new()
	for i in MapData.LAYERS:
		var b := Button.new()
		b.icon = ed.matlib.thumb(ed.data.layer_mats[i])
		b.expand_icon = true
		b.toggle_mode = true
		b.button_group = grp
		b.custom_minimum_size = Vector2(68, 68)
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = (ed.P[key] == i)
		b.tooltip_text = ed.matlib.mats[ed.data.layer_mats[i]]["name"]
		b.text = str(i + 1)
		b.add_theme_font_size_override("font_size", 14)
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		var idx := i
		b.pressed.connect(func(): ed.P[key] = idx)
		g.add_child(b)
	return g

func _asset_library(multi: bool) -> void:
	var cats := HFlowContainer.new(); _add(cats)
	for c in ["All"] + AssetLibrary.CATS:
		var b := UIKit.btn(c, func(): _lib_cat = c; refresh_panel(), false, 40)
		b.add_theme_font_size_override("font_size", 15)
		if c == _lib_cat: b.modulate = UIKit.ACCENT
		cats.add_child(b)
	var ids := ed.assets.ids_in(_lib_cat)
	if ed.assets.entries.is_empty():
		_add(UIKit.hint("Library is empty. Tap 'Import assets' (GLB / GLTF) - everything you import appears here automatically. On PC you can also drop files into res://import_assets/."))
	var grid := GridContainer.new(); grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6); grid.add_theme_constant_override("v_separation", 6)
	_add(grid)
	for id in ids:
		var e: Dictionary = ed.assets.entries[id]
		var b := Button.new()
		b.toggle_mode = true
		b.icon = ed.assets.thumb(id)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.text = e["name"]
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		b.custom_minimum_size = Vector2(96, 104)
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = (ed.P["asset"] == id) if not multi else ed.P["scatter_assets"].has(id)
		var aid: String = id
		b.pressed.connect(func():
			ed.P["asset"] = aid
			if multi:
				if ed.P["scatter_assets"].has(aid): ed.P["scatter_assets"].erase(aid)
				else: ed.P["scatter_assets"].append(aid)
			refresh_panel())
		grid.add_child(b)
	var row := HBoxContainer.new(); _add(row)
	var imp := UIKit.btn("Import assets", _import_assets); imp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(imp)
	var rf := UIKit.btn("Refresh", func(): ed.assets.scan()); rf.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(rf)
	if ed.P["asset"] != "" and ed.assets.entries.has(ed.P["asset"]):
		var cur: String = ed.P["asset"]
		_add(UIKit.hint("Selected: %s   (category: %s, auto-fit x%.3f)" % [cur, ed.assets.entries[cur]["category"], ed.assets.entries[cur].get("auto_scale", 1.0)]))
		var sm := {"v": ed.assets.get_scale_mul(cur)}
		_add(UIKit.slider("Asset size correction", sm, "v", 0.1, 5.0, 0.05, func(v): _debounce("assetscale", func(): ed.assets.set_scale_mul(cur, v)), " x"))
		var cr := HFlowContainer.new(); _add(cr)
		for c in AssetLibrary.CATS:
			var cb := UIKit.btn(c, func(): ed.assets.set_category(cur, c), false, 36)
			cb.add_theme_font_size_override("font_size", 13)
			cr.add_child(cb)

func _import_assets() -> void:
	FileBrowser.open(root, "Import 3D models / textures", ["glb", "gltf", "png", "jpg", "jpeg", "webp"], true, func(paths):
		var n := 0
		for p in paths:
			var r: String = ed.assets.import_file(p)
			if r != "": n += 1
			if r != "" and not r.begins_with("tex:") and ed.P["asset"] == "": ed.P["asset"] = r
		toast("Imported %d file(s)" % n)
		refresh_panel())

func _placement_sliders() -> void:
	_add(UIKit.slider("Size min", ed.P, "scale_min", 0.1, 4.0, 0.05))
	_add(UIKit.slider("Size max", ed.P, "scale_max", 0.1, 4.0, 0.05))
	_add(UIKit.slider("Align to slope", ed.P, "align", 0.0, 1.0, 0.05))
	_add(UIKit.slider("Sink into ground", ed.P, "sink", -1.0, 2.0, 0.05, Callable(), " m"))
	_add(UIKit.toggle("Random rotation", ed.P, "random_yaw", func(_o): refresh_panel()))
	if not ed.P["random_yaw"]:
		_add(UIKit.slider("Rotation", ed.P, "yaw", 0.0, TAU, 0.05))

func _p_place() -> void:
	_add(UIKit.header("PLACE OBJECTS  -  touch ground, slide, lift"))
	_asset_library(false)
	_add(UIKit.toggle("Random size", ed.P, "random_scale"))
	_placement_sliders()

func _p_scatter() -> void:
	_add(UIKit.header("TREE / VEGETATION BRUSH"))
	_add(UIKit.mode_row([["paint", "Plant"], ["erase", "Remove"]], ed.P["scatter_mode"], func(m): ed.P["scatter_mode"] = m))
	_add(UIKit.slider("Radius", ed.P, "radius", 3.0, 90.0, 1.0, Callable(), " m"))
	_add(UIKit.slider("Density /100 m2", ed.P, "density", 0.2, 20.0, 0.2))
	_add(UIKit.slider("Min spacing", ed.P, "spacing", 0.3, 15.0, 0.1, Callable(), " m"))
	_add(UIKit.slider("Max slope", ed.P, "slope_max", 5.0, 80.0, 1.0, Callable(), " deg"))
	_add(UIKit.slider("Lowest height", ed.P, "min_h", -50.0, 200.0, 1.0, Callable(), " m"))
	_add(UIKit.slider("Highest height", ed.P, "max_h", -50.0, 500.0, 1.0, Callable(), " m"))
	_placement_sliders()
	_add(UIKit.toggle("Remove only selected assets", ed.P, "erase_selected_only"))
	_add(UIKit.header("PICK ONE OR MORE ASSETS"))
	_asset_library(true)
	_add(UIKit.header("AUTO FILL"))
	_add(UIKit.hint("Fills every spot painted with the layer below. Uses density + rules above."))
	_add(_layer_grid("layer"))
	_add(UIKit.btn("Fill painted layer with selection", func():
		var pool: Array = ed.P["scatter_assets"].duplicate()
		if pool.is_empty() and ed.P["asset"] != "": pool.append(ed.P["asset"])
		AutoTools.fill_layer(ed, ed.P["layer"], pool, ed.P["density"])))

func _p_select() -> void:
	_add(UIKit.header("SELECT / EDIT OBJECT"))
	var o := ed.selected
	if o == null:
		_add(UIKit.hint("Tap an object to select it. Drag it to move. Then rotate / scale / delete here."))
		_add(UIKit.hint("Objects: %d" % ed.data.objects.size()))
		return
	_add(UIKit.hint("Selected: %s" % o.asset))
	var st := {"yaw": rad_to_deg(o.xf.basis.get_euler().y), "scale": o.xf.basis.get_scale().x, "lift": 0.0}
	_add(UIKit.slider("Rotate", st, "yaw", -180.0, 180.0, 1.0, func(v): _commit_edit_delayed(func(xf: Transform3D):
		var sc := xf.basis.get_scale()
		return Transform3D(Basis(Vector3.UP, deg_to_rad(v)).scaled(sc), xf.origin)), " deg"))
	_add(UIKit.slider("Size", st, "scale", 0.1, 5.0, 0.05, func(v): _commit_edit_delayed(func(xf: Transform3D):
		var e := xf.basis.orthonormalized()
		return Transform3D(e.scaled(Vector3.ONE * v), xf.origin))))
	_add(UIKit.slider("Lift", st, "lift", -3.0, 6.0, 0.05, func(v): _commit_edit_delayed(func(xf: Transform3D):
		var g := ed.data.height_at(xf.origin.x, xf.origin.z)
		return Transform3D(xf.basis, Vector3(xf.origin.x, g + v, xf.origin.z))), " m"))
	_add(UIKit.btn("Snap to ground", func(): ed.edit_selected(func(xf: Transform3D): return Transform3D(xf.basis, Vector3(xf.origin.x, ed.data.height_at(xf.origin.x, xf.origin.z), xf.origin.z)), "Snap")))
	_add(UIKit.btn("Duplicate", func(): ed.duplicate_selected(); refresh_panel()))
	_add(UIKit.btn("Delete", func(): ed.delete_selected()))

var _deb: Dictionary = {}
func _debounce(key: String, fn: Callable, delay := 0.35) -> void:
	var t := get_tree().create_timer(delay)
	_deb[key] = t
	await t.timeout
	if _deb.get(key) == t: fn.call()

var _edit_timer: SceneTreeTimer
var _edit_fn: Callable
func _commit_edit_delayed(fn: Callable) -> void:
	# live preview while the slider moves, one undo step after it settles
	_edit_fn = fn
	if ed.selected == null: return
	var o := ed.selected
	var nx: Transform3D = fn.call(o.xf)
	var ch := [ed.data.obj_chunk(o.xf.origin)]
	ed.data.move_object(o, nx)
	ed.data.objects_changed.emit(ch)
	ed.update_selection_marker()

func _p_water() -> void:
	_add(UIKit.header("WATER"))
	_add(UIKit.mode_row([["lake", "Lake"], ["ocean", "Ocean"], ["plane", "Pool"]], ed.P["water_mode"], func(m): ed.P["water_mode"] = m; refresh_panel()))
	var presets := []
	for k in WaterPresets.PRESETS: presets.append([k, WaterPresets.PRESETS[k]["name"]])
	_add(UIKit.header("LOOK"))
	_add(UIKit.mode_row(presets, ed.P["water_preset"], func(m): ed.P["water_preset"] = m, 2))
	match ed.P["water_mode"]:
		"lake":
			_add(UIKit.slider("Fill height above tap", ed.P, "water_offset", 0.2, 12.0, 0.1, Callable(), " m"))
			_add(UIKit.hint("Tap inside a hollow / dug basin. The water fills it up to that height and the shoreline, depth colour and foam follow the terrain."))
		"ocean":
			_add(UIKit.slider("Sea level", ed.P, "sea_level", -10.0, 60.0, 0.5, Callable(), " m"))
			_add(UIKit.hint("Tap anywhere: floods every low area of the map and extends to the horizon."))
		"plane":
			_add(UIKit.slider("Width", ed.P, "plane_w", 4.0, 200.0, 1.0, Callable(), " m"))
			_add(UIKit.slider("Length", ed.P, "plane_d", 4.0, 200.0, 1.0, Callable(), " m"))
			_add(UIKit.slider("Depth", ed.P, "plane_depth", 0.5, 8.0, 0.1, Callable(), " m"))
			_add(UIKit.slider("Height above tap", ed.P, "water_offset", -1.0, 6.0, 0.1, Callable(), " m"))
			_add(UIKit.slider("Rotation", ed.P, "yaw", 0.0, TAU, 0.05))
			_add(UIKit.hint("Tap to drop a water plane like an object (pools, ponds on flat ground)."))
	_add(UIKit.header("WATER IN MAP (%d)" % ed.data.waters.size()))
	for i in ed.data.waters.size():
		var w: Dictionary = ed.data.waters[i]
		var row := HBoxContainer.new(); _add(row)
		var b := UIKit.btn("%s  %s  @%.1f" % [w["kind"], w["preset"], w["level"]], func(): ed.selected_water = i; refresh_panel(), false, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i == ed.selected_water: b.modulate = UIKit.ACCENT
		row.add_child(b)
		row.add_child(UIKit.btn("X", func():
			var st := ed.undo.begin("Delete water")
			st.snapshot_waters()
			ed.data.waters.remove_at(i)
			ed.water.rebuild_all()
			ed.undo.commit(st)
			ed.selected_water = -1
			refresh_panel(), false, 44))
	if ed.selected_water >= 0 and ed.selected_water < ed.data.waters.size():
		var w2: Dictionary = ed.data.waters[ed.selected_water]
		var holder := {"level": w2["level"]}
		_add(UIKit.slider("Water level", holder, "level", -20.0, 150.0, 0.1, func(v):
			w2["level"] = v
			ed.water.rebuild_all(), " m"))

func _p_path() -> void:
	_add(UIKit.header("ROUTES  (road / rail / river / object line)"))
	_add(UIKit.mode_row([["road", "Road"], ["rail", "Rail"], ["river", "River"], ["line", "Object line"]], ed.P["path_type"], func(m): ed.P["path_type"] = m; refresh_panel(), 2))
	var ap: Dictionary = ed.data.paths[ed.active_path] if ed.active_path >= 0 and ed.active_path < ed.data.paths.size() else {}
	var live := func(key: String) -> Callable:
		return func(v):
			if not ap.is_empty():
				ap[key] = v
				ed.path_dirty = true
	var t: String = ap.get("type", ed.P["path_type"])
	if t == "road" or t == "river":
		var dw := {"v": ap.get("width", ed.P["path_width"])}
		_add(UIKit.slider("Width", dw, "v", 2.0, 40.0, 0.5, func(v): ed.P["path_width"] = v; live.call("width").call(v), " m"))
	if t == "rail":
		_add(UIKit.hint("Rail: ballast bed + sleepers + two rails (built-in track). Use 'Objects' with your own rail asset for custom track."))
	if t != "line":
		var ds := {"v": ap.get("shoulder", ed.P["path_shoulder"])}
		_add(UIKit.slider("Blend into terrain", ds, "v", 1.0, 20.0, 0.5, func(v): ed.P["path_shoulder"] = v; live.call("shoulder").call(v), " m"))
	if t == "river":
		var dd := {"v": ap.get("depth", ed.P["path_depth"])}
		_add(UIKit.slider("Depth", dd, "v", 0.5, 5.0, 0.1, func(v): ed.P["path_depth"] = v; live.call("depth").call(v), " m"))
	if t == "line":
		var sp := {"v": ap.get("spacing", ed.P["path_spacing"])}
		_add(UIKit.slider("Spacing", sp, "v", 0.3, 20.0, 0.1, func(v): ed.P["path_spacing"] = v; live.call("spacing").call(v), " m"))
		var off := {"v": ap.get("offset", ed.P["path_offset"])}
		_add(UIKit.slider("Side offset", off, "v", -10.0, 10.0, 0.1, func(v): ed.P["path_offset"] = v; live.call("offset").call(v), " m"))
		_add(UIKit.hint("Uses the asset selected below."))
		_asset_library(false)
		if not ap.is_empty() and ap.get("asset", "") != ed.P["asset"]:
			ap["asset"] = ed.P["asset"]
			ed.path_dirty = true
	_add(UIKit.header("ACTIONS"))
	_add(UIKit.btn("New route", func(): ed.new_path(); refresh_panel()))
	var row := HBoxContainer.new(); _add(row)
	var c1 := UIKit.btn("Close loop", func(on):
		if not ap.is_empty(): ap["closed"] = on; ed.rebuild_active_path(), true, 46)
	c1.button_pressed = ap.get("closed", false)
	c1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(c1)
	var c2 := UIKit.btn("Del point", func():
		if ap.is_empty() or ed.sel_point < 0: return
		var st := ed.undo.begin("Delete point"); st.snapshot_paths()
		var pts: PackedVector3Array = ap["points"]; pts.remove_at(ed.sel_point); ap["points"] = pts
		ed.sel_point = -1
		ed.undo.commit(st); ed.rebuild_active_path(), false, 46)
	c2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(c2)
	if t != "line":
		_add(UIKit.btn("Apply to terrain", func():
			if ap.is_empty(): return
			var st := ed.undo.begin("Apply route")
			PathTerrain.apply(ed.data, ap, st)
			ed.undo.commit(st)
			ed.rebuild_active_path()
			toast("Route applied to terrain")))
	_add(UIKit.btn("Delete route", func():
		if ap.is_empty(): return
		var st := ed.undo.begin("Delete route"); st.snapshot_paths()
		ed.data.paths.remove_at(ed.active_path)
		ed.undo.commit(st)
		ed.active_path = -1; ed.sel_point = -1
		ed.paths.rebuild_all(); ed.update_path_markers(); refresh_panel()))
	_add(UIKit.header("ROUTES IN MAP (%d)" % ed.data.paths.size()))
	for i in ed.data.paths.size():
		var b := UIKit.btn("%s  (%d pts)" % [ed.data.paths[i]["name"], ed.data.paths[i]["points"].size()], func():
			ed.active_path = i; ed.sel_point = -1; ed.update_path_markers(); refresh_panel(), false, 44)
		if i == ed.active_path: b.modulate = UIKit.ACCENT
		_add(b)
	_add(UIKit.hint("Tap ground = add point. Tap on the line = insert. Drag a point to move it."))

func _p_map() -> void:
	_add(UIKit.header("MAP"))
	_add(UIKit.hint("%s   %d x %d m   cells %d" % [ed.data.map_name, int(ed.data.size), int(ed.data.size), ed.data.cells]))
	_add(UIKit.btn("Save map", func(): ed.save_map()))
	_add(UIKit.btn("Open / New / Export...", _open_menu))
	_add(UIKit.header("VIEW"))
	_add(UIKit.toggle("Shadows", ed.P, "shadows", func(on): ed.sun.shadow_enabled = on; ed.objects.shadows = on; ed.objects.apply_settings()))
	_add(UIKit.slider("Object view distance (0=inf)", ed.P, "view_dist", 0.0, 600.0, 10.0, func(v): ed.objects.view_distance = v; ed.paths.view_distance = v; ed.objects.apply_settings(), " m"))
	_add(UIKit.slider("Sun height", ed.P, "sun_pitch", -85.0, -8.0, 1.0, func(_v): ed.apply_sun(), " deg"))
	_add(UIKit.slider("Sun direction", ed.P, "sun_yaw", -180.0, 180.0, 1.0, func(_v): ed.apply_sun(), " deg"))
	_add(UIKit.header("NEW TERRAIN"))
	_add(UIKit.mode_row([["flat", "Flat"], ["hills", "Hills"], ["mountains", "Mountains"], ["island", "Island"]], _gen["style"], func(m): _gen["style"] = m, 2))
	_add(UIKit.mode_row([["128", "256 m"], ["256", "512 m"], ["384", "768 m"]], str(_gen["cells"]), func(m): _gen["cells"] = int(m)))
	_add(UIKit.slider("Seed", _gen, "seed", 1.0, 99.0, 1.0))
	_add(UIKit.btn("Create new map (clears current)", func():
		ed.new_map(_gen["cells"], _gen["style"], int(_gen["seed"]))))

# ------------------------------------------------------------------ menu / dialogs
func _open_menu() -> void:
	var m := Control.new(); m.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.55); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_child(dim)
	var pc := PanelContainer.new(); pc.position = Vector2(380, 50); pc.custom_minimum_size = Vector2(520, 620)
	pc.add_theme_stylebox_override("panel", UIKit.box(UIKit.BG2, 16))
	m.add_child(pc)
	var sc := ScrollContainer.new(); pc.add_child(sc)
	var v := VBoxContainer.new(); v.size_flags_horizontal = Control.SIZE_EXPAND_FILL; sc.add_child(v)
	v.add_child(UIKit.header("PROJECT"))
	var name_edit := LineEdit.new(); name_edit.text = ed.data.map_name; name_edit.custom_minimum_size = Vector2(0, 48)
	v.add_child(name_edit)
	v.add_child(UIKit.btn("Save", func(): ed.save_map(name_edit.text); m.queue_free()))
	v.add_child(UIKit.header("OPEN"))
	var maps := ed.list_maps()
	if maps.is_empty(): v.add_child(UIKit.hint("No saved maps yet."))
	for mp in maps:
		var n: String = mp
		v.add_child(UIKit.btn(n, func():
			if ed.load_map("%s/%s.zexmap" % [MapEditor.MAPS_DIR, n]): toast("Loaded " + n)
			m.queue_free(), false, 46))
	v.add_child(UIKit.header("EXPORT"))
	v.add_child(UIKit.btn("Export whole map as GLB", func(): m.queue_free(); _export("glb")))
	v.add_child(UIKit.btn("Export heightmap + splat + objects.json", func(): m.queue_free(); _export("data")))
	v.add_child(UIKit.hint("Exports go to Downloads/ZEXMaps (or the app folder if the device blocks it)."))
	v.add_child(UIKit.header("ASSETS"))
	v.add_child(UIKit.btn("Import assets (GLB / textures)", func(): m.queue_free(); _import_assets()))
	v.add_child(UIKit.btn("Close", func(): m.queue_free(), false, 54))
	v.add_child(UIKit.hint("Developed by Zex Interactive | Paras Sharma"))
	root.add_child(m)

func _export(kind: String) -> void:
	var ex := MapExporter.new()
	ex.ed = ed
	toast("Exporting...")
	await get_tree().process_frame
	var res: String
	if kind == "glb": res = await ex.export_glb()
	else: res = ex.export_data()
	toast(res)
