# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : map_data.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name MapData
extends RefCounted
## All editable map state. The map is made of 50 x 50 m ground tiles (tile (0,0) is centred on the world origin, tiles are
## addressed by Vector2i offsets and can be negative). Heights / splat live in dense arrays that cover `t_count` tiles per side
## and are re-allocated (signal `grown`) when a tile is added outside the current capacity. Only tiles in `tiles` exist.

signal changed_region(rect: Rect2i)           # height cells changed (inclusive cell rect)
signal splat_changed()                        # whole splat changed
signal splat_region_changed(rect: Rect2i)     # splat pixels changed
signal objects_changed(chunks: Array)         # chunk keys whose objects changed (rebuild)
signal objects_added(list: Array)             # freshly placed MapObjects (fast append)
signal waters_changed()
signal paths_changed()
signal tiles_changed()
signal grown()

const LAYERS := 8
const TILE := 50                              # tile edge in cells == metres (cell = 1 m)
const MAX_T := 31                             # max tiles per side (31 -> 1550 m)
const OBJ_CHUNK := 32.0
const GRID_CELL := 8.0

var map_name: String = "Untitled"
var t_count: int = 3                          # dense capacity in tiles per side (odd)
var tiles: Dictionary = {}                    # Vector2i -> true
var cell: float = 1.0
var cells: int = 150
var verts: int = 151
var size: float = 150.0
var heights: PackedFloat32Array
var splat_res: int = 150
var splat: Array[Image] = []
var layer_mats: PackedStringArray = PackedStringArray(["proto", "grass", "dirt", "rock", "sand", "snow", "gravel", "road"])
var objects: Array = []                       # Array[MapObject]
var obj_grid: Dictionary = {}                 # Vector2i -> Array[MapObject]
var obj_chunks: Dictionary = {}               # Vector2i -> object count
var waters: Array = []
var paths: Array = []
var sky_preset: String = "day"
var _tmask := PackedByteArray()               # t_count^2, 1 = tile exists

func _init(tiles_per_side: int = 1) -> void:
	var n := maxi(3, tiles_per_side)
	if n % 2 == 0: n += 1
	_alloc(mini(n, MAX_T))
	tiles[Vector2i.ZERO] = true
	_rebuild_mask()

func _alloc(count: int) -> void:
	t_count = count
	cells = t_count * TILE
	verts = cells + 1
	size = float(cells)
	splat_res = cells
	heights = PackedFloat32Array(); heights.resize(verts * verts)
	splat.clear()
	for i in 2:
		var im := Image.create(splat_res, splat_res, false, Image.FORMAT_RGBA8)
		im.fill(Color(1, 0, 0, 0) if i == 0 else Color(0, 0, 0, 0))
		splat.append(im)

# ------------------------------------------------------------------ tiles
func slot_of(mat_id: String) -> int:
	return layer_mats.find(mat_id)

func half_t() -> int:
	return (t_count - 1) / 2

func tile_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / TILE + 0.5), floori(z / TILE + 0.5))

func tile_min(t: Vector2i) -> Vector2:
	return Vector2(t.x * TILE - TILE * 0.5, t.y * TILE - TILE * 0.5)

func tile_center(t: Vector2i) -> Vector2:
	return Vector2(t.x * TILE, t.y * TILE)

func _rebuild_mask() -> void:
	_tmask = PackedByteArray(); _tmask.resize(t_count * t_count); _tmask.fill(0)
	var h := half_t()
	for t in tiles:
		var tx: int = t.x + h; var tz: int = t.y + h
		if tx >= 0 and tz >= 0 and tx < t_count and tz < t_count:
			_tmask[tz * t_count + tx] = 1

func _tm(tx: int, tz: int) -> bool:
	return tx >= 0 and tz >= 0 and tx < t_count and tz < t_count and _tmask[tz * t_count + tx] == 1

