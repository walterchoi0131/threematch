## MapDebugPanel — 世界地圖 F9 浮動 debug 面板。
## 目前提供：地圖進度、角色清單與道具的快速調整。
class_name MapDebugPanel
extends RefCounted


## 建立浮動面板並回傳節點本身（呼叫端負責 free / queue_free）。
##   parent: 將面板加為子節點的容器（CanvasLayer 或 Control）。
##   on_cleared: Callable() -> void，於 debug 狀態變更後被呼叫，畫面端負責即時刷新。
static func build(parent: Node, on_cleared: Callable) -> Control:
	var panel := PanelContainer.new()
	panel.z_index = 100
	parent.add_child(panel)
	panel.offset_left = -274
	panel.offset_top = 4
	panel.offset_right = -4
	panel.offset_bottom = 250
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
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Map Debug (F9 close)"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	# 狀態摘要
	var info := Label.new()
	info.add_theme_font_size_override("font_size", 12)
	info.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	info.text = _make_info_text()
	vbox.add_child(info)

	var reset_map_btn := Button.new()
	reset_map_btn.text = "Reset map progress"
	reset_map_btn.add_theme_color_override("font_color", Color(1.0, 0.78, 0.62))
	vbox.add_child(reset_map_btn)

	var reset_owned_btn := Button.new()
	reset_owned_btn.text = "Reset owned character list"
	reset_owned_btn.add_theme_color_override("font_color", Color(0.72, 0.95, 1.0))
	vbox.add_child(reset_owned_btn)

	var sapphire_btn := Button.new()
	sapphire_btn.text = "+1 Sapphire"
	sapphire_btn.add_theme_color_override("font_color", Color(0.62, 0.82, 1.0))
	vbox.add_child(sapphire_btn)

	var status := Label.new()
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6))
	status.text = ""
	vbox.add_child(status)

	reset_map_btn.pressed.connect(func() -> void:
		GameState.reset_map_progress()
		status.text = "Map progress reset."
		info.text = _make_info_text()
		if on_cleared.is_valid():
			on_cleared.call()
	)

	reset_owned_btn.pressed.connect(func() -> void:
		GameState.reset_owned_character_list()
		status.text = "Owned character list reset."
		info.text = _make_info_text()
		if on_cleared.is_valid():
			on_cleared.call()
	)

	sapphire_btn.pressed.connect(func() -> void:
		GameState.add_loot(ItemDefs.Type.SAPPHIRE, 1)
		status.text = "Sapphire +1."
		info.text = _make_info_text()
		if on_cleared.is_valid():
			on_cleared.call()
	)

	return panel


static func _make_info_text() -> String:
	return "Cleared stages: %d\nOwned characters: %d\nGold: %d\nSapphire: %d" % [
		GameState.cleared_stages.size(),
		GameState.owned_characters.size(),
		GameState.gold,
		GameState.get_inventory_count(ItemDefs.Type.SAPPHIRE),
	]
