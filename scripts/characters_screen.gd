## CharactersScreen（角色列表畫面）— 顯示玩家擁有的所有角色。
## 點擊角色卡片可進入詳細資訊畫面。使用 CharacterCard 共用元件。
extends Node2D

const CharacterSorter = preload("res://scripts/character_sorter.gd")
const RosterLayout = preload("res://scripts/roster_layout.gd")

var _sort_mode: int = CharacterSorter.Mode.LEVEL
var _roster_host: Control = null
var _card_panels: Array[PanelContainer] = []   # 對應 owned_characters[i]


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

	# 標題列：左側「角色選擇」、右側排序按鈕
	var header := HBoxContainer.new()
	header.offset_left = 48.0
	header.offset_top = 96.0
	header.offset_right = 808.0
	header.offset_bottom = 132.0
	header.add_theme_constant_override("separation", 8)
	layer.add_child(header)

	var sel_label := Label.new()
	sel_label.text = Locale.tr_ui("CHAR_SELECTION")
	sel_label.add_theme_font_size_override("font_size", 20)
	sel_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	sel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(sel_label)

	var sort_row: HBoxContainer = CharacterSorter.make_sort_buttons(_sort_mode, _on_sort_changed)
	header.add_child(sort_row)

	# Scroll container + host（RosterLayout 清空並重建內部佈局）
	var scroll := ScrollContainer.new()
	scroll.offset_left = 48.0
	scroll.offset_top = 140.0
	scroll.offset_right = 808.0
	scroll.offset_bottom = 920.0
	layer.add_child(scroll)

	_roster_host = VBoxContainer.new()
	_roster_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_roster_host)

	_build_cards()
	_apply_sort()

	# Back button
	var back_btn := Button.new()
	back_btn.text = Locale.tr_ui("BACK_MAP")
	back_btn.offset_left = 320.0
	back_btn.offset_top = 940.0
	back_btn.offset_right = 536.0
	back_btn.offset_bottom = 980.0
	back_btn.pressed.connect(_on_back_pressed)
	layer.add_child(back_btn)


func _build_cards() -> void:
	_card_panels.clear()
	for i in GameState.owned_characters.size():
		var c: CharacterData = GameState.owned_characters[i]
		var card: PanelContainer = CharacterCard.make(c, CharacterCard.CardSize.SMALL)
		card.gui_input.connect(_on_card_clicked.bind(i))
		_card_panels.append(card)


func _on_sort_changed(mode: int) -> void:
	_sort_mode = mode
	_apply_sort()


func _apply_sort() -> void:
	var entries: Array = []
	for i in GameState.owned_characters.size():
		entries.append({"i": i, "c": GameState.owned_characters[i], "card": _card_panels[i]})
	RosterLayout.apply(_roster_host, entries, _sort_mode, 4)


func _on_card_clicked(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		GameState.detail_character = GameState.owned_characters[index]
		get_tree().change_scene_to_file("res://scenes/character_detail.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map.tscn")
