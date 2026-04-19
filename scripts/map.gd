## Map（地圖畫面）— 關卡選擇與隊伍編成介面。
## 玩家可選擇關卡、編成隊伍、檢視角色。
extends Node2D

const STAGE1 := preload("res://stages/stage_dev.tres")  # 第一關預載

var _pending_stage: StageData = null  # 待確認的關卡

# ── 隊伍選擇覆蓋層節點 ──
var _picker_overlay: Control = null      # 覆蓋層根節點
var _picker_grid: GridContainer = null   # 角色網格
var _picker_count_label: Label = null    # 已選數量顯示
var _picker_confirm_btn: Button = null   # 確認按鈕
var _selected_indices: Array[int] = []   # 已選角色索引
var _card_panels: Array[PanelContainer] = []  # 角色卡片面板

# ── 樣式 ──
var _style_normal: StyleBoxFlat     # 未選中樣式
var _style_selected: StyleBoxFlat   # 已選中樣式


func _ready() -> void:
	_style_normal = StyleBoxFlat.new()
	_style_normal.bg_color = Color(0.15, 0.17, 0.25, 1)
	_style_normal.border_width_left = 3
	_style_normal.border_width_top = 3
	_style_normal.border_width_right = 3
	_style_normal.border_width_bottom = 3
	_style_normal.border_color = Color(0.35, 0.4, 0.55, 1)
	_style_normal.corner_radius_top_left = 8
	_style_normal.corner_radius_top_right = 8
	_style_normal.corner_radius_bottom_right = 8
	_style_normal.corner_radius_bottom_left = 8

	_style_selected = StyleBoxFlat.new()
	_style_selected.bg_color = Color(0.2, 0.24, 0.35, 1)
	_style_selected.border_width_left = 3
	_style_selected.border_width_top = 3
	_style_selected.border_width_right = 3
	_style_selected.border_width_bottom = 3
	_style_selected.border_color = Color(1.0, 0.85, 0.2, 1)
	_style_selected.corner_radius_top_left = 8
	_style_selected.corner_radius_top_right = 8
	_style_selected.corner_radius_bottom_right = 8
	_style_selected.corner_radius_bottom_left = 8


## 點擊關卡按鈕時顯示隊伍選擇器
func _on_stage1_pressed() -> void:
	_pending_stage = STAGE1
	_show_party_picker()


## 點擊角色按鈕時前往角色列表畫面
func _on_characters_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/characters.tscn")


# ── 隊伍選擇器覆蓋層 ──────────────────────────────────────────

