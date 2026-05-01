## MapDebugPanel — 世界地圖 F9 浮動 debug 面板。
## 目前提供：清除存檔（刪除 user://save.json + 重置記憶體狀態）。
class_name MapDebugPanel
extends RefCounted


## 建立浮動面板並回傳節點本身（呼叫端負責 free / queue_free）。
##   parent: 將面板加為子節點的容器（CanvasLayer 或 Control）。
##   on_cleared: Callable() -> void，於清除存檔後被呼叫，畫面端負責即時刷新。
static func build(parent: Node, on_cleared: Callable) -> Control:
	var panel := PanelContainer.new()
	panel.z_index = 100
	parent.add_child(panel)
	panel.offset_left = -274
	panel.offset_top = 4
	panel.offset_right = -4
	panel.offset_bottom = 200
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

	# 清除存檔按鈕
	var clear_btn := Button.new()
	clear_btn.text = "Clear Save (delete save.json + reset)"
	clear_btn.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7))
	vbox.add_child(clear_btn)

	var status := Label.new()
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6))
	status.text = ""
	vbox.add_child(status)

	clear_btn.pressed.connect(func() -> void:
		GameState.clear_save()
		status.text = "Save cleared."
		info.text = _make_info_text()
		if on_cleared.is_valid():
			on_cleared.call()
	)

	return panel


static func _make_info_text() -> String:
	return "Cleared stages: %d\nOwned characters: %d\nGold: %d" % [
		GameState.cleared_stages.size(),
		GameState.owned_characters.size(),
		GameState.gold,
	]
