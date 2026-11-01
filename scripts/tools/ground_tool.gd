class_name GroundTool
extends EditorTool
## Trainz-style base plates: green "+" ghosts appear next to the ground; tap one to add a 50 x 50 m tile that snaps to the
## neighbouring edges (shared edge heights are kept, the interior continues the slope). Remove mode deletes a tile.
var _ghost_quads: MultiMeshInstance3D
var _ghost_plus: MultiMeshInstance3D
var _cands: Array = []          # [{t: Vector2i, h: float}]
var _press := Vector2.ZERO

func _init() -> void:
	tool_name = "ground"

func activate() -> void:
	_ensure_nodes()
	refresh_ghosts()

func deactivate() -> void:
	super.deactivate()
	if _ghost_quads: _ghost_quads.visible = false
	if _ghost_plus: _ghost_plus.visible = false

func _ensure_nodes() -> void:
	if _ghost_quads != null: return
	var quad := PlaneMesh.new(); quad.size = Vector2(47.5, 47.5)
	var qm := StandardMaterial3D.new()
	qm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.albedo_color = Color(0.25, 0.9, 0.4, 0.14)
	qm.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = qm
	_ghost_quads = _make_mm(quad)
	# plus sign: two thin bars
	var plus := ArrayMesh.new()
	var v := PackedVector3Array(); var idx := PackedInt32Array()
	for bar in [[Vector3(-7, 0, -1), Vector3(7, 0, 1)], [Vector3(-1, 0, -7), Vector3(1, 0, 7)]]:
		var b := v.size()
		var a: Vector3 = bar[0]; var c: Vector3 = bar[1]
		v.append_array([Vector3(a.x, 0, a.z), Vector3(c.x, 0, a.z), Vector3(c.x, 0, c.z), Vector3(a.x, 0, c.z)])
		idx.append_array([b, b + 1, b + 2, b, b + 2, b + 3])
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v; arr[Mesh.ARRAY_INDEX] = idx
	plus.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(1, 1, 1, 0.95)
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	plus.surface_set_material(0, pm)
	_ghost_plus = _make_mm(plus)

func _make_mm(mesh: Mesh) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-4000, -500, -4000), Vector3(8000, 1000, 8000))
	ed.add_child(mmi)
	return mmi

func candidates() -> Array:
	var d: MapData = ed.data
	var out: Array = []
	var seen: Dictionary = {}
	var lim := (MapData.MAX_T - 1) / 2
	for t in d.tiles:
		for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var c: Vector2i = t + off
			if d.tiles.has(c) or seen.has(c) or absi(c.x) > lim or absi(c.y) > lim: continue
			seen[c] = true
			var edge := d.tile_center(t) + Vector2(off) * (MapData.TILE * 0.5)
			out.append({"t": c, "h": d.height_at(edge.x, edge.y)})
	return out

func refresh_ghosts() -> void:
	_ensure_nodes()
	var show: bool = ed.tool_id == "ground" and ed.P["ground_mode"] == "add"
	_ghost_quads.visible = show; _ghost_plus.visible = show
	if not show: return
	_cands = candidates()
	var q := _ghost_quads.multimesh; var p := _ghost_plus.multimesh
	q.instance_count = _cands.size(); p.instance_count = _cands.size()
	for i in _cands.size():
		var c: Vector2i = _cands[i]["t"]
		var o := Vector3(c.x * MapData.TILE, _cands[i]["h"] + 0.15, c.y * MapData.TILE)
		q.set_instance_transform(i, Transform3D(Basis.IDENTITY, o))
		p.set_instance_transform(i, Transform3D(Basis.IDENTITY, o + Vector3(0, 0.1, 0)))

func pick_ghost(pos: Vector2) -> Variant:
	var r := ed.cam.ray_from_screen(pos)
	var o: Vector3 = r["o"]; var dir: Vector3 = r["d"]
	var best_t := 1e9
	var best = null
	for c in _cands:
		if absf(dir.y) < 0.0001: continue
		var t: float = (c["h"] + 0.15 - o.y) / dir.y
		if t < 0.0 or t >= best_t: continue
		var hit: Vector3 = o + dir * t
		if data_tile(hit) == c["t"]:
			best_t = t; best = c["t"]
	return best

func data_tile(p: Vector3) -> Vector2i:
	return ed.data.tile_of(p.x, p.z)

func begin(pos: Vector2) -> void:
	active = true
	_press = pos

func end() -> void:
	active = false
	if _press.distance_to(ed.last_pointer) > 14.0: return
	var d: MapData = ed.data
	if ed.P["ground_mode"] == "add":
		var t = pick_ghost(_press)
		if t == null: return
		add_at(t)
	else:
		var g = ed.cam.screen_to_ground(_press)
		if g == null: return
		var t2 := d.tile_of(g.x, g.z)
		var st := ed.undo.begin("Remove tile")
		st.snapshot_tiles()
		if d.remove_tile(t2, st):
			ed.undo.commit(st)
			ed.toast("Tile removed")
			ed.refresh_panel()
		else:
			ed.toast("Keep at least one tile")

func add_at(t: Vector2i) -> bool:
	var d: MapData = ed.data
	var st := ed.undo.begin("Add tile")
	st.snapshot_tiles()
	if not d.add_tile(t, st):
		ed.toast("Map size limit reached")
		return false
	ed.undo.commit(st)
	refresh_ghosts()
	ed.toast("Ground added  (%d tiles, %d x %d m)" % [d.tiles.size(), int(d.active_bounds().size.x), int(d.active_bounds().size.y)])
	ed.refresh_panel()
	return true

func add_ring() -> void:
	var n := 0
	for c in candidates():
		if n >= 60: break
		if add_at(c["t"]): n += 1
	refresh_ghosts()

func hover(_pos: Vector2) -> void: pass
