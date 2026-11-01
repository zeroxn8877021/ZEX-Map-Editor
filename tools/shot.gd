# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : shot.gd
# Copyright : (c) Zex Interactive. All rights reserved.

extends Node
## Scripted editor session for screenshots / smoke tests. Run:  xvfb-run -a godot --path . --rendering-method gl_compatibility --rendering-driver opengl3 res://tools/shot.tscn
var ed: MapEditor
const OUT_DIR := "user://screenshots"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	ed = load("res://scenes/editor.tscn").instantiate()
	add_child(ed)
	await _frames(8)
	await _snap("01_start_flat_50x50")
	ed.set_tool("ground")
	for tz in range(-2, 3):
		for tx in range(-2, 3): ed.data.add_tile(Vector2i(tx, tz))
	ed.data.generate("hills", 3, 14.0)
	ed.terrain.rebuild_now()
	ed.cam.focus_on(Vector3(0, 0, 0), 170.0); ed.cam._t_pitch = deg_to_rad(-50)
	await _frames(40)
	await _snap("02_ground_tiles")
	# sculpt a mountain + dig a pit
	ed.set_tool("sculpt")
	ed.P["radius"] = 28.0; ed.P["strength"] = 0.3; ed.P["sculpt_mode"] = "raise"
	await _stroke([Vector3(-60, 0, 20), Vector3(-40, 0, 25)], 0.6)
	ed.P["sculpt_mode"] = "lower"; ed.P["radius"] = 22.0; ed.P["strength"] = 0.4
	await _stroke([Vector3(40, 0, 0)], 0.9)
	await _frames(10)
	await _snap("03_sculpt")
	# paint
	ed.set_tool("paint")
	ed.P["radius"] = 20.0; ed.P["layer"] = 2; ed.P["strength"] = 1.0
	await _stroke([Vector3(-60, 0, 20), Vector3(-45, 0, 30)], 1.0)
	ed.P["layer"] = 3
	await _stroke([Vector3(40, 0, 0)], 1.0)
	await _frames(4)
	await _snap("04_paint")
	# water: lake in the pit
	ed.set_tool("water")
	ed.cam.focus_on(Vector3(40, 0, 0), 70.0)
	ed.cam._t_pitch = deg_to_rad(-72)
	await _frames(40)
	var tp := Vector3(40, ed.data.height_at(40, 0), 0)
	ed.P["water_mode"] = "lake"; ed.P["water_offset"] = 2.0
	await _tap(tp)
	await _frames(6)
	await _snap("05_water_lake")
	# scatter trees
	ed.cam.focus_on(Vector3(0, 0, -20), 110.0)
	ed.cam._t_pitch = deg_to_rad(-38)
	await _frames(40)
	ed.set_tool("scatter")
	ed.P["scatter_assets"] = ["tree", "shrub"] if ed.assets.entries.has("tree") else []
	ed.P["radius"] = 30.0; ed.P["density"] = 2.5; ed.P["spacing"] = 4.0
	await _stroke([Vector3(0, 0, -40), Vector3(30, 0, -50), Vector3(-30, 0, -40)], 1.0)
	await _frames(8)
	await _snap("06_trees")
	print("objects: ", ed.data.objects.size(), " assets: ", ed.assets.entries.keys())
	# road
	ed.set_tool("path")
	ed.P["path_type"] = "road"
	for p in [Vector3(-90, 0, -10), Vector3(-30, 0, 10), Vector3(20, 0, 50), Vector3(80, 0, 40)]:
		await _tap(p)
	await _frames(6)
	await _snap("07_road")
	var st := ed.undo.begin("apply")
	PathTerrain.apply(ed.data, ed.data.paths[0], st)
	ed.undo.commit(st)
	ed.rebuild_active_path()
	await _frames(12)
	await _snap("08_road_applied")
	ed.undo.undo(); ed.undo.undo()
	await _frames(6)
	ed.undo.redo()
	await _frames(6)
	# export
	var ex := MapExporter.new(); ex.ed = ed; ex.bake_res = 1024
	var r: String = await ex.export_glb(ProjectSettings.globalize_path("user://me_test.glb"))
	print(r)
	print(ex.export_data())
	await _snap("09_final")
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n: await get_tree().process_frame

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT_DIR.path_join(name + ".png"))
	print("shot ", name)

func _scr(w: Vector3) -> Vector2:
	w.y = ed.data.height_at(w.x, w.z)
	return ed.cam.cam.unproject_position(w)

func _stroke(pts: Array, hold: float) -> void:
	var t := ed.tool
	var first := true
	for p in pts:
		var s := _scr(p)
		ed.last_pointer = s
		if first: t.begin(s); first = false
		else: t.drag(s)
		var time := 0.0
		while time < hold:
			t.tick(0.05); time += 0.05
			await get_tree().process_frame
	t.end()

func _tap(p: Vector3) -> void:
	var s := _scr(p)
	ed.last_pointer = s
	ed.tool.begin(s)
	await get_tree().process_frame
	ed.tool.end()
	await get_tree().process_frame
