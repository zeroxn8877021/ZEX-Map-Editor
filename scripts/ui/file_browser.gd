# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : file_browser.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name FileBrowser
extends Control
## Touch-friendly file picker (works on desktop and Android storage). Multi-select, extension filter, quick shortcuts.
signal picked(paths: Array)
var exts: Array = []
var multi := true
var cur := ""
var sel: Dictionary = {}
var _list: VBoxContainer
var _path_edit: LineEdit
var _ok: Button
var _title := "Select files"

static func open(parent: Node, title: String, filter_exts: Array, allow_multi: bool, cb: Callable) -> FileBrowser:
	var fb := FileBrowser.new()
	fb.exts = filter_exts
	fb.multi = allow_multi
	fb._title = title
	fb.picked.connect(cb)
	parent.add_child(fb)
	return fb

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if OS.get_name() == "Android": OS.request_permissions()
	var dim := ColorRect.new(); dim.color = Color(0, 0, 0, 0.6); dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.custom_minimum_size = Vector2(980, 600)
	pc.position = Vector2(150, 60)
	pc.add_theme_stylebox_override("panel", UIKit.box(UIKit.BG2, 16))
	add_child(pc)
	var v := VBoxContainer.new(); pc.add_child(v)
	var t := Label.new(); t.text = _title + ("   (" + ", ".join(exts) + ")" if not exts.is_empty() else ""); t.add_theme_color_override("font_color", UIKit.ACCENT)
	v.add_child(t)
	var top := HBoxContainer.new(); v.add_child(top)
	top.add_child(UIKit.btn("Up", _up, false, 46))
	_path_edit = LineEdit.new(); _path_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_path_edit.custom_minimum_size = Vector2(0, 46)
	_path_edit.text_submitted.connect(func(s): go(s))
	top.add_child(_path_edit)
	var sc := HFlowContainer.new(); v.add_child(sc)
	for d in _shortcuts():
		var path: String = d[1]
		sc.add_child(UIKit.btn(d[0], func(): go(path), false, 42))
	var scroll := ScrollContainer.new(); scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_list = VBoxContainer.new(); _list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var bot := HBoxContainer.new(); v.add_child(bot)
	bot.add_child(UIKit.btn("Cancel", queue_free, false, 54))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; bot.add_child(sp)
	_ok = UIKit.btn("Select", _confirm, false, 54)
	_ok.custom_minimum_size.x = 220
	bot.add_child(_ok)
	var start := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if start == "" or not DirAccess.dir_exists_absolute(start): start = ProjectSettings.globalize_path("user://")
	go(start)

func _shortcuts() -> Array:
	var out: Array = []
	var dl := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if dl != "": out.append(["Downloads", dl])
	var docs := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if docs != "": out.append(["Documents", docs])
	var pics := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if pics != "": out.append(["Pictures", pics])
	if OS.get_name() == "Android": out.append(["Storage", "/storage/emulated/0"])
	out.append(["Home", OS.get_environment("HOME") if OS.get_environment("HOME") != "" else "/"])
	out.append(["App folder", ProjectSettings.globalize_path("user://")])
	out.append(["import_assets", ProjectSettings.globalize_path("res://import_assets")])
	return out

func go(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	cur = path
	_path_edit.text = path
	for c in _list.get_children(): c.queue_free()
	var da := DirAccess.open(path)
	if da == null:
		var l := Label.new(); l.text = "Cannot open this folder (storage permission?)"; _list.add_child(l)
		return
	var dirs: Array = []; var files: Array = []
	for d in da.get_directories():
		if not d.begins_with("."): dirs.append(d)
	for f in da.get_files():
		if exts.is_empty() or f.get_extension().to_lower() in exts: files.append(f)
	dirs.sort(); files.sort()
	for d in dirs:
		var full := path.path_join(d)
		var b := UIKit.btn("[folder]  " + d, func(): go(full), false, 50)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_list.add_child(b)
	for f in files:
		var full := path.path_join(f)
		var b2 := Button.new()
		b2.text = "%s    (%s)" % [f, _size_txt(full)]
		b2.toggle_mode = true
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b2.custom_minimum_size = Vector2(0, 50)
		b2.focus_mode = Control.FOCUS_NONE
		b2.button_pressed = sel.has(full)
		b2.toggled.connect(func(on):
			if on:
				if not multi: sel.clear()
				sel[full] = true
			else: sel.erase(full)
			_update_ok()
			if not multi and on: _confirm())
		_list.add_child(b2)
	if dirs.is_empty() and files.is_empty():
		var l2 := Label.new(); l2.text = "(empty)"; _list.add_child(l2)
	_update_ok()

func _size_txt(p: String) -> String:
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null: return "?"
	var n := f.get_length(); f.close()
	return "%.1f MB" % (n / 1048576.0) if n > 1048576 else "%d KB" % (n / 1024)

func _up() -> void:
	var p := cur.get_base_dir()
	if p != cur: go(p)

func _update_ok() -> void:
	_ok.text = "Select (%d)" % sel.size()
	_ok.disabled = sel.is_empty()

func _confirm() -> void:
	if sel.is_empty(): return
	picked.emit(sel.keys())
	queue_free()