## 顯示隊伍選擇器（過場動畫覆蓋在地圖上方）
func _show_party_picker() -> void:
	if _picker_overlay != null:
		return
	_selected_indices.clear()
	_card_panels.clear()

	var ui_layer: CanvasLayer = $UILayer

	# Dark overlay background
	_picker_overlay = Control.new()
	_picker_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picker_overlay.offset_right = 576.0
	_picker_overlay.offset_bottom = 1024.0
	ui_layer.add_child(_picker_overlay)

	var dark_bg := ColorRect.new()
	dark_bg.color = Color(0.0, 0.0, 0.0, 0.85)
	dark_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_picker_overlay.add_child(dark_bg)

	# Title
	var title := Label.new()
	title.text = "SELECT PARTY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.offset_left = 0.0
	title.offset_top = 40.0
	title.offset_right = 576.0
	title.offset_bottom = 90.0
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	_picker_overlay.add_child(title)

	# Count label
	_picker_count_label = Label.new()
	_picker_count_label.text = "0 / %d selected" % GameState.MAX_PARTY_SIZE
	_picker_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_picker_count_label.offset_left = 0.0
	_picker_count_label.offset_top = 90.0
	_picker_count_label.offset_right = 576.0
	_picker_count_label.offset_bottom = 115.0
	_picker_count_label.add_theme_font_size_override("font_size", 16)
	_picker_count_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_picker_overlay.add_child(_picker_count_label)

	# Scroll + Grid
	var scroll := ScrollContainer.new()
	scroll.offset_left = 32.0
	scroll.offset_top = 130.0
	scroll.offset_right = 544.0
	scroll.offset_bottom = 880.0
	_picker_overlay.add_child(scroll)

	_picker_grid = GridContainer.new()
	_picker_grid.columns = 2
	_picker_grid.add_theme_constant_override("h_separation", 24)
	_picker_grid.add_theme_constant_override("v_separation", 24)
	_picker_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_picker_grid)

	for i in GameState.owned_characters.size():
		var c: CharacterData = GameState.owned_characters[i]
		var card := _make_picker_card(c, i)
		_picker_grid.add_child(card)
		_card_panels.append(card)

	# 自動選擇前 4 個角色
	var auto_count: int = mini(GameState.owned_characters.size(), GameState.MAX_PARTY_SIZE)
	for i in auto_count:
		_selected_indices.append(i)
		_card_panels[i].add_theme_stylebox_override("panel", _style_selected)
	_picker_count_label.text = "%d / %d selected" % [_selected_indices.size(), GameState.MAX_PARTY_SIZE]

	# Buttons row
	var btn_row := HBoxContainer.new()
	btn_row.offset_left = 100.0
	btn_row.offset_top = 900.0
	btn_row.offset_right = 476.0
	btn_row.offset_bottom = 950.0
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 40)
	_picker_overlay.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(130, 44)
	cancel_btn.pressed.connect(_on_picker_cancel)
	btn_row.add_child(cancel_btn)

	_picker_confirm_btn = Button.new()
	_picker_confirm_btn.text = "Confirm"
	_picker_confirm_btn.custom_minimum_size = Vector2(130, 44)
	_picker_confirm_btn.disabled = _selected_indices.is_empty()
	_picker_confirm_btn.pressed.connect(_on_picker_confirm)
	btn_row.add_child(_picker_confirm_btn)


## 建立選擇器中的角色卡片
func _make_picker_card(c: CharacterData, index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(220, 260)
	panel.add_theme_stylebox_override("panel", _style_normal)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	# Portrait
	if c.portrait_texture:
		var portrait := TextureRect.new()
		portrait.texture = c.portrait_texture
		portrait.custom_minimum_size = Vector2(200, 170)
		portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(portrait)
	else:
		var portrait := ColorRect.new()
		portrait.custom_minimum_size = Vector2(200, 170)
		portrait.color = c.portrait_color
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(portrait)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = c.character_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	# Level + stats
	var info_lbl := Label.new()
	info_lbl.text = "Lv.%d  ATK %d  HP %d" % [c.level, c.get_atk(), c.get_max_hp()]
	info_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info_lbl.add_theme_font_size_override("font_size", 12)
	info_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	info_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(info_lbl)

	panel.gui_input.connect(_on_picker_card_input.bind(index))
	return panel


## 處理選擇器中的角色卡片點擊（選中/取消選中）
func _on_picker_card_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	if _selected_indices.has(index):
		# Deselect
		_selected_indices.erase(index)
		_card_panels[index].add_theme_stylebox_override("panel", _style_normal)
	else:
		# Select (if under max)
		if _selected_indices.size() >= GameState.MAX_PARTY_SIZE:
			return
		_selected_indices.append(index)
		_card_panels[index].add_theme_stylebox_override("panel", _style_selected)

	_picker_count_label.text = "%d / %d selected" % [_selected_indices.size(), GameState.MAX_PARTY_SIZE]
	_picker_confirm_btn.disabled = _selected_indices.is_empty()


## 取消選擇
func _on_picker_cancel() -> void:
	if _picker_overlay != null:
		_picker_overlay.queue_free()
		_picker_overlay = null
	_pending_stage = null


## 確認選擇：儲存隊伍並進入戰鬥（或先進入對話場景）
func _on_picker_confirm() -> void:
	GameState.selected_stage = _pending_stage
	GameState.selected_party.clear()
	for idx in _selected_indices:
		GameState.selected_party.append(GameState.owned_characters[idx])

	# 有對話 → 先進對話場景；否則直接進戰鬥
	if _pending_stage.pre_dialog != null and _pending_stage.pre_dialog.lines.size() > 0:
		get_tree().change_scene_to_file("res://scenes/dialog_box.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/main.tscn")
