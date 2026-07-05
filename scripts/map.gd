## Map（世界地圖 / Hub）— 玩家進入遊戲後的主畫面。
## 包含三個分頁（Characters / Map / Inventory），由底部 BottomNav 切換。
## Map 分頁上的關卡按鈕（StageButton）由 Godot 編輯器擺放；按下後開啟戰前準備覆蓋層。
## 已通關記錄存於 GameState.cleared_stages；解鎖規則由 StageButton 自行依 prerequisite_stage_id 判斷。
extends Node2D

const PrepareScene: PackedScene = preload("res://scenes/prepare.tscn")
const CharactersScene: PackedScene = preload("res://scenes/characters.tscn")
const InventoryScene: PackedScene = preload("res://scenes/inventory.tscn")
const StageButtonScene: PackedScene = preload("res://scenes/stage_button.tscn")
const StartStageTutorialPageScript := preload("res://scripts/start_stage_tutorial_page.gd")
const TutorialPageLibraryScript := preload("res://scripts/tutorial_page_library.gd")

const OVERLAY_HEIGHT_RATIO: float = 0.8
const STAGE_DIR: String = "res://stages"
const NEW_STAGE_OFFSET: Vector2 = Vector2(160.0, 0.0)
const TUTORIAL_PAGE_LIBRARY_PATH := "res://data/tutorial_page_library.tres"
const TUTORIAL_IMAGE_ROOT := "res://assets/tutor"

enum Page { CHARACTERS, MAP, INVENTORY }

var _overlay_layer: CanvasLayer = null
var _stage_buttons: Array[StageButton] = []
var _scene_stage_paths: Dictionary = {}
var _path_layer: Control = null
var _debug_panel: Control = null
var _dev_mode_label: Label = null
var _dev_mode_back_button: Button = null
var _link_drag_source: StageButton = null
var _link_drag_active: bool = false
var _dev_drag_hint_layer: CanvasLayer = null
var _dev_drag_hint_panel: PanelContainer = null
var _dev_drag_hint_label: Label = null
var _remove_confirm_dialog: ConfirmationDialog = null
var _pending_remove_stage: StageData = null
var _remove_relation_confirm_dialog: ConfirmationDialog = null
var _pending_remove_relation: Dictionary = {}
var _portrait_debug_layer: CanvasLayer = null
var _fuse_skill_debug_icon: Texture2D = preload("res://assets/blocks/puzzle_key_gem.png")
var _tutorial_editor_layer: CanvasLayer = null
var _tutorial_editor_panel: PanelContainer = null
var _tutorial_page_library: TutorialPageLibrary = null
var _tutorial_editor_page_list: VBoxContainer = null
var _tutorial_editor_image_option: OptionButton = null
var _tutorial_editor_image_preview: TextureRect = null
var _tutorial_editor_chi_title_edit: LineEdit = null
var _tutorial_editor_eng_title_edit: LineEdit = null
var _tutorial_editor_ch_info_edit: TextEdit = null
var _tutorial_editor_eng_info_edit: TextEdit = null
var _tutorial_editor_status_label: Label = null
var _tutorial_editor_selected_index: int = -1
var _tutorial_editor_refreshing: bool = false
var _tutorial_image_catalog: Array[Dictionary] = []

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
	_refresh_stage_buttons(GameState.consume_map_unlock_pop_source_stage_id())

	GameState.play_bgm(load("res://assets/music/mhr_quest.mp3"), true, "map")
	get_viewport().size_changed.connect(_on_viewport_resized)
	_build_portrait_debug_btn()
	_build_dev_mode_label()
	_build_dev_mode_back_button()
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
	if not sb.stage_long_pressed.is_connected(_on_stage_button_long_pressed):
		sb.stage_long_pressed.connect(_on_stage_button_long_pressed)
	if not sb.stage_add_pressed.is_connected(_on_stage_button_add_pressed):
		sb.stage_add_pressed.connect(_on_stage_button_add_pressed)
	if not sb.stage_remove_pressed.is_connected(_on_stage_button_remove_pressed):
		sb.stage_remove_pressed.connect(_on_stage_button_remove_pressed)
	if not sb.stage_dragged.is_connected(_on_stage_button_dragged):
		sb.stage_dragged.connect(_on_stage_button_dragged)
	if not sb.stage_drag_finished.is_connected(_on_stage_button_drag_finished):
		sb.stage_drag_finished.connect(_on_stage_button_drag_finished)
	if not sb.stage_link_drag_started.is_connected(_on_stage_link_drag_started):
		sb.stage_link_drag_started.connect(_on_stage_link_drag_started)
	if not sb.stage_link_dragged.is_connected(_on_stage_link_dragged):
		sb.stage_link_dragged.connect(_on_stage_link_dragged)
	if not sb.stage_link_drag_finished.is_connected(_on_stage_link_drag_finished):
		sb.stage_link_drag_finished.connect(_on_stage_link_drag_finished)


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
func _refresh_stage_buttons(unlock_pop_source_stage_id: String = "") -> void:
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
	if not unlock_pop_source_stage_id.is_empty():
		_play_unlock_pop_for_source(unlock_pop_source_stage_id)
	if _path_layer != null:
		_path_layer.queue_redraw()


