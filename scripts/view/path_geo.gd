# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : path_geo.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name PathGeo
extends RefCounted
## Spline helpers + ribbon mesh builders shared by roads, rails and rivers.

## Smooth Catmull-Rom style curve through the control points, evenly resampled.
static func sample(points: PackedVector3Array, closed: bool, step: float) -> Dictionary:
	var out_p := PackedVector3Array(); var out_t := PackedVector3Array()
	var n := points.size()
	if n < 2: return {"pos": out_p, "tan": out_t, "len": 0.0}
	var c := Curve3D.new()
	c.bake_interval = maxf(step * 0.5, 0.25)
	for i in n:
		var p := points[i]
		var prev := points[(i - 1 + n) % n] if (closed or i > 0) else p
		var nxt := points[(i + 1) % n] if (closed or i < n - 1) else p
		var tan := (nxt - prev) / 6.0
		if not closed and (i == 0 or i == n - 1):
			tan = ((points[1] - points[0]) if i == 0 else (points[n - 1] - points[n - 2])) / 3.0
		c.add_point(p, -tan, tan)
	if closed:
		c.add_point(points[0], -(points[1] - points[n - 1]) / 6.0, (points[1] - points[n - 1]) / 6.0)
	var length := c.get_baked_length()
	var cnt := maxi(2, int(length / step) + 1)
	for i in cnt:
		var off := minf(length, i * (length / (cnt - 1)))
		var p := c.sample_baked(off, true)
		out_p.append(p)
	for i in out_p.size():
		var a := out_p[maxi(i - 1, 0)]; var b := out_p[mini(i + 1, out_p.size() - 1)]
		var t := Vector3(b.x - a.x, 0, b.z - a.z)
		out_t.append(t.normalized() if t.length() > 0.0001 else Vector3(0, 0, 1))
	return {"pos": out_p, "tan": out_t, "len": length}

## Ribbon that hugs the terrain. y_mode: "terrain" (follow ground + y_off) or a PackedFloat32Array of per-sample levels.
static func ribbon(s: Dictionary, half_w: float, data: MapData, y_off: float, uv_len: float, levels: PackedFloat32Array = PackedFloat32Array(), lat_segs: int = 4, depth_profile: float = -1.0) -> ArrayMesh:
	var pos: PackedVector3Array = s["pos"]; var tan: PackedVector3Array = s["tan"]
	var n := pos.size()
	if n < 2: return null
	var verts := PackedVector3Array(); var uvs := PackedVector2Array(); var cols := PackedColorArray(); var idxs := PackedInt32Array()
	var dist := 0.0
	for i in n:
		if i > 0: dist += pos[i].distance_to(pos[i - 1])
		var right := Vector3(-tan[i].z, 0, tan[i].x)
		for j in lat_segs + 1:
			var u := float(j) / lat_segs
			var off := (u - 0.5) * 2.0 * half_w
			var p := pos[i] + right * off
			var y: float
			if levels.size() == n: y = levels[i]
			else: y = data.height_at(p.x, p.z) + y_off
			verts.append(Vector3(p.x, y, p.z))
			uvs.append(Vector2(u, dist / uv_len))
			if depth_profile >= 0.0:
				var e := 1.0 - absf(u - 0.5) * 2.0
				cols.append(Color(clampf(depth_profile / 4.0 * smoothstep(0.0, 0.6, e), 0, 1), 0, 0, 1))
	for i in n - 1:
		for j in lat_segs:
			var a := i * (lat_segs + 1) + j
			var b := a + 1
			var c := a + lat_segs + 1
			var d := c + 1
			idxs.append_array([a, c, b, b, c, d])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	if cols.size() == verts.size(): arrays[Mesh.ARRAY_COLOR] = cols
	var nr := PackedVector3Array(); nr.resize(verts.size()); nr.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = nr
	arrays[Mesh.ARRAY_INDEX] = idxs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

## Thin raised bar (rail head) along the path at lateral offset.
static func beam(s: Dictionary, data: MapData, lateral: float, w: float, h: float, y_base: float) -> ArrayMesh:
	var pos: PackedVector3Array = s["pos"]; var tan: PackedVector3Array = s["tan"]
	var n := pos.size()
	if n < 2: return null
	var verts := PackedVector3Array(); var norms := PackedVector3Array(); var idxs := PackedInt32Array()
	for i in n:
		var right := Vector3(-tan[i].z, 0, tan[i].x)
		var c := pos[i] + right * lateral
		var y := data.height_at(c.x, c.z) + y_base
		var l := c - right * w * 0.5; var r := c + right * w * 0.5
		verts.append(Vector3(l.x, y, l.z)); norms.append(Vector3.UP)
		verts.append(Vector3(r.x, y, r.z)); norms.append(Vector3.UP)
		verts.append(Vector3(l.x, y + h, l.z)); norms.append(Vector3.UP)
		verts.append(Vector3(r.x, y + h, r.z)); norms.append(Vector3.UP)
	for i in n - 1:
		var b := i * 4; var nb := b + 4
		# top, left side, right side
		idxs.append_array([b + 2, nb + 2, b + 3, b + 3, nb + 2, nb + 3])
		idxs.append_array([b, nb, b + 2, b + 2, nb, nb + 2])
		idxs.append_array([b + 3, nb + 3, b + 1, b + 1, nb + 3, nb + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idxs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m

## River level profile: follows the ground but never rises downstream (running minimum, lightly smoothed).
static func river_levels(s: Dictionary, data: MapData, depth: float) -> PackedFloat32Array:
	var pos: PackedVector3Array = s["pos"]
	var lv := PackedFloat32Array(); lv.resize(pos.size())
	var cur := 1e9
	for i in pos.size():
		cur = minf(cur, data.height_at(pos[i].x, pos[i].z) - depth * 0.35)
		lv[i] = cur
	return lv
