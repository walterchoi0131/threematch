## Map（世界地圖 / Hub）— 玩家進入遊戲後的主畫面。
## 包含三個分頁（Characters / Map / Inventory），由底部 BottomNav 切換。
## Map 分頁上的關卡按鈕（StageButton）由 Godot 編輯器擺放；按下後開啟戰前準備覆蓋層。
## 已通關記錄存於 GameState.cleared_stages；解鎖規則由 StageButton 自行依 prerequisite_stage_id 判斷。
extends Node2D

const PrepareScene: PackedScene = preload("res://scenes/prepare.tscn")
const CharactersScene: PackedScene = preload("res://scenes/characters.tscn")
const InventoryScene: PackedScene = preload("res://scenes/inventory.tscn")
const StageButtonScene: PackedScene = preload("res://scenes/stage_button.tscn")

const OVERLAY_HEIGHT_RATIO: float = 0.8
const STAGE_DIR: String = "res://stages"
const NEW_STAGE_OFFSET: Vector2 = Vector2(160.0, 0.0)

enum Page { CHARACTERS, MAP, INVENTORY }

var _overlay_layer: CanvasLayer = null
var _stage_buttons: Array[StageButton] = []
var _scene_stage_paths: Dictionary = {}
var _path_layer: Control = null
var _debug_panel: Control = null
var _dev_mode_label: Label = null
var _portrait_debug_layer: CanvasLayer = null
var _fuse_skill_debug_icon: Texture2D = preload("res://assets/blocks/puzzle_key_gem.png")

@onready var _pages_root: Control = $UILayer/Pages
@onready var _map_page: Control = $UILayer/Pages/MapPage
@onready var _characters_page: Control = $UILayer/Pages/CharactersPage
@onready var _inventory_page: Control = $UILayer/Pages/InventoryPage
@onready var _characters_tab: Button = $UILayer/BottomNav/HBox/CharactersTab
@onready var _map_tab: Button = $UILayer/BottomNav/HBox/MapTab
@onready var _inventory_tab: Button = $UILayer/BottomNav/HBox/InventoryTab


func _ready() -> void:
	GameState.fade_in_if_pending(0.25)

	_characters_tab.text = Locale.tr_ui("CHARACTERS")
	_map_tab.text = Locale.tr_ui("MAP")
	_inventory_tab.text = Locale.tr_ui("INVENTORY")

	# 收集 MapPage 上所有 StageButton（編輯器擺放）
	_stage_buttons.clear()
	_scene_stage_paths.clear()
	_collect_stage_buttons(_map_page)
	for sb in _stage_buttons:
		_connect_stage_button(sb)
		if sb.stage != null and sb.stage.resource_path != "":
			_scene_stage_paths[sb.stage.resource_path] = true
	_ensure_stage_buttons_for_stage_resources()
	_apply_stage_positions_from_data()
	_setup_path_layer()

	# 懶載入 Characters / Inventory 子畫面到對應分頁
	_ensure_subpage(_characters_page, CharactersScene)
	_ensure_subpage(_inventory_page, InventoryScene)

	_show_page(Page.MAP)
	_refresh_stage_buttons()

	GameState.play_bgm(load("res://assets/music/mhr_quest.mp3"), true, "map")
	get_viewport().size_changed.connect(_on_viewport_resized)
	_build_portrait_debug_btn()
	_build_dev_mode_label()
	_refresh_dev_mode_ui()


func _collect_stage_buttons(node: Node) -> void:
	for child in node.get_children():
		if child is StageButton:
			_stage_buttons.append(child as StageButton)
		_collect_stage_buttons(child)


func _connect_stage_button(sb: StageButton) -> void:
	if sb == null:
		return
	if not sb.stage_pressed.is_connected(_on_stage_button_pressed):
		sb.stage_pressed.connect(_on_stage_button_pressed)
	if not sb.stage_add_pressed.is_connected(_on_stage_button_add_pressed):
		sb.stage_add_pressed.connect(_on_stage_button_add_pressed)
	if not sb.stage_remove_pressed.is_connected(_on_stage_button_remove_pressed):
		sb.stage_remove_pressed.connect(_on_stage_button_remove_pressed)
	if not sb.stage_dragged.is_connected(_on_stage_button_dragged):
		sb.stage_dragged.connect(_on_stage_button_dragged)
	if not sb.stage_drag_finished.is_connected(_on_stage_button_drag_finished):
		sb.stage_drag_finished.connect(_on_stage_button_drag_finished)


