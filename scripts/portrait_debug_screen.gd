## PortraitDebugScreen — 頭像偏移/縮放全局調試介面。
## 4 欄各自模擬真實遊戲場景（寬度跟随 viewport）：
##   0 = Battle Panel  (portrait_scale / portrait_offset)   → 4 張卡片底部列
##   1 = Square Card   (square_scale   / square_offset)     → 7 欄角色格（VP_W/7 每格）
##   2 = Result Row    (rectangular_scale / rectangular_offset) → 戰鬥結算列
##   3 = Dialog Box    (dialog_square_scale / dialog_square_offset) → 對話框底部
##   4 = Dialog Phase  (dialog_phase_scale / dialog_phase_offset)   → 劇情對話大立繪
## 拖拽 = 調整 Offset，滚輪 = 調整 Scale。Save 按鈕寫回 .tres。
extends Control

const _SCALE_STEP: float    = 0.01
const _RECT_IMG_SIZE: float = 1200.0  # battle_result 使用 300×4
const _STAT_LEVEL_MIN: int = 1
const _STAT_LEVEL_MAX: int = 99
const _STAT_HP_COLOR: Color = Color(0.36, 0.82, 0.96, 1.0)
const _STAT_MAGIC_COLOR: Color = Color(0.78, 0.58, 1.0, 1.0)
const _STAT_ATK_COLOR: Color = Color(1.0, 0.50, 0.42, 1.0)
const _DIALOG_PHASE_PREVIEW_MAX_H: float = 640.0
const _LOOT_LOG_PORTRAIT_SLOT_SIZE := Vector2(80.0, 42.0)
const _LOOT_LOG_PORTRAIT_CANVAS_SIZE := Vector2(160.0, 160.0)
const _LOOT_LOG_CHARACTER_PORTRAIT_BASE_OFFSET := Vector2(-16.0, -24.0)
const _LOOT_LOG_ENEMY_PORTRAIT_BASE_OFFSET := Vector2(-40.0, -59.0)
const _ENEMY_ROOT: String = "res://enemies"
## 遊戲 viewport 實際寬度（由 ViewportUtils.get_size().x 動態設定，預設等於專案基準 720px）
var _VP_W: float = 720.0


enum TargetMode { CHARACTER, ENEMY }

## [scale_prop, offset_prop, column_label]
const _CHAR_SYS: Array = [
	["portrait_scale",      "portrait_offset",      "Battle Panel"],
	["square_scale",        "square_offset",        "Square Card"],
	["rectangular_scale",   "rectangular_offset",   "Result Row"],
	["loot_log_scale",      "loot_log_offset",      "Loot Log"],
	["dialog_square_scale", "dialog_square_offset", "Dialog Box"],
	["dialog_phase_scale",  "dialog_phase_offset",  "Dialog Phase"],
]
const _ENEMY_SYS: Array = [
	["info_popup_scale",    "info_popup_offset",    "Info Popup"],
	["dialog_phase_scale",  "dialog_phase_offset",  "Dialog Phase"],
	["loot_log_scale",      "loot_log_offset",      "Loot Log"],
]

var _char_data: CharacterData = null
var _previous_char_data: CharacterData = null
var _enemy_data: EnemyData = null
var _previous_enemy_data: EnemyData = null
var _target_mode: int = TargetMode.CHARACTER
var _mode_char_btn: Button = null
var _mode_enemy_btn: Button = null

## 每欄的「576px 寬場景容器」節點 — rebuild 時清空並填入
var _scene_nodes: Array[Control] = []
## 每欄場景容器的父級 wrapper（用於接收 resized 後更新 scale）
var _wrappers: Array[Control]    = []
## TextureRect（或 null）for each preview card
var _portraits: Array            = []   # untyped: TextureRect or null
## 是否用 anchor offset 定位（rectangular），否則用 .position
var _is_rect: Array[bool]        = [false, false, true, false, false, false]

var _scale_lbls: Array[Label]         = []
var _offset_lbls: Array[Label]        = []
var _drag_active: Array[bool]         = []
var _drag_start_mouse: Array[Vector2] = []
var _drag_start_offset: Array[Vector2] = []
var _char_btns: Array[Button]         = []
var _enemy_btns: Array[Button]        = []
var _hp_chart: StatChart = null
var _magic_chart: StatChart = null
var _atk_chart: StatChart = null
var _hp_growth_edit: LineEdit = null
var _magic_growth_edit: LineEdit = null
var _atk_growth_edit: LineEdit = null
var _hp_growth_mode_opt: OptionButton = null
var _magic_growth_mode_opt: OptionButton = null
var _atk_growth_mode_opt: OptionButton = null
var _stat_max_lbl: Label = null
var _stat_hover_panel_lbl: Label = null
var _stat_detail_level: int = _STAT_LEVEL_MIN
var _syncing_growth_edits: bool = false
var _syncing_growth_mode_options: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for _i: int in _systems().size():
		_drag_active.append(false)
		_drag_start_mouse.append(Vector2.ZERO)
		_drag_start_offset.append(Vector2.ZERO)
		_portraits.append(null)
	_build()


func _systems() -> Array:
	return _ENEMY_SYS if _target_mode == TargetMode.ENEMY else _CHAR_SYS


func _build() -> void:
	_VP_W = ViewportUtils.get_size().x
	# ── 背景 ──
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.09, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# ── 頂部工具列 ──
	var top_bar := HBoxContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 52.0
	top_bar.add_theme_constant_override("separation", 8)
	add_child(top_bar)

	var pad_l := Control.new()
	pad_l.custom_minimum_size = Vector2(12, 1)
	pad_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(pad_l)

	var title_lbl := Label.new()
	title_lbl.text = "Portrait Debug"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(title_lbl)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.add_theme_font_size_override("font_size", 16)
	save_btn.custom_minimum_size = Vector2(74, 40)
	save_btn.pressed.connect(_save)
	top_bar.add_child(save_btn)

	var grant_all_btn := Button.new()
	grant_all_btn.text = "Grant All"
	grant_all_btn.add_theme_font_size_override("font_size", 16)
	grant_all_btn.custom_minimum_size = Vector2(110, 40)
	grant_all_btn.pressed.connect(_on_grant_all_owned_pressed)
	top_bar.add_child(grant_all_btn)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.custom_minimum_size = Vector2(44, 40)
	close_btn.pressed.connect(queue_free)
	top_bar.add_child(close_btn)

	var pad_r := Control.new()
	pad_r.custom_minimum_size = Vector2(12, 1)
	pad_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(pad_r)

	# ── 主體 VBox（top_bar 之下） ──
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.offset_top = 52.0
	main_vbox.add_theme_constant_override("separation", 0)
	add_child(main_vbox)

	# 4 列預覽區（垂直排列，可滾動）
	var preview_scroll := ScrollContainer.new()
	preview_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	main_vbox.add_child(preview_scroll)

	var preview_vbox := VBoxContainer.new()
	preview_vbox.add_theme_constant_override("separation", 4)
	preview_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_scroll.add_child(preview_vbox)

	for i: int in _systems().size():
		_build_preview_col(preview_vbox, i)

	# 分割線
	var divider := ColorRect.new()
	divider.color = Color(0.28, 0.28, 0.35, 1.0)
	divider.custom_minimum_size = Vector2(0, 2)
	main_vbox.add_child(divider)

	# ── 底部角色列表 ──
	var selector_mode_row := HBoxContainer.new()
	selector_mode_row.add_theme_constant_override("separation", 8)
	selector_mode_row.custom_minimum_size = Vector2(0, 40)
	main_vbox.add_child(selector_mode_row)

	var selector_pad := Control.new()
	selector_pad.custom_minimum_size = Vector2(8, 1)
	selector_mode_row.add_child(selector_pad)

	_mode_char_btn = _make_mode_button("Character", TargetMode.CHARACTER)
	selector_mode_row.add_child(_mode_char_btn)
	_mode_enemy_btn = _make_mode_button("Enemy", TargetMode.ENEMY)
	selector_mode_row.add_child(_mode_enemy_btn)
	_refresh_mode_buttons()

	var selector_spacer := Control.new()
	selector_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selector_mode_row.add_child(selector_spacer)

	var char_scroll := ScrollContainer.new()
	char_scroll.custom_minimum_size = Vector2(0, 140)
	char_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	char_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(char_scroll)

	var char_row := HBoxContainer.new()
	char_row.add_theme_constant_override("separation", 6)
	char_scroll.add_child(char_row)

	var cl_pad := Control.new()
	cl_pad.custom_minimum_size = Vector2(8, 1)
	cl_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	char_row.add_child(cl_pad)

	if _target_mode == TargetMode.ENEMY:
		var enemies: Array[EnemyData] = _debug_enemies()
		for i: int in enemies.size():
			_build_enemy_btn(char_row, enemies[i], i)
		if enemies.size() > 0:
			_select_enemy(0, false)
	else:
		var chars: Array[CharacterData] = _debug_characters()
		for i: int in chars.size():
			_build_char_btn(char_row, chars[i], i)
		if chars.size() > 0:
			_select_char(0, false)


