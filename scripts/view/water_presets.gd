# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : water_presets.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name WaterPresets
extends RefCounted
const PRESETS := {
	"gta":   {"name": "GTA V clear", "shallow": Color(0.12, 0.66, 0.60), "mid": Color(0.05, 0.42, 0.50), "deep": Color(0.02, 0.20, 0.32), "clarity": 1.0, "wave": 0.5, "wave_h": 0.012, "foam": 1.0},
	"ocean": {"name": "Deep ocean", "shallow": Color(0.10, 0.55, 0.62), "mid": Color(0.03, 0.30, 0.50), "deep": Color(0.01, 0.12, 0.30), "clarity": 0.9, "wave": 0.7, "wave_h": 0.05, "foam": 1.0},
	"river": {"name": "River", "shallow": Color(0.24, 0.50, 0.40), "mid": Color(0.12, 0.34, 0.30), "deep": Color(0.06, 0.20, 0.20), "clarity": 0.6, "wave": 0.9, "wave_h": 0.01, "foam": 0.6},
	"swamp": {"name": "Swamp", "shallow": Color(0.28, 0.40, 0.18), "mid": Color(0.14, 0.24, 0.12), "deep": Color(0.07, 0.12, 0.08), "clarity": 0.35, "wave": 0.25, "wave_h": 0.006, "foam": 0.2},
	"pool":  {"name": "Pool", "shallow": Color(0.30, 0.86, 0.92), "mid": Color(0.15, 0.66, 0.82), "deep": Color(0.10, 0.50, 0.72), "clarity": 1.0, "wave": 0.3, "wave_h": 0.006, "foam": 0.0},
}
static var _noise: ImageTexture

static func noise_tex() -> ImageTexture:
	if _noise != null: return _noise
	var chans: Array[Image] = []
	for i in 3:
		var n := FastNoiseLite.new()
		n.seed = 100 + i * 17
		n.frequency = 0.02 + i * 0.01
		n.fractal_octaves = 3
		chans.append(n.get_seamless_image(256, 256, false, false, 0.25))
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		for x in 256:
			img.set_pixel(x, y, Color(chans[0].get_pixel(x, y).r, chans[1].get_pixel(x, y).r, chans[2].get_pixel(x, y).r))
	img.generate_mipmaps()
	_noise = ImageTexture.create_from_image(img)
	return _noise

static func make_material(preset: String) -> ShaderMaterial:
	var p: Dictionary = PRESETS.get(preset, PRESETS["gta"])
	var m := ShaderMaterial.new()
	m.shader = load("res://assets/shaders/water_surface.gdshader")
	m.set_shader_parameter("noise_tex", noise_tex())
	m.set_shader_parameter("shallow_col", p["shallow"])
	m.set_shader_parameter("mid_col", p["mid"])
	m.set_shader_parameter("deep_col", p["deep"])
	m.set_shader_parameter("clarity", p["clarity"])
	m.set_shader_parameter("wave_speed", p["wave"])
	m.set_shader_parameter("wave_height", p["wave_h"])
	m.set_shader_parameter("foam_amount", p["foam"])
	return m
