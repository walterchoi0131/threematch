## BattleResult（戰鬥結算畫面）— 顯示金幣、戰利品、角色經驗值動畫。
## 三階段播放：Gold → Loot → EXP。點擊可跳過當前階段。
extends Control

const FONT_PATH := "res://assets/fonts/RussoOne-Regular.ttf"

# ── 階段列舉 ──
enum Phase { GOLD, LOOT, EXP, DONE }

var _font: Font
var _phase: Phase = Phase.GOLD
var _phase_animating: bool = false  # 動畫播放中
var _phase_tween: Tween = null      # 當前階段的 tween

# ── 資料 ──
var _loot: Dictionary = {}                    # 從 GameState 讀取
var _party: Array[CharacterData] = []         # 從 GameState 讀取
var _total_exp: int = 0                       # 從 GameState 讀取
var _gold_amount: int = 0                     # 本場金幣總量

# ── UI 節點 ──
var _content: VBoxContainer = null            # 主內容容器
var _gold_label: Label = null                 # 金幣數字標籤
var _loot_container: VBoxContainer = null     # 戰利品容器
var _loot_items: Array[Control] = []          # 戰利品項目節點
var _char_cards: Array[Dictionary] = []       # [{card, bar_fill, lv_label, exp_before, lv_before}]
var _tap_hint: Label = null                   # "Tap to continue" 提示

# ── 全螢幕點擊 ──
var _tap_button: Button = null


func _ready() -> void:
	_font = load(FONT_PATH)

	# 讀取結算資料
	_loot = GameState.last_battle_loot.duplicate()
	_party = GameState.last_battle_party.duplicate()
	_total_exp = GameState.last_battle_exp
	_gold_amount = _loot.get(ItemDefs.Type.GOLD, 0)

	_build_ui()
	_setup_tap_input()

	# 從黑幕 fade-in
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 1)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(black)
	var tw := create_tween()
	tw.tween_property(black, "color:a", 0.0, 0.4)
	tw.tween_callback(black.queue_free)

	# 啟動第一階段
	await get_tree().create_timer(0.5).timeout
	_start_phase(Phase.GOLD)


# ── UI 建構 ──────────────────────────────────────────────────

func _build_ui() -> void:
	# 標題
	var title := _make_styled_label(Locale.tr_ui("BATTLE_RESULT"), 36, Color(1.0, 0.9, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 40.0
	title.offset_bottom = 90.0
	add_child(title)

	# 主內容容器
	_content = VBoxContainer.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = 48.0
	_content.offset_top = 110.0
	_content.offset_right = -48.0
	_content.offset_bottom = -60.0
	_content.add_theme_constant_override("separation", 20)
	add_child(_content)

	_build_gold_section()
	_build_loot_section()
	_build_exp_section()
	_build_tap_hint()


func _build_gold_section() -> void:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	_content.add_child(hbox)

	var icon_lbl := _make_styled_label("💰", 32, Color(1, 0.85, 0.15))
	hbox.add_child(icon_lbl)

	_gold_label = _make_styled_label("0", 36, Color(1, 0.85, 0.15))
	hbox.add_child(_gold_label)


func _build_loot_section() -> void:
	_loot_container = VBoxContainer.new()
	_loot_container.add_theme_constant_override("separation", 8)
	_content.add_child(_loot_container)

	# 預建所有戰利品項目（初始隱藏）
	for type: ItemDefs.Type in _loot:
		if type == ItemDefs.Type.GOLD:
			continue
		var amount: int = _loot[type]
		var item_row := HBoxContainer.new()
		item_row.alignment = BoxContainer.ALIGNMENT_CENTER
		item_row.add_theme_constant_override("separation", 8)
		item_row.modulate.a = 0.0
		item_row.scale = Vector2(0.0, 0.0)
		item_row.pivot_offset = Vector2(60, 12)

		var color: Color = ItemDefs.get_color(type)
		var name_text: String = ItemDefs.get_display_name(type)

		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(16, 16)
		dot.color = color
		item_row.add_child(dot)

		var lbl := _make_styled_label("%s  ×%d" % [name_text, amount], 24, color)
		item_row.add_child(lbl)

		_loot_container.add_child(item_row)
		_loot_items.append(item_row)


func _build_exp_section() -> void:
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 12)
	_content.add_child(separator)

	var exp_title := _make_styled_label("%s  +%d" % [Locale.tr_ui("EXP"), _total_exp], 24, Color(0.6, 0.85, 1.0))
	exp_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(exp_title)

	var list_box := VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 10)
	_content.add_child(list_box)

	for c in _party:
		var card_data: Dictionary = _make_char_card(c)
		list_box.add_child(card_data.card)
		_char_cards.append(card_data)