func _play_unlock_pop_for_source(source_stage_id: String) -> void:
	for sb in _stage_buttons:
		if sb.stage == null or sb.stage.map_hidden:
			continue
		if sb.stage.prerequisite_stage_id != source_stage_id:
			continue
		if not sb.is_unlocked_for_play() or GameState.is_stage_cleared(sb.stage.stage_id):
			continue
		sb.play_unlock_pop()


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


func _on_stage_button_long_pressed(stage: StageData) -> void:
	if stage == null:
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
	_create_child_stage(parent_stage, parent_stage.map_position + NEW_STAGE_OFFSET)


func _create_child_stage(parent_stage: StageData, map_position: Vector2) -> StageButton:
	if parent_stage == null or not GameState.dev_mode:
		return null
	var all_stages: Array[StageData] = _load_all_stage_resources()
	var child_id: String = _make_unique_child_stage_id(parent_stage, all_stages)
	var child_path: String = _stage_resource_path_for_id(child_id)
	var child_stage: StageData = parent_stage.duplicate(true) as StageData
	child_stage.stage_id = child_id
	child_stage.stage_name = "Stage %s" % child_id
	child_stage.prerequisite_stage_id = parent_stage.stage_id
	child_stage.connects_to = []
	child_stage.map_hidden = false
	child_stage.map_position = map_position
	child_stage.battle_background_override_path = ""
	var err: int = ResourceSaver.save(child_stage, child_path)
	if err != OK:
		push_warning("Map: failed to create stage %s (%d)" % [child_path, err])
		return null
	child_stage = load(child_path) as StageData
	if child_stage == null:
		push_warning("Map: created stage could not be loaded: %s" % child_path)
		return null
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
	_save_stage(child_stage)
	if _path_layer != null:
		_path_layer.set("stage_buttons", _stage_buttons)
	_refresh_stage_buttons()
	return sb


func _on_stage_button_remove_pressed(stage: StageData) -> void:
	if stage == null or not GameState.dev_mode:
		return
	_confirm_remove_stage(stage)


func _confirm_remove_stage(stage: StageData) -> void:
	_pending_remove_stage = stage
	if _remove_confirm_dialog == null or not is_instance_valid(_remove_confirm_dialog):
		_remove_confirm_dialog = ConfirmationDialog.new()
		_remove_confirm_dialog.name = "RemoveStageConfirmDialog"
		_remove_confirm_dialog.title = "確認刪除關卡"
		_remove_confirm_dialog.confirmed.connect(_on_remove_stage_confirmed)
		add_child(_remove_confirm_dialog)
		_remove_confirm_dialog.get_ok_button().text = "刪除"
		_remove_confirm_dialog.get_cancel_button().text = "取消"
	_remove_confirm_dialog.dialog_text = "確定要刪除「%s」嗎？\n這會移除相關路線；若此關卡是場景內建節點，會改為隱藏。" % stage.stage_id
	_remove_confirm_dialog.popup_centered(Vector2(420, 170))


func _on_remove_stage_confirmed() -> void:
	var stage: StageData = _pending_remove_stage
	_pending_remove_stage = null
	_remove_stage_now(stage)


func _remove_stage_now(stage: StageData) -> void:
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

func _on_stage_link_drag_started(sb: StageButton, global_pos: Vector2) -> void:
	if sb == null or sb.stage == null or not GameState.dev_mode:
		return
	_link_drag_source = sb
	_link_drag_active = true
	_update_stage_link_draft(global_pos)
	_update_dev_drag_hint(global_pos)


func _on_stage_link_dragged(sb: StageButton, global_pos: Vector2) -> void:
	if sb == null or sb != _link_drag_source or not _link_drag_active or not GameState.dev_mode:
		return
	_update_stage_link_draft(global_pos)
	_update_dev_drag_hint(global_pos)


func _on_stage_link_drag_finished(sb: StageButton, global_pos: Vector2) -> void:
	if sb == null or sb != _link_drag_source or not _link_drag_active or not GameState.dev_mode:
		_clear_stage_link_draft()
		return
	var source_stage: StageData = sb.stage
	var cancel_on_source: bool = _stage_button_contains_global_pos(sb, global_pos)
	var target_button: StageButton = _stage_button_at_global_pos(global_pos, sb)
	_clear_stage_link_draft()
	_hide_dev_drag_hint()
	if source_stage == null:
		return
	if cancel_on_source:
		return
	if target_button != null and target_button.stage != null:
		_create_prerequisite_relation(source_stage, target_button.stage)
		return
	_create_child_stage(source_stage, _map_position_for_new_stage_at_global_pos(global_pos, sb))