func _debug_characters() -> Array[CharacterData]:
	return GameState.get_character_catalog()


func _debug_enemies() -> Array[EnemyData]:
	var result: Array[EnemyData] = []
	_collect_enemy_resources(_ENEMY_ROOT, result)
	result.sort_custom(func(a: EnemyData, b: EnemyData) -> bool:
		var left: String = a.get_display_name() if a != null else ""
		var right: String = b.get_display_name() if b != null else ""
		return left.naturalnocasecmp_to(right) < 0
	)
	return result


func _collect_enemy_resources(dir_path: String, result: Array[EnemyData]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name.is_empty():
			break
		if file_name == "." or file_name == "..":
			continue
		if dir.current_is_dir():
			_collect_enemy_resources("%s/%s" % [dir_path, file_name], result)
			continue
		if not (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			continue
		var resource: Resource = load("%s/%s" % [dir_path, file_name])
		if resource is EnemyData:
			result.append(resource as EnemyData)
	dir.list_dir_end()


func _make_mode_button(label_text: String, mode: int) -> Button:
	var btn := Button.new()
	btn.text = label_text
	btn.toggle_mode = true
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(112, 32)
	btn.pressed.connect(func() -> void:
		_switch_mode(mode)
	)
	return btn


func _switch_mode(mode: int) -> void:
	if _target_mode == mode:
		_refresh_mode_buttons()
		return
	_target_mode = mode
	_rebuild_preserving_selection("")


func _refresh_mode_buttons() -> void:
	if _mode_char_btn != null:
		_mode_char_btn.button_pressed = _target_mode == TargetMode.CHARACTER
	if _mode_enemy_btn != null:
		_mode_enemy_btn.button_pressed = _target_mode == TargetMode.ENEMY


func _selected_target() -> Resource:
	return _enemy_data if _target_mode == TargetMode.ENEMY else _char_data


# ─────────────────────────────────────────────────────────────
# 建立單列（垂直堆疊）：左側資訊欄 + 右側場景預覽
# ─────────────────────────────────────────────────────────────
func _build_preview_col(parent: VBoxContainer, sys_idx: int) -> void:
	# 分隔線（第一個之外都加，在 row 之前插入）
	if sys_idx > 0:
		var div := ColorRect.new()
		div.color = Color(0.25, 0.26, 0.33, 1.0)
		div.custom_minimum_size = Vector2(0, 1)
		div.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent.add_child(div)

	# 每個場景項目是一個 HBoxContainer：左邊資訊 + 右邊預覽
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size   = Vector2(0.0, 0.0)
	parent.add_child(row)

	# ── 左側資訊欄 ──
	var info_vbox := VBoxContainer.new()
	info_vbox.custom_minimum_size   = Vector2(90.0, 0.0)
	info_vbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info_vbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 6)
	info_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info_vbox)

	var sys_lbl := Label.new()
	sys_lbl.text = _systems()[sys_idx][2] as String
	sys_lbl.add_theme_font_size_override("font_size", 13)
	sys_lbl.add_theme_color_override("font_color", Color(0.72, 0.88, 1.0))
	sys_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sys_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(sys_lbl)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(spacer)

	var scale_lbl := Label.new()
	scale_lbl.text = "Scale: 1.00"
	scale_lbl.add_theme_font_size_override("font_size", 12)
	scale_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	scale_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(scale_lbl)
	_scale_lbls.append(scale_lbl)

	var offset_lbl := Label.new()
	offset_lbl.text = "(0, 0)"
	offset_lbl.add_theme_font_size_override("font_size", 11)
	offset_lbl.add_theme_color_override("font_color", Color(0.75, 0.78, 0.88))
	offset_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(offset_lbl)
	_offset_lbls.append(offset_lbl)

	# ── 右側場景預覽 clip wrapper ──
	var wrapper := Control.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN  # 高度由 custom_minimum_size 決定
	wrapper.clip_contents = true
	row.add_child(wrapper)
	_wrappers.append(wrapper)

	var clip_bg := ColorRect.new()
	clip_bg.color = Color(0.08, 0.09, 0.14, 1.0)
	clip_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(clip_bg)

	var scene := Control.new()
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.size = Vector2(_VP_W, 200.0)  # rebuild 時重設
	wrapper.add_child(scene)
	_scene_nodes.append(scene)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var captured: int = sys_idx
	overlay.gui_input.connect(func(ev: InputEvent) -> void:
		_on_preview_input(ev, captured)
	)
	wrapper.add_child(overlay)


# ─────────────────────────────────────────────────────────────
# 潛力數值折線圖（Lv → HP / MAG / ATK）
# ─────────────────────────────────────────────────────────────
func _build_stats_section(parent: VBoxContainer) -> void:
	var section := PanelContainer.new()
	section.custom_minimum_size = Vector2(0.0, 340.0)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.075, 0.085, 0.125, 1.0)
	style.set_border_width_all(1)
	style.border_color = Color(0.28, 0.30, 0.40, 1.0)
	style.set_content_margin_all(10)
	section.add_theme_stylebox_override("panel", style)
	parent.add_child(section)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(header)

	var title_lbl := Label.new()
	title_lbl.text = "Potential Stats"
	title_lbl.add_theme_font_size_override("font_size", 16)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title_lbl)

	_stat_max_lbl = Label.new()
	_stat_max_lbl.text = "Max Lv99: -"
	_stat_max_lbl.add_theme_font_size_override("font_size", 13)
	_stat_max_lbl.add_theme_color_override("font_color", Color(0.86, 0.90, 1.0))
	_stat_max_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_stat_max_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stat_max_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_stat_max_lbl)

	var chart_area := Control.new()
	chart_area.custom_minimum_size = Vector2(0.0, 286.0)
	chart_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(chart_area)

	var charts_row := HBoxContainer.new()
	charts_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	charts_row.add_theme_constant_override("separation", 8)
	chart_area.add_child(charts_row)

	var hp_nodes: Dictionary = _build_stat_chart_column(charts_row, "HP", _STAT_HP_COLOR, 0)
	_hp_chart = hp_nodes["chart"] as StatChart
	_hp_growth_edit = hp_nodes["edit"] as LineEdit
	_hp_growth_mode_opt = hp_nodes["mode"] as OptionButton

	var magic_nodes: Dictionary = _build_stat_chart_column(charts_row, "MAG", _STAT_MAGIC_COLOR, 1)
	_magic_chart = magic_nodes["chart"] as StatChart
	_magic_growth_edit = magic_nodes["edit"] as LineEdit
	_magic_growth_mode_opt = magic_nodes["mode"] as OptionButton

	var atk_nodes: Dictionary = _build_stat_chart_column(charts_row, "ATK", _STAT_ATK_COLOR, 2)
	_atk_chart = atk_nodes["chart"] as StatChart
	_atk_growth_edit = atk_nodes["edit"] as LineEdit
	_atk_growth_mode_opt = atk_nodes["mode"] as OptionButton

	_build_stat_hover_panel(chart_area)


