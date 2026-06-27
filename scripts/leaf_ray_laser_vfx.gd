extends Node2D

signal finished

const BeamVFXScene := preload("res://assets/BinbunVFX/beam_vfx/effects/base/base_beam_vfx.tscn")

const PRIMARY_COLOR := Color(1.0, 0.96, 0.64, 1.0)
const SECONDARY_COLOR := Color(0.42, 1.0, 0.10, 1.0)
const TERTIARY_COLOR := Color(1.0, 0.68, 0.05, 1.0)
const CAMERA_DISTANCE := 5.2
const BEAM_RADIUS := 0.05
const START_RADIUS := 0.032
const BEAM_SCALE := 0.52
const VIEWPORT_PADDING := 80.0

var from_pos: Vector2 = Vector2.ZERO
var to_pos: Vector2 = Vector2.ZERO
var duration: float = 1.0
var elapsed: float = 0.0
var source_node: Node2D = null

var _container: SubViewportContainer = null
var _viewport: SubViewport = null
var _camera: Camera3D = null
var _beam: Node3D = null
var _beam_end_point: Node3D = null
var _using_beam_scene: bool = false
var _shared_vfx_layer: BattleVfx3DLayer = null


func _init() -> void:
	set_process(false)


func start(p_from: Vector2, p_to: Vector2, p_duration: float = 1.0) -> void:
	source_node = null
	from_pos = p_from
	to_pos = p_to
	_begin(p_duration)


func start_following(p_source: Node2D, p_to: Vector2, p_duration: float = 1.0) -> void:
	source_node = p_source
	from_pos = p_source.global_position if is_instance_valid(p_source) else from_pos
	to_pos = p_to
	_begin(p_duration)


func play(p_from: Vector2, p_to: Vector2, p_duration: float = 1.0) -> void:
	start(p_from, p_to, p_duration)
	await finished


func set_shared_vfx_layer(layer: BattleVfx3DLayer) -> void:
	_shared_vfx_layer = layer


func _begin(p_duration: float) -> void:
	duration = maxf(p_duration, 0.05)
	elapsed = 0.0
	z_index = 96
	_using_beam_scene = _setup_binbun_beam()
	set_process(true)
	queue_redraw()


func _setup_binbun_beam() -> bool:
	if BeamVFXScene == null:
		return false
	if _shared_vfx_layer != null:
		_shared_vfx_layer.call("_ensure_viewport")
		_viewport = _shared_vfx_layer.viewport
		_camera = _shared_vfx_layer.camera
	elif _container == null:
		_setup_viewport()
	if _viewport == null or _camera == null:
		return false
	_clear_beam()

	if _shared_vfx_layer == null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_container.visible = true

	_beam = BeamVFXScene.instantiate() as Node3D
	if _beam == null:
		return false
	_duplicate_beam_materials(_beam)
	if _shared_vfx_layer != null:
		_shared_vfx_layer.add_world_node(_beam)
	else:
		_viewport.add_child(_beam)

	_beam_end_point = Node3D.new()
	if _shared_vfx_layer != null:
		_shared_vfx_layer.add_world_node(_beam_end_point)
	else:
		_viewport.add_child(_beam_end_point)

	_beam.set("primary_color", PRIMARY_COLOR)
	_beam.set("secondary_color", SECONDARY_COLOR)
	_beam.set("tertiary_color", TERTIARY_COLOR)
	_beam.scale = Vector3(BEAM_SCALE, BEAM_SCALE, BEAM_SCALE)
	_beam.set("emission", 2.2)
	_beam.set("beam_radius", BEAM_RADIUS)
	_beam.set("start_radius", START_RADIUS)
	_beam.set("start_flare", 0.08)
	_beam.set("pulse_strength", 0.025)
	_beam.set("pulse_frequency", 34.0)
	_beam.set("pulse_speed", 42.0)
	_beam.set("start_amount", 42)
	_beam.set("end_amount", 42)
	_beam.set("end_emitting", true)
	_beam.set("enable_end", true)
	_beam.set("end_point", _beam_end_point)
	_beam.set("open_amount", 0.0)
	_beam.set("audio_playing", false)
	_beam.set("audio_autoplay", false)
	_update_beam_transform()
	_show_end_spray_only()
	return true


