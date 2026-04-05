## CharacterPanel（角色面板）— 顯示隊伍角色卡片的水平容器。
## 負責角色卡片的建立、攻擊動畫、冷卻顯示、發光效果、治療文字等。
extends HBoxContainer

signal active_skill_activated(char_index: int)  # 主動技能觸發信號

var _cards: Array[Control] = []        # 角色卡片陣列
var _card_orig_y: Dictionary = {}      # 角色卡片原始 Y 座標
var _glow_tweens: Dictionary = {}      # 角色索引 -> 發光動畫
var _glow_panels: Dictionary = {}      # 角色索引 -> 發光覆蓋層
var _cd_labels: Dictionary = {}        # 角色索引 -> 冷卻標籤
var _char_data: Array[CharacterData] = []  # 角色資料陣列


## 初始化角色面板：為每個角色建立卡片
func setup(characters: Array[CharacterData]) -> void:
	_cards.clear()
	_char_data = characters
	for child in get_children():
		child.queue_free()

	for i in characters.size():
		var card := _make_card(characters[i], i)
		add_child(card)
		_cards.append(card)


## 取得角色卡片的螢幕中心座標
func get_card_screen_center(index: int) -> Vector2:
	if index < 0 or index >= _cards.size():
		return Vector2.ZERO
	return _cards[index].get_global_rect().get_center()


## 建立單張角色卡片
func _make_card(c: CharacterData, index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(120, 120)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	# 頭像 — 有貼圖用貼圖，否則用色塊
	if c.portrait_texture:
		var portrait := TextureRect.new()
		portrait.texture = c.portrait_texture
		portrait.custom_minimum_size = Vector2(120, 110)
		portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(portrait)
	else:
		var portrait := ColorRect.new()
		portrait.custom_minimum_size = Vector2(120, 110)
		portrait.color = c.portrait_color
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(portrait)

	# 發光覆蓋層（預設隱藏）
	var glow := ColorRect.new()
	glow.color = Color(1.0, 0.9, 0.2, 0.0)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(glow)
	_glow_panels[index] = glow

	# 冷卻標籤覆蓋層（預設隱藏）
	var cd_lbl := Label.new()
	cd_lbl.text = ""
	cd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	cd_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	cd_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	cd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cd_lbl.add_theme_font_size_override("font_size", 20)
	cd_lbl.visible = false
	panel.add_child(cd_lbl)
	_cd_labels[index] = cd_lbl

	# 點擊處理
	panel.gui_input.connect(_on_card_gui_input.bind(index))

	return panel


func _on_card_gui_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		active_skill_activated.emit(index)


## 顯示主動技能冷卻數字。turns_left=0 表示已就緒。
func update_cooldown(index: int, turns_left: int) -> void:
	if not _cd_labels.has(index):
		return
	var cd_lbl: Label = _cd_labels[index]
	if turns_left > 0:
		cd_lbl.text = "CD %d" % turns_left
		cd_lbl.visible = true
		_stop_glow(index)
	else:
		cd_lbl.visible = false


## 開始卡片發光脈衝（主動技能已就緒）
func start_glow(index: int) -> void:
	if not _glow_panels.has(index):
		return
	_stop_glow(index)
	var glow: ColorRect = _glow_panels[index]
	var tween := create_tween().set_loops()
	tween.tween_property(glow, "color:a", 0.35, 0.5).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(glow, "color:a", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT)
	_glow_tweens[index] = tween


## 停止發光
func _stop_glow(index: int) -> void:
	if _glow_tweens.has(index):
		var old_tween: Tween = _glow_tweens[index]
		if old_tween.is_valid():
			old_tween.kill()
		_glow_tweens.erase(index)
	if _glow_panels.has(index):
		_glow_panels[index].color.a = 0.0


## 在角色卡片上方顯示浮動治療文字
func show_heal_text(index: int, amount: int) -> void:
	if index < 0 or index >= _cards.size():
		return
	var card := _cards[index]
	var lbl := Label.new()
	lbl.text = "+%d" % amount
	lbl.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3))
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(card.size.x * 0.5 - 20, -10)
	card.add_child(lbl)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(lbl, "position:y", lbl.position.y - 30, 0.6)
	tween.tween_property(lbl, "modulate:a", 0.0, 0.6).set_delay(0.3)
	tween.chain().tween_callback(lbl.queue_free)


## 攻擊動畫：角色卡向上彈起
func play_card_attack_up(index: int) -> void:
	if index < 0 or index >= _cards.size():
		return
	var card := _cards[index]
	_card_orig_y[index] = card.position.y
	var tween := create_tween()
	tween.tween_property(card, "position:y", card.position.y - 20.0, 0.12) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	await tween.finished


## 攻擊動畫：角色卡回到原位
func play_card_return(index: int) -> void:
	if index < 0 or index >= _cards.size():
		return
	var card := _cards[index]
	var orig_y: float = _card_orig_y.get(index, card.position.y)
	var tween := create_tween()
	tween.tween_property(card, "position:y", orig_y, 0.12) \
		.set_ease(Tween.EASE_IN)
	await tween.finished

