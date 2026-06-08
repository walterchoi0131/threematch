extends Control

const ENEMY_ROOT: String = "res://enemies"
const ENEMY_IMAGE_ROOT: String = "res://assets/enemy"
const STAT_LEVEL_MIN: int = CharacterData.STAT_LEVEL_MIN
const STAT_LEVEL_MAX: int = CharacterData.STAT_LEVEL_MAX

class _ActionDropRow extends HBoxContainer:
	var owner_screen: Control = null

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return owner_screen != null and owner_screen.has_method("_is_action_drag_data") and bool(owner_screen.call("_is_action_drag_data", data))

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if owner_screen != null and owner_screen.has_method("_drop_action_at_end"):
			owner_screen.call("_drop_action_at_end", data)


class _ActionPaletteRow extends HBoxContainer:
	var owner_screen: Control = null

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return owner_screen != null and owner_screen.has_method("_can_drop_action_on_palette") and bool(owner_screen.call("_can_drop_action_on_palette", data))

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if owner_screen != null and owner_screen.has_method("_drop_action_on_palette"):
			owner_screen.call("_drop_action_on_palette", data)


class _ActionChip extends Button:
	var action_type: int = EnemyData.ActionType.ATTACK_15
	var attack_percent: int = EnemyData.ATTACK_PERCENT_DEFAULT
	var action_count: int = EnemyData.ACTION_COUNT_DEFAULT
	var source_index: int = -1
	var owner_screen: Control = null

	func _get_drag_data(_at_position: Vector2) -> Variant:
		var preview := Label.new()
		preview.text = text
		preview.add_theme_font_size_override("font_size", 16)
		preview.add_theme_color_override("font_color", Color.WHITE)
		set_drag_preview(preview)
		var drag_percent: int = attack_percent
		if source_index < 0 and action_type == EnemyData.ActionType.ATTACK_15 and owner_screen != null and owner_screen.has_method("_current_attack_percent"):
			drag_percent = int(owner_screen.call("_current_attack_percent"))
		var drag_count: int = action_count
		if source_index < 0 and action_type == EnemyData.ActionType.BREAK_LIGHT_ATTACK and owner_screen != null and owner_screen.has_method("_current_action_count"):
			drag_percent = int(owner_screen.call("_current_attack_percent"))
			drag_count = int(owner_screen.call("_current_action_count"))
		return {
			"action_type": action_type,
			"attack_percent": drag_percent,
			"action_count": drag_count,
			"source_index": source_index,
		}

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		if owner_screen == null or not owner_screen.has_method("_is_action_drag_data") or not bool(owner_screen.call("_is_action_drag_data", data)):
			return false
		if source_index >= 0:
			return true
		return owner_screen.has_method("_can_drop_action_on_palette") and bool(owner_screen.call("_can_drop_action_on_palette", data))

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if owner_screen == null:
			return
		if source_index >= 0 and owner_screen.has_method("_drop_action_on_index"):
			owner_screen.call("_drop_action_on_index", source_index, data)
		elif owner_screen.has_method("_drop_action_on_palette"):
			owner_screen.call("_drop_action_on_palette", data)


class _PassiveDropRow extends HBoxContainer:
	var owner_screen: Control = null

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return owner_screen != null and owner_screen.has_method("_is_passive_drag_data") and bool(owner_screen.call("_is_passive_drag_data", data))

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if owner_screen != null and owner_screen.has_method("_drop_passive_at_end"):
			owner_screen.call("_drop_passive_at_end", data)


class _PassivePaletteRow extends HBoxContainer:
	var owner_screen: Control = null

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return owner_screen != null and owner_screen.has_method("_can_drop_passive_on_palette") and bool(owner_screen.call("_can_drop_passive_on_palette", data))

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if owner_screen != null and owner_screen.has_method("_drop_passive_on_palette"):
			owner_screen.call("_drop_passive_on_palette", data)


class _PassiveChip extends Button:
	var passive_type: int = EnemyData.PassiveType.REQUIRE_GEM_COUNT_DAMAGE_GATE
	var source_index: int = -1
	var owner_screen: Control = null

	func _get_drag_data(_at_position: Vector2) -> Variant:
		var preview := Label.new()
		preview.text = text
		preview.add_theme_font_size_override("font_size", 16)
		preview.add_theme_color_override("font_color", Color.WHITE)
		set_drag_preview(preview)
		return {
			"passive_type": passive_type,
			"source_index": source_index,
		}

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		if owner_screen == null or not owner_screen.has_method("_is_passive_drag_data") or not bool(owner_screen.call("_is_passive_drag_data", data)):
			return false
		if source_index >= 0:
			return true
		return owner_screen.has_method("_can_drop_passive_on_palette") and bool(owner_screen.call("_can_drop_passive_on_palette", data))

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if owner_screen == null:
			return
		if source_index >= 0 and owner_screen.has_method("_drop_passive_on_index"):
			owner_screen.call("_drop_passive_on_index", source_index, data)
		elif owner_screen.has_method("_drop_passive_on_palette"):
			owner_screen.call("_drop_passive_on_palette", data)


var _enemy_entries: Array[Dictionary] = []
var _image_entries: Array[Dictionary] = []
var _selected_enemy: EnemyData = null
var _selected_path: String = ""
var _action_sequence: Array[int] = []
var _action_percents: Array[int] = []
var _action_counts: Array[int] = []
var _passive_sequence: Array[int] = []

var _status_lbl: Label = null
var _detail_body: Control = null
var _enemy_row: HBoxContainer = null
var _image_picker_panel: PanelContainer = null
var _name_edit: LineEdit = null
var _name_zh_edit: LineEdit = null
var _name_en_edit: LineEdit = null
var _hp_slider: HSlider = null
var _hp_value_lbl: Label = null
var _element_option: OptionButton = null
var _passive_gem_option: OptionButton = null
var _passive_count_spin: SpinBox = null
var _passive_summary_lbl: Label = null
var _passive_row: _PassiveDropRow = null
var _portrait_preview: TextureRect = null
var _attack_percent_slider: HSlider = null
var _attack_percent_lbl: Label = null
var _attack_palette_chip: _ActionChip = null
var _lightbreak_count_spin: SpinBox = null
var _lightbreak_palette_chip: _ActionChip = null
var _action_row: _ActionDropRow = null
var _estimate_info_lbl: Label = null
var _estimate_level_value: int = STAT_LEVEL_MIN


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_reload_enemies()
	_reload_images()
	_refresh_enemy_row()
	if not _enemy_entries.is_empty():
		_select_enemy(0)
	else:
		_refresh_detail()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.09, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	_build_top_bar(root)
	_build_estimate_bar(root)
	_build_detail_area(root)
	_build_enemy_strip(root)
	_build_image_picker()


func _build_top_bar(parent: VBoxContainer) -> void:
	var top_bar := HBoxContainer.new()
	top_bar.custom_minimum_size = Vector2(0, 52)
	top_bar.add_theme_constant_override("separation", 8)
	parent.add_child(top_bar)

	var pad_l := Control.new()
	pad_l.custom_minimum_size = Vector2(12, 1)
	top_bar.add_child(pad_l)

	var title_lbl := Label.new()
	title_lbl.text = "Monster Debug"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar.add_child(title_lbl)

	_status_lbl = Label.new()
	_status_lbl.text = ""
	_status_lbl.add_theme_font_size_override("font_size", 12)
	_status_lbl.add_theme_color_override("font_color", Color(0.78, 0.82, 0.92))
	_status_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(_status_lbl)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.custom_minimum_size = Vector2(74, 40)
	save_btn.pressed.connect(_save_selected_enemy)
	top_bar.add_child(save_btn)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(44, 40)
	close_btn.pressed.connect(queue_free)
	top_bar.add_child(close_btn)

	var pad_r := Control.new()
	pad_r.custom_minimum_size = Vector2(12, 1)
	top_bar.add_child(pad_r)


