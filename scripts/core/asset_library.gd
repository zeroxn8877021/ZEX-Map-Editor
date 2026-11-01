# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : asset_library.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name AssetLibrary
extends Node
## The object library. Anything dropped into  res://import_assets/  (dev) or  user://assets/  (device / in-app import)
## shows up automatically; "Refresh" rescans. Models are loaded at runtime (GLTFDocument), so no editor re-import is needed
## for user:// assets. Entries keep category, bounds and a rendered thumbnail.

signal changed
signal thumb_ready(id: String)
signal scale_changed(id: String)

const USER_DIR := "user://assets"
const DEV_DIR := "res://import_assets"
const MODEL_EXT := ["glb", "gltf", "tscn", "scn"]
const IMG_EXT := ["png", "jpg", "jpeg", "webp"]
const CATS := ["Trees", "Plants", "Rocks", "Buildings", "Rails & Fence", "Props", "Other"]

var entries: Dictionary = {}            # id -> {id,name,path,category,aabb:AABB}
var textures: Array = []                # [{name,path}]
var _parts: Dictionary = {}
var _cat_override: Dictionary = {}
var _scale_mul: Dictionary = {}          # id -> user scale multiplier (persisted)
var _lod_cache: Dictionary = {}
var _thumbs: Dictionary = {}
var _thumb_queue: Array = []
var _thumb_busy := false
var _vp: SubViewport
var _cam: Camera3D
var _holder: Node3D

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	DirAccess.make_dir_recursive_absolute(USER_DIR + "/textures")
	_load_cats()
	scan()

# ------------------------------------------------------------------ scanning
func scan() -> void:
	var found: Dictionary = {}
	var tex: Array = []
	for root in [DEV_DIR, USER_DIR]:
		_walk(root, found, tex)
	# keep existing entries' cached parts if the file is unchanged
	for id in entries.keys():
		if not found.has(id):
			_parts.erase(id); _thumbs.erase(id)
	entries = found
	textures = tex
	for id in entries:
		if not _thumbs.has(id) and not _thumb_queue.has(id):
			_thumb_queue.append(id)
	changed.emit()
	_pump_thumbs()

func _walk(dir: String, found: Dictionary, tex: Array) -> void:
	var da := DirAccess.open(dir)
	if da == null: return
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if f.begins_with("."):
			f = da.get_next(); continue
		var full := dir.path_join(f)
		if da.current_is_dir():
			_walk(full, found, tex)
		else:
			var name := f
			if name.ends_with(".remap"): name = name.trim_suffix(".remap")
			if name.ends_with(".import"):
				f = da.get_next(); continue
			var ext := name.get_extension().to_lower()
			if ext in MODEL_EXT:
				var path := full.trim_suffix(".remap")
				var id := name.get_basename().to_lower().replace(" ", "_")
				if not found.has(id):
					found[id] = {"id": id, "name": name.get_basename(), "path": path, "category": _cat_override.get(id, guess_category(id)), "aabb": AABB()}
			elif ext in IMG_EXT:
				tex.append({"name": name.get_basename(), "path": full.trim_suffix(".remap")})
		f = da.get_next()
	da.list_dir_end()

static func guess_category(id: String) -> String:
	var n := id.to_lower()
	for k in ["tree", "pine", "oak", "palm", "birch", "spruce", "log"]:
		if n.contains(k): return "Trees"
	for k in ["grass", "bush", "shrub", "fern", "flower", "plant", "weed", "reed"]:
		if n.contains(k): return "Plants"
	for k in ["rock", "stone", "boulder", "cliff"]:
		if n.contains(k): return "Rocks"
	for k in ["house", "building", "hut", "tower", "wall", "barn", "shed", "ruin", "bridge", "gate"]:
		if n.contains(k): return "Buildings"
	for k in ["fence", "rail", "track", "sleeper", "pole", "lamp", "sign"]:
		if n.contains(k): return "Rails & Fence"
	return "Props"