func _build_tap_hint() -> void:
	_tap_hint = _make_styled_label(Locale.tr_ui("TAP_CONTINUE"), 18, Color(0.6, 0.6, 0.6, 0.0))
	_tap_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tap_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_tap_hint.offset_top = -50.0
	_tap_hint.offset_bottom = -20.0
	add_child(_tap_hint)


# ── 角色卡片 ──────────────────────────────────────────────────

func _make_char_card(c: CharacterData) -> Dictionary:
	# 一整列為 HBoxContainer：左側矩形頭像（絕對定位底-左，可上/右溢出），右側 名字 + Lv + EXP 條
	const ROW_HEIGHT := 96.0
	const PORTRAIT_W := 96.0
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT + 8)
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.10, 0.12, 0.18, 1)
	row_style.set_corner_radius_all(8)
	row_style.set_content_margin_all(6)
	row.add_theme_stylebox_override("panel", row_style)
	row.clip_contents = true

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	# 左側：佔位控件（寬度保留 PORTRAIT_W 讓右側文字不從最左邊開始）
	var placeholder := Control.new()
	placeholder.custom_minimum_size = Vector2(PORTRAIT_W, ROW_HEIGHT)
	placeholder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	placeholder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(placeholder)

	# 角色圖 overlay：plain Control，PanelContainer 會把它 fit 到全 row 大小，
	# 但不會干涉其子節點的 anchor/offset
	var portrait_overlay := Control.new()
	portrait_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_child(portrait_overlay)

	var portrait_ref: TextureRect = null
	if c.portrait_texture != null:
		const IMG_SIZE: float = 300.0 * 4.0     # 1200×1200
		var portrait := TextureRect.new()
		portrait.texture = c.portrait_texture
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 錨定到 overlay 的左下角
		portrait.anchor_left   = 0.0
		portrait.anchor_top    = 1.0
		portrait.anchor_right  = 0.0
		portrait.anchor_bottom = 1.0
		portrait.grow_horizontal = Control.GROW_DIRECTION_END
		portrait.grow_vertical   = Control.GROW_DIRECTION_BEGIN
		portrait.pivot_offset  = Vector2(0, IMG_SIZE)
		portrait.scale         = Vector2(c.rectangular_scale, c.rectangular_scale)
		portrait.offset_left   = 0.0       + c.rectangular_offset.x
		portrait.offset_top    = -IMG_SIZE + c.rectangular_offset.y
		portrait.offset_right  = IMG_SIZE  + c.rectangular_offset.x
		portrait.offset_bottom = 0.0       + c.rectangular_offset.y
		portrait_overlay.add_child(portrait)
		row.set_meta("_portrait", portrait)
		portrait_ref = portrait

	# 右側：名字 + Lv + EXP 條
	var right_box := VBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_box.add_theme_constant_override("separation", 6)
	hbox.add_child(right_box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	right_box.add_child(header)

	var name_lbl := Label.new()
	name_lbl.text = c.character_name
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	name_lbl.add_theme_constant_override("outline_size", 3)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(name_lbl)

	var lv_label := Label.new()
	lv_label.text = "Lv.%d" % c.level
	lv_label.add_theme_font_override("font", _font)
	lv_label.add_theme_font_size_override("font_size", 22)
	lv_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	lv_label.add_theme_color_override("font_outline_color", Color.BLACK)
	lv_label.add_theme_constant_override("outline_size", 3)
	lv_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(lv_label)

	# EXP 條背景
	var bar_bg := ColorRect.new()
	bar_bg.custom_minimum_size = Vector2(0, 14)
	bar_bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_bg.size_flags_vertical = Control.SIZE_SHRINK_END
	bar_bg.color = Color(0.2, 0.2, 0.25, 1)
	right_box.add_child(bar_bg)

	# EXP 條填充（以 scale.x 控制長度）
	var bar_fill := ColorRect.new()
	bar_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar_fill.color = Color(0.3, 0.75, 1.0)
	bar_fill.pivot_offset = Vector2.ZERO
	var exp_ratio: float = float(c.current_exp) / float(maxi(c.exp_to_next_level(), 1))
	bar_fill.scale.x = clampf(exp_ratio, 0.0, 1.0)
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar_bg.add_child(bar_fill)

	return {
		"card": row,
		"pop_target": row,
		"bar_fill": bar_fill,
		"bar_bg": bar_bg,
		"lv_label": lv_label,
		"name_label": name_lbl,
		"exp_before": c.current_exp,
		"lv_before": c.level,
		"char_data": c,
	}


# ── 階段控制 ──────────────────────────────────────────────────

func _setup_tap_input() -> void:
	_tap_button = Button.new()
	_tap_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tap_button.flat = true
	_tap_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_tap_button.pressed.connect(_on_tap)
	add_child(_tap_button)


func _on_tap() -> void:
	if _phase == Phase.DONE:
		_go_to_map()
		return

	if _phase_animating:
		# 跳過當前階段動畫
		_skip_current_phase()
	else:
		# 進入下一階段
		_advance_phase()


func _start_phase(phase: Phase) -> void:
	_phase = phase
	_phase_animating = true
	match phase:
		Phase.GOLD:
			_play_gold_phase()
		Phase.LOOT:
			_play_loot_phase()
		Phase.EXP:
			_play_exp_phase()
		Phase.DONE:
			_phase_animating = false
			_show_tap_hint()


func _advance_phase() -> void:
	var next: Phase
	match _phase:
		Phase.GOLD:
			next = Phase.LOOT
		Phase.LOOT:
			next = Phase.EXP
		Phase.EXP:
			next = Phase.DONE
		_:
			next = Phase.DONE
	_start_phase(next)


func _skip_current_phase() -> void:
	if _phase_tween != null and _phase_tween.is_valid():
		_phase_tween.kill()
		_phase_tween = null
	# EXP 階段使用多個獨立 tween
	for tw in _exp_tweens:
		if tw != null and tw.is_valid():
			tw.kill()
	_exp_tweens.clear()

	match _phase:
		Phase.GOLD:
			_gold_label.text = str(_gold_amount)
		Phase.LOOT:
			for item in _loot_items:
				item.modulate.a = 1.0
				item.scale = Vector2(1.0, 1.0)
		Phase.EXP:
			_finalize_exp_phase()

	_phase_animating = false
	_advance_phase()


# ── Gold 階段 ──────────────────────────────────────────────────

func _play_gold_phase() -> void:
	if _gold_amount == 0:
		_gold_label.text = "0"
		_phase_animating = false
		_advance_phase()
		return

	var counter := {"value": 0}
	_phase_tween = create_tween()
	_phase_tween.tween_method(func(val: float) -> void:
		counter.value = int(val)
		_gold_label.text = str(counter.value)
	, 0.0, float(_gold_amount), 1.5)
	_phase_tween.tween_callback(func() -> void:
		_phase_animating = false
		_advance_phase()
	)


# ── Loot 階段 ──────────────────────────────────────────────────

func _play_loot_phase() -> void:
	if _loot_items.is_empty():
		_phase_animating = false
		_advance_phase()
		return

	_phase_tween = create_tween()
	for i in _loot_items.size():
		var item: Control = _loot_items[i]
		_phase_tween.tween_property(item, "modulate:a", 1.0, 0.15)
		_phase_tween.parallel().tween_property(item, "scale", Vector2(1.2, 1.2), 0.15) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		_phase_tween.tween_property(item, "scale", Vector2(1.0, 1.0), 0.1)
		if i < _loot_items.size() - 1:
			_phase_tween.tween_interval(0.2)

	_phase_tween.tween_callback(func() -> void:
		_phase_animating = false
		_advance_phase()
	)


# ── EXP 階段（全員同時動畫） ──────────────────────────────────

var _exp_tweens: Array[Tween] = []  # 每位角色的獨立 tween
var _exp_done_count: int = 0        # 已完成動畫的角色數

func _play_exp_phase() -> void:
	if _party.is_empty() or _total_exp == 0:
		_phase_animating = false
		_advance_phase()
		return

	_exp_tweens.clear()
	_exp_done_count = 0
	var total_chars: int = _char_cards.size()

	for i in total_chars:
		var info: Dictionary = _char_cards[i]
		var c: CharacterData = info.char_data
		var bar_fill: ColorRect = info.bar_fill
		var lv_label: Label = info.lv_label
		var card: PanelContainer = info.card
		var pop_target: PanelContainer = info.get("pop_target", card)

		# 記錄動畫前狀態
		var start_lv: int = c.level

		# 實際加經驗
		var levels_gained: int = c.add_exp(_total_exp)
		var end_exp: int = c.current_exp
		var end_lv: int = c.level

		var tw := create_tween()
		_exp_tweens.append(tw)

		if levels_gained == 0:
			var end_ratio: float = float(end_exp) / float(maxi(c.exp_to_next_level(), 1))
			tw.tween_property(bar_fill, "scale:x", clampf(end_ratio, 0.0, 1.0), 1.0)
		else:
			# 填滿第一條
			tw.tween_property(bar_fill, "scale:x", 1.0, 0.4)

			for lv_idx in levels_gained:
				var current_anim_lv: int = start_lv + lv_idx + 1
				tw.tween_callback(func() -> void:
					bar_fill.scale.x = 0.0
					lv_label.text = "Lv.%d" % current_anim_lv
				)
				tw.tween_callback(_play_level_up_pop.bind(pop_target, current_anim_lv))
				if lv_idx < levels_gained - 1:
					tw.tween_property(bar_fill, "scale:x", 1.0, 0.3)

			var final_ratio: float = float(end_exp) / float(maxi(c.exp_to_next_level(), 1))
			tw.tween_property(bar_fill, "scale:x", clampf(final_ratio, 0.0, 1.0), 0.4)

		tw.tween_callback(func() -> void:
			_exp_done_count += 1
			if _exp_done_count >= total_chars:
				_phase_animating = false
				_advance_phase()
		)

	# 經驗已套用到 CharacterData，立即存檔以持久化等級/經驗
	GameState.save_game()


func _finalize_exp_phase() -> void:
	# 跳過時：確保所有角色都已加完經驗（可能已在 _play_exp_phase 中加過）
	for info in _char_cards:
		var c: CharacterData = info.char_data
		var bar_fill: ColorRect = info.bar_fill
		var lv_label: Label = info.lv_label
		var exp_ratio: float = float(c.current_exp) / float(maxi(c.exp_to_next_level(), 1))
		bar_fill.scale.x = clampf(exp_ratio, 0.0, 1.0)
		lv_label.text = "Lv.%d" % c.level


func _play_level_up_pop(card: PanelContainer, new_lv: int) -> void:
	# "Lv UP!" 浮動文字
	var pop := _make_styled_label(Locale.tr_ui("LV_UP"), 22, Color(1.0, 0.9, 0.2))
	pop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pop.position = Vector2(card.size.x * 0.5 - 40, -20)
	pop.modulate.a = 1.0
	card.add_child(pop)

	var pop_tw := create_tween().set_parallel(true)
	pop_tw.tween_property(pop, "position:y", pop.position.y - 40.0, 0.8)
	pop_tw.tween_property(pop, "modulate:a", 0.0, 0.8).set_delay(0.3)
	pop_tw.chain().tween_callback(pop.queue_free)


# ── 完成與離開 ──────────────────────────────────────────────────

func _show_tap_hint() -> void:
	var tw := create_tween().set_loops()
	tw.tween_property(_tap_hint, "modulate:a", 1.0, 0.6)
	tw.tween_property(_tap_hint, "modulate:a", 0.3, 0.6)


func _go_to_map() -> void:
	# 防重複觸發
	_tap_button.disabled = true
	# 漸隱勝利音樂（存於 GameState）
	GameState.fade_out_bgm(0.5)
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(black)
	var tw := create_tween()
	tw.tween_property(black, "color:a", 1.0, 0.4)
	tw.tween_callback(func() -> void:
		get_tree().change_scene_to_file("res://scenes/map.tscn")
	)


# ── F9 角色矩形偏移 Debug 面板 ────────────────────────────────

var _debug_panel: Control = null

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		_toggle_debug_panel()


func _toggle_debug_panel() -> void:
	if _debug_panel != null and is_instance_valid(_debug_panel):
		_debug_panel.queue_free()
		_debug_panel = null
		return
	var layer := CanvasLayer.new()
	layer.layer = 64
	add_child(layer)
	_debug_panel = _build_rect_debug_panel(layer)
	_debug_panel.tree_exited.connect(func() -> void:
		if is_instance_valid(layer):
			layer.queue_free()
	)


func _build_rect_debug_panel(parent: Node) -> Control:
	var panel := PanelContainer.new()
	panel.z_index = 100
	parent.add_child(panel)
	panel.offset_left = -300
	panel.offset_top = 4
	panel.offset_right = -4
	panel.offset_bottom = 700
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0

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
	title.text = "Rectangular Debug (F9 close)"
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)

	for info: Dictionary in _char_cards:
		var c: CharacterData = info.char_data
		var row_ctrl: Control = info.get("pop_target", null) as Control
		var section := VBoxContainer.new()
		vbox.add_child(section)

		var name_lbl := Label.new()
		name_lbl.text = "── %s ──" % c.character_name
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
		section.add_child(name_lbl)

		var cap: CharacterData = c
		var cap_row: Control = row_ctrl
		_add_dbg_slider(section, "Scale", cap.rectangular_scale, 0.1, 5.0, 0.05, func(v: float) -> void:
			cap.rectangular_scale = v
			_apply_portrait_transform(cap_row, cap)
			_save_char(cap)
		)
		_add_dbg_slider(section, "Off X", cap.rectangular_offset.x, -800, 800, 1.0, func(v: float) -> void:
			cap.rectangular_offset.x = v
			_apply_portrait_transform(cap_row, cap)
			_save_char(cap)
		)
		_add_dbg_slider(section, "Off Y", cap.rectangular_offset.y, -800, 800, 1.0, func(v: float) -> void:
			cap.rectangular_offset.y = v
			_apply_portrait_transform(cap_row, cap)
			_save_char(cap)
		)

	return panel


