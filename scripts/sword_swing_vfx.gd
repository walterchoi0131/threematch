class_name SwordSwingVfx
extends Node2D

signal finished

const SWORD_SCENE_PATH := "res://assets/kaykit_vfx/sword_1handed.gltf"
const KNIGHT_TEXTURE_PATH := "res://assets/kaykit_vfx/knight_texture.png"
const WINDUP_DURATION := 0.18
const SMASH_DURATION := 0.16
const FADE_OUT_DURATION := 0.16
const HILT_TO_RIGHT_UP_Z_ANGLE := deg_to_rad(-52.0)

var _container: SubViewportContainer = null
var _viewport: SubViewport = null
var _camera: Camera3D = null
var _pivot: Node3D = null
var _model: Node3D = null


func _setup() -> void:
	var rect_size: Vector2 = ViewportUtils.get_size()
	position = Vector2.ZERO

	_container = SubViewportContainer.new()
	_container.size = rect_size
	_container.position = Vector2.ZERO
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(rect_size)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_container.add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.18
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
	light.light_energy = 2.0
	_viewport.add_child(light)

	var fill := OmniLight3D.new()
	fill.light_energy = 1.15
	fill.position = Vector3(0.0, 0.0, 2.2)
	_viewport.add_child(fill)

	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 0.0, 3.0)
	_camera.current = true
	_viewport.add_child(_camera)


