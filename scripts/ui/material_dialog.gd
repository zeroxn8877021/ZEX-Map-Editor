# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : material_dialog.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name MaterialDialog
extends Control
## Pick / create / edit terrain materials for a splat slot (or any material choice).
signal chosen(id: String)
var ed: MapEditor
var current := ""
var _grid: GridContainer
var _edit_box: VBoxContainer
var _tile := {"v": 6.0}
var _tint_btn: ColorPickerButton

static func open(parent: Node, editor: MapEditor, cur: String, cb: Callable) -> MaterialDialog:
	var d := MaterialDialog.new()
	d.ed = editor; d.current = cur
	d.chosen.connect(cb)
	parent.add_child(d)
	return d

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var pc := PanelContainer.new()
	pc.position = Vector2(110, 40); pc.custom_minimum_size = Vector2(1060, 640)
	pc.add_theme_stylebox_override("panel", UIKit.box(UIKit.BG2, 16))
	add_child(pc)
	var h := HBoxContainer.new(); pc.add_child(h)
	var left := VBoxContainer.new(); left.size_flags_horizontal = Control.SIZE_EXPAND_FILL; h.add_child(left)
	left.add_child(UIKit.header("TERRAIN MATERIALS  -  tap one to use it"))
	var sc := ScrollContainer.new(); sc.size_flags_vertical = Control.SIZE_EXPAND_FILL; sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sc)
	_grid = GridContainer.new(); _grid.columns = 4; sc.add_child(_grid)
	_grid.add_theme_constant_override("h_separation", 8); _grid.add_theme_constant_override("v_separation", 8)
	var r := VBoxContainer.new(); r.custom_minimum_size = Vector2(320, 0); h.add_child(r)
	r.add_child(UIKit.header("CREATE"))
	r.add_child(UIKit.btn("New from image file...", _from_image))
	r.add_child(UIKit.btn("New from colour (procedural)", _from_color))
	r.add_child(UIKit.hint("Tip: import textures from Downloads - they are copied into the app so they stay after restart."))
	_edit_box = VBoxContainer.new(); r.add_child(_edit_box)
	var sp := Control.new(); sp.size_flags_vertical = Control.SIZE_EXPAND_FILL; r.add_child(sp)
	r.add_child(UIKit.btn("Close", queue_free, false, 54))
	_fill()

func _fill() -> void:
	for c in _grid.get_children(): c.queue_free()
	for id in ed.matlib.order:
		var m: Dictionary = ed.matlib.mats[id]
		var b := Button.new()
		b.icon = ed.matlib.thumb(id)
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.text = m["name"]
		b.add_theme_font_size_override("font_size", 14)
		b.clip_text = true
		b.custom_minimum_size = Vector2(124, 132)
		b.toggle_mode = true
		b.button_pressed = (id == current)
		b.focus_mode = Control.FOCUS_NONE
		var mid: String = id
		b.pressed.connect(func():
			current = mid
			chosen.emit(mid)
			_fill()
			_show_edit())
		_grid.add_child(b)
	_show_edit()

func _show_edit() -> void:
	for c in _edit_box.get_children(): c.queue_free()
	if not ed.matlib.mats.has(current): return
	var m: Dictionary = ed.matlib.mats[current]
	_edit_box.add_child(UIKit.header("EDIT: " + m["name"]))
	_tile["v"] = m["tile"]
	_edit_box.add_child(UIKit.slider("Tile size (m per repeat)", _tile, "v", 1.0, 30.0, 0.5, func(x): _apply_edit()))
	var row := HBoxContainer.new(); _edit_box.add_child(row)
	var l := Label.new(); l.text = "Tint"; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(l)
	_tint_btn = ColorPickerButton.new(); _tint_btn.color = m["tint"]; _tint_btn.custom_minimum_size = Vector2(120, 44)
	_tint_btn.popup_closed.connect(_apply_edit)
	row.add_child(_tint_btn)
	if not m["builtin"]:
		_edit_box.add_child(UIKit.btn("Delete material", func():
			ed.matlib.delete_material(current)
			current = "grass"
			_fill(), false, 46))

func _apply_edit() -> void:
	if not ed.matlib.mats.has(current): return
	ed.matlib.update_material(current, _tile["v"], _tint_btn.color if _tint_btn else Color.WHITE)
	chosen.emit(current)

func _from_image() -> void:
	FileBrowser.open(self, "Pick a texture image", ["png", "jpg", "jpeg", "webp"], false, func(paths):
		var p: String = paths[0]
		var id: String = ed.matlib.create_from_image(p, p.get_file().get_basename(), 6.0)
		if id == "": ed.toast("Could not read that image"); return
		current = id
		_fill()
		chosen.emit(id))

var _color_pop: Control
func _from_color() -> void:
	var pop := PanelContainer.new()
	pop.position = Vector2(420, 120)
	pop.add_theme_stylebox_override("panel", UIKit.box(Color(0.1, 0.11, 0.14), 14))
	var v := VBoxContainer.new(); pop.add_child(v)
	var cp := ColorPicker.new(); cp.color = Color(0.4, 0.35, 0.25); cp.edit_alpha = false
	v.add_child(cp)
	var row := HBoxContainer.new(); v.add_child(row)
	row.add_child(UIKit.btn("Cancel", pop.queue_free))
	row.add_child(UIKit.btn("Create", func():
		var id: String = ed.matlib.create_from_color("Custom colour", cp.color, 6.0)
		current = id
		pop.queue_free()
		_fill()
		chosen.emit(id)))
	add_child(pop)