func _update_stage_link_draft(global_pos: Vector2) -> void:
	if _path_layer == null or _link_drag_source == null or _link_drag_source.stage == null:
		return
	var local_pos: Vector2 = _map_page.get_global_transform_with_canvas().affine_inverse() * global_pos
	if _path_layer.has_method("set_draft_path"):
		_path_layer.call("set_draft_path", _link_drag_source.stage.stage_id, local_pos)


func _clear_stage_link_draft() -> void:
	_link_drag_source = null
	_link_drag_active = false
	_hide_dev_drag_hint()
	if _path_layer != null and _path_layer.has_method("clear_draft_path"):
		_path_layer.call("clear_draft_path")


func _map_position_for_new_stage_at_global_pos(global_pos: Vector2, source_button: StageButton = null) -> Vector2:
	var local_pos: Vector2 = _map_page.get_global_transform_with_canvas().affine_inverse() * global_pos
	var button_size: Vector2 = source_button.button_size if source_button != null else Vector2(140, 110)
	return local_pos - button_size * 0.5


func _ensure_dev_drag_hint() -> void:
	if _dev_drag_hint_panel != null and is_instance_valid(_dev_drag_hint_panel):
		return
	_dev_drag_hint_layer = CanvasLayer.new()
	_dev_drag_hint_layer.layer = 80
	add_child(_dev_drag_hint_layer)
	_dev_drag_hint_panel = PanelContainer.new()
	_dev_drag_hint_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.08, 0.06, 0.9)
	style.border_color = Color(0.35, 1.0, 0.54, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	_dev_drag_hint_panel.add_theme_stylebox_override("panel", style)
	_dev_drag_hint_layer.add_child(_dev_drag_hint_panel)
	_dev_drag_hint_label = Label.new()
	_dev_drag_hint_label.add_theme_font_size_override("font_size", 15)
	_dev_drag_hint_label.add_theme_color_override("font_color", Color(0.78, 1.0, 0.82, 1.0))
	_dev_drag_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_dev_drag_hint_label.add_theme_constant_override("outline_size", 3)
	_dev_drag_hint_panel.add_child(_dev_drag_hint_label)


func _update_dev_drag_hint(global_pos: Vector2) -> void:
	_ensure_dev_drag_hint()
	if _dev_drag_hint_panel == null or _dev_drag_hint_label == null:
		return
	if _stage_button_contains_global_pos(_link_drag_source, global_pos):
		_dev_drag_hint_label.text = "放開：取消"
		_dev_drag_hint_panel.self_modulate = Color(1.0, 0.9, 0.65, 1.0)
		_dev_drag_hint_panel.visible = true
		_dev_drag_hint_panel.position = global_pos + Vector2(16, -48)
		return
	var target_button: StageButton = _stage_button_at_global_pos(global_pos, _link_drag_source)
	if target_button != null and target_button.stage != null:
		_dev_drag_hint_label.text = "放開：新增前置線 -> %s" % target_button.stage.stage_id
		_dev_drag_hint_panel.self_modulate = Color(0.72, 0.9, 1.0, 1.0)
	else:
		_dev_drag_hint_label.text = "放開：新增關卡"
		_dev_drag_hint_panel.self_modulate = Color(0.72, 1.0, 0.72, 1.0)
	_dev_drag_hint_panel.visible = true
	_dev_drag_hint_panel.position = global_pos + Vector2(16, -48)


func _hide_dev_drag_hint() -> void:
	if _dev_drag_hint_panel != null and is_instance_valid(_dev_drag_hint_panel):
		_dev_drag_hint_panel.visible = false


func _stage_button_contains_global_pos(sb: StageButton, global_pos: Vector2) -> bool:
	if sb == null or sb.stage == null or not sb.visible:
		return false
	var hit_rect: Rect2 = sb.get_spot_hit_global_rect() if sb.has_method("get_spot_hit_global_rect") else sb.get_global_rect()
	return hit_rect.grow(6.0).has_point(global_pos)


func _stage_button_at_global_pos(global_pos: Vector2, except_button: StageButton = null) -> StageButton:
	for sb in _stage_buttons:
		if sb == null or sb == except_button or sb.stage == null or not sb.visible:
			continue
		if _stage_button_contains_global_pos(sb, global_pos):
			return sb
	return null


func _find_stage_button_by_id(stage_id: String) -> StageButton:
	for sb in _stage_buttons:
		if sb != null and sb.stage != null and sb.stage.stage_id == stage_id:
			return sb
	return null


func _create_prerequisite_relation(parent_stage: StageData, child_stage: StageData) -> void:
	if parent_stage == null or child_stage == null:
		return
	var parent_id: String = parent_stage.stage_id
	var child_id: String = child_stage.stage_id
	if parent_id == "" or child_id == "" or parent_id == child_id:
		return
	if _would_create_prerequisite_cycle(parent_id, child_id):
		push_warning("Map: rejected prerequisite cycle %s -> %s" % [parent_id, child_id])
		return

	var old_parent_id: String = child_stage.prerequisite_stage_id
	if old_parent_id != "" and old_parent_id != parent_id:
		var old_parent_button: StageButton = _find_stage_button_by_id(old_parent_id)
		if old_parent_button != null and old_parent_button.stage != null and old_parent_button.stage.connects_to.has(child_id):
			old_parent_button.stage.connects_to.erase(child_id)
			_save_stage(old_parent_button.stage)

	child_stage.prerequisite_stage_id = parent_id
	_save_stage(child_stage)
	if not parent_stage.connects_to.has(child_id):
		parent_stage.connects_to.append(child_id)
	_save_stage(parent_stage)
	_refresh_stage_buttons()


func _remove_prerequisite_relation(parent_id: String, child_id: String) -> void:
	if parent_id == "" or child_id == "":
		return
	var parent_button: StageButton = _find_stage_button_by_id(parent_id)
	var child_button: StageButton = _find_stage_button_by_id(child_id)
	var changed_parent := false
	var changed_child := false
	if parent_button != null and parent_button.stage != null and parent_button.stage.connects_to.has(child_id):
		parent_button.stage.connects_to.erase(child_id)
		changed_parent = true
	if child_button != null and child_button.stage != null and child_button.stage.prerequisite_stage_id == parent_id:
		child_button.stage.prerequisite_stage_id = ""
		changed_child = true
	if changed_parent:
		_save_stage(parent_button.stage)
	if changed_child:
		_save_stage(child_button.stage)
	if changed_parent or changed_child:
		_refresh_stage_buttons()


func _confirm_remove_prerequisite_relation(parent_id: String, child_id: String) -> void:
	if parent_id == "" or child_id == "":
		return
	_pending_remove_relation = {
		"parent_id": parent_id,
		"child_id": child_id,
	}
	if _remove_relation_confirm_dialog == null or not is_instance_valid(_remove_relation_confirm_dialog):
		_remove_relation_confirm_dialog = ConfirmationDialog.new()
		_remove_relation_confirm_dialog.name = "RemoveRelationConfirmDialog"
		_remove_relation_confirm_dialog.title = "確認刪除路線"
		_remove_relation_confirm_dialog.confirmed.connect(_on_remove_relation_confirmed)
		add_child(_remove_relation_confirm_dialog)
		_remove_relation_confirm_dialog.get_ok_button().text = "刪除"
		_remove_relation_confirm_dialog.get_cancel_button().text = "取消"
	_remove_relation_confirm_dialog.dialog_text = "確定要刪除「%s → %s」前置路線嗎？\n這會移除該關卡的前置需求。" % [parent_id, child_id]
	_remove_relation_confirm_dialog.popup_centered(Vector2(420, 170))


func _on_remove_relation_confirmed() -> void:
	var relation: Dictionary = _pending_remove_relation
	_pending_remove_relation = {}
	var parent_id: String = String(relation.get("parent_id", ""))
	var child_id: String = String(relation.get("child_id", ""))
	_remove_prerequisite_relation(parent_id, child_id)


func _try_remove_relation_at_global_pos(global_pos: Vector2) -> bool:
	if _path_layer == null or not _path_layer.has_method("find_relation_at_point"):
		return false
	var local_pos: Vector2 = _map_page.get_global_transform_with_canvas().affine_inverse() * global_pos
	var relation: Dictionary = _path_layer.call("find_relation_at_point", local_pos) as Dictionary
	if relation.is_empty():
		return false
	var parent_id: String = String(relation.get("from_id", ""))
	var child_id: String = String(relation.get("to_id", ""))
	_confirm_remove_prerequisite_relation(parent_id, child_id)
	return true


func _would_create_prerequisite_cycle(parent_id: String, child_id: String) -> bool:
	var current_id: String = parent_id
	var seen: Dictionary = {}
	while current_id != "":
		if current_id == child_id:
			return true
		if seen.has(current_id):
			return true
		seen[current_id] = true
		var current_button: StageButton = _find_stage_button_by_id(current_id)
		if current_button == null or current_button.stage == null:
			return false
		current_id = current_button.stage.prerequisite_stage_id
	return false


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
	if _overlay_layer != null:
		var frame: Node = _overlay_layer.get_node_or_null("OverlayFrame")
		if frame is Control:
			_layout_overlay_frame(frame as Control)
	if _tutorial_editor_panel != null and is_instance_valid(_tutorial_editor_panel):
		_layout_tutorial_editor_panel(_tutorial_editor_panel)


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


# ── World Map Dev and Debug Panel ───────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F4:
			_toggle_dev_mode()
			_set_debug_panel_visible(GameState.dev_mode)
	elif event is InputEventMouseButton and GameState.dev_mode:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			if _try_remove_relation_at_global_pos(get_global_mouse_position()):
				get_viewport().set_input_as_handled()


func _toggle_dev_mode() -> void:
	GameState.dev_mode = not GameState.dev_mode
	if not GameState.dev_mode:
		_clear_stage_link_draft()
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


func _build_dev_mode_back_button() -> void:
	if _portrait_debug_layer == null:
		return
	_dev_mode_back_button = Button.new()
	_dev_mode_back_button.name = "DevModeBackButton"
	_dev_mode_back_button.text = "Back"
	_dev_mode_back_button.tooltip_text = "Exit dev mode"
	_dev_mode_back_button.anchor_left = 0.0
	_dev_mode_back_button.anchor_top = 0.0
	_dev_mode_back_button.offset_left = 16.0
	_dev_mode_back_button.offset_top = 50.0
	_dev_mode_back_button.offset_right = 104.0
	_dev_mode_back_button.offset_bottom = 82.0
	_dev_mode_back_button.add_theme_font_size_override("font_size", 14)
	_dev_mode_back_button.pressed.connect(_on_dev_mode_back_pressed)
	_portrait_debug_layer.add_child(_dev_mode_back_button)


func _refresh_dev_mode_ui() -> void:
	if _dev_mode_label == null:
		return
	_dev_mode_label.visible = GameState.dev_mode
	_dev_mode_label.text = "DEV MODE  F4"
	if _dev_mode_back_button != null:
		_dev_mode_back_button.visible = GameState.dev_mode


func _on_dev_mode_back_pressed() -> void:
	GameState.dev_mode = false
	_clear_stage_link_draft()
	_refresh_dev_mode_ui()
	_refresh_stage_buttons()
	_set_debug_panel_visible(false)


func _set_debug_panel_visible(visible: bool) -> void:
	if visible:
		_show_debug_panel()
	else:
		_close_debug_panel()


func _close_debug_panel() -> void:
	if _debug_panel != null and is_instance_valid(_debug_panel):
		_debug_panel.queue_free()
	_debug_panel = null


func _show_debug_panel() -> void:
	if _debug_panel != null and is_instance_valid(_debug_panel):
		return
	var layer := CanvasLayer.new()
	layer.layer = 64
	add_child(layer)
	_debug_panel = MapDebugPanel.build(layer, func() -> void:
		_refresh_after_save_clear()
	)
	# 關閉時連同 CanvasLayer 一起移除
	_debug_panel.tree_exited.connect(func() -> void:
		if _debug_panel != null and not is_instance_valid(_debug_panel):
			_debug_panel = null
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

	var tutorial_btn: Button = _make_debug_launcher_button("TU", "Tutorial Pages", 16, -310.0, -256.0)
	tutorial_btn.pressed.connect(_open_tutorial_page_editor)
	_portrait_debug_layer.add_child(tutorial_btn)

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


func _open_tutorial_page_editor() -> void:
	if _tutorial_editor_layer != null and is_instance_valid(_tutorial_editor_layer):
		return
	_load_tutorial_page_library()
	_load_tutorial_image_catalog()
	_migrate_legacy_stage_tutorial_pages()
	_tutorial_editor_layer = CanvasLayer.new()
	_tutorial_editor_layer.layer = 72
	add_child(_tutorial_editor_layer)

	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_tutorial_editor_layer.add_child(backdrop)

	var panel := PanelContainer.new()
	_tutorial_editor_panel = panel
	_layout_tutorial_editor_panel(panel)
	panel.add_theme_stylebox_override("panel", _make_tutorial_editor_panel_style(Color(0.06, 0.07, 0.11, 0.98)))
	_tutorial_editor_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	root.add_child(header)

	var title := Label.new()
	title.text = "Tutorial Pages"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(_make_tutorial_editor_button("Add", _on_tutorial_editor_add_pressed, Vector2(62, 30)))
	header.add_child(_make_tutorial_editor_button("Delete", _on_tutorial_editor_delete_pressed, Vector2(72, 30)))
	header.add_child(_make_tutorial_editor_button("Save", _on_tutorial_editor_save_pressed, Vector2(62, 30)))
	header.add_child(_make_tutorial_editor_button("Close", _close_tutorial_page_editor, Vector2(68, 30)))

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(190, 0)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(list_scroll)

	_tutorial_editor_page_list = VBoxContainer.new()
	_tutorial_editor_page_list.add_theme_constant_override("separation", 6)
	_tutorial_editor_page_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(_tutorial_editor_page_list)

	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 8)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(form)

	var image_row := HBoxContainer.new()
	image_row.add_theme_constant_override("separation", 8)
	form.add_child(image_row)

	_tutorial_editor_image_option = OptionButton.new()
	_tutorial_editor_image_option.custom_minimum_size = Vector2(220, 30)
	_tutorial_editor_image_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_populate_tutorial_image_option(_tutorial_editor_image_option, "")
	_tutorial_editor_image_option.item_selected.connect(_on_tutorial_editor_image_selected)
	image_row.add_child(_tutorial_editor_image_option)

	_tutorial_editor_image_preview = TextureRect.new()
	_tutorial_editor_image_preview.custom_minimum_size = Vector2(78, 58)
	_tutorial_editor_image_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tutorial_editor_image_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image_row.add_child(_tutorial_editor_image_preview)

	_tutorial_editor_chi_title_edit = _make_tutorial_editor_line_edit("chi_title")
	_tutorial_editor_chi_title_edit.text_changed.connect(_on_tutorial_editor_chi_title_changed)
	form.add_child(_tutorial_editor_chi_title_edit)

	_tutorial_editor_eng_title_edit = _make_tutorial_editor_line_edit("eng_title")
	_tutorial_editor_eng_title_edit.text_changed.connect(_on_tutorial_editor_eng_title_changed)
	form.add_child(_tutorial_editor_eng_title_edit)

	_tutorial_editor_ch_info_edit = _make_tutorial_editor_text_edit("ch_info")
	_tutorial_editor_ch_info_edit.text_changed.connect(_on_tutorial_editor_ch_info_changed)
	form.add_child(_tutorial_editor_ch_info_edit)

	_tutorial_editor_eng_info_edit = _make_tutorial_editor_text_edit("eng_info")
	_tutorial_editor_eng_info_edit.text_changed.connect(_on_tutorial_editor_eng_info_changed)
	form.add_child(_tutorial_editor_eng_info_edit)

	_tutorial_editor_status_label = Label.new()
	_tutorial_editor_status_label.add_theme_font_size_override("font_size", 12)
	_tutorial_editor_status_label.add_theme_color_override("font_color", Color(0.78, 0.88, 1.0, 0.9))
	root.add_child(_tutorial_editor_status_label)

	if _tutorial_page_library.pages.is_empty():
		_tutorial_page_library.add_page_with_id("tutorial_page")
	_tutorial_editor_selected_index = clampi(_tutorial_editor_selected_index, 0, maxi(0, _tutorial_page_library.pages.size() - 1))
	_refresh_tutorial_editor()


func _close_tutorial_page_editor() -> void:
	if _tutorial_editor_layer != null and is_instance_valid(_tutorial_editor_layer):
		_tutorial_editor_layer.queue_free()
	_tutorial_editor_layer = null
	_tutorial_editor_panel = null
	_tutorial_editor_page_list = null
	_tutorial_editor_image_option = null
	_tutorial_editor_image_preview = null
	_tutorial_editor_chi_title_edit = null
	_tutorial_editor_eng_title_edit = null
	_tutorial_editor_ch_info_edit = null
	_tutorial_editor_eng_info_edit = null
	_tutorial_editor_status_label = null


func _layout_tutorial_editor_panel(panel: Control) -> void:
	if panel == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var margin_x: float = 20.0
	var top_margin: float = 54.0
	var bottom_margin: float = 34.0
	if vp.x < 760.0:
		margin_x = 10.0
	if vp.y < 760.0:
		top_margin = 38.0
		bottom_margin = 22.0
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = margin_x
	panel.offset_right = -margin_x
	panel.offset_top = top_margin
	panel.offset_bottom = -bottom_margin


func _load_tutorial_page_library() -> void:
	if _tutorial_page_library != null:
		return
	if ResourceLoader.exists(TUTORIAL_PAGE_LIBRARY_PATH):
		_tutorial_page_library = load(TUTORIAL_PAGE_LIBRARY_PATH) as TutorialPageLibrary
	if _tutorial_page_library == null:
		_tutorial_page_library = TutorialPageLibraryScript.new() as TutorialPageLibrary
	_tutorial_page_library.ensure_page_ids()


func _save_tutorial_page_library() -> bool:
	_load_tutorial_page_library()
	_tutorial_page_library.ensure_page_ids()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TUTORIAL_PAGE_LIBRARY_PATH.get_base_dir()))
	var err: int = ResourceSaver.save(_tutorial_page_library, TUTORIAL_PAGE_LIBRARY_PATH)
	if err != OK:
		_set_tutorial_editor_status("Save failed (%d)" % err, false)
		return false
	_set_tutorial_editor_status("Saved tutorial pages")
	return true