func play(start_screen: Vector2, end_screen: Vector2, blast_width_px: float = 96.0, anchor_screen: Vector2 = Vector2.INF) -> void:
	if _viewport == null:
		_setup()
	_pivot = Node3D.new()
	_model = _create_model()
	_pivot.add_child(_model)
	_viewport.add_child(_pivot)

	var start_world: Vector3 = _screen_to_world(start_screen)
	var end_world: Vector3 = _screen_to_world(end_screen)
	var anchor_world: Vector3 = _screen_to_world(anchor_screen) if anchor_screen.is_finite() else (start_world + end_world) * 0.5
	var unit_dir: Vector3 = Vector3(-1.0, -1.0, 0.0).normalized()
	var perp: Vector3 = Vector3(-unit_dir.y, unit_dir.x, 0.0)
	var width_world: float = maxf(0.18, blast_width_px * _world_units_per_pixel() * 0.45)
	var hilt_world: Vector3 = anchor_world + unit_dir * width_world * 0.04 - perp * width_world * 0.04
	var z_angle: float = HILT_TO_RIGHT_UP_Z_ANGLE
	var sword_scale: float = maxf(0.74, blast_width_px * _world_units_per_pixel() * 3.15)

	_pivot.position = hilt_world
	_pivot.rotation = Vector3(0.0, 0.0, z_angle)
	_model.position = Vector3(0.0, sword_scale * 0.58, 0.0)
	_model.rotation = Vector3(deg_to_rad(92.0), 0.0, 0.0)
	_model.scale = Vector3.ONE * sword_scale

	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.72, 0.22, 0.0)
	flash.size = ViewportUtils.get_size()
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.z_index = -1
	add_child(flash)

	var windup_tw := create_tween().set_parallel(true)
	windup_tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(_model):
			return
		var clamped_t: float = clampf(t, 0.0, 1.0)
		var pull_t: float = sin(clamped_t * PI * 0.5)
		_pivot.position = hilt_world - unit_dir * pull_t * width_world * 0.10
		_pivot.rotation = Vector3(0.0, 0.0, z_angle)
		_model.rotation = Vector3(
			deg_to_rad(lerpf(92.0, 106.0, pull_t)),
			deg_to_rad(lerpf(0.0, 5.0, pull_t)),
			deg_to_rad(lerpf(0.0, -6.0, pull_t))
		)
	, 0.0, 1.0, WINDUP_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	await windup_tw.finished

	var smash_tw := create_tween().set_parallel(true)
	smash_tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(_model):
			return
		var clamped_t: float = clampf(t, 0.0, 1.0)
		var impact_t: float = 1.0 - pow(1.0 - clamped_t, 3.0)
		var settle_t: float = sin(clamped_t * PI)
		_pivot.position = hilt_world + unit_dir * lerpf(-width_world * 0.10, width_world * 0.04, impact_t)
		_pivot.rotation = Vector3(0.0, 0.0, z_angle)
		_model.rotation = Vector3(
			deg_to_rad(lerpf(106.0, 18.0, impact_t)),
			deg_to_rad(lerpf(5.0, -10.0, impact_t)),
			deg_to_rad(lerpf(-6.0, 5.0, impact_t))
		)
		_model.scale = Vector3.ONE * sword_scale * (1.0 + settle_t * 0.035)
	, 0.0, 1.0, SMASH_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUINT)
	smash_tw.tween_property(flash, "color:a", 0.22, SMASH_DURATION * 0.45).set_ease(Tween.EASE_OUT)
	smash_tw.tween_property(flash, "color:a", 0.0, SMASH_DURATION * 0.7).set_delay(SMASH_DURATION * 0.25).set_ease(Tween.EASE_IN)
	await smash_tw.finished

	finished.emit()
	var fade_tw := create_tween().set_parallel(true)
	if _container != null:
		fade_tw.tween_property(_container, "modulate:a", 0.0, FADE_OUT_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	if is_instance_valid(_pivot):
		fade_tw.tween_property(_pivot, "scale", Vector3.ONE * 0.86, FADE_OUT_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	fade_tw.tween_property(flash, "color:a", 0.0, FADE_OUT_DURATION).set_ease(Tween.EASE_IN)
	await fade_tw.finished
	_release_pivot()
	if not is_queued_for_deletion():
		queue_free()


func _screen_to_world(screen_pos: Vector2) -> Vector3:
	var screen: Vector2 = ViewportUtils.get_size()
	var cam_distance: float = 3.0
	var fov_rad: float = deg_to_rad(_camera.fov)
	var half_h: float = cam_distance * tan(fov_rad * 0.5)
	var aspect: float = screen.x / maxf(screen.y, 1.0)
	var half_w: float = half_h * aspect
	return Vector3(
		(screen_pos.x / screen.x - 0.5) * 2.0 * half_w,
		-(screen_pos.y / screen.y - 0.5) * 2.0 * half_h,
		0.0
	)


func _world_units_per_pixel() -> float:
	var screen: Vector2 = ViewportUtils.get_size()
	var cam_distance: float = 3.0
	var fov_rad: float = deg_to_rad(_camera.fov)
	var half_h: float = cam_distance * tan(fov_rad * 0.5)
	return (half_h * 2.0) / maxf(screen.y, 1.0)


func _create_model() -> Node3D:
	if ResourceLoader.exists(SWORD_SCENE_PATH):
		var scene := load(SWORD_SCENE_PATH) as PackedScene
		if scene != null:
			var instance := scene.instantiate() as Node3D
			if instance != null:
				return instance
	return _create_fallback_sword()


func _create_fallback_sword() -> Node3D:
	var root := Node3D.new()
	var blade_mat := StandardMaterial3D.new()
	blade_mat.albedo_color = Color(0.86, 0.88, 0.92, 1.0)
	blade_mat.metallic = 0.55
	blade_mat.roughness = 0.28
	var knight_texture: Texture2D = _load_knight_texture()
	if knight_texture != null:
		blade_mat.albedo_texture = knight_texture
	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = Color(0.36, 0.20, 0.08, 1.0)

	var blade_mesh := BoxMesh.new()
	blade_mesh.size = Vector3(0.10, 1.42, 0.045)
	var blade := MeshInstance3D.new()
	blade.mesh = blade_mesh
	blade.material_override = blade_mat
	blade.position = Vector3(0.0, 0.38, 0.0)
	root.add_child(blade)

	var guard_mesh := BoxMesh.new()
	guard_mesh.size = Vector3(0.44, 0.08, 0.06)
	var guard := MeshInstance3D.new()
	guard.mesh = guard_mesh
	guard.material_override = blade_mat
	guard.position = Vector3(0.0, -0.38, 0.0)
	root.add_child(guard)

	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.045
	handle_mesh.bottom_radius = 0.045
	handle_mesh.height = 0.44
	var handle := MeshInstance3D.new()
	handle.mesh = handle_mesh
	handle.material_override = handle_mat
	handle.rotation_degrees.x = 90.0
	handle.position = Vector3(0.0, -0.68, 0.0)
	root.add_child(handle)
	return root


func _load_knight_texture() -> Texture2D:
	if ResourceLoader.exists(KNIGHT_TEXTURE_PATH):
		var texture := load(KNIGHT_TEXTURE_PATH) as Texture2D
		if texture != null:
			return texture
	var image := Image.new()
	if image.load(KNIGHT_TEXTURE_PATH) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _exit_tree() -> void:
	_release_pivot()


func _release_pivot() -> void:
	if is_instance_valid(_pivot):
		_pivot.queue_free()
	_pivot = null
	_model = null
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
