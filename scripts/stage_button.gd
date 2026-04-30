## StageButton（世界地圖關卡按鈕）— 可在編輯器中拖放並擺放於世界地圖上。
## 透過 `stage` 屬性綁定 StageData；按下時 emit `stage_pressed(stage)`。
## 解鎖規則：若 `stage.prerequisite_stage_id` 已通關才會顯示。
## 「最新可玩」關卡會顯示一個跳動的黃色「!」標記。
@tool
class_name StageButton
extends Control

signal stage_pressed(stage: StageData)

## 綁定的關卡資料（必填）
@export var stage: StageData = null:
	set(value):
		stage = value
		if is_inside_tree():
			_refresh()

## 按鈕大小（控制顯示尺寸）
@export var button_size: Vector2 = Vector2(120, 120):
	set(value):
		button_size = value
		custom_minimum_size = value
		size = value
		if is_inside_tree():
			_layout()

## 已通關時的色調
@export var cleared_tint: Color = Color(0.65, 0.95, 0.65, 1.0)
## 可玩（已解鎖未通關）的色調
@export var available_tint: Color = Color(1, 1, 1, 1)

var _btn: Button = null
var _label: Label = null
var _marker: Label = null
var _marker_tween: Tween = null
var _is_latest: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = button_size
	size = button_size
	_build()
	_refresh()


func _build() -> void:
	if _btn != null:
		return
	_btn = Button.new()
	_btn.name = "Btn"
	_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	_btn.flat = false
	_btn.focus_mode = Control.FOCUS_NONE
	_btn.add_theme_font_size_override("font_size", 28)
	add_child(_btn)
	if not Engine.is_editor_hint():
		_btn.pressed.connect(_on_pressed)

	_label = Label.new()
	_label.name = "Caption"
	_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_label.offset_top = -22.0
	_label.offset_bottom = 6.0
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override("outline_size", 4)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)

	_marker = Label.new()
	_marker.name = "Marker"
	_marker.text = "!"
	_marker.add_theme_font_size_override("font_size", 42)
	_marker.add_theme_color_override("font_color", Color(1.0, 0.92, 0.15))
	_marker.add_theme_color_override("font_outline_color", Color(0.35, 0.18, 0, 1))
	_marker.add_theme_constant_override("outline_size", 6)
	_marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_marker.size = Vector2(40, 50)
	_marker.position = Vector2((button_size.x - 40) * 0.5, -56)
	_marker.visible = false
	add_child(_marker)


func _layout() -> void:
	if _marker != null:
		_marker.position = Vector2((button_size.x - 40) * 0.5, -56)


## 由父層 (map.gd) 在解鎖狀態變動時呼叫，重新整理可見性與標記
func refresh_state() -> void:
	_refresh()


func set_latest(latest: bool) -> void:
	_is_latest = latest
	if _marker == null:
		return
	_marker.visible = latest
	if latest:
		_start_marker_tween()
	else:
		_stop_marker_tween()


func _refresh() -> void:
	if _btn == null:
		return
	if stage == null:
		_btn.text = "?"
		_btn.disabled = true
		visible = true
		if _label != null:
			_label.text = ""
		if _marker != null:
			_marker.visible = false
		return

	var sid: String = stage.stage_id
	var prereq: String = stage.prerequisite_stage_id
	var unlocked: bool = prereq == "" or GameState.is_stage_cleared(prereq)
	var cleared: bool = GameState.is_stage_cleared(sid)

	visible = unlocked
	_btn.text = sid
	_btn.disabled = false
	_btn.modulate = cleared_tint if cleared else available_tint
	if _label != null:
		_label.text = stage.stage_name


func _on_pressed() -> void:
	if stage == null:
		return
	stage_pressed.emit(stage)


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