## Height vertex belongs to an existing tile (borders count for both neighbours).
func vert_active(gx: int, gz: int) -> bool:
	var a := gx / TILE; var b := (gx - 1) / TILE if gx > 0 else a
	var c := gz / TILE; var e := (gz - 1) / TILE if gz > 0 else c
	return _tm(a, c) or _tm(b, c) or _tm(a, e) or _tm(b, e)

func px_active(px: int, pz: int) -> bool:
	return _tm(px / TILE, pz / TILE)

func is_active_at(x: float, z: float) -> bool:
	return tiles.has(tile_of(x, z))

func active_bounds() -> Rect2:
	if tiles.is_empty(): return Rect2(-TILE * 0.5, -TILE * 0.5, TILE, TILE)
	var mn := Vector2i(1 << 20, 1 << 20); var mx := Vector2i(-(1 << 20), -(1 << 20))
	for t in tiles:
		mn.x = mini(mn.x, t.x); mn.y = mini(mn.y, t.y); mx.x = maxi(mx.x, t.x); mx.y = maxi(mx.y, t.y)
	var lo := tile_min(mn)
	return Rect2(lo.x, lo.y, (mx.x - mn.x + 1) * TILE, (mx.y - mn.y + 1) * TILE)

## Re-allocates the dense arrays to cover `new_count` tiles per side (old data stays at the same world position).
func _grow(new_count: int) -> void:
	var old_h := heights; var old_v := verts; var old_n := t_count
	var old_splat := splat.duplicate()
	var off := ((new_count - old_n) / 2) * TILE
	_alloc(new_count)
	for iz in old_v:
		for ix in old_v:
			heights[(iz + off) * verts + ix + off] = old_h[iz * old_v + ix]
	for i in 2:
		splat[i].blit_rect(old_splat[i], Rect2i(0, 0, old_n * TILE, old_n * TILE), Vector2i(off, off))
	_rebuild_mask()
	grown.emit()

## Adds a ground tile. Shared edge heights stay, the new interior blends toward the neighbouring edges (auto snap).
func add_tile(t: Vector2i, st: Variant = null) -> bool:
	if tiles.has(t): return false
	var lim := (MAX_T - 1) / 2
	if absi(t.x) > lim or absi(t.y) > lim: return false
	var need := 2 * maxi(absi(t.x), absi(t.y)) + 1
	if need > t_count: _grow(mini(MAX_T, need + 2))
	var h := half_t()
	var x0 := (t.x + h) * TILE; var z0 := (t.y + h) * TILE
	var left := tiles.has(t + Vector2i(-1, 0)); var right := tiles.has(t + Vector2i(1, 0))
	var up := tiles.has(t + Vector2i(0, -1)); var down := tiles.has(t + Vector2i(0, 1))
	for iz in range(z0, z0 + TILE + 1):
		for ix in range(x0, x0 + TILE + 1):
			var i := iz * verts + ix
			var shared := (ix == x0 and left) or (ix == x0 + TILE and right) or (iz == z0 and up) or (iz == z0 + TILE and down)
			if shared: continue
			var sw := 0.0; var sh := 0.0
			if left:
				var w := 1.0 / pow(ix - x0 + 1.0, 2.0); sw += w; sh += w * heights[iz * verts + x0]
			if right:
				var w2 := 1.0 / pow(x0 + TILE - ix + 1.0, 2.0); sw += w2; sh += w2 * heights[iz * verts + x0 + TILE]
			if up:
				var w3 := 1.0 / pow(iz - z0 + 1.0, 2.0); sw += w3; sh += w3 * heights[z0 * verts + ix]
			if down:
				var w4 := 1.0 / pow(z0 + TILE - iz + 1.0, 2.0); sw += w4; sh += w4 * heights[(z0 + TILE) * verts + ix]
			if st != null: st.touch_h(i)
			heights[i] = (sh / sw) if sw > 0.0 else 0.0
	tiles[t] = true
	_rebuild_mask()
	changed_region.emit(Rect2i(x0, z0, TILE, TILE))
	tiles_changed.emit()
	return true

