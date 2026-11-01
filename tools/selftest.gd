# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : selftest.gd
# Copyright : (c) Zex Interactive. All rights reserved.

extends Node
## Functional self test (run with xvfb + gl_compatibility like shot.tscn). Prints PASS/FAIL lines and exits.
var ed: MapEditor
var fails := 0

func check(c: bool, msg: String) -> void:
	print(("PASS  " if c else "FAIL  ") + msg)
	if not c: fails += 1

func _ready() -> void:
	ed = load("res://scenes/editor.tscn").instantiate()
	add_child(ed)
	await _frames(6)
	var d: MapData = ed.data
	check(d.tiles.size() == 1 and absf(d.height_at(0, 0)) < 0.001, "default map = one flat 50x50 tile")
	for tz in range(-2, 3):
		for tx in range(-2, 3): d.add_tile(Vector2i(tx, tz))
	check(d.tiles.size() == 25, "ground tiles can be added (+ snap)")
	await _frames(6)
	# ---------- gestures through real input events
	ed.set_tool("sculpt"); ed.P["radius"] = 12.0; ed.P["strength"] = 1.0; ed.P["sculpt_mode"] = "raise"
	var c0 := Vector2(600, 400)
	var h_before := d.height_at(0, 0)
	var sum_before := _sum(d.heights)
	_touch(0, c0, true); await get_tree().create_timer(0.3).timeout
	_drag(0, c0 + Vector2(30, 10)); await get_tree().create_timer(0.3).timeout
	_touch(0, c0 + Vector2(30, 10), false); await _frames(3)
	check(_sum(d.heights) > sum_before + 1.0, "one-finger drag sculpts terrain")
	check(ed.undo.can_undo(), "stroke recorded for undo")
	var dist0 := ed.cam._t_dist
	var sum1 := _sum(d.heights)
	_touch(0, Vector2(500, 400), true); _touch(1, Vector2(700, 400), true); await _frames(2)
	_drag(0, Vector2(450, 400)); _drag(1, Vector2(750, 400)); await _frames(2)
	_touch(0, Vector2(450, 400), false); _touch(1, Vector2(750, 400), false); await _frames(3)
	check(ed.cam._t_dist < dist0, "pinch zooms the camera in")
	check(absf(_sum(d.heights) - sum1) < 0.01, "two-finger gesture does not sculpt")
	# ---------- undo / redo heights
	var s_now := _sum(d.heights)
	ed.undo.undo()
	check(_sum(d.heights) < s_now - 1.0, "undo reverts heights")
	ed.undo.redo()
	check(absf(_sum(d.heights) - s_now) < 0.01, "redo restores heights")
	# ---------- paint + undo
	ed.set_tool("paint"); ed.P["layer"] = 2; ed.P["radius"] = 10.0; ed.P["strength"] = 1.0
	var t: PaintTool = ed.tool
	t.stroke = ed.undo.begin("Paint"); t.active = true; t.cursor = Vector3(20, 0, 20); t.has_cursor = true
	t.apply(t.cursor, 0.5)
	ed.undo.commit(t.stroke); t.stroke = null; t.active = false
	check(d.dominant_layer(20, 20) == 2, "paint brush paints layer 2")
	ed.undo.undo()
	check(d.dominant_layer(20, 20) == 0, "undo reverts paint")
	# ---------- place / select / delete
	ed.set_tool("place"); ed.P["asset"] = "tree" if ed.assets.entries.has("tree") else ""
	if ed.P["asset"] != "":
		var po := _scr(Vector3(10, 0, 10))
		ed.last_pointer = po
		ed.tool.begin(po); await _frames(1); ed.tool.end()
		check(d.objects.size() == 1, "place tool adds one object")
		var o: MapObject = d.objects[0]
		check(absf(o.xf.origin.y - d.height_at(o.xf.origin.x, o.xf.origin.z)) < 0.01 + ed.P["sink"], "object snaps to ground")
		ed.set_tool("select")
		var sp := ed.cam.cam.unproject_position(o.xf * ed.assets.get_aabb("tree").get_center())
		ed.last_pointer = sp
		ed.tool.begin(sp); ed.tool.end()
		check(ed.selected == o, "select tool picks the object")
		ed.duplicate_selected()
		check(d.objects.size() == 2, "duplicate")
		ed.delete_selected()
		check(d.objects.size() == 1, "delete")
		ed.undo.undo(); ed.undo.undo()
		check(d.objects.size() == 1, "undo delete + duplicate")
		# scatter + erase
		ed.set_tool("scatter"); ed.P["scatter_assets"] = ["tree"]; ed.P["radius"] = 25.0; ed.P["density"] = 2.0; ed.P["spacing"] = 3.0
		var st: ScatterTool = ed.tool
		st.stroke = ed.undo.begin("Scatter")
		var n := st.scatter_at(Vector3(-60, 0, -60))
		ed.undo.commit(st.stroke)
		check(n > 20, "scatter places many trees (%d)" % n)
		var mind := 999.0
		for i in range(1, d.objects.size()):
			for j in range(i + 1, mini(d.objects.size(), i + 30)):
				mind = minf(mind, Vector2(d.objects[i].xf.origin.x - d.objects[j].xf.origin.x, d.objects[i].xf.origin.z - d.objects[j].xf.origin.z).length())
		check(mind >= 2.99, "scatter respects spacing (min %.2f)" % mind)
		ed.P["scatter_mode"] = "erase"
		st.stroke = ed.undo.begin("Erase")
		st.erase_at(Vector3(-60, 0, -60))
		ed.undo.commit(st.stroke)
		check(d.objects.size() <= 2, "erase brush removes trees (%d left)" % d.objects.size())
		ed.undo.undo()
		check(d.objects.size() > 20, "undo erase brings them back")
	# ---------- water kinds + undo
	d.waters.clear()
	var w := {"preset": "gta", "kind": "ocean", "level": -2.0}
	d.waters.append(w); ed.water.rebuild_all()
	check(ed.water.get_child_count() == 1, "ocean mesh builds")
	d.waters.append({"preset": "pool", "kind": "plane", "level": 3.0, "center": [0.0, 0.0], "size": [30.0, 20.0], "depth": 3.0, "yaw": 0.3})
	ed.water.rebuild_all()
	check(ed.water.get_child_count() == 2, "pool plane builds")
	# ---------- paths of every kind
	d.generate("hills", 7, 20.0)
	for typ in ["road", "rail", "river", "line"]:
		ed.set_tool("path"); ed.P["path_type"] = typ
		ed.active_path = -1
		ed.P["asset"] = "fence" if ed.assets.entries.has("fence") else ed.P["asset"]
		ed.new_path()
		var pts := PackedVector3Array([Vector3(-80, 0, 40), Vector3(-30, 0, 55), Vector3(20, 0, 40), Vector3(70, 0, 60)])
		for i in pts.size(): pts[i].y = d.height_at(pts[i].x, pts[i].z)
		d.paths[ed.active_path]["points"] = pts
		d.paths[ed.active_path]["asset"] = ed.P["asset"]
		ed.rebuild_active_path()
		await _frames(1)
		if typ == "line" and ed.assets.entries.is_empty():
			print("SKIP  line route (no assets in library)"); continue
		check(ed.paths._nodes.has(ed.active_path) and ed.paths._nodes[ed.active_path].get_child_count() > 0, "%s route builds geometry" % typ)
		if typ != "line":
			var h0 := _sum(d.heights)
			var stk := ed.undo.begin("apply")
			PathTerrain.apply(d, d.paths[ed.active_path], stk)
			ed.undo.commit(stk)
			check(absf(_sum(d.heights) - h0) > 0.01, "%s applies to terrain" % typ)
	# ---------- save / load roundtrip
	d.map_name = "selftest_map"
	check(ed.save_map(), "save map")
	var hs := _sum(d.heights); var nobj := d.objects.size(); var nw := d.waters.size(); var np := d.paths.size()
	check(ed.load_map("%s/selftest_map.zexmap" % MapEditor.MAPS_DIR), "load map")
	check(absf(_sum(ed.data.heights) - hs) < 0.5 and ed.data.objects.size() == nobj and ed.data.waters.size() == nw and ed.data.paths.size() == np, "roundtrip keeps heights/objects/water/paths")
	DirAccess.remove_absolute("%s/selftest_map.zexmap" % MapEditor.MAPS_DIR)
	# ---------- auto texture + fill layer
	ed.data.splat[0].fill(Color(1, 0, 0, 0))
	await AutoTools.auto_texture(ed, {"slope": 30.0, "snow_h": 20.0, "sand_h": 1.0, "dirt": 0.5, "l_flat": 0, "l_dirt": 1, "l_rock": 2, "l_snow": 4, "l_sand": 3})
	var used := {}
	for i in 400:
		used[ed.data.dominant_layer(randf_range(-200, 200), randf_range(-200, 200))] = true
	check(used.size() >= 2, "auto texture uses several layers (%s)" % str(used.keys()))
	# ---------- lake on a hand made basin (overflow safe)
	var exp := MapExporter.new(); exp.ed = ed; exp.bake_res = 512; exp.object_detail = 0.2; exp.terrain_step = 2
	var res: String = await exp.export_glb(ProjectSettings.globalize_path("user://me_selftest.glb"))
	check(res.begins_with("Exported"), "GLB export: " + res)
	# ---------- walk mode
	ed.enter_walk(); await _frames(3); ed.exit_walk()
	check(not ed.walk_mode, "walk mode enters/exits")
	print("FAILS: ", fails)
	get_tree().quit(1 if fails > 0 else 0)

func _sum(a: PackedFloat32Array) -> float:
	var s := 0.0
	for v in a: s += v
	return s

func _frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _scr(w: Vector3) -> Vector2:
	w.y = ed.data.height_at(w.x, w.z)
	return ed.cam.cam.unproject_position(w)

func _touch(idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new(); e.index = idx; e.position = pos; e.pressed = pressed
	get_viewport().push_input(e)

func _drag(idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new(); e.index = idx; e.position = pos; e.relative = Vector2(10, 0)
	get_viewport().push_input(e)
