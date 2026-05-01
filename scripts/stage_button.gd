## StageButton（世界地圖關卡按鈕）— 可在編輯器中拖放並擺放於世界地圖上。
## 透過 `stage` 屬性綁定 StageData；按下時 emit `stage_pressed(stage)`。
## 解鎖規則：若 `stage.prerequisite_stage_id` 已通關才會顯示。
## 「最新可玩」關卡會顯示一個跳動的黃色「!」標記。
@tool
class_name StageButton
extends Control

signal stage_pressed(stage: StageData)

const FLAG_TEXTURE_PATH: String = "res://assets/flag.png"
const FLAG_HFRAMES: int = 5
const FLAG_FRAME_TIME: float = 0.18
## 橢圓佔總高度的比例（其餘空間留給下方關卡名稱）
const OVAL_HEIGHT_RATIO: float = 0.62
## 橢圓本體相對按鈕區域再縮小的比例（0.5 = 半徑）
const OVAL_SCALE: float = 0.5
## 橢圓填色：未通關橘色、已通關淺綠
const OVAL_FILL_AVAILABLE: Color = Color(0.94, 0.62, 0.18, 1.0)
const OVAL_FILL_CLEARED: Color = Color(0.61, 0.90, 0.61, 1.0)
const OVAL_BORDER: Color = Color(0.24, 0.16, 0.08, 1.0)

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
var _label: Label = null
var _label_bg: TextureRect = null
var _marker: Label = null
var _marker_tween: Tween = null
var _is_latest: bool = false
var _flag_sprite: Sprite2D = null
var _flag_timer: float = 0.0
var _flag_frame: int = 0
var _flag_visible: bool = false
var _oval: OvalShape = null
var _glow: OvalShape = null
var _glow_tween: Tween = null
var _rays: MarkerRays = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = button_size
	size = button_size
	_build()
	_refresh()