func _ensure_stage_buttons_for_stage_resources() -> void:
	var existing: Dictionary = {}
	for sb in _stage_buttons:
		if sb != null and sb.stage != null and sb.stage.stage_id != "":
			existing[sb.stage.stage_id] = true

	for stage in _load_all_stage_resources():
		if stage == null or stage.stage_id == "" or stage.map_hidden:
			continue
		if existing.has(stage.stage_id):
			continue
		var sb: StageButton = StageButtonScene.instantiate() as StageButton
		sb.name = "Stage_%s" % _stage_node_suffix(stage.stage_id)
		sb.stage = stage
		_map_page.add_child(sb)
		_stage_buttons.append(sb)
		_connect_stage_button(sb)
		existing[stage.stage_id] = true


func _apply_stage_positions_from_data() -> void:
	for sb in _stage_buttons:
		if sb == null or sb.stage == null:
			continue
		if _has_saved_map_position(sb.stage):
			_set_stage_button_position(sb, sb.stage.map_position)
		else:
			sb.stage.map_position = sb.position


func _has_saved_map_position(stage: StageData) -> bool:
	return stage != null and stage.map_position.x >= 0.0 and stage.map_position.y >= 0.0


func _set_stage_button_position(sb: StageButton, target_position: Vector2) -> void:
	if sb == null:
		return
	var max_pos: Vector2 = Vector2(
		maxf(0.0, _map_page.size.x - sb.button_size.x),
		maxf(0.0, _map_page.size.y - sb.button_size.y)
	)
	sb.position = Vector2(
		clampf(target_position.x, 0.0, max_pos.x),
		clampf(target_position.y, 0.0, max_pos.y)
	)
	sb.size = sb.button_size
	if sb.stage != null:
		sb.stage.map_position = sb.position


func _load_all_stage_resources() -> Array[StageData]:
	var result: Array[StageData] = []
	var dir := DirAccess.open(STAGE_DIR)
	if dir == null:
		push_warning("Map: cannot open stage dir %s" % STAGE_DIR)
		return result
	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name == "":
			break
		if dir.current_is_dir() or not file_name.ends_with(".tres"):
			continue
		var path: String = "%s/%s" % [STAGE_DIR, file_name]
		var res: Resource = load(path)
		if res is StageData:
			result.append(res as StageData)
	dir.list_dir_end()
	return result


func _stage_node_suffix(stage_id: String) -> String:
	var suffix: String = stage_id.strip_edges()
	for ch in [" ", "-", ".", "/", "\\", ":"]:
		suffix = suffix.replace(ch, "_")
	return suffix


func _make_unique_child_stage_id(parent_stage: StageData, all_stages: Array[StageData]) -> String:
	var base: String = "%s-new" % parent_stage.stage_id
	var taken: Dictionary = {}
	for stage in all_stages:
		if stage != null:
			taken[stage.stage_id] = true
	var index: int = 1
	var candidate: String = base
	while taken.has(candidate) or ResourceLoader.exists(_stage_resource_path_for_id(candidate)):
		index += 1
		candidate = "%s-%d" % [base, index]
	return candidate


func _stage_resource_path_for_id(stage_id: String) -> String:
	var file_id: String = stage_id.strip_edges().to_lower()
	for ch in [" ", "-", ".", "/", "\\", ":"]:
		file_id = file_id.replace(ch, "_")
	return "%s/stage_%s.tres" % [STAGE_DIR, file_id]


func _save_stage(stage: StageData) -> bool:
	if stage == null or stage.resource_path == "":
		return false
	var err: int = ResourceSaver.save(stage, stage.resource_path)
	if err != OK:
		push_warning("Map: failed to save stage %s (%d)" % [stage.resource_path, err])
		return false
	return true


func _ensure_subpage(page: Control, scene: PackedScene) -> void:
	if scene == null:
		return
	var screen: Node = scene.instantiate()
	if screen is Control:
		var ctrl: Control = screen as Control
		ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.add_child(screen)