func _migrate_legacy_stage_tutorial_pages() -> void:
	_load_tutorial_page_library()
	var library_changed := false
	for stage: StageData in _load_all_stage_resources():
		if stage == null or stage.start_stage_tutorial.is_empty():
			continue
		var stage_changed := false
		var had_legacy_pages := false
		for index in stage.start_stage_tutorial.size():
			var legacy_page: StartStageTutorialPage = stage.start_stage_tutorial[index]
			if legacy_page == null or legacy_page.is_blank():
				continue
			had_legacy_pages = true
			var page_id: String = legacy_page.page_id.strip_edges()
			if page_id.is_empty():
				page_id = _tutorial_page_library.make_unique_page_id("%s_tutorial_%d" % [stage.stage_id, index + 1])
			var page: StartStageTutorialPage = _tutorial_page_library.get_page(page_id)
			if page == null:
				page = StartStageTutorialPageScript.new() as StartStageTutorialPage
				page.page_id = page_id
				page.copy_content_from(legacy_page)
				_tutorial_page_library.pages.append(page)
				library_changed = true
			if not stage.start_stage_tutorial_page_ids.has(page_id):
				stage.start_stage_tutorial_page_ids.append(page_id)
				stage_changed = true
		if had_legacy_pages:
			stage.start_stage_tutorial.clear()
			stage_changed = true
		if stage_changed:
			_save_stage(stage)
	if library_changed:
		_save_tutorial_page_library()


