extends Control

const STAT_LEVEL_MIN: int = CharacterData.STAT_LEVEL_MIN
const STAT_LEVEL_MAX: int = CharacterData.STAT_LEVEL_MAX
const STAT_HP_COLOR: Color = Color(0.36, 0.82, 0.96, 1.0)
const STAT_MAGIC_COLOR: Color = Color(0.78, 0.58, 1.0, 1.0)
const STAT_ATK_COLOR: Color = Color(1.0, 0.50, 0.42, 1.0)
const ROW_HEIGHT: float = 194.0
const CHARACTER_COL_WIDTH: float = 112.0
const STAT_CHART_HEIGHT: float = 54.0


class _StatRow:
	var character: CharacterData = null
	var charts: Array[StatChart] = []
	var stat_title_lbls: Array[Label] = []
	var growth_edits: Array[LineEdit] = []
	var growth_mode_options: Array[OptionButton] = []
	var detail_lbl: Label = null
	var max_potential_value_lbl: Label = null
	var status_lbl: Label = null
	var detail_level: int = 1
	var syncing_growth_edits: bool = false
	var syncing_growth_mode_options: bool = false


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
	_status_lbl.text = "Edit rows, then Save or Save All"
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

	var stat_header := HBoxContainer.new()
	stat_header.add_theme_constant_override("separation", 8)
	stat_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(stat_header)

	for stat_idx: int in 3:
		var stat_lbl := _make_header_label(_stat_label(stat_idx))
		stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stat_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stat_header.add_child(stat_lbl)


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
	row.detail_level = clampi(character.level, STAT_LEVEL_MIN, STAT_LEVEL_MAX)
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

	var stats_box := VBoxContainer.new()
	stats_box.add_theme_constant_override("separation", 5)
	stats_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(stats_box)

	var chart_row := HBoxContainer.new()
	chart_row.add_theme_constant_override("separation", 8)
	chart_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stats_box.add_child(chart_row)

	for stat_idx: int in 3:
		_build_stat_column(chart_row, row, stat_idx)

	row.detail_lbl = Label.new()
	row.detail_lbl.text = "Lv.-  HP -  MAG -  ATK -"
	row.detail_lbl.add_theme_font_size_override("font_size", 12)
	row.detail_lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	row.detail_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_box.add_child(row.detail_lbl)

	_sync_row_edit_texts(row)
	_sync_row_growth_mode_options(row)
	_refresh_row_from_data(row, true)


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
	save_btn.custom_minimum_size = Vector2(0, 32)
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
	column.add_theme_constant_override("separation", 4)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(column)

	var title_lbl := Label.new()
	title_lbl.text = _stat_label(stat_idx)
	title_lbl.add_theme_font_size_override("font_size", 14)
	title_lbl.add_theme_color_override("font_color", _stat_color(stat_idx))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title_lbl)
	row.stat_title_lbls.append(title_lbl)

	var chart := StatChart.new()
	chart.setup(_stat_label(stat_idx), _stat_color(stat_idx))
	chart.custom_minimum_size = Vector2(0, STAT_CHART_HEIGHT)
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chart.hover_level.connect(_on_row_chart_hover_level.bind(row))
	column.add_child(chart)
	row.charts.append(chart)

	var coff_row := HBoxContainer.new()
	coff_row.add_theme_constant_override("separation", 4)
	coff_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(coff_row)

	var coff_lbl := Label.new()
	coff_lbl.text = "COFF"
	coff_lbl.add_theme_font_size_override("font_size", 10)
	coff_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	coff_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	coff_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coff_row.add_child(coff_lbl)

	var edit := _make_growth_edit(row, stat_idx)
	coff_row.add_child(edit)
	row.growth_edits.append(edit)

	var mode_opt := _make_growth_mode_option(row, stat_idx)
	coff_row.add_child(mode_opt)
	row.growth_mode_options.append(mode_opt)


func _make_growth_edit(row: _StatRow, stat_idx: int) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = "0.000"
	edit.custom_minimum_size = Vector2(58, 28)
	edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	edit.add_theme_font_size_override("font_size", 11)
	edit.add_theme_color_override("font_color", Color(0.96, 0.98, 1.0))
	edit.add_theme_color_override("font_placeholder_color", Color(0.55, 0.58, 0.68))
	edit.text_changed.connect(_on_row_growth_text_changed.bind(row, stat_idx))
	edit.text_submitted.connect(_on_row_growth_text_submitted.bind(row, stat_idx))
	edit.focus_exited.connect(_on_row_growth_focus_exited.bind(row, stat_idx))
	return edit


func _make_growth_mode_option(row: _StatRow, stat_idx: int) -> OptionButton:
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(72, 28)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_theme_font_size_override("font_size", 10)
	option.fit_to_longest_item = false
	option.tooltip_text = "Linear / Weak Early Strong Late / Strong Early Weak Late"
	option.add_item("Linear", CharacterData.GrowthMode.LINEAR)
	option.add_item("Late", CharacterData.GrowthMode.WEAK_EARLY_STRONG_LATE)
	option.add_item("Early", CharacterData.GrowthMode.STRONG_EARLY_WEAK_LATE)
	option.item_selected.connect(_on_row_growth_mode_selected.bind(row, stat_idx))
	return option