func _build_stat_chart_column(parent: HBoxContainer, stat_label: String, color: Color, stat_idx: int) -> Dictionary:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(column)

	var title_lbl := Label.new()
	title_lbl.text = stat_label
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", color)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title_lbl)

	var chart := StatChart.new()
	chart.setup(stat_label, color)
	chart.custom_minimum_size = Vector2(0.0, 202.0)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart.hover_level.connect(_on_stat_chart_hover_level)
	column.add_child(chart)

	var coff_row := HBoxContainer.new()
	coff_row.add_theme_constant_override("separation", 6)
	coff_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(coff_row)

	var coff_lbl := Label.new()
	coff_lbl.text = "%s COFF" % stat_label
	coff_lbl.add_theme_font_size_override("font_size", 11)
	coff_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	coff_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coff_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coff_row.add_child(coff_lbl)

	var edit := _make_growth_edit(stat_idx)
	coff_row.add_child(edit)

	var mode_opt := _make_growth_mode_option(stat_idx)
	column.add_child(mode_opt)

	return {"chart": chart, "edit": edit, "mode": mode_opt}


func _make_growth_edit(stat_idx: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = "0.000"
	edit.custom_minimum_size = Vector2(72.0, 30.0)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_size_override("font_size", 12)
	edit.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	edit.add_theme_color_override("font_placeholder_color", Color(0.55, 0.58, 0.68))
	edit.text_changed.connect(_on_growth_text_changed.bind(stat_idx))
	edit.text_submitted.connect(_on_growth_text_submitted.bind(stat_idx))
	edit.focus_exited.connect(_on_growth_focus_exited.bind(stat_idx))
	return edit


func _make_growth_mode_option(stat_idx: int) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(0.0, 30.0)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_theme_font_size_override("font_size", 11)
	option.add_item("Linear", CharacterData.GrowthMode.LINEAR)
	option.add_item("Weak Early / Strong Late", CharacterData.GrowthMode.WEAK_EARLY_STRONG_LATE)
	option.add_item("Strong Early / Weak Late", CharacterData.GrowthMode.STRONG_EARLY_WEAK_LATE)
	option.item_selected.connect(_on_growth_mode_selected.bind(stat_idx))
	return option


func _build_stat_hover_panel(parent: Control) -> void:
	var detail_panel := PanelContainer.new()
	detail_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_panel.anchor_left = 1.0
	detail_panel.anchor_right = 1.0
	detail_panel.anchor_top = 0.0
	detail_panel.anchor_bottom = 0.0
	detail_panel.offset_left = -286.0
	detail_panel.offset_right = -8.0
	detail_panel.offset_top = 30.0
	detail_panel.offset_bottom = 82.0
	var detail_style := StyleBoxFlat.new()
	detail_style.bg_color = Color(0.05, 0.06, 0.09, 0.92)
	detail_style.set_border_width_all(1)
	detail_style.border_color = Color(0.72, 0.76, 0.90, 0.38)
	detail_style.set_corner_radius_all(6)
	detail_style.set_content_margin_all(8)
	detail_panel.add_theme_stylebox_override("panel", detail_style)
	parent.add_child(detail_panel)

	_stat_hover_panel_lbl = Label.new()
	_stat_hover_panel_lbl.text = "Lv.-\nHP -  MAG -  ATK -"
	_stat_hover_panel_lbl.add_theme_font_size_override("font_size", 12)
	_stat_hover_panel_lbl.add_theme_color_override("font_color", Color(0.94, 0.96, 1.0))
	_stat_hover_panel_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_panel.add_child(_stat_hover_panel_lbl)


func _refresh_stats_section() -> void:
	if _hp_chart == null or _magic_chart == null or _atk_chart == null:
		return
	if _char_data == null:
		_hp_chart.clear()
		_magic_chart.clear()
		_atk_chart.clear()
		_syncing_growth_edits = true
		if _hp_growth_edit != null:
			_hp_growth_edit.text = ""
		if _magic_growth_edit != null:
			_magic_growth_edit.text = ""
		if _atk_growth_edit != null:
			_atk_growth_edit.text = ""
		_syncing_growth_edits = false
		_syncing_growth_mode_options = true
		_select_growth_mode_option(_hp_growth_mode_opt, CharacterData.GrowthMode.LINEAR)
		_select_growth_mode_option(_magic_growth_mode_opt, CharacterData.GrowthMode.LINEAR)
		_select_growth_mode_option(_atk_growth_mode_opt, CharacterData.GrowthMode.LINEAR)
		_syncing_growth_mode_options = false
		if _stat_max_lbl != null:
			_stat_max_lbl.text = "Max Lv99: -"
		if _stat_hover_panel_lbl != null:
			_stat_hover_panel_lbl.text = "Lv.-\nHP -  MAG -  ATK -"
		return

	_sync_growth_edit_texts()
	_sync_growth_mode_options()
	_stat_detail_level = clampi(_char_data.level, _STAT_LEVEL_MIN, _STAT_LEVEL_MAX)
	_refresh_stat_charts_from_data(true)


func _sync_growth_edit_texts() -> void:
	if _char_data == null:
		return
	_syncing_growth_edits = true
	if _hp_growth_edit != null:
		_hp_growth_edit.text = _format_growth_value(_char_data.hp_growth)
	if _magic_growth_edit != null:
		_magic_growth_edit.text = _format_growth_value(_char_data.magic_growth)
	if _atk_growth_edit != null:
		_atk_growth_edit.text = _format_growth_value(_char_data.atk_growth)
	_syncing_growth_edits = false


func _sync_growth_mode_options() -> void:
	if _char_data == null:
		return
	_syncing_growth_mode_options = true
	_select_growth_mode_option(_hp_growth_mode_opt, _char_data.hp_growth_mode)
	_select_growth_mode_option(_magic_growth_mode_opt, _char_data.magic_growth_mode)
	_select_growth_mode_option(_atk_growth_mode_opt, _char_data.atk_growth_mode)
	_syncing_growth_mode_options = false


func _select_growth_mode_option(option: OptionButton, mode_value: int) -> void:
	if option == null:
		return
	for item_idx: int in option.item_count:
		if option.get_item_id(item_idx) == mode_value:
			option.select(item_idx)
			return


func _refresh_stat_charts_from_data(reset_detail: bool) -> void:
	if _char_data == null:
		return
	if _hp_chart == null or _magic_chart == null or _atk_chart == null:
		return

	var hp_values: Array[int] = []
	var magic_values: Array[int] = []
	var atk_values: Array[int] = []
	for level_value: int in range(_STAT_LEVEL_MIN, _STAT_LEVEL_MAX + 1):
		hp_values.append(_char_data.get_max_hp_at_level(level_value))
		magic_values.append(_char_data.get_magic_at_level(level_value))
		atk_values.append(_char_data.get_atk_at_level(level_value))

	var current_level: int = clampi(_char_data.level, _STAT_LEVEL_MIN, _STAT_LEVEL_MAX)
	_hp_chart.set_series(hp_values, _STAT_LEVEL_MIN, _STAT_LEVEL_MAX, current_level)
	_magic_chart.set_series(magic_values, _STAT_LEVEL_MIN, _STAT_LEVEL_MAX, current_level)
	_atk_chart.set_series(atk_values, _STAT_LEVEL_MIN, _STAT_LEVEL_MAX, current_level)
	_update_max_stat_indicator()
	if reset_detail:
		_stat_detail_level = current_level
	_update_stat_detail_panel(_stat_detail_level)


func _on_stat_chart_hover_level(level_value: int) -> void:
	_update_stat_detail_panel(level_value)


func _update_stat_detail_panel(level_value: int) -> void:
	if _stat_hover_panel_lbl == null or _char_data == null:
		return
	_stat_detail_level = clampi(level_value, _STAT_LEVEL_MIN, _STAT_LEVEL_MAX)
	var hp_value: int = _char_data.get_max_hp_at_level(_stat_detail_level)
	var magic_value: int = _char_data.get_magic_at_level(_stat_detail_level)
	var atk_value: int = _char_data.get_atk_at_level(_stat_detail_level)
	_stat_hover_panel_lbl.text = "Lv.%d\nHP %d  MAG %d  ATK %d" % [_stat_detail_level, hp_value, magic_value, atk_value]


func _update_max_stat_indicator() -> void:
	if _stat_max_lbl == null or _char_data == null:
		return
	var hp_value: int = _char_data.get_max_hp_at_level(_STAT_LEVEL_MAX)
	var magic_value: int = _char_data.get_magic_at_level(_STAT_LEVEL_MAX)
	var atk_value: int = _char_data.get_atk_at_level(_STAT_LEVEL_MAX)
	var total_value: int = hp_value + magic_value + atk_value
	_stat_max_lbl.text = "Max Lv%d  HP %d  MAG %d  ATK %d  Total %d" % [_STAT_LEVEL_MAX, hp_value, magic_value, atk_value, total_value]


func _on_growth_mode_selected(item_idx: int, stat_idx: int) -> void:
	if _syncing_growth_mode_options or _char_data == null:
		return
	var option: OptionButton = _growth_mode_option_for_stat(stat_idx)
	if option == null:
		return
	var mode_value: int = option.get_item_id(item_idx)
	_set_growth_mode_for_stat(stat_idx, mode_value)
	_refresh_stat_charts_from_data(false)


func _on_growth_text_changed(new_text: String, stat_idx: int) -> void:
	_apply_growth_edit_text(new_text, stat_idx, false)


func _on_growth_text_submitted(new_text: String, stat_idx: int) -> void:
	_apply_growth_edit_text(new_text, stat_idx, true)


func _on_growth_focus_exited(stat_idx: int) -> void:
	_normalize_growth_edit(stat_idx)


func _apply_growth_edit_text(new_text: String, stat_idx: int, normalize: bool) -> void:
	if _syncing_growth_edits or _char_data == null:
		return
	var clean_text: String = new_text.strip_edges()
	if clean_text == "" or clean_text == "." or clean_text == "-" or clean_text == "-.":
		return
	if not clean_text.is_valid_float():
		return
	var growth_value: float = maxf(float(clean_text), 0.0)
	_set_growth_for_stat(stat_idx, growth_value)
	if normalize:
		var edit: LineEdit = _growth_edit_for_stat(stat_idx)
		if edit != null:
			_syncing_growth_edits = true
			edit.text = _format_growth_value(growth_value)
			_syncing_growth_edits = false
	_refresh_stat_charts_from_data(false)


func _normalize_growth_edit(stat_idx: int) -> void:
	if _char_data == null:
		return
	var edit: LineEdit = _growth_edit_for_stat(stat_idx)
	if edit == null:
		return
	var clean_text: String = edit.text.strip_edges()
	var growth_value: float = _get_growth_for_stat(stat_idx)
	if clean_text.is_valid_float():
		growth_value = maxf(float(clean_text), 0.0)
		_set_growth_for_stat(stat_idx, growth_value)
	_syncing_growth_edits = true
	edit.text = _format_growth_value(growth_value)
	_syncing_growth_edits = false
	_refresh_stat_charts_from_data(false)


func _commit_growth_edits() -> void:
	if _char_data == null:
		return
	_normalize_growth_edit(0)
	_normalize_growth_edit(1)
	_normalize_growth_edit(2)


func _growth_edit_for_stat(stat_idx: int) -> LineEdit:
	match stat_idx:
		0:
			return _hp_growth_edit
		1:
			return _magic_growth_edit
		2:
			return _atk_growth_edit
	return null


func _get_growth_for_stat(stat_idx: int) -> float:
	if _char_data == null:
		return 0.0
	match stat_idx:
		0:
			return _char_data.hp_growth
		1:
			return _char_data.magic_growth
		2:
			return _char_data.atk_growth
	return 0.0


func _set_growth_for_stat(stat_idx: int, growth_value: float) -> void:
	if _char_data == null:
		return
	match stat_idx:
		0:
			_char_data.hp_growth = growth_value
		1:
			_char_data.magic_growth = growth_value
		2:
			_char_data.atk_growth = growth_value


func _growth_mode_option_for_stat(stat_idx: int) -> OptionButton:
	match stat_idx:
		0:
			return _hp_growth_mode_opt
		1:
			return _magic_growth_mode_opt
		2:
			return _atk_growth_mode_opt
	return null


func _set_growth_mode_for_stat(stat_idx: int, mode_value: int) -> void:
	if _char_data == null:
		return
	match stat_idx:
		0:
			_char_data.hp_growth_mode = mode_value as CharacterData.GrowthMode
		1:
			_char_data.magic_growth_mode = mode_value as CharacterData.GrowthMode
		2:
			_char_data.atk_growth_mode = mode_value as CharacterData.GrowthMode


func _format_growth_value(growth_value: float) -> String:
	return "%.3f" % growth_value


# ─────────────────────────────────────────────────────────────
# 場景不縮放 — 1:1 遊戲像素，讓 wrapper 高度跟隨場景高度
# ─────────────────────────────────────────────────────────────
func _fit_scene_to_wrapper(idx: int) -> void:
	var wrapper: Control = _wrappers[idx]
	var scene: Control   = _scene_nodes[idx]
	scene.scale    = Vector2.ONE
	scene.position = Vector2.ZERO
	# wrapper 高度 = 場景高度，讓外層 HBox row 正確撐開
	wrapper.custom_minimum_size = Vector2(0.0, scene.size.y)


# ─────────────────────────────────────────────────────────────
# 重建單欄的場景內容（切角色後呼叫）
# ─────────────────────────────────────────────────────────────
func _rebuild_preview(idx: int) -> void:
	if _selected_target() == null:
		return
	var scene: Control = _scene_nodes[idx]
	# 清空舊內容
	for child: Node in scene.get_children():
		child.queue_free()

	var portrait_ref: TextureRect = null
	# 各場景高度 = 遊戲實際像素（不縮放）
	# Battle: CharacterRow offset_top=-200 → offset_bottom=-140 → 高度 60px
	# Square: VP_W / 7 ≈ 82px（同 characters_screen / prepare_screen 公式）
	var cell: float = _VP_W / 7.0
	var scene_heights: Array[float] = [60.0, cell, 112.0, 58.0, 190.0, _dialog_phase_preview_height()]
	if _target_mode == TargetMode.ENEMY:
		scene_heights = [240.0, _dialog_phase_preview_height(), 58.0]
	var scene_h: float = scene_heights[idx]

	if _target_mode == TargetMode.ENEMY:
		match idx:
			0:
				portrait_ref = _build_scene_enemy_info_popup(scene, scene_h)
			1:
				portrait_ref = _build_scene_enemy_dialog_phase(scene, scene_h)
			2:
				portrait_ref = _build_scene_loot_log(scene, scene_h)
	else:
		match idx:
			0:
				portrait_ref = _build_scene_battle(scene, scene_h)
			1:
				portrait_ref = _build_scene_square(scene, scene_h)
			2:
				portrait_ref = _build_scene_result(scene, scene_h)
			3:
				portrait_ref = _build_scene_loot_log(scene, scene_h)
			4:
				portrait_ref = _build_scene_dialog(scene, scene_h)
			5:
				portrait_ref = _build_scene_dialog_phase(scene, scene_h)

	scene.size = Vector2(_VP_W, scene_h)
	_portraits[idx] = portrait_ref
	_fit_scene_to_wrapper(idx)
	_refresh_preview(idx)


# ─────────────────────────────────────────────────────────────
# 場景 0：Battle Panel — 4 張卡片水平列（與 CharacterPanel 完全同尺寸）
# CharacterRow: anchor_bottom=1, offset_top=-200, offset_bottom=-140 → 高度 60px
# card_w = VP_W / 4 ≈ 144px，card_h = 60px
# ─────────────────────────────────────────────────────────────
func _build_scene_battle(scene: Control, scene_h: float) -> TextureRect:
	const N_CARDS: int = 4
	var card_w: float = _VP_W / float(N_CARDS)   # 同遊戲：576 / 4 = 144px

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.12, 1.0)
	bg.size = Vector2(_VP_W, scene_h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(bg)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	hbox.position = Vector2(0.0, 0.0)
	hbox.size      = Vector2(_VP_W, scene_h)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(hbox)

	var chars: Array[CharacterData] = _debug_characters()
	var target_idx: int = chars.find(_char_data)
	var portrait_ref: TextureRect = null

	for i: int in N_CARDS:
		# 目標角色放第 0 張，其餘依序填入其他角色作為背景
		var c: CharacterData
		var is_target: bool = (i == 0)
		if i == 0:
			c = _char_data
		else:
			var ci: int = (target_idx + i) % maxi(chars.size(), 1)
			c = chars[ci] if ci < chars.size() else _char_data

		var result: Dictionary = CharacterCard.make_battle(c)
		var card: PanelContainer = result.panel as PanelContainer
		card.custom_minimum_size = Vector2(card_w, scene_h)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(card)

		if is_target and result.portrait != null:
			portrait_ref = result.portrait as TextureRect

	return portrait_ref


# ─────────────────────────────────────────────────────────────
# 場景 1：Square Card — 單張顯示（1 格，cell = VP_W/7 ≈ 82px）
# 只顯示目標角色，方便觀察頭像裁切框
# ─────────────────────────────────────────────────────────────
func _build_scene_square(scene: Control, scene_h: float) -> TextureRect:
	var cell: float = scene_h  # scene_h 已由 _rebuild_preview 設為 _VP_W / 7 ≈ 82px

	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.14, 0.22, 1.0)
	bg.size = Vector2(_VP_W, cell)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(bg)

	var result: Dictionary = CharacterCard.make_square(_char_data)
	var card: PanelContainer = result.panel as PanelContainer
	card.custom_minimum_size = Vector2(cell, cell)
	card.size = Vector2(cell, cell)
	card.position = Vector2.ZERO
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(card)

	var portrait_ref: TextureRect = null
	if result.portrait != null:
		portrait_ref = result.portrait as TextureRect
		# 高亮外框
		var hl := Panel.new()
		var hl_s := StyleBoxFlat.new()
		hl_s.draw_center = false
		hl_s.border_color = Color(1.0, 0.85, 0.2)
		hl_s.set_border_width_all(3)
		hl_s.set_corner_radius_all(10)
		hl.add_theme_stylebox_override("panel", hl_s)
		hl.set_anchors_preset(Control.PRESET_FULL_RECT)
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(hl)

	return portrait_ref


