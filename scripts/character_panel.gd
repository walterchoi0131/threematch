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

# 長按觸發（Flutter 風格：按住期間計時，達到閾值立即觸發，不等放手）
const LONG_PRESS_THRESHOLD: float = 0.5  # 秒
var _pressing_index: int = -1            # 目前按住的卡片索引（-1 表示無）
var _press_start_time: float = 0.0       # 按下時間
var _long_press_fired: bool = false      # 是否已觸發長按（防止 release 時重複觸發）
var _popup_layer: CanvasLayer = null     # 長按彈出的覆蓋面板
var _popup_dim: ColorRect = null         # 暗化背景（淡入淡出用）
var _popup_panel: Control = null         # 中央面板（淡入淡出用）


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

	# 放射光芒：插入為 gem_icon 的「前一個兄弟」— 與 gem_icon 同在 gem_layer，
	# 但繪製順序在它之前，因此會出現在元素圖示「下方」、卡片其它內容「上方」。
	var gem_icon: TextureRect = result.gem_icon
	var ray := Node2D.new()
	ray.set_script(load("res://scripts/ray_burst.gd"))
	ray.position = Vector2(14.0, 14.0)  # gem_size(28) * 0.5
	ray.z_index = 0
	ray.visible = false
	ray.set("outer_radius", 22.0)
	ray.set("ray_count", 6)
	ray.set("ray_half_angle", 0.35)
	var gem_element_color: Color = Block.COLORS.get(c.gem_type, Color.WHITE)
	ray.set("ray_color", Color(gem_element_color.r, gem_element_color.g, gem_element_color.b, 0.7))
	var gem_parent: Node = gem_icon.get_parent()
	if gem_parent != null:
		gem_parent.add_child(ray)
		gem_parent.move_child(ray, gem_icon.get_index())
		# 讓 ray 也座標到 gem_icon 中心位置
		ray.position = gem_icon.position + Vector2(14.0, 14.0)
	else:
		gem_icon.add_child(ray)
	_gem_icons[index] = gem_icon
	_gem_rays[index] = ray

	# 點擊處理
	panel.gui_input.connect(_on_card_gui_input.bind(index))

	return panel


## _process：Flutter 風格長按 — 按住期間每幀檢查，達閾值立即觸發（不等放手）。
func _process(_delta: float) -> void:
	if _pressing_index < 0 or _long_press_fired:
		return
	var held: float = (Time.get_ticks_msec() / 1000.0) - _press_start_time
	if held >= LONG_PRESS_THRESHOLD:
		_long_press_fired = true
		_show_char_popup(_pressing_index)


func _on_card_gui_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var mb := event as InputEventMouseButton
	if mb.pressed:
		# 如果彈出面板開著，任何按下都關閉它
		if _popup_layer != null:
			_close_char_popup()
			return
		_pressing_index = index
		_press_start_time = Time.get_ticks_msec() / 1000.0
		_long_press_fired = false
	else:
		var was_long := _long_press_fired
		_pressing_index = -1
		_long_press_fired = false
		if not was_long:
			active_skill_activated.emit(index)


