# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : editor.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name MapEditor
extends Node3D
## Main controller: owns the map, the views, the tools and the touch gesture logic.

const MAPS_DIR := "user://maps"
var data: MapData
var matlib: MaterialLibrary
var assets: AssetLibrary
var undo: UndoManager
var terrain: TerrainView
var objects: ObjectView
var water: WaterView
var paths: PathView
var cam: CamRig
var ui: EditorUI
var sun: DirectionalLight3D
var env: Environment

var P := {
	"radius": 8.0, "strength": 0.5, "hardness": 0.5, "ground_mode": "add", "view_range": 450.0,
	"sculpt_mode": "raise", "level_h": 5.0,
	"paint_mode": "paint", "layer": 1, "smart_slope": 32.0, "smart_steep_layer": 3,
	"asset": "", "scatter_assets": [], "scatter_mode": "paint", "erase_selected_only": false,
	"yaw": 0.0, "random_yaw": true, "random_scale": true, "scale_min": 0.85, "scale_max": 1.25, "align": 0.0, "sink": 0.0,
	"density": 3.0, "spacing": 3.0, "slope_max": 38.0, "min_h": -50.0, "max_h": 500.0,
	"water_mode": "lake", "water_preset": "gta", "water_offset": 1.5, "sea_level": 0.0, "plane_w": 40.0, "plane_d": 30.0, "plane_depth": 3.0,
	"path_type": "road", "path_width": 6.0, "path_shoulder": 6.0, "path_depth": 1.8, "path_spacing": 3.0, "path_offset": 0.0,
	"path_flatten": true, "path_closed": false,
	"grid": false, "shadows": true, "view_dist": 0.0, "cam_mode": false, "sun_pitch": -48.0, "sun_yaw": -35.0,
}
var tools: Dictionary = {}
var tool: EditorTool
var tool_id := "ground"
var selected: MapObject
var selected_water := -1
var active_path := -1
var sel_point := -1
var path_dirty := false
var last_pointer := Vector2.ZERO
var touches: Dictionary = {}
var _g_mode := "none"
var _pending := -1
var _pending_pos := Vector2.ZERO
var _pending_t := 0.0
var _g_prev_mid := Vector2.ZERO
var _g_prev_dist := 0.0
var _g_prev_ang := 0.0
var _sel_marker: MeshInstance3D
var _path_markers: MultiMeshInstance3D
var _terr_edit_t := -1.0
var _autosave_t := 0.0
var _marker_t := 0.0
var _path_cache: Array = []
var _path_cache_valid := false
var walk_mode := false
var _walk_move := Vector2.ZERO
var _walk_look := Vector2.ZERO
var _walk_touch_move := -1
var _walk_touch_look := -1
var _walk_origin := Vector2.ZERO
var headless_test := false

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)
	matlib = MaterialLibrary.new()
	assets = AssetLibrary.new()
	assets.name = "Assets"
	add_child(assets)
	_make_world()
	assets.changed.connect(_on_assets_changed)
	assets.scale_changed.connect(func(_i): objects.rebuild_all(); paths.rebuild_all(); update_selection_marker())
	new_map(1, "flat", 1, false)
	ui = EditorUI.new()
	ui.ed = self
	ui.name = "UI"
	add_child(ui)
	for t in [SculptTool, PaintTool, PlaceTool, ScatterTool, SelectTool, WaterTool, PathTool, GroundTool]:
		var inst: EditorTool = t.new()
		inst.setup(self)
		tools[inst.tool_name] = inst
	set_tool("ground")

func _make_world() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.28, 0.5, 0.82)
	psm.sky_horizon_color = Color(0.72, 0.83, 0.92)
	psm.ground_horizon_color = Color(0.72, 0.83, 0.92)
	psm.ground_bottom_color = Color(0.3, 0.34, 0.3)
	sky.sky_material = psm
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.83, 0.92)
	env.fog_density = 0.0009
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 160.0
	add_child(sun)
	apply_sun()
	terrain = TerrainView.new(); terrain.name = "Terrain"; add_child(terrain)
	objects = ObjectView.new(); objects.name = "Objects"; add_child(objects)
	water = WaterView.new(); water.name = "Water"; add_child(water)
	paths = PathView.new(); paths.name = "Paths"; add_child(paths)
	cam = CamRig.new(); cam.name = "CamRig"; add_child(cam)
	_sel_marker = MeshInstance3D.new()
	_sel_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_sel_marker)
	_path_markers = MultiMeshInstance3D.new()
	_path_markers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	var sph := SphereMesh.new(); sph.radius = 0.5; sph.height = 1.0; sph.radial_segments = 12; sph.rings = 6
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.render_priority = 10
	sph.material = mat
	mm.mesh = sph
	_path_markers.multimesh = mm
	add_child(_path_markers)

