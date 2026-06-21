extends Node2D
class_name BattleVfx3DLayer

const CAMERA_DISTANCE := 5.2
const VIEWPORT_PADDING := 80.0

var container: SubViewportContainer = null
var viewport: SubViewport = null
var camera: Camera3D = null
var _active_nodes: Dictionary = {}


func _ready() -> void:
	z_index = 94
	_ensure_viewport()
	set_process(true)


func _process(_delta: float) -> void:
	_sync_viewport_size()


func add_world_node(node: Node3D) -> void:
	if node == null:
		return
	_ensure_viewport()
	if node.get_parent() != viewport:
		viewport.add_child(node)
	_active_nodes[node.get_instance_id()] = node
	_update_render_mode()


func remove_world_node(node: Node3D) -> void:
	if node == null:
		return
	_active_nodes.erase(node.get_instance_id())
	if is_instance_valid(node):
		node.queue_free()
	_update_render_mode()


func screen_to_world(screen_pos: Vector2) -> Vector3:
	_ensure_viewport()
	var view_size: Vector2 = container.size if container != null else ViewportUtils.get_size()
	var local_pos := screen_pos + Vector2(VIEWPORT_PADDING, VIEWPORT_PADDING)
	var fov_rad: float = deg_to_rad(camera.fov if camera != null else 75.0)
	var half_h: float = CAMERA_DISTANCE * tan(fov_rad * 0.5)
	var aspect: float = view_size.x / maxf(view_size.y, 1.0)
	var half_w: float = half_h * aspect
	return Vector3(
		(local_pos.x / view_size.x - 0.5) * 2.0 * half_w,
		-(local_pos.y / view_size.y - 0.5) * 2.0 * half_h,
		0.0
	)


func world_units_per_pixel() -> float:
	_ensure_viewport()
	var view_size: Vector2 = container.size if container != null else ViewportUtils.get_size()
	var fov_rad: float = deg_to_rad(camera.fov if camera != null else 75.0)
	var half_h: float = CAMERA_DISTANCE * tan(fov_rad * 0.5)
	return (half_h * 2.0) / maxf(view_size.y, 1.0)


func _ensure_viewport() -> void:
	if container != null and viewport != null and camera != null:
		return
	var rect_size: Vector2 = ViewportUtils.get_size()
	position = Vector2.ZERO

	container = SubViewportContainer.new()
	container.name = "BattleVfx3DViewport"
	container.size = rect_size + Vector2(VIEWPORT_PADDING * 2.0, VIEWPORT_PADDING * 2.0)
	container.position = Vector2(-VIEWPORT_PADDING, -VIEWPORT_PADDING)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)

	viewport = SubViewport.new()
	viewport.size = Vector2i(container.size)
	viewport.transparent_bg = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	container.add_child(viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.12
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35.0, -25.0, 0.0)
	light.light_energy = 1.6
	viewport.add_child(light)

	camera = Camera3D.new()
	camera.position = Vector3(0.0, 0.0, CAMERA_DISTANCE)
	camera.current = true
	viewport.add_child(camera)


func _sync_viewport_size() -> void:
	if container == null or viewport == null:
		return
	var target_size := ViewportUtils.get_size() + Vector2(VIEWPORT_PADDING * 2.0, VIEWPORT_PADDING * 2.0)
	if container.size == target_size:
		return
	container.size = target_size
	container.position = Vector2(-VIEWPORT_PADDING, -VIEWPORT_PADDING)
	viewport.size = Vector2i(target_size)


func _update_render_mode() -> void:
	if viewport == null:
		return
	for key in _active_nodes.keys():
		var node: Variant = _active_nodes[key]
		if not is_instance_valid(node):
			_active_nodes.erase(key)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if not _active_nodes.is_empty() else SubViewport.UPDATE_DISABLED

