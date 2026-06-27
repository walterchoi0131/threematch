extends Control

const CHARACTER_DIR := "res://characters"
const ICON_SIZE := Vector2(52, 52)
const CARD_SIZE := Vector2(84, 100)
const UPPER_ICON_BUTTON_SIZE := Vector2(64, 64)
const DROP_ROW_HEIGHT := 136.0
const BLAST_GRID_CELL_SIZE := 12.0


class UpperGemDragButton:
	extends Button

	var skill_template: Dictionary = {}

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if skill_template.is_empty():
			return null
		var preview := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.05, 0.10, 0.15, 0.94)
		style.border_color = Color(0.24, 0.90, 0.86, 1.0)
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(8)
		preview.add_theme_stylebox_override("panel", style)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		preview.add_child(row)
		var icon := TextureRect.new()
		icon.texture = skill_template.get("icon", null)
		icon.custom_minimum_size = Vector2(42, 42)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
		var label := Label.new()
		label.text = str(skill_template.get("display_name", skill_template.get("name", "")))
		label.add_theme_font_size_override("font_size", 16)
		label.add_theme_color_override("font_color", Color(0.86, 1.0, 0.96))
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		set_drag_preview(preview)
		return {"kind": "upper_gem_skill", "template": skill_template.duplicate(true)}


class SkillDropRow:
	extends PanelContainer

	var screen: Control = null
	var skill_index: int = -1

	func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
		return data is Dictionary and str(data.get("kind", "")) == "upper_gem_skill"

	func _drop_data(_at_position: Vector2, data: Variant) -> void:
		if screen != null and screen.has_method("_apply_template_to_selected"):
			screen.call("_apply_template_to_selected", skill_index, data.get("template", {}))


var _characters: Array[CharacterData] = []
var _selected_character: CharacterData = null
var _selected_button: Button = null
var _character_flow: HFlowContainer = null
var _info_box: VBoxContainer = null
var _status_lbl: Label = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_characters()
	_build()
	if not _characters.is_empty():
		_select_character(_characters[0], null)


func _load_characters() -> void:
	_characters.clear()
	var dir := DirAccess.open(CHARACTER_DIR)
	if dir == null:
		return
	var files := dir.get_files()
	files.sort()
	for file_name: String in files:
		if not file_name.ends_with(".tres"):
			continue
		var path := "%s/%s" % [CHARACTER_DIR, file_name]
		var res := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res is CharacterData:
			_characters.append(res as CharacterData)
	_characters.sort_custom(func(a: CharacterData, b: CharacterData) -> bool:
		return Locale.tr_ui(a.character_name) < Locale.tr_ui(b.character_name)
	)


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.035, 0.045, 0.065, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 10)
	root.offset_left = 14
	root.offset_top = 10
	root.offset_right = -14
	root.offset_bottom = -12
	add_child(root)

	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 10)
	root.add_child(top_bar)

	var title := Label.new()
	title.text = "融合寶石技能 DEV"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.38))
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_bar.add_child(title)

	_status_lbl = Label.new()
	_status_lbl.text = "拖曳下方 Upper Gem 到中間技能列，會直接寫入角色 .tres。"
	_status_lbl.add_theme_font_size_override("font_size", 13)
	_status_lbl.add_theme_color_override("font_color", Color(0.74, 0.88, 0.94))
	_status_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(_status_lbl)

	var reload_btn := Button.new()
	reload_btn.text = "重新載入"
	reload_btn.custom_minimum_size = Vector2(92, 38)
	reload_btn.pressed.connect(_on_reload_pressed)
	top_bar.add_child(reload_btn)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(44, 38)
	close_btn.pressed.connect(queue_free)
	top_bar.add_child(close_btn)

	var character_section := _make_section("角色")
	root.add_child(character_section)
	_build_character_list(character_section)

	var fusing_section := _make_section("Fusing Gem")
	root.add_child(fusing_section)
	var info_scroll := ScrollContainer.new()
	info_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	fusing_section.add_child(info_scroll)

	_info_box = VBoxContainer.new()
	_info_box.add_theme_constant_override("separation", 8)
	_info_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_scroll.add_child(_info_box)

	var upper_section := _make_section("Upper Gem")
	root.add_child(upper_section)
	_build_upper_gem_list(upper_section)