func _refresh_row_from_data(row: _StatRow, reset_detail: bool) -> void:
	if row.character == null or row.charts.size() < 3:
		return
	var hp_values: Array[int] = []
	var magic_values: Array[int] = []
	var atk_values: Array[int] = []
	for level_value: int in range(STAT_LEVEL_MIN, STAT_LEVEL_MAX + 1):
		hp_values.append(row.character.get_max_hp_at_level(level_value))
		magic_values.append(row.character.get_magic_at_level(level_value))
		atk_values.append(row.character.get_atk_at_level(level_value))

	var current_level: int = clampi(row.character.level, STAT_LEVEL_MIN, STAT_LEVEL_MAX)
	row.charts[0].set_series(hp_values, STAT_LEVEL_MIN, STAT_LEVEL_MAX, current_level)
	row.charts[1].set_series(magic_values, STAT_LEVEL_MIN, STAT_LEVEL_MAX, current_level)
	row.charts[2].set_series(atk_values, STAT_LEVEL_MIN, STAT_LEVEL_MAX, current_level)
	_update_row_total(row)
	if reset_detail:
		row.detail_level = current_level
	_update_row_detail(row, row.detail_level)


func _on_row_chart_hover_level(level_value: int, row: _StatRow) -> void:
	_update_row_detail(row, level_value)


func _update_row_detail(row: _StatRow, level_value: int) -> void:
	if row.detail_lbl == null or row.character == null:
		return
	row.detail_level = clampi(level_value, STAT_LEVEL_MIN, STAT_LEVEL_MAX)
	var hp_value: int = row.character.get_max_hp_at_level(row.detail_level)
	var magic_value: int = row.character.get_magic_at_level(row.detail_level)
	var atk_value: int = row.character.get_atk_at_level(row.detail_level)
	row.detail_lbl.text = "Lv.%d  HP %d  MAG %d  ATK %d" % [row.detail_level, hp_value, magic_value, atk_value]


func _update_row_total(row: _StatRow) -> void:
	if row.character == null:
		return
	var hp_value: int = row.character.get_max_hp_at_level(STAT_LEVEL_MAX)
	var magic_value: int = row.character.get_magic_at_level(STAT_LEVEL_MAX)
	var atk_value: int = row.character.get_atk_at_level(STAT_LEVEL_MAX)
	var total_value: int = hp_value + magic_value + atk_value
	var max_values: Array[int] = [hp_value, magic_value, atk_value]
	for stat_idx: int in mini(row.stat_title_lbls.size(), max_values.size()):
		row.stat_title_lbls[stat_idx].text = "%s (%d)" % [_stat_label(stat_idx), max_values[stat_idx]]
	if row.max_potential_value_lbl != null:
		row.max_potential_value_lbl.text = "%d" % total_value


func _sync_row_edit_texts(row: _StatRow) -> void:
	if row.character == null:
		return
	row.syncing_growth_edits = true
	for stat_idx: int in row.growth_edits.size():
		row.growth_edits[stat_idx].text = _format_growth_value(_get_growth_for_stat(row.character, stat_idx))
	row.syncing_growth_edits = false


func _sync_row_growth_mode_options(row: _StatRow) -> void:
	if row.character == null:
		return
	row.syncing_growth_mode_options = true
	for stat_idx: int in row.growth_mode_options.size():
		_select_growth_mode_option(row.growth_mode_options[stat_idx], _get_growth_mode_for_stat(row.character, stat_idx))
	row.syncing_growth_mode_options = false


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
	var growth_value: float = maxf(float(clean_text), 0.0)
	_set_growth_for_stat(row.character, stat_idx, growth_value)
	if normalize and stat_idx < row.growth_edits.size():
		row.syncing_growth_edits = true
		row.growth_edits[stat_idx].text = _format_growth_value(growth_value)
		row.syncing_growth_edits = false
	_mark_row_unsaved(row)
	_refresh_row_from_data(row, false)


func _normalize_row_growth_edit(row: _StatRow, stat_idx: int, refresh: bool) -> void:
	if row.character == null or stat_idx >= row.growth_edits.size():
		return
	var edit: LineEdit = row.growth_edits[stat_idx]
	var clean_text: String = edit.text.strip_edges()
	var growth_value: float = _get_growth_for_stat(row.character, stat_idx)
	if clean_text.is_valid_float():
		growth_value = maxf(float(clean_text), 0.0)
		_set_growth_for_stat(row.character, stat_idx, growth_value)
	row.syncing_growth_edits = true
	edit.text = _format_growth_value(growth_value)
	row.syncing_growth_edits = false
	if refresh:
		_mark_row_unsaved(row)
		_refresh_row_from_data(row, false)


func _on_row_growth_mode_selected(item_idx: int, row: _StatRow, stat_idx: int) -> void:
	if row.syncing_growth_mode_options or row.character == null:
		return
	if stat_idx >= row.growth_mode_options.size():
		return
	var option: OptionButton = row.growth_mode_options[stat_idx]
	var mode_value: int = option.get_item_id(item_idx)
	_set_growth_mode_for_stat(row.character, stat_idx, mode_value)
	_mark_row_unsaved(row)
	_refresh_row_from_data(row, false)


func _commit_row_edits(row: _StatRow) -> void:
	for stat_idx: int in row.growth_edits.size():
		_normalize_row_growth_edit(row, stat_idx, false)
	_refresh_row_from_data(row, false)


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
	match stat_idx:
		0:
			character.hp_growth = growth_value
		1:
			character.magic_growth = growth_value
		2:
			character.atk_growth = growth_value


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


func _select_growth_mode_option(option: OptionButton, mode_value: int) -> void:
	if option == null:
		return
	for item_idx: int in option.item_count:
		if option.get_item_id(item_idx) == mode_value:
			option.select(item_idx)
			return


func _format_growth_value(growth_value: float) -> String:
	return "%.3f" % growth_value


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