# ─────────────────────────────────────────────────────────────
# 場景 2：Result Row — 戰鬥結算列（矩形頭像底-左錨定）
# ROW_H = 96px + 8px padding，與 battle_result.gd 完全一致
# ─────────────────────────────────────────────────────────────
func _build_scene_result(scene: Control, scene_h: float) -> TextureRect:
	const ROW_H: float = 96.0
	const ROW_TOTAL: float = ROW_H + 8.0   # 104px per row（content margin 6*2 + ROW_H）
	const SIDE: float  = 12.0
	var ROW_W: float = _VP_W - SIDE * 2.0

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.14, 1.0)
	bg.size = Vector2(_VP_W, scene_h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(bg)

	var chars: Array[CharacterData] = _debug_characters()
	var target_idx: int = chars.find(_char_data)
	# 顯示 2 列：目標角色在第 0 列，另一個角色作背景
	const N_ROWS: int = 1
	var portrait_ref: TextureRect = null

	for ri: int in N_ROWS:
		var is_target: bool = (ri == 0)
		var ci: int = (target_idx + ri) % maxi(chars.size(), 1)
		var c: CharacterData = _char_data if is_target else (chars[ci] if ci < chars.size() else _char_data)

		var row := PanelContainer.new()
		row.position = Vector2(SIDE, ri * (ROW_TOTAL + 4.0))
		row.size     = Vector2(ROW_W, ROW_TOTAL)
		var rs := StyleBoxFlat.new()
		rs.bg_color = Color(0.10, 0.12, 0.18, 1.0)
		if is_target:
			rs.bg_color = Color(0.14, 0.17, 0.28, 1.0)
		rs.set_corner_radius_all(8)
		rs.set_content_margin_all(6)
		row.add_theme_stylebox_override("panel", rs)
		row.clip_contents = true
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scene.add_child(row)

		# HBox: placeholder + right info
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hbox)

		var ph := Control.new()
		ph.custom_minimum_size = Vector2(ROW_TOTAL, ROW_TOTAL)
		ph.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		ph.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(ph)

		var rvb := VBoxContainer.new()
		rvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rvb.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		rvb.add_theme_constant_override("separation", 4)
		rvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(rvb)

		var nl := Label.new()
		nl.text = Locale.tr_ui(c.character_name)
		nl.add_theme_font_size_override("font_size", 18)
		nl.add_theme_color_override("font_color", Color.WHITE)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rvb.add_child(nl)

		var ll := Label.new()
		ll.text = "Lv.%d" % c.level
		ll.add_theme_font_size_override("font_size", 16)
		ll.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
		ll.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rvb.add_child(ll)

		# portrait overlay
		var po := Control.new()
		po.mouse_filter = Control.MOUSE_FILTER_IGNORE
		po.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.add_child(po)

		if c.portrait_texture != null:
			var portrait := TextureRect.new()
			portrait.texture     = c.portrait_texture
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			portrait.anchor_left   = 0.0;  portrait.anchor_right  = 0.0
			portrait.anchor_top    = 1.0;  portrait.anchor_bottom = 1.0
			portrait.grow_horizontal = Control.GROW_DIRECTION_END
			portrait.grow_vertical   = Control.GROW_DIRECTION_BEGIN
			portrait.pivot_offset    = Vector2(0.0, _RECT_IMG_SIZE)
			po.add_child(portrait)
			if is_target:
				portrait_ref = portrait

		# 高亮指示
		if is_target:
			var hl_rect := ColorRect.new()
			hl_rect.color = Color(1.0, 0.85, 0.2, 0.08)
			hl_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			hl_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(hl_rect)

	return portrait_ref