func _build_estimate_bar(parent: VBoxContainer) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 58)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.07, 0.08, 0.13, 0.96), Color(0.28, 0.31, 0.42, 1.0), 8))
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	_estimate_info_lbl = Label.new()
	_estimate_info_lbl.text = "Player team estimated HP/ATK: hover Lv 1-99"
	_estimate_info_lbl.add_theme_font_size_override("font_size", 12)
	_estimate_info_lbl.add_theme_color_override("font_color", Color(0.86, 0.90, 1.0))
	box.add_child(_estimate_info_lbl)

	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 1)
	bar.custom_minimum_size = Vector2(0, 20)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(bar)

	for level_value in range(STAT_LEVEL_MIN, STAT_LEVEL_MAX + 1):
		var segment := ColorRect.new()
		var progress: float = float(level_value - STAT_LEVEL_MIN) / float(STAT_LEVEL_MAX - STAT_LEVEL_MIN)
		segment.color = Color(0.22 + progress * 0.55, 0.48 + progress * 0.22, 0.92, 0.95)
		segment.custom_minimum_size = Vector2(3, 18)
		segment.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		segment.mouse_filter = Control.MOUSE_FILTER_STOP
		segment.tooltip_text = _estimate_text(level_value)
		segment.mouse_entered.connect(_on_estimate_level_hovered.bind(level_value))
		bar.add_child(segment)


func _build_detail_area(parent: VBoxContainer) -> void:
	var detail_panel := PanelContainer.new()
	detail_panel.custom_minimum_size = Vector2(0, 360)
	detail_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.065, 0.075, 0.12, 0.96), Color(0.30, 0.33, 0.46, 1.0), 8))
	parent.add_child(detail_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	detail_panel.add_child(margin)

	_detail_body = VBoxContainer.new()
	(_detail_body as VBoxContainer).add_theme_constant_override("separation", 12)
	_detail_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(_detail_body)


func _build_enemy_strip(parent: VBoxContainer) -> void:
	var divider := ColorRect.new()
	divider.color = Color(0.28, 0.28, 0.35, 1.0)
	divider.custom_minimum_size = Vector2(0, 2)
	parent.add_child(divider)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 132)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)

	_enemy_row = HBoxContainer.new()
	_enemy_row.add_theme_constant_override("separation", 8)
	scroll.add_child(_enemy_row)


func _build_image_picker() -> void:
	_image_picker_panel = PanelContainer.new()
	_image_picker_panel.visible = false
	_image_picker_panel.set_anchors_preset(Control.PRESET_CENTER)
	_image_picker_panel.offset_left = -300.0
	_image_picker_panel.offset_top = -260.0
	_image_picker_panel.offset_right = 300.0
	_image_picker_panel.offset_bottom = 260.0
	_image_picker_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.04, 0.07, 0.98), Color(0.48, 0.50, 0.66, 1.0), 8))
	add_child(_image_picker_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_image_picker_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	box.add_child(header)

	var title := Label.new()
	title.text = "Create Enemy From Image"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(40, 32)
	close_btn.pressed.connect(func() -> void:
		_image_picker_panel.visible = false
	)
	header.add_child(close_btn)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	box.add_child(scroll)

	var grid := GridContainer.new()
	grid.name = "ImageGrid"
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)


func _reload_enemies() -> void:
	_enemy_entries.clear()
	_collect_enemy_resources(ENEMY_ROOT, _enemy_entries)
	_enemy_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("label", "")).naturalnocasecmp_to(String(b.get("label", ""))) < 0
	)


func _collect_enemy_resources(dir_path: String, results: Array[Dictionary]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_collect_enemy_resources("%s/%s" % [dir_path, file_name], results)
		elif file_name.ends_with(".tres") or file_name.ends_with(".res"):
			var resource_path: String = "%s/%s" % [dir_path, file_name]
			var resource: Resource = load(resource_path)
			if resource is EnemyData:
				var enemy_data: EnemyData = resource as EnemyData
				results.append({
					"data": enemy_data,
					"path": resource_path,
					"label": "%s %s" % [enemy_data.get_display_name(), resource_path],
				})
		file_name = dir.get_next()
	dir.list_dir_end()


func _reload_images() -> void:
	_image_entries.clear()
	_collect_enemy_images(ENEMY_IMAGE_ROOT, _image_entries)
	_image_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_path: String = String(a.get("path", ""))
		var b_path: String = String(b.get("path", ""))
		var a_weight: int = 0 if a_path.find("/generated/") >= 0 else -1
		var b_weight: int = 0 if b_path.find("/generated/") >= 0 else -1
		if a_weight != b_weight:
			return a_weight < b_weight
		return a_path.naturalnocasecmp_to(b_path) < 0
	)
	_refresh_image_picker()


func _collect_enemy_images(dir_path: String, results: Array[Dictionary]) -> void:
	var normalized: String = dir_path.replace("\\", "/")
	if normalized.find("/set") >= 0:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if dir.current_is_dir():
			if not file_name.begins_with("."):
				_collect_enemy_images("%s/%s" % [dir_path, file_name], results)
		elif _is_image_file(file_name):
			var image_path: String = "%s/%s" % [dir_path, file_name]
			results.append({"path": image_path, "name": image_path.get_file().get_basename()})
		file_name = dir.get_next()
	dir.list_dir_end()


func _is_image_file(file_name: String) -> bool:
	var lower_name: String = file_name.to_lower()
	return lower_name.ends_with(".png") or lower_name.ends_with(".jpg") or lower_name.ends_with(".jpeg") or lower_name.ends_with(".webp")


func _refresh_enemy_row() -> void:
	if _enemy_row == null:
		return
	for child in _enemy_row.get_children():
		_enemy_row.remove_child(child)
		child.queue_free()

	var pad := Control.new()
	pad.custom_minimum_size = Vector2(8, 1)
	_enemy_row.add_child(pad)

	for i in _enemy_entries.size():
		var entry: Dictionary = _enemy_entries[i]
		var enemy_data: EnemyData = entry.get("data") as EnemyData
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(112, 112)
		btn.tooltip_text = String(entry.get("path", ""))
		btn.toggle_mode = true
		btn.button_pressed = enemy_data == _selected_enemy
		btn.pressed.connect(_select_enemy.bind(i))
		btn.add_theme_stylebox_override("normal", _make_button_style(Color(0.08, 0.09, 0.14, 0.95), Color(0.32, 0.34, 0.46, 1.0)))
		btn.add_theme_stylebox_override("pressed", _make_button_style(Color(0.18, 0.16, 0.08, 0.98), Color(1.0, 0.82, 0.24, 1.0)))
		_enemy_row.add_child(btn)

		var content := VBoxContainer.new()
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(content)

		var image := TextureRect.new()
		image.custom_minimum_size = Vector2(96, 78)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture = enemy_data.portrait_texture
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(image)

		var label := Label.new()
		label.text = enemy_data.get_display_name()
		label.add_theme_font_size_override("font_size", 11)
		label.add_theme_color_override("font_color", Color.WHITE)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(label)

	var end_pad := Control.new()
	end_pad.custom_minimum_size = Vector2(8, 1)
	_enemy_row.add_child(end_pad)


