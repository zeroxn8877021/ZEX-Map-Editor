class_name TerrainView
extends Node3D
## Streamed terrain: one mesh + one material per 50 m tile. Only tiles near the camera exist as meshes (two LODs with skirts),
## far tiles are freed again. Splat weights are uploaded per tile (52 x 52 px) so painting never re-uploads the whole map.

const TILE := 50
const SKIRT := 4.0
var data: MapData
var matlib: MaterialLibrary
var view_range := 450.0                 # tiles farther than this are not built
var lod_dist := 150.0                   # tiles farther than this use the coarse mesh
var budget_ms := 5.0
var _base_mat: ShaderMaterial
var layer_array: Texture2DArray
var _tiles: Dictionary = {}             # Vector2i -> {mi, lod, mat, t0, t1}
var _dirty_h: Dictionary = {}
var _dirty_s: Dictionary = {}
var _idx_cache: Dictionary = {}
var _stream_t := 1.0
var _build_queue: Array = []
var stats := {"built": 0, "freed": 0, "rebuilt": 0}

static var _globals_ready := false

static func ensure_globals() -> void:
	if _globals_ready: return
	_globals_ready = true
	var names := {"zx_brush": RenderingServer.GLOBAL_VAR_TYPE_VEC4, "zx_brush_col": RenderingServer.GLOBAL_VAR_TYPE_VEC4,
		"zx_grid": RenderingServer.GLOBAL_VAR_TYPE_FLOAT, "zx_tile_a": RenderingServer.GLOBAL_VAR_TYPE_VEC4, "zx_tile_b": RenderingServer.GLOBAL_VAR_TYPE_VEC4}
	for i in 8: names["zx_tint%d" % i] = RenderingServer.GLOBAL_VAR_TYPE_VEC4
	for n in names:
		RenderingServer.global_shader_parameter_add(n, names[n], 0.0 if names[n] == RenderingServer.GLOBAL_VAR_TYPE_FLOAT else Vector4())
	RenderingServer.global_shader_parameter_set("zx_brush_col", Vector4(1, 0.85, 0.2, 1))

func setup(d: MapData, ml: MaterialLibrary) -> void:
	ensure_globals()
	data = d
	matlib = ml
	for k in _tiles.keys(): _free_tile(k)
	_tiles.clear(); _dirty_h.clear(); _dirty_s.clear(); _build_queue.clear()
	_base_mat = ShaderMaterial.new()
	_base_mat.shader = load("res://assets/shaders/terrain_splat.gdshader")
	refresh_layers()
	_stream_t = 1.0
	update_stream(true)

# ------------------------------------------------------------------ layers (all global / shared, no per-tile work)
func refresh_layers() -> void:
	layer_array = matlib.build_array(data.layer_mats)
	_base_mat.set_shader_parameter("layer_tex", layer_array)
	for k in _tiles: _tiles[k]["mat"].set_shader_parameter("layer_tex", layer_array)
	refresh_tiling()

## Cheap: replaces a single layer inside the existing texture array.
func refresh_layer(i: int) -> void:
	matlib.update_array_layer(layer_array, i, data.layer_mats[i])
	refresh_tiling()

func refresh_tiling() -> void:
	var ta := Vector4(); var tb := Vector4()
	for i in 4:
		ta[i] = matlib.tile_of(data.layer_mats[i])
		tb[i] = matlib.tile_of(data.layer_mats[i + 4])
	RenderingServer.global_shader_parameter_set("zx_tile_a", ta)
	RenderingServer.global_shader_parameter_set("zx_tile_b", tb)
	for i in 8:
		var c: Color = matlib.mats[data.layer_mats[i]]["tint"]
		var detail := 0.0 if data.layer_mats[i] in ["proto"] else 1.0
		RenderingServer.global_shader_parameter_set("zx_tint%d" % i, Vector4(c.r, c.g, c.b, detail))

func set_brush(pos: Vector3, radius: float, active: bool, col: Color = Color(1, 0.85, 0.2)) -> void:
	RenderingServer.global_shader_parameter_set("zx_brush", Vector4(pos.x, pos.z, radius, 1.0 if active else 0.0))
	RenderingServer.global_shader_parameter_set("zx_brush_col", Vector4(col.r, col.g, col.b, 1.0))

func set_grid(on: bool) -> void:
	RenderingServer.global_shader_parameter_set("zx_grid", 1.0 if on else 0.0)