# ─────────────────────────────────────────────────────────────
# 場景 3：Dialog Box — 對話面板（PANEL_H=190px，與 battle_dialog.gd 完全一致）
# 142×142 頭像 clip，左邊接文字欄
# ─────────────────────────────────────────────────────────────
func _build_scene_loot_log(scene: Control, scene_h: float) -> TextureRect:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.12, 1.0)
	bg.size = Vector2(_VP_W, scene_h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(bg)

	var toast_size := Vector2(224.0, 46.0)
	var panel := PanelContainer.new()
	panel.position = Vector2(12.0, 6.0)
	panel.size = toast_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(2)
	style.set_content_margin(SIDE_LEFT, 0.0)
	panel.add_theme_stylebox_override("panel", style)
	scene.add_child(panel)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(row)

	var portrait_slot := Control.new()
	portrait_slot.custom_minimum_size = _LOOT_LOG_PORTRAIT_SLOT_SIZE
	portrait_slot.size = _LOOT_LOG_PORTRAIT_SLOT_SIZE
	portrait_slot.clip_contents = true
	portrait_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(portrait_slot)

	var portrait_ref: TextureRect = null
	var portrait_texture: Texture2D = null
	if _target_mode == TargetMode.ENEMY:
		portrait_texture = _enemy_data.portrait_texture if _enemy_data != null else null
	elif _char_data != null:
		portrait_texture = _char_data.portrait_texture

	if portrait_texture != null:
		var portrait := TextureRect.new()
		portrait.texture = portrait_texture
		portrait.size = _LOOT_LOG_PORTRAIT_CANVAS_SIZE
		portrait.custom_minimum_size = _LOOT_LOG_PORTRAIT_CANVAS_SIZE
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var base_position: Vector2 = _LOOT_LOG_ENEMY_PORTRAIT_BASE_OFFSET if _target_mode == TargetMode.ENEMY else _LOOT_LOG_CHARACTER_PORTRAIT_BASE_OFFSET
		portrait.set_meta("debug_base_position", base_position)
		portrait_slot.add_child(portrait)
		portrait_ref = portrait

	var label := Label.new()
	label.text = "Loot Log"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(120.0, 42.0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	return portrait_ref


func _build_scene_dialog(scene: Control, scene_h: float) -> TextureRect:
	const PORTRAIT_SIZE: float = 142.0   # battle_dialog.gd PORTRAIT_SIZE
	const PANEL_H: float       = 190.0   # battle_dialog.gd PANEL_HEIGHT
	const MARGIN: float        = 16.0    # battle_dialog.gd PANEL_MARGIN

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.12, 1.0)
	bg.size  = Vector2(_VP_W, scene_h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(bg)

	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.06, 0.12, 0.94)
	ps.set_corner_radius_all(6)
	ps.set_content_margin_all(MARGIN)
	panel.add_theme_stylebox_override("panel", ps)
	panel.size     = Vector2(_VP_W, PANEL_H)
	panel.position = Vector2(0.0, 0.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	# 142×142 頭像 clip
	var clip := Control.new()
	clip.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(clip)

	var portrait_ref: TextureRect = null
	if _char_data.portrait_texture != null:
		var portrait := TextureRect.new()
		portrait.texture              = _char_data.portrait_texture
		portrait.expand_mode          = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode         = TextureRect.STRETCH_KEEP_ASPECT
		portrait.custom_minimum_size  = Vector2(300.0, 300.0)
		portrait.size                 = Vector2(300.0, 300.0)
		portrait.pivot_offset         = Vector2.ZERO
		portrait.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		clip.add_child(portrait)
		portrait_ref = portrait

	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 8)
	text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(text_vbox)

	var name_lbl := Label.new()
	name_lbl.text = Locale.tr_ui(_char_data.character_name)
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(name_lbl)

	var text_lbl := Label.new()
	text_lbl.text = "..."
	text_lbl.add_theme_font_size_override("font_size", 17)
	text_lbl.add_theme_color_override("font_color", Color.WHITE)
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(text_lbl)

	return portrait_ref


# ─────────────────────────────────────────────────────────────
# 工具：在 scene 上貼標籤文字
# ─────────────────────────────────────────────────────────────
func _build_scene_dialog_phase(scene: Control, scene_h: float) -> TextureRect:
	const PHASE_PORTRAIT_SCALE: float = 7.2
	const PHASE_PORTRAIT_Y_RATIO: float = 0.527
	const PHASE_LEFT_X_RATIO: float = 0.064
	const PHASE_REF_X_RATIO: float = 0.62
	const PHASE_PANEL_H: float = 300.0
	var actual_vp: Vector2 = ViewportUtils.get_size()
	var preview_scale: float = _dialog_phase_preview_scale()
	var preview_size: Vector2 = actual_vp * preview_scale
	scene.set_meta("debug_input_scale", preview_scale)

	var viewport_root := Control.new()
	viewport_root.size = actual_vp
	viewport_root.scale = Vector2(preview_scale, preview_scale)
	viewport_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(viewport_root)

	var bg_tex: Texture2D = load("res://assets/dialog_background/dialog_bg_classroom.png") as Texture2D
	if bg_tex != null:
		var bg := TextureRect.new()
		bg.texture = bg_tex
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.size = actual_vp
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		viewport_root.add_child(bg)
	else:
		var bg_color := ColorRect.new()
		bg_color.color = Color(0.08, 0.09, 0.13, 1.0)
		bg_color.size = actual_vp
		bg_color.mouse_filter = Control.MOUSE_FILTER_IGNORE
		viewport_root.add_child(bg_color)

	var portrait_ref: TextureRect = null
	var portrait_w: float = 300.0 * (PHASE_PORTRAIT_SCALE / 4.0)
	var portrait_h: float = 400.0 * (PHASE_PORTRAIT_SCALE / 4.0)
	var current_base_position := Vector2(
		actual_vp.x * PHASE_LEFT_X_RATIO - (portrait_w - 300.0) * 0.5 - 30.0,
		actual_vp.y * PHASE_PORTRAIT_Y_RATIO - (portrait_h - 400.0)
	)
	portrait_ref = _make_dialog_phase_portrait(
		viewport_root,
		_char_data,
		current_base_position,
		Vector2(portrait_w, portrait_h),
		1.0
	)

	if _previous_char_data != null and _previous_char_data != _char_data:
		var ref_base_position := Vector2(
			actual_vp.x * PHASE_REF_X_RATIO - (portrait_w - 300.0) * 0.5,
			actual_vp.y * PHASE_PORTRAIT_Y_RATIO - (portrait_h - 400.0)
		)
		var ref_portrait := _make_dialog_phase_portrait(
			viewport_root,
			_previous_char_data,
			ref_base_position,
			Vector2(portrait_w, portrait_h),
			0.72
		)
		if ref_portrait != null:
			ref_portrait.scale = Vector2(_previous_char_data.dialog_phase_scale, _previous_char_data.dialog_phase_scale)
			ref_portrait.position = ref_base_position + _previous_char_data.dialog_phase_offset
			_add_dialog_phase_reference_label(viewport_root, _previous_char_data, ref_base_position)

	var panel := PanelContainer.new()
	panel.position = Vector2(0.0, actual_vp.y - PHASE_PANEL_H)
	panel.size = Vector2(actual_vp.x, PHASE_PANEL_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.08, 0.14, 0.92)
	ps.border_color = Color(0.35, 0.35, 0.5, 0.6)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(0)
	ps.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", ps)
	viewport_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = Locale.tr_ui(_char_data.character_name)
	name_lbl.add_theme_font_size_override("font_size", 28)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var text_lbl := Label.new()
	text_lbl.text = "Dialog phase portrait preview"
	text_lbl.add_theme_font_size_override("font_size", 24)
	text_lbl.add_theme_color_override("font_color", Color.WHITE)
	text_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(text_lbl)

	var outline := Panel.new()
	outline.size = preview_size
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline_style := StyleBoxFlat.new()
	outline_style.draw_center = false
	outline_style.border_color = Color(0.5, 0.52, 0.68, 0.65)
	outline_style.set_border_width_all(1)
	outline.add_theme_stylebox_override("panel", outline_style)
	scene.add_child(outline)

	return portrait_ref


func _make_dialog_phase_portrait(parent: Control, character: CharacterData, base_position: Vector2, portrait_size: Vector2, alpha: float) -> TextureRect:
	if character == null or character.portrait_texture == null:
		return null
	var portrait := TextureRect.new()
	portrait.texture = character.portrait_texture
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.size = portrait_size
	portrait.custom_minimum_size = portrait.size
	portrait.pivot_offset = Vector2(portrait_size.x * 0.5, portrait_size.y)
	portrait.modulate = Color(1.0, 1.0, 1.0, alpha)
	portrait.set_meta("debug_base_position", base_position)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(portrait)
	return portrait


func _add_dialog_phase_reference_label(parent: Control, character: CharacterData, base_position: Vector2) -> void:
	var panel := PanelContainer.new()
	panel.position = base_position + Vector2(70.0, 24.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.045, 0.07, 0.74)
	style.border_color = Color(0.9, 0.88, 0.62, 0.42)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var lbl := Label.new()
	lbl.text = "參照物: %s" % Locale.tr_ui(character.character_name)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.94, 0.68, 0.94))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)