func _refresh_tutorial_editor() -> void:
	if _tutorial_editor_page_list == null:
		return
	_tutorial_editor_refreshing = true
	for child in _tutorial_editor_page_list.get_children():
		_tutorial_editor_page_list.remove_child(child)
		child.queue_free()
	_load_tutorial_page_library()
	for index in _tutorial_page_library.pages.size():
		var page: StartStageTutorialPage = _tutorial_page_library.pages[index]
		var btn := Button.new()
		btn.text = _tutorial_page_library.display_name(page)
		btn.toggle_mode = true
		btn.button_pressed = index == _tutorial_editor_selected_index
		btn.custom_minimum_size = Vector2(0, 34)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_tutorial_editor_page_selected.bind(index))
		_tutorial_editor_page_list.add_child(btn)
	_refresh_tutorial_editor_form()
	_tutorial_editor_refreshing = false


func _refresh_tutorial_editor_form() -> void:
	var page: StartStageTutorialPage = _get_selected_tutorial_page()
	var has_page: bool = page != null
	_tutorial_editor_refreshing = true
	if _tutorial_editor_image_option != null:
		_populate_tutorial_image_option(_tutorial_editor_image_option, page.image_path if has_page else "")
	if _tutorial_editor_image_preview != null:
		_set_tutorial_image_preview(_tutorial_editor_image_preview, page.image_path if has_page else "")
	if _tutorial_editor_chi_title_edit != null:
		_tutorial_editor_chi_title_edit.editable = has_page
		_tutorial_editor_chi_title_edit.text = page.chi_title if has_page else ""
	if _tutorial_editor_eng_title_edit != null:
		_tutorial_editor_eng_title_edit.editable = has_page
		_tutorial_editor_eng_title_edit.text = page.eng_title if has_page else ""
	if _tutorial_editor_ch_info_edit != null:
		_tutorial_editor_ch_info_edit.editable = has_page
		_tutorial_editor_ch_info_edit.text = page.ch_info if has_page else ""
	if _tutorial_editor_eng_info_edit != null:
		_tutorial_editor_eng_info_edit.editable = has_page
		_tutorial_editor_eng_info_edit.text = page.eng_info if has_page else ""
	_tutorial_editor_refreshing = false


