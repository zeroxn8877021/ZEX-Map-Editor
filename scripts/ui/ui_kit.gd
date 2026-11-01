# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : ui_kit.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name UIKit
extends RefCounted
## Touch-sized widgets + dark theme used by the whole editor UI.
const BG := Color(0.07, 0.08, 0.10, 0.88)
const BG2 := Color(0.12, 0.14, 0.17, 0.95)
const ACCENT := Color(1.0, 0.72, 0.18)
const TXT := Color(0.93, 0.95, 0.97)
const DIM := Color(0.62, 0.67, 0.72)

static func box(col: Color, r := 10, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(r)
	s.border_color = border
	s.set_border_width_all(bw)
	s.content_margin_left = 12; s.content_margin_right = 12
	s.content_margin_top = 8; s.content_margin_bottom = 8
	return s

static func circle_tex(radius: int, col: Color) -> ImageTexture:
	var d := radius * 2
	var im := Image.create(d, d, false, Image.FORMAT_RGBA8)
	for y in d:
		for x in d:
			var dist := Vector2(x + 0.5 - radius, y + 0.5 - radius).length()
			var a := clampf(radius - dist, 0.0, 1.0)
			im.set_pixel(x, y, Color(col.r, col.g, col.b, a))
	return ImageTexture.create_from_image(im)

static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 20
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		pass
	t.set_stylebox("normal", "Button", box(Color(0.17, 0.20, 0.24, 0.95)))
	t.set_stylebox("hover", "Button", box(Color(0.22, 0.26, 0.31, 0.95)))
	t.set_stylebox("pressed", "Button", box(ACCENT.darkened(0.15), 10))
	t.set_stylebox("disabled", "Button", box(Color(0.12, 0.13, 0.15, 0.7)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TXT)
	t.set_color("font_pressed_color", "Button", Color(0.1, 0.07, 0.0))
	t.set_color("font_hover_color", "Button", TXT)
	t.set_color("font_disabled_color", "Button", DIM)
	t.set_color("icon_normal_color", "Button", Color.WHITE)
	t.set_color("icon_pressed_color", "Button", Color.WHITE)
	t.set_color("icon_hover_color", "Button", Color.WHITE)
	t.set_font_size("font_size", "Button", 19)
	t.set_stylebox("panel", "PanelContainer", box(BG, 14))
	t.set_color("font_color", "Label", TXT)
	t.set_font_size("font_size", "Label", 19)
	var track := box(Color(0.25, 0.29, 0.34), 6)
	track.content_margin_top = 4; track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT.darkened(0.2), 6))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, 6))
	var g := circle_tex(18, ACCENT)
	t.set_icon("grabber", "HSlider", g)
	t.set_icon("grabber_highlight", "HSlider", g)
	t.set_icon("grabber_disabled", "HSlider", g)
	t.set_constant("center_grabber", "HSlider", 0)
	t.set_stylebox("normal", "LineEdit", box(Color(0.1, 0.12, 0.15), 8, Color(0.3, 0.35, 0.4), 1))
	t.set_stylebox("focus", "LineEdit", box(Color(0.1, 0.12, 0.15), 8, ACCENT, 2))
	t.set_color("font_color", "LineEdit", TXT)
	t.set_stylebox("panel", "PopupPanel", box(BG2, 12))
	t.set_constant("separation", "VBoxContainer", 8)
	t.set_constant("h_separation", "HFlowContainer", 8)
	t.set_constant("v_separation", "HFlowContainer", 8)
	t.set_constant("separation", "HBoxContainer", 8)
	return t

static func btn(text: String, cb: Callable, toggle := false, min_h := 52) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = toggle
	b.custom_minimum_size = Vector2(0, min_h)
	b.focus_mode = Control.FOCUS_NONE
	if toggle: b.toggled.connect(func(on): cb.call(on))
	else: b.pressed.connect(cb)
	return b

static func header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", ACCENT)
	l.add_theme_font_size_override("font_size", 17)
	return l

static func hint(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", DIM)
	l.add_theme_font_size_override("font_size", 15)
	return l

## Row of mutually exclusive toggle buttons. items: [[id, label], ...]
static func mode_row(items: Array, current: String, cb: Callable, cols := 3) -> Control:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 6)
	var grp := ButtonGroup.new()
	for it in items:
		var b := Button.new()
		b.text = it[1]
		b.toggle_mode = true
		b.button_group = grp
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 17)
		b.button_pressed = (it[0] == current)
		var id: String = it[0]
		b.pressed.connect(func(): cb.call(id))
		g.add_child(b)
	return g

## Labelled slider. Writes into dict[key]; on_change is optional.
static func slider(label: String, dict: Dictionary, key: String, lo: float, hi: float, step: float, on_change: Callable = Callable(), suffix := "") -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	var l := Label.new(); l.text = label; l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.add_theme_font_size_override("font_size", 17)
	var vl := Label.new(); vl.add_theme_color_override("font_color", ACCENT); vl.add_theme_font_size_override("font_size", 17)
	top.add_child(l); top.add_child(vl)
	var s := HSlider.new()
	s.min_value = lo; s.max_value = hi; s.step = step
	s.value = float(dict[key])
	s.custom_minimum_size = Vector2(0, 38)
	s.focus_mode = Control.FOCUS_NONE
	var fmt := func(x: float) -> String:
		return ("%d%s" % [int(x), suffix]) if step >= 1.0 else ("%.2f%s" % [x, suffix])
	vl.text = fmt.call(s.value)
	s.value_changed.connect(func(x):
		dict[key] = x
		vl.text = fmt.call(x)
		if on_change.is_valid(): on_change.call(x))
	v.add_child(top); v.add_child(s)
	return v

static func toggle(label: String, dict: Dictionary, key: String, on_change: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = label
	b.toggle_mode = true
	b.button_pressed = bool(dict[key])
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 48)
	b.toggled.connect(func(on):
		dict[key] = on
		if on_change.is_valid(): on_change.call(on))
	return b

static func flow() -> HFlowContainer:
	return HFlowContainer.new()