func _add_enemy_dialog_phase_reference_label(parent: Control, enemy: EnemyData, base_position: Vector2) -> void:
	var panel := PanelContainer.new()
	panel.position = base_position + Vector2(70.0, 24.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.045, 0.07, 0.74)
	style.border_color = Color(0.9, 0.88, 0.62, 0.42)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)

	var lbl := Label.new()
	lbl.text = "參照物: %s" % enemy.get_display_name()
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.94, 0.68, 0.94))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)


func _dialog_phase_preview_height() -> float:
	return ceil(ViewportUtils.get_size().y * _dialog_phase_preview_scale())


func _dialog_phase_preview_scale() -> float:
	var actual_vp: Vector2 = ViewportUtils.get_size()
	if actual_vp.x <= 0.0 or actual_vp.y <= 0.0:
		return 1.0
	var available_w: float = maxf(_VP_W - 98.0, 360.0)
	return minf(1.0, minf(available_w / actual_vp.x, _DIALOG_PHASE_PREVIEW_MAX_H / actual_vp.y))


func _build_scene_enemy_info_popup(scene: Control, scene_h: float) -> TextureRect:
	if _enemy_data == null:
		return null
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.12, 1.0)
	bg.size = Vector2(_VP_W, scene_h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(bg)

	const PANEL_W: float = 480.0
	const HEADER_H: float = 150.0
	var panel := PanelContainer.new()
	panel.position = Vector2(maxf(12.0, (_VP_W - PANEL_W) * 0.5), 18.0)
	panel.size = Vector2(minf(PANEL_W, _VP_W - 24.0), HEADER_H)
	panel.clip_contents = true
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.18, 0.97)
	style.border_color = Color(0.85, 0.72, 0.30)
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	style.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", style)
	scene.add_child(panel)

	var header := Control.new()
	header.custom_minimum_size = Vector2(panel.size.x, HEADER_H)
	header.clip_contents = true
	panel.add_child(header)

	var portrait_ref: TextureRect = null
	if _enemy_data.portrait_texture != null:
		var portrait := TextureRect.new()
		portrait.texture = _enemy_data.portrait_texture
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.anchor_left = 0.0
		portrait.anchor_top = 1.0
		portrait.anchor_right = 0.0
		portrait.anchor_bottom = 1.0
		portrait.offset_left = 4.0
		portrait.offset_top = -260.0
		portrait.offset_right = 264.0
		portrait.offset_bottom = 0.0
		portrait.set_meta("debug_base_position", Vector2.ZERO)
		portrait.set_meta("debug_enemy_info_popup", true)
		header.add_child(portrait)
		portrait_ref = portrait

	var name_lbl := Label.new()
	name_lbl.text = _enemy_data.get_display_name()
	name_lbl.position = Vector2(156.0, 48.0)
	name_lbl.size = Vector2(maxf(120.0, panel.size.x - 176.0), 42.0)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_lbl.add_theme_font_size_override("font_size", 27)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	name_lbl.add_theme_constant_override("outline_size", 4)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(name_lbl)

	return portrait_ref