func _refresh_image_picker() -> void:
	if _image_picker_panel == null:
		return
	var grid: GridContainer = _image_picker_panel.get_node_or_null("MarginContainer/VBoxContainer/ScrollContainer/ImageGrid") as GridContainer
	if grid == null:
		return
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for i in _image_entries.size():
		var entry: Dictionary = _image_entries[i]
		var texture: Texture2D = load(String(entry.get("path", ""))) as Texture2D
		if texture == null:
			continue
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(128, 118)
		btn.tooltip_text = String(entry.get("path", ""))
		btn.pressed.connect(_create_enemy_from_image.bind(i))
		grid.add_child(btn)

		var content := VBoxContainer.new()
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(content)

		var image := TextureRect.new()
		image.custom_minimum_size = Vector2(112, 86)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		image.texture = texture
		image.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(image)

		var label := Label.new()
		label.text = String(entry.get("name", ""))
		label.add_theme_font_size_override("font_size", 10)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(label)


func _select_enemy(index: int) -> void:
	if index < 0 or index >= _enemy_entries.size():
		return
	var entry: Dictionary = _enemy_entries[index]
	_selected_enemy = entry.get("data") as EnemyData
	_selected_path = String(entry.get("path", ""))
	_action_sequence.clear()
	_action_percents.clear()
	_action_counts.clear()
	_passive_sequence.clear()
	if _selected_enemy != null:
		for i in _selected_enemy.action_pattern.size():
			var action: EnemyData.ActionType = _selected_enemy.action_pattern[i]
			_action_sequence.append(int(action))
			_action_percents.append(_selected_enemy.get_action_percent_at(i))
			_action_counts.append(_selected_enemy.get_action_count_at(i))
		if int(_selected_enemy.passive_type) != EnemyData.PassiveType.NONE:
			_passive_sequence.append(int(_selected_enemy.passive_type))
	_refresh_detail()
	if _estimate_info_lbl != null:
		_estimate_level_value = STAT_LEVEL_MIN
		_refresh_estimate_info()
	_refresh_enemy_row()
	_set_status("")


func _refresh_detail() -> void:
	if _detail_body == null:
		return
	for child in _detail_body.get_children():
		_detail_body.remove_child(child)
		child.queue_free()
	_hp_slider = null
	_hp_value_lbl = null
	_element_option = null
	_passive_gem_option = null
	_passive_count_spin = null
	_passive_summary_lbl = null
	_passive_row = null
	_attack_percent_slider = null
	_attack_percent_lbl = null
	_attack_palette_chip = null
	_lightbreak_count_spin = null
	_lightbreak_palette_chip = null
	_action_row = null

	if _selected_enemy == null:
		var empty_lbl := Label.new()
		empty_lbl.text = "No enemy selected."
		empty_lbl.add_theme_font_size_override("font_size", 20)
		empty_lbl.add_theme_color_override("font_color", Color(0.86, 0.90, 1.0))
		_detail_body.add_child(empty_lbl)
		return

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	top_row.custom_minimum_size = Vector2(0, 246)
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_body.add_child(top_row)

	_build_portrait_column(top_row)
	_build_fields_column(top_row)

	var top_spacer := Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(top_spacer)

	_build_passive_column(_detail_body as VBoxContainer)
	_build_action_column(_detail_body as VBoxContainer)


func _build_portrait_column(parent: HBoxContainer) -> void:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(220, 0)
	col.add_theme_constant_override("separation", 8)
	parent.add_child(col)

	var preview_box := PanelContainer.new()
	preview_box.custom_minimum_size = Vector2(220, 220)
	preview_box.add_theme_stylebox_override("panel", _make_panel_style(Color(0.02, 0.025, 0.04, 1.0), Color(0.32, 0.35, 0.48, 1.0), 8))
	col.add_child(preview_box)

	_portrait_preview = TextureRect.new()
	_portrait_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_preview.texture = _selected_enemy.portrait_texture
	_portrait_preview.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_box.add_child(_portrait_preview)

	var path_lbl := Label.new()
	path_lbl.text = _selected_path
	path_lbl.add_theme_font_size_override("font_size", 11)
	path_lbl.add_theme_color_override("font_color", Color(0.74, 0.80, 0.92))
	path_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(path_lbl)


func _build_fields_column(parent: HBoxContainer) -> void:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(260, 0)
	col.add_theme_constant_override("separation", 8)
	parent.add_child(col)

	col.add_child(_make_section_title("Details"))

	_name_edit = LineEdit.new()
	_name_edit.text = _selected_enemy.enemy_name
	_name_edit.placeholder_text = "Fallback/internal enemy name"
	col.add_child(_make_labeled_control("Fallback", _name_edit))

	_name_zh_edit = LineEdit.new()
	_name_zh_edit.text = _selected_enemy.enemy_name_zh
	_name_zh_edit.placeholder_text = "中文敵人名稱"
	col.add_child(_make_labeled_control("Name ZH", _name_zh_edit))

	_name_en_edit = LineEdit.new()
	_name_en_edit.text = _selected_enemy.enemy_name_en
	_name_en_edit.placeholder_text = "English enemy name"
	col.add_child(_make_labeled_control("Name EN", _name_en_edit))

	var hp_box := HBoxContainer.new()
	hp_box.add_theme_constant_override("separation", 8)
	_hp_slider = HSlider.new()
	_hp_slider.min_value = EnemyData.HP_PERCENT_MIN
	_hp_slider.max_value = EnemyData.HP_PERCENT_MAX
	_hp_slider.step = 25
	_hp_slider.value = _selected_enemy.get_hp_percent()
	_hp_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hp_slider.tooltip_text = "Actual HP = same-level estimated player team ATK × this percent."
	_hp_slider.value_changed.connect(_on_hp_percent_changed)
	hp_box.add_child(_hp_slider)
	_hp_value_lbl = Label.new()
	_hp_value_lbl.custom_minimum_size = Vector2(68, 0)
	_hp_value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hp_value_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hp_value_lbl.add_theme_font_size_override("font_size", 12)
	_hp_value_lbl.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0))
	hp_box.add_child(_hp_value_lbl)
	_on_hp_percent_changed(_hp_slider.value)
	col.add_child(_make_labeled_control("HP %", hp_box))

	_element_option = OptionButton.new()
	_add_element_option(Block.Type.RED)
	_add_element_option(Block.Type.BLUE)
	_add_element_option(Block.Type.GREEN)
	_add_element_option(Block.Type.LIGHT)
	_add_element_option(Block.Type.DARK)
	_select_element_option(int(_selected_enemy.element))
	col.add_child(_make_labeled_control("Element", _element_option))