func _setup_viewport() -> void:
	var rect_size: Vector2 = ViewportUtils.get_size()
	position = Vector2.ZERO

	_container = SubViewportContainer.new()
	_container.size = rect_size + Vector2(VIEWPORT_PADDING * 2.0, VIEWPORT_PADDING * 2.0)
	_container.position = Vector2(-VIEWPORT_PADDING, -VIEWPORT_PADDING)
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.visible = false
	_container.modulate = Color(1.0, 1.0, 1.0, 0.82)
	add_child(_container)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(_container.size)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_container.add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.12
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, -25.0, 0.0)
	light.light_energy = 1.2
	_viewport.add_child(light)

	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 0.0, CAMERA_DISTANCE)
	_camera.current = true
	_viewport.add_child(_camera)


func _process(delta: float) -> void:
	if is_instance_valid(source_node):
		from_pos = source_node.global_position
	elapsed += delta

	if _using_beam_scene:
		_update_beam_transform()
		var open_value: float = clampf(elapsed / 0.12, 0.0, 1.0)
		if elapsed > duration - 0.16:
			open_value = minf(open_value, clampf((duration - elapsed) / 0.16, 0.0, 1.0))
		if is_instance_valid(_beam):
			_beam.set("open_amount", open_value)
			_show_end_spray_only(open_value)
		queue_redraw()
	else:
		queue_redraw()

	if elapsed >= duration:
		set_process(false)
		finished.emit()
		queue_free()


func _update_beam_transform() -> void:
	if not is_instance_valid(_beam) or not is_instance_valid(_beam_end_point):
		return
	var from_3d: Vector3 = _screen_to_world(from_pos)
	var to_3d: Vector3 = _screen_to_world(to_pos)
	var length: float = from_3d.distance_to(to_3d)
	if length <= 0.001:
		length = 0.001
	_beam.global_position = from_3d
	_beam_end_point.global_position = to_3d
	_beam.set("beam_length", length / BEAM_SCALE)
	if _beam.has_method("follow_node"):
		_beam.call("follow_node")
	_show_end_spray_only()


func _show_end_spray_only(open_value: float = 1.0) -> void:
	if not is_instance_valid(_beam):
		return
	_beam.set("enable_end", true)
	var end_pivot := _beam.get_node_or_null("BeamEndPivot")
	if end_pivot != null:
		end_pivot.visible = open_value > 0.72
	var end_mesh := _beam.get_node_or_null("BeamEndPivot/BeamEnd")
	if end_mesh != null:
		end_mesh.visible = false
	var end_particles := _beam.get_node_or_null("BeamEndPivot/BeamEndParticles")
	if end_particles != null and end_particles is GPUParticles3D:
		var particles := end_particles as GPUParticles3D
		particles.visible = open_value > 0.72
		particles.emitting = open_value > 0.72


func _screen_to_world(screen_pos: Vector2) -> Vector3:
	if _shared_vfx_layer != null:
		return _shared_vfx_layer.screen_to_world(screen_pos)
	var view_size: Vector2 = _container.size if _container != null else ViewportUtils.get_size()
	var local_pos := screen_pos + Vector2(VIEWPORT_PADDING, VIEWPORT_PADDING)
	var fov_rad: float = deg_to_rad(_camera.fov if _camera != null else 75.0)
	var half_h: float = CAMERA_DISTANCE * tan(fov_rad * 0.5)
	var aspect: float = view_size.x / maxf(view_size.y, 1.0)
	var half_w: float = half_h * aspect
	return Vector3(
		(local_pos.x / view_size.x - 0.5) * 2.0 * half_w,
		-(local_pos.y / view_size.y - 0.5) * 2.0 * half_h,
		0.0
	)


