## StageButton（世界地圖關卡按鈕）— 可在編輯器中拖放並擺放於世界地圖上。
## 透過 `stage` 屬性綁定 StageData；按下時 emit `stage_pressed(stage)`。
## 解鎖規則：若 `stage.prerequisite_stage_id` 已通關才會顯示。
## 「最新可玩」關卡會在 spot 後方顯示旋轉光錐。
@tool
class_name StageButton
extends Control

signal stage_pressed(stage: StageData)
signal stage_edit_pressed(stage: StageData)

const RAY_BURST_SCRIPT := preload("res://scripts/ray_burst.gd")
## Spot 圖佔總高度的比例（其餘空間留給下方關卡名稱）
const SPOT_HEIGHT_RATIO: float = 0.62
const SPOT_DISPLAY_SCALE: float = 1.5
const SPOT_BACKDROP_PAD: float = 12.0
const SPOT_GLOW_PAD: float = 8.0
const SPOT_LOCKED_TINT: Color = Color(0.42, 0.42, 0.46, 0.68)
const SPOT_GLOW_TINT: Color = Color(1.0, 0.92, 0.25, 0.0)
const LATEST_RAY_COLOR: Color = Color(1.0, 0.93, 0.22, 0.76)
const CAPTION_BG_HEIGHT_RATIO: float = 0.4
const EDIT_BUTTON_SIZE: Vector2 = Vector2(42, 28)

## 綁定的關卡資料（必填）
@export var stage: StageData = null:
	set(value):
		stage = value
		if is_inside_tree():
			_refresh()

## 按鈕大小（控制顯示尺寸；預設為橢圓比例）
@export var button_size: Vector2 = Vector2(140, 110):
	set(value):
		button_size = value
		custom_minimum_size = value
		size = value
		if is_inside_tree():
			_layout()

## 已通關時的色調
@export var cleared_tint: Color = Color(1, 1, 1, 1.0)
## 可玩（已解鎖未通關）的色調
@export var available_tint: Color = Color(1, 1, 1, 1)

var _btn: Button = null
var _edit_btn: Button = null
var _label: Label = null
var _label_bg: TextureRect = null
var _is_latest: bool = false
var _spot_backdrop: TextureRect = null
var _spot_rect: TextureRect = null
var _spot_glow: TextureRect = null
var _glow_tween: Tween = null
var _rays: Node2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = button_size
	size = button_size
	_build()
	_refresh()


func _build() -> void:
	if _btn != null:
		return
	var spot_h: float = button_size.y * SPOT_HEIGHT_RATIO

	_spot_backdrop = TextureRect.new()
	_spot_backdrop.name = "SpotBackdrop"
	_spot_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spot_backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_spot_backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	_spot_backdrop.texture = _make_spot_backdrop_texture()
	add_child(_spot_backdrop)

	_spot_glow = TextureRect.new()
	_spot_glow.name = "SpotGlow"
	_spot_glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spot_glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_spot_glow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_spot_glow.modulate = SPOT_GLOW_TINT
	add_child(_spot_glow)

	_rays = Node2D.new()
	_rays.name = "CurrentStageRays"
	_rays.set_script(RAY_BURST_SCRIPT)
	_rays.set("ray_color", LATEST_RAY_COLOR)
	_rays.set("ray_count", 6)
	_rays.set("ray_half_angle", 0.24)
	_rays.set("rotation_speed", 0.55)
	_rays.visible = false
	add_child(_rays)

	_spot_rect = TextureRect.new()
	_spot_rect.name = "Spot"
	_spot_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spot_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_spot_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(_spot_rect)

	# 透明 Button：吸收點擊（覆蓋於 spot 上方）
	_btn = Button.new()
	_btn.name = "Btn"
	_btn.flat = true
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.add_theme_font_size_override("font_size", 0)
	_btn.position = Vector2(0, 0)
	_btn.size = Vector2(button_size.x, spot_h)
	# 套用全透明 stylebox（避免 Button 預設 panel 干擾）
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxEmpty.new()
		_btn.add_theme_stylebox_override(state, sb)
	add_child(_btn)
	if not Engine.is_editor_hint():
		_btn.pressed.connect(_on_pressed)
		_btn.mouse_entered.connect(_on_hover_enter)
		_btn.mouse_exited.connect(_on_hover_exit)

	_edit_btn = Button.new()
	_edit_btn.name = "EditBtn"
	_edit_btn.text = "Edit"
	_edit_btn.focus_mode = Control.FOCUS_NONE
	_edit_btn.tooltip_text = "Edit stage layout"
	_edit_btn.custom_minimum_size = EDIT_BUTTON_SIZE
	_edit_btn.add_theme_font_size_override("font_size", 11)
	add_child(_edit_btn)
	if not Engine.is_editor_hint():
		_edit_btn.pressed.connect(_on_edit_pressed)

	# 關卡名稱標籤背景（仿戰鬥場景敵人意圖：黑色漸層 0→0.5→0）
	_label_bg = TextureRect.new()
	_label_bg.name = "CaptionBG"
	_label_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label_bg.stretch_mode = TextureRect.STRETCH_SCALE
	# 仿戰鬥場景敵人意圖：兩端透明、中央深色（加深至 0.78 以在彩色地圖上更清楚）
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(0, 0, 0, 0),
		Color(0, 0, 0, 0.78),
		Color(0, 0, 0, 0),
	])
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0, 0.5)
	grad_tex.fill_to = Vector2(1, 0.5)
	grad_tex.width = 64
	grad_tex.height = 1
	_label_bg.texture = grad_tex
	add_child(_label_bg)

	# 關卡名稱標籤：位於 spot 下方（保持原始字型大小）
	_label = Label.new()
	_label.name = "Caption"
	_label.position = Vector2(0, spot_h + 2.0)
	_label.size = Vector2(button_size.x, button_size.y - spot_h - 2.0)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override("outline_size", 4)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	# 初始化完成後立即套用正確的位置與尺寸
	_layout()