func _build_character_list(parent: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(scroll)

	_character_flow = HFlowContainer.new()
	_character_flow.add_theme_constant_override("h_separation", 8)
	_character_flow.add_theme_constant_override("v_separation", 8)
	_character_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_character_flow)

	for character: CharacterData in _characters:
		var btn := Button.new()
		btn.custom_minimum_size = CARD_SIZE
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		btn.tooltip_text = "%s\n%s" % [Locale.tr_ui(character.character_name), character.resource_path]
		btn.pressed.connect(_select_character.bind(character, btn))
		_character_flow.add_child(btn)

		var cell := VBoxContainer.new()
		cell.set_anchors_preset(Control.PRESET_FULL_RECT)
		cell.offset_left = 4
		cell.offset_right = -4
		cell.offset_top = 4
		cell.offset_bottom = -4
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(cell)

		var wrap := Control.new()
		wrap.custom_minimum_size = Vector2(70, 70)
		wrap.clip_contents = true
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(wrap)

		var card_result: Dictionary = CharacterCard.make_square(character)
		var card: PanelContainer = card_result.get("panel", null) as PanelContainer
		if card != null:
			card.set_anchors_preset(Control.PRESET_FULL_RECT)
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wrap.add_child(card)

		var name_lbl := Label.new()
		name_lbl.text = Locale.tr_ui(character.character_name)
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(name_lbl)


func _build_upper_gem_list(parent: VBoxContainer) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(scroll)

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 8)
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(flow)

	for template: Dictionary in _upper_gem_templates():
		var btn := UpperGemDragButton.new()
		btn.skill_template = template
		btn.custom_minimum_size = UPPER_ICON_BUTTON_SIZE
		btn.tooltip_text = "%s\n%s" % [template.get("display_name", ""), template.get("desc", "")]
		flow.add_child(btn)

		var icon := TextureRect.new()
		icon.texture = template.get("icon", null)
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 6
		icon.offset_right = -6
		icon.offset_top = 6
		icon.offset_bottom = -6
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(icon)


func _select_character(character: CharacterData, source_btn: Button) -> void:
	_selected_character = character
	if _selected_button != null and is_instance_valid(_selected_button):
		_selected_button.modulate = Color.WHITE
	_selected_button = source_btn
	if _selected_button != null:
		_selected_button.modulate = Color(0.78, 1.0, 0.96, 1.0)
	_rebuild_info()


func _rebuild_info() -> void:
	if _info_box == null:
		return
	for child in _info_box.get_children():
		child.queue_free()
	if _selected_character == null:
		return

	var selected_lbl := Label.new()
	selected_lbl.text = "%s  |  %s  |  %s" % [
		Locale.tr_ui(_selected_character.character_name),
		_gem_type_name(_selected_character.gem_type),
		_selected_character.resource_path,
	]
	selected_lbl.add_theme_font_size_override("font_size", 13)
	selected_lbl.add_theme_color_override("font_color", Color(0.78, 0.90, 1.0))
	selected_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_box.add_child(selected_lbl)

	for i in range(_selected_character.responding_skills.size()):
		var skill: Dictionary = _selected_character.responding_skills[i]
		_info_box.add_child(_make_drop_row(i, skill, false))
	_info_box.add_child(_make_drop_row(_selected_character.responding_skills.size(), {}, true))