## Removes a tile (never the last one). Objects standing on it are removed too (recorded in st for undo).
func remove_tile(t: Vector2i, st: Variant = null) -> bool:
	if not tiles.has(t) or tiles.size() <= 1: return false
	var c := tile_center(t)
	var gone: Array = []
	for o in query_objects(Vector3(c.x, 0, c.y), TILE * 0.8):
		if tile_of(o.xf.origin.x, o.xf.origin.z) == t: gone.append(o)
	var chunks: Dictionary = {}
	for o in gone:
		chunks[obj_chunk(o.xf.origin)] = true
		remove_object(o)
		if st != null: st.obj_removed.append(o)
	tiles.erase(t)
	_rebuild_mask()
	if not gone.is_empty(): objects_changed.emit(chunks.keys())
	tiles_changed.emit()
	return true

# ------------------------------------------------------------------ height access
func idx(ix: int, iz: int) -> int:
	return clampi(iz, 0, cells) * verts + clampi(ix, 0, cells)

func h_cell(ix: int, iz: int) -> float:
	return heights[clampi(iz, 0, cells) * verts + clampi(ix, 0, cells)]

func world_to_grid(x: float, z: float) -> Vector2:
	return Vector2((x + size * 0.5) / cell, (z + size * 0.5) / cell)

func grid_to_world(ix: float, iz: float) -> Vector2:
	return Vector2(ix * cell - size * 0.5, iz * cell - size * 0.5)

func inside(x: float, z: float) -> bool:
	var h := size * 0.5
	return x >= -h and x <= h and z >= -h and z <= h

func height_at(x: float, z: float) -> float:
	var g := world_to_grid(x, z)
	var gx := clampf(g.x, 0.0, cells - 0.0001)
	var gz := clampf(g.y, 0.0, cells - 0.0001)
	var ix := int(gx); var iz := int(gz)
	var fx := gx - ix; var fz := gz - iz
	var h00 := heights[iz * verts + ix]
	var h10 := heights[iz * verts + ix + 1]
	var h01 := heights[(iz + 1) * verts + ix]
	var h11 := heights[(iz + 1) * verts + ix + 1]
	if fx + fz < 1.0:
		return h00 + (h10 - h00) * fx + (h01 - h00) * fz
	return h11 + (h01 - h11) * (1.0 - fx) + (h10 - h11) * (1.0 - fz)

func normal_at(x: float, z: float) -> Vector3:
	var e := cell
	var dx := height_at(x + e, z) - height_at(x - e, z)
	var dz := height_at(x, z + e) - height_at(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()

func slope_at(x: float, z: float) -> float:
	return rad_to_deg(acos(clampf(normal_at(x, z).y, -1.0, 1.0)))

# ------------------------------------------------------------------ ray vs heightfield
func raycast(origin: Vector3, dir: Vector3, max_dist: float = 4000.0) -> Variant:
	var step := cell * 0.5
	var t := 0.0
	var prev_t := 0.0
	var prev_above := true
	while t < max_dist:
		var p := origin + dir * t
		if inside(p.x, p.z):
			var above := p.y > height_at(p.x, p.z)
			if not above and prev_above and t > 0.0:
				var a := prev_t; var b := t
				for i in 10:
					var m := (a + b) * 0.5
					var q := origin + dir * m
					if q.y > height_at(q.x, q.z): a = m
					else: b = m
				return origin + dir * ((a + b) * 0.5)
			if not above and t == 0.0:
				return Vector3(origin.x, height_at(origin.x, origin.z), origin.z)
			prev_above = above
		else:
			prev_above = true
		prev_t = t
		t += step * clampf((p.y - (height_at(clampf(p.x, -size * 0.5, size * 0.5), clampf(p.z, -size * 0.5, size * 0.5)))) * 0.15, 1.0, 16.0)
	return null

# ------------------------------------------------------------------ splat access
func splat_px(x: float, z: float) -> Vector2:
	return Vector2((x + size * 0.5) / size * splat_res, (z + size * 0.5) / size * splat_res)

func get_weights(px: int, pz: int) -> PackedFloat32Array:
	px = clampi(px, 0, splat_res - 1); pz = clampi(pz, 0, splat_res - 1)
	var a := splat[0].get_pixel(px, pz)
	var b := splat[1].get_pixel(px, pz)
	return PackedFloat32Array([a.r, a.g, a.b, a.a, b.r, b.g, b.b, b.a])

func set_weights(px: int, pz: int, w: PackedFloat32Array) -> void:
	splat[0].set_pixel(px, pz, Color(w[0], w[1], w[2], w[3]))
	splat[1].set_pixel(px, pz, Color(w[4], w[5], w[6], w[7]))

func dominant_layer(x: float, z: float) -> int:
	var p := splat_px(x, z)
	var w := get_weights(int(p.x), int(p.y))
	var best := 0
	for i in LAYERS:
		if w[i] > w[best]: best = i
	return best

# ------------------------------------------------------------------ objects
func _ogrid(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / GRID_CELL), floori(p.z / GRID_CELL))

