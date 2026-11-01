# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : map_exporter.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name MapExporter
extends RefCounted
## Exports the finished map. GLB = terrain (splat blend BAKED into one albedo texture), water, roads/rails/rivers, all objects
## (shared meshes, so file size stays sane). "data" export writes heightmap / splat / objects.json for loading in another game.
var ed: MapEditor
var bake_res := 2048
var object_detail := 0.35      # fraction of triangles kept per object (1 = full)
var terrain_step := 1          # 1 = every height cell, 2 = every second ...

func export_dir() -> String:
	var dl := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	var d := (dl + "/ZEXMaps") if dl != "" else ProjectSettings.globalize_path("user://exports")
	if DirAccess.make_dir_recursive_absolute(d) != OK and not DirAccess.dir_exists_absolute(d):
		d = ProjectSettings.globalize_path("user://exports")
		DirAccess.make_dir_recursive_absolute(d)
	return d

# ------------------------------------------------------------------ GLB
func export_glb(out_path: String = "") -> String:
	var d: MapData = ed.data
	var root := Node3D.new()
	root.name = d.map_name.validate_node_name() if d.map_name != "" else "ZEXMap"
	# 1) terrain
	var tex := await _bake_albedo()
	var tmat := StandardMaterial3D.new()
	tmat.roughness = 1.0
	tmat.metallic_specular = 0.1
	if tex != null: tmat.albedo_texture = tex
	else: tmat.albedo_color = Color(0.35, 0.45, 0.25)
	var tmi := MeshInstance3D.new()
	tmi.name = "Terrain"
	tmi.mesh = _terrain_mesh(d)
	tmi.material_override = tmat
	root.add_child(tmi)
	# 2) water
	var wi := 0
	for w in d.waters:
		var mi: MeshInstance3D = ed.water.build_one(w)
		if mi == null: continue
		mi.name = "Water_%d" % wi; wi += 1
		mi.material_override = _std_water(w.get("preset", "gta"))
		root.add_child(mi)
	# 3) routes
	var pi := 0
	for p in d.paths:
		var holder: Node3D = ed.paths.build_node(p)
		if holder == null: continue
		holder.name = "Route_%d_%s" % [pi, p["type"]]; pi += 1
		_convert_node(holder)
		root.add_child(holder)
	# 4) objects
	var objs := Node3D.new(); objs.name = "Objects"
	root.add_child(objs)
	var n := 0
	for o: MapObject in d.objects:
		var parts: Array = ed.assets.get_parts(o.asset)
		for part in parts:
			var mi2 := MeshInstance3D.new()
			mi2.mesh = ed.assets.decimated(part["mesh"], object_detail)
			mi2.transform = o.xf * part["xf"]
			mi2.name = "%s_%d" % [o.asset, n]
			objs.add_child(mi2)
			n += 1
	var path := out_path
	if path == "":
		path = "%s/%s_%s.glb" % [export_dir(), d.map_name.validate_filename(), Time.get_datetime_string_from_system().replace(":", "-")]
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var err := doc.append_from_scene(root, st)
	if err == OK: err = doc.write_to_filesystem(st, path)
	root.free()
	if err != OK: return "GLB export failed (%d)" % err
	var f := FileAccess.open(path, FileAccess.READ)
	var mb := (f.get_length() / 1048576.0) if f else 0.0
	return "Exported %.1f MB: %s" % [mb, path]

func _terrain_mesh(d: MapData) -> ArrayMesh:
	var st := maxi(1, terrain_step)
	var n := d.cells / st + 1
	var verts := PackedVector3Array(); verts.resize(n * n)
	var norms := PackedVector3Array(); norms.resize(n * n)
	var uvs := PackedVector2Array(); uvs.resize(n * n)
	var half := d.size * 0.5
	for z in n:
		for x in n:
			var i := z * n + x
			var gx := x * st; var gz := z * st
			verts[i] = Vector3(gx * d.cell - half, d.h_cell(gx, gz), gz * d.cell - half)
			norms[i] = Vector3(d.h_cell(gx - st, gz) - d.h_cell(gx + st, gz), 2.0 * d.cell * st, d.h_cell(gx, gz - st) - d.h_cell(gx, gz + st)).normalized()
			uvs[i] = Vector2(float(gx) / d.cells, float(gz) / d.cells)
	var idx := PackedInt32Array()
	for z in n - 1:
		for x in n - 1:
			var a := z * n + x
			idx.append_array([a, a + 1, a + n, a + 1, a + n + 1, a + n])
	var arr := []; arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts; arr[Mesh.ARRAY_NORMAL] = norms; arr[Mesh.ARRAY_TEX_UV] = uvs; arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m

