## CharactersScreen（角色列表畫面）— 顯示玩家擁有的所有角色。
## 點擊角色卡片可進入詳細資訊畫面。使用 CharacterCard 共用元件。
## 以覆蓋層方式由 map.gd 開啟，關閉時 emit `closed` 訊號。
extends Control

signal closed

const CharacterSorter = preload("res://scripts/character_sorter.gd")
const RosterLayout = preload("res://scripts/roster_layout.gd")

var _sort_mode: int = CharacterSorter.Mode.TYPE
var _sort_ascending: bool = true   # TYPE 預設升冪
var _roster_host: Control = null
var _card_panels: Array[PanelContainer] = []   # 對應 owned_characters[i]
var _debug_panel: Control = null


func _ready() -> void:
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		_toggle_debug_panel()


func _toggle_debug_panel() -> void:
	if _debug_panel != null:
		_debug_panel.queue_free()
		_debug_panel = null
		return
	var chars: Array = []
	for c in GameState.owned_characters:
		chars.append(c)
	_debug_panel = SquareDebugPanel.build(self, chars, _apply_square_to_card)


## 即時更新角色列表畫面中對應角色卡片的頭像 scale/offset
func _apply_square_to_card(c: CharacterData) -> void:
	var idx: int = GameState.owned_characters.find(c)
	if idx < 0 or idx >= _card_panels.size():
		return
	var card: PanelContainer = _card_panels[idx]
	if not card.has_meta("_portrait"):
		return
	var p: TextureRect = card.get_meta("_portrait") as TextureRect
	if p == null:
		return
	p.scale = Vector2(c.square_scale, c.square_scale)
	p.position = c.square_offset


func _build_ui() -> void:
	# 卡片溢出容許（roster grid 內的元素圖示可能溢出卡片邊界）
	clip_contents = false

	# 背景：填滿覆蓋層 frame
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0, 0, 0, 0)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Title — 沿用「角色選擇」風格（font_size 20, Color(0.85,0.85,0.9)），加大
	var title := Label.new()
	title.text = Locale.tr_ui("CHARACTERS")
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))

	# 標題列：左側 Title、右側排序按鈕（移除「角色選擇」標籤）
	var header := HBoxContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 48.0
	header.offset_right = -48.0
	header.offset_top = 16.0
	header.offset_bottom = 60.0
	header.add_theme_constant_override("separation", 8)
	add_child(header)

	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var sort_row: HBoxContainer = CharacterSorter.make_sort_buttons(_sort_mode, _on_sort_changed, _sort_ascending)
	header.add_child(sort_row)

	# Scroll container + host（RosterLayout 清空並重建內部佈局）
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 48.0
	scroll.offset_right = -48.0
	scroll.offset_top = 70.0
	scroll.offset_bottom = -68.0
	add_child(scroll)

	_roster_host = VBoxContainer.new()
	_roster_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_roster_host)

	_build_cards()
	_apply_sort()

	# Back button
	var back_btn := Button.new()
	back_btn.text = Locale.tr_ui("BACK_SHORT")
	back_btn.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	back_btn.offset_left = 320.0
	back_btn.offset_right = -320.0
	back_btn.offset_top = -56.0
	back_btn.offset_bottom = -12.0
	back_btn.pressed.connect(_on_back_pressed)
	add_child(back_btn)


func _build_cards() -> void:
	_card_panels.clear()
	for i in GameState.owned_characters.size():
		var c: CharacterData = GameState.owned_characters[i]
		var data: Dictionary = CharacterCard.make_square(c)
		var card: PanelContainer = data.panel
		card.size_flags_horizontal = 0
		card.custom_minimum_size = Vector2(142, 142)
		card.gui_input.connect(_on_card_clicked.bind(i))
		_card_panels.append(card)


func _on_sort_changed(mode: int, ascending: bool) -> void:
	_sort_mode = mode
	_sort_ascending = ascending
	_apply_sort()


func _apply_sort() -> void:
	var entries: Array = []
	for i in GameState.owned_characters.size():
		entries.append({"i": i, "c": GameState.owned_characters[i], "card": _card_panels[i]})
	RosterLayout.apply(_roster_host, entries, _sort_mode, 5, _sort_ascending)


func _on_card_clicked(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		GameState.detail_character = GameState.owned_characters[index]
		get_tree().change_scene_to_file("res://scenes/character_detail.tscn")


func _on_back_pressed() -> void:
	# 若以 overlay 形式開啟（map.gd 將本節點掛在 OverlayFrame 之下），
	# 本節點不會是 current_scene；emit closed 讓 map 收回。
	# 否則（從 character_detail 直接 change_scene 進來，本節點為 current_scene），
	# 改用 change_scene_to_file 回到地圖。
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file("res://scenes/map.tscn")
	else:
		closed.emit()