func _get_selected_tutorial_page() -> StartStageTutorialPage:
	_load_tutorial_page_library()
	if _tutorial_editor_selected_index < 0 or _tutorial_editor_selected_index >= _tutorial_page_library.pages.size():
		return null
	return _tutorial_page_library.pages[_tutorial_editor_selected_index]


func _on_tutorial_editor_page_selected(index: int) -> void:
	_tutorial_editor_selected_index = index
	_refresh_tutorial_editor()


func _on_tutorial_editor_add_pressed() -> void:
	_load_tutorial_page_library()
	var page: StartStageTutorialPage = _tutorial_page_library.add_page_with_id("tutorial_page")
	if not _tutorial_image_catalog.is_empty():
		page.image_path = String(_tutorial_image_catalog[0].get("resource_path", ""))
	_tutorial_editor_selected_index = _tutorial_page_library.pages.size() - 1
	_refresh_tutorial_editor()


func _on_tutorial_editor_delete_pressed() -> void:
	_load_tutorial_page_library()
	var page: StartStageTutorialPage = _get_selected_tutorial_page()
	if page == null:
		return
	var page_id: String = page.page_id
	_tutorial_page_library.pages.remove_at(_tutorial_editor_selected_index)
	for stage: StageData in _load_all_stage_resources():
		if stage == null:
			continue
		var changed := false
		for index in range(stage.start_stage_tutorial_page_ids.size() - 1, -1, -1):
			if stage.start_stage_tutorial_page_ids[index] == page_id:
				stage.start_stage_tutorial_page_ids.remove_at(index)
				changed = true
		if changed:
			_save_stage(stage)
	_tutorial_editor_selected_index = mini(_tutorial_editor_selected_index, _tutorial_page_library.pages.size() - 1)
	_save_tutorial_page_library()
	_refresh_tutorial_editor()


