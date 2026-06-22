extends Control

const STAT_LEVEL_MIN: int = CharacterData.STAT_LEVEL_MIN
const STAT_LEVEL_MAX: int = CharacterData.STAT_LEVEL_MAX
const STAT_HP_COLOR: Color = Color(0.36, 0.82, 0.96, 1.0)
const STAT_MAGIC_COLOR: Color = Color(0.78, 0.58, 1.0, 1.0)
const STAT_ATK_COLOR: Color = Color(1.0, 0.50, 0.42, 1.0)
const ROW_HEIGHT: float = 184.0
const CHARACTER_COL_WIDTH: float = 112.0
const INFO_COL_WIDTH: float = 184.0
const COFF_SUM_MIN: float = 21.0
const COFF_SUM_MAX: float = 27.0
const COFF_STEP: float = 0.5


class _StatRow:
	var character: CharacterData = null
	var stat_title_lbls: Array[Label] = []
	var growth_edits: Array[LineEdit] = []
	var growth_mode_buttons: Array[Array] = []
	var detail_lbl: Label = null
	var rank_lbl: Label = null
	var sum_lbl: Label = null
	var max_potential_value_lbl: Label = null
	var status_lbl: Label = null
	var radar: Control = null
	var line_chart: Control = null
	var syncing_growth_edits: bool = false
	var syncing_growth_mode_buttons: bool = false


var _rows: Array[_StatRow] = []
var _status_lbl: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.09, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

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
	title_lbl.text = "Stat Debug"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(title_lbl)

	_status_lbl = Label.new()
	_status_lbl.text = "調整 COFF，總點數限制 21～27。"
	_status_lbl.add_theme_font_size_override("font_size", 12)
	_status_lbl.add_theme_color_override("font_color", Color(0.78, 0.82, 0.92))
	_status_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(_status_lbl)

	var save_all_btn := Button.new()
	save_all_btn.text = "Save All"
	save_all_btn.add_theme_font_size_override("font_size", 16)
	save_all_btn.custom_minimum_size = Vector2(96, 40)
	save_all_btn.pressed.connect(_on_save_all_pressed)
	top_bar.add_child(save_all_btn)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.custom_minimum_size = Vector2(44, 40)
	close_btn.pressed.connect(queue_free)
	top_bar.add_child(close_btn)

	var pad_r := Control.new()
	pad_r.custom_minimum_size = Vector2(12, 1)
	pad_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(pad_r)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 52.0
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll)

	var table := VBoxContainer.new()
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table.add_theme_constant_override("separation", 8)
	scroll.add_child(table)

	_build_header_row(table)

	var chars: Array[CharacterData] = GameState.owned_characters
	if chars.is_empty():
		_build_empty_state(table)
		return

	for character: CharacterData in chars:
		_build_character_row(table, character)


func _build_header_row(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.custom_minimum_size = Vector2(0, 34)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 8)
	parent.add_child(header)

	var character_lbl := _make_header_label("Character")
	character_lbl.custom_minimum_size = Vector2(CHARACTER_COL_WIDTH, 0)
	header.add_child(character_lbl)

	var edit_lbl := _make_header_label("HP / MAG / ATK COFF")
	edit_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(edit_lbl)

	var rank_lbl := _make_header_label("Rank / Radar")
	rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_lbl.custom_minimum_size = Vector2(INFO_COL_WIDTH, 0)
	header.add_child(rank_lbl)


func _build_empty_state(parent: VBoxContainer) -> void:
	var empty_lbl := Label.new()
	empty_lbl.text = "No owned characters."
	empty_lbl.add_theme_font_size_override("font_size", 18)
	empty_lbl.add_theme_color_override("font_color", Color(0.82, 0.86, 0.95))
	empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_lbl.custom_minimum_size = Vector2(0, 120)
	empty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(empty_lbl)


