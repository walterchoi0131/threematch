## GemParticle（寶石粒子）— 從消除的寶石飛向角色卡片的 VFX 粒子。
## 使用 SubViewport 渲染 3D VFX。支援物件池：viewport 基礎設施只建立一次，
## launch() 可重複呼叫以重用同一節點。
extends Node2D

const BlastVFXScene := preload("res://assets/BinbunVFX/loot_effects/effects/floating/loot_vfx_epic.tscn")

const SCREEN_W := 856.0
const SCREEN_H := 1024.0

signal released  ## 飛行結束、可被池回收時發出

var is_available := true

var _container: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera3D
var _vfx: Node3D
var _tween: Tween


## 建立 SubViewport / Camera / Environment（只在池初始化時呼叫一次）
func setup() -> void:
	var rect_size := Vector2(SCREEN_W, SCREEN_H)
	position = Vector2.ZERO

	_container = SubViewportContainer.new()
	_container.size = rect_size
	_container.position = Vector2.ZERO
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_container.visible = false

	_viewport = SubViewport.new()
	_viewport.size = Vector2i(rect_size)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_container.add_child(_viewport)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.glow_enabled = true
	env.glow_intensity = 1.2
	env.glow_bloom = 0.3
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_viewport.add_child(world_env)

	var cam_distance := 3.0
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 0, cam_distance)
	_viewport.add_child(_camera)

	add_child(_container)


## 發射粒子：從 from 到 to（全域 2D 座標），帶拖尾效果
## spread: -1.0～+1.0，控制弧線偏向左或右
func launch(from: Vector2, to: Vector2, color: Color, duration: float = 0.35, spread: float = 0.0) -> void:
	is_available = false
	duration = duration / 2.0  # 速度加快 200%

	if _viewport == null:
		setup()

	# 中止殘留的 tween
	if _tween and _tween.is_valid():
		_tween.kill()

	# 清除舊 VFX 實例
	if _vfx:
		_vfx.queue_free()
		_vfx = null

	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_container.visible = true

	# ── 2D 像素 → 3D 座標 ──
	var cam_distance := 3.0
	var fov_rad: float = deg_to_rad(_camera.fov)
	var half_h_3d: float = cam_distance * tan(fov_rad * 0.5)
	var aspect: float = SCREEN_W / SCREEN_H
	var half_w_3d: float = half_h_3d * aspect

	var from_3d := Vector3(
		(from.x / SCREEN_W - 0.5) * 2.0 * half_w_3d,
		-(from.y / SCREEN_H - 0.5) * 2.0 * half_h_3d,
		0.0
	)
	var to_3d := Vector3(
		(to.x / SCREEN_W - 0.5) * 2.0 * half_w_3d,
		-(to.y / SCREEN_H - 0.5) * 2.0 * half_h_3d,
		0.0
	)

	# ── VFX 實例 ──
	_vfx = BlastVFXScene.instantiate()
	_vfx.position = from_3d
	_vfx.scale = Vector3(1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0)

	# 複製材質使每個實例獨立
	for child in _vfx.get_children():
		if (child is MeshInstance3D or child is GPUParticles3D) and child.material_override != null:
			child.material_override = child.material_override.duplicate()

	_viewport.add_child(_vfx)

	_vfx.set("primary_color", color)
	_vfx.set("secondary_color", color.darkened(0.4))
	_vfx.set("light_color", color)

	for child in _vfx.get_children():
		if child is GPUParticles3D:
			child.local_coords = false

	# ── 拋物線弧線動畫 ──
	var dir_3d: Vector3 = to_3d - from_3d
	var perp := Vector3(-dir_3d.y, dir_3d.x, 0.0).normalized()
	var side: float = spread
	var backswing := from_3d - dir_3d.normalized() * dir_3d.length() * 0.25 + perp * dir_3d.length() * 0.3 * side

	_tween = create_tween()
	_tween.tween_property(_vfx, "position", backswing, duration * 0.25) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_method(func(t: float) -> void:
		var mid_ctrl: Vector3 = (backswing + to_3d) * 0.5 + perp * dir_3d.length() * 0.4 * side
		var a: Vector3 = backswing.lerp(mid_ctrl, t)
		var b: Vector3 = mid_ctrl.lerp(to_3d, t)
		if _vfx:
			_vfx.position = a.lerp(b, t)
	, 0.0, 1.0, duration * 0.75).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_callback(_on_flight_done)


func _on_flight_done() -> void:
	if _vfx:
		_vfx.queue_free()
		_vfx = null
	_container.visible = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	is_available = true
	released.emit()


## 強制回收（用於場景切換等清理）
func force_release() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	if _vfx:
		_vfx.queue_free()
		_vfx = null
	_container.visible = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	is_available = true