func _on_tutorial_editor_save_pressed() -> void:
	if _save_tutorial_page_library():
		_refresh_tutorial_editor()


func _on_tutorial_editor_image_selected(_item_index: int) -> void:
	if _tutorial_editor_refreshing:
		return
	var page: StartStageTutorialPage = _get_selected_tutorial_page()
	if page == null or _tutorial_editor_image_option == null:
		return
	page.image_path = String(_tutorial_editor_image_option.get_selected_metadata())
	_set_tutorial_image_preview(_tutorial_editor_image_preview, page.image_path)


func _on_tutorial_editor_chi_title_changed(new_text: String) -> void:
	if _tutorial_editor_refreshing:
		return
	var page: StartStageTutorialPage = _get_selected_tutorial_page()
	if page != null:
		page.chi_title = new_text


func _on_tutorial_editor_eng_title_changed(new_text: String) -> void:
	if _tutorial_editor_refreshing:
		return
	var page: StartStageTutorialPage = _get_selected_tutorial_page()
	if page != null:
		page.eng_title = new_text


func _on_tutorial_editor_ch_info_changed() -> void:
	if _tutorial_editor_refreshing:
		return
	var page: StartStageTutorialPage = _get_selected_tutorial_page()
	if page != null and _tutorial_editor_ch_info_edit != null:
		page.ch_info = _tutorial_editor_ch_info_edit.text