func _build_character_row(parent: VBoxContainer, character: CharacterData) -> void:
	var row := _StatRow.new()
	row.character = character
	_rows.append(row)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.075, 0.085, 0.125, 1.0), Color(0.28, 0.30, 0.40, 1.0), 8))
	parent.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(hbox)

	_build_character_cell(hbox, row)

	var stats_area := VBoxContainer.new()
	stats_area.add_theme_constant_override("separation", 6)
	stats_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(stats_area)

	var stats_box := HBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 8)
	stats_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_area.add_child(stats_box)

	for stat_idx: int in 3:
		_build_stat_column(stats_box, row, stat_idx)

	row.line_chart = _StatLinesChart.new()
	row.line_chart.custom_minimum_size = Vector2(0, 70)
	row.line_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.line_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_area.add_child(row.line_chart)

	_build_rank_cell(hbox, row)

	_ensure_row_coff_sum_bounds(row)
	_sync_row_edit_texts(row)
	_sync_row_growth_mode_buttons(row)
	_refresh_row_from_data(row)


func _build_character_cell(parent: HBoxContainer, row: _StatRow) -> void:
	var character: CharacterData = row.character
	var cell := VBoxContainer.new()
	cell.custom_minimum_size = Vector2(CHARACTER_COL_WIDTH, 0)
	cell.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cell.add_theme_constant_override("separation", 6)
	parent.add_child(cell)

	var portrait_wrap := Control.new()
	portrait_wrap.custom_minimum_size = Vector2(92, 92)
	portrait_wrap.clip_contents = true
	cell.add_child(portrait_wrap)

	var card_result: Dictionary = CharacterCard.make_square(character)
	var card: PanelContainer = card_result["panel"] as PanelContainer
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_wrap.add_child(card)

	var name_lbl := Label.new()
	name_lbl.text = Locale.tr_ui(character.character_name)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(name_lbl)

	var level_lbl := Label.new()
	level_lbl.text = "Lv.%d" % character.level
	level_lbl.add_theme_font_size_override("font_size", 12)
	level_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	level_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(level_lbl)

	var max_potential_lbl := Label.new()
	max_potential_lbl.text = "Max Potential"
	max_potential_lbl.add_theme_font_size_override("font_size", 11)
	max_potential_lbl.add_theme_color_override("font_color", Color(0.86, 0.90, 1.0))
	max_potential_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	max_potential_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	max_potential_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(max_potential_lbl)

	row.max_potential_value_lbl = Label.new()
	row.max_potential_value_lbl.text = "-"
	row.max_potential_value_lbl.add_theme_font_size_override("font_size", 17)
	row.max_potential_value_lbl.add_theme_color_override("font_color", Color(0.86, 0.90, 1.0))
	row.max_potential_value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.max_potential_value_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(row.max_potential_value_lbl)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(spacer)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.custom_minimum_size = Vector2(0, 30)
	save_btn.add_theme_font_size_override("font_size", 13)
	save_btn.pressed.connect(_on_row_save_pressed.bind(row))
	cell.add_child(save_btn)

	row.status_lbl = Label.new()
	row.status_lbl.text = "Unsaved"
	row.status_lbl.add_theme_font_size_override("font_size", 10)
	row.status_lbl.add_theme_color_override("font_color", Color(0.70, 0.74, 0.84))
	row.status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.status_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(row.status_lbl)