func _make_spot_backdrop_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	gradient.colors = PackedColorArray([
		Color(0, 0, 0, 0.62),
		Color(0, 0, 0, 0.36),
		Color(0, 0, 0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 192
	texture.height = 128
	return texture


func _layout() -> void:
	var spot_h: float = button_size.y * SPOT_HEIGHT_RATIO
	var spot_display_size: Vector2 = Vector2(button_size.x * SPOT_DISPLAY_SCALE, spot_h * SPOT_DISPLAY_SCALE)
	var spot_display_pos: Vector2 = Vector2(
		(button_size.x - spot_display_size.x) * 0.5,
		(spot_h - spot_display_size.y) * 0.5
	)
	if _spot_backdrop != null:
		var backdrop_pad: Vector2 = Vector2(SPOT_BACKDROP_PAD, SPOT_BACKDROP_PAD)
		_spot_backdrop.position = spot_display_pos - backdrop_pad
		_spot_backdrop.size = spot_display_size + backdrop_pad * 2.0
	if _spot_glow != null:
		_spot_glow.position = spot_display_pos - Vector2(SPOT_GLOW_PAD, SPOT_GLOW_PAD)
		_spot_glow.size = spot_display_size + Vector2(SPOT_GLOW_PAD * 2.0, SPOT_GLOW_PAD * 2.0)
	if _spot_rect != null:
		_spot_rect.position = spot_display_pos
		_spot_rect.size = spot_display_size
	if _btn != null:
		_btn.position = spot_display_pos
		_btn.size = spot_display_size
	if _edit_btn != null:
		var edit_y: float = max(0.0, (spot_h - EDIT_BUTTON_SIZE.y) * 0.5)
		_edit_btn.position = Vector2(0.0, edit_y)
		_edit_btn.size = EDIT_BUTTON_SIZE
	if _label_bg != null:
		var caption_h: float = button_size.y - spot_h
		var bg_h: float = caption_h * CAPTION_BG_HEIGHT_RATIO
		_label_bg.position = Vector2(0, spot_h + (caption_h - bg_h) * 0.5)
		_label_bg.size = Vector2(button_size.x, bg_h)
	if _label != null:
		_label.position = Vector2(0, spot_h + 2.0)
		_label.size = Vector2(button_size.x, button_size.y - spot_h - 2.0)
		_label.add_theme_font_size_override("font_size", 18)
	if _rays != null:
		_rays.position = Vector2(button_size.x * 0.5, spot_h * 0.5)
		_rays.set("outer_radius", maxf(spot_display_size.x * 0.42, spot_display_size.y * 0.82))
		_rays.queue_redraw()


## 由父層 (map.gd) 在解鎖狀態變動時呼叫，重新整理可見性與標記
func refresh_state() -> void:
	_refresh()


## 回傳 spot 中心在本地座標中的位置（供地圖路徑層對齊用）。
func get_anchor_center() -> Vector2:
	var spot_h: float = button_size.y * SPOT_HEIGHT_RATIO
	return Vector2(button_size.x * 0.5, spot_h * 0.5)


func is_unlocked_for_play() -> bool:
	if stage == null:
		return false
	if Engine.is_editor_hint():
		return true
	var prereq: String = stage.prerequisite_stage_id
	return prereq == "" or GameState.is_stage_cleared(prereq)


func _refresh() -> void:
	if _btn == null:
		return
	if stage == null:
		_btn.text = ""
		_btn.disabled = true
		if _spot_backdrop != null:
			_spot_backdrop.visible = false
		if _spot_rect != null:
			_spot_rect.texture = null
		if _spot_glow != null:
			_spot_glow.texture = null
			_spot_glow.modulate = SPOT_GLOW_TINT
		if _edit_btn != null:
			_edit_btn.visible = false
		visible = true
		if _label != null:
			_label.text = ""
		if _rays != null:
			_rays.visible = false
		return

	var sid: String = stage.stage_id
	var in_editor: bool = Engine.is_editor_hint()
	var unlocked: bool = is_unlocked_for_play()
	var cleared: bool = not in_editor and GameState.is_stage_cleared(sid)
	if not in_editor and not unlocked:
		visible = false
		_btn.disabled = true
		if _spot_backdrop != null:
			_spot_backdrop.visible = false
		if _rays != null:
			_rays.visible = false
		if _spot_glow != null:
			_spot_glow.modulate = SPOT_GLOW_TINT
		return

	visible = true
	_btn.text = ""
	_btn.disabled = not unlocked
	_btn.modulate = cleared_tint if cleared else available_tint
	if _spot_backdrop != null:
		_spot_backdrop.visible = true
	var spot_texture: Texture2D = load(StageData.get_stage_spot_path(stage.area)) as Texture2D
	if _spot_rect != null:
		_spot_rect.texture = spot_texture
		_spot_rect.modulate = _get_spot_tint(unlocked, cleared)
	if _spot_glow != null:
		_spot_glow.texture = spot_texture
		var glow_alpha: float = _spot_glow.modulate.a
		_spot_glow.modulate = Color(SPOT_GLOW_TINT.r, SPOT_GLOW_TINT.g, SPOT_GLOW_TINT.b, glow_alpha)
	if _edit_btn != null:
		_edit_btn.visible = not in_editor
		_edit_btn.disabled = false
	if _label != null:
		_label.text = sid
	# 未通關時由 set_latest 控制光錐。
	if cleared and _rays != null:
		_rays.visible = false


func _get_spot_tint(unlocked: bool, cleared: bool) -> Color:
	if cleared:
		return cleared_tint
	if unlocked:
		return available_tint
	return SPOT_LOCKED_TINT


func set_latest(latest: bool) -> void:
	_is_latest = latest
	# 通關後不顯示最新關卡光錐。
	var cleared: bool = stage != null and not Engine.is_editor_hint() \
		and GameState.is_stage_cleared(stage.stage_id)
	var show_rays: bool = latest and visible and is_unlocked_for_play() and not cleared
	if _rays != null:
		_rays.visible = show_rays


func _on_pressed() -> void:
	if stage == null:
		return
	if not is_unlocked_for_play():
		return
	stage_pressed.emit(stage)


func _on_edit_pressed() -> void:
	if stage == null:
		return
	stage_edit_pressed.emit(stage)


func _on_hover_enter() -> void:
	if _spot_glow == null or stage == null:
		return
	if not is_unlocked_for_play():
		return
	_fade_glow(1.0, 0.12)


func _on_hover_exit() -> void:
	if _spot_glow == null:
		return
	_fade_glow(0.0, 0.18)


func _fade_glow(target_alpha: float, duration: float) -> void:
	if _spot_glow == null:
		return
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = create_tween()
	_glow_tween.tween_property(_spot_glow, "modulate:a", target_alpha, duration)