func _on_tutorial_editor_eng_info_changed() -> void:
	if _tutorial_editor_refreshing:
		return
	var page: StartStageTutorialPage = _get_selected_tutorial_page()
	if page != null and _tutorial_editor_eng_info_edit != null:
		page.eng_info = _tutorial_editor_eng_info_edit.text


func _load_tutorial_image_catalog() -> void:
	if not _tutorial_image_catalog.is_empty():
		return
	_tutorial_image_catalog.clear()
	_collect_tutorial_images(TUTORIAL_IMAGE_ROOT)
	_tutorial_image_catalog.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("name", "")) < String(b.get("name", ""))
	)


func _collect_tutorial_images(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var subdirs: Array[String] = []
	while true:
		var file_name: String = dir.get_next()
		if file_name == "":
			break
		if file_name.begins_with("."):
			continue
		if dir.current_is_dir():
			subdirs.append(file_name)
			continue
		var lower: String = file_name.to_lower()
		if not (lower.ends_with(".png") or lower.ends_with(".jpg") or lower.ends_with(".jpeg") or lower.ends_with(".webp")):
			continue
		var resource_path := "%s/%s" % [dir_path, file_name]
		_tutorial_image_catalog.append({
			"name": resource_path.trim_prefix(TUTORIAL_IMAGE_ROOT + "/"),
			"resource_path": resource_path,
		})
	dir.list_dir_end()
	for subdir_name in subdirs:
		_collect_tutorial_images(dir_path + "/" + subdir_name)


func _populate_tutorial_image_option(option: OptionButton, selected_path: String) -> void:
	if option == null:
		return
	option.clear()
	option.add_item("No Image")
	option.set_item_metadata(0, "")
	for entry: Dictionary in _tutorial_image_catalog:
		option.add_item(String(entry.get("name", "Image")))
		option.set_item_metadata(option.item_count - 1, String(entry.get("resource_path", "")))
	if not selected_path.is_empty():
		var found := false
		for index in option.item_count:
			if String(option.get_item_metadata(index)) == selected_path:
				found = true
				option.select(index)
				break
		if not found:
			option.add_item(selected_path.get_file())
			option.set_item_metadata(option.item_count - 1, selected_path)
			option.select(option.item_count - 1)
	else:
		option.select(0)


func _set_tutorial_image_preview(preview: TextureRect, image_path: String) -> void:
	if preview == null:
		return
	var path: String = image_path.strip_edges()
	if path.is_empty() or not (ResourceLoader.exists(path) or FileAccess.file_exists(path)):
		preview.texture = null
		return
	preview.texture = load(path) as Texture2D


func _make_tutorial_editor_button(label_text: String, callback: Callable, minimum_size: Vector2) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = minimum_size
	btn.pressed.connect(callback)
	return btn


func _make_tutorial_editor_line_edit(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return edit


func _make_tutorial_editor_text_edit(placeholder: String) -> TextEdit:
	var edit := TextEdit.new()
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(0, 120)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	return edit


func _make_tutorial_editor_panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.42, 0.52, 0.72, 0.92)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	return style


func _set_tutorial_editor_status(text: String, ok: bool = true) -> void:
	if _tutorial_editor_status_label == null:
		return
	_tutorial_editor_status_label.text = text
	_tutorial_editor_status_label.add_theme_color_override("font_color", Color(0.78, 0.95, 0.78, 0.95) if ok else Color(1.0, 0.52, 0.46, 0.95))
