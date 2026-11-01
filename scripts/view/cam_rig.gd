# Project   : ZEX Map Editor
# Studio    : Zex Interactive
# Author    : Paras Sharma
# File      : cam_rig.gd
# Copyright : (c) Zex Interactive. All rights reserved.

class_name CamRig
extends Node3D
## Orbit camera around a ground focus point. Touch gestures are fed in by the editor (pan / pinch / twist / orbit);
## desktop: RMB orbit, MMB / Shift+RMB pan, wheel zoom, WASD fly-pan.

var cam: Camera3D
var data: MapData
var focus := Vector3.ZERO
var yaw := deg_to_rad(35.0)
var pitch := deg_to_rad(-42.0)
var dist := 90.0
var _t_focus := Vector3.ZERO
var _t_yaw := yaw
var _t_pitch := pitch
var _t_dist := dist
var min_dist := 3.0
var max_dist := 700.0
var walk_mode := false
var walk_pos := Vector3.ZERO
var _bounds := Rect2()

func _ready() -> void:
	cam = Camera3D.new()
	cam.name = "Cam"
	cam.fov = 62.0
	cam.near = 0.12
	cam.far = 2500.0
	add_child(cam)
	cam.make_current()

func setup(d: MapData) -> void:
	data = d
	_t_focus = Vector3(0, d.height_at(0, 0), 0)
	focus = _t_focus
	_t_dist = 75.0
	dist = _t_dist
	max_dist = 900.0
	_bounds = d.active_bounds()

func orbit(dx: float, dy: float) -> void:
	_t_yaw -= dx * 0.0065
	_t_pitch = clampf(_t_pitch - dy * 0.0055, deg_to_rad(-88.0), deg_to_rad(-6.0))

func twist(a: float) -> void:
	_t_yaw += a

func pan_screen(dx: float, dy: float) -> void:
	var right := Vector3(cos(_t_yaw), 0, -sin(_t_yaw))
	var fwd := Vector3(-sin(_t_yaw), 0, -cos(_t_yaw))
	var k := _t_dist * 0.0014 * (62.0 / cam.fov)
	_t_focus += (-right * dx + fwd * dy) * k
	_clamp_focus()

func pan_world(v: Vector3) -> void:
	_t_focus += v
	_clamp_focus()

func zoom_mul(f: float) -> void:
	_t_dist = clampf(_t_dist * f, min_dist, max_dist)

func focus_on(p: Vector3, d: float = -1.0) -> void:
	_t_focus = p
	if d > 0: _t_dist = d
	_clamp_focus()

func refresh_bounds() -> void:
	_bounds = data.active_bounds()

func _clamp_focus() -> void:
	if data == null: return
	var b := _bounds.grow(12.0)
	_t_focus.x = clampf(_t_focus.x, b.position.x, b.end.x)
	_t_focus.z = clampf(_t_focus.z, b.position.y, b.end.y)

func _process(dt: float) -> void:
	if data == null: return
	var k := 1.0 - exp(-dt * 14.0)
	_t_focus.y = data.height_at(_t_focus.x, _t_focus.z)
	focus = focus.lerp(_t_focus, k)
	yaw = lerp_angle(yaw, _t_yaw, k)
	pitch = lerpf(pitch, _t_pitch, k)
	dist = lerpf(dist, _t_dist, k)
	if walk_mode:
		return
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0))
	var p := focus + basis * Vector3(0, 0, dist)
	var gh := data.height_at(p.x, p.z) + 1.5
	if p.y < gh:
		p.y = gh
	cam.global_transform = Transform3D(Basis.IDENTITY, p).looking_at(focus + Vector3(0, 0.5, 0), Vector3.UP)

func ray_from_screen(pos: Vector2) -> Dictionary:
	return {"o": cam.project_ray_origin(pos), "d": cam.project_ray_normal(pos)}

func screen_to_ground(pos: Vector2) -> Variant:
	var r := ray_from_screen(pos)
	return data.raycast(r["o"], r["d"])

func enter_walk(p: Vector3) -> void:
	walk_mode = true
	walk_pos = p
	cam.fov = 70.0

func exit_walk() -> void:
	walk_mode = false
	cam.fov = 62.0

func walk_step(move: Vector2, look: Vector2, dt: float, run: bool) -> void:
	_t_yaw -= look.x * 0.004
	_t_pitch = clampf(_t_pitch - look.y * 0.004, deg_to_rad(-80), deg_to_rad(80))
	yaw = _t_yaw; pitch = _t_pitch
	var spd := (9.0 if run else 4.0)
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	walk_pos += (fwd * -move.y + right * move.x) * spd * dt
	walk_pos.x = clampf(walk_pos.x, _bounds.position.x, _bounds.end.x); walk_pos.z = clampf(walk_pos.z, _bounds.position.y, _bounds.end.y)
	walk_pos.y = lerpf(walk_pos.y, data.height_at(walk_pos.x, walk_pos.z), 1.0 - exp(-dt * 12.0))
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(pitch, yaw, 0)), walk_pos + Vector3(0, 1.7, 0))