# ------------------------------------------------------------------ dirty tracking
func _tiles_in_rect(r: Rect2i) -> Array:
	var half_t: int = (data.t_count - 1) / 2
	var out: Array = []
	var tx0 := clampi(int(floor(float(r.position.x - 1) / TILE)), 0, data.t_count - 1) - half_t
	var tz0 := clampi(int(floor(float(r.position.y - 1) / TILE)), 0, data.t_count - 1) - half_t
	var tx1 := clampi(int(floor(float(r.end.x + 1) / TILE)), 0, data.t_count - 1) - half_t
	var tz1 := clampi(int(floor(float(r.end.y + 1) / TILE)), 0, data.t_count - 1) - half_t
	for tz in range(tz0, tz1 + 1):
		for tx in range(tx0, tx1 + 1):
			var t := Vector2i(tx, tz)
			if data.tiles.has(t): out.append(t)
	return out

func mark_dirty(rect: Rect2i) -> void:
	for t in _tiles_in_rect(rect):
		if _tiles.has(t): _dirty_h[t] = true

func mark_splat(rect: Rect2i) -> void:
	for t in _tiles_in_rect(rect):
		if _tiles.has(t): _dirty_s[t] = true

func mark_splat_all() -> void:
	for t in _tiles: _dirty_s[t] = true

func rebuild_now() -> void:
	for t in _dirty_h.keys():
		if _tiles.has(t): _build_tile(t, _tiles[t]["lod"])
	_dirty_h.clear()
	for t in _dirty_s.keys():
		if _tiles.has(t): _upload_splat(t)
	_dirty_s.clear()

# ------------------------------------------------------------------ streaming
func _cam_pos() -> Vector3:
	var c := get_viewport().get_camera_3d()
	return c.global_position if c != null else Vector3.ZERO

func _tile_dist(t: Vector2i, p: Vector3) -> float:
	var mn := data.tile_min(t)
	var dx := maxf(maxf(mn.x - p.x, 0.0), p.x - (mn.x + TILE))
	var dz := maxf(maxf(mn.y - p.z, 0.0), p.z - (mn.y + TILE))
	return sqrt(dx * dx + dz * dz)

func update_stream(force_all := false) -> void:
	var p := _cam_pos()
	_build_queue.clear()
	for t in _tiles.keys():
		if not data.tiles.has(t):
			_free_tile(t); _tiles.erase(t)
	for t in data.tiles:
		var d := _tile_dist(t, p)
		if force_all and not _tiles.has(t) and d < view_range:
			pass
		if _tiles.has(t):
			if d > view_range * 1.25:
				_free_tile(t); _tiles.erase(t); stats["freed"] += 1
				continue
			var lod: int = _tiles[t]["lod"]
			if lod == 0 and d > lod_dist * 1.15: _build_queue.append([d, t, 1])
			elif lod == 1 and d < lod_dist * 0.9: _build_queue.append([d, t, 0])
		elif d < view_range:
			_build_queue.append([d, t, 0 if d < lod_dist else 1])
	_build_queue.sort_custom(func(a, b): return a[0] < b[0])

func _process(dt: float) -> void:
	if data == null: return
	_stream_t += dt
	if _stream_t > 0.25:
		_stream_t = 0.0
		update_stream()
	var t0 := Time.get_ticks_usec()
	# edits first (visible), then streaming builds
	for t in _dirty_h.keys():
		if _tiles.has(t):
			_build_tile(t, _tiles[t]["lod"]); stats["rebuilt"] += 1
		_dirty_h.erase(t)
		if (Time.get_ticks_usec() - t0) / 1000.0 > budget_ms: return
	for t in _dirty_s.keys():
		if _tiles.has(t): _upload_splat(t)
		_dirty_s.erase(t)
	while not _build_queue.is_empty() and (Time.get_ticks_usec() - t0) / 1000.0 < budget_ms:
		var job: Array = _build_queue.pop_front()
		var t: Vector2i = job[1]
		if not data.tiles.has(t): continue
		_build_tile(t, job[2])
		stats["built"] += 1

func built_count() -> int:
	return _tiles.size()

# ------------------------------------------------------------------ tile meshes
func _free_tile(t: Vector2i) -> void:
	if _tiles.has(t):
		_tiles[t]["mi"].queue_free()

func _index_for(n: int) -> PackedInt32Array:
	if _idx_cache.has(n): return _idx_cache[n]
	var idx := PackedInt32Array()
	for z in n - 1:
		for x in n - 1:
			var a := z * n + x
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	# skirts (both windings so they are visible from any side). skirt vertex k = n*n + edge*n + i
	var base := n * n
	var edges: Array = []
	for i in n: edges.append([i, base + i])                              # north (z = 0)
	var north := edges.duplicate(); edges.clear()
	for i in n: edges.append([(n - 1) * n + i, base + n + i])           # south
	var south := edges.duplicate(); edges.clear()
	for i in n: edges.append([i * n, base + 2 * n + i])                  # west
	var west := edges.duplicate(); edges.clear()
	for i in n: edges.append([i * n + n - 1, base + 3 * n + i])         # east
	var east := edges.duplicate()
	for e in [north, south, west, east]:
		for i in n - 1:
			var a: int = e[i][0]; var b: int = e[i + 1][0]; var c: int = e[i][1]; var d: int = e[i + 1][1]
			idx.append_array([a, b, c, b, d, c, a, c, b, b, c, d])
	_idx_cache[n] = idx
	return idx

