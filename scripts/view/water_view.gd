# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : water_view.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name WaterView
extends Node3D
## Builds the water meshes. Lake / ocean meshes are derived from the heightmap (flood-fill from the tapped seed point), so
## shorelines, depth colour and foam follow the terrain automatically; plane water is a fixed-depth pool / pond.
var data: MapData
var _nodes: Array = []
var max_wet_frac := 0.45     # basin overflow guard (fraction of map vertices)
var overflow := false

func setup(d: MapData) -> void:
	data = d
	rebuild_all()

func rebuild_all() -> void:
	for n in _nodes: n.free()
	_nodes.clear()
	for w in data.waters:
		var mi := build_one(w)
		if mi != null:
			add_child(mi)
			_nodes.append(mi)

func build_one(w: Dictionary) -> MeshInstance3D:
	var mesh: ArrayMesh
	match w["kind"]:
		"lake": mesh = _lake_mesh(w, false)
		"ocean": mesh = _lake_mesh(w, true)
		"plane": mesh = _plane_mesh(w)
	if mesh == null: return null
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = WaterPresets.make_material(w.get("preset", "gta"))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _lake_mesh(w: Dictionary, everywhere: bool) -> ArrayMesh:
	var L: float = w["level"]
	var n := data.verts
	var wet := PackedByteArray(); wet.resize(n * n)
	if everywhere:
		for i in n * n:
			if data.heights[i] < L: wet[i] = 1
	else:
		var seed_p := Vector2(w["seed"][0], w["seed"][1])
		var g := data.world_to_grid(seed_p.x, seed_p.y)
		var sx := clampi(roundi(g.x), 0, n - 1); var sz := clampi(roundi(g.y), 0, n - 1)
		if data.heights[sz * n + sx] >= L:
			# seed on dry ground -> search the nearest wet vertex within 4 cells
			var found := false
			for r in range(1, 5):
				for dz in range(-r, r + 1):
					for dx in range(-r, r + 1):
						var xx := sx + dx; var zz := sz + dz
						if xx >= 0 and zz >= 0 and xx < n and zz < n and data.heights[zz * n + xx] < L:
							sx = xx; sz = zz; found = true; break
					if found: break
				if found: break
			if not found: return null
		var stack := PackedInt32Array([sz * n + sx])
		wet[sz * n + sx] = 1
		var wet_count := 1
		var cap := int(n * n * max_wet_frac)
		overflow = false
		while stack.size() > 0:
			var cur := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			var cx := cur % n; var cz := cur / n
			for off in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var nx: int = cx + off[0]; var nz: int = cz + off[1]
				if nx < 0 or nz < 0 or nx >= n or nz >= n: continue
				var ni := nz * n + nx
				if wet[ni] == 0 and data.heights[ni] < L:
					wet[ni] = 1
					wet_count += 1
					stack.append(ni)
			if wet_count > cap:
				overflow = true
				return null
	var verts := PackedVector3Array(); var cols := PackedColorArray(); var uvs := PackedVector2Array(); var idxs := PackedInt32Array()
	var vmap: Dictionary = {}
	var half := data.size * 0.5
	for iz in data.cells:
		for ix in data.cells:
			var i00 := iz * n + ix
			if wet[i00] + wet[i00 + 1] + wet[i00 + n] + wet[i00 + n + 1] == 0: continue
			var q: Array = []
			for off in [[0, 0], [1, 0], [0, 1], [1, 1]]:
				var vx: int = ix + off[0]; var vz: int = iz + off[1]
				var key := vz * n + vx
				if not vmap.has(key):
					vmap[key] = verts.size()
					verts.append(Vector3(vx * data.cell - half, L, vz * data.cell - half))
					var depth := maxf(0.0, L - data.heights[key]) if wet[key] == 1 else 0.0
					cols.append(Color(clampf(depth / 4.0, 0.0, 1.0), 0, 0, 1))
					uvs.append(Vector2(vx, vz))
				q.append(vmap[key])
			idxs.append_array([q[0], q[1], q[2], q[1], q[3], q[2]])
	if everywhere:
		# skirt beyond the map so the sea reaches the horizon
		var far := data.size * 1.6
		var d := 1.0
		var corners := [Vector2(-far, -far), Vector2(far, -far), Vector2(far, far), Vector2(-far, far)]
		var inner := [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]
		for e in 4:
			var o0: Vector2 = corners[e]; var o1: Vector2 = corners[(e + 1) % 4]
			var i0: Vector2 = inner[e]; var i1: Vector2 = inner[(e + 1) % 4]
			var base := verts.size()
			for p in [o0, o1, i1, i0]:
				verts.append(Vector3(p.x, L, p.y)); cols.append(Color(d, 0, 0, 1)); uvs.append(p)
			idxs.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	if verts.is_empty(): return null
	return _finish(verts, cols, uvs, idxs)

func _plane_mesh(w: Dictionary) -> ArrayMesh:
	var c := Vector2(w["center"][0], w["center"][1])
	var sz := Vector2(w["size"][0], w["size"][1])
	var L: float = w["level"]
	var depth: float = w.get("depth", 3.0)
	var seg := 20
	var yaw: float = w.get("yaw", 0.0)
	var verts := PackedVector3Array(); var cols := PackedColorArray(); var uvs := PackedVector2Array(); var idxs := PackedInt32Array()
	for z in seg + 1:
		for x in seg + 1:
			var u := float(x) / seg - 0.5
			var v := float(z) / seg - 0.5
			var lp := Vector2(u * sz.x, v * sz.y).rotated(yaw)
			verts.append(Vector3(c.x + lp.x, L, c.y + lp.y))
			var edge := minf(minf(u + 0.5, 0.5 - u), minf(v + 0.5, 0.5 - v)) * 2.0
			cols.append(Color(clampf(depth / 4.0 * smoothstep(0.0, 0.18, edge), 0.0, 1.0), 0, 0, 1))
			uvs.append(Vector2(u, v))
	for z in seg:
		for x in seg:
			var a := z * (seg + 1) + x
			idxs.append_array([a, a + 1, a + seg + 1, a + 1, a + seg + 2, a + seg + 1])
	return _finish(verts, cols, uvs, idxs)

func _finish(verts: PackedVector3Array, cols: PackedColorArray, uvs: PackedVector2Array, idxs: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idxs
	var normals := PackedVector3Array(); normals.resize(verts.size()); normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
