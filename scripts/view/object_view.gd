# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : object_view.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name ObjectView
extends Node3D
## Placed objects as MultiMeshes per (32 m chunk, asset, mesh part). Chunks are STREAMED: only chunks within `radius` of the
## camera exist as nodes (data stays in MapData), new placements are appended in place (capacity doubling) instead of
## rebuilding the chunk, and chunks outside the radius are freed.

var data: MapData
var assets: AssetLibrary
var radius := 450.0                 # stream radius (m), driven by the draw-distance slider
var view_distance := 0.0            # 0 = radius
var shadows := false
var missing: Dictionary = {}
var budget_ms := 5.0
var _chunks: Dictionary = {}        # Vector2i -> {node, slots}
var _dirty: Dictionary = {}
var _stream_t := 1.0
var _queue: Array = []
var stats := {"built": 0, "fast_adds": 0, "rebuilds": 0}

func setup(d: MapData, a: AssetLibrary) -> void:
	data = d
	assets = a
	rebuild_all()

func rebuild_all() -> void:
	for k in _chunks.keys(): _free_chunk(k)
	_chunks.clear(); _dirty.clear(); _queue.clear()
	_stream_t = 1.0

func mark(keys: Array) -> void:
	for k in keys:
		if _chunks.has(k) or data.obj_chunks.has(k): _dirty[k] = true

func built_count() -> int:
	return _chunks.size()

func apply_settings() -> void:
	for k in _chunks:
		for slot in _chunks[k]["slots"].values():
			for mmi: MultiMeshInstance3D in slot["mmis"]:
				mmi.visibility_range_end = _vis_end()
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _vis_end() -> float:
	return view_distance if view_distance > 0.0 else radius + 24.0

func _cam_pos() -> Vector3:
	var c := get_viewport().get_camera_3d()
	return c.global_position if c != null else Vector3.ZERO

func _chunk_dist(k: Vector2i, p: Vector3) -> float:
	var cx := (k.x + 0.5) * MapData.OBJ_CHUNK; var cz := (k.y + 0.5) * MapData.OBJ_CHUNK
	return maxf(Vector2(cx - p.x, cz - p.z).length() - MapData.OBJ_CHUNK * 0.7, 0.0)

func _update_stream() -> void:
	var p := _cam_pos()
	_queue.clear()
	for k in data.obj_chunks:
		if _chunks.has(k): continue
		var d := _chunk_dist(k, p)
		if d < radius: _queue.append([d, k])
	_queue.sort_custom(func(a, b): return a[0] < b[0])
	for k in _chunks.keys():
		if _chunk_dist(k, p) > radius * 1.3 + 16.0 or not data.obj_chunks.has(k):
			_free_chunk(k); _chunks.erase(k)

func _process(dt: float) -> void:
	if data == null: return
	_stream_t += dt
	if _stream_t > 0.3:
		_stream_t = 0.0
		_update_stream()
	var t0 := Time.get_ticks_usec()
	for k in _dirty.keys():
		_dirty.erase(k)
		if _chunks.has(k):
			_free_chunk(k); _chunks.erase(k)
		if data.obj_chunks.has(k):
			_build_chunk(k); stats["rebuilds"] += 1
		if (Time.get_ticks_usec() - t0) / 1000.0 > budget_ms: return
	while not _queue.is_empty() and (Time.get_ticks_usec() - t0) / 1000.0 < budget_ms:
		var job: Array = _queue.pop_front()
		if _chunks.has(job[1]) or not data.obj_chunks.has(job[1]): continue
		_build_chunk(job[1]); stats["built"] += 1

func _free_chunk(k: Vector2i) -> void:
	if _chunks.has(k): _chunks[k]["node"].queue_free()

func _pow2(n: int) -> int:
	var c := 8
	while c < n: c *= 2
	return c

func _objects_in_chunk(k: Vector2i) -> Dictionary:
	var per := int(MapData.OBJ_CHUNK / MapData.GRID_CELL)
	var by_asset: Dictionary = {}
	for gz in range(k.y * per, (k.y + 1) * per):
		for gx in range(k.x * per, (k.x + 1) * per):
			var arr = data.obj_grid.get(Vector2i(gx, gz))
			if arr == null: continue
			for o: MapObject in arr:
				if not by_asset.has(o.asset): by_asset[o.asset] = []
				by_asset[o.asset].append(o)
	return by_asset

func _build_chunk(k: Vector2i) -> void:
	var by_asset := _objects_in_chunk(k)
	if by_asset.is_empty(): return
	var holder := Node3D.new()
	holder.name = "c_%d_%d" % [k.x, k.y]
	add_child(holder)
	var rec := {"node": holder, "slots": {}}
	_chunks[k] = rec
	var box := AABB(Vector3(k.x * MapData.OBJ_CHUNK - 20.0, -300.0, k.y * MapData.OBJ_CHUNK - 20.0), Vector3(MapData.OBJ_CHUNK + 40.0, 1200.0, MapData.OBJ_CHUNK + 40.0))
	for aid in by_asset:
		var parts := assets.get_parts(aid)
		if parts.is_empty():
			missing[aid] = true
			continue
		var list: Array = by_asset[aid]
		var cap := _pow2(int(list.size() * 1.5))
		var mmis: Array = []
		for p in parts:
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = p["mesh"]
			mm.instance_count = cap
			var pxf: Transform3D = p["xf"]
			for i in list.size():
				mm.set_instance_transform(i, (list[i] as MapObject).xf * pxf)
			mm.visible_instance_count = list.size()
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.custom_aabb = box
			mmi.visibility_range_end = _vis_end()
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			holder.add_child(mmi)
			mmis.append(mmi)
		rec["slots"][aid] = {"mmis": mmis, "parts": parts, "count": list.size(), "cap": cap}

## Fast path for newly placed objects: append in place when the chunk is loaded and has room.
func add_objects(list: Array) -> void:
	for o: MapObject in list:
		var k := data.obj_chunk(o.xf.origin)
		if not _chunks.has(k):
			if data.obj_chunks.has(k): _dirty[k] = true
			continue
		var slots: Dictionary = _chunks[k]["slots"]
		var slot = slots.get(o.asset)
		if slot == null or slot["count"] >= slot["cap"]:
			_dirty[k] = true
			continue
		var i: int = slot["count"]
		for pi in slot["parts"].size():
			var mmi: MultiMeshInstance3D = slot["mmis"][pi]
			mmi.multimesh.set_instance_transform(i, o.xf * slot["parts"][pi]["xf"])
			mmi.multimesh.visible_instance_count = i + 1
		slot["count"] = i + 1
		stats["fast_adds"] += 1