## 長按觸發 → 彈出角色資訊浮窗（自製，非 character_detail）。
func _show_char_popup(index: int) -> void:
	if _popup_layer != null or index < 0 or index >= _char_data.size():
		return
	var c: CharacterData = _char_data[index]
	if c == null:
		return

	_popup_layer = CanvasLayer.new()
	_popup_layer.layer = 82
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	host.add_child(_popup_layer)

	# 暗化底層
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	# 點擊任意處關閉
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_close_char_popup()
	)
	_popup_layer.add_child(dim)

	# 中央圓角面板
	const PANEL_W: float = 480.0
	const IMG_SIZE: float = 300.0 * 4.0
	const HEADER_H: float = 130.0
	var panel := PanelContainer.new()
	panel.anchor_left   = 0.5
	panel.anchor_right  = 0.5
	panel.anchor_top    = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left   = -PANEL_W * 0.5
	panel.offset_right  =  PANEL_W * 0.5
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.clip_contents = true
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.12, 0.18, 0.97)
	bg.set_border_width_all(2)
	bg.border_color = Color(0.85, 0.72, 0.30)
	bg.set_corner_radius_all(14)
	bg.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", bg)
	_popup_layer.add_child(panel)
	_popup_dim = dim
	_popup_panel = panel

	# ── 主佈局 VBox ──
	var vbox_main := VBoxContainer.new()
	vbox_main.add_theme_constant_override("separation", 0)
	vbox_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox_main)

	# ── 頭部：角色圖 (絕對定位) + 名字/Lv ──
	var header := Control.new()
	header.custom_minimum_size = Vector2(PANEL_W, HEADER_H)
	header.clip_contents = true
	vbox_main.add_child(header)

	# 角色圖：絕對定位，右上角，4× 尺寸，向下溢出
	if c.portrait_texture != null:
		var portrait := TextureRect.new()
		portrait.texture = c.portrait_texture
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.anchor_left   = 0.0
		portrait.anchor_top    = 1.0
		portrait.anchor_right  = 0.0
		portrait.anchor_bottom = 1.0
		portrait.grow_horizontal = Control.GROW_DIRECTION_END
		portrait.grow_vertical   = Control.GROW_DIRECTION_BEGIN
		portrait.offset_left   = 0.0       + c.rectangular_offset.x
		portrait.offset_top    = -IMG_SIZE + c.rectangular_offset.y
		portrait.offset_right  = IMG_SIZE  + c.rectangular_offset.x
		portrait.offset_bottom = 0.0       + c.rectangular_offset.y
		portrait.pivot_offset  = Vector2(0, IMG_SIZE)
		portrait.scale = Vector2(c.rectangular_scale, c.rectangular_scale)
		header.add_child(portrait)

	# 名字 + Lv（右側對齊）
	var info_vbox := VBoxContainer.new()
	info_vbox.anchor_left   = 0.0
	info_vbox.anchor_top    = 0.0
	info_vbox.anchor_right  = 1.0
	info_vbox.anchor_bottom = 1.0
	info_vbox.offset_left   = 12.0
	info_vbox.offset_top    = 0.0
	info_vbox.offset_right  = -12.0
	info_vbox.offset_bottom = 0.0
	info_vbox.add_theme_constant_override("separation", 6)
	info_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	info_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(info_vbox)

	var name_lbl := Label.new()
	name_lbl.text = c.character_name
	name_lbl.add_theme_font_size_override("font_size", 24)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	name_lbl.add_theme_constant_override("outline_size", 4)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(name_lbl)

	var lv_row := HBoxContainer.new()
	lv_row.add_theme_constant_override("separation", 4)
	lv_row.alignment = BoxContainer.ALIGNMENT_END
	lv_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lv_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(lv_row)

	var elem_icon := TextureRect.new()
	elem_icon.texture = Block.GEM_TEXTURES.get(c.gem_type, null)
	elem_icon.custom_minimum_size = Vector2(13, 13)
	elem_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	elem_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv_row.add_child(elem_icon)

	var lv_lbl := Label.new()
	lv_lbl.text = "Lv. %d" % c.level
	lv_lbl.add_theme_font_size_override("font_size", 20)
	lv_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	lv_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lv_lbl.add_theme_constant_override("outline_size", 3)
	lv_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lv_row.add_child(lv_lbl)

	# ── 技能區 ──
	var skills_scroll := ScrollContainer.new()
	skills_scroll.custom_minimum_size = Vector2(PANEL_W, 280)
	skills_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox_main.add_child(skills_scroll)

	var skills_vbox := VBoxContainer.new()
	skills_vbox.add_theme_constant_override("separation", 8)
	skills_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var skills_margin := MarginContainer.new()
	skills_margin.add_theme_constant_override("margin_left", 16)
	skills_margin.add_theme_constant_override("margin_right", 16)
	skills_margin.add_theme_constant_override("margin_top", 12)
	skills_margin.add_theme_constant_override("margin_bottom", 12)
	skills_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills_scroll.add_child(skills_margin)
	skills_margin.add_child(skills_vbox)

	_add_popup_skill(skills_vbox, Locale.tr_ui("PASSIVE"), c.passive_skill_name, c.passive_skill_desc, null)
	_add_popup_skill(skills_vbox, Locale.tr_ui("ACTIVE"),  c.active_skill_name,  c.active_skill_desc,  null)

	var elem_color: Color = Block.COLORS.get(c.gem_type, Color(0.4, 0.6, 1.0))
	var base_gem_tex: Texture2D = Block.GEM_TEXTURES.get(c.gem_type, null)
	for sk: Dictionary in c.responding_skills:
		var sk_name: String = sk.get("name", "")
		var sk_desc: String = sk.get("desc", "")
		var fuse_label: String = str(sk.get("fuse_label", sk.get("threshold", "")))
		if sk_name == "":
			continue
		var upper_type: int = FuseTutorialCanvas.NAME_TO_UPPER.get(sk_name, -1)
		var upper_tex: Texture2D = Block.UPPER_GEM_TEXTURES.get(upper_type, null) if upper_type >= 0 else null
		var pattern: Array = FuseTutorialCanvas._blast_pattern_for(upper_type)
		var chain: Control = FuseTutorialCanvas._make_skill_chain(fuse_label, base_gem_tex, upper_tex, pattern, elem_color)
		_add_popup_skill(skills_vbox, Locale.tr_ui("RESPONDING"), sk_name, sk_desc, chain)

	# ── 淡入動畫 ──
	dim.modulate.a = 0.0
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.88, 0.88)
	# 等 layout 計算完再設 pivot 到中心
	panel.resized.connect(func() -> void:
		panel.pivot_offset = panel.size * 0.5
	, CONNECT_ONE_SHOT)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(dim,   "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.20) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _add_popup_skill(parent: VBoxContainer, tag: String, skill_name: String, desc: String, fuse_chain: Control) -> void:
	if skill_name == "":
		return
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 4)
	parent.add_child(entry)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	entry.add_child(row)

	var tag_lbl := Label.new()
	tag_lbl.text = "[%s]" % tag
	tag_lbl.add_theme_font_size_override("font_size", 13)
	tag_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	tag_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tag_lbl)

	var nm := Label.new()
	nm.text = skill_name
	nm.add_theme_font_size_override("font_size", 16)
	nm.add_theme_color_override("font_color", Color.WHITE)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)

	if desc != "":
		var dl := Label.new()
		dl.text = desc
		dl.add_theme_font_size_override("font_size", 13)
		dl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.82))
		dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		entry.add_child(dl)

	if fuse_chain != null:
		entry.add_child(fuse_chain)