func _build_stat_column(parent: HBoxContainer, row: _StatRow, stat_idx: int) -> void:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(column)

	var title_lbl := Label.new()
	title_lbl.text = _stat_label(stat_idx)
	title_lbl.add_theme_font_size_override("font_size", 15)
	title_lbl.add_theme_color_override("font_color", _stat_color(stat_idx))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title_lbl)
	row.stat_title_lbls.append(title_lbl)

	var coff_row := HBoxContainer.new()
	coff_row.add_theme_constant_override("separation", 4)
	coff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(coff_row)

	var minus_btn := Button.new()
	minus_btn.text = "-"
	minus_btn.custom_minimum_size = Vector2(30, 30)
	minus_btn.add_theme_font_size_override("font_size", 16)
	minus_btn.pressed.connect(_on_row_growth_step_pressed.bind(row, stat_idx, -COFF_STEP))
	coff_row.add_child(minus_btn)

	var edit := _make_growth_edit(row, stat_idx)
	coff_row.add_child(edit)
	row.growth_edits.append(edit)

	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.custom_minimum_size = Vector2(30, 30)
	plus_btn.add_theme_font_size_override("font_size", 16)
	plus_btn.pressed.connect(_on_row_growth_step_pressed.bind(row, stat_idx, COFF_STEP))
	coff_row.add_child(plus_btn)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 4)
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(mode_row)

	var group := ButtonGroup.new()
	var buttons: Array[Button] = []
	_add_growth_mode_radio(mode_row, buttons, group, "平均", CharacterData.GrowthMode.LINEAR, row, stat_idx)
	_add_growth_mode_radio(mode_row, buttons, group, "後期", CharacterData.GrowthMode.WEAK_EARLY_STRONG_LATE, row, stat_idx)
	_add_growth_mode_radio(mode_row, buttons, group, "早期", CharacterData.GrowthMode.STRONG_EARLY_WEAK_LATE, row, stat_idx)
	row.growth_mode_buttons.append(buttons)


func _build_rank_cell(parent: HBoxContainer, row: _StatRow) -> void:
	var info := VBoxContainer.new()
	info.custom_minimum_size = Vector2(INFO_COL_WIDTH, 0)
	info.size_flags_horizontal = Control.SIZE_SHRINK_END
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	parent.add_child(info)

	row.rank_lbl = Label.new()
	row.rank_lbl.text = "-"
	row.rank_lbl.add_theme_font_size_override("font_size", 16)
	row.rank_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.28))
	row.rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.rank_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.rank_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(row.rank_lbl)

	row.radar = _CoffRadar.new()
	row.radar.custom_minimum_size = Vector2(150, 96)
	row.radar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.radar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(row.radar)

	row.sum_lbl = Label.new()
	row.sum_lbl.text = "-"
	row.sum_lbl.add_theme_font_size_override("font_size", 12)
	row.sum_lbl.add_theme_color_override("font_color", Color(0.86, 0.90, 1.0))
	row.sum_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.sum_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(row.sum_lbl)

	row.detail_lbl = Label.new()
	row.detail_lbl.text = "Lv.-  HP -  MAG -  ATK -"
	row.detail_lbl.add_theme_font_size_override("font_size", 11)
	row.detail_lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	row.detail_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.detail_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_child(row.detail_lbl)