func set_category(id: String, cat: String) -> void:
	_cat_override[id] = cat
	_parts.erase(id)
	if entries.has(id): entries[id]["category"] = cat
	var f := FileAccess.open(USER_DIR + "/categories.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_cat_override)); f.close()
	changed.emit()

func _load_cats() -> void:
	var f := FileAccess.open(USER_DIR + "/categories.json", FileAccess.READ)
	if f:
		var d = JSON.parse_string(f.get_as_text())
		if typeof(d) == TYPE_DICTIONARY: _cat_override = d
		f.close()
	var f2 := FileAccess.open(USER_DIR + "/scales.json", FileAccess.READ)
	if f2:
		var d2 = JSON.parse_string(f2.get_as_text())
		if typeof(d2) == TYPE_DICTIONARY: _scale_mul = d2
		f2.close()

func set_scale_mul(id: String, v: float) -> void:
	_scale_mul[id] = v
	_parts.erase(id); _thumbs.erase(id)
	var f := FileAccess.open(USER_DIR + "/scales.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_scale_mul)); f.close()
	get_parts(id)
	scale_changed.emit(id)

func get_scale_mul(id: String) -> float:
	return float(_scale_mul.get(id, 1.0))

func ids_in(cat: String) -> Array:
	var out: Array = []
	for id in entries:
		if cat == "All" or entries[id]["category"] == cat: out.append(id)
	out.sort()
	return out

# ------------------------------------------------------------------ import
## Copies a model (or image) into user://assets and rescans. Returns the new id / "" on failure.
func import_file(src: String) -> String:
	var ext := src.get_extension().to_lower()
	var fname := src.get_file()
	if ext in MODEL_EXT:
		var dst := USER_DIR.path_join(fname)
		if DirAccess.copy_absolute(src, dst) != OK: return ""
		if ext == "gltf":   # sidecar buffers
			var base := src.get_base_dir()
			for side in [fname.get_basename() + ".bin"]:
				if FileAccess.file_exists(base.path_join(side)):
					DirAccess.copy_absolute(base.path_join(side), USER_DIR.path_join(side))
		scan()
		return fname.get_basename().to_lower().replace(" ", "_")
	if ext in IMG_EXT:
		var dst2 := USER_DIR.path_join("textures").path_join(fname)
		if DirAccess.copy_absolute(src, dst2) != OK: return ""
		scan()
		return "tex:" + dst2
	return ""

func remove_asset(id: String) -> void:
	if not entries.has(id): return
	var p: String = entries[id]["path"]
	if p.begins_with("user://"):
		DirAccess.remove_absolute(p)
	entries.erase(id); _parts.erase(id)
	changed.emit()

# ------------------------------------------------------------------ loading
func _instantiate(id: String) -> Node:
	var e: Dictionary = entries.get(id, {})
	if e.is_empty(): return null
	var p: String = e["path"]
	var ext := p.get_extension().to_lower()
	if p.begins_with("res://") and ext in ["glb", "gltf", "tscn", "scn"]:
		var ps = load(p)
		if ps is PackedScene: return ps.instantiate()
	if ext == "tscn" or ext == "scn":
		var ps2 = load(p)
		return ps2.instantiate() if ps2 is PackedScene else null
	# runtime glTF (user://)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(p, st, 0, "") != OK: return null
	return doc.generate_scene(st)

## Mesh parts of an asset: [{mesh: Mesh, xf: Transform3D}] relative to the asset root. Units are normalised
## (a tree exported in centimetres or a rock far from the origin still lands at a sensible size / pivot).
func get_parts(id: String) -> Array:
	if _parts.has(id): return _parts[id]
	var raw: Array = []
	var root := _instantiate(id)
	if root != null:
		_collect(root, Transform3D.IDENTITY, raw, true)
		root.free()
	var box := _union(raw, Transform3D.IDENTITY)
	var cat: String = entries[id]["category"] if entries.has(id) else "Props"
	var auto_s := _auto_scale(cat, box)
	var s := auto_s * float(_scale_mul.get(id, 1.0))
	var fix := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), Vector3.ZERO)
	var sb := _union(raw, fix)
	var sz := sb.size
	var c := sb.get_center()
	var shift := Vector3.ZERO
	if Vector2(c.x, c.z).length() > 0.5 * maxf(sz.x, sz.z) or sb.position.y < -0.25 * sz.y or sb.position.y > 0.25 * sz.y:
		shift = Vector3(-c.x, -sb.position.y, -c.z)
	fix.origin = shift
	var out: Array = []
	for p in raw:
		out.append({"mesh": p["mesh"], "xf": fix * p["xf"]})
	_parts[id] = out
	if entries.has(id):
		entries[id]["aabb"] = _union(out, Transform3D.IDENTITY)
		entries[id]["auto_scale"] = auto_s
	return out