func _build_passive_column(parent: VBoxContainer) -> void:
	var passive_panel := PanelContainer.new()
	passive_panel.custom_minimum_size = Vector2(0, 172)
	passive_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	passive_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.04, 0.07, 0.98), Color(0.28, 0.32, 0.45, 1.0), 8))
	parent.add_child(passive_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	passive_panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 10)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(stack)

	var palette_box := VBoxContainer.new()
	palette_box.add_theme_constant_override("separation", 8)
	stack.add_child(palette_box)
	palette_box.add_child(_make_section_title("Passive List"))

	var palette := _PassivePaletteRow.new()
	palette.owner_screen = self
	palette.add_theme_constant_override("separation", 8)
	palette_box.add_child(palette)
	palette.add_child(_make_passive_chip(EnemyData.PassiveType.REQUIRE_GEM_COUNT_DAMAGE_GATE, -1))

	var gate_settings := HBoxContainer.new()
	gate_settings.add_theme_constant_override("separation", 8)
	palette.add_child(gate_settings)

	_passive_gem_option = OptionButton.new()
	_add_element_option_to(_passive_gem_option, Block.Type.RED)
	_add_element_option_to(_passive_gem_option, Block.Type.BLUE)
	_add_element_option_to(_passive_gem_option, Block.Type.GREEN)
	_add_element_option_to(_passive_gem_option, Block.Type.LIGHT)
	_add_element_option_to(_passive_gem_option, Block.Type.DARK)
	_select_element_option_in(_passive_gem_option, int(_selected_enemy.passive_required_gem_type))
	_passive_gem_option.item_selected.connect(func(_index: int) -> void:
		_refresh_passive_summary()
	)
	gate_settings.add_child(_make_labeled_control("Required Gem", _passive_gem_option))

	_passive_count_spin = SpinBox.new()
	_passive_count_spin.min_value = 1
	_passive_count_spin.max_value = 99
	_passive_count_spin.step = 1
	_passive_count_spin.value = EnemyData.clamp_passive_required_gem_count(_selected_enemy.passive_required_gem_count)
	_passive_count_spin.value_changed.connect(func(_value: float) -> void:
		_refresh_passive_summary()
	)
	gate_settings.add_child(_make_labeled_control("Count", _passive_count_spin))

	var sequence_box := VBoxContainer.new()
	sequence_box.add_theme_constant_override("separation", 8)
	stack.add_child(sequence_box)
	sequence_box.add_child(_make_section_title("Passives"))

	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size = Vector2(0, 62)
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.02, 0.025, 0.045, 1.0), Color(0.28, 0.32, 0.45, 1.0), 8))
	sequence_box.add_child(row_panel)

	var row_margin := MarginContainer.new()
	row_margin.add_theme_constant_override("margin_left", 8)
	row_margin.add_theme_constant_override("margin_right", 8)
	row_margin.add_theme_constant_override("margin_top", 8)
	row_margin.add_theme_constant_override("margin_bottom", 8)
	row_panel.add_child(row_margin)

	_passive_row = _PassiveDropRow.new()
	_passive_row.owner_screen = self
	_passive_row.add_theme_constant_override("separation", 6)
	_passive_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_margin.add_child(_passive_row)

	_passive_summary_lbl = Label.new()
	_passive_summary_lbl.add_theme_font_size_override("font_size", 11)
	_passive_summary_lbl.add_theme_color_override("font_color", Color(0.74, 0.80, 0.92))
	_passive_summary_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sequence_box.add_child(_passive_summary_lbl)

	_refresh_passive_sequence()


func _make_passive_chip(passive_type: int, source_index: int) -> _PassiveChip:
	var chip := _PassiveChip.new()
	chip.owner_screen = self
	chip.passive_type = passive_type
	chip.source_index = source_index
	chip.text = _passive_label(passive_type)
	chip.tooltip_text = "Drag into Passives" if source_index < 0 else "Drag to reorder, or drag back to Passive List to remove"
	chip.custom_minimum_size = Vector2(112, 38)
	chip.add_theme_font_size_override("font_size", 13)
	chip.add_theme_stylebox_override("normal", _passive_style(passive_type, false))
	chip.add_theme_stylebox_override("hover", _passive_style(passive_type, true))
	chip.add_theme_stylebox_override("pressed", _passive_style(passive_type, true))
	if source_index < 0:
		chip.pressed.connect(func() -> void:
			_set_single_passive(passive_type)
		)
	return chip


func _refresh_passive_sequence() -> void:
	if _passive_row == null:
		return
	for child in _passive_row.get_children():
		_passive_row.remove_child(child)
		child.queue_free()

	if _passive_sequence.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Drag passives here. Empty saves as no passive."
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.add_theme_color_override("font_color", Color(0.74, 0.78, 0.88))
		empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_passive_row.add_child(empty_lbl)
		_refresh_passive_summary()
		return

	for i in _passive_sequence.size():
		_passive_row.add_child(_make_passive_chip(_passive_sequence[i], i))
	_refresh_passive_summary()


func _refresh_passive_summary() -> void:
	if _passive_summary_lbl == null:
		return
	if _passive_sequence.is_empty():
		_passive_summary_lbl.text = "No passive effect."
		return
	var gem_label: String = "gem"
	if _passive_gem_option != null and _passive_gem_option.selected >= 0:
		gem_label = _passive_gem_option.get_item_text(_passive_gem_option.selected)
	var count: int = _current_passive_required_count()
	_passive_summary_lbl.text = "If this turn blasted fewer than %d %s gems, incoming damage becomes 1." % [count, gem_label]


