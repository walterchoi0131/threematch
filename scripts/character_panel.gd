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
var _portraits: Dictionary = {}        # 角色索引 -> TextureRect（用於即時調整）
var _gem_icons: Dictionary = {}        # 角色索引 -> TextureRect（元素寶石圖示）
var _gem_rays: Dictionary = {}         # 角色索引 -> Node2D（技能就緒放射光芒）
var _debug_panel: Control = null       # 即時調整面板


## 初始化角色面板：為每個角色建立卡片
func setup(characters: Array[CharacterData]) -> void:
	_cards.clear()
	_gem_icons.clear()
	_gem_rays.clear()
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


## 進場準備：將所有卡片設為透明並推到螢幕底部以下
## 必須在 UI 佈局完成後（process_frame 之後）呼叫，才能讀取正確的 global_position
func prepare_intro() -> void:
	var vp_height: float = get_viewport_rect().size.y
	for i in _cards.size():
		var card := _cards[i]
		_card_orig_y[i] = card.position.y  # 記錄佈局後的正確目標 Y
		# 將卡片推到螢幕底部以下
		var push_down: float = vp_height - card.global_position.y + 20.0
		card.position.y += push_down
		card.modulate.a = 0.0


## 進場動畫：卡片從螢幕底部滑入目標位置 + 透明漸為不透明（fire-and-forget）
func play_intro_slide() -> void:
	for i in _cards.size():
		var card := _cards[i]
		var target_y: float = _card_orig_y.get(i, card.position.y)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(card, "position:y", target_y, 0.7) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(card, "modulate:a", 1.0, 0.5) \
			.set_ease(Tween.EASE_OUT)
		# 每張卡片間隔 0.16 秒依序出現
		if i < _cards.size() - 1:
			await get_tree().create_timer(0.16).timeout


## 建立單張角色卡片
func _make_card(c: CharacterData, index: int) -> PanelContainer:
	var result: Dictionary = CharacterCard.make_battle(c)
	var panel: PanelContainer = result.panel
	_glow_panels[index] = result.glow
	if result.portrait != null:
		_portraits[index] = result.portrait

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

	# 放射光芒（加到 gem_icon 作為子節點）
	var gem_icon: TextureRect = result.gem_icon
	var ray := Node2D.new()
	ray.set_script(load("res://scripts/ray_burst.gd"))
	ray.position = Vector2(14.0, 14.0)  # gem_size(28) * 0.5
	ray.z_index = -1
	ray.visible = false
	ray.set("outer_radius", 22.0)
	ray.set("ray_count", 6)
	ray.set("ray_half_angle", 0.35)
	var gem_element_color: Color = Block.COLORS.get(c.gem_type, Color.WHITE)
	ray.set("ray_color", Color(gem_element_color.r, gem_element_color.g, gem_element_color.b, 0.7))
	gem_icon.add_child(ray)
	_gem_icons[index] = gem_icon
	_gem_rays[index] = ray

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
	# 已經在發光中 → 跳過，避免重複播放彈跳動畫
	if _glow_tweens.has(index) and _glow_tweens[index].is_valid():
		return
	_stop_glow(index)
	var glow: ColorRect = _glow_panels[index]
	var tween := create_tween().set_loops()
	tween.tween_property(glow, "color:a", 0.35, 0.5).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(glow, "color:a", 0.0, 0.5).set_ease(Tween.EASE_IN_OUT)
	_glow_tweens[index] = tween
	_play_gem_skill_ready(index)


## 停止發光
func _stop_glow(index: int) -> void:
	if _glow_tweens.has(index):
		var old_tween: Tween = _glow_tweens[index]
		if old_tween.is_valid():
			old_tween.kill()
		_glow_tweens.erase(index)
	if _glow_panels.has(index):
		_glow_panels[index].color.a = 0.0
	_stop_gem_effects(index)


## 技能就緒：寶石圖示彈跳放大到 1.5x 並保持 + 啟動放射光芒
func _play_gem_skill_ready(index: int) -> void:
	if _gem_icons.has(index):
		var gem: Control = _gem_icons[index]
		var tw := create_tween()
		tw.tween_property(gem, "scale", Vector2(2.0, 2.0), 0.12) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(gem, "scale", Vector2(1.5, 1.5), 0.1) \
			.set_ease(Tween.EASE_IN_OUT)
	if _gem_rays.has(index):
		_gem_rays[index].visible = true


