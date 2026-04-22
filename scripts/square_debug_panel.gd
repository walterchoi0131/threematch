## SquareDebugPanel — F9 即時調整 CharacterData.square_scale / square_offset 的浮動面板。
## 拖動滑桿時：呼叫 on_apply(c) 讓畫面更新對應頭像，並自動寫回 .tres。
class_name SquareDebugPanel
extends RefCounted


## 建立浮動面板並回傳節點本身（呼叫端負責 free / queue_free）。
##   parent: 將面板加為子節點的容器（CanvasLayer 或 Control）。
##   characters: 要編輯的 CharacterData 陣列。
##   on_apply: Callable(c: CharacterData) -> void，於滑桿異動時被呼叫，畫面端負責即時刷新。
static func build(parent: Node, characters: Array, on_apply: Callable) -> Control:
	var panel := PanelContainer.new()
	panel.z_index = 100
	parent.add_child(panel)
	panel.offset_left = 4
	panel.offset_top = 4
	panel.offset_right = 274
	panel.offset_bottom = 600

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	bg.set_border_width_all(1)
	bg.border_color = Color(0.4, 0.4, 0.5, 0.8)
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", bg)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "Square Debug (F9 close)"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	for c: CharacterData in characters:
		var section := VBoxContainer.new()
		vbox.add_child(section)

		var name_lbl := Label.new()
		name_lbl.text = "── %s ──" % c.character_name
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		section.add_child(name_lbl)

		var cap: CharacterData = c
		_add_slider(section, "Sq Scale", cap.square_scale, 0.1, 5.0, 0.05, func(v: float) -> void:
			cap.square_scale = v
			on_apply.call(cap)
			_save(cap)
		)
		_add_slider(section, "Sq X", cap.square_offset.x, -400, 400, 1.0, func(v: float) -> void:
			cap.square_offset.x = v
			on_apply.call(cap)
			_save(cap)
		)
		_add_slider(section, "Sq Y", cap.square_offset.y, -400, 400, 1.0, func(v: float) -> void:
			cap.square_offset.y = v
			on_apply.call(cap)
			_save(cap)
		)

	# 列印目前數值
	var print_btn := Button.new()
	print_btn.text = "Print values to console"
	print_btn.pressed.connect(func() -> void:
		for cd: CharacterData in characters:
			print("%s  square_scale = %.2f  square_offset = Vector2(%.1f, %.1f)" % [
				cd.character_name, cd.square_scale, cd.square_offset.x, cd.square_offset.y])
	)
	vbox.add_child(print_btn)

	return panel


## 即時將異動寫回 .tres 檔（僅當 resource_path 已設定時）
static func _save(c: CharacterData) -> void:
	if c == null or c.resource_path == "":
		return
	var err: int = ResourceSaver.save(c, c.resource_path)
	if err != OK:
		push_warning("SquareDebugPanel: failed to save %s (err=%d)" % [c.resource_path, err])


static func _add_slider(parent: Control, label_text: String, initial: float, min_val: float, max_val: float, step_val: float, on_changed: Callable) -> void:
	var hbox := HBoxContainer.new()
	parent.add_child(hbox)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(65, 0)
	lbl.add_theme_font_size_override("font_size", 13)
	hbox.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step_val
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(100, 0)
	hbox.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.text = "%.2f" % initial
	val_lbl.custom_minimum_size = Vector2(50, 0)
	val_lbl.add_theme_font_size_override("font_size", 13)
	hbox.add_child(val_lbl)

	slider.value_changed.connect(func(v: float) -> void:
		val_lbl.text = "%.2f" % v
		on_changed.call(v)
	)