func _make_drop_row(skill_index: int, skill: Dictionary, is_add_row: bool) -> SkillDropRow:
	var row := SkillDropRow.new()
	row.screen = self
	row.skill_index = skill_index
	row.custom_minimum_size = Vector2(0, DROP_ROW_HEIGHT)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_stylebox_override("panel", _make_panel_style(
		Color(0.05, 0.10, 0.13, 0.92) if is_add_row else Color(0.08, 0.10, 0.15, 0.96),
		Color(0.24, 0.90, 0.86, 0.80) if is_add_row else Color(0.82, 0.68, 0.32, 1.0),
		6
	))

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(hbox)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(box)

	if is_add_row:
		var add_spacer := Control.new()
		add_spacer.custom_minimum_size = Vector2(190, 1)
		hbox.add_child(add_spacer)
		hbox.move_child(add_spacer, 0)
		_add_plain_label(box, "拖到這裡新增融合技能", 15, Color(0.62, 1.0, 0.95))
		_add_plain_label(box, "新增會 append 到 responding_skills。", 12, Color(0.72, 0.82, 0.88))
	else:
		var preview := _make_fusing_preview(skill_index, skill)
		hbox.add_child(preview)
		hbox.move_child(preview, 0)
		var skill_name := str(skill.get("name", ""))
		var threshold := SkillUpgradeUtils.responding_threshold(_selected_character, skill_index, skill)
		var trigger := str(skill.get("trigger_type", "count"))
		_add_plain_label(box, "#%d  %s  %d+  %s" % [skill_index + 1, skill_name, threshold, trigger], 15, Color(1.0, 0.92, 0.52))
		_add_plain_label(box, SkillUpgradeUtils.get_responding_description(_selected_character, skill_index, skill), 12, Color(0.75, 0.82, 0.90))
		var delete_btn := Button.new()
		delete_btn.text = "X"
		delete_btn.tooltip_text = "Delete fusing skill"
		delete_btn.custom_minimum_size = Vector2(38, 38)
		delete_btn.add_theme_font_size_override("font_size", 17)
		delete_btn.add_theme_color_override("font_color", Color(1.0, 0.46, 0.42))
		delete_btn.pressed.connect(_delete_skill_from_selected.bind(skill_index))
		hbox.add_child(delete_btn)
	return row


func _make_fusing_preview(skill_index: int, skill: Dictionary) -> Control:
	var wrap := HBoxContainer.new()
	wrap.custom_minimum_size = Vector2(238, 96)
	wrap.add_theme_constant_override("separation", 10)
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_child(_make_fuse_chain(skill_index, skill))
	var upper_type: int = int(SkillUpgradeUtils.responding_upper_type(skill))
	wrap.add_child(_make_blast_grid(_blast_pattern_for(upper_type), upper_type))
	return wrap


func _make_fuse_chain(skill_index: int, skill: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(148, 72)
	row.add_theme_constant_override("separation", 4)
	row.alignment = BoxContainer.ALIGNMENT_CENTER

	var fuse_gem_type: Block.Type = SkillUpgradeUtils.responding_gem_type(_selected_character, skill)
	var base_tex: Texture2D = Block.GEM_TEXTURES.get(fuse_gem_type, null)
	row.add_child(_make_preview_icon(base_tex, Vector2(36, 36)))

	var fuse_lbl := Label.new()
	fuse_lbl.text = "%s+" % SkillUpgradeUtils.responding_fuse_label(_selected_character, skill_index, skill)
	fuse_lbl.add_theme_font_size_override("font_size", 15)
	fuse_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.52))
	fuse_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(fuse_lbl)

	var arrow_lbl := Label.new()
	arrow_lbl.text = ">"
	arrow_lbl.add_theme_font_size_override("font_size", 17)
	arrow_lbl.add_theme_color_override("font_color", Color(0.74, 0.90, 1.0))
	arrow_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(arrow_lbl)

	var upper_tex: Texture2D = _upper_texture_for_skill(skill)
	row.add_child(_make_preview_icon(upper_tex, Vector2(46, 46)))
	return row


func _make_preview_icon(texture: Texture2D, icon_size: Vector2) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = icon_size
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return icon


func _make_blast_grid(pattern: Array, upper_type: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.custom_minimum_size = Vector2(76, 76)
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	var hit_color: Color = UpperGemDefs.get_preview_color(upper_type, Color(0.32, 0.88, 1.0))
	for y in range(5):
		for x in range(5):
			var cell := PanelContainer.new()
			cell.custom_minimum_size = Vector2(BLAST_GRID_CELL_SIZE, BLAST_GRID_CELL_SIZE)
			var style := StyleBoxFlat.new()
			var hit := pattern.has(Vector2i(x, y))
			style.bg_color = hit_color if hit else Color(0.10, 0.14, 0.18, 0.82)
			style.border_color = Color(0.40, 0.52, 0.62, 0.75)
			style.set_border_width_all(1)
			style.set_corner_radius_all(2)
			cell.add_theme_stylebox_override("panel", style)
			grid.add_child(cell)
	return grid


func _blast_pattern_for(upper_type: int) -> Array:
	if Block.upper_type_has_building(upper_type):
		return [Vector2i(2, 2)]
	match upper_type:
		Block.UpperType.FIREBALL:
			return [Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 3), Vector2i(1, 2), Vector2i(3, 2)]
		Block.UpperType.FIRE_PILLAR_X:
			var cells_x: Array = []
			for x in 5:
				cells_x.append(Vector2i(x, 2))
			return cells_x
		Block.UpperType.FIRE_PILLAR_Y, Block.UpperType.WATER_SLASH:
			var cells_y: Array = []
			for y in 5:
				cells_y.append(Vector2i(2, y))
			return cells_y
		Block.UpperType.SAINT_CROSS:
			return [Vector2i(2, 2), Vector2i(0, 0), Vector2i(1, 1), Vector2i(3, 3), Vector2i(4, 4),
					Vector2i(0, 4), Vector2i(1, 3), Vector2i(3, 1), Vector2i(4, 0)]
		Block.UpperType.SNOWBALL:
			var cells_b: Array = []
			for x in range(1, 4):
				for y in range(1, 4):
					cells_b.append(Vector2i(x, y))
			return cells_b
		Block.UpperType.ICEBALL, Block.UpperType.LEAF_RAY, Block.UpperType.LEAF_SHIELD, Block.UpperType.BAMBOO_SUPPLY:
			return [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
					Vector2i(1, 2),                  Vector2i(3, 2),
					Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)]
		Block.UpperType.WOOD_SPEAR_UP:
			return [Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 0), Vector2i(1, 0), Vector2i(3, 0)]
		Block.UpperType.WOOD_SPEAR_DOWN:
			return [Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(1, 4), Vector2i(3, 4)]
		Block.UpperType.LIGHT_SHIELD:
			var cells_light: Array = []
			for x in 5:
				cells_light.append(Vector2i(x, 2))
			return cells_light
	return []


func _apply_template_to_selected(skill_index: int, template: Dictionary) -> void:
	if _selected_character == null or template.is_empty():
		return
	var updated: Dictionary = template.duplicate(true)
	updated.erase("icon")
	updated.erase("display_name")
	updated.erase("short_name")
	updated["fuse_label"] = str(updated.get("threshold", 1))
	updated["priority"] = int(updated.get("priority", maxi(1, _selected_character.responding_skills.size() - skill_index + 1)))

	if skill_index >= 0 and skill_index < _selected_character.responding_skills.size():
		_selected_character.responding_skills[skill_index] = updated
	else:
		_selected_character.responding_skills.append(updated)

	_save_selected_responding_skills("已寫入 %s：%s" % [_selected_character.resource_path, updated.get("name", "")])


func _delete_skill_from_selected(skill_index: int) -> void:
	if _selected_character == null:
		return
	if skill_index < 0 or skill_index >= _selected_character.responding_skills.size():
		return
	var removed: Dictionary = _selected_character.responding_skills[skill_index]
	var removed_name: String = str(removed.get("name", ""))
	_selected_character.responding_skills.remove_at(skill_index)
	_save_selected_responding_skills("已刪除 %s：%s" % [_selected_character.resource_path, removed_name])


func _save_selected_responding_skills(success_text: String) -> void:
	var path := _selected_character.resource_path
	var err := ResourceSaver.save(_selected_character, path)
	if err == OK:
		_sync_live_character_resource(path, _selected_character.responding_skills)
		_status_lbl.text = success_text
		_status_lbl.add_theme_color_override("font_color", Color(0.62, 1.0, 0.70))
	else:
		_status_lbl.text = "存檔失敗 %s (err=%d)" % [path, err]
		_status_lbl.add_theme_color_override("font_color", Color(1.0, 0.42, 0.36))
	_rebuild_info()


func _sync_live_character_resource(path: String, responding_skills: Array[Dictionary]) -> void:
	var cached := ResourceLoader.load(path)
	if cached is CharacterData and cached != _selected_character:
		(cached as CharacterData).responding_skills = responding_skills.duplicate(true)
	for c: CharacterData in GameState.owned_characters:
		if c != null and c.resource_path == path:
			c.responding_skills = responding_skills.duplicate(true)
	for c: CharacterData in GameState.selected_party:
		if c != null and c.resource_path == path:
			c.responding_skills = responding_skills.duplicate(true)


func _on_reload_pressed() -> void:
	var previous_path := _selected_character.resource_path if _selected_character != null else ""
	_load_characters()
	for child in _character_flow.get_children():
		child.queue_free()
	_build_character_list_items()
	var found: CharacterData = null
	for character: CharacterData in _characters:
		if character.resource_path == previous_path:
			found = character
			break
	_select_character(found if found != null else (_characters[0] if not _characters.is_empty() else null), null)
	_status_lbl.text = "已重新載入角色 .tres。"
	_status_lbl.add_theme_color_override("font_color", Color(0.74, 0.88, 0.94))


func _build_character_list_items() -> void:
	if _character_flow == null:
		return
	for character: CharacterData in _characters:
		var btn := Button.new()
		btn.custom_minimum_size = CARD_SIZE
		btn.tooltip_text = "%s\n%s" % [Locale.tr_ui(character.character_name), character.resource_path]
		btn.pressed.connect(_select_character.bind(character, btn))
		_character_flow.add_child(btn)

		var cell := VBoxContainer.new()
		cell.set_anchors_preset(Control.PRESET_FULL_RECT)
		cell.offset_left = 4
		cell.offset_right = -4
		cell.offset_top = 4
		cell.offset_bottom = -4
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(cell)

		var wrap := Control.new()
		wrap.custom_minimum_size = Vector2(70, 70)
		wrap.clip_contents = true
		wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(wrap)
		var card_result: Dictionary = CharacterCard.make_square(character)
		var card: PanelContainer = card_result.get("panel", null) as PanelContainer
		if card != null:
			card.set_anchors_preset(Control.PRESET_FULL_RECT)
			card.mouse_filter = Control.MOUSE_FILTER_IGNORE
			wrap.add_child(card)

		var name_lbl := Label.new()
		name_lbl.text = Locale.tr_ui(character.character_name)
		name_lbl.add_theme_font_size_override("font_size", 11)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(name_lbl)


func _upper_gem_templates() -> Array[Dictionary]:
	return [
		_skill_template("Fireball", "Fireball", "Fireball", Block.UpperType.FIREBALL, "count", "create a Fireball gem at tapped cell. Tap to blast cross area."),
		_skill_template("Fire Pillar", "Fire Pillar", "Pillar", Block.UpperType.FIRE_PILLAR_X, "line", "create a Fire Pillar gem. Tap to blast entire row or column."),
		_skill_template("Justice Slash", "Saint Cross", "Cross", Block.UpperType.SAINT_CROSS, "count", "create a Saint Cross upper gem at tapped cell."),
		_skill_template("Leaf Shield", "Leaf Shield", "Leaf", Block.UpperType.LEAF_SHIELD, "count", "create a Leaf Shield gem at tapped cell."),
		_skill_template("Snowball", "Snowball", "Snow", Block.UpperType.SNOWBALL, "count", "create a Snowball gem at tapped cell. Click to blast 8 surrounding gems."),
		_skill_template("Iceball", "Iceball", "Ice", Block.UpperType.ICEBALL, "count", "create an Iceball gem at tapped cell."),
		_skill_template("Water Slash", "Water Slash", "Slash", Block.UpperType.WATER_SLASH, "count", "create a Water Slash gem at tapped cell."),
		_skill_template("Porcupine", "Porcupine", "Spike", Block.UpperType.PORCUPINE, "count", "summon a Porcupine gem at tapped cell."),
		_skill_template("Turtle", "Turtle", "Turtle", Block.UpperType.TURTLE, "count", "summon a Turtle gem at tapped cell."),
		_skill_template("Emerald Tower", "Emerald Tower", "Tower", Block.UpperType.EMERALD_TOWER, "count", "summon an Emerald Tower building gem at tapped cell."),
		_skill_template("Bamboo Supply", "Bamboo", "Bamboo", Block.UpperType.BAMBOO_SUPPLY, "count", "create a Bamboo Supply gem at tapped cell."),
		_skill_template("Wood Spear", "Wood Spear", "Spear", Block.UpperType.WOOD_SPEAR_UP, "count", "create a Wood Spear gem at tapped cell."),
		_skill_template("Leaf Ray", "Leaf Ray", "Ray", Block.UpperType.LEAF_RAY, "count", "create an instant Leaf Ray gem at tapped cell."),
		_skill_template("光之盾", "光之盾", "Light", Block.UpperType.LIGHT_SHIELD, "count", "create a Light Shield upper gem."),
	]


func _skill_template(skill_name: String, display_name: String, short_name: String, upper_type: Block.UpperType, trigger_type: String, desc: String) -> Dictionary:
	var threshold: int = SkillUpgradeUtils.default_fuse_threshold_for_upper(upper_type)
	var requirement_type: Block.Type = Block.UPPER_ELEMENT.get(upper_type, Block.Type.RED) as Block.Type
	if upper_type == Block.UpperType.EMERALD_TOWER:
		requirement_type = Block.Type.LIGHT
	return {
		"name": skill_name,
		"display_name": display_name,
		"short_name": short_name,
		"desc": desc,
		"threshold": threshold,
		"fuse_label": str(threshold),
		"trigger_type": trigger_type,
		"priority": 1,
		"upper_type": upper_type,
		"gem_type": int(requirement_type),
		"icon": Block.UPPER_GEM_TEXTURES.get(upper_type, null),
	}


func _upper_texture_for_skill(skill: Dictionary) -> Texture2D:
	var upper_type := SkillUpgradeUtils.responding_upper_type(skill)
	if upper_type == Block.UpperType.NONE:
		return null
	return Block.UPPER_GEM_TEXTURES.get(upper_type, null)


func _make_section(title_text: String) -> VBoxContainer:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.size_flags_vertical = Control.SIZE_EXPAND_FILL
	section.size_flags_stretch_ratio = 1.0
	section.add_theme_constant_override("separation", 5)
	section.add_child(_make_section_label(title_text))
	return section


func _make_section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.58, 0.92, 1.0))
	return label


func _add_plain_label(parent: Control, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label


func _make_panel_style(bg_color: Color, border_color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = border_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _gem_type_name(gem_type: int) -> String:
	match gem_type:
		Block.Type.RED:
			return "RED"
		Block.Type.BLUE:
			return "BLUE"
		Block.Type.GREEN:
			return "GREEN"
		Block.Type.LIGHT:
			return "LIGHT"
		Block.Type.DARK:
			return "DARK"
	return str(gem_type)
