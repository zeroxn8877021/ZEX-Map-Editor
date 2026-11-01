# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : shot2.gd
# Copyright : (c) Zex Interactive. All rights reserved.

extends Node
func _ready() -> void:
	var ed: MapEditor = load("res://scenes/editor.tscn").instantiate()
	add_child(ed)
	for i in 6: await get_tree().process_frame
	var d := ed.data
	d.generate("island", 4, 30.0)
	ed.terrain.rebuild_now()
	d.waters.append({"preset": "ocean", "kind": "ocean", "level": 0.0})
	ed.water.rebuild_all()
	for spec in [["river", [Vector3(-60, 0, -80), Vector3(-30, 0, -30), Vector3(-40, 0, 10)]], ["rail", [Vector3(10, 0, -40), Vector3(40, 0, 0), Vector3(30, 0, 50)]]]:
		ed.P["path_type"] = spec[0]; ed.active_path = -1; ed.new_path()
		var pts := PackedVector3Array(spec[1])
		for i in pts.size(): pts[i].y = d.height_at(pts[i].x, pts[i].z)
		d.paths[ed.active_path]["points"] = pts
		var st := ed.undo.begin("a"); PathTerrain.apply(d, d.paths[ed.active_path], st); ed.undo.commit(st)
		ed.rebuild_active_path()
	ed.set_tool("sculpt")
	ed.cam.focus_on(Vector3(0, 0, -10), 150.0); ed.cam._t_pitch = deg_to_rad(-45)
	for i in 50: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://me2_island.png"))
	get_tree().quit()