func _is_passive_drag_data(data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("passive_type")


func _can_drop_passive_on_palette(data: Variant) -> bool:
	if not _is_passive_drag_data(data):
		return false
	var drag_data: Dictionary = data as Dictionary
	var source_index: int = int(drag_data.get("source_index", -1))
	return source_index >= 0 and source_index < _passive_sequence.size()


func _drop_passive_on_palette(data: Variant) -> void:
	if not _can_drop_passive_on_palette(data):
		return
	var drag_data: Dictionary = data as Dictionary
	var source_index: int = int(drag_data.get("source_index", -1))
	_remove_passive(source_index)


func _drop_passive_at_end(data: Variant) -> void:
	if not _is_passive_drag_data(data):
		return
	var drag_data: Dictionary = data as Dictionary
	var source_index: int = int(drag_data.get("source_index", -1))
	var passive_type: int = int(drag_data.get("passive_type", EnemyData.PassiveType.REQUIRE_GEM_COUNT_DAMAGE_GATE))
	if source_index >= 0 and source_index < _passive_sequence.size():
		return
	_set_single_passive(passive_type)


func _drop_passive_on_index(_target_index: int, data: Variant) -> void:
	if not _is_passive_drag_data(data):
		return
	var drag_data: Dictionary = data as Dictionary
	var source_index: int = int(drag_data.get("source_index", -1))
	if source_index >= 0 and source_index < _passive_sequence.size():
		return
	_drop_passive_at_end(data)


func _remove_passive(index: int) -> void:
	if index < 0 or index >= _passive_sequence.size():
		return
	_passive_sequence.remove_at(index)
	_refresh_passive_sequence()


func _set_single_passive(passive_type: int) -> void:
	_passive_sequence = [passive_type]
	_refresh_passive_sequence()


func _current_passive_required_count() -> int:
	if _passive_count_spin != null:
		return EnemyData.clamp_passive_required_gem_count(int(round(_passive_count_spin.value)))
	if _selected_enemy != null:
		return EnemyData.clamp_passive_required_gem_count(_selected_enemy.passive_required_gem_count)
	return EnemyData.PASSIVE_REQUIRED_GEM_COUNT_DEFAULT


func _build_action_column(parent: VBoxContainer) -> void:
	var action_panel := PanelContainer.new()
	action_panel.custom_minimum_size = Vector2(0, 252)
	action_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.035, 0.04, 0.07, 0.98), Color(0.28, 0.32, 0.45, 1.0), 8))
	parent.add_child(action_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	action_panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 12)
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(stack)

	var palette_box := VBoxContainer.new()
	palette_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_box.add_theme_constant_override("separation", 8)
	stack.add_child(palette_box)

	palette_box.add_child(_make_section_title("Action List"))

	var palette := _ActionPaletteRow.new()
	palette.owner_screen = self
	palette.add_theme_constant_override("separation", 8)
	palette_box.add_child(palette)
	palette.add_child(_make_action_chip(EnemyData.ActionType.REST, -1))

	var attack_box := VBoxContainer.new()
	attack_box.custom_minimum_size = Vector2(168, 0)
	attack_box.add_theme_constant_override("separation", 4)
	palette.add_child(attack_box)
	_attack_palette_chip = _make_action_chip(EnemyData.ActionType.ATTACK_15, -1, _current_attack_percent())
	attack_box.add_child(_attack_palette_chip)
	var attack_slider_row := HBoxContainer.new()
	attack_slider_row.add_theme_constant_override("separation", 6)
	attack_box.add_child(attack_slider_row)
	_attack_percent_slider = HSlider.new()
	_attack_percent_slider.min_value = EnemyData.ATTACK_PERCENT_MIN
	_attack_percent_slider.max_value = EnemyData.ATTACK_PERCENT_MAX
	_attack_percent_slider.step = 1
	_attack_percent_slider.value = EnemyData.ATTACK_PERCENT_DEFAULT
	_attack_percent_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attack_percent_slider.tooltip_text = "Attack percent for new dragged Attack and Lightbreak actions."
	_attack_percent_slider.value_changed.connect(_on_attack_percent_changed)
	attack_slider_row.add_child(_attack_percent_slider)
	_attack_percent_lbl = Label.new()
	_attack_percent_lbl.custom_minimum_size = Vector2(44, 0)
	_attack_percent_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_attack_percent_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_attack_percent_lbl.add_theme_font_size_override("font_size", 11)
	_attack_percent_lbl.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0))
	attack_slider_row.add_child(_attack_percent_lbl)
	_on_attack_percent_changed(_attack_percent_slider.value)

	palette.add_child(_make_action_chip(EnemyData.ActionType.STONE_MAGIC, -1))

	var lightbreak_box := VBoxContainer.new()
	lightbreak_box.custom_minimum_size = Vector2(188, 0)
	lightbreak_box.add_theme_constant_override("separation", 4)
	palette.add_child(lightbreak_box)
	_lightbreak_palette_chip = _make_action_chip(
		EnemyData.ActionType.BREAK_LIGHT_ATTACK,
		-1,
		_current_attack_percent(),
		_current_action_count()
	)
	lightbreak_box.add_child(_lightbreak_palette_chip)
	var lightbreak_count_row := HBoxContainer.new()
	lightbreak_count_row.add_theme_constant_override("separation", 6)
	lightbreak_box.add_child(lightbreak_count_row)
	var lightbreak_count_label := Label.new()
	lightbreak_count_label.text = "Light"
	lightbreak_count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lightbreak_count_label.add_theme_font_size_override("font_size", 11)
	lightbreak_count_label.add_theme_color_override("font_color", Color(0.90, 0.94, 1.0))
	lightbreak_count_row.add_child(lightbreak_count_label)
	_lightbreak_count_spin = SpinBox.new()
	_lightbreak_count_spin.min_value = EnemyData.ACTION_COUNT_MIN
	_lightbreak_count_spin.max_value = EnemyData.ACTION_COUNT_MAX
	_lightbreak_count_spin.step = 1
	_lightbreak_count_spin.value = EnemyData.ACTION_COUNT_DEFAULT
	_lightbreak_count_spin.custom_minimum_size = Vector2(72, 0)
	_lightbreak_count_spin.tooltip_text = "Light gem count removed by new Lightbreak actions."
	_lightbreak_count_spin.value_changed.connect(_on_lightbreak_count_changed)
	lightbreak_count_row.add_child(_lightbreak_count_spin)

	var sequence_box := VBoxContainer.new()
	sequence_box.add_theme_constant_override("separation", 8)
	sequence_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sequence_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(sequence_box)

	var sequence_title := _make_section_title("行動序列表")
	sequence_box.add_child(sequence_title)

	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size = Vector2(0, 86)
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_panel.add_theme_stylebox_override("panel", _make_panel_style(Color(0.02, 0.025, 0.045, 1.0), Color(0.28, 0.32, 0.45, 1.0), 8))
	sequence_box.add_child(row_panel)

	var row_margin := MarginContainer.new()
	row_margin.add_theme_constant_override("margin_left", 8)
	row_margin.add_theme_constant_override("margin_right", 8)
	row_margin.add_theme_constant_override("margin_top", 8)
	row_margin.add_theme_constant_override("margin_bottom", 8)
	row_panel.add_child(row_margin)

	var action_scroll := ScrollContainer.new()
	action_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	action_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	action_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	action_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row_margin.add_child(action_scroll)

	_action_row = _ActionDropRow.new()
	_action_row.owner_screen = self
	_action_row.add_theme_constant_override("separation", 6)
	_action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	action_scroll.add_child(_action_row)

	var row_buttons := HBoxContainer.new()
	row_buttons.add_theme_constant_override("separation", 8)
	sequence_box.add_child(row_buttons)

	var clear_btn := Button.new()
	clear_btn.text = "Clear Sequence"
	clear_btn.custom_minimum_size = Vector2(128, 32)
	clear_btn.pressed.connect(func() -> void:
		_action_sequence.clear()
		_action_percents.clear()
		_action_counts.clear()
		_refresh_action_sequence()
	)
	row_buttons.add_child(clear_btn)

	var fallback_btn := Button.new()
	fallback_btn.text = "Default Attack"
	fallback_btn.custom_minimum_size = Vector2(128, 32)
	fallback_btn.pressed.connect(func() -> void:
		_action_sequence = [EnemyData.ActionType.ATTACK_15]
		_action_percents = [EnemyData.ATTACK_PERCENT_DEFAULT]
		_action_counts = [EnemyData.ACTION_COUNT_DEFAULT]
		_refresh_action_sequence()
	)
	row_buttons.add_child(fallback_btn)

	_refresh_action_sequence()


func _make_action_chip(
		action_type: int,
		source_index: int,
		attack_percent: int = EnemyData.ATTACK_PERCENT_DEFAULT,
		action_count: int = EnemyData.ACTION_COUNT_DEFAULT) -> _ActionChip:
	var chip := _ActionChip.new()
	chip.owner_screen = self
	chip.action_type = action_type
	chip.attack_percent = _action_percent_for_type(action_type, attack_percent)
	chip.action_count = _action_count_for_type(action_type, action_count)
	chip.source_index = source_index
	chip.text = _action_label(action_type, chip.attack_percent, chip.action_count)
	chip.tooltip_text = "Drag into 行動序列表" if source_index < 0 else "Drag to reorder, or drag back to Action List to remove"
	chip.custom_minimum_size = Vector2(112, 38)
	chip.add_theme_font_size_override("font_size", 13)
	chip.add_theme_stylebox_override("normal", _action_style(action_type, false))
	chip.add_theme_stylebox_override("hover", _action_style(action_type, true))
	chip.add_theme_stylebox_override("pressed", _action_style(action_type, true))
	if source_index < 0:
		chip.pressed.connect(func() -> void:
			if action_type == EnemyData.ActionType.BREAK_LIGHT_ATTACK:
				_append_action(action_type, _current_attack_percent(), _current_action_count())
			else:
				_append_action(action_type, _current_attack_percent() if action_type == EnemyData.ActionType.ATTACK_15 else attack_percent, action_count)
			_refresh_action_sequence()
		)
	return chip