func obj_chunk(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / OBJ_CHUNK), floori(p.z / OBJ_CHUNK))

func _chunk_inc(k: Vector2i) -> void:
	obj_chunks[k] = int(obj_chunks.get(k, 0)) + 1

func _chunk_dec(k: Vector2i) -> void:
	var n := int(obj_chunks.get(k, 0)) - 1
	if n <= 0: obj_chunks.erase(k)
	else: obj_chunks[k] = n

func add_object(o: MapObject) -> void:
	objects.append(o)
	var k := _ogrid(o.xf.origin)
	if not obj_grid.has(k): obj_grid[k] = []
	obj_grid[k].append(o)
	_chunk_inc(obj_chunk(o.xf.origin))

func remove_object(o: MapObject) -> void:
	var i := objects.find(o)
	if i >= 0:
		objects[i] = objects[objects.size() - 1]
		objects.pop_back()
		_chunk_dec(obj_chunk(o.xf.origin))
	var k := _ogrid(o.xf.origin)
	if obj_grid.has(k):
		obj_grid[k].erase(o)

func move_object(o: MapObject, new_xf: Transform3D) -> void:
	var k0 := _ogrid(o.xf.origin)
	var k1 := _ogrid(new_xf.origin)
	var c0 := obj_chunk(o.xf.origin)
	var c1 := obj_chunk(new_xf.origin)
	o.xf = new_xf
	if k0 != k1:
		if obj_grid.has(k0): obj_grid[k0].erase(o)
		if not obj_grid.has(k1): obj_grid[k1] = []
		obj_grid[k1].append(o)
	if c0 != c1:
		_chunk_dec(c0); _chunk_inc(c1)

func query_objects(center: Vector3, radius: float) -> Array:
	var out: Array = []
	var r2 := radius * radius
	var k0 := _ogrid(center - Vector3(radius, 0, radius))
	var k1 := _ogrid(center + Vector3(radius, 0, radius))
	for gz in range(k0.y, k1.y + 1):
		for gx in range(k0.x, k1.x + 1):
			var arr = obj_grid.get(Vector2i(gx, gz))
			if arr == null: continue
			for o in arr:
				var d: Vector3 = o.xf.origin - center
				if d.x * d.x + d.z * d.z <= r2:
					out.append(o)
	return out

func nearest_object_dist(p: Vector3, radius: float) -> float:
	var best := radius
	for o in query_objects(p, radius):
		var d := Vector2(o.xf.origin.x - p.x, o.xf.origin.z - p.z).length()
		best = minf(best, d)
	return best

