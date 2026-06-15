@tool
extends Node2D

const TrailProjectileScript := preload("res://scripts/trail_projectile.gd")

const PARTICLE_LIFETIME := 1.0
const SPAWN_INTERVAL_MIN := 0.030
const SPAWN_INTERVAL_MAX := 0.070
const MAX_ACTIVE_PARTICLES := 39
const SPEED_MIN := 10.0
const SPEED_MAX := 44.0
const RING_LIFETIME := 1.85
const RING_SPAWN_INTERVAL := 1.15
const RING_INNER_RADIUS := 8.0
const RING_OUTER_RADIUS := 38.0
const RING_WIDTH := 2.7
const RING_POINT_COUNT := 96

@export var preview_color: Color = Color(0.40, 0.90, 0.35, 0.60):
	set(value):
		preview_color = value
		configure(value)

var _texture: Texture2D = null
var _color: Color = Color.WHITE
var _particles: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_spawn_delay: float = 0.0
var _next_ring_delay: float = 0.0


func _ready() -> void:
	_rng.randomize()
	_texture = TrailProjectileScript.make_attack_spark_texture()
	_color = preview_color
	_next_spawn_delay = _rng.randf_range(0.02, 0.08)
	_next_ring_delay = 0.0
	set_process(true)


func configure(color: Color) -> void:
	_color = color
	if _texture == null:
		_texture = TrailProjectileScript.make_attack_spark_texture()
	if _particles.is_empty() and _next_spawn_delay <= 0.0:
		_next_spawn_delay = _rng.randf_range(0.02, 0.08)
	if _rings.is_empty() and _next_ring_delay <= 0.0:
		_next_ring_delay = 0.0
	queue_redraw()


func _process(delta: float) -> void:
	_next_spawn_delay -= delta
	while _next_spawn_delay <= 0.0:
		_spawn_particle()
		_next_spawn_delay += _rng.randf_range(SPAWN_INTERVAL_MIN, SPAWN_INTERVAL_MAX)

	_next_ring_delay -= delta
	while _next_ring_delay <= 0.0:
		_spawn_ring()
		_next_ring_delay += RING_SPAWN_INTERVAL

	for i in range(_particles.size() - 1, -1, -1):
		var p: Dictionary = _particles[i]
		p["age"] = float(p.get("age", 0.0)) + delta
		if float(p.get("age", 0.0)) >= PARTICLE_LIFETIME:
			_particles.remove_at(i)
		else:
			_particles[i] = p
	for i in range(_rings.size() - 1, -1, -1):
		var ring: Dictionary = _rings[i]
		ring["age"] = float(ring.get("age", 0.0)) + delta
		if float(ring.get("age", 0.0)) >= RING_LIFETIME:
			_rings.remove_at(i)
		else:
			_rings[i] = ring
	queue_redraw()


func _spawn_particle() -> void:
	if _particles.size() >= MAX_ACTIVE_PARTICLES:
		_particles.pop_front()
	_particles.append({
		"age": 0.0,
		"angle": _rng.randf_range(0.0, TAU),
		"speed": _rng.randf_range(SPEED_MIN, SPEED_MAX),
		"scale": _rng.randf_range(0.75, 1.38),
		"alpha": _rng.randf_range(0.55, 0.95),
	})


func _spawn_ring() -> void:
	_rings.append({
		"age": 0.0,
		"alpha": _rng.randf_range(0.46, 0.72),
		"width": _rng.randf_range(RING_WIDTH * 0.75, RING_WIDTH * 1.15),
	})


func _draw() -> void:
	_draw_pulse_rings()
	if _texture == null:
		return
	for p in _particles:
		var age: float = float(p.get("age", 0.0))
		var t: float = clampf(age / PARTICLE_LIFETIME, 0.0, 1.0)
		var angle: float = float(p.get("angle", 0.0))
		var dir := Vector2(cos(angle), sin(angle))
		var travel_t: float = 1.0 - pow(1.0 - t, 1.55)
		var pos: Vector2 = dir * float(p.get("speed", 24.0)) * PARTICLE_LIFETIME * travel_t
		var fade_in: float = clampf(t / 0.16, 0.0, 1.0)
		var fade_out: float = pow(1.0 - t, 1.35)
		var alpha: float = float(p.get("alpha", 0.75)) * fade_in * fade_out
		if alpha <= 0.01:
			continue
		var shrink: float = lerpf(1.0, 0.04, pow(t, 1.10))
		var size: Vector2 = _texture.get_size() * float(p.get("scale", 0.7)) * shrink
		var rect := Rect2(pos - size * 0.5, size)
		draw_texture_rect(_texture, rect, false, Color(_color.r, _color.g, _color.b, alpha * 0.62))
		var core_size: Vector2 = size * 0.46
		draw_texture_rect(_texture, Rect2(pos - core_size * 0.5, core_size), false, Color(1, 1, 1, alpha * 0.72))


func _draw_pulse_rings() -> void:
	for ring in _rings:
		var age: float = float(ring.get("age", 0.0))
		var t: float = clampf(age / RING_LIFETIME, 0.0, 1.0)
		var ease_t: float = 1.0 - pow(1.0 - t, 2.1)
		var radius: float = lerpf(RING_INNER_RADIUS, RING_OUTER_RADIUS, ease_t)
		var fade_in: float = clampf(t / 0.18, 0.0, 1.0)
		var fade_out: float = pow(1.0 - t, 1.65)
		var alpha: float = float(ring.get("alpha", 0.58)) * fade_in * fade_out
		if alpha <= 0.01:
			continue
		var width: float = float(ring.get("width", RING_WIDTH))
		var glow_color := Color(_color.r, _color.g, _color.b, alpha * 0.24)
		var core_color := Color(_color.r, _color.g, _color.b, alpha * 0.72)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, RING_POINT_COUNT, glow_color, width * 2.8, true)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, RING_POINT_COUNT, core_color, width, true)