func _refresh_action_sequence() -> void:
	if _action_row == null:
		return
	for child in _action_row.get_children():
		_action_row.remove_child(child)
		child.queue_free()

	if _action_sequence.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Drag actions here. Empty saves as default Attack 15%."
		empty_lbl.add_theme_font_size_override("font_size", 13)
		empty_lbl.add_theme_color_override("font_color", Color(0.74, 0.78, 0.88))
		empty_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_action_row.add_child(empty_lbl)
		return

	for i in _action_sequence.size():
		_action_row.add_child(_make_action_chip(_action_sequence[i], i, _action_percent_at(i), _action_count_at(i)))


func _is_action_drag_data(data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("action_type")


func _can_drop_action_on_palette(data: Variant) -> bool:
	if not _is_action_drag_data(data):
		return false
	var drag_data: Dictionary = data as Dictionary
	var source_index: int = int(drag_data.get("source_index", -1))
	return source_index >= 0 and source_index < _action_sequence.size()


func _drop_action_on_palette(data: Variant) -> void:
	if not _can_drop_action_on_palette(data):
		return
	var drag_data: Dictionary = data as Dictionary
	var source_index: int = int(drag_data.get("source_index", -1))
	_remove_action(source_index)


func _drop_action_at_end(data: Variant) -> void:
	if not _is_action_drag_data(data):
		return
	var drag_data: Dictionary = data as Dictionary
	var source_index: int = int(drag_data.get("source_index", -1))
	var action_type: int = int(drag_data.get("action_type", EnemyData.ActionType.ATTACK_15))
	var attack_percent: int = int(drag_data.get("attack_percent", EnemyData.ATTACK_PERCENT_DEFAULT))
	var action_count: int = int(drag_data.get("action_count", EnemyData.ACTION_COUNT_DEFAULT))
	if source_index >= 0 and source_index < _action_sequence.size():
		var moved_action: int = _action_sequence[source_index]
		var moved_percent: int = _action_percent_at(source_index)
		var moved_count: int = _action_count_at(source_index)
		_action_sequence.remove_at(source_index)
		if source_index < _action_percents.size():
			_action_percents.remove_at(source_index)
		if source_index < _action_counts.size():
			_action_counts.remove_at(source_index)
		_action_sequence.append(moved_action)
		_action_percents.append(moved_percent)
		_action_counts.append(moved_count)
	else:
		_append_action(action_type, attack_percent, action_count)
	_refresh_action_sequence()


func _drop_action_on_index(target_index: int, data: Variant) -> void:
	if not _is_action_drag_data(data):
		return
	var drag_data: Dictionary = data as Dictionary
	var source_index: int = int(drag_data.get("source_index", -1))
	var action_type: int = int(drag_data.get("action_type", EnemyData.ActionType.ATTACK_15))
	var attack_percent: int = int(drag_data.get("attack_percent", EnemyData.ATTACK_PERCENT_DEFAULT))
	var action_count: int = int(drag_data.get("action_count", EnemyData.ACTION_COUNT_DEFAULT))
	var insert_index: int = clampi(target_index, 0, _action_sequence.size())
	if source_index >= 0 and source_index < _action_sequence.size():
		var moved_action: int = _action_sequence[source_index]
		var moved_percent: int = _action_percent_at(source_index)
		var moved_count: int = _action_count_at(source_index)
		_action_sequence.remove_at(source_index)
		if source_index < _action_percents.size():
			_action_percents.remove_at(source_index)
		if source_index < _action_counts.size():
			_action_counts.remove_at(source_index)
		if source_index < insert_index:
			insert_index -= 1
		_action_sequence.insert(clampi(insert_index, 0, _action_sequence.size()), moved_action)
		_action_percents.insert(clampi(insert_index, 0, _action_percents.size()), moved_percent)
		_action_counts.insert(clampi(insert_index, 0, _action_counts.size()), moved_count)
	else:
		_action_sequence.insert(insert_index, action_type)
		_action_percents.insert(insert_index, _action_percent_for_type(action_type, attack_percent))
		_action_counts.insert(insert_index, _action_count_for_type(action_type, action_count))
	_refresh_action_sequence()


func _remove_action(index: int) -> void:
	if index < 0 or index >= _action_sequence.size():
		return
	_action_sequence.remove_at(index)
	if index < _action_percents.size():
		_action_percents.remove_at(index)
	if index < _action_counts.size():
		_action_counts.remove_at(index)
	_refresh_action_sequence()


func _append_action(action_type: int, attack_percent: int, action_count: int = EnemyData.ACTION_COUNT_DEFAULT) -> void:
	_action_sequence.append(action_type)
	_action_percents.append(_action_percent_for_type(action_type, attack_percent))
	_action_counts.append(_action_count_for_type(action_type, action_count))


func _action_percent_at(index: int) -> int:
	if index >= 0 and index < _action_percents.size():
		return EnemyData.clamp_attack_percent(int(_action_percents[index]))
	return EnemyData.ATTACK_PERCENT_DEFAULT


func _action_percent_for_type(action_type: int, attack_percent: int) -> int:
	if action_type == EnemyData.ActionType.ATTACK_15 or action_type == EnemyData.ActionType.BREAK_LIGHT_ATTACK:
		return EnemyData.clamp_attack_percent(attack_percent)
	return EnemyData.ATTACK_PERCENT_DEFAULT


func _action_count_at(index: int) -> int:
	if index >= 0 and index < _action_counts.size():
		return EnemyData.clamp_action_count(int(_action_counts[index]))
	return EnemyData.ACTION_COUNT_DEFAULT


func _action_count_for_type(action_type: int, action_count: int) -> int:
	if action_type == EnemyData.ActionType.BREAK_LIGHT_ATTACK:
		return EnemyData.clamp_action_count(action_count)
	return EnemyData.ACTION_COUNT_DEFAULT


func _current_attack_percent() -> int:
	if _attack_percent_slider != null:
		return EnemyData.clamp_attack_percent(int(round(_attack_percent_slider.value)))
	return EnemyData.ATTACK_PERCENT_DEFAULT


func _current_action_count() -> int:
	if _lightbreak_count_spin != null:
		return EnemyData.clamp_action_count(int(round(_lightbreak_count_spin.value)))
	return EnemyData.ACTION_COUNT_DEFAULT


func _on_attack_percent_changed(value: float) -> void:
	var percent: int = EnemyData.clamp_attack_percent(int(round(value)))
	if _attack_percent_lbl != null:
		_attack_percent_lbl.text = "%d%%" % percent
	if _attack_palette_chip != null:
		_attack_palette_chip.attack_percent = percent
		_attack_palette_chip.text = _action_label(EnemyData.ActionType.ATTACK_15, percent)
	if _lightbreak_palette_chip != null:
		_lightbreak_palette_chip.attack_percent = percent
		_lightbreak_palette_chip.text = _action_label(EnemyData.ActionType.BREAK_LIGHT_ATTACK, percent, _current_action_count())
	_refresh_estimate_info()


func _on_lightbreak_count_changed(_value: float) -> void:
	var count: int = _current_action_count()
	if _lightbreak_palette_chip != null:
		_lightbreak_palette_chip.action_count = count
		_lightbreak_palette_chip.text = _action_label(EnemyData.ActionType.BREAK_LIGHT_ATTACK, _current_attack_percent(), count)


func _on_hp_percent_changed(value: float) -> void:
	var percent: int = EnemyData.clamp_hp_percent(int(round(value)))
	if _hp_value_lbl != null:
		_hp_value_lbl.text = "%d%%" % percent
	_refresh_estimate_info()


func _save_selected_enemy() -> void:
	if _selected_enemy == null or _selected_path.is_empty():
		_set_status("No enemy selected", false)
		return
	_selected_enemy.enemy_name = _name_edit.text.strip_edges() if _name_edit != null else _selected_enemy.enemy_name
	_selected_enemy.enemy_name_zh = _name_zh_edit.text.strip_edges() if _name_zh_edit != null else _selected_enemy.enemy_name_zh
	_selected_enemy.enemy_name_en = _name_en_edit.text.strip_edges() if _name_en_edit != null else _selected_enemy.enemy_name_en
	if _selected_enemy.enemy_name.is_empty():
		if not _selected_enemy.enemy_name_en.is_empty():
			_selected_enemy.enemy_name = _selected_enemy.enemy_name_en
		elif not _selected_enemy.enemy_name_zh.is_empty():
			_selected_enemy.enemy_name = _selected_enemy.enemy_name_zh
		else:
			_selected_enemy.enemy_name = _selected_path.get_file().get_basename()
	_selected_enemy.max_hp = _current_hp_percent()
	_selected_enemy.enemy_level = 1
	_selected_enemy.attack_damage = 0
	_selected_enemy.attack_coeff = 1.0
	_selected_enemy.attack_interval = 0
	_selected_enemy.is_main_boss = false
	if _element_option != null and _element_option.selected >= 0:
		_selected_enemy.element = int(_element_option.get_item_metadata(_element_option.selected)) as Block.Type
	if not _passive_sequence.is_empty():
		_selected_enemy.passive_type = int(_passive_sequence[0]) as EnemyData.PassiveType
		if _passive_gem_option != null and _passive_gem_option.selected >= 0:
			_selected_enemy.passive_required_gem_type = int(_passive_gem_option.get_item_metadata(_passive_gem_option.selected)) as Block.Type
		_selected_enemy.passive_required_gem_count = _current_passive_required_count()
		if _selected_enemy.passive_name.strip_edges().is_empty():
			_selected_enemy.passive_name = "Gem Gate"
		if _selected_enemy.passive_desc.strip_edges().is_empty():
			_selected_enemy.passive_desc = "Incoming damage becomes 1 unless enough matching gems were blasted this turn."
	else:
		_selected_enemy.passive_type = EnemyData.PassiveType.NONE
	var validated_pattern: Array[EnemyData.ActionType] = _validated_action_pattern()
	_selected_enemy.action_pattern = validated_pattern
	_selected_enemy.action_percents = _validated_action_percents(validated_pattern)
	_selected_enemy.action_counts = _validated_action_counts(validated_pattern)
	var err: int = ResourceSaver.save(_selected_enemy, _selected_path)
	if err == OK:
		_set_status("Saved %s" % _selected_path.get_file())
		_reload_enemies()
		_refresh_enemy_row()
	else:
		_set_status("Save failed (%d)" % err, false)


func _validated_action_pattern() -> Array[EnemyData.ActionType]:
	var pattern: Array[EnemyData.ActionType] = []
	var has_active: bool = false
	for action_value: int in _action_sequence:
		var action_type: EnemyData.ActionType = int(action_value) as EnemyData.ActionType
		pattern.append(action_type)
		if action_type != EnemyData.ActionType.REST:
			has_active = true
	if pattern.is_empty() or not has_active:
		pattern.clear()
		pattern.append(EnemyData.ActionType.ATTACK_15)
	return pattern


func _validated_action_percents(pattern: Array[EnemyData.ActionType]) -> Array[int]:
	var percents: Array[int] = []
	if pattern.size() != _action_sequence.size():
		for action_type: EnemyData.ActionType in pattern:
			percents.append(_action_percent_for_type(int(action_type), EnemyData.ATTACK_PERCENT_DEFAULT))
		return percents
	for i in pattern.size():
		percents.append(_action_percent_for_type(int(pattern[i]), _action_percent_at(i)))
	return percents


func _validated_action_counts(pattern: Array[EnemyData.ActionType]) -> Array[int]:
	var counts: Array[int] = []
	if pattern.size() != _action_sequence.size():
		for action_type: EnemyData.ActionType in pattern:
			counts.append(_action_count_for_type(int(action_type), EnemyData.ACTION_COUNT_DEFAULT))
		return counts
	for i in pattern.size():
		counts.append(_action_count_for_type(int(pattern[i]), _action_count_at(i)))
	return counts


func _toggle_image_picker() -> void:
	if _image_picker_panel == null:
		return
	_image_picker_panel.visible = not _image_picker_panel.visible


func _create_enemy_from_image(index: int) -> void:
	if index < 0 or index >= _image_entries.size():
		return
	var entry: Dictionary = _image_entries[index]
	var image_path: String = String(entry.get("path", ""))
	var texture: Texture2D = load(image_path) as Texture2D
	if texture == null:
		_set_status("Image load failed", false)
		return
	var enemy := EnemyData.new()
	enemy.enemy_name = _title_from_slug(image_path.get_file().get_basename())
	enemy.enemy_name_en = enemy.enemy_name
	enemy.enemy_level = 1
	enemy.max_hp = EnemyData.HP_PERCENT_MIN
	enemy.attack_damage = 0
	enemy.attack_coeff = 1.0
	enemy.attack_interval = 0
	enemy.is_main_boss = false
	enemy.element = _guess_element_from_path(image_path)
	enemy.portrait_texture = texture
	enemy.passive_type = EnemyData.PassiveType.NONE
	enemy.action_pattern = [EnemyData.ActionType.ATTACK_15]
	enemy.action_percents = [EnemyData.ATTACK_PERCENT_DEFAULT]
	enemy.action_counts = [EnemyData.ACTION_COUNT_DEFAULT]
	var save_path: String = _unique_enemy_path(enemy.enemy_name)
	var err: int = ResourceSaver.save(enemy, save_path)
	if err != OK:
		_set_status("Create failed (%d)" % err, false)
		return
	_image_picker_panel.visible = false
	_reload_enemies()
	_refresh_enemy_row()
	var created_index: int = _find_enemy_entry_by_path(save_path)
	if created_index >= 0:
		_select_enemy(created_index)
	_set_status("Created %s" % save_path.get_file())


func _find_enemy_entry_by_path(path: String) -> int:
	for i in _enemy_entries.size():
		if String(_enemy_entries[i].get("path", "")) == path:
			return i
	return -1


func _unique_enemy_path(display_name: String) -> String:
	var slug: String = _slugify(display_name)
	if slug.is_empty():
		slug = "enemy"
	var candidate: String = "%s/%s.tres" % [ENEMY_ROOT, slug]
	var index: int = 2
	while ResourceLoader.exists(candidate) or FileAccess.file_exists(candidate):
		candidate = "%s/%s_%d.tres" % [ENEMY_ROOT, slug, index]
		index += 1
	return candidate


func _slugify(value: String) -> String:
	var result: String = ""
	var allowed: String = "abcdefghijklmnopqrstuvwxyz0123456789"
	for i in value.length():
		var ch: String = value.substr(i, 1).to_lower()
		if allowed.contains(ch):
			result += ch
		else:
			if not result.ends_with("_"):
				result += "_"
	return result.strip_edges().trim_suffix("_")


func _title_from_slug(value: String) -> String:
	var parts: PackedStringArray = value.replace("-", "_").split("_", false)
	var words: Array[String] = []
	for part: String in parts:
		if part.is_empty():
			continue
		words.append(part.substr(0, 1).to_upper() + part.substr(1).to_lower())
	return " ".join(words) if not words.is_empty() else "New Enemy"


func _guess_element_from_path(path: String) -> Block.Type:
	var lower_path: String = path.to_lower()
	if lower_path.find("light") >= 0:
		return Block.Type.LIGHT
	if lower_path.find("dark") >= 0 or lower_path.find("dungeon") >= 0:
		return Block.Type.DARK
	if lower_path.find("lava") >= 0 or lower_path.find("fire") >= 0:
		return Block.Type.RED
	if lower_path.find("ice") >= 0 or lower_path.find("water") >= 0:
		return Block.Type.BLUE
	return Block.Type.GREEN


func _estimate_text(level_value: int) -> String:
	var total_hp: int = _estimate_team_hp(level_value)
	var total_attack: int = _estimate_team_attack(level_value)
	var attack_percent: int = _current_attack_percent()
	var attack_damage: int = maxi(1, int(round(float(total_hp) * float(attack_percent) / 100.0)))
	var hp_percent: int = _current_hp_percent()
	var enemy_hp: int = maxi(1, int(round(float(maxi(1, total_attack)) * float(hp_percent) / 100.0)))
	return "Lv %d Team HP %d | Team ATK %d | Enemy HP %d%% -> %d | Attack %d%% %d" % [level_value, total_hp, total_attack, hp_percent, enemy_hp, attack_percent, attack_damage]


func _current_hp_percent() -> int:
	if _hp_slider != null:
		return EnemyData.clamp_hp_percent(int(round(_hp_slider.value)))
	if _selected_enemy != null:
		return _selected_enemy.get_hp_percent()
	return EnemyData.HP_PERCENT_MIN


func _refresh_estimate_info() -> void:
	if _estimate_info_lbl != null:
		_estimate_info_lbl.text = _estimate_text(_estimate_level_value)


func _estimate_team_hp(level_value: int) -> int:
	var preview_party: Array[CharacterData] = _preview_party()
	var total_hp: int = 0
	for character: CharacterData in preview_party:
		if character == null:
			continue
		total_hp += character.get_max_hp_at_level(level_value)
	return total_hp


func _estimate_team_attack(level_value: int) -> int:
	var preview_party: Array[CharacterData] = _preview_party()
	var total_attack: int = 0
	for character: CharacterData in preview_party:
		if character == null:
			continue
		total_attack += character.get_atk_at_level(level_value)
	return total_attack


func _preview_party() -> Array[CharacterData]:
	var party: Array[CharacterData] = []
	var last_party: Array[CharacterData] = GameState.get_last_used_party()
	for character: CharacterData in last_party:
		if character != null and party.size() < GameState.MAX_PARTY_SIZE:
			party.append(character)
	if party.is_empty():
		for character: CharacterData in GameState.owned_characters:
			if character != null and party.size() < GameState.MAX_PARTY_SIZE:
				party.append(character)
	return party


func _on_estimate_level_hovered(level_value: int) -> void:
	_estimate_level_value = level_value
	_refresh_estimate_info()


func _add_element_option(element_type: int) -> void:
	_add_element_option_to(_element_option, element_type)


func _add_element_option_to(option: OptionButton, element_type: int) -> void:
	if option == null:
		return
	var label: String = str(Block.ICONS.get(element_type, "?"))
	match element_type:
		Block.Type.RED:
			label = "Fire"
		Block.Type.BLUE:
			label = "Water"
		Block.Type.GREEN:
			label = "Leaf"
		Block.Type.LIGHT:
			label = "Light"
		Block.Type.DARK:
			label = "Dark"
	option.add_item(label)
	option.set_item_metadata(option.item_count - 1, element_type)


func _select_element_option(element_type: int) -> void:
	_select_element_option_in(_element_option, element_type)


func _select_element_option_in(option: OptionButton, element_type: int) -> void:
	if option == null:
		return
	for i in option.item_count:
		if int(option.get_item_metadata(i)) == element_type:
			option.select(i)
			return
	option.select(0)


func _make_labeled_control(label_text: String, control: Control) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.92))
	box.add_child(label)
	box.add_child(control)
	return box