func _duplicate_beam_materials(root: Node) -> void:
	for child in root.get_children():
		if child is MeshInstance3D:
			var mesh_instance := child as MeshInstance3D
			if mesh_instance.material_override != null:
				mesh_instance.material_override = mesh_instance.material_override.duplicate()
		elif child is GPUParticles3D:
			var particles := child as GPUParticles3D
			if particles.material_override != null:
				particles.material_override = particles.material_override.duplicate()
			if particles.process_material != null:
				particles.process_material = particles.process_material.duplicate()
		_duplicate_beam_materials(child)


func _clear_beam() -> void:
	if is_instance_valid(_beam):
		if _shared_vfx_layer != null:
			_shared_vfx_layer.remove_world_node(_beam)
		else:
			_beam.queue_free()
	_beam = null
	if is_instance_valid(_beam_end_point):
		if _shared_vfx_layer != null:
			_shared_vfx_layer.remove_world_node(_beam_end_point)
		else:
			_beam_end_point.queue_free()
	_beam_end_point = null


func _exit_tree() -> void:
	if _viewport != null and _shared_vfx_layer == null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_clear_beam()


func _draw() -> void:
	if _using_beam_scene:
		_draw_support_beam()
		return
	_draw_support_beam()
	_draw_old_streaks()


func _draw_support_beam() -> void:
	var beam_vec := to_pos - from_pos
	var beam_len := beam_vec.length()
	if beam_len <= 0.1:
		return

	var extend := clampf(elapsed / 0.18, 0.0, 1.0)
	var fade := 1.0
	if elapsed > duration - 0.35:
		fade = clampf((duration - elapsed) / 0.35, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(elapsed * 18.0)
	var end_pos := from_pos + beam_vec * extend

	draw_line(from_pos, end_pos, Color(0.20, 1.00, 0.15, 0.30 * fade), 24.0 + 5.0 * pulse, true)
	draw_line(from_pos, end_pos, Color(0.85, 1.00, 0.18, 0.44 * fade), 15.0 + 3.0 * pulse, true)
	draw_line(from_pos, end_pos, Color(1.00, 0.92, 0.24, 0.66 * fade), 8.0 + 1.8 * pulse, true)
	draw_line(from_pos, end_pos, Color(1.00, 1.00, 0.84, 0.88 * fade), 3.5 + 0.8 * pulse, true)


func _draw_old_streaks() -> void:
	var beam_vec := to_pos - from_pos
	var beam_len := beam_vec.length()
	if beam_len <= 0.1:
		return

	var dir := beam_vec / beam_len
	var perp := Vector2(-dir.y, dir.x)
	var extend := clampf(elapsed / 0.18, 0.0, 1.0)
	var fade := 1.0
	if elapsed > duration - 0.35:
		fade = clampf((duration - elapsed) / 0.35, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(elapsed * 18.0)
	var end_pos := from_pos + beam_vec * extend

	for i in range(9):
		var t0 := float(i) / 9.0
		var t1 := minf(1.0, t0 + 0.38 + 0.08 * sin(float(i)))
		var phase := elapsed * (3.2 + float(i) * 0.13) + float(i) * 1.7
		var offset := perp * (sin(phase) * 18.0 + cos(phase * 0.7) * 8.0)
		var start := from_pos.lerp(end_pos, t0) + offset * 0.55
		var stop := from_pos.lerp(end_pos, t1) + offset
		var line_color := Color(0.64, 1.0, 0.10, (0.34 + 0.16 * pulse) * fade)
		if i % 3 == 0:
			line_color = Color(1.0, 0.75, 0.08, 0.50 * fade)
		draw_line(start, stop, line_color, 2.0 + float(i % 3), true)