func apply_sun() -> void:
	sun.rotation_degrees = Vector3(P["sun_pitch"], P["sun_yaw"], 0)

# ------------------------------------------------------------------ map lifecycle
func new_map(tiles_per_side: int, style: String, seed_v: int, rebind_ui := true) -> void:
	data = MapData.new(tiles_per_side)
	if style != "flat": data.generate(style, seed_v, 30.0)
	_bind_data()
	if rebind_ui and ui: ui.on_map_changed()

func _bind_data() -> void:
	undo = UndoManager.new(data)
	undo.stack_changed.connect(func(): if ui: ui.refresh_undo())
	data.changed_region.connect(_on_height_changed)
	data.splat_changed.connect(func(): terrain.mark_splat_all())
	data.splat_region_changed.connect(func(r): terrain.mark_splat(r))
	data.objects_added.connect(func(l): objects.add_objects(l))
	data.tiles_changed.connect(_on_tiles_changed)
	data.grown.connect(_on_grown)
	data.objects_changed.connect(func(k): objects.mark(k))
	data.waters_changed.connect(func(): water.rebuild_all())
	data.paths_changed.connect(func(): _path_cache_valid = false; paths.rebuild_all(); update_path_markers())
	terrain.setup(data, matlib)
	objects.setup(data, assets)
	water.setup(data)
	paths.setup(data, assets, matlib)
	cam.setup(data)
	selected = null; selected_water = -1; active_path = -1; sel_point = -1
	update_selection_marker(); update_path_markers()
	_path_cache_valid = false

func _on_tiles_changed() -> void:
	terrain.update_stream()
	cam.refresh_bounds()
	if ui and tool_id == "ground": tools["ground"].refresh_ghosts()

func _on_grown() -> void:
	# arrays were re-allocated: indices in the undo stack are stale
	undo.undo_stack.clear(); undo.redo_stack.clear()
	undo.stack_changed.emit()
	terrain.setup(data, matlib)
	_path_cache_valid = false

func _on_assets_changed() -> void:
	objects.rebuild_all()
	paths.rebuild_all()

func _on_height_changed(rect: Rect2i) -> void:
	terrain.mark_dirty(rect)
	_terr_edit_t = 0.0

func load_map(path: String) -> bool:
	var m := MapData.load_from(path)
	if m == null: return false
	data = m
	_bind_data()
	if ui: ui.on_map_changed()
	return true

func save_map(name: String = "") -> bool:
	if name != "": data.map_name = name
	var p := "%s/%s.zexmap" % [MAPS_DIR, data.map_name.validate_filename()]
	var ok := data.save_to(p)
	toast(("Saved " + p) if ok else "Save failed")
	return ok

func list_maps() -> Array:
	var out: Array = []
	var da := DirAccess.open(MAPS_DIR)
	if da == null: return out
	for f in da.get_files():
		if f.ends_with(".zexmap"): out.append(f.get_basename())
	out.sort()
	return out

# ------------------------------------------------------------------ tools / state
func set_tool(id: String) -> void:
	if tool != null: tool.deactivate()
	tool_id = id
	tool = tools[id]
	tool.activate()
	if id != "select": selected = null; update_selection_marker()
	update_path_markers()
	if ui: ui.show_tool_panel(id)

func toast(msg: String) -> void:
	print("[editor] ", msg)
	if ui: ui.toast(msg)

func make_xf(pos: Vector3, yaw: float, scale_v: float) -> Transform3D:
	var up := Vector3.UP
	if P["align"] > 0.0:
		up = Vector3.UP.lerp(data.normal_at(pos.x, pos.z), P["align"]).normalized()
	var b := Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw)
	b = b.scaled(Vector3.ONE * scale_v)
	return Transform3D(b, pos - up * P["sink"])

