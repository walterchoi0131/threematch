## InventoryScreen（背包畫面）— 顯示玩家持有的金幣與物品。
extends Control

const FONT_PATH := "res://assets/fonts/RussoOne-Regular.ttf"

var _font: Font


func _ready() -> void:
	_font = load(FONT_PATH)
	_build_ui()


func _build_ui() -> void:
	# 標題
	var title := _make_label(Locale.tr_ui("INVENTORY"), 36, Color(1.0, 0.9, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 50.0
	title.offset_bottom = 100.0
	add_child(title)

	# 金幣區
	var gold_row := HBoxContainer.new()
	gold_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
	gold_row.offset_top = 120.0
	gold_row.offset_bottom = 160.0
	gold_row.offset_left = 48.0
	gold_row.offset_right = -48.0
	gold_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gold_row.add_theme_constant_override("separation", 12)
	add_child(gold_row)

	var gold_icon := _make_label("💰", 28, Color(1, 0.85, 0.15))
	gold_row.add_child(gold_icon)

	var gold_lbl := _make_label("%s:  %d" % [Locale.tr_ui("GOLD"), GameState.gold], 28, Color(1, 0.85, 0.15))
	gold_row.add_child(gold_lbl)

	# 分隔線
	var sep := HSeparator.new()
	sep.set_anchors_preset(Control.PRESET_TOP_WIDE)
	sep.offset_top = 170.0
	sep.offset_bottom = 178.0
	sep.offset_left = 48.0
	sep.offset_right = -48.0
	add_child(sep)

	# 物品列表
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 190.0
	scroll.offset_bottom = -80.0
	scroll.offset_left = 48.0
	scroll.offset_right = -48.0
	add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	var has_items := false
	for type: ItemDefs.Type in GameState.inventory:
		var amount: int = GameState.inventory[type]
		if amount <= 0:
			continue
		has_items = true
		var card := _make_item_card(type, amount)
		grid.add_child(card)

	if not has_items:
		var empty_lbl := _make_label(Locale.tr_ui("NO_ITEMS"), 20, Color(0.5, 0.5, 0.55))
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(empty_lbl)

	# 返回按鈕
	var back_btn := Button.new()
	back_btn.text = Locale.tr_ui("BACK_MAP")
	back_btn.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	back_btn.offset_top = -60.0
	back_btn.offset_bottom = -16.0
	back_btn.offset_left = 160.0
	back_btn.offset_right = -160.0
	back_btn.pressed.connect(_on_back_pressed)
	add_child(back_btn)


func _make_item_card(type: ItemDefs.Type, amount: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(200, 60)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.22, 1)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.35, 0.5, 1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	panel.add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)

	var color: Color = ItemDefs.get_color(type)

	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(20, 20)
	dot.color = color
	hbox.add_child(dot)

	var lbl := _make_label("%s  ×%d" % [ItemDefs.get_display_name(type), amount], 18, color)
	hbox.add_child(lbl)

	return panel


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map.tscn")