# ------------------------------------------------------------------ generators
## Fills the ACTIVE tiles with terrain: flat / hills / mountains / island.
func generate(style: String, seed_v: int = 1, amp: float = 30.0) -> void:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 5
	n.frequency = 0.004
	var bb := active_bounds()
	var ctr := bb.get_center()
	var rad := maxf(bb.size.x, bb.size.y) * 0.5
	for iz in verts:
		for ix in verts:
			if not vert_active(ix, iz): continue
			var w := grid_to_world(ix, iz)
			var h := 0.0
			match style:
				"flat": h = 0.0
				"hills": h = n.get_noise_2d(w.x, w.y) * amp * 0.5
				"mountains": h = (absf(n.get_noise_2d(w.x, w.y)) * 2.0 - 0.15) * amp * 1.6
				"island":
					var d := Vector2(w.x - ctr.x, w.y - ctr.y).length() / rad
					var fall := 1.0 - smoothstep(0.35, 0.95, d)
					h = (n.get_noise_2d(w.x, w.y) * amp * 0.35 + amp * 0.35) * fall - (1.0 - fall) * amp * 0.5 - 1.0
			heights[iz * verts + ix] = h
	changed_region.emit(Rect2i(0, 0, cells, cells))

# ------------------------------------------------------------------ serialization
func to_dict() -> Dictionary:
	var pos := PackedFloat32Array()
	var ids := PackedStringArray()
	for o: MapObject in objects:
		var b := o.xf.basis
		pos.append_array([b.x.x, b.x.y, b.x.z, b.y.x, b.y.y, b.y.z, b.z.x, b.z.y, b.z.z, o.xf.origin.x, o.xf.origin.y, o.xf.origin.z])
		ids.append(o.asset)
	var tl := PackedInt32Array()
	for t in tiles: tl.append_array([t.x, t.y])
	return {
		"v": 3, "name": map_name, "t_count": t_count, "tiles": tl,
		"heights": heights, "splat0": splat[0].get_data(), "splat1": splat[1].get_data(),
		"layer_mats": layer_mats, "obj_xf": pos, "obj_ids": ids,
		"waters": waters.duplicate(true), "paths": paths.duplicate(true), "sky": sky_preset,
	}

func from_dict(d: Dictionary) -> void:
	_alloc(int(d["t_count"]))
	map_name = d.get("name", "Untitled")
	tiles.clear()
	var tl: PackedInt32Array = d["tiles"]
	for i in range(0, tl.size(), 2): tiles[Vector2i(tl[i], tl[i + 1])] = true
	if tiles.is_empty(): tiles[Vector2i.ZERO] = true
	_rebuild_mask()
	heights = d["heights"]
	splat[0] = Image.create_from_data(splat_res, splat_res, false, Image.FORMAT_RGBA8, d["splat0"])
	splat[1] = Image.create_from_data(splat_res, splat_res, false, Image.FORMAT_RGBA8, d["splat1"])
	layer_mats = d["layer_mats"]
	objects.clear(); obj_grid.clear(); obj_chunks.clear()
	var pos: PackedFloat32Array = d["obj_xf"]
	var ids: PackedStringArray = d["obj_ids"]
	for i in ids.size():
		var k := i * 12
		var b := Basis(Vector3(pos[k], pos[k + 1], pos[k + 2]), Vector3(pos[k + 3], pos[k + 4], pos[k + 5]), Vector3(pos[k + 6], pos[k + 7], pos[k + 8]))
		add_object(MapObject.make(ids[i], Transform3D(b, Vector3(pos[k + 9], pos[k + 10], pos[k + 11]))))
	waters = d["waters"]
	paths = d["paths"]
	sky_preset = d.get("sky", "day")

func save_to(path: String) -> bool:
	var f := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if f == null: return false
	f.store_var(to_dict())
	f.close()
	return true

static func load_from(path: String) -> MapData:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if f == null: return null
	var d = f.get_var()
	f.close()
	if typeof(d) != TYPE_DICTIONARY or not d.has("t_count"): return null
	var m := MapData.new(1)
	m.from_dict(d)
	return m