func _make_section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 17)
	label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	return label


func _action_label(action_type: int, attack_percent: int = EnemyData.ATTACK_PERCENT_DEFAULT, action_count: int = EnemyData.ACTION_COUNT_DEFAULT) -> String:
	match action_type:
		EnemyData.ActionType.REST:
			return "Rest"
		EnemyData.ActionType.STONE_MAGIC:
			return "Stone Magic"
		EnemyData.ActionType.BREAK_LIGHT_ATTACK:
			return "破光 %d%% L%d" % [EnemyData.clamp_attack_percent(attack_percent), EnemyData.clamp_action_count(action_count)]
		_:
			return "Attack %d%%" % EnemyData.clamp_attack_percent(attack_percent)


func _passive_label(passive_type: int) -> String:
	match passive_type:
		EnemyData.PassiveType.REQUIRE_GEM_COUNT_DAMAGE_GATE:
			return "Gem Gate"
		_:
			return "Passive"


func _action_style(action_type: int, hover: bool) -> StyleBoxFlat:
	var color: Color = Color(0.18, 0.20, 0.28, 1.0)
	match action_type:
		EnemyData.ActionType.REST:
			color = Color(0.20, 0.22, 0.28, 1.0)
		EnemyData.ActionType.STONE_MAGIC:
			color = Color(0.32, 0.30, 0.36, 1.0)
		EnemyData.ActionType.BREAK_LIGHT_ATTACK:
			color = Color(0.48, 0.38, 0.12, 1.0)
		_:
			color = Color(0.42, 0.18, 0.14, 1.0)
	if hover:
		color = color.lightened(0.12)
	return _make_button_style(color, Color(0.55, 0.58, 0.72, 1.0))


func _passive_style(passive_type: int, hover: bool) -> StyleBoxFlat:
	var color: Color = Color(0.18, 0.22, 0.31, 1.0)
	match passive_type:
		EnemyData.PassiveType.REQUIRE_GEM_COUNT_DAMAGE_GATE:
			color = Color(0.18, 0.30, 0.42, 1.0)
	if hover:
		color = color.lightened(0.12)
	return _make_button_style(color, Color(0.55, 0.68, 0.82, 1.0))


func _make_button_style(bg_color: Color, border_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(6)
	return style


func _make_panel_style(bg_color: Color, border_color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	style.set_content_margin_all(6)
	return style


func _set_status(message: String, ok: bool = true) -> void:
	if _status_lbl == null:
		return
	_status_lbl.text = message
	_status_lbl.add_theme_color_override("font_color", Color(0.78, 0.92, 0.78) if ok else Color(1.0, 0.52, 0.46))
