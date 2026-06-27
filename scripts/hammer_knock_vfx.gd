class_name HammerKnockVfx
extends Node2D

signal finished
signal heavy_impact

const HAMMER_SCENE_PATH := "res://assets/kaykit_vfx/hammer_A.gltf"
const WEAPON_TEXTURE_PATH := "res://assets/kaykit_vfx/weapons_bits_texture.png"
const LIGHT_RAISE_DURATION := 0.16
const LIGHT_KNOCK_DURATION := 0.26
const HEAVY_RAISE_DURATION := 0.24
const HEAVY_KNOCK_DURATION := 0.30
const IMPACT_HOLD := 0.16

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
	env.glow_intensity = 0.45
	env.glow_bloom = 0.14
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-55.0, -34.0, 0.0)
	key_light.light_energy = 2.15
	_viewport.add_child(key_light)

	var fill := OmniLight3D.new()
	fill.light_energy = 1.25
	fill.position = Vector3(0.0, 0.0, 2.4)
	_viewport.add_child(fill)

	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, 0.0, 3.0)
	_camera.current = true
	_viewport.add_child(_camera)


func play_at(target_screen: Vector2, cell_size_px: float = 64.0) -> void:
	if _viewport == null:
		_setup()
	_pivot = Node3D.new()
	_model = _create_model()
	_pivot.add_child(_model)
	_viewport.add_child(_pivot)

	var target_world: Vector3 = _screen_to_world(target_screen)
	var unit_px: float = _world_units_per_pixel()
	var cell_world: float = maxf(0.24, cell_size_px * unit_px)
	var handle_pivot_pos := target_world + Vector3(cell_world * 1.28, cell_world * 0.24, 0.0)
	var windup_pos := handle_pivot_pos + Vector3(cell_world * 0.04, cell_world * 0.04, 0.10)
	var light_raised_pos := handle_pivot_pos + Vector3(cell_world * 0.02, cell_world * 0.03, 0.12)
	var light_impact_pos := handle_pivot_pos
	var heavy_raised_pos := handle_pivot_pos + Vector3(cell_world * 0.03, cell_world * 0.05, 0.14)
	var impact_pos := handle_pivot_pos
	var hammer_scale: float = maxf(0.30, cell_world * 1.15)

	_pivot.position = windup_pos
	_pivot.rotation = Vector3(0.0, 0.0, deg_to_rad(8.0))
	_model.position = Vector3(0.0, 0.40 * hammer_scale, 0.0)
	_model.rotation = Vector3.ZERO
	_model.scale = Vector3.ONE * hammer_scale

	var tw := create_tween().set_parallel(true)
	tw.tween_property(_pivot, "position", light_raised_pos, LIGHT_RAISE_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_pivot, "rotation", Vector3(0.0, 0.0, deg_to_rad(-4.0)), LIGHT_RAISE_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	await tw.finished

	var light_knock_tw := create_tween().set_parallel(true)
	light_knock_tw.tween_property(_pivot, "position", light_impact_pos, LIGHT_KNOCK_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	light_knock_tw.tween_property(_pivot, "rotation", Vector3(0.0, 0.0, deg_to_rad(70.0)), LIGHT_KNOCK_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	await light_knock_tw.finished
	_play_impact_2d(target_screen, cell_size_px * 0.62)

	var heavy_raise_tw := create_tween().set_parallel(true)
	heavy_raise_tw.tween_property(_pivot, "position", heavy_raised_pos, HEAVY_RAISE_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	heavy_raise_tw.tween_property(_pivot, "rotation", Vector3(0.0, 0.0, deg_to_rad(-10.0)), HEAVY_RAISE_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	await heavy_raise_tw.finished

	var heavy_knock_tw := create_tween().set_parallel(true)
	heavy_knock_tw.tween_property(_pivot, "position", impact_pos, HEAVY_KNOCK_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUINT)
	heavy_knock_tw.tween_property(_pivot, "rotation", Vector3(0.0, 0.0, deg_to_rad(92.0)), HEAVY_KNOCK_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUINT)
	await heavy_knock_tw.finished

	heavy_impact.emit()
	_play_impact_2d(target_screen, cell_size_px)

	var recoil_tw := create_tween().set_parallel(true)
	recoil_tw.tween_property(_pivot, "position", handle_pivot_pos + Vector3(cell_world * 0.01, cell_world * 0.04, 0.0), IMPACT_HOLD).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	recoil_tw.tween_property(_pivot, "rotation", Vector3(0.0, 0.0, deg_to_rad(84.0)), IMPACT_HOLD).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	await recoil_tw.finished

	finished.emit()
	var fade_tw := create_tween().set_parallel(true)
	fade_tw.tween_property(_container, "modulate:a", 0.0, 0.10)
	if is_instance_valid(_pivot):
		fade_tw.tween_property(_pivot, "scale", _pivot.scale * 0.94, 0.10)
	await fade_tw.finished
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_pivot):
		_pivot.queue_free()
	_pivot = null
	_model = null
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _play_impact_2d(target_screen: Vector2, cell_size_px: float) -> void:
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.78, 0.22, 0.48)
	flash.size = Vector2.ONE * cell_size_px * 1.32
	flash.position = target_screen - flash.size * 0.5
	flash.pivot_offset = flash.size * 0.5
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.rotation = deg_to_rad(45.0)
	add_child(flash)

	var tw := create_tween().set_parallel(true)
	tw.tween_property(flash, "scale", Vector2.ONE * 1.85, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(flash, "color:a", 0.0, 0.22).set_ease(Tween.EASE_IN)

	var shard_colors: Array[Color] = [
		Color(1.0, 0.64, 0.18, 0.95),
		Color(1.0, 0.92, 0.38, 0.95),
		Color(0.78, 0.42, 0.13, 0.92)
	]
	for i in range(16):
		var shard := ColorRect.new()
		shard.color = shard_colors[i % shard_colors.size()]
		shard.size = Vector2(cell_size_px * 0.16, cell_size_px * 0.055)
		shard.position = target_screen - shard.size * 0.5
		shard.pivot_offset = shard.size * 0.5
		shard.rotation = TAU * float(i) / 16.0
		shard.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shard)

		var dir := Vector2.RIGHT.rotated(TAU * float(i) / 16.0)
		tw.tween_property(shard, "position", shard.position + dir * cell_size_px * 0.78, 0.24).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(shard, "color:a", 0.0, 0.24).set_ease(Tween.EASE_IN)
		tw.tween_callback(shard.queue_free).set_delay(0.24)
	tw.tween_callback(flash.queue_free).set_delay(0.22)


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
	if ResourceLoader.exists(HAMMER_SCENE_PATH):
		var scene := load(HAMMER_SCENE_PATH) as PackedScene
		if scene != null:
			var instance := scene.instantiate() as Node3D
			if instance != null:
				return instance
	return _create_fallback_hammer()


func _create_fallback_hammer() -> Node3D:
	var root := Node3D.new()
	var metal_mat := StandardMaterial3D.new()
	metal_mat.albedo_color = Color(0.80, 0.78, 0.70, 1.0)
	metal_mat.metallic = 0.15
	metal_mat.roughness = 0.42
	var weapon_texture: Texture2D = _load_weapon_texture()
	if weapon_texture != null:
		metal_mat.albedo_texture = weapon_texture
	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = Color(0.42, 0.25, 0.10, 1.0)
	handle_mat.roughness = 0.6

	var head_mesh := BoxMesh.new()
	head_mesh.size = Vector3(0.48, 0.30, 0.30)
	var head := MeshInstance3D.new()
	head.mesh = head_mesh
	head.material_override = metal_mat
	head.position = Vector3(0.0, 0.50, 0.0)
	root.add_child(head)

	var cap_mesh := BoxMesh.new()
	cap_mesh.size = Vector3(0.18, 0.42, 0.34)
	for x in [-0.31, 0.31]:
		var cap := MeshInstance3D.new()
		cap.mesh = cap_mesh
		cap.material_override = metal_mat
		cap.position = Vector3(x, 0.50, 0.0)
		root.add_child(cap)

	var handle_mesh := CylinderMesh.new()
	handle_mesh.top_radius = 0.045
	handle_mesh.bottom_radius = 0.06
	handle_mesh.height = 1.12
	var handle := MeshInstance3D.new()
	handle.mesh = handle_mesh
	handle.material_override = handle_mat
	handle.rotation_degrees.x = 0.0
	handle.position = Vector3(0.0, -0.14, 0.0)
	root.add_child(handle)
	return root


func _load_weapon_texture() -> Texture2D:
	if ResourceLoader.exists(WEAPON_TEXTURE_PATH):
		var texture := load(WEAPON_TEXTURE_PATH) as Texture2D
		if texture != null:
			return texture
	var image := Image.new()
	if image.load(WEAPON_TEXTURE_PATH) != OK:
		return null
	return ImageTexture.create_from_image(image)