func _rebuild_subpage(page: Control, scene: PackedScene) -> void:
	if page == null:
		return
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	_ensure_subpage(page, scene)


func _refresh_after_save_clear() -> void:
	_rebuild_subpage(_characters_page, CharactersScene)
	_rebuild_subpage(_inventory_page, InventoryScene)
	_refresh_stage_buttons()


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
		if sb.stage != null and not sb.stage.map_hidden and sb.is_unlocked_for_play() and not GameState.is_stage_cleared(sb.stage.stage_id):
			latest = sb
			break
	for sb in _stage_buttons:
		sb.set_latest(sb == latest)
	if _path_layer != null:
		_path_layer.queue_redraw()


# ── 世界地圖路徑連線（Stage 之間的道路 UI）────────────────────

func _setup_path_layer() -> void:
	_path_layer = Control.new()
	_path_layer.name = "PathLayer"
	_path_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_path_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_path_layer.set_script(preload("res://scripts/map_path_layer.gd"))
	_map_page.add_child(_path_layer)
	_map_page.move_child(_path_layer, 0)
	_path_layer.set("stage_buttons", _stage_buttons)
	_path_layer.queue_redraw()


# ── 關卡按鈕 → 戰前準備覆蓋層 ─────────────────────────────────

func _on_stage_button_pressed(stage: StageData) -> void:
	if stage == null:
		return
	if GameState.dev_mode:
		_open_stage_editor(stage)
		return
	GameState.selected_stage = stage
	GameState.stage_edit_mode = false
	_open_overlay(PrepareScene)


func _on_stage_button_edit_pressed(stage: StageData) -> void:
	if stage == null:
		return
	_open_stage_editor(stage)


func _open_stage_editor(stage: StageData) -> void:
	if stage == null:
		return
	_close_overlay()
	GameState.selected_stage = stage
	GameState.stage_edit_mode = true
	GameState.fade_to_scene("res://scenes/main.tscn", 0.25)


func _on_stage_button_add_pressed(parent_stage: StageData) -> void:
	if parent_stage == null or not GameState.dev_mode:
		return
	var all_stages: Array[StageData] = _load_all_stage_resources()
	var child_id: String = _make_unique_child_stage_id(parent_stage, all_stages)
	var child_path: String = _stage_resource_path_for_id(child_id)
	var child_stage: StageData = parent_stage.duplicate(true) as StageData
	child_stage.stage_id = child_id
	child_stage.stage_name = "Stage %s" % child_id
	child_stage.prerequisite_stage_id = parent_stage.stage_id
	child_stage.connects_to = []
	child_stage.map_hidden = false
	child_stage.map_position = parent_stage.map_position + NEW_STAGE_OFFSET
	var err: int = ResourceSaver.save(child_stage, child_path)
	if err != OK:
		push_warning("Map: failed to create stage %s (%d)" % [child_path, err])
		return
	child_stage = load(child_path) as StageData
	if child_stage == null:
		push_warning("Map: created stage could not be loaded: %s" % child_path)
		return
	if not parent_stage.connects_to.has(child_id):
		parent_stage.connects_to.append(child_id)
		_save_stage(parent_stage)
	var sb: StageButton = StageButtonScene.instantiate() as StageButton
	sb.name = "Stage_%s" % _stage_node_suffix(child_id)
	sb.stage = child_stage
	_map_page.add_child(sb)
	_stage_buttons.append(sb)
	_connect_stage_button(sb)
	_set_stage_button_position(sb, child_stage.map_position)
	if _path_layer != null:
		_path_layer.set("stage_buttons", _stage_buttons)
	_refresh_stage_buttons()


