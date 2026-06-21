extends Control
class_name GoldCoin3DProxy

var vfx_layer: BattleVfx3DLayer = null
var pixel_size: int = 72
var animate_spin: bool = true
var coin_root: Node3D = null
var coin_material: StandardMaterial3D = null
var coin_label: Label3D = null
var _last_alpha: float = -1.0

const MODEL_DIAMETER := 1.64
const WORLD_SIZE_CALIBRATION := 0.36


func configure(layer: BattleVfx3DLayer, p_pixel_size: int, p_animate_spin: bool = true) -> void:
	vfx_layer = layer
	pixel_size = p_pixel_size
	animate_spin = p_animate_spin
	custom_minimum_size = Vector2(pixel_size, pixel_size)
	size = Vector2(pixel_size, pixel_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_create_coin()
	set_process(true)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(coin_root != null)


func _process(delta: float) -> void:
	if coin_root == null or not is_instance_valid(coin_root) or vfx_layer == null:
		return
	var rect := get_global_rect()
	var alpha := _get_inherited_canvas_alpha()
	_apply_alpha(alpha)
	coin_root.visible = is_visible_in_tree() and alpha > 0.01
	coin_root.global_position = vfx_layer.screen_to_world(rect.get_center())
	var transform_scale := get_global_transform().get_scale()
	var visual_scale: float = maxf(0.01, (absf(transform_scale.x) + absf(transform_scale.y)) * 0.5)
	var target_world_diameter: float = float(pixel_size) * visual_scale * vfx_layer.world_units_per_pixel() * WORLD_SIZE_CALIBRATION
	var scale_value: float = target_world_diameter / MODEL_DIAMETER
	coin_root.scale = Vector3(scale_value, scale_value, scale_value)
	if animate_spin:
		coin_root.rotation_degrees.y = fmod(coin_root.rotation_degrees.y + delta * 500.0, 360.0)


func release_3d_coin() -> void:
	set_process(false)
	if is_instance_valid(coin_root):
		coin_root.visible = false
	if is_instance_valid(vfx_layer) and coin_root != null:
		vfx_layer.remove_world_node(coin_root)
	elif is_instance_valid(coin_root):
		coin_root.queue_free()
	coin_root = null
	coin_material = null
	coin_label = null


func _get_inherited_canvas_alpha() -> float:
	var alpha: float = modulate.a * self_modulate.a
	var node := get_parent()
	while node != null:
		if node is CanvasItem:
			var canvas_item := node as CanvasItem
			alpha *= canvas_item.modulate.a * canvas_item.self_modulate.a
		node = node.get_parent()
	return clampf(alpha, 0.0, 1.0)


func _apply_alpha(alpha: float) -> void:
	if absf(alpha - _last_alpha) < 0.01:
		return
	_last_alpha = alpha
	if coin_material != null:
		var color := coin_material.albedo_color
		color.a = alpha
		coin_material.albedo_color = color
	if is_instance_valid(coin_label):
		var label_color := coin_label.modulate
		label_color.a = alpha
		coin_label.modulate = label_color
		var outline_color := coin_label.outline_modulate
		outline_color.a = alpha
		coin_label.outline_modulate = outline_color


func _exit_tree() -> void:
	release_3d_coin()


func _create_coin() -> void:
	if vfx_layer == null:
		return
	if coin_root != null and is_instance_valid(coin_root):
		return
	coin_root = Node3D.new()
	coin_root.name = "LootGoldCoin3D"

	coin_material = StandardMaterial3D.new()
	coin_material.albedo_color = Color(1.0, 0.72, 0.08, 1.0)
	coin_material.metallic = 0.75
	coin_material.roughness = 0.24
	coin_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var coin_mesh := CylinderMesh.new()
	coin_mesh.top_radius = 0.82
	coin_mesh.bottom_radius = 0.82
	coin_mesh.height = 0.16
	coin_mesh.radial_segments = 64
	var coin := MeshInstance3D.new()
	coin.name = "CoinMesh"
	coin.mesh = coin_mesh
	coin.material_override = coin_material
	coin.rotation_degrees.x = 90.0
	coin_root.add_child(coin)

	coin_label = Label3D.new()
	coin_label.name = "CoinMark"
	coin_label.text = "$"
	coin_label.font_size = 72
	coin_label.modulate = Color(1.0, 0.94, 0.42, 1.0)
	coin_label.outline_modulate = Color(0.38, 0.20, 0.02, 1.0)
	coin_label.outline_size = 8
	coin_label.position = Vector3(0.0, 0.0, 0.11)
	coin_root.add_child(coin_label)

	vfx_layer.add_world_node(coin_root)
