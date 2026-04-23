## Map（地圖畫面）— 關卡選擇介面。
## 玩家可選擇關卡（進入準備畫面）、檢視角色、查看背包。
## 角色 / 背包 / 戰前準備皆以「覆蓋層」方式開啟，地圖保持顯示於下方。
extends Node2D

const STAGE1 := preload("res://stages/stage_dev.tres")  # 第一關預載

const PrepareScene: PackedScene = preload("res://scenes/prepare.tscn")
const CharactersScene: PackedScene = preload("res://scenes/characters.tscn")
const InventoryScene: PackedScene = preload("res://scenes/inventory.tscn")

const OVERLAY_HEIGHT_RATIO: float = 0.8

var _overlay_layer: CanvasLayer = null


func _ready() -> void:
	$UILayer/Title.text = Locale.tr_ui("STAGE_SELECT")
	$UILayer/CharactersBtn.text = Locale.tr_ui("CHARACTERS")
	$UILayer/InventoryBtn.text = Locale.tr_ui("INVENTORY")

	# 播放地圖 BGM（循環，存於 GameState；若已在播放同一首則不重啟）
	GameState.play_bgm(load("res://assets/music/fez_map.mp3"), true, "map")
	get_viewport().size_changed.connect(_on_viewport_resized)


## 點擊關卡按鈕時開啟戰前準備覆蓋層
func _on_stage1_pressed() -> void:
	GameState.selected_stage = STAGE1
	_open_overlay(PrepareScene)


## 點擊角色按鈕時開啟角色列表覆蓋層
func _on_characters_pressed() -> void:
	_open_overlay(CharactersScene)


## 點擊背包按鈕時開啟背包覆蓋層
func _on_inventory_pressed() -> void:
	_open_overlay(InventoryScene)


# ── 覆蓋層管理 ────────────────────────────────────────────────

## 將指定 PackedScene 以「全寬 × 80% 高」的覆蓋層形式開啟。
## 點擊半透明背景或子畫面 emit `closed` 即關閉。
func _open_overlay(scene: PackedScene) -> void:
	_close_overlay()
	if scene == null:
		return

	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 50
	add_child(_overlay_layer)

	# 點擊熱區：覆蓋全螢幕但完全透明，按下即關閉
	var backdrop := Control.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	_overlay_layer.add_child(backdrop)

	# 半透明黑色：只覆蓋中央 80% 高度（上下 10% 完全透明可看見地圖）
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(dim)

	# 中央容器（全寬 × 80% 高，置中）
	var frame := Control.new()
	frame.name = "OverlayFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.clip_contents = false
	_overlay_layer.add_child(frame)

	# 實例化目標畫面，加入 frame 並讓其填滿
	var screen: Node = scene.instantiate()
	if screen is Control:
		var ctrl: Control = screen as Control
		ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.add_child(screen)

	if screen.has_signal("closed"):
		screen.connect("closed", _close_overlay)

	_layout_overlay_frame(frame)
	_play_overlay_open(frame, backdrop)


func _on_viewport_resized() -> void:
	if _overlay_layer == null:
		return
	var frame: Node = _overlay_layer.get_node_or_null("OverlayFrame")
	if frame is Control:
		_layout_overlay_frame(frame as Control)


func _layout_overlay_frame(frame: Control) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var w: float = vp.x
	var h: float = vp.y * OVERLAY_HEIGHT_RATIO
	frame.set_anchors_preset(Control.PRESET_TOP_LEFT)
	frame.position = Vector2(0, (vp.y - h) * 0.5)
	frame.size = Vector2(w, h)
	# 同步調整背景半透明區（只覆蓋中央 80%）
	if _overlay_layer != null:
		var bd: Node = _overlay_layer.get_node_or_null("Backdrop")
		if bd:
			var dim: Node = bd.get_node_or_null("Dim")
			if dim is ColorRect:
				var d: ColorRect = dim as ColorRect
				d.set_anchors_preset(Control.PRESET_TOP_LEFT)
				d.position = Vector2(0, (vp.y - h) * 0.5)
				d.size = Vector2(w, h)


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_close_overlay()


func _close_overlay() -> void:
	if _overlay_layer == null:
		return
	var layer: CanvasLayer = _overlay_layer
	_overlay_layer = null
	var frame: Node = layer.get_node_or_null("OverlayFrame")
	var backdrop: Node = layer.get_node_or_null("Backdrop")
	if frame is Control and backdrop is Control:
		_play_overlay_close(layer, frame as Control, backdrop as Control)
	else:
		layer.queue_free()


## Overlay 開啟動畫：從頂部滑入 + 淡入
func _play_overlay_open(frame: Control, backdrop: Control) -> void:
	var target_y: float = frame.position.y
	frame.position.y = target_y - frame.size.y - 80.0
	frame.modulate.a = 0.0
	backdrop.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(frame, "position:y", target_y, 0.32) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(frame, "modulate:a", 1.0, 0.25)
	tw.tween_property(backdrop, "modulate:a", 1.0, 0.2)


## Overlay 關閉動畫：反向滑出 + 淡出
func _play_overlay_close(layer: CanvasLayer, frame: Control, backdrop: Control) -> void:
	# 關閉期間不接受輸入
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var end_y: float = frame.position.y - frame.size.y - 80.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(frame, "position:y", end_y, 0.28) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(frame, "modulate:a", 0.0, 0.25)
	tw.tween_property(backdrop, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(layer.queue_free)