func _on_stage_button_remove_pressed(stage: StageData) -> void:
	if stage == null or not GameState.dev_mode:
		return
	var removed_id: String = stage.stage_id
	var fallback_prereq: String = stage.prerequisite_stage_id
	var stage_path: String = stage.resource_path
	var all_stages: Array[StageData] = _load_all_stage_resources()
	var reparented_child_ids: Array[String] = []
	for other_stage in all_stages:
		if other_stage == null or other_stage.stage_id == removed_id:
			continue
		var changed: bool = false
		if other_stage.connects_to.has(removed_id):
			other_stage.connects_to.erase(removed_id)
			changed = true
		if other_stage.prerequisite_stage_id == removed_id:
			other_stage.prerequisite_stage_id = fallback_prereq
			reparented_child_ids.append(other_stage.stage_id)
			changed = true
		if changed:
			_save_stage(other_stage)
	if fallback_prereq != "" and not reparented_child_ids.is_empty():
		for other_stage in all_stages:
			if other_stage == null or other_stage.stage_id != fallback_prereq:
				continue
			var changed: bool = false
			for child_id in reparented_child_ids:
				if not other_stage.connects_to.has(child_id):
					other_stage.connects_to.append(child_id)
					changed = true
			if changed:
				_save_stage(other_stage)
			break

	var physically_removed: bool = false
	if stage_path != "" and not _scene_stage_paths.has(stage_path):
		var absolute_path: String = ProjectSettings.globalize_path(stage_path)
		var remove_err: int = DirAccess.remove_absolute(absolute_path)
		physically_removed = remove_err == OK
		if remove_err != OK:
			push_warning("Map: failed to remove stage file %s (%d)" % [stage_path, remove_err])
	if not physically_removed:
		stage.map_hidden = true
		_save_stage(stage)

	var removed_buttons: Array[StageButton] = []
	for sb in _stage_buttons:
		if sb != null and sb.stage == stage:
			removed_buttons.append(sb)
	for sb in removed_buttons:
		_stage_buttons.erase(sb)
		sb.queue_free()
	if _path_layer != null:
		_path_layer.set("stage_buttons", _stage_buttons)
	_refresh_stage_buttons()


func _on_stage_button_dragged(sb: StageButton, target_position: Vector2) -> void:
	if sb == null or sb.stage == null or not GameState.dev_mode:
		return
	var map_position: Vector2 = _map_page.get_global_transform_with_canvas().affine_inverse() * target_position
	_set_stage_button_position(sb, map_position)
	if _path_layer != null:
		_path_layer.queue_redraw()


func _on_stage_button_drag_finished(sb: StageButton) -> void:
	if sb == null or sb.stage == null or not GameState.dev_mode:
		return
	_save_stage(sb.stage)
	if _path_layer != null:
		_path_layer.queue_redraw()


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
	dim.color = Color(0, 0, 0, 0.0)
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


# ── F4/F9 Dev and Debug Panel ───────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F4:
			_toggle_dev_mode()
		elif event.keycode == KEY_F9:
			_toggle_debug_panel()


func _toggle_dev_mode() -> void:
	GameState.dev_mode = not GameState.dev_mode
	_refresh_dev_mode_ui()
	_refresh_stage_buttons()


func _build_dev_mode_label() -> void:
	if _portrait_debug_layer == null:
		return
	_dev_mode_label = Label.new()
	_dev_mode_label.name = "DevModeLabel"
	_dev_mode_label.anchor_left = 0.0
	_dev_mode_label.anchor_top = 0.0
	_dev_mode_label.offset_left = 16.0
	_dev_mode_label.offset_top = 16.0
	_dev_mode_label.offset_right = 240.0
	_dev_mode_label.offset_bottom = 46.0
	_dev_mode_label.add_theme_font_size_override("font_size", 16)
	_dev_mode_label.add_theme_color_override("font_color", Color(1, 0.92, 0.35, 1))
	_dev_mode_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_dev_mode_label.add_theme_constant_override("outline_size", 4)
	_dev_mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_debug_layer.add_child(_dev_mode_label)


func _refresh_dev_mode_ui() -> void:
	if _dev_mode_label == null:
		return
	_dev_mode_label.visible = GameState.dev_mode
	_dev_mode_label.text = "DEV MODE  F4"


func _toggle_debug_panel() -> void:
	if _debug_panel != null and is_instance_valid(_debug_panel):
		_debug_panel.queue_free()
		_debug_panel = null
		return
	var layer := CanvasLayer.new()
	layer.layer = 64
	add_child(layer)
	_debug_panel = MapDebugPanel.build(layer, func() -> void:
		_refresh_after_save_clear()
	)
	# 關閉時連同 CanvasLayer 一起移除
	_debug_panel.tree_exited.connect(func() -> void:
		if is_instance_valid(layer):
			layer.queue_free()
	)


# ── Debug 浮動按鈕 ──────────────────────────────────────────