func _union(parts: Array, pre: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	for p in parts:
		var b: AABB = pre * p["xf"] * p["mesh"].get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box

static func _auto_scale(cat: String, box: AABB) -> float:
	var sz := box.size
	var longest := maxf(sz.x, maxf(sz.y, sz.z))
	if longest <= 0.0001: return 1.0
	match cat:
		"Trees":
			if sz.y < 2.0 or sz.y > 45.0: return 9.0 / maxf(sz.y, 0.0001)
		"Plants":
			if sz.y < 0.1 or sz.y > 4.0: return 0.9 / maxf(sz.y, 0.0001)
		"Rocks":
			if longest < 0.3 or longest > 12.0: return 2.2 / longest
		"Buildings":
			if longest < 2.0 or longest > 70.0: return 10.0 / longest
		"Rails & Fence":
			if longest < 0.3 or longest > 12.0: return 3.0 / longest
		_:
			if longest < 0.1 or longest > 30.0: return 1.5 / longest
	return 1.0

## Drops vertices no index uses and the attributes a GLB export does not need (tangents, UV2, skinning).
static func _compact(a: Array) -> Array:
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var remap := PackedInt32Array(); remap.resize(verts.size()); remap.fill(-1)
	var order := PackedInt32Array()
	var new_idx := PackedInt32Array(); new_idx.resize(idx.size())
	for i in idx.size():
		var v := idx[i]
		if remap[v] < 0:
			remap[v] = order.size()
			order.append(v)
		new_idx[i] = remap[v]
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	var nv := PackedVector3Array(); nv.resize(order.size())
	for i in order.size(): nv[i] = verts[order[i]]
	out[Mesh.ARRAY_VERTEX] = nv
	if a[Mesh.ARRAY_NORMAL] != null:
		var src: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var dst := PackedVector3Array(); dst.resize(order.size())
		for i in order.size(): dst[i] = src[order[i]]
		out[Mesh.ARRAY_NORMAL] = dst
	if a[Mesh.ARRAY_TEX_UV] != null:
		var src2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
		var dst2 := PackedVector2Array(); dst2.resize(order.size())
		for i in order.size(): dst2[i] = src2[order[i]]
		out[Mesh.ARRAY_TEX_UV] = dst2
	if a[Mesh.ARRAY_COLOR] != null:
		var src3: PackedColorArray = a[Mesh.ARRAY_COLOR]
		var dst3 := PackedColorArray(); dst3.resize(order.size())
		for i in order.size(): dst3[i] = src3[order[i]]
		out[Mesh.ARRAY_COLOR] = dst3
	out[Mesh.ARRAY_INDEX] = new_idx
	return out

## Reduced-polygon copy of a mesh (uses the engine's LOD generator). keep = fraction of triangles to keep (0..1).
func decimated(mesh: Mesh, keep: float) -> Mesh:
	if keep >= 0.99 or not (mesh is ArrayMesh): return mesh
	var key := "%d_%d" % [mesh.get_instance_id(), int(keep * 100)]
	if _lod_cache.has(key): return _lod_cache[key]
	var im := ImporterMesh.new()
	var src_arrays: Array = []
	for sidx in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(sidx)
		src_arrays.append(arr)
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, mesh.surface_get_material(sidx))
	im.generate_lods(60.0, 25.0, [])
	var out := ArrayMesh.new()
	for sidx in mesh.get_surface_count():
		var arrays: Array = src_arrays[sidx].duplicate()
		for ci in [Mesh.ARRAY_CUSTOM0, Mesh.ARRAY_CUSTOM1, Mesh.ARRAY_CUSTOM2, Mesh.ARRAY_CUSTOM3]:
			arrays[ci] = null
		var base: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var best: PackedInt32Array = base
		for l in im.get_surface_lod_count(sidx):
			var ind := im.get_surface_lod_indices(sidx, l)
			best = ind
			if ind.size() <= base.size() * keep: break
		if best.size() >= 3:
			arrays[Mesh.ARRAY_INDEX] = best
		arrays = _compact(arrays)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(sidx))
	_lod_cache[key] = out
	return out

func _collect(n: Node, parent_xf: Transform3D, out: Array, is_root: bool) -> void:
	var xf := parent_xf
	if n is Node3D and not is_root:
		xf = parent_xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append({"mesh": (n as MeshInstance3D).mesh, "xf": xf})
	for c in n.get_children():
		_collect(c, xf, out, false)

func get_aabb(id: String) -> AABB:
	get_parts(id)
	return entries[id]["aabb"] if entries.has(id) else AABB()

func make_instance(id: String) -> Node3D:
	## A real Node3D for previews / export (shares the cached meshes).
	var root := Node3D.new()
	for p in get_parts(id):
		var mi := MeshInstance3D.new()
		mi.mesh = p["mesh"]
		mi.transform = p["xf"]
		root.add_child(mi)
	return root

# ------------------------------------------------------------------ thumbnails
func thumb(id: String) -> Texture2D:
	return _thumbs.get(id)

func _pump_thumbs() -> void:
	if _thumb_busy or _thumb_queue.is_empty(): return
	if DisplayServer.get_name() == "headless": return
	_thumb_busy = true
	if _vp == null:
		_vp = SubViewport.new()
		_vp.size = Vector2i(112, 112)
		_vp.own_world_3d = true
		_vp.transparent_bg = true
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(_vp)
		_cam = Camera3D.new(); _cam.fov = 30.0
		_vp.add_child(_cam)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-50, -35, 0)
		_vp.add_child(sun)
		var we := WorldEnvironment.new()
		var env := Environment.new()
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(0.7, 0.75, 0.8)
		env.ambient_light_energy = 0.8
		we.environment = env
		_vp.add_child(we)
		_holder = Node3D.new()
		_vp.add_child(_holder)
	_render_next()

func _render_next() -> void:
	while not _thumb_queue.is_empty():
		var id: String = _thumb_queue.pop_front()
		if not entries.has(id): continue
		var inst := make_instance(id)
		if inst.get_child_count() == 0:
			inst.free(); continue
		_holder.add_child(inst)
		var box := get_aabb(id)
		var c := box.get_center()
		var r := maxf(box.size.length() * 0.5, 0.2)
		_cam.position = c + Vector3(0.6, 0.45, 1.0).normalized() * r * 3.4
		_cam.look_at(c)
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var img := _vp.get_texture().get_image()
		if img != null and not img.is_empty():
			_thumbs[id] = ImageTexture.create_from_image(img)
			thumb_ready.emit(id)
		inst.queue_free()
		await get_tree().process_frame
	_thumb_busy = false
