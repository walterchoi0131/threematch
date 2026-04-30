## Map（世界地圖 / Hub）— 玩家進入遊戲後的主畫面。
## 包含三個分頁（Characters / Map / Inventory），由底部 BottomNav 切換。
## Map 分頁上的關卡按鈕（StageButton）由 Godot 編輯器擺放；按下後開啟戰前準備覆蓋層。
## 已通關記錄存於 GameState.cleared_stages；解鎖規則由 StageButton 自行依 prerequisite_stage_id 判斷。
extends Node2D

const PrepareScene: PackedScene = preload("res://scenes/prepare.tscn")
const CharactersScene: PackedScene = preload("res://scenes/characters.tscn")
const InventoryScene: PackedScene = preload("res://scenes/inventory.tscn")

const OVERLAY_HEIGHT_RATIO: float = 0.8

enum Page { CHARACTERS, MAP, INVENTORY }

var _overlay_layer: CanvasLayer = null
var _stage_buttons: Array[StageButton] = []

@onready var _pages_root: Control = $UILayer/Pages
@onready var _map_page: Control = $UILayer/Pages/MapPage
@onready var _characters_page: Control = $UILayer/Pages/CharactersPage
@onready var _inventory_page: Control = $UILayer/Pages/InventoryPage
@onready var _characters_tab: Button = $UILayer/BottomNav/HBox/CharactersTab
@onready var _map_tab: Button = $UILayer/BottomNav/HBox/MapTab
@onready var _inventory_tab: Button = $UILayer/BottomNav/HBox/InventoryTab


func _ready() -> void:
	_characters_tab.text = Locale.tr_ui("CHARACTERS")
	_map_tab.text = Locale.tr_ui("MAP")
	_inventory_tab.text = Locale.tr_ui("INVENTORY")

	# 收集 MapPage 上所有 StageButton（編輯器擺放）
	_stage_buttons.clear()
	_collect_stage_buttons(_map_page)
	for sb in _stage_buttons:
		sb.stage_pressed.connect(_on_stage_button_pressed)

	# 懶載入 Characters / Inventory 子畫面到對應分頁
	_ensure_subpage(_characters_page, CharactersScene)
	_ensure_subpage(_inventory_page, InventoryScene)

	_show_page(Page.MAP)
	_refresh_stage_buttons()

	GameState.play_bgm(load("res://assets/music/fez_map.mp3"), true, "map")
	get_viewport().size_changed.connect(_on_viewport_resized)


func _collect_stage_buttons(node: Node) -> void:
	for child in node.get_children():
		if child is StageButton:
			_stage_buttons.append(child as StageButton)
		_collect_stage_buttons(child)


func _ensure_subpage(page: Control, scene: PackedScene) -> void:
	if scene == null:
		return
	var screen: Node = scene.instantiate()
	if screen is Control:
		var ctrl: Control = screen as Control
		ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(screen)


func _on_characters_tab_pressed() -> void:
	_show_page(Page.CHARACTERS)


func _on_map_tab_pressed() -> void:
	_show_page(Page.MAP)


func _on_inventory_tab_pressed() -> void:
	_show_page(Page.INVENTORY)


func _show_page(page: Page) -> void:
	_characters_page.visible = page == Page.CHARACTERS
	_map_page.visible = page == Page.MAP
	_inventory_page.visible = page == Page.INVENTORY
	_characters_tab.modulate = Color(1, 1, 1, 1) if page == Page.CHARACTERS else Color(0.65, 0.65, 0.7, 1)
	_map_tab.modulate = Color(1, 1, 1, 1) if page == Page.MAP else Color(0.65, 0.65, 0.7, 1)
	_inventory_tab.modulate = Color(1, 1, 1, 1) if page == Page.INVENTORY else Color(0.65, 0.65, 0.7, 1)


## 刷新所有 StageButton 解鎖狀態，並標示「最新可玩」者顯示跳動的「!」
func _refresh_stage_buttons() -> void:
	var sorted: Array[StageButton] = _stage_buttons.duplicate()
	sorted.sort_custom(func(a: StageButton, b: StageButton) -> bool:
		var sa: String = a.stage.stage_id if a.stage != null else ""
		var sb_id: String = b.stage.stage_id if b.stage != null else ""
		return sa < sb_id
	)
	for sb in sorted:
		sb.refresh_state()
	var latest: StageButton = null
	for sb in sorted:
		if sb.stage != null and sb.visible and not GameState.is_stage_cleared(sb.stage.stage_id):
			latest = sb
			break
	for sb in _stage_buttons:
		sb.set_latest(sb == latest)


# ── 關卡按鈕 → 戰前準備覆蓋層 ─────────────────────────────────

func _on_stage_button_pressed(stage: StageData) -> void:
	if stage == null:
		return
	GameState.selected_stage = stage
	_open_overlay(PrepareScene)


# ── 覆蓋層管理（戰前準備）──────────────────────────────────

func _open_overlay(scene: PackedScene) -> void:
	_close_overlay()
	if scene == null:
		return

	_overlay_layer = CanvasLayer.new()
	_overlay_layer.layer = 50
	add_child(_overlay_layer)

	var backdrop := Control.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(_on_backdrop_input)
	_overlay_layer.add_child(backdrop)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0, 0, 0, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(dim)

	var frame := Control.new()
	frame.name = "OverlayFrame"
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.clip_contents = false
	_overlay_layer.add_child(frame)

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


func _play_overlay_close(layer: CanvasLayer, frame: Control, backdrop: Control) -> void:
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var end_y: float = frame.position.y - frame.size.y - 80.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(frame, "position:y", end_y, 0.28) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(frame, "modulate:a", 0.0, 0.25)
	tw.tween_property(backdrop, "modulate:a", 0.0, 0.25)
	tw.chain().tween_callback(layer.queue_free)