func _paths_cache() -> Array:
	if _path_cache_valid: return _path_cache
	_path_cache.clear()
	for p in data.paths:
		if p["type"] == "line" or p["points"].size() < 2: continue
		var s := PathGeo.sample(p["points"], p.get("closed", false), 2.0)
		_path_cache.append({"pos": s["pos"], "r": float(p.get("width", 6.0)) * 0.5 + 1.0})
	_path_cache_valid = true
	return _path_cache

func is_blocked(p: Vector3) -> bool:
	for w in data.waters:
		match w["kind"]:
			"lake", "ocean":
				if p.y < w["level"] + 0.05: return true
			"plane":
				var c := Vector2(w["center"][0], w["center"][1])
				if Vector2(p.x, p.z).distance_to(c) < maxf(w["size"][0], w["size"][1]) * 0.55: return true
	for pc in _paths_cache():
		var pos: PackedVector3Array = pc["pos"]
		var r2: float = pc["r"] * pc["r"]
		for q in pos:
			var dx := q.x - p.x; var dz := q.z - p.z
			if dx * dx + dz * dz < r2: return true
	return false

# ------------------------------------------------------------------ selection
func select_at(pos: Vector2) -> void:
	var g = cam.screen_to_ground(pos)
	var best: MapObject = null
	var best_d := 52.0
	var cands: Array = []
	var centre: Vector3 = g if g != null else cam.focus
	cands = data.query_objects(centre, maxf(14.0, cam.dist * 0.35))
	for o in cands:
		var aabb := assets.get_aabb(o.asset)
		var mid: Vector3 = o.xf * aabb.get_center() if aabb.size != Vector3.ZERO else o.xf.origin
		if cam.cam.is_position_behind(mid): continue
		var d := cam.cam.unproject_position(mid).distance_to(pos)
		if d < best_d: best_d = d; best = o
	selected = best
	update_selection_marker()
	if ui: ui.refresh_panel()

func update_selection_marker() -> void:
	if selected == null:
		_sel_marker.mesh = null
		return
	var aabb := assets.get_aabb(selected.asset)
	if aabb.size == Vector3.ZERO: aabb = AABB(Vector3(-0.5, 0, -0.5), Vector3(1, 1, 1))
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var c: Array = []
	for i in 8:
		c.append(selected.xf * (aabb.position + Vector3(aabb.size.x * (i & 1), aabb.size.y * ((i >> 1) & 1), aabb.size.z * ((i >> 2) & 1))))
	for e in [[0, 1], [2, 3], [4, 5], [6, 7], [0, 2], [1, 3], [4, 6], [5, 7], [0, 4], [1, 5], [2, 6], [3, 7]]:
		im.surface_add_vertex(c[e[0]]); im.surface_add_vertex(c[e[1]])
	im.surface_end()
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.85, 0.15)
	m.no_depth_test = true
	im.surface_set_material(0, m)
	_sel_marker.mesh = im
	_sel_marker.global_transform = Transform3D.IDENTITY

func edit_selected(fn: Callable, label := "Edit object") -> void:
	if selected == null: return
	var st := undo.begin(label)
	st.obj_moved.append([selected, selected.xf])
	var chunks := [data.obj_chunk(selected.xf.origin)]
	var nx: Transform3D = fn.call(selected.xf)
	data.move_object(selected, nx)
	chunks.append(data.obj_chunk(nx.origin))
	data.objects_changed.emit(chunks)
	undo.commit(st)
	update_selection_marker()

func delete_selected() -> void:
	if selected == null: return
	var st := undo.begin("Delete")
	st.obj_removed.append(selected)
	var ch := [data.obj_chunk(selected.xf.origin)]
	data.remove_object(selected)
	data.objects_changed.emit(ch)
	undo.commit(st)
	selected = null
	update_selection_marker()
	if ui: ui.refresh_panel()

func duplicate_selected() -> void:
	if selected == null: return
	var o := MapObject.make(selected.asset, selected.xf)
	var xf := o.xf
	xf.origin += Vector3(2.5, 0, 2.5)
	xf.origin.y = data.height_at(xf.origin.x, xf.origin.z)
	o.xf = xf
	var st := undo.begin("Duplicate")
	st.obj_added.append(o)
	data.add_object(o)
	data.objects_added.emit([o])
	undo.commit(st)
	selected = o
	update_selection_marker()