func _build() -> void:
	if _btn != null:
		return
	var oval_h: float = button_size.y * OVAL_HEIGHT_RATIO
	var oval_w_small: float = button_size.x * OVAL_SCALE
	var oval_h_small: float = oval_h * OVAL_SCALE
	var oval_x: float = (button_size.x - oval_w_small) * 0.5
	var oval_y: float = (oval_h - oval_h_small) * 0.5

	# Hover 時的橢圓暈光（位於最底層，預設透明）
	_glow = OvalShape.new()
	_glow.name = "Glow"
	_glow.fill_color = Color(OVAL_FILL_AVAILABLE.r, OVAL_FILL_AVAILABLE.g, OVAL_FILL_AVAILABLE.b, 0.5)
	_glow.border_width = 0.0
	_glow.modulate.a = 0.0
	add_child(_glow)

	# 自繪橢圓（縮小至按鈕區域的一半，水平/垂直置中於按鈕區域）
	_oval = OvalShape.new()
	_oval.name = "Oval"
	_oval.fill_color = OVAL_FILL_AVAILABLE
	_oval.border_color = OVAL_BORDER
	_oval.border_width = 2.0
	_oval.position = Vector2(oval_x, oval_y)
	_oval.size = Vector2(oval_w_small, oval_h_small)
	add_child(_oval)

	# 透明 Button：吸收點擊（覆蓋於 oval 上方）
	_btn = Button.new()
	_btn.name = "Btn"
	_btn.flat = true
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.add_theme_font_size_override("font_size", 0)
	_btn.position = Vector2(0, 0)
	_btn.size = Vector2(button_size.x, oval_h)
	# 套用全透明 stylebox（避免 Button 預設 panel 干擾）
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxEmpty.new()
		_btn.add_theme_stylebox_override(state, sb)
	add_child(_btn)
	if not Engine.is_editor_hint():
		_btn.pressed.connect(_on_pressed)
		_btn.mouse_entered.connect(_on_hover_enter)
		_btn.mouse_exited.connect(_on_hover_exit)

	# 關卡名稱標籤背景（仿戰鬥場景敵人意圖：黑色漸層 0→0.5→0）
	_label_bg = TextureRect.new()
	_label_bg.name = "CaptionBG"
	_label_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label_bg.stretch_mode = TextureRect.STRETCH_SCALE
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(0, 0, 0, 0),
		Color(0, 0, 0, 0.5),
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

	# 關卡名稱標籤：位於橢圓下方（保持原始字型大小）
	_label = Label.new()
	_label.name = "Caption"
	_label.position = Vector2(0, oval_h + 2.0)
	_label.size = Vector2(button_size.x, button_size.y - oval_h - 2.0)
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override("outline_size", 4)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)

	# 已通關旗幟動畫（錨定於橢圓中心）
	_flag_sprite = Sprite2D.new()
	_flag_sprite.name = "FlagSprite"
	var flag_tex: Texture2D = load(FLAG_TEXTURE_PATH) as Texture2D
	if flag_tex != null:
		_flag_sprite.texture = flag_tex
		_flag_sprite.hframes = FLAG_HFRAMES
		_flag_sprite.frame = 0
		var fw: float = float(flag_tex.get_width()) / FLAG_HFRAMES
		var target_w: float = oval_h * 0.85
		var s: float = target_w / max(fw, 1.0)
		_flag_sprite.scale = Vector2(s, s)
		_flag_sprite.position = Vector2(button_size.x * 0.5, oval_h * 0.5)
	_flag_sprite.visible = false
	add_child(_flag_sprite)

	# 黃色放射光錐（"!" 後方；尺寸依橢圓高度）
	_rays = MarkerRays.new()
	_rays.name = "Rays"
	_rays.position = Vector2(button_size.x * 0.5, oval_h * 0.5)
	_rays.radius = oval_h * 0.55
	_rays.inner_radius = oval_h * 0.30
	_rays.visible = false
	add_child(_rays)

	# 黃色 "!" 標記（錨定於橢圓中心；位於光錐之上）
	_marker = Label.new()
	_marker.name = "Marker"
	_marker.text = "!"
	_marker.add_theme_font_size_override("font_size", int(oval_h * 0.85))
	_marker.add_theme_color_override("font_color", Color(1.0, 0.92, 0.15))
	_marker.add_theme_color_override("font_outline_color", Color(0.35, 0.18, 0, 1))
	_marker.add_theme_constant_override("outline_size", 6)
	_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_marker.size = Vector2(button_size.x, oval_h)
	_marker.position = Vector2(0, 0)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.visible = false
	add_child(_marker)


func _layout() -> void:
	var oval_h: float = button_size.y * OVAL_HEIGHT_RATIO
	var oval_w_small: float = button_size.x * OVAL_SCALE
	var oval_h_small: float = oval_h * OVAL_SCALE
	var oval_x: float = (button_size.x - oval_w_small) * 0.5
	var oval_y: float = (oval_h - oval_h_small) * 0.5
	var glow_pad: float = max(6.0, oval_h_small * 0.18)
	if _glow != null:
		_glow.position = Vector2(oval_x - glow_pad, oval_y - glow_pad)
		_glow.size = Vector2(oval_w_small + glow_pad * 2.0, oval_h_small + glow_pad * 2.0)
	if _oval != null:
		_oval.position = Vector2(oval_x, oval_y)
		_oval.size = Vector2(oval_w_small, oval_h_small)
	if _btn != null:
		_btn.position = Vector2(0, 0)
		_btn.size = Vector2(button_size.x, oval_h)
	if _label_bg != null:
		var bg_h: float = button_size.y - oval_h
		_label_bg.position = Vector2(0, oval_h)
		_label_bg.size = Vector2(button_size.x, bg_h)
	if _label != null:
		_label.position = Vector2(0, oval_h + 2.0)
		_label.size = Vector2(button_size.x, button_size.y - oval_h - 2.0)
		_label.add_theme_font_size_override("font_size", 18)
	if _marker != null:
		_marker.size = Vector2(button_size.x, oval_h)
		_marker.position = Vector2(0, 0)
		_marker.add_theme_font_size_override("font_size", int(oval_h * 0.85))
	if _rays != null:
		_rays.position = Vector2(button_size.x * 0.5, oval_h * 0.5)
		_rays.radius = oval_h * 0.55
		_rays.inner_radius = oval_h * 0.30
	if _flag_sprite != null and _flag_sprite.texture != null:
		var fw: float = float(_flag_sprite.texture.get_width()) / FLAG_HFRAMES
		var target_w: float = oval_h * 0.85
		var s: float = target_w / max(fw, 1.0)
		_flag_sprite.scale = Vector2(s, s)
		_flag_sprite.position = Vector2(button_size.x * 0.5, oval_h * 0.5)