func _build_scene_enemy_dialog_phase(scene: Control, scene_h: float) -> TextureRect:
	if _enemy_data == null:
		return null
	const PHASE_PORTRAIT_SCALE: float = 7.2
	const PHASE_PORTRAIT_Y_RATIO: float = 0.527
	const PHASE_LEFT_X_RATIO: float = 0.064
	const PHASE_REF_X_RATIO: float = 0.62
	const PHASE_PANEL_H: float = 300.0
	var actual_vp: Vector2 = ViewportUtils.get_size()
	var preview_scale: float = _dialog_phase_preview_scale()
	var preview_size: Vector2 = actual_vp * preview_scale
	scene.set_meta("debug_input_scale", preview_scale)

	var viewport_root := Control.new()
	viewport_root.size = actual_vp
	viewport_root.scale = Vector2(preview_scale, preview_scale)
	viewport_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(viewport_root)

	var bg_color := ColorRect.new()
	bg_color.color = Color(0.08, 0.09, 0.13, 1.0)
	bg_color.size = actual_vp
	bg_color.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport_root.add_child(bg_color)

	var portrait_ref: TextureRect = null
	var portrait_w: float = 300.0 * (PHASE_PORTRAIT_SCALE / 4.0)
	var portrait_h: float = 400.0 * (PHASE_PORTRAIT_SCALE / 4.0)
	if _enemy_data.portrait_texture != null:
		var base_position := Vector2(
			actual_vp.x * PHASE_LEFT_X_RATIO - (portrait_w - 300.0) * 0.5 - 30.0,
			actual_vp.y * PHASE_PORTRAIT_Y_RATIO - (portrait_h - 400.0)
		)
		var portrait := TextureRect.new()
		portrait.texture = _enemy_data.portrait_texture
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.size = Vector2(portrait_w, portrait_h)
		portrait.custom_minimum_size = portrait.size
		portrait.pivot_offset = Vector2(portrait_w * 0.5, portrait_h)
		portrait.set_meta("debug_base_position", base_position)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		viewport_root.add_child(portrait)
		portrait_ref = portrait

	if _previous_enemy_data != null and _previous_enemy_data != _enemy_data and _previous_enemy_data.portrait_texture != null:
		var ref_base_position := Vector2(
			actual_vp.x * PHASE_REF_X_RATIO - (portrait_w - 300.0) * 0.5,
			actual_vp.y * PHASE_PORTRAIT_Y_RATIO - (portrait_h - 400.0)
		)
		var ref_portrait := TextureRect.new()
		ref_portrait.texture = _previous_enemy_data.portrait_texture
		ref_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ref_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ref_portrait.size = Vector2(portrait_w, portrait_h)
		ref_portrait.custom_minimum_size = ref_portrait.size
		ref_portrait.pivot_offset = Vector2(portrait_w * 0.5, portrait_h)
		ref_portrait.modulate = Color(1.0, 1.0, 1.0, 0.72)
		ref_portrait.position = ref_base_position + _previous_enemy_data.dialog_phase_offset
		ref_portrait.scale = Vector2(_previous_enemy_data.dialog_phase_scale, _previous_enemy_data.dialog_phase_scale)
		ref_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		viewport_root.add_child(ref_portrait)
		_add_enemy_dialog_phase_reference_label(viewport_root, _previous_enemy_data, ref_base_position)

	var panel := PanelContainer.new()
	panel.position = Vector2(0.0, actual_vp.y - PHASE_PANEL_H)
	panel.size = Vector2(actual_vp.x, PHASE_PANEL_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.08, 0.14, 0.92)
	ps.border_color = Color(0.35, 0.35, 0.5, 0.6)
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(0)
	ps.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", ps)
	viewport_root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var name_lbl := Label.new()
	name_lbl.text = _enemy_data.get_display_name()
	name_lbl.add_theme_font_size_override("font_size", 28)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	var text_lbl := Label.new()
	text_lbl.text = "Enemy dialog phase portrait preview"
	text_lbl.add_theme_font_size_override("font_size", 24)
	text_lbl.add_theme_color_override("font_color", Color.WHITE)
	text_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(text_lbl)

	var outline := Panel.new()
	outline.size = preview_size
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outline_style := StyleBoxFlat.new()
	outline_style.draw_center = false
	outline_style.border_color = Color(0.5, 0.52, 0.68, 0.65)
	outline_style.set_border_width_all(1)
	outline.add_theme_stylebox_override("panel", outline_style)
	scene.add_child(outline)

	return portrait_ref


func _add_label(parent: Control, text: String, x: float, y: float, font_size: int) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(x, y)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9, 0.85))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)


# ─────────────────────────────────────────────────────────────
# 建立底部角色按鈕
# ─────────────────────────────────────────────────────────────
func _build_char_btn(parent: HBoxContainer, c: CharacterData, idx: int) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(84, 116)
	btn.clip_contents = true

	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.10, 0.11, 0.16, 1.0)
	sbox.set_corner_radius_all(6)
	sbox.set_border_width_all(2)
	sbox.border_color = Color(0.28, 0.30, 0.40, 1.0)
	btn.add_theme_stylebox_override("normal",  sbox)
	btn.add_theme_stylebox_override("hover",   sbox)
	btn.add_theme_stylebox_override("pressed", sbox)
	btn.add_theme_stylebox_override("focus",   sbox)
	parent.add_child(btn)
	_char_btns.append(btn)

	if c.portrait_texture != null:
		var tex := TextureRect.new()
		tex.texture = c.portrait_texture
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		tex.expand_mode  = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(tex)

	var name_bg := ColorRect.new()
	name_bg.color = Color(0, 0, 0, 0.65)
	name_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_bg.offset_top = -26.0
	name_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(name_bg)

	var name_lbl := Label.new()
	name_lbl.text = Locale.tr_ui(c.character_name)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_lbl.offset_top = -24.0
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(name_lbl)

	var sel := Panel.new()
	sel.name = "SelBorder"
	var sel_style := StyleBoxFlat.new()
	sel_style.draw_center = false
	sel_style.border_color = Color(1.0, 0.85, 0.2)
	sel_style.set_border_width_all(3)
	sel_style.set_corner_radius_all(6)
	sel.add_theme_stylebox_override("panel", sel_style)
	sel.set_anchors_preset(Control.PRESET_FULL_RECT)
	sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel.visible = false
	btn.add_child(sel)

	var ci: int = idx
	btn.pressed.connect(func() -> void: _select_char(ci))