# ------------------------------------------------------------------ paths
func new_path() -> void:
	var t: String = P["path_type"]
	var p := {"type": t, "points": PackedVector3Array(), "width": P["path_width"], "shoulder": P["path_shoulder"],
		"depth": P["path_depth"], "closed": false, "name": "%s %d" % [t.capitalize(), data.paths.size() + 1],
		"asset": P["asset"], "spacing": P["path_spacing"], "offset": P["path_offset"], "align": 0.0, "scale": 1.0,
		"preset": "river", "mat": "road"}
	if t == "rail": p["width"] = 4.2
	if t == "river": p["width"] = maxf(P["path_width"], 10.0)
	data.paths.append(p)
	active_path = data.paths.size() - 1
	sel_point = -1

func rebuild_active_path() -> void:
	_path_cache_valid = false
	if active_path >= 0:
		paths.rebuild(active_path)
	update_path_markers()
	path_dirty = false

func update_path_markers() -> void:
	var mm := _path_markers.multimesh
	if tool_id != "path" or active_path < 0 or active_path >= data.paths.size():
		mm.instance_count = 0
		return
	var pts: PackedVector3Array = data.paths[active_path]["points"]
	mm.instance_count = pts.size()
	var sc := clampf(cam.dist * 0.016, 0.6, 12.0)
	for i in pts.size():
		var s := sc * (1.7 if i == sel_point else 1.0)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), pts[i] + Vector3(0, 0.4, 0)))
		mm.set_instance_color(i, Color(1.0, 0.85, 0.15) if i == sel_point else (Color(0.3, 0.9, 1.0) if i > 0 else Color(0.4, 1.0, 0.4)))

func refresh_panel() -> void:
	if ui: ui.refresh_panel()

# ------------------------------------------------------------------ input
func _unhandled_input(ev: InputEvent) -> void:
	if walk_mode:
		_walk_input(ev); return
	if ev is InputEventScreenTouch:
		var t := ev as InputEventScreenTouch
		if t.pressed:
			touches[t.index] = t.position
			_touch_down(t.index, t.position)
		else:
			_touch_up(t.index, t.position)
			touches.erase(t.index)
	elif ev is InputEventScreenDrag:
		var d := ev as InputEventScreenDrag
		touches[d.index] = d.position
		_touch_move(d.index, d.position, d.relative)
	elif ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP: cam.zoom_mul(0.9)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN: cam.zoom_mul(1.1)
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			if Input.is_key_pressed(KEY_SHIFT): cam.pan_screen(mm.relative.x, mm.relative.y)
			else: cam.orbit(mm.relative.x, mm.relative.y)
		elif mm.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			cam.pan_screen(mm.relative.x, mm.relative.y)
		elif mm.button_mask == 0 and touches.is_empty():
			tool.hover(mm.position)

func _touch_down(idx: int, pos: Vector2) -> void:
	last_pointer = pos
	if touches.size() == 1:
		if P["cam_mode"]:
			_g_mode = "orbit"
		else:
			_g_mode = "tool"
			_pending = idx; _pending_pos = pos; _pending_t = 0.0
	else:
		_abort_tool()
		_g_mode = "cam"
		_reset_cam_gesture()

func _abort_tool() -> void:
	if tool.active: tool.cancel()
	_pending = -1

func _start_pending() -> void:
	if _pending >= 0 and _g_mode == "tool":
		var p := _pending_pos
		_pending = -1
		tool.begin(p)

func _touch_up(idx: int, pos: Vector2) -> void:
	last_pointer = pos
	if _g_mode == "tool" and idx == _pending:
		_start_pending()
	if _g_mode == "tool" and tool.active:
		tool.end()
	if touches.size() <= 1:
		_g_mode = "none"
	elif _g_mode == "cam":
		_reset_cam_gesture.call_deferred()

func _touch_move(idx: int, pos: Vector2, rel: Vector2) -> void:
	last_pointer = pos
	match _g_mode:
		"orbit":
			cam.orbit(rel.x, rel.y)
		"tool":
			if _pending == idx:
				_pending_pos = pos
				_start_pending()
			if tool.active: tool.drag(pos)
		"cam":
			_cam_gesture()