## 停止寶石技能就緒特效
func _stop_gem_effects(index: int) -> void:
	if _gem_icons.has(index):
		_gem_icons[index].scale = Vector2.ONE
	if _gem_rays.has(index):
		_gem_rays[index].visible = false


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


# ── 即時頭像調整面板（F9 切換）─────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		_toggle_debug_panel()


func _toggle_debug_panel() -> void:
	if _debug_panel != null:
		_debug_panel.queue_free()
		_debug_panel = null
		return
	_build_debug_panel()


func _build_debug_panel() -> void:
	var panel := PanelContainer.new()
	panel.z_index = 100
	# 加到 UILayer 的 CanvasLayer 上；若找不到就加到自身
	var ui_layer: Node = get_parent()
	if ui_layer is CanvasLayer:
		ui_layer.add_child(panel)
	else:
		add_child(panel)
	panel.offset_left = 4
	panel.offset_top = 4
	panel.offset_right = 274
	panel.offset_bottom = 600

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "Portrait Debug (F9 close)"
	title.add_theme_font_size_override("font_size", 16)
	vbox.add_child(title)

	for i in _char_data.size():
		var c := _char_data[i]
		var section := VBoxContainer.new()
		vbox.add_child(section)

		var name_lbl := Label.new()
		name_lbl.text = "── %s ──" % c.character_name
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		section.add_child(name_lbl)

		_add_slider(section, "Scale", c.portrait_scale, 0.1, 5.0, 0.05, func(v: float) -> void:
			c.portrait_scale = v
			_apply_portrait(i, c)
		)
		_add_slider(section, "Offset X", c.portrait_offset.x, -400, 200, 1.0, func(v: float) -> void:
			c.portrait_offset.x = v
			_apply_portrait(i, c)
		)
		_add_slider(section, "Offset Y", c.portrait_offset.y, -200, 200, 1.0, func(v: float) -> void:
			c.portrait_offset.y = v
			_apply_portrait(i, c)
		)

		# ── 戰鬥對話頭像（Battle Dialog Square）──
		var dlg_lbl := Label.new()
		dlg_lbl.text = "  Dialog Square"
		dlg_lbl.add_theme_font_size_override("font_size", 12)
		dlg_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		section.add_child(dlg_lbl)

		_add_slider(section, "Dlg Scale", c.dialog_square_scale, 0.1, 5.0, 0.05, func(v: float) -> void:
			c.dialog_square_scale = v
			_refresh_battle_dialog()
		)
		_add_slider(section, "Dlg X", c.dialog_square_offset.x, -400, 400, 1.0, func(v: float) -> void:
			c.dialog_square_offset.x = v
			_refresh_battle_dialog()
		)
		_add_slider(section, "Dlg Y", c.dialog_square_offset.y, -400, 400, 1.0, func(v: float) -> void:
			c.dialog_square_offset.y = v
			_refresh_battle_dialog()
		)

	# 列印按鈕：輸出所有角色數值到控制台
	var print_btn := Button.new()
	print_btn.text = "Print values to console"
	print_btn.pressed.connect(func() -> void:
		for ci in _char_data.size():
			var cd := _char_data[ci]
			print("%s  portrait_scale = %.2f  portrait_offset = Vector2(%.1f, %.1f)" % [
				cd.character_name, cd.portrait_scale, cd.portrait_offset.x, cd.portrait_offset.y])
			print("%s  dialog_square_scale = %.2f  dialog_square_offset = Vector2(%.1f, %.1f)" % [
				cd.character_name, cd.dialog_square_scale, cd.dialog_square_offset.x, cd.dialog_square_offset.y])
	)
	vbox.add_child(print_btn)

	_debug_panel = panel


func _add_slider(parent: Control, label_text: String, initial: float, min_val: float, max_val: float, step_val: float, on_changed: Callable) -> void:
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


func _apply_portrait(index: int, c: CharacterData) -> void:
	if not _portraits.has(index):
		return
	var portrait: TextureRect = _portraits[index]
	portrait.scale = Vector2(c.portrait_scale, c.portrait_scale)
	portrait.position = c.portrait_offset


## 在從 F9 面板調整 dialog_square_* 後立即讓眼前的戰鬥對話重新套用
func _refresh_battle_dialog() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	for child in root.find_children("*", "Control", true, false):
		if child.has_method("refresh_dialog_pose"):
			child.refresh_dialog_pose()