func _make_growth_edit(row: _StatRow, stat_idx: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = "0.0"
	edit.custom_minimum_size = Vector2(56, 30)
	edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	edit.add_theme_font_size_override("font_size", 12)
	edit.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	edit.add_theme_color_override("font_placeholder_color", Color(0.55, 0.58, 0.68))
	edit.text_changed.connect(_on_row_growth_text_changed.bind(row, stat_idx))
	edit.text_submitted.connect(_on_row_growth_text_submitted.bind(row, stat_idx))
	edit.focus_exited.connect(_on_row_growth_focus_exited.bind(row, stat_idx))
	return edit


func _add_growth_mode_radio(parent: HBoxContainer, buttons: Array[Button], group: ButtonGroup, label_text: String, mode_value: int, row: _StatRow, stat_idx: int) -> void:
	var button := Button.new()
	button.text = label_text
	button.toggle_mode = true
	button.button_group = group
	button.custom_minimum_size = Vector2(42, 28)
	button.add_theme_font_size_override("font_size", 11)
	button.tooltip_text = _growth_mode_tooltip(mode_value)
	button.set_meta("growth_mode", mode_value)
	button.pressed.connect(_on_row_growth_mode_button_pressed.bind(row, stat_idx, mode_value))
	parent.add_child(button)
	buttons.append(button)


func _refresh_row_from_data(row: _StatRow) -> void:
	if row.character == null:
		return
	_ensure_row_coff_sum_bounds(row)
	_update_row_totals(row)
	_update_row_detail(row)
	_update_row_rank(row)
	if row.radar != null:
		row.radar.call("set_values", [
			_get_growth_for_stat(row.character, 0),
			_get_growth_for_stat(row.character, 1),
			_get_growth_for_stat(row.character, 2),
		])
	if row.line_chart != null:
		row.line_chart.call("set_character", row.character)


func _update_row_detail(row: _StatRow) -> void:
	if row.detail_lbl == null or row.character == null:
		return
	var level_value: int = clampi(row.character.level, STAT_LEVEL_MIN, STAT_LEVEL_MAX)
	var hp_value: int = row.character.get_max_hp_at_level(level_value)
	var magic_value: int = row.character.get_magic_at_level(level_value)
	var atk_value: int = row.character.get_atk_at_level(level_value)
	row.detail_lbl.text = "Lv.%d  HP %d  MAG %d  ATK %d" % [level_value, hp_value, magic_value, atk_value]


func _update_row_totals(row: _StatRow) -> void:
	if row.character == null:
		return
	var hp_value: int = row.character.get_max_hp_at_level(STAT_LEVEL_MAX)
	var magic_value: int = row.character.get_magic_at_level(STAT_LEVEL_MAX)
	var atk_value: int = row.character.get_atk_at_level(STAT_LEVEL_MAX)
	var total_value: int = hp_value + magic_value + atk_value
	var max_values: Array[int] = [hp_value, magic_value, atk_value]
	for stat_idx: int in mini(row.stat_title_lbls.size(), max_values.size()):
		row.stat_title_lbls[stat_idx].text = "%s\nLv99 %d" % [_stat_label(stat_idx), max_values[stat_idx]]
	if row.max_potential_value_lbl != null:
		row.max_potential_value_lbl.text = "%d" % total_value


func _update_row_rank(row: _StatRow) -> void:
	if row.character == null:
		return
	var sum_value: float = _coff_sum(row.character)
	var rank_text: String = _rank_for_sum(sum_value)
	var style_text: String = _dominant_growth_style(row.character)
	var role_text: String = _best_stat_role(row.character)
	if row.rank_lbl != null:
		row.rank_lbl.text = "%s級的 %s %s" % [rank_text, style_text, role_text]
		row.rank_lbl.add_theme_color_override("font_color", _rank_color(rank_text))
	if row.sum_lbl != null:
		row.sum_lbl.text = "COFF %.1f / %.0f" % [sum_value, COFF_SUM_MAX]


func _sync_row_edit_texts(row: _StatRow) -> void:
	if row.character == null:
		return
	row.syncing_growth_edits = true
	for stat_idx: int in row.growth_edits.size():
		row.growth_edits[stat_idx].text = _format_growth_value(_get_growth_for_stat(row.character, stat_idx))
	row.syncing_growth_edits = false


func _sync_row_growth_mode_buttons(row: _StatRow) -> void:
	if row.character == null:
		return
	row.syncing_growth_mode_buttons = true
	for stat_idx: int in row.growth_mode_buttons.size():
		_select_growth_mode_buttons(row.growth_mode_buttons[stat_idx], _get_growth_mode_for_stat(row.character, stat_idx))
	row.syncing_growth_mode_buttons = false


func _on_row_growth_step_pressed(row: _StatRow, stat_idx: int, delta: float) -> void:
	if row.character == null:
		return
	var next_value: float = _get_growth_for_stat(row.character, stat_idx) + delta
	_set_growth_for_stat_with_sum_clamp(row, stat_idx, next_value)
	_mark_row_unsaved(row)
	_sync_row_edit_texts(row)
	_refresh_row_from_data(row)


func _on_row_growth_text_changed(new_text: String, row: _StatRow, stat_idx: int) -> void:
	_apply_row_growth_edit_text(new_text, row, stat_idx, false)


func _on_row_growth_text_submitted(new_text: String, row: _StatRow, stat_idx: int) -> void:
	_apply_row_growth_edit_text(new_text, row, stat_idx, true)


func _on_row_growth_focus_exited(row: _StatRow, stat_idx: int) -> void:
	_normalize_row_growth_edit(row, stat_idx, true)


func _apply_row_growth_edit_text(new_text: String, row: _StatRow, stat_idx: int, normalize: bool) -> void:
	if row.syncing_growth_edits or row.character == null:
		return
	var clean_text: String = new_text.strip_edges()
	if clean_text == "" or clean_text == "." or clean_text == "-" or clean_text == "-.":
		_mark_row_unsaved(row)
		return
	if not clean_text.is_valid_float():
		return
	_set_growth_for_stat_with_sum_clamp(row, stat_idx, float(clean_text))
	if normalize:
		_sync_row_edit_texts(row)
	_mark_row_unsaved(row)
	_refresh_row_from_data(row)


func _normalize_row_growth_edit(row: _StatRow, stat_idx: int, refresh: bool) -> void:
	if row.character == null or stat_idx >= row.growth_edits.size():
		return
	var edit: LineEdit = row.growth_edits[stat_idx]
	var clean_text: String = edit.text.strip_edges()
	var growth_value: float = _get_growth_for_stat(row.character, stat_idx)
	if clean_text.is_valid_float():
		growth_value = float(clean_text)
	_set_growth_for_stat_with_sum_clamp(row, stat_idx, growth_value)
	_sync_row_edit_texts(row)
	if refresh:
		_mark_row_unsaved(row)
		_refresh_row_from_data(row)


func _on_row_growth_mode_button_pressed(row: _StatRow, stat_idx: int, mode_value: int) -> void:
	if row.syncing_growth_mode_buttons or row.character == null:
		return
	_set_growth_mode_for_stat(row.character, stat_idx, mode_value)
	_mark_row_unsaved(row)
	_refresh_row_from_data(row)


func _commit_row_edits(row: _StatRow) -> void:
	for stat_idx: int in row.growth_edits.size():
		_normalize_row_growth_edit(row, stat_idx, false)
	_ensure_row_coff_sum_bounds(row)
	_sync_row_edit_texts(row)
	_refresh_row_from_data(row)


func _on_row_save_pressed(row: _StatRow) -> void:
	var err: int = _save_row(row)
	if err == OK:
		_set_status("Saved %s" % Locale.tr_ui(row.character.character_name))
	elif err == ERR_UNAVAILABLE:
		_set_status("Cannot save %s: no resource path" % Locale.tr_ui(row.character.character_name))
	else:
		_set_status("Save failed for %s (err=%d)" % [Locale.tr_ui(row.character.character_name), err])


func _on_save_all_pressed() -> void:
	var saved_count: int = 0
	var skipped_count: int = 0
	var failed_count: int = 0
	for row: _StatRow in _rows:
		var err: int = _save_row(row)
		if err == OK:
			saved_count += 1
		elif err == ERR_UNAVAILABLE:
			skipped_count += 1
		else:
			failed_count += 1
	_set_status("Save All: %d saved, %d skipped, %d failed" % [saved_count, skipped_count, failed_count])


func _save_row(row: _StatRow) -> int:
	if row.character == null:
		return ERR_UNAVAILABLE
	_commit_row_edits(row)
	if row.character.resource_path == "":
		_set_row_status(row, "No path", Color(1.0, 0.62, 0.34))
		return ERR_UNAVAILABLE
	var err: int = ResourceSaver.save(row.character, row.character.resource_path)
	if err == OK:
		_set_row_status(row, "Saved", Color(0.58, 1.0, 0.62))
	else:
		_set_row_status(row, "Failed %d" % err, Color(1.0, 0.42, 0.38))
	return err


func _mark_row_unsaved(row: _StatRow) -> void:
	_set_row_status(row, "Unsaved", Color(1.0, 0.92, 0.5))


func _set_row_status(row: _StatRow, text: String, color: Color) -> void:
	if row.status_lbl == null:
		return
	row.status_lbl.text = text
	row.status_lbl.add_theme_color_override("font_color", color)


func _set_status(text: String) -> void:
	if _status_lbl == null:
		return
	_status_lbl.text = text


func _set_growth_for_stat_with_sum_clamp(row: _StatRow, stat_idx: int, requested_value: float) -> void:
	if row.character == null:
		return
	var other_sum: float = 0.0
	for idx: int in 3:
		if idx != stat_idx:
			other_sum += _get_growth_for_stat(row.character, idx)
	var value: float = maxf(requested_value, 0.0)
	value = minf(value, COFF_SUM_MAX - other_sum)
	value = maxf(value, COFF_SUM_MIN - other_sum)
	value = maxf(value, 0.0)
	_set_growth_for_stat(row.character, stat_idx, snappedf(value, 0.1))
	_ensure_row_coff_sum_bounds(row)


func _ensure_row_coff_sum_bounds(row: _StatRow) -> void:
	if row.character == null:
		return
	var sum_value: float = _coff_sum(row.character)
	if sum_value > COFF_SUM_MAX:
		var overflow: float = sum_value - COFF_SUM_MAX
		var stat_idx: int = _best_stat_index(row.character)
		_set_growth_for_stat(row.character, stat_idx, maxf(_get_growth_for_stat(row.character, stat_idx) - overflow, 0.0))
	elif sum_value < COFF_SUM_MIN:
		var deficit: float = COFF_SUM_MIN - sum_value
		var stat_idx: int = _best_stat_index(row.character)
		_set_growth_for_stat(row.character, stat_idx, _get_growth_for_stat(row.character, stat_idx) + deficit)


func _coff_sum(character: CharacterData) -> float:
	return character.hp_growth + character.magic_growth + character.atk_growth


func _get_growth_for_stat(character: CharacterData, stat_idx: int) -> float:
	match stat_idx:
		0:
			return character.hp_growth
		1:
			return character.magic_growth
		2:
			return character.atk_growth
	return 0.0


func _set_growth_for_stat(character: CharacterData, stat_idx: int, growth_value: float) -> void:
	var clean_value: float = maxf(growth_value, 0.0)
	match stat_idx:
		0:
			character.hp_growth = clean_value
		1:
			character.magic_growth = clean_value
		2:
			character.atk_growth = clean_value


func _get_growth_mode_for_stat(character: CharacterData, stat_idx: int) -> int:
	match stat_idx:
		0:
			return character.hp_growth_mode
		1:
			return character.magic_growth_mode
		2:
			return character.atk_growth_mode
	return CharacterData.GrowthMode.LINEAR


func _set_growth_mode_for_stat(character: CharacterData, stat_idx: int, mode_value: int) -> void:
	match stat_idx:
		0:
			character.hp_growth_mode = mode_value as CharacterData.GrowthMode
		1:
			character.magic_growth_mode = mode_value as CharacterData.GrowthMode
		2:
			character.atk_growth_mode = mode_value as CharacterData.GrowthMode


func _select_growth_mode_buttons(buttons: Array, mode_value: int) -> void:
	for button_variant in buttons:
		var button: Button = button_variant as Button
		if button == null:
			continue
		button.set_pressed_no_signal(int(button.get_meta("growth_mode", -1)) == mode_value)


func _format_growth_value(growth_value: float) -> String:
	return "%.1f" % growth_value


func _rank_for_sum(sum_value: float) -> String:
	if sum_value >= 27.0:
		return "S"
	if sum_value >= 24.0:
		return "A"
	return "B"


func _rank_color(rank_text: String) -> Color:
	match rank_text:
		"S":
			return Color(1.0, 0.86, 0.25)
		"A":
			return Color(0.55, 0.92, 1.0)
		"B":
			return Color(0.76, 0.82, 0.92)
	return Color.WHITE


func _dominant_growth_style(character: CharacterData) -> String:
	var weights: Dictionary = {
		CharacterData.GrowthMode.LINEAR: 0.0,
		CharacterData.GrowthMode.WEAK_EARLY_STRONG_LATE: 0.0,
		CharacterData.GrowthMode.STRONG_EARLY_WEAK_LATE: 0.0,
	}
	for stat_idx: int in 3:
		var mode_value: int = _get_growth_mode_for_stat(character, stat_idx)
		weights[mode_value] = float(weights.get(mode_value, 0.0)) + _get_growth_for_stat(character, stat_idx)
	var best_mode: int = CharacterData.GrowthMode.LINEAR
	var best_weight: float = -INF
	for mode_variant in weights.keys():
		var weight: float = float(weights[mode_variant])
		if weight > best_weight:
			best_weight = weight
			best_mode = int(mode_variant)
	return _growth_mode_label(best_mode)


func _best_stat_role(character: CharacterData) -> String:
	match _best_stat_index(character):
		0:
			return "坦克"
		1:
			return "法師"
		2:
			return "攻擊手"
	return "均衡者"


func _best_stat_index(character: CharacterData) -> int:
	var values: Array[float] = [character.hp_growth, character.magic_growth, character.atk_growth]
	var best_idx: int = 0
	var best_value: float = values[0]
	for idx: int in range(1, values.size()):
		if values[idx] > best_value:
			best_value = values[idx]
			best_idx = idx
	return best_idx


func _growth_mode_label(mode_value: int) -> String:
	match mode_value:
		CharacterData.GrowthMode.WEAK_EARLY_STRONG_LATE:
			return "後期"
		CharacterData.GrowthMode.STRONG_EARLY_WEAK_LATE:
			return "早期"
	return "平均"


func _growth_mode_tooltip(mode_value: int) -> String:
	match mode_value:
		CharacterData.GrowthMode.WEAK_EARLY_STRONG_LATE:
			return "後期成長"
		CharacterData.GrowthMode.STRONG_EARLY_WEAK_LATE:
			return "早期成長"
	return "平均成長"


func _stat_label(stat_idx: int) -> String:
	match stat_idx:
		0:
			return "HP"
		1:
			return "MAG"
		2:
			return "ATK"
	return "?"


func _stat_color(stat_idx: int) -> Color:
	match stat_idx:
		0:
			return STAT_HP_COLOR
		1:
			return STAT_MAGIC_COLOR
		2:
			return STAT_ATK_COLOR
	return Color.WHITE


func _make_header_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.92))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_panel_style(bg_color: Color, border_color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.set_border_width_all(1)
	style.border_color = border_color
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(8)
	return style


class _CoffRadar extends Control:
	var _values: Array[float] = [0.0, 0.0, 0.0]
	const _MAX_AXIS_VALUE: float = 9.0

	func set_values(values: Array) -> void:
		for idx: int in mini(values.size(), _values.size()):
			_values[idx] = maxf(float(values[idx]), 0.0)
		queue_redraw()

	func _draw() -> void:
		var center: Vector2 = size * 0.5 + Vector2(0.0, 6.0)
		var radius: float = minf(size.x, size.y) * 0.36
		var axes: Array[Vector2] = [
			Vector2(0.0, -1.0),
			Vector2(-0.866, 0.5),
			Vector2(0.866, 0.5),
		]
		var colors: Array[Color] = [STAT_HP_COLOR, STAT_MAGIC_COLOR, STAT_ATK_COLOR]
		for ring_idx: int in range(1, 4):
			var ring_points: PackedVector2Array = PackedVector2Array()
			var ring_scale: float = float(ring_idx) / 3.0
			for axis: Vector2 in axes:
				ring_points.append(center + axis * radius * ring_scale)
			var closed_ring: PackedVector2Array = ring_points.duplicate()
			closed_ring.append(ring_points[0])
			draw_polyline(closed_ring, Color(0.30, 0.34, 0.46, 0.65), 1.0)
		for idx: int in axes.size():
			draw_line(center, center + axes[idx] * radius, Color(0.48, 0.54, 0.68, 0.72), 1.0)
			draw_circle(center + axes[idx] * (radius + 8.0), 3.0, colors[idx])
		var stat_points: PackedVector2Array = PackedVector2Array()
		for idx: int in axes.size():
			var ratio: float = clampf(_values[idx] / _MAX_AXIS_VALUE, 0.0, 1.0)
			stat_points.append(center + axes[idx] * radius * ratio)
		draw_colored_polygon(stat_points, Color(1.0, 0.86, 0.28, 0.20))
		var closed_stats: PackedVector2Array = stat_points.duplicate()
		closed_stats.append(stat_points[0])
		draw_polyline(closed_stats, Color(1.0, 0.86, 0.28, 1.0), 2.0)
		for point: Vector2 in stat_points:
			draw_circle(point, 3.2, Color(1.0, 0.94, 0.48, 1.0))


class _StatLinesChart extends Control:
	var _character: CharacterData = null

	func set_character(character: CharacterData) -> void:
		_character = character
		queue_redraw()

	func _draw() -> void:
		if _character == null:
			return
		var pad_l: float = 28.0
		var pad_r: float = 10.0
		var pad_t: float = 8.0
		var pad_b: float = 18.0
		var rect := Rect2(pad_l, pad_t, maxf(size.x - pad_l - pad_r, 1.0), maxf(size.y - pad_t - pad_b, 1.0))
		draw_rect(rect, Color(0.035, 0.045, 0.075, 0.72), true)
		draw_rect(rect, Color(0.25, 0.29, 0.40, 0.75), false, 1.0)

		for i in range(1, 4):
			var x: float = rect.position.x + rect.size.x * float(i) / 4.0
			draw_line(Vector2(x, rect.position.y), Vector2(x, rect.position.y + rect.size.y), Color(0.18, 0.21, 0.30, 0.72), 1.0)
		for i in range(1, 3):
			var y: float = rect.position.y + rect.size.y * float(i) / 3.0
			draw_line(Vector2(rect.position.x, y), Vector2(rect.position.x + rect.size.x, y), Color(0.18, 0.21, 0.30, 0.72), 1.0)

		var hp_values: Array[float] = []
		var magic_values: Array[float] = []
		var atk_values: Array[float] = []
		var max_value: float = 1.0
		for level_value: int in range(STAT_LEVEL_MIN, STAT_LEVEL_MAX + 1):
			var hp: float = float(_character.get_max_hp_at_level(level_value))
			var mag: float = float(_character.get_magic_at_level(level_value))
			var atk: float = float(_character.get_atk_at_level(level_value))
			hp_values.append(hp)
			magic_values.append(mag)
			atk_values.append(atk)
			max_value = maxf(max_value, hp)
			max_value = maxf(max_value, mag)
			max_value = maxf(max_value, atk)

		_draw_series(rect, hp_values, max_value, STAT_HP_COLOR)
		_draw_series(rect, magic_values, max_value, STAT_MAGIC_COLOR)
		_draw_series(rect, atk_values, max_value, STAT_ATK_COLOR)

		var font: Font = get_theme_font("font", "Label")
		var font_size: int = 10
		draw_string(font, Vector2(rect.position.x, size.y - 5.0), "Lv1", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.72, 0.78, 0.92))
		draw_string(font, Vector2(rect.position.x + rect.size.x - 24.0, size.y - 5.0), "Lv99", HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, Color(0.72, 0.78, 0.92))
		draw_circle(Vector2(rect.position.x + rect.size.x + 2.0, rect.position.y), 2.8, STAT_HP_COLOR)
		draw_circle(Vector2(rect.position.x + rect.size.x + 2.0, rect.position.y + 9.0), 2.8, STAT_MAGIC_COLOR)
		draw_circle(Vector2(rect.position.x + rect.size.x + 2.0, rect.position.y + 18.0), 2.8, STAT_ATK_COLOR)

	func _draw_series(rect: Rect2, values: Array[float], max_value: float, color: Color) -> void:
		if values.size() < 2:
			return
		var points := PackedVector2Array()
		for idx: int in values.size():
			var x: float = rect.position.x + rect.size.x * float(idx) / float(values.size() - 1)
			var ratio: float = clampf(values[idx] / max_value, 0.0, 1.0)
			var y: float = rect.position.y + rect.size.y * (1.0 - ratio)
			points.append(Vector2(x, y))
		draw_polyline(points, color, 2.2)