func _bake_albedo() -> Texture2D:
	if DisplayServer.get_name() == "headless": return null
	var d: MapData = ed.data
	var vp := SubViewport.new()
	vp.size = Vector2i(bake_res, bake_res)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.msaa_3d = Viewport.MSAA_DISABLED
	ed.add_child(vp)
	var code: String = (load("res://assets/shaders/terrain_splat.gdshader") as Shader).code
	var mat: ShaderMaterial = ed.terrain.make_bake_material(code.replace("render_mode diffuse_lambert, specular_disabled;", "render_mode unshaded;"))
	mat.set_shader_parameter("brush", Vector4(0, 0, 0, 0))
	mat.set_shader_parameter("grid_on", 0.0)
	var quad := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(d.size, d.size)
	quad.mesh = pm
	quad.material_override = mat
	vp.add_child(quad)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = d.size
	cam.near = 1.0; cam.far = 2000.0
	vp.add_child(cam)
	cam.position = Vector3(0, 800, 0)
	cam.look_at(Vector3.ZERO, Vector3(0, 0, -1))
	cam.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty(): return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _std_water(preset: String) -> StandardMaterial3D:
	var p: Dictionary = WaterPresets.PRESETS.get(preset, WaterPresets.PRESETS["gta"])
	var m := StandardMaterial3D.new()
	var c: Color = (p["shallow"] as Color).lerp(p["mid"], 0.5)
	m.albedo_color = Color(c.r, c.g, c.b, 0.78)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic_specular = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

## Replaces shader materials by glTF-friendly ones and expands MultiMeshes into plain meshes.
func _convert_node(n: Node) -> void:
	for c in n.get_children():
		_convert_node(c)
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var sm = mi.material_override
		if sm is ShaderMaterial:
			if sm.get_shader_parameter("shallow_col") != null:
				mi.material_override = _std_water("river")
			else:
				var std := StandardMaterial3D.new()
				std.albedo_texture = sm.get_shader_parameter("tex")
				var t = sm.get_shader_parameter("tint")
				if t is Vector3: std.albedo_color = Color(t.x, t.y, t.z)
				std.roughness = 0.95
				std.cull_mode = BaseMaterial3D.CULL_DISABLED
				mi.material_override = std
	elif n is MultiMeshInstance3D:
		var mmi := n as MultiMeshInstance3D
		var mm := mmi.multimesh
		var parent := n.get_parent()
		for i in mm.instance_count:
			var mi2 := MeshInstance3D.new()
			mi2.mesh = mm.mesh
			mi2.transform = mm.get_instance_transform(i)
			parent.add_child(mi2)
		n.queue_free()
		parent.remove_child(n)
		n.free()

# ------------------------------------------------------------------ data export (heightmap / splat / json)
func export_data() -> String:
	var d: MapData = ed.data
	var dir := "%s/%s_data" % [export_dir(), d.map_name.validate_filename()]
	DirAccess.make_dir_recursive_absolute(dir)
	# heightmap as little-endian uint16 (r16) + preview png
	var mn := 1e9; var mx := -1e9
	for h in d.heights:
		mn = minf(mn, h); mx = maxf(mx, h)
	var rng := maxf(mx - mn, 0.001)
	var buf := PackedByteArray(); buf.resize(d.heights.size() * 2)
	var prev := Image.create(d.verts, d.verts, false, Image.FORMAT_L8)
	for i in d.heights.size():
		var t := (d.heights[i] - mn) / rng
		buf.encode_u16(i * 2, int(clampf(t, 0.0, 1.0) * 65535.0))
		prev.set_pixel(i % d.verts, i / d.verts, Color(t, t, t))
	var f := FileAccess.open(dir + "/heightmap.r16", FileAccess.WRITE)
	if f == null: return "Could not write to " + dir
	f.store_buffer(buf); f.close()
	prev.save_png(dir + "/heightmap_preview.png")
	d.splat[0].save_png(dir + "/splat_0.png")
	d.splat[1].save_png(dir + "/splat_1.png")
	var layers: Array = []
	for i in MapData.LAYERS:
		var id: String = d.layer_mats[i]
		layers.append({"slot": i, "material": id, "name": ed.matlib.mats[id]["name"], "tile_m": ed.matlib.tile_of(id)})
		ed.matlib.get_image(id).save_png("%s/layer_%d_%s.png" % [dir, i, id])
	var objs: Array = []
	var used: Dictionary = {}
	for o: MapObject in d.objects:
		var q := o.xf.basis.get_rotation_quaternion()
		var s := o.xf.basis.get_scale()
		objs.append({"asset": o.asset, "pos": [snapped(o.xf.origin.x, 0.001), snapped(o.xf.origin.y, 0.001), snapped(o.xf.origin.z, 0.001)],
			"quat": [q.x, q.y, q.z, q.w], "scale": [s.x, s.y, s.z]})
		used[o.asset] = true
	for aid in used:
		if ed.assets.entries.has(aid):
			var src: String = ed.assets.entries[aid]["path"]
			if src.begins_with("user://"): src = ProjectSettings.globalize_path(src)
			DirAccess.make_dir_recursive_absolute(dir + "/assets")
			DirAccess.copy_absolute(src, dir + "/assets/" + src.get_file())
	var meta := {"name": d.map_name, "size_m": d.size, "cells": d.cells, "cell_m": d.cell, "height_min": mn, "height_max": mx,
		"heightmap": "heightmap.r16 (uint16 LE, %d x %d, height = min + v/65535*(max-min))" % [d.verts, d.verts],
		"layers": layers, "objects": objs, "waters": d.waters, "routes": d.paths.map(func(p): return {"type": p["type"], "name": p["name"], "width": p.get("width", 0), "closed": p.get("closed", false), "points": (p["points"] as PackedVector3Array).to_byte_array().size() / 12}),
		"route_points": d.paths.map(func(p): return Array(p["points"]).map(func(v): return [v.x, v.y, v.z]))}
	var jf := FileAccess.open(dir + "/map.json", FileAccess.WRITE)
	jf.store_string(JSON.stringify(meta, "  ")); jf.close()
	return "Data exported: " + dir