func _reset_cam_gesture() -> void:
	var pts := touches.values()
	if pts.size() < 2: return
	_g_prev_mid = _mid(pts)
	_g_prev_dist = maxf((pts[0] as Vector2).distance_to(pts[1]), 1.0)
	_g_prev_ang = ((pts[1] as Vector2) - (pts[0] as Vector2)).angle()

func _mid(pts: Array) -> Vector2:
	var m := Vector2.ZERO
	for p in pts: m += p
	return m / pts.size()

func _cam_gesture() -> void:
	var pts := touches.values()
	if pts.size() < 2: return
	var mid := _mid(pts)
	var dist := maxf((pts[0] as Vector2).distance_to(pts[1]), 1.0)
	var ang := ((pts[1] as Vector2) - (pts[0] as Vector2)).angle()
	var dm := mid - _g_prev_mid
	if pts.size() >= 3:
		cam.orbit(0.0, dm.y)
	else:
		cam.pan_screen(dm.x, dm.y)
		cam.zoom_mul(_g_prev_dist / dist)
		cam.twist(-wrapf(ang - _g_prev_ang, -PI, PI))
	_g_prev_mid = mid; _g_prev_dist = dist; _g_prev_ang = ang

func _process(dt: float) -> void:
	if walk_mode:
		cam.walk_step(_walk_move, _walk_look, dt, false)
		_walk_look = Vector2.ZERO
		return
	if _pending >= 0:
		_pending_t += dt
		if _pending_t > 0.07: _start_pending()
	if tool != null and tool.active: tool.tick(dt)
	if path_dirty and active_path >= 0:
		path_dirty = false
		paths.rebuild(active_path)
	if _terr_edit_t >= 0.0:
		_terr_edit_t += dt
		if _terr_edit_t > 0.45 and not (tool != null and tool.active):
			_terr_edit_t = -1.0
			if not data.waters.is_empty(): water.rebuild_all()
			if not data.paths.is_empty(): _path_cache_valid = false; paths.rebuild_all()
	_marker_t += dt
	if _marker_t > 0.15:
		_marker_t = 0.0
		if tool_id == "path": update_path_markers()
	_autosave_t += dt
	if _autosave_t > 120.0:
		_autosave_t = 0.0
		data.save_to(MAPS_DIR + "/_autosave.zexmap")
	# desktop keyboard fly
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): mv.z -= 1
	if Input.is_key_pressed(KEY_S): mv.z += 1
	if Input.is_key_pressed(KEY_A): mv.x -= 1
	if Input.is_key_pressed(KEY_D): mv.x += 1
	if mv != Vector3.ZERO:
		var yaw := cam.yaw
		var f := Vector3(-sin(yaw), 0, -cos(yaw)); var r := Vector3(cos(yaw), 0, -sin(yaw))
		cam.pan_world((f * -mv.z + r * mv.x) * cam.dist * 0.9 * dt)

# ------------------------------------------------------------------ walk preview
func enter_walk() -> void:
	walk_mode = true
	tool.deactivate()
	var f := cam.focus
	cam.enter_walk(Vector3(f.x, data.height_at(f.x, f.z), f.z))
	ui.set_walk(true)

func exit_walk() -> void:
	walk_mode = false
	cam.exit_walk()
	ui.set_walk(false)
	set_tool(tool_id)

func _walk_input(ev: InputEvent) -> void:
	var half := get_viewport().get_visible_rect().size.x * 0.5
	if ev is InputEventScreenTouch:
		var t := ev as InputEventScreenTouch
		if t.pressed:
			if t.position.x < half and _walk_touch_move < 0:
				_walk_touch_move = t.index; _walk_origin = t.position
			elif _walk_touch_look < 0:
				_walk_touch_look = t.index
		else:
			if t.index == _walk_touch_move: _walk_touch_move = -1; _walk_move = Vector2.ZERO
			if t.index == _walk_touch_look: _walk_touch_look = -1
	elif ev is InputEventScreenDrag:
		var d := ev as InputEventScreenDrag
		if d.index == _walk_touch_move:
			_walk_move = ((d.position - _walk_origin) / 90.0).limit_length(1.0)
		elif d.index == _walk_touch_look:
			_walk_look += d.relative
