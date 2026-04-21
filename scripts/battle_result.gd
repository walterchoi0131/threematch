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

	var card_row := HBoxContainer.new()
	card_row.alignment = BoxContainer.ALIGNMENT_CENTER
	card_row.add_theme_constant_override("separation", 12)
	_content.add_child(card_row)

	for c in _party:
		var card_data: Dictionary = _make_char_card(c)
		card_row.add_child(card_data.card)
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
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(110, 160)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.22, 1)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.35, 0.4, 0.55, 1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	card.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	# 頭像
	if c.portrait_texture:
		var portrait := TextureRect.new()
		portrait.texture = c.portrait_texture
		portrait.custom_minimum_size = Vector2(100, 80)
		portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(portrait)
	else:
		var portrait := ColorRect.new()
		portrait.custom_minimum_size = Vector2(100, 80)
		portrait.color = c.portrait_color
		vbox.add_child(portrait)

	# 名字
	var name_lbl := Label.new()
	name_lbl.text = c.character_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	# 等級標籤
	var lv_label := Label.new()
	lv_label.text = "Lv.%d" % c.level
	lv_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_label.add_theme_font_override("font", _font)
	lv_label.add_theme_font_size_override("font_size", 14)
	lv_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	lv_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(lv_label)

	# EXP 條背景
	var bar_bg := ColorRect.new()
	bar_bg.custom_minimum_size = Vector2(100, 8)
	bar_bg.color = Color(0.2, 0.2, 0.25, 1)
	vbox.add_child(bar_bg)

	# EXP 條填充
	var bar_fill := ColorRect.new()
	bar_fill.custom_minimum_size = Vector2(100, 8)
	bar_fill.color = Color(0.3, 0.75, 1.0)
	bar_fill.size = Vector2(100, 8)
	var exp_ratio: float = float(c.current_exp) / float(maxi(c.exp_to_next_level(), 1))
	bar_fill.scale.x = clampf(exp_ratio, 0.0, 1.0)
	bar_fill.position = Vector2.ZERO
	bar_bg.add_child(bar_fill)

	return {
		"card": card,
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
				tw.tween_callback(_play_level_up_pop.bind(card, current_anim_lv))
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
	# 卡片 bounce
	var tw := create_tween()
	tw.tween_property(card, "scale", Vector2(1.12, 1.12), 0.1) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(card, "scale", Vector2(1.0, 1.0), 0.1)

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
