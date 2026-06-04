## DebrisVfx — pooled falling shard effect for gem and obstacle breaks.
class_name DebrisVfx
extends Node2D

const MAX_ACTIVE_NODES := 44
const MAX_SHARDS_PER_NODE := 8
const GRAVITY := 980.0
const DEFAULT_Z_INDEX := 90

static var _inactive_pool: Array = []
static var _active_nodes: Array = []
static var _rng := RandomNumberGenerator.new()
static var _rng_ready := false

var _sprites: Array[Sprite2D] = []
var _velocities: Array[Vector2] = []
var _angular_velocities: Array[float] = []
var _lifetimes: Array[float] = []
var _base_colors: Array[Color] = []
var _age: float = 0.0
var _active: bool = false


static func play(parent: Node, texture: Texture2D, global_pos: Vector2, shard_count: int, scale_range: Vector2, lifetime_range: Vector2, z_index_value: int = DEFAULT_Z_INDEX, tint: Color = Color.WHITE) -> void:
	if parent == null or texture == null:
		return
	_ensure_rng()
	var debris: DebrisVfx = _acquire(parent)
	debris._restart(texture, global_pos, shard_count, scale_range, lifetime_range, z_index_value, tint)


static func _ensure_rng() -> void:
	if _rng_ready:
		return
	_rng.randomize()
	_rng_ready = true


static func _acquire(parent: Node) -> DebrisVfx:
	var debris: DebrisVfx = null
	while debris == null and not _inactive_pool.is_empty():
		var pooled: Variant = _inactive_pool.pop_back()
		if is_instance_valid(pooled):
			debris = pooled as DebrisVfx

	if debris == null and _active_nodes.size() >= MAX_ACTIVE_NODES:
		var oldest: Variant = _active_nodes.pop_front()
		if is_instance_valid(oldest):
			debris = oldest as DebrisVfx
			debris._deactivate(false)

	if debris == null:
		debris = DebrisVfx.new()

	if debris.get_parent() != parent:
		if debris.get_parent() != null:
			debris.get_parent().remove_child(debris)
		parent.add_child(debris)

	_active_nodes.erase(debris)
	_active_nodes.append(debris)
	return debris


func _ensure_shards() -> void:
	while _sprites.size() < MAX_SHARDS_PER_NODE:
		var sprite := Sprite2D.new()
		sprite.centered = true
		sprite.visible = false
		add_child(sprite)
		_sprites.append(sprite)
		_velocities.append(Vector2.ZERO)
		_angular_velocities.append(0.0)
		_lifetimes.append(0.0)
		_base_colors.append(Color.WHITE)


func _restart(texture: Texture2D, start_global_pos: Vector2, requested_shards: int, scale_range: Vector2, lifetime_range: Vector2, z_index_value: int, tint: Color) -> void:
	_ensure_shards()
	global_position = start_global_pos
	z_index = z_index_value
	visible = true
	_age = 0.0
	_active = true
	set_process(true)

	var shard_total: int = clampi(requested_shards, 1, MAX_SHARDS_PER_NODE)
	var texture_size := Vector2(float(texture.get_width()), float(texture.get_height()))
	var min_region_size := Vector2(maxf(texture_size.x * 0.24, 8.0), maxf(texture_size.y * 0.24, 8.0))
	var max_region_size := Vector2(maxf(texture_size.x * 0.44, min_region_size.x), maxf(texture_size.y * 0.44, min_region_size.y))

	for shard_index in MAX_SHARDS_PER_NODE:
		var sprite: Sprite2D = _sprites[shard_index]
		if shard_index >= shard_total:
			sprite.visible = false
			continue

		var region_width: float = minf(_rng.randf_range(min_region_size.x, max_region_size.x), texture_size.x)
		var region_height: float = minf(_rng.randf_range(min_region_size.y, max_region_size.y), texture_size.y)
		var region_x: float = _rng.randf_range(0.0, maxf(texture_size.x - region_width, 0.0))
		var region_y: float = _rng.randf_range(0.0, maxf(texture_size.y - region_height, 0.0))
		var shard_scale: float = _rng.randf_range(scale_range.x, scale_range.y)
		var angle: float = _rng.randf_range(-PI, 0.0)
		var speed: float = _rng.randf_range(130.0, 290.0)
		var upward_kick: float = _rng.randf_range(80.0, 180.0)
		var lifetime: float = _rng.randf_range(lifetime_range.x, lifetime_range.y)

		sprite.texture = texture
		sprite.region_enabled = true
		sprite.region_rect = Rect2(region_x, region_y, region_width, region_height)
		sprite.position = Vector2(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-5.0, 5.0))
		sprite.scale = Vector2(shard_scale, shard_scale)
		sprite.rotation = _rng.randf_range(0.0, TAU)
		sprite.modulate = tint
		sprite.visible = true

		_velocities[shard_index] = Vector2(cos(angle) * speed, sin(angle) * speed * 0.65 - upward_kick)
		_angular_velocities[shard_index] = _rng.randf_range(-TAU * 3.0, TAU * 3.0)
		_lifetimes[shard_index] = lifetime
		_base_colors[shard_index] = tint


func _process(delta: float) -> void:
	if not _active:
		return
	_age += delta
	var all_done := true
	for shard_index in MAX_SHARDS_PER_NODE:
		var sprite: Sprite2D = _sprites[shard_index]
		if not sprite.visible:
			continue
		var lifetime: float = _lifetimes[shard_index]
		if _age >= lifetime:
			sprite.visible = false
			continue

		all_done = false
		var velocity: Vector2 = _velocities[shard_index]
		velocity.y += GRAVITY * delta
		_velocities[shard_index] = velocity
		sprite.position += velocity * delta
		sprite.rotation += _angular_velocities[shard_index] * delta

		var fade_start: float = lifetime * 0.45
		if _age > fade_start:
			var fade_t: float = clampf((_age - fade_start) / maxf(lifetime - fade_start, 0.001), 0.0, 1.0)
			var base_color: Color = _base_colors[shard_index]
			base_color.a *= 1.0 - fade_t
			sprite.modulate = base_color

	if all_done:
		_release_to_pool()


func _deactivate(return_to_pool: bool) -> void:
	_active = false
	set_process(false)
	visible = false
	for sprite in _sprites:
		sprite.visible = false
	if return_to_pool:
		_active_nodes.erase(self)
		if not _inactive_pool.has(self):
			_inactive_pool.append(self)


func _release_to_pool() -> void:
	_deactivate(true)
