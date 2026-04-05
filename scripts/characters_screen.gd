## CharactersScreen（角色列表畫面）— 顯示玩家擁有的所有角色。
## 點擊角色卡片可進入詳細資訊畫面。
extends Node2D


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# Background
	var bg := ColorRect.new()
	bg.offset_right = 576.0
	bg.offset_bottom = 1024.0
	bg.color = Color(0.09, 0.09, 0.14, 1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var layer := CanvasLayer.new()
	add_child(layer)

	# Title
	var title := Label.new()
	title.text = "CHARACTERS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.offset_left = 0.0
	title.offset_top = 40.0
	title.offset_right = 576.0
	title.offset_bottom = 90.0
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	layer.add_child(title)

	# Scroll container for grid
	var scroll := ScrollContainer.new()
	scroll.offset_left = 32.0
	scroll.offset_top = 110.0
	scroll.offset_right = 544.0
	scroll.offset_bottom = 920.0
	layer.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 24)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for i in GameState.owned_characters.size():
		var c: CharacterData = GameState.owned_characters[i]
		var card := _make_card(c, i)
		grid.add_child(card)

	# Back button
	var back_btn := Button.new()
	back_btn.text = "Back to Map"
	back_btn.offset_left = 200.0
	back_btn.offset_top = 940.0
	back_btn.offset_right = 376.0
	back_btn.offset_bottom = 980.0
	back_btn.pressed.connect(_on_back_pressed)
	layer.add_child(back_btn)


func _make_card(c: CharacterData, index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(230, 280)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15, 0.17, 0.25, 1)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.4, 0.45, 0.65, 1)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_right = 8
	style.corner_radius_bottom_left = 8
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	# Portrait
	if c.portrait_texture:
		var portrait := TextureRect.new()
		portrait.texture = c.portrait_texture
		portrait.custom_minimum_size = Vector2(200, 180)
		portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(portrait)
	else:
		var portrait := ColorRect.new()
		portrait.custom_minimum_size = Vector2(200, 180)
		portrait.color = c.portrait_color
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(portrait)

	# Name
	var name_lbl := Label.new()
	name_lbl.text = c.character_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	# Level
	var lv_lbl := Label.new()
	lv_lbl.text = "Lv. %d" % c.level
	lv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_lbl.add_theme_font_size_override("font_size", 14)
	lv_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	lv_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(lv_lbl)

	# Click handler
	panel.gui_input.connect(_on_card_clicked.bind(index))

	return panel


func _on_card_clicked(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		GameState.detail_character = GameState.owned_characters[index]
		get_tree().change_scene_to_file("res://scenes/character_detail.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map.tscn")
