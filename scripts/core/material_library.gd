# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : material_library.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name MaterialLibrary
extends RefCounted
## Terrain / ribbon materials (albedo tile + tint + tiling size). Built-ins ship in res://assets/tex, user materials are
## stored in user://materials (image copied there + materials.json) so they survive app restarts on Android.

const TEX_SIZE := 512
const USER_DIR := "user://materials"
const BUILTIN := [
	{"id": "proto", "name": "Prototype grid", "path": "res://assets/tex/proto.png", "tile": 4.0},
	{"id": "grass", "name": "Grass", "path": "res://assets/tex/grass.png", "tile": 7.0},
	{"id": "dirt", "name": "Forest dirt", "path": "res://assets/tex/dirt.png", "tile": 6.0},
	{"id": "rock", "name": "Rock", "path": "res://assets/tex/rock.png", "tile": 9.0},
	{"id": "sand", "name": "Sand", "path": "res://assets/tex/sand.png", "tile": 6.0},
	{"id": "snow", "name": "Snow", "path": "res://assets/tex/snow.png", "tile": 8.0},
	{"id": "gravel", "name": "Gravel", "path": "res://assets/tex/gravel.png", "tile": 4.0},
	{"id": "mud", "name": "Mud", "path": "res://assets/tex/mud.png", "tile": 5.0},
	{"id": "road", "name": "Asphalt", "path": "res://assets/tex/asphalt.png", "tile": 5.0},
	{"id": "cobble", "name": "Cobble road", "path": "res://assets/tex/road.png", "tile": 5.0},
	{"id": "ballast", "name": "Rail ballast", "path": "res://assets/tex/ballast.png", "tile": 3.0},
	{"id": "dry_earth", "name": "Dry earth", "path": "res://assets/tex/dry_earth.png", "tile": 6.0},
]

var mats: Dictionary = {}            # id -> {id,name,path,tile,tint:Color,builtin:bool}
var order: Array = []                # ids in display order
var _img_cache: Dictionary = {}      # id -> Image (RGB8 512)
var _thumb_cache: Dictionary = {}

func _init() -> void:
	for b in BUILTIN:
		var m: Dictionary = b.duplicate()
		m["tint"] = Color(0.74, 0.80, 0.64) if m["id"] == "grass" else Color.WHITE
		m["builtin"] = true
		mats[m["id"]] = m
		order.append(m["id"])
	_load_user()

func _load_user() -> void:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	var f := FileAccess.open(USER_DIR + "/materials.json", FileAccess.READ)
	if f == null: return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(data) != TYPE_ARRAY: return
	for d in data:
		var m := {"id": d["id"], "name": d["name"], "path": d["path"], "tile": float(d["tile"]),
			"tint": Color.html(d.get("tint", "ffffff")), "builtin": false}
		if FileAccess.file_exists(m["path"]):
			mats[m["id"]] = m
			order.append(m["id"])

func _save_user() -> void:
	var arr: Array = []
	for id in order:
		var m: Dictionary = mats[id]
		if m["builtin"]: continue
		arr.append({"id": id, "name": m["name"], "path": m["path"], "tile": m["tile"], "tint": m["tint"].to_html(false)})
	var f := FileAccess.open(USER_DIR + "/materials.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(arr))
		f.close()

## Creates a custom material from any image file (copied into user://materials). Returns the new id or "" on failure.
func create_from_image(src_path: String, mat_name: String, tile: float = 6.0, tint: Color = Color.WHITE) -> String:
	var img := Image.load_from_file(src_path)
	if img == null or img.is_empty():
		return ""
	var id := "u_%d" % (Time.get_ticks_usec() % 100000000)
	img.convert(Image.FORMAT_RGB8)
	var dst := "%s/%s.png" % [USER_DIR, id]
	img.save_png(dst)
	mats[id] = {"id": id, "name": mat_name, "path": dst, "tile": tile, "tint": tint, "builtin": false}
	order.append(id)
	_save_user()
	return id

func create_from_color(mat_name: String, base: Color, tile: float = 6.0, noise: float = 0.25) -> String:
	## Procedural tileable material from a colour (no source image needed).
	var n := FastNoiseLite.new()
	n.seed = randi()
	n.frequency = 0.02
	var img := n.get_seamless_image(256, 256, false, false, 0.2)
	var out := Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		for x in 256:
			var v := img.get_pixel(x, y).r
			var k := 1.0 + (v - 0.5) * noise * 2.0
			out.set_pixel(x, y, Color(base.r * k, base.g * k, base.b * k))
	var id := "u_%d" % (Time.get_ticks_usec() % 100000000)
	var dst := "%s/%s.png" % [USER_DIR, id]
	out.save_png(dst)
	mats[id] = {"id": id, "name": mat_name, "path": dst, "tile": tile, "tint": Color.WHITE, "builtin": false}
	order.append(id)
	_save_user()
	return id

func update_material(id: String, tile: float, tint: Color, new_name: String = "") -> void:
	if not mats.has(id): return
	mats[id]["tile"] = tile
	mats[id]["tint"] = tint
	if new_name != "": mats[id]["name"] = new_name
	_save_user()

func delete_material(id: String) -> void:
	if not mats.has(id) or mats[id]["builtin"]: return
	DirAccess.remove_absolute(mats[id]["path"])
	mats.erase(id)
	order.erase(id)
	_img_cache.erase(id)
	_save_user()

func get_image(id: String) -> Image:
	if _img_cache.has(id): return _img_cache[id]
	var m: Dictionary = mats.get(id, mats["grass"])
	var img: Image = load(m["path"]).get_image() if m["path"].begins_with("res://") else Image.load_from_file(m["path"])
	if img.is_compressed(): img.decompress()
	img.convert(Image.FORMAT_RGB8)
	while img.get_width() >= TEX_SIZE * 4 or img.get_height() >= TEX_SIZE * 4:
		img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)   # cheap pre-shrink of big photos
	if img.get_width() != TEX_SIZE or img.get_height() != TEX_SIZE:
		img.resize(TEX_SIZE, TEX_SIZE, Image.INTERPOLATE_CUBIC)
	_img_cache[id] = img
	return img

func thumb(id: String) -> Texture2D:
	if _thumb_cache.has(id): return _thumb_cache[id]
	var im: Image = get_image(id).duplicate()
	im.resize(96, 96, Image.INTERPOLATE_BILINEAR)
	var t := ImageTexture.create_from_image(im)
	_thumb_cache[id] = t
	return t

func tile_of(id: String) -> float:
	return float(mats.get(id, mats["grass"])["tile"])

## Texture2DArray for the 8 terrain slots.
func build_array(slot_ids: PackedStringArray) -> Texture2DArray:
	var imgs: Array[Image] = []
	for id in slot_ids:
		var im: Image = get_image(id).duplicate()
		im.generate_mipmaps()
		imgs.append(im)
	var arr := Texture2DArray.new()
	arr.create_from_images(imgs)
	return arr

## Replaces one layer of an existing Texture2DArray in place (no full rebuild).
func update_array_layer(arr: Texture2DArray, layer: int, id: String) -> void:
	var im: Image = get_image(id).duplicate()
	im.generate_mipmaps()
	arr.update_layer(im, layer)

func texture_for(id: String) -> Texture2D:
	var im: Image = get_image(id).duplicate()
	im.generate_mipmaps()
	return ImageTexture.create_from_image(im)
