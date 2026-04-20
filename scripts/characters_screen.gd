## CharactersScreen（角色列表畫面）— 顯示玩家擁有的所有角色。
## 點擊角色卡片可進入詳細資訊畫面。使用 CharacterCard 共用元件。
extends Node2D


func _ready() -> void:
	_build_ui()


func _build_ui() -> void:
	# Background
	var bg := ColorRect.new()
	bg.offset_right = 856.0
	bg.offset_bottom = 1024.0
	bg.color = Color(0.09, 0.09, 0.14, 1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var layer := CanvasLayer.new()
	add_child(layer)

	# Title
	var title := Label.new()
	title.text = Locale.tr_ui("CHARACTERS")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.offset_left = 0.0
	title.offset_top = 40.0
	title.offset_right = 856.0
	title.offset_bottom = 90.0
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	layer.add_child(title)

	# Scroll container for grid
	var scroll := ScrollContainer.new()
	scroll.offset_left = 48.0
	scroll.offset_top = 110.0
	scroll.offset_right = 808.0
	scroll.offset_bottom = 920.0
	layer.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for i in GameState.owned_characters.size():
		var c: CharacterData = GameState.owned_characters[i]
		var data: Dictionary = CharacterCard.make_battle(c)
		var card: PanelContainer = data.panel
		card.gui_input.connect(_on_card_clicked.bind(i))
		grid.add_child(card)

	# Back button
	var back_btn := Button.new()
	back_btn.text = Locale.tr_ui("BACK_MAP")
	back_btn.offset_left = 320.0
	back_btn.offset_top = 940.0
	back_btn.offset_right = 536.0
	back_btn.offset_bottom = 980.0
	back_btn.pressed.connect(_on_back_pressed)
	layer.add_child(back_btn)


func _on_card_clicked(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		GameState.detail_character = GameState.owned_characters[index]
		get_tree().change_scene_to_file("res://scenes/character_detail.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map.tscn")