func _build_portrait_debug_btn() -> void:
	_portrait_debug_layer = CanvasLayer.new()
	_portrait_debug_layer.layer = 12
	add_child(_portrait_debug_layer)

	var stat_btn: Button = _make_debug_launcher_button("ST", "Stat Debug", 16, -250.0, -196.0)
	stat_btn.pressed.connect(_open_stat_debug)
	_portrait_debug_layer.add_child(stat_btn)

	var portrait_btn: Button = _make_debug_launcher_button("🖼", "Portrait Debug", 26, -190.0, -136.0)
	portrait_btn.pressed.connect(_open_portrait_debug)
	_portrait_debug_layer.add_child(portrait_btn)

	var enemy_btn: Button = _make_debug_launcher_button("EN", "Monster Debug", 16, -130.0, -76.0)
	enemy_btn.pressed.connect(_open_enemy_debug)
	_portrait_debug_layer.add_child(enemy_btn)

	var fuse_btn: Button = _make_debug_launcher_button("", "融合寶石技能 DEV", 16, -70.0, -16.0)
	fuse_btn.icon = _fuse_skill_debug_icon
	fuse_btn.expand_icon = true
	fuse_btn.pressed.connect(_open_fuse_skill_debug)
	_portrait_debug_layer.add_child(fuse_btn)


func _make_debug_launcher_button(label_text: String, tooltip: String, font_size: int, top_offset: float, bottom_offset: float) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.add_theme_font_size_override("font_size", font_size)
	btn.custom_minimum_size = Vector2(54, 54)
	btn.tooltip_text = tooltip

	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.12, 0.14, 0.22, 0.90)
	sbox.set_border_width_all(2)
	sbox.border_color = Color(0.55, 0.55, 0.72, 1.0)
	sbox.set_corner_radius_all(27)
	btn.add_theme_stylebox_override("normal",  sbox)
	btn.add_theme_stylebox_override("hover",   sbox)
	btn.add_theme_stylebox_override("pressed", sbox)
	btn.add_theme_stylebox_override("focus",   sbox)

	# 右下角、底部導覽列上方
	btn.anchor_left   = 1.0; btn.anchor_right  = 1.0
	btn.anchor_top    = 1.0; btn.anchor_bottom = 1.0
	btn.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	btn.grow_vertical   = Control.GROW_DIRECTION_BEGIN
	btn.offset_left   = -76.0
	btn.offset_top    = top_offset
	btn.offset_right  = -22.0
	btn.offset_bottom = bottom_offset

	return btn


func _open_portrait_debug() -> void:
	if _portrait_debug_layer == null:
		return
	# 只允許一個
	for child in _portrait_debug_layer.get_children():
		if child.get_script() != null and \
				child.get_script().resource_path == "res://scripts/portrait_debug_screen.gd":
			return
	var screen: Control = load("res://scripts/portrait_debug_screen.gd").new() as Control
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.tree_exiting.connect(func() -> void: pass)  # 保留佔位
	_portrait_debug_layer.add_child(screen)


func _open_stat_debug() -> void:
	if _portrait_debug_layer == null:
		return
	# 只允許一個
	for child in _portrait_debug_layer.get_children():
		if child.get_script() != null and \
				child.get_script().resource_path == "res://scripts/stat_debug_screen.gd":
			return
	var screen: Control = load("res://scripts/stat_debug_screen.gd").new() as Control
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_debug_layer.add_child(screen)


func _open_enemy_debug() -> void:
	if _portrait_debug_layer == null:
		return
	# 只允許一個
	for child in _portrait_debug_layer.get_children():
		if child.get_script() != null and \
				child.get_script().resource_path == "res://scripts/enemy_debug_screen.gd":
			return
	var screen: Control = load("res://scripts/enemy_debug_screen.gd").new() as Control
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_debug_layer.add_child(screen)


func _open_fuse_skill_debug() -> void:
	if _portrait_debug_layer == null:
		return
	for child in _portrait_debug_layer.get_children():
		if child.get_script() != null and \
				child.get_script().resource_path == "res://scripts/fuse_skill_debug_screen.gd":
			return
	var screen: Control = load("res://scripts/fuse_skill_debug_screen.gd").new() as Control
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_debug_layer.add_child(screen)