func _build_enemy_btn(parent: HBoxContainer, enemy_data: EnemyData, idx: int) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(104, 116)
	btn.clip_contents = true

	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.10, 0.11, 0.16, 1.0)
	sbox.set_corner_radius_all(6)
	sbox.set_border_width_all(2)
	sbox.border_color = Color(0.28, 0.30, 0.40, 1.0)
	btn.add_theme_stylebox_override("normal",  sbox)
	btn.add_theme_stylebox_override("hover",   sbox)
	btn.add_theme_stylebox_override("pressed", sbox)
	btn.add_theme_stylebox_override("focus",   sbox)
	parent.add_child(btn)
	_enemy_btns.append(btn)

	if enemy_data.portrait_texture != null:
		var tex := TextureRect.new()
		tex.texture = enemy_data.portrait_texture
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(tex)

	var name_bg := ColorRect.new()
	name_bg.color = Color(0, 0, 0, 0.65)
	name_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_bg.offset_top = -30.0
	name_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(name_bg)

	var name_lbl := Label.new()
	name_lbl.text = enemy_data.get_display_name()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_lbl.offset_top = -28.0
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(name_lbl)

	var sel := Panel.new()
	sel.name = "SelBorder"
	var sel_style := StyleBoxFlat.new()
	sel_style.draw_center = false
	sel_style.border_color = Color(1.0, 0.85, 0.2)
	sel_style.set_border_width_all(3)
	sel_style.set_corner_radius_all(6)
	sel.add_theme_stylebox_override("panel", sel_style)
	sel.set_anchors_preset(Control.PRESET_FULL_RECT)
	sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel.visible = false
	btn.add_child(sel)

	var enemy_index: int = idx
	btn.pressed.connect(func() -> void: _select_enemy(enemy_index))


# ─────────────────────────────────────────────────────────────
# 邏輯
# ─────────────────────────────────────────────────────────────
func _select_char(idx: int, record_previous: bool = true) -> void:
	var chars: Array[CharacterData] = _debug_characters()
	if idx < 0 or idx >= chars.size():
		return
	var next_char: CharacterData = chars[idx]
	if record_previous and _char_data != null and _char_data != next_char:
		_previous_char_data = _char_data
	_char_data = next_char
	for j: int in _char_btns.size():
		var sel: Node = _char_btns[j].get_node_or_null("SelBorder")
		if sel != null:
			(sel as Control).visible = (j == idx)
	for i: int in _systems().size():
		_rebuild_preview(i)


func _select_enemy(idx: int, record_previous: bool = true) -> void:
	var enemies: Array[EnemyData] = _debug_enemies()
	if idx < 0 or idx >= enemies.size():
		return
	var next_enemy: EnemyData = enemies[idx]
	if record_previous and _enemy_data != null and _enemy_data != next_enemy:
		_previous_enemy_data = _enemy_data
	_enemy_data = next_enemy
	for j: int in _enemy_btns.size():
		var sel: Node = _enemy_btns[j].get_node_or_null("SelBorder")
		if sel != null:
			(sel as Control).visible = (j == idx)
	for i: int in _systems().size():
		_rebuild_preview(i)


func _on_grant_all_owned_pressed() -> void:
	if _target_mode == TargetMode.ENEMY:
		return
	var selected_path: String = _char_data.resource_path if _char_data != null else ""
	GameState.debug_grant_all_characters(true)
	_rebuild_preserving_selection(selected_path)


func _rebuild_preserving_selection(selected_path: String) -> void:
	for child in get_children():
		child.queue_free()
	_scene_nodes.clear()
	_wrappers.clear()
	_portraits.clear()
	_scale_lbls.clear()
	_offset_lbls.clear()
	_char_btns.clear()
	_enemy_btns.clear()
	_drag_active.clear()
	_drag_start_mouse.clear()
	_drag_start_offset.clear()
	for _i: int in _systems().size():
		_drag_active.append(false)
		_drag_start_mouse.append(Vector2.ZERO)
		_drag_start_offset.append(Vector2.ZERO)
		_portraits.append(null)
	_char_data = null
	_enemy_data = null
	_hp_chart = null
	_magic_chart = null
	_atk_chart = null
	_hp_growth_edit = null
	_magic_growth_edit = null
	_atk_growth_edit = null
	_hp_growth_mode_opt = null
	_magic_growth_mode_opt = null
	_atk_growth_mode_opt = null
	_stat_max_lbl = null
	_stat_hover_panel_lbl = null
	_syncing_growth_edits = false
	_syncing_growth_mode_options = false
	_build()
	if selected_path == "":
		return
	if _target_mode == TargetMode.ENEMY:
		var enemies: Array[EnemyData] = _debug_enemies()
		for i in enemies.size():
			var enemy_data: EnemyData = enemies[i]
			if enemy_data != null and enemy_data.resource_path == selected_path:
				_select_enemy(i, false)
				return
	else:
		var chars: Array[CharacterData] = _debug_characters()
		for i in chars.size():
			var character: CharacterData = chars[i]
			if character != null and character.resource_path == selected_path:
				_select_char(i, false)
				return


func _on_preview_input(ev: InputEvent, idx: int) -> void:
	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_active[idx]       = true
				_drag_start_mouse[idx]  = mb.global_position
				_drag_start_offset[idx] = _get_offset(idx)
			else:
				_drag_active[idx] = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_set_scale(idx, snappedf(_get_scale(idx) + _SCALE_STEP, 0.001))
			_refresh_preview(idx)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_set_scale(idx, maxf(snappedf(_get_scale(idx) - _SCALE_STEP, 0.001), 0.05))
			_refresh_preview(idx)
	elif ev is InputEventMouseMotion and _drag_active[idx]:
		var mm: InputEventMouseMotion = ev as InputEventMouseMotion
		# scene は 1:1 スケールなのでマウス delta = ゲーム pixel delta
		var input_scale: float = _preview_input_scale(idx)
		var delta: Vector2 = (mm.global_position - _drag_start_mouse[idx]) / input_scale
		_set_offset(idx, _drag_start_offset[idx] + delta)
		_refresh_preview(idx)


func _refresh_preview(idx: int) -> void:
	if _selected_target() == null:
		return
	var portrait_node = _portraits[idx]
	if portrait_node == null:
		return
	var portrait: TextureRect = portrait_node as TextureRect
	var scale_v: float    = _get_scale(idx)
	var offset_v: Vector2 = _get_offset(idx)

	if bool(portrait.get_meta("debug_enemy_info_popup", false)):
		portrait.scale = Vector2(scale_v, scale_v)
		portrait.offset_left = 4.0 + offset_v.x
		portrait.offset_top = -260.0 + offset_v.y
		portrait.offset_right = 264.0 + offset_v.x
		portrait.offset_bottom = offset_v.y
	elif _is_rect_preview(idx):
		portrait.scale         = Vector2(scale_v, scale_v)
		portrait.offset_left   = 0.0             + offset_v.x
		portrait.offset_top    = -_RECT_IMG_SIZE + offset_v.y
		portrait.offset_right  = _RECT_IMG_SIZE  + offset_v.x
		portrait.offset_bottom = 0.0             + offset_v.y
	else:
		portrait.scale    = Vector2(scale_v, scale_v)
		var base_position: Vector2 = portrait.get_meta("debug_base_position", Vector2.ZERO)
		portrait.position = base_position + offset_v

	_scale_lbls[idx].text  = "Scale: %.2f" % scale_v
	_offset_lbls[idx].text = "(%.0f, %.0f)" % [offset_v.x, offset_v.y]


func _get_scale(idx: int) -> float:
	var target: Resource = _selected_target()
	if target == null:
		return 1.0
	return target.get(_systems()[idx][0]) as float


func _set_scale(idx: int, v: float) -> void:
	var target: Resource = _selected_target()
	if target == null:
		return
	target.set(_systems()[idx][0], v)


func _get_offset(idx: int) -> Vector2:
	var target: Resource = _selected_target()
	if target == null:
		return Vector2.ZERO
	return target.get(_systems()[idx][1]) as Vector2


func _set_offset(idx: int, v: Vector2) -> void:
	var target: Resource = _selected_target()
	if target == null:
		return
	target.set(_systems()[idx][1], v)


func _is_rect_preview(idx: int) -> bool:
	return _target_mode == TargetMode.CHARACTER and idx >= 0 and idx < _is_rect.size() and _is_rect[idx]


func _preview_input_scale(idx: int) -> float:
	if idx < 0 or idx >= _scene_nodes.size():
		return 1.0
	var scene: Control = _scene_nodes[idx]
	if scene == null:
		return 1.0
	return maxf(0.01, float(scene.get_meta("debug_input_scale", 1.0)))


func _save() -> void:
	var target: Resource = _selected_target()
	if target == null or target.resource_path == "":
		return
	if _target_mode == TargetMode.CHARACTER:
		_commit_growth_edits()
	var err: int = ResourceSaver.save(target, target.resource_path)
	if err != OK:
		push_warning("PortraitDebugScreen: save failed for %s (err=%d)" % [target.resource_path, err])
