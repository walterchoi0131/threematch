extends Node
class_name PlayerProjectileImpactVfx

const IMPACT_SCENES := {
	Block.Type.GREEN: preload("res://projectiles/impacts/projectile_2_impact.tscn"),
	Block.Type.RED: preload("res://projectiles/impacts/projectile_3_impact.tscn"),
	Block.Type.LIGHT: preload("res://projectiles/impacts/projectile_4_impact.tscn"),
}
const PREWARM_PER_ELEMENT := 2
const MAX_PER_ELEMENT := 4
const SOURCE_CAMERA_DISTANCE := 8.520485
const EFFECT_END_PADDING_SEC := 0.12
const GPU_PREWARM_SCALE := 0.002

var _layer: BattleVfx3DLayer = null
var _templates: Dictionary = {}
var _pools: Dictionary = {}
var _particles_by_id: Dictionary = {}
var _duration_by_id: Dictionary = {}
var _active_until_msec: Dictionary = {}
var _active_started_msec: Dictionary = {}
var _active_nodes: Dictionary = {}
var _gpu_prewarmed: bool = false


func configure(layer: BattleVfx3DLayer) -> void:
	_layer = layer
	if _layer == null or not _templates.is_empty():
		return
	for element_value in IMPACT_SCENES.keys():
		var element := int(element_value)
		var template := _instantiate_impact_template(IMPACT_SCENES[element] as PackedScene)
		if template == null:
			continue
		_templates[element] = template
		_pools[element] = []
		for _index in PREWARM_PER_ELEMENT:
			_create_pool_node(element)
	set_process(false)


func play_impact(gem_type: Block.Type, screen_position: Vector2, visual_scale: float = 1.0) -> bool:
	var element := int(gem_type)
	if _layer == null or not _templates.has(element):
		return false
	var impact := _acquire_node(element)
	if impact == null:
		return false
	_activate_node(impact, screen_position, maxf(visual_scale, 0.01))
	return true


func prewarm_gpu() -> void:
	if _gpu_prewarmed or _layer == null:
		return
	_gpu_prewarmed = true
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var warmed_nodes: Array[Node3D] = []
	var center := ViewportUtils.get_size() * 0.5
	for element_value in _templates.keys():
		var impact := _acquire_node(int(element_value))
		if impact == null:
			continue
		_activate_node(impact, center, GPU_PREWARM_SCALE)
		warmed_nodes.append(impact)
	for _frame in 3:
		await get_tree().process_frame
		if not is_inside_tree():
			return
	for impact in warmed_nodes:
		_release_node(impact)


func _process(_delta: float) -> void:
	if _active_until_msec.is_empty():
		set_process(false)
		return
	var now := Time.get_ticks_msec()
	var expired_ids: Array[int] = []
	for id_value in _active_until_msec.keys():
		var id := int(id_value)
		if now >= int(_active_until_msec[id]):
			expired_ids.append(id)
	for id in expired_ids:
		var impact: Node3D = _active_nodes.get(id) as Node3D
		if is_instance_valid(impact):
			_release_node(impact)
		else:
			_forget_active_id(id)


func _instantiate_impact_template(scene: PackedScene) -> Node3D:
	if scene == null:
		return null
	var impact := scene.instantiate() as Node3D
	if impact == null:
		return null
	impact.name = "ImpactTemplate"
	impact.visible = false
	return impact


func _create_pool_node(element: int) -> Node3D:
	var template: Node3D = _templates.get(element) as Node3D
	if template == null:
		return null
	var impact := template.duplicate() as Node3D
	if impact == null:
		return null
	impact.name = "PlayerImpact_%d_%d" % [element, (_pools.get(element, []) as Array).size()]
	impact.visible = false
	var particles: Array[GPUParticles3D] = []
	_collect_particles(impact, particles)
	var duration := 0.0
	for particle in particles:
		particle.emitting = false
		var playback_speed := maxf(absf(particle.speed_scale), 0.01)
		duration = maxf(duration, particle.lifetime / playback_speed)
	var id := impact.get_instance_id()
	_particles_by_id[id] = particles
	_duration_by_id[id] = duration + EFFECT_END_PADDING_SEC
	var pool: Array = _pools.get(element, [])
	pool.append(impact)
	_pools[element] = pool
	return impact


func _collect_particles(root: Node, output: Array[GPUParticles3D]) -> void:
	for child in root.get_children():
		if child is GPUParticles3D:
			output.append(child as GPUParticles3D)
		_collect_particles(child, output)


func _acquire_node(element: int) -> Node3D:
	var pool: Array = _pools.get(element, [])
	for value in pool:
		var impact := value as Node3D
		if is_instance_valid(impact) and not _active_until_msec.has(impact.get_instance_id()):
			return impact
	if pool.size() < MAX_PER_ELEMENT:
		return _create_pool_node(element)
	var oldest: Node3D = null
	var oldest_started := Time.get_ticks_msec()
	for value in pool:
		var impact := value as Node3D
		if not is_instance_valid(impact):
			continue
		var started := int(_active_started_msec.get(impact.get_instance_id(), oldest_started))
		if oldest == null or started < oldest_started:
			oldest = impact
			oldest_started = started
	if oldest != null:
		_release_node(oldest)
	return oldest


func _activate_node(impact: Node3D, screen_position: Vector2, visual_scale: float) -> void:
	var id := impact.get_instance_id()
	_layer.add_world_node(impact)
	impact.global_position = _layer.screen_to_world(screen_position)
	var camera_scale := BattleVfx3DLayer.CAMERA_DISTANCE / SOURCE_CAMERA_DISTANCE
	impact.scale = Vector3.ONE * camera_scale * visual_scale
	impact.visible = true
	for particle_value in _particles_by_id.get(id, []):
		var particle := particle_value as GPUParticles3D
		if is_instance_valid(particle):
			particle.restart()
	var now := Time.get_ticks_msec()
	_active_started_msec[id] = now
	_active_until_msec[id] = now + int(ceil(float(_duration_by_id.get(id, 1.0)) * 1000.0))
	_active_nodes[id] = impact
	set_process(true)


func _release_node(impact: Node3D) -> void:
	if not is_instance_valid(impact):
		return
	var id := impact.get_instance_id()
	for particle_value in _particles_by_id.get(id, []):
		var particle := particle_value as GPUParticles3D
		if is_instance_valid(particle):
			particle.emitting = false
	impact.visible = false
	if is_instance_valid(_layer):
		_layer.deactivate_world_node(impact)
	_forget_active_id(id)


func _forget_active_id(id: int) -> void:
	_active_until_msec.erase(id)
	_active_started_msec.erase(id)
	_active_nodes.erase(id)
	if _active_until_msec.is_empty():
		set_process(false)


func _exit_tree() -> void:
	for template_value in _templates.values():
		var template := template_value as Node3D
		if is_instance_valid(template) and template.get_parent() == null:
			template.free()
	for pool_value in _pools.values():
		for node_value in pool_value as Array:
			var impact := node_value as Node3D
			if not is_instance_valid(impact):
				continue
			if impact.get_parent() == null:
				impact.free()
			else:
				impact.queue_free()
