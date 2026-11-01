# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : path_view.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name PathView
extends Node3D
## Renders every path in MapData.paths: roads (ribbon), rails (ballast + sleepers + two rails), rivers (flowing water ribbon),
## and "object lines" (any library asset repeated along the curve: fences, walls, power poles, custom rails ...).
var data: MapData
var assets: AssetLibrary
var matlib: MaterialLibrary
var _nodes: Dictionary = {}     # path index -> Node3D
var view_distance := 0.0
const SLEEPER_STEP := 0.72

func setup(d: MapData, a: AssetLibrary, ml: MaterialLibrary) -> void:
	data = d; assets = a; matlib = ml
	rebuild_all()

func rebuild_all() -> void:
	for k in _nodes.keys(): _nodes[k].free()
	_nodes.clear()
	for i in data.paths.size(): rebuild(i)

func rebuild(i: int) -> void:
	if _nodes.has(i):
		_nodes[i].free(); _nodes.erase(i)
	if i >= data.paths.size(): return
	var p: Dictionary = data.paths[i]
	var holder := build_node(p)
	if holder != null:
		add_child(holder)
		_nodes[i] = holder

func build_node(p: Dictionary) -> Node3D:
	var pts: PackedVector3Array = p["points"]
	if pts.size() < 2: return null
	var holder := Node3D.new()
	holder.name = "path"
	var s := PathGeo.sample(pts, p.get("closed", false), 1.0 if p["type"] != "fence" else maxf(float(p.get("spacing", 3.0)) * 0.5, 0.5))
	match p["type"]:
		"road": _build_road(holder, p, s)
		"rail": _build_rail(holder, p, s)
		"river": _build_river(holder, p, s)
		"line": _build_line(holder, p, s)
	return holder

func _ribbon_mat(mat_id: String, tint: Color = Color.WHITE) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/ribbon.gdshader")
	m.set_shader_parameter("tex", matlib.texture_for(mat_id))
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	return m

func _add_mesh(holder: Node3D, mesh: Mesh, mat: Material, shadow := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	holder.add_child(mi)
	return mi

func _build_road(holder: Node3D, p: Dictionary, s: Dictionary) -> void:
	var w: float = p.get("width", 6.0)
	var mat_id: String = p.get("mat", "road")
	var uv_len := matlib.tile_of(mat_id) * 2.0
	var mesh := PathGeo.ribbon(s, w * 0.5 + 0.35, data, 0.06, uv_len, PackedFloat32Array(), 6)
	if mesh: _add_mesh(holder, mesh, _ribbon_mat(mat_id))

func _build_rail(holder: Node3D, p: Dictionary, s: Dictionary) -> void:
	var gauge := 1.435
	var bed_w: float = p.get("width", 4.2)
	var bed := PathGeo.ribbon(s, bed_w * 0.5, data, 0.05, matlib.tile_of("ballast") * 2.0, PackedFloat32Array(), 4)
	if bed: _add_mesh(holder, bed, _ribbon_mat("ballast"))
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.45, 0.45, 0.47); steel.metallic = 0.7; steel.roughness = 0.4
	for side in [-1.0, 1.0]:
		var r := PathGeo.beam(s, data, side * gauge * 0.5, 0.07, 0.16, 0.22)
		if r: _add_mesh(holder, r, steel)
	# sleepers: one MultiMesh of dark wood boxes
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.22, 0.15, 0.10); wood.roughness = 0.9
	var box := BoxMesh.new(); box.size = Vector3(2.6, 0.14, 0.26)
	box.material = wood
	var pos: PackedVector3Array = s["pos"]; var tan: PackedVector3Array = s["tan"]
	var tf: Array = []
	var acc := 0.0
	for i in pos.size() - 1:
		var seg := pos[i + 1].distance_to(pos[i])
		acc += seg
		while acc >= SLEEPER_STEP:
			acc -= SLEEPER_STEP
			var f := 1.0 - acc / maxf(seg, 0.001)
			var c := pos[i].lerp(pos[i + 1], f)
			var yaw := atan2(-tan[i].x, -tan[i].z)
			tf.append(Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, data.height_at(c.x, c.z) + 0.16, c.z)))
	if tf.is_empty(): return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = tf.size()
	for i in tf.size(): mm.set_instance_transform(i, tf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = view_distance
	holder.add_child(mmi)

func _build_river(holder: Node3D, p: Dictionary, s: Dictionary) -> void:
	var w: float = p.get("width", 12.0)
	var depth: float = p.get("depth", 1.8)
	var lv := PathGeo.river_levels(s, data, depth)
	if p.has("levels") and (p["levels"] as PackedFloat32Array).size() == (s["pos"] as PackedVector3Array).size():
		lv = p["levels"]
	var mesh := PathGeo.ribbon(s, w * 0.5, data, 0.0, 10.0, lv, 6, depth + 0.6)
	if mesh == null: return
	var m := WaterPresets.make_material(p.get("preset", "river"))
	_add_mesh(holder, mesh, m)

func _build_line(holder: Node3D, p: Dictionary, s: Dictionary) -> void:
	var aid: String = p.get("asset", "")
	var parts := assets.get_parts(aid) if aid != "" else []
	if parts.is_empty(): return
	var spacing: float = maxf(float(p.get("spacing", 3.0)), 0.2)
	var align: float = p.get("align", 0.0)
	var offset: float = p.get("offset", 0.0)
	var scale_v: float = p.get("scale", 1.0)
	var tf: Array = []
	for t in line_transforms(s, spacing, align, offset, scale_v):
		tf.append(t)
	if tf.is_empty(): return
	for part in parts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part["mesh"]
		mm.instance_count = tf.size()
		for i in tf.size(): mm.set_instance_transform(i, tf[i] * part["xf"])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = view_distance
		holder.add_child(mmi)

## Transforms of objects repeated along a sampled curve (shared with the exporter).
func line_transforms(s: Dictionary, spacing: float, align: float, offset: float, scale_v: float) -> Array:
	var out: Array = []
	var pos: PackedVector3Array = s["pos"]; var tan: PackedVector3Array = s["tan"]
	var acc := spacing * 0.5
	for i in pos.size() - 1:
		var seg := pos[i + 1].distance_to(pos[i])
		acc += seg
		while acc >= spacing:
			acc -= spacing
			var f := 1.0 - acc / maxf(seg, 0.001)
			var c := pos[i].lerp(pos[i + 1], f)
			var t := tan[i].lerp(tan[mini(i + 1, tan.size() - 1)], f).normalized()
			var right := Vector3(-t.z, 0, t.x)
			c += right * offset
			var n := data.normal_at(c.x, c.z).lerp(Vector3.UP, 1.0 - align).normalized()
			var z_axis := (-t - n * (-t).dot(n)).normalized()   # forward along path, perpendicular to n
			var x_axis := n.cross(z_axis).normalized()
			var b := Basis(x_axis, n, z_axis).scaled(Vector3.ONE * scale_v)
			out.append(Transform3D(b, Vector3(c.x, data.height_at(c.x, c.z), c.z)))
	return out