func _add_dbg_slider(parent: Control, label_text: String, initial: float, min_val: float, max_val: float, step_val: float, on_changed: Callable) -> void:
	var hbox := HBoxContainer.new()
	parent.add_child(hbox)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(50, 0)
	lbl.add_theme_font_size_override("font_size", 12)
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
	val_lbl.add_theme_font_size_override("font_size", 12)
	hbox.add_child(val_lbl)

	slider.value_changed.connect(func(v: float) -> void:
		val_lbl.text = "%.2f" % v
		on_changed.call(v)
	)


## 將 rectangular_scale/offset 重新套用到以 row.set_meta("_portrait") 儲存的 TextureRect。
static func _apply_portrait_transform(row: Control, c: CharacterData) -> void:
	if row == null or not row.has_meta("_portrait"):
		return
	var portrait: TextureRect = row.get_meta("_portrait") as TextureRect
	if portrait == null:
		return
	const IMG_SIZE: float = 300.0 * 4.0
	portrait.scale = Vector2(c.rectangular_scale, c.rectangular_scale)
	portrait.offset_left   = 0.0       + c.rectangular_offset.x
	portrait.offset_top    = -IMG_SIZE + c.rectangular_offset.y
	portrait.offset_right  = IMG_SIZE  + c.rectangular_offset.x
	portrait.offset_bottom = 0.0       + c.rectangular_offset.y


static func _save_char(c: CharacterData) -> void:
	if c == null or c.resource_path == "":
		return
	var err: int = ResourceSaver.save(c, c.resource_path)
	if err != OK:
		push_warning("battle_result: failed to save %s (err=%d)" % [c.resource_path, err])


# ── 工具函式 ──────────────────────────────────────────────────

func _make_styled_label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl
