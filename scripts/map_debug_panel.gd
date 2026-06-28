## MapDebugPanel - 世界地圖 F4 浮動 debug 面板。
class_name MapDebugPanel
extends RefCounted


static func build(parent: Node, on_cleared: Callable) -> Control:
	var panel := PanelContainer.new()
	panel.z_index = 100
	parent.add_child(panel)
	panel.offset_left = -292
	panel.offset_top = 4
	panel.offset_right = -4
	panel.offset_bottom = 236
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	bg.set_border_width_all(1)
	bg.border_color = Color(0.4, 0.4, 0.5, 0.8)
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", bg)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 7)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "地圖除錯（F4 關閉）"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	var info := Label.new()
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	info.text = _make_info_text()
	vbox.add_child(info)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 6)
	action_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(action_row)

	var reset_map_btn := _make_action_button("重置地圖", "↺", Color(1.0, 0.78, 0.62))
	action_row.add_child(reset_map_btn)

	var reset_owned_btn := _make_action_button("重置角色", "人", Color(0.72, 0.95, 1.0))
	action_row.add_child(reset_owned_btn)

	var grant_all_btn := _make_action_button("全部取得", "全", Color(1.0, 0.88, 0.35))
	action_row.add_child(grant_all_btn)

	var sapphire_btn := _make_action_button("藍寶 +1", "", Color(0.62, 0.82, 1.0), ItemDefs.get_image(ItemDefs.Type.SAPPHIRE))
	action_row.add_child(sapphire_btn)

	var status := Label.new()
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6))
	status.text = ""
	vbox.add_child(status)

	reset_map_btn.pressed.connect(func() -> void:
		GameState.reset_map_progress()
		status.text = "地圖進度已重置。"
		info.text = _make_info_text()
		if on_cleared.is_valid():
			on_cleared.call()
	)

	reset_owned_btn.pressed.connect(func() -> void:
		GameState.reset_owned_character_list()
		status.text = "角色與技能升級已重置。"
		info.text = _make_info_text()
		if on_cleared.is_valid():
			on_cleared.call()
	)

	grant_all_btn.pressed.connect(func() -> void:
		var added: int = GameState.debug_grant_all_characters(true)
		status.text = "全部取得完成，新增 %d 個。" % added
		info.text = _make_info_text()
		if on_cleared.is_valid():
			on_cleared.call()
	)

	sapphire_btn.pressed.connect(func() -> void:
		GameState.add_loot(ItemDefs.Type.SAPPHIRE, 1)
		status.text = "藍寶石 +1。"
		info.text = _make_info_text()
		if on_cleared.is_valid():
			on_cleared.call()
	)

	return panel


static func _make_action_button(label_text: String, icon_text: String, tint: Color, icon_texture: Texture2D = null) -> Button:
	var button := Button.new()
	button.text = ""
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(64, 66)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(tint.r * 0.22, tint.g * 0.22, tint.b * 0.22, 0.5)
	style.border_color = Color(tint.r, tint.g, tint.b, 0.62)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(3)
	button.add_theme_stylebox_override("normal", style)

	var hover: StyleBoxFlat = style.duplicate() as StyleBoxFlat
	hover.bg_color = style.bg_color.lightened(0.12)
	button.add_theme_stylebox_override("hover", hover)

	var pressed: StyleBoxFlat = style.duplicate() as StyleBoxFlat
	pressed.bg_color = style.bg_color.darkened(0.12)
	button.add_theme_stylebox_override("pressed", pressed)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 3)
	margin.add_theme_constant_override("margin_right", 3)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	button.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 1)
	margin.add_child(column)

	if icon_texture != null:
		var icon := TextureRect.new()
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.texture = icon_texture
		icon.custom_minimum_size = Vector2(28, 28)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		column.add_child(icon)
	else:
		var icon_label := Label.new()
		icon_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon_label.text = icon_text
		icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_label.add_theme_font_size_override("font_size", 18)
		icon_label.add_theme_color_override("font_color", tint)
		column.add_child(icon_label)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = label_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", tint.lightened(0.16))
	column.add_child(label)
	return button


static func _make_info_text() -> String:
	return "已通關關卡：%d\n持有角色：%d\n技能升級：%d\n金幣：%d\n藍寶石：%d" % [
		GameState.cleared_stages.size(),
		GameState.owned_characters.size(),
		GameState.skill_upgrade_levels.size(),
		GameState.gold,
		GameState.get_inventory_count(ItemDefs.Type.SAPPHIRE),
	]