func _close_char_popup() -> void:
	if _popup_layer == null:
		return
	# 將 layer 移交局部變數，防止淡出期間重複觸發
	var layer := _popup_layer
	_popup_layer = null
	_popup_dim = null
	_popup_panel = null
	_pressing_index = -1
	_long_press_fired = false
	# 淡出動畫，完成後釋放
	var tw := create_tween().set_parallel(true)
	for child in layer.get_children():
		tw.tween_property(child, "modulate:a", 0.0, 0.14).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(layer.queue_free)


## 顯示主動技能冷卻數字。turns_left=0 表示已就緒。
## CD 數字不再顯示在卡片上（僅保留就緒狀態的發光），故 cd_lbl 永遠隱藏。
func update_cooldown(index: int, turns_left: int) -> void:
	if not _cd_labels.has(index):
		return
	var cd_lbl: Label = _cd_labels[index]
	cd_lbl.visible = false
	if turns_left > 0:
		_stop_glow(index)


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
			_save_character(c)
		)
		_add_slider(section, "Offset X", c.portrait_offset.x, -400, 200, 1.0, func(v: float) -> void:
			c.portrait_offset.x = v
			_apply_portrait(i, c)
			_save_character(c)
		)
		_add_slider(section, "Offset Y", c.portrait_offset.y, -200, 200, 1.0, func(v: float) -> void:
			c.portrait_offset.y = v
			_apply_portrait(i, c)
			_save_character(c)
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
			_save_character(c)
		)
		_add_slider(section, "Dlg X", c.dialog_square_offset.x, -400, 400, 1.0, func(v: float) -> void:
			c.dialog_square_offset.x = v
			_refresh_battle_dialog()
			_save_character(c)
		)
		_add_slider(section, "Dlg Y", c.dialog_square_offset.y, -400, 400, 1.0, func(v: float) -> void:
			c.dialog_square_offset.y = v
			_refresh_battle_dialog()
			_save_character(c)
		)

		# ── 方形卡片頭像（Square Card —— 角色列表 / 準備畫面）──
		var sq_lbl := Label.new()
		sq_lbl.text = "  Square Card"
		sq_lbl.add_theme_font_size_override("font_size", 12)
		sq_lbl.add_theme_color_override("font_color", Color(0.85, 1.0, 0.7))
		section.add_child(sq_lbl)

		_add_slider(section, "Sq Scale", c.square_scale, 0.1, 5.0, 0.05, func(v: float) -> void:
			c.square_scale = v
			_save_character(c)
		)
		_add_slider(section, "Sq X", c.square_offset.x, -400, 400, 1.0, func(v: float) -> void:
			c.square_offset.x = v
			_save_character(c)
		)
		_add_slider(section, "Sq Y", c.square_offset.y, -400, 400, 1.0, func(v: float) -> void:
			c.square_offset.y = v
			_save_character(c)
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
			print("%s  square_scale = %.2f  square_offset = Vector2(%.1f, %.1f)" % [
				cd.character_name, cd.square_scale, cd.square_offset.x, cd.square_offset.y])
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


## 即時將 CharacterData 變更寫回對應的 .tres 檔
func _save_character(c: CharacterData) -> void:
	if c == null or c.resource_path == "":
		return
	var err: int = ResourceSaver.save(c, c.resource_path)
	if err != OK:
		push_warning("character_panel: failed to save %s (err=%d)" % [c.resource_path, err])


## 在從 F9 面板調整 dialog_square_* 後立即讓眼前的戰鬥對話重新套用
func _refresh_battle_dialog() -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	for child in root.find_children("*", "Control", true, false):
		if child.has_method("refresh_dialog_pose"):
			child.refresh_dialog_pose()