## 由父層 (map.gd) 在解鎖狀態變動時呼叫，重新整理可見性與標記
func refresh_state() -> void:
	_refresh()


func _refresh() -> void:
	if _btn == null:
		return
	if stage == null:
		_btn.text = ""
		_btn.disabled = true
		visible = true
		if _label != null:
			_label.text = ""
		if _marker != null:
			_marker.visible = false
		if _rays != null:
			_rays.visible = false
		_set_flag_visible(false)
		return

	var sid: String = stage.stage_id
	var prereq: String = stage.prerequisite_stage_id
	var unlocked: bool = prereq == "" or GameState.is_stage_cleared(prereq)
	var cleared: bool = GameState.is_stage_cleared(sid)

	visible = unlocked
	_btn.text = ""
	_btn.disabled = false
	_btn.modulate = cleared_tint if cleared else available_tint
	var oval_col: Color = OVAL_FILL_CLEARED if cleared else OVAL_FILL_AVAILABLE
	if _oval != null:
		_oval.fill_color = oval_col
	if _glow != null:
		_glow.fill_color = Color(oval_col.r, oval_col.g, oval_col.b, 0.55)
	if _label != null:
		_label.text = sid
	# 已通關顯示旗幟動畫；未通關則由 set_latest 控制 "!"
	_set_flag_visible(cleared)
	if cleared and _marker != null:
		_marker.visible = false
	if cleared and _rays != null:
		_rays.visible = false


func set_latest(latest: bool) -> void:
	_is_latest = latest
	if _marker == null:
		return
	# 通關後不顯示 "!"
	var cleared: bool = stage != null and GameState.is_stage_cleared(stage.stage_id)
	var show_marker: bool = latest and not cleared
	_marker.visible = show_marker
	if _rays != null:
		_rays.visible = show_marker
	if show_marker:
		_start_marker_tween()
	else:
		_stop_marker_tween()


## 旗幟動畫顯示/隱藏與每幀更新
func _set_flag_visible(v: bool) -> void:
	_flag_visible = v
	if _flag_sprite == null:
		return
	_flag_sprite.visible = v and _flag_sprite.texture != null
	set_process(v and _flag_sprite.texture != null)


func _process(delta: float) -> void:
	if not _flag_visible or _flag_sprite == null or _flag_sprite.texture == null:
		return
	_flag_timer += delta
	if _flag_timer >= FLAG_FRAME_TIME:
		_flag_timer = 0.0
		_flag_frame = (_flag_frame + 1) % FLAG_HFRAMES
		_flag_sprite.frame = _flag_frame


func _on_pressed() -> void:
	if stage == null:
		return
	stage_pressed.emit(stage)


func _on_hover_enter() -> void:
	if _glow == null or stage == null:
		return
	_fade_glow(1.0, 0.12)


func _on_hover_exit() -> void:
	if _glow == null:
		return
	_fade_glow(0.0, 0.18)


func _fade_glow(target_alpha: float, duration: float) -> void:
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = create_tween()
	_glow_tween.tween_property(_glow, "modulate:a", target_alpha, duration)


func _start_marker_tween() -> void:
	_stop_marker_tween()
	if _marker == null:
		return
	var base_y: float = _marker.position.y
	_marker_tween = create_tween().set_loops()
	_marker_tween.tween_property(_marker, "position:y", base_y - 12.0, 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_marker_tween.tween_property(_marker, "position:y", base_y, 0.4) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _stop_marker_tween() -> void:
	if _marker_tween != null and _marker_tween.is_valid():
		_marker_tween.kill()
	_marker_tween = null
