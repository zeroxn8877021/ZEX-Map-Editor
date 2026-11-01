extends Node
func _ready() -> void:
	var ed: MapEditor = load("res://scenes/editor.tscn").instantiate()
	add_child(ed)
	for i in 10: await get_tree().process_frame
	await _snap("g1_start")
	var g: GroundTool = ed.tools["ground"]
	g.add_at(Vector2i(1, 0)); g.add_at(Vector2i(0, 1)); g.add_at(Vector2i(-1, 0))
	ed.cam.focus_on(Vector3(0, 0, 0), 150.0)
	for i in 20: await get_tree().process_frame
	await _snap("g2_added")
	print("tiles ", ed.data.tiles.size(), " built ", ed.terrain.built_count(), " t_count ", ed.data.t_count)
	get_tree().quit()
func _snap(n: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("user://me_" + n + ".png"))
