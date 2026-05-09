## MeteorVFX（隕石特效）— 從天空（西南方向）落向棋盤的 3D 火球。
## 使用 SubViewport 渲染 fireball.gltf。落地時發出 landed 信號並自我釋放。
extends Node2D

const FIREBALL_PATH := "res://assets/3d/fireball.gltf"

signal landed  ## 隕石落地時發出

const FALL_DURATION := 0.65  # 落下時間（秒）

var _container: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera3D
var _model: Node3D
var _tween: Tween


## 建立 SubViewport / Camera / Environment
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
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_container.add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.glow_enabled = true
	env.glow_intensity = 1.4
	env.glow_bloom = 0.4
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	# 補光，避免模型過暗
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.5
	_viewport.add_child(light)

	_camera = Camera3D.new()
	_camera.position = Vector3(0, 0, 3.0)
	_viewport.add_child(_camera)


## 在指定螢幕座標 at_screen 落下隕石。await 直到落地。
func play(at_screen: Vector2) -> void:
	if _viewport == null:
		_setup()

	# ── 2D → 3D 座標映射 ──
	var screen: Vector2 = ViewportUtils.get_size()
	var cam_distance: float = 3.0
	var fov_rad: float = deg_to_rad(_camera.fov)
	var half_h_3d: float = cam_distance * tan(fov_rad * 0.5)
	var aspect: float = screen.x / screen.y
	var half_w_3d: float = half_h_3d * aspect

	var target_3d := Vector3(
		(at_screen.x / screen.x - 0.5) * 2.0 * half_w_3d,
		-(at_screen.y / screen.y - 0.5) * 2.0 * half_h_3d,
		0.0
	)
	# 起始位置：高空 + 西方 + 南方（朝向相機，+Z）
	var start_3d: Vector3 = target_3d + Vector3(-1.4, 1.8, 1.2)

	# 嘗試載入 GLTF；失敗時 fallback 到發光球體（確保畫面一定有東西）
	var loaded_ok: bool = false
	if ResourceLoader.exists(FIREBALL_PATH):
		var FireballScene: PackedScene = load(FIREBALL_PATH)
		if FireballScene != null:
			_model = FireballScene.instantiate()
			_model.scale = Vector3(0.6, 0.6, 0.6)
			loaded_ok = true
		else:
			push_warning("MeteorVFX: fireball.gltf load() returned null; using fallback sphere.")
	else:
		push_warning("MeteorVFX: fireball.gltf not found; using fallback sphere.")

	if not loaded_ok:
		_model = Node3D.new()
		var mesh_inst := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.3
		sphere.height = 0.6
		mesh_inst.mesh = sphere
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.5, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.4, 0.05)
		mat.emission_energy_multiplier = 4.0
		mesh_inst.material_override = mat
		_model.add_child(mesh_inst)

	_model.position = start_3d
	_viewport.add_child(_model)

	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_model, "position", target_3d, FALL_DURATION) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(_model, "rotation", Vector3(0, TAU * 1.5, TAU * 0.8), FALL_DURATION) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_LINEAR)

	await _tween.finished

	# 落地閃光：模型快速放大後消失
	var flash_tw := create_tween().set_parallel(true)
	flash_tw.tween_property(_model, "scale", Vector3(1.6, 1.6, 1.6), 0.15) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	landed.emit()
	await flash_tw.finished
	queue_free()