func _build_tile(t: Vector2i, lod: int) -> void:
	var step := 1 if lod == 0 else 5
	var n := TILE / step + 1
	var half_t: int = (data.t_count - 1) / 2
	var gx0: int = (t.x + half_t) * TILE
	var gz0: int = (t.y + half_t) * TILE
	var H := data.heights
	var V := data.verts
	var cell := data.cell
	var total := n * n + 4 * n
	var verts := PackedVector3Array(); verts.resize(total)
	var norms := PackedVector3Array(); norms.resize(total)
	var ds := 2.0 * cell * step
	var maxg := data.cells
	for z in n:
		var gz := gz0 + z * step
		var gzu := maxi(gz - step, 0); var gzd := mini(gz + step, maxg)
		var row := gz * V
		for x in n:
			var gx := gx0 + x * step
			var h := H[row + gx]
			var i := z * n + x
			verts[i] = Vector3(x * step * cell, h, z * step * cell)
			norms[i] = Vector3(H[row + maxi(gx - step, 0)] - H[row + mini(gx + step, maxg)], ds, H[gzu * V + gx] - H[gzd * V + gx]).normalized()
	var base := n * n
	for i in n:
		var v0 := verts[i]; var v1 := verts[(n - 1) * n + i]; var v2 := verts[i * n]; var v3 := verts[i * n + n - 1]
		verts[base + i] = v0 - Vector3(0, SKIRT, 0); norms[base + i] = norms[i]
		verts[base + n + i] = v1 - Vector3(0, SKIRT, 0); norms[base + n + i] = norms[(n - 1) * n + i]
		verts[base + 2 * n + i] = v2 - Vector3(0, SKIRT, 0); norms[base + 2 * n + i] = norms[i * n]
		verts[base + 3 * n + i] = v3 - Vector3(0, SKIRT, 0); norms[base + 3 * n + i] = norms[i * n + n - 1]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = _index_for(n)
	var rec: Dictionary = _tiles.get(t, {})
	var mi: MeshInstance3D = rec.get("mi")
	if mi == null:
		mi = MeshInstance3D.new()
		mi.name = "tile_%d_%d" % [t.x, t.y]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mn := data.tile_min(t)
		mi.position = Vector3(mn.x, 0, mn.y)
		var m: ShaderMaterial = _base_mat.duplicate()
		m.set_shader_parameter("splat_xform", Vector4(mn.x - 1.0, mn.y - 1.0, TILE + 2.0, TILE + 2.0))
		mi.material_override = m
		add_child(mi)
		rec = {"mi": mi, "mat": m, "lod": lod, "t0": null, "t1": null}
		_tiles[t] = rec
		_upload_splat(t)
	rec["lod"] = lod
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mi.mesh = am

func _tile_splat_image(t: Vector2i, i: int) -> Image:
	var half_t: int = (data.t_count - 1) / 2
	var px0 := (t.x + half_t) * TILE - 1
	var pz0 := (t.y + half_t) * TILE - 1
	var im := Image.create(TILE + 2, TILE + 2, false, Image.FORMAT_RGBA8)
	var rx0 := maxi(px0, 0); var rz0 := maxi(pz0, 0)
	var rx1 := mini(px0 + TILE + 2, data.splat_res); var rz1 := mini(pz0 + TILE + 2, data.splat_res)
	im.blit_rect(data.splat[i], Rect2i(rx0, rz0, rx1 - rx0, rz1 - rz0), Vector2i(rx0 - px0, rz0 - pz0))
	return im

func _upload_splat(t: Vector2i) -> void:
	var rec: Dictionary = _tiles[t]
	for i in 2:
		var im := _tile_splat_image(t, i)
		var key := "t%d" % i
		if rec[key] == null:
			rec[key] = ImageTexture.create_from_image(im)
			rec["mat"].set_shader_parameter("splat%d" % i, rec[key])
		else:
			(rec[key] as ImageTexture).update(im)

## Full-map material for baking / export (one big splat texture).
func make_bake_material(shader_code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = shader_code
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("layer_tex", layer_array)
	m.set_shader_parameter("splat0", ImageTexture.create_from_image(data.splat[0]))
	m.set_shader_parameter("splat1", ImageTexture.create_from_image(data.splat[1]))
	m.set_shader_parameter("splat_xform", Vector4(-data.size * 0.5, -data.size * 0.5, data.size, data.size))
	return m
