## BattleResult（戰鬥結算畫面）— 顯示金幣、戰利品、角色經驗值動畫。
## 三階段播放：Gold → Loot → EXP。點擊可跳過當前階段。
extends Control

const FONT_PATH := "res://assets/fonts/game_ui_font.tres"
const _DialogBoxScene := preload("res://scenes/dialog_box.tscn")
const UpperPulseParticlesScript := preload("res://scripts/upper_gem_pulse_particles.gd")
const RayBurstScript := preload("res://scripts/ray_burst.gd")
const GoldCoin3DProxyScript := preload("res://scripts/gold_coin_3d_proxy.gd")
const BattleVfx3DLayerScript := preload("res://scripts/battle_vfx_3d_layer.gd")

const LOOT_CARD_SIZE := Vector2(112, 132)
const LOOT_ICON_FRAME_SIZE := 96.0
const LOOT_ICON_SIZE := 62
const DEV_REPORT_GEM_ORDER: Array[int] = [
	Block.Type.RED,
	Block.Type.BLUE,
	Block.Type.GREEN,
	Block.Type.LIGHT,
	Block.Type.DARK,
]

# ── 階段列舉 ──
enum Phase { GOLD, EXP, LOOT, DONE }

var _font: Font
var _phase: Phase = Phase.GOLD
var _phase_animating: bool = false  # 動畫播放中
var _phase_tween: Tween = null      # 當前階段的 tween

# ── 資料 ──
var _loot: Dictionary = {}                    # 從 GameState 讀取
var _party: Array[CharacterData] = []         # 從 GameState 讀取
var _total_exp: int = 0                       # 從 GameState 讀取
var _gold_amount: int = 0                     # 本場金幣總量
var _reward_characters: Array[CharacterData] = []
var _dev_report_rows: Array = []

# ── UI 節點 ──
var _content: VBoxContainer = null            # 主內容容器
var _gold_label: Label = null                 # 金幣數字標籤
var _loot_container: VBoxContainer = null     # 戰利品容器
var _loot_items: Array[Control] = []          # 戰利品項目節點
var _char_cards: Array[Dictionary] = []       # [{card, bar_fill, lv_label, exp_before, lv_before}]
var _tap_hint: Label = null                   # "Tap to continue" 提示

# ── 全螢幕點擊 ──
var _dev_pages_shell: Control = null
var _dev_result_page: Control = null
var _dev_report_page: Control = null
var _dev_result_tab_button: Button = null
var _dev_report_tab_button: Button = null
var _battle_vfx_3d_layer: BattleVfx3DLayer = null
var _tap_button: Button = null
var _dev_tab_tap_tracking: bool = false
var _dev_tab_tap_start: Vector2 = Vector2.ZERO
var _post_dialog_active: bool = false
var _result_exit_started: bool = false


func _ready() -> void:
	_font = load(FONT_PATH)

	# 讀取結算資料
	_loot = GameState.last_battle_loot.duplicate()
	_party = GameState.last_battle_party.duplicate()
	_total_exp = GameState.last_battle_exp
	_reward_characters = GameState.last_battle_reward_characters.duplicate()
	var dev_report_value: Variant = GameState.get_meta("last_battle_dev_turn_report", [])
	if dev_report_value is Array:
		var dev_report_array: Array = dev_report_value as Array
		_dev_report_rows = dev_report_array.duplicate(true)
	else:
		_dev_report_rows = []
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
	var show_dev_tabs: bool = GameState.dev_mode and not _dev_report_rows.is_empty()
	_content = VBoxContainer.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = 48.0
	_content.offset_top = 110.0
	_content.offset_right = -48.0
	_content.offset_bottom = -60.0
	_content.add_theme_constant_override("separation", 20)
	if show_dev_tabs:
		_dev_pages_shell = Control.new()
		_dev_pages_shell.set_anchors_preset(Control.PRESET_FULL_RECT)
		_dev_pages_shell.offset_left = 48.0
		_dev_pages_shell.offset_top = 110.0
		_dev_pages_shell.offset_right = -48.0
		_dev_pages_shell.offset_bottom = -60.0
		add_child(_dev_pages_shell)

		var tab_row := HBoxContainer.new()
		tab_row.set_anchors_preset(Control.PRESET_TOP_WIDE)
		tab_row.offset_left = 0.0
		tab_row.offset_top = 0.0
		tab_row.offset_right = 0.0
		tab_row.offset_bottom = 34.0
		tab_row.add_theme_constant_override("separation", 2)
		_dev_pages_shell.add_child(tab_row)

		_dev_result_tab_button = _make_dev_page_tab_button("結算")
		_dev_result_tab_button.pressed.connect(_set_dev_report_page.bind(0))
		tab_row.add_child(_dev_result_tab_button)

		_dev_report_tab_button = _make_dev_page_tab_button("報表")
		_dev_report_tab_button.pressed.connect(_set_dev_report_page.bind(1))
		tab_row.add_child(_dev_report_tab_button)

		var result_page := Control.new()
		result_page.name = "結算"
		_dev_result_page = result_page
		_dev_result_page.set_anchors_preset(Control.PRESET_FULL_RECT)
		_dev_result_page.offset_top = 34.0
		_dev_pages_shell.add_child(_dev_result_page)

		_content.offset_left = 0.0
		_content.offset_top = 10.0
		_content.offset_right = 0.0
		_content.offset_bottom = 0.0
		_dev_result_page.add_child(_content)
	else:
		_dev_pages_shell = null
		_dev_result_page = null
		_dev_report_page = null
		_dev_result_tab_button = null
		_dev_report_tab_button = null
		add_child(_content)

	_build_exp_section()
	_build_loot_section()
	if show_dev_tabs:
		_build_dev_report_page()
	_build_tap_hint()


func _make_dev_page_tab_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(86.0, 34.0)
	button.focus_mode = Control.FOCUS_NONE
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", Color(0.88, 0.92, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(1.0, 0.92, 0.42))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	return button


func _set_dev_report_page(page_index: int) -> void:
	var report_active: bool = page_index == 1
	if _dev_result_page != null:
		_dev_result_page.visible = not report_active
	if _dev_report_page != null:
		_dev_report_page.visible = report_active
	_style_dev_page_tab(_dev_result_tab_button, not report_active)
	_style_dev_page_tab(_dev_report_tab_button, report_active)


func _style_dev_page_tab(button: Button, active: bool) -> void:
	if button == null:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.12, 0.18, 0.96) if active else Color(0.05, 0.06, 0.10, 0.92)
	style.border_color = Color(0.52, 0.64, 0.95, 0.95) if active else Color(0.22, 0.28, 0.42, 0.85)
	style.set_border_width_all(1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	style.set_content_margin(SIDE_LEFT, 12.0)
	style.set_content_margin(SIDE_RIGHT, 12.0)
	style.set_content_margin(SIDE_TOP, 6.0)
	style.set_content_margin(SIDE_BOTTOM, 6.0)
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.add_theme_color_override("font_color", Color(1.0, 0.92, 0.42) if active else Color(0.82, 0.86, 0.96))


func _build_dev_report_page() -> void:
	if _dev_pages_shell == null:
		return
	var page := Control.new()
	page.name = "回合報表"
	_dev_report_page = page
	_dev_report_page.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dev_report_page.offset_top = 34.0
	_dev_pages_shell.add_child(_dev_report_page)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dev_report_page.add_child(scroll)

	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)

	var title := _make_styled_label("DEV 回合攻擊報表", 24, Color(1.0, 0.92, 0.42))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var summary := _make_styled_label(_dev_report_summary_text_v2(), 16, Color(0.82, 0.90, 1.0))
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(summary)

	for report in _dev_report_rows:
		box.add_child(_make_dev_report_turn_card_v2(report))
	_set_dev_report_page(0)


func _dev_report_summary_text_v2() -> String:
	var total_gems: int = 0
	var total_damage: int = 0
	for report in _dev_report_rows:
		total_gems += int(report.get("total_gems", 0))
		total_damage += int(report.get("total_damage", 0))
	return "Turns %d    Stage Gems %d    Total DMG %d" % [_dev_report_rows.size(), total_gems, total_damage]


func _make_dev_report_turn_card_v2(report: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.13, 0.92)
	style.border_color = Color(0.38, 0.48, 0.70, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	card.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)

	var header := _make_styled_label(
		"Turn %d / Round %d    Stage Gems %d    Total DMG %d" % [
			int(report.get("turn", 0)),
			int(report.get("round", 0)),
			int(report.get("total_gems", 0)),
			int(report.get("total_damage", 0)),
		],
		18,
		Color(1.0, 0.95, 0.74)
	)
	box.add_child(header)

	var gem_title := _make_styled_label("Stage Gems", 14, Color(0.78, 0.86, 1.0))
	box.add_child(gem_title)
	box.add_child(_make_dev_stage_gem_row(report.get("blasted_by_type", {})))

	var damage_title := _make_styled_label("Character DMG", 14, Color(0.78, 0.86, 1.0))
	box.add_child(damage_title)

	var character_flow := HFlowContainer.new()
	character_flow.alignment = FlowContainer.ALIGNMENT_CENTER
	character_flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	character_flow.add_theme_constant_override("h_separation", 10)
	character_flow.add_theme_constant_override("v_separation", 10)
	box.add_child(character_flow)

	var characters: Array = report.get("characters", []) as Array
	for char_report in characters:
		if not (char_report is Dictionary):
			continue
		var row: Dictionary = char_report as Dictionary
		character_flow.add_child(_make_dev_character_damage_card(row))
	return card


func _make_dev_stage_gem_row(value: Variant) -> Control:
	var outer := HBoxContainer.new()
	outer.alignment = BoxContainer.ALIGNMENT_CENTER
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_theme_constant_override("separation", 10)
	if not (value is Dictionary):
		outer.add_child(_make_styled_label("-", 16, Color(0.92, 0.94, 1.0)))
		return outer
	var blasted: Dictionary = value
	var ordered_keys: Array[int] = []
	for gem_type_value in DEV_REPORT_GEM_ORDER:
		var gem_type: int = int(gem_type_value)
		if int(blasted.get(gem_type, 0)) > 0:
			ordered_keys.append(gem_type)
	for key in blasted.keys():
		var gem_type: int = int(key)
		if int(blasted.get(key, 0)) > 0 and not ordered_keys.has(gem_type):
			ordered_keys.append(gem_type)
	if ordered_keys.is_empty():
		outer.add_child(_make_styled_label("0", 16, Color(0.92, 0.94, 1.0)))
		return outer
	for gem_type in ordered_keys:
		outer.add_child(_make_dev_gem_count_chip(gem_type, int(blasted.get(gem_type, 0))))
	return outer


func _make_dev_gem_count_chip(gem_type: int, count: int) -> Control:
	var chip := HBoxContainer.new()
	chip.custom_minimum_size = Vector2(76.0, 38.0)
	chip.alignment = BoxContainer.ALIGNMENT_CENTER
	chip.add_theme_constant_override("separation", 4)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(30.0, 30.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = Block.GEM_TEXTURES.get(gem_type, null)
	chip.add_child(icon)

	var count_label := _make_styled_label("%d" % count, 18, Color.WHITE)
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.add_child(count_label)
	return chip


func _make_dev_character_damage_card(row: Dictionary) -> Control:
	var wrap := VBoxContainer.new()
	wrap.custom_minimum_size = Vector2(118.0, 112.0)
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_theme_constant_override("separation", 4)

	var character: CharacterData = _dev_character_for_row(row)
	if character != null:
		var card_data: Dictionary = CharacterCard.make_battle(character)
		var panel: PanelContainer = card_data.get("panel", null) as PanelContainer
		if panel != null:
			panel.custom_minimum_size = Vector2(112.0, 76.0)
			panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			wrap.add_child(panel)
	else:
		var fallback := PanelContainer.new()
		fallback.custom_minimum_size = Vector2(112.0, 76.0)
		var fallback_style := StyleBoxFlat.new()
		fallback_style.bg_color = Color(0.11, 0.12, 0.16, 1.0)
		fallback_style.border_color = Color(0.35, 0.40, 0.55, 1.0)
		fallback_style.set_border_width_all(2)
		fallback_style.set_corner_radius_all(8)
		fallback.add_theme_stylebox_override("panel", fallback_style)
		var name_label := _make_styled_label(String(row.get("name", "?")), 13, Color.WHITE)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.add_child(name_label)
		wrap.add_child(fallback)

	var dmg_label := _make_styled_label("DMG %d" % int(row.get("damage", 0)), 15, Color(1.0, 0.88, 0.48))
	dmg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dmg_label.custom_minimum_size = Vector2(118.0, 24.0)
	wrap.add_child(dmg_label)
	return wrap


func _dev_character_for_row(row: Dictionary) -> CharacterData:
	var index: int = int(row.get("index", -1))
	if index >= 0 and index < _party.size():
		return _party[index]
	var row_name: String = String(row.get("name", ""))
	for character_value in _party:
		var character: CharacterData = character_value as CharacterData
		if character == null:
			continue
		if Locale.tr_ui(character.character_name) == row_name or character.character_name == row_name:
			return character
	return null


func _build_gold_section() -> void:
	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 12)
	_content.add_child(hbox)

	var icon_lbl := _make_styled_label("💰", 32, Color(1, 0.85, 0.15))
	hbox.add_child(icon_lbl)
	icon_lbl.visible = false
	var coin_icon := _make_gold_coin_3d_proxy(48, true)
	hbox.add_child(coin_icon)

	_gold_label = _make_styled_label("0", 36, Color(1, 0.85, 0.15))
	hbox.add_child(_gold_label)


func _build_loot_section() -> void:
	_loot_container = VBoxContainer.new()
	_loot_container.add_theme_constant_override("separation", 8)
	_content.add_child(_loot_container)
	var loot_title := _make_styled_label(Locale.tr_ui("LOOT"), 24, Color(0.95, 0.92, 0.82))
	loot_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loot_container.add_child(loot_title)

	var flow := HFlowContainer.new()
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 12)
	flow.add_theme_constant_override("v_separation", 12)
	_loot_container.add_child(flow)

	# 預建所有戰利品項目（初始隱藏）
	for type: ItemDefs.Type in _loot:
		var amount: int = _loot[type]
		if amount <= 0:
			continue
		var item_card := _make_loot_item_card(type, amount)
		flow.add_child(item_card)
		_loot_items.append(item_card)

	for character: CharacterData in _reward_characters:
		if character == null:
			continue
		var char_row := _make_reward_character_row(character)
		flow.add_child(char_row)
		_loot_items.append(char_row)


func _make_loot_item_card(type: ItemDefs.Type, amount: int) -> Control:
	var color: Color = ItemDefs.get_color(type)
	var card := VBoxContainer.new()
	card.custom_minimum_size = LOOT_CARD_SIZE
	card.modulate.a = 0.0
	card.scale = Vector2(0.0, 0.0)
	card.pivot_offset = LOOT_CARD_SIZE * 0.5
	card.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_theme_constant_override("separation", 5)

	var frame := Control.new()
	frame.custom_minimum_size = Vector2(LOOT_ICON_FRAME_SIZE, LOOT_ICON_FRAME_SIZE)
	frame.size = Vector2(LOOT_ICON_FRAME_SIZE, LOOT_ICON_FRAME_SIZE)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	frame.clip_contents = false

	var frame_bg := PanelContainer.new()
	frame_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame_bg.position = Vector2.ZERO
	frame_bg.size = Vector2(LOOT_ICON_FRAME_SIZE, LOOT_ICON_FRAME_SIZE)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.10, 0.84)
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(0)
	frame_bg.add_theme_stylebox_override("panel", style)
	frame.add_child(frame_bg)
	card.add_child(frame)

	var frame_overlay := Control.new()
	frame_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame_overlay.position = Vector2.ZERO
	frame_overlay.size = Vector2(LOOT_ICON_FRAME_SIZE, LOOT_ICON_FRAME_SIZE)
	frame_overlay.clip_contents = false
	frame.add_child(frame_overlay)

	var shining_color: Variant = ItemDefs.get_shining_color(type)
	if shining_color is Color:
		var ray := Node2D.new()
		ray.name = "LootResultShiningRayBurst"
		ray.position = Vector2(LOOT_ICON_FRAME_SIZE, LOOT_ICON_FRAME_SIZE) * 0.5
		ray.z_index = 0
		ray.scale = Vector2(0.9, 0.9)
		ray.set_script(RayBurstScript)
		ray.set("ray_color", shining_color)
		ray.set("outer_radius", LOOT_ICON_FRAME_SIZE * 0.48)
		frame_overlay.add_child(ray)

		var pulse_ring := Node2D.new()
		pulse_ring.name = "LootResultShiningPulseRing"
		pulse_ring.position = Vector2(LOOT_ICON_FRAME_SIZE, LOOT_ICON_FRAME_SIZE) * 0.5
		pulse_ring.z_index = 3
		pulse_ring.scale = Vector2(0.95, 0.95)
		pulse_ring.set_script(UpperPulseParticlesScript)
		pulse_ring.set("draw_particles", false)
		frame_overlay.add_child(pulse_ring)
		pulse_ring.call("configure", shining_color)

	var icon_center := Vector2(LOOT_ICON_FRAME_SIZE, LOOT_ICON_FRAME_SIZE) * 0.5
	if type == ItemDefs.Type.GOLD:
		var coin := _make_gold_coin_3d_proxy(LOOT_ICON_SIZE, true)
		coin.size = Vector2(LOOT_ICON_SIZE, LOOT_ICON_SIZE)
		coin.position = icon_center - Vector2(LOOT_ICON_SIZE, LOOT_ICON_SIZE) * 0.5
		coin.z_index = 4
		frame_overlay.add_child(coin)
	else:
		var image: Texture2D = ItemDefs.get_image(type)
		if image != null:
			var icon := TextureRect.new()
			var icon_size: float = float(LOOT_ICON_SIZE) * ItemDefs.get_size_multiplier(type)
			icon.texture = image
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.size = Vector2(icon_size, icon_size)
			icon.custom_minimum_size = icon.size
			icon.position = icon_center - icon.size * 0.5
			icon.z_index = 4
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frame_overlay.add_child(icon)
		else:
			var dot := ColorRect.new()
			dot.color = color
			dot.size = Vector2(34, 34)
			dot.position = icon_center - dot.size * 0.5
			dot.z_index = 4
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			frame_overlay.add_child(dot)

	if shining_color is Color:
		var dust := Node2D.new()
		dust.name = "LootResultShiningDust"
		dust.position = Vector2(LOOT_ICON_FRAME_SIZE, LOOT_ICON_FRAME_SIZE) * 0.5
		dust.z_index = 6
		dust.scale = Vector2(0.72, 0.72)
		dust.set_script(UpperPulseParticlesScript)
		dust.set("draw_rings", false)
		frame_overlay.add_child(dust)
		dust.call("configure", shining_color)

	var amount_lbl := _make_styled_label("%d" % amount, 17, Color.WHITE)
	amount_lbl.z_index = 8
	amount_lbl.custom_minimum_size = Vector2.ZERO
	amount_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	amount_lbl.position = Vector2(LOOT_ICON_FRAME_SIZE - 58.0, LOOT_ICON_FRAME_SIZE - 28.0)
	amount_lbl.size = Vector2(50.0, 24.0)
	frame_overlay.add_child(amount_lbl)

	var name_lbl := _make_styled_label(ItemDefs.get_display_name(type), 14, Color(0.9, 0.9, 0.95))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.custom_minimum_size = Vector2(LOOT_CARD_SIZE.x, 0)
	card.add_child(name_lbl)

	return card


func _get_battle_vfx_3d_layer() -> BattleVfx3DLayer:
	if is_instance_valid(_battle_vfx_3d_layer):
		return _battle_vfx_3d_layer
	_battle_vfx_3d_layer = BattleVfx3DLayerScript.new() as BattleVfx3DLayer
	_battle_vfx_3d_layer.name = "BattleResultVfx3DLayer"
	add_child(_battle_vfx_3d_layer)
	return _battle_vfx_3d_layer


func _make_gold_coin_3d_proxy(pixel_size: int, animate_spin: bool = true) -> Control:
	var layer := _get_battle_vfx_3d_layer()
	var proxy := GoldCoin3DProxyScript.new() as GoldCoin3DProxy
	if layer != null:
		proxy.configure(layer, pixel_size, animate_spin)
	else:
		proxy.custom_minimum_size = Vector2(pixel_size, pixel_size)
		proxy.size = Vector2(pixel_size, pixel_size)
		proxy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return proxy


func _make_reward_character_row(character: CharacterData) -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(140, 132)
	row.modulate.a = 0.0
	row.scale = Vector2(0.0, 0.0)
	row.pivot_offset = Vector2(70, 66)
	row.clip_contents = true

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.04, 0.86)
	style.border_color = Color(1.0, 0.86, 0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	row.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 5)
	row.add_child(box)

	if character.portrait_texture != null:
		var portrait := TextureRect.new()
		portrait.texture = character.portrait_texture
		portrait.custom_minimum_size = Vector2(74, 66)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(portrait)

	var label := _make_styled_label("New Character", 14, Color(1.0, 0.86, 0.25))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)

	var name_label := _make_styled_label(Locale.tr_ui(character.character_name), 16, Color.WHITE)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	return row


func _build_exp_section() -> void:
	var separator := HSeparator.new()
	separator.add_theme_constant_override("separation", 12)
	_content.add_child(separator)

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
	# 一整列：角色圖作為 overlay，文字/EXP 從整列 33% x 位置開始。
	const ROW_HEIGHT := 96.0
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_HEIGHT + 8)
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.10, 0.12, 0.18, 1)
	row_style.set_corner_radius_all(8)
	row_style.set_content_margin_all(6)
	row.add_theme_stylebox_override("panel", row_style)
	row.clip_contents = true

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

	var content_overlay := Control.new()
	content_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_child(content_overlay)

	# 右側：名字 + Lv + EXP 條，從整列 33% x 開始。
	var right_box := VBoxContainer.new()
	right_box.anchor_left = 0.33
	right_box.anchor_top = 0.0
	right_box.anchor_right = 1.0
	right_box.anchor_bottom = 1.0
	right_box.offset_left = 6.0
	right_box.offset_top = 8.0
	right_box.offset_right = -8.0
	right_box.offset_bottom = -8.0
	right_box.add_theme_constant_override("separation", 6)
	content_overlay.add_child(right_box)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	right_box.add_child(header)

	var name_lbl := Label.new()
	name_lbl.text = Locale.tr_ui(c.character_name)
	name_lbl.add_theme_font_override("font", _font)
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	name_lbl.add_theme_constant_override("outline_size", 3)
	name_lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(name_lbl)

	var exp_gain_label := Label.new()
	exp_gain_label.text = "+0EXP"
	exp_gain_label.add_theme_font_override("font", _font)
	exp_gain_label.add_theme_font_size_override("font_size", 16)
	exp_gain_label.add_theme_color_override("font_color", Color(0.62, 0.88, 1.0))
	exp_gain_label.add_theme_color_override("font_outline_color", Color.BLACK)
	exp_gain_label.add_theme_constant_override("outline_size", 3)
	exp_gain_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exp_gain_label.size_flags_vertical = Control.SIZE_SHRINK_END
	exp_gain_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	exp_gain_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(exp_gain_label)

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
		"exp_gain_label": exp_gain_label,
		"exp_before": c.current_exp,
		"lv_before": c.level,
		"char_data": c,
	}


# ── 階段控制 ──────────────────────────────────────────────────

func _setup_tap_input() -> void:
	_tap_button = Button.new()
	_tap_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tap_button.flat = true
	_tap_button.mouse_filter = Control.MOUSE_FILTER_IGNORE if _dev_pages_shell != null else Control.MOUSE_FILTER_STOP
	_tap_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_tap_button.pressed.connect(_on_tap)
	add_child(_tap_button)


func _input(event: InputEvent) -> void:
	if _post_dialog_active or _result_exit_started or _dev_pages_shell == null:
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		_handle_dev_tab_tap_event(mouse_event.pressed, mouse_event.position)
	elif event is InputEventScreenTouch:
		var touch_event: InputEventScreenTouch = event as InputEventScreenTouch
		_handle_dev_tab_tap_event(touch_event.pressed, touch_event.position)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		_toggle_debug_panel()


func _handle_dev_tab_tap_event(pressed: bool, position: Vector2) -> void:
	const TAP_MOVE_LIMIT := 14.0
	if pressed:
		_dev_tab_tap_tracking = not _dev_tab_tap_ignored(position)
		_dev_tab_tap_start = position
		return
	if not _dev_tab_tap_tracking:
		return
	_dev_tab_tap_tracking = false
	if _dev_tab_tap_start.distance_to(position) > TAP_MOVE_LIMIT:
		return
	_on_tap()
	get_viewport().set_input_as_handled()


func _dev_tab_tap_ignored(position: Vector2) -> bool:
	if _dev_pages_shell == null:
		return true
	var tabs_rect: Rect2 = _dev_pages_shell.get_global_rect()
	if not tabs_rect.has_point(position):
		return false
	const TAB_BAR_HEIGHT := 42.0
	return position.y <= tabs_rect.position.y + TAB_BAR_HEIGHT


func _on_tap() -> void:
	if _post_dialog_active or _result_exit_started:
		return
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
			next = Phase.EXP
		Phase.EXP:
			next = Phase.LOOT
		Phase.LOOT:
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
			if _gold_label != null:
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
	if _gold_label == null:
		_phase_animating = false
		_advance_phase()
		return
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
		var exp_gain_label: Label = info.get("exp_gain_label", null) as Label

		# 記錄動畫前狀態
		var start_lv: int = c.level

		# 實際加經驗
		var levels_gained: int = c.add_exp(_total_exp)
		var end_exp: int = c.current_exp
		var end_lv: int = c.level

		var tw := create_tween()
		_exp_tweens.append(tw)
		_animate_exp_gain_label(exp_gain_label, _total_exp)

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
					tw.tween_property(bar_fill, "scale:x", 1.0, 0.3).from(0.0)

			var final_ratio: float = float(end_exp) / float(maxi(c.exp_to_next_level(), 1))
			tw.tween_property(bar_fill, "scale:x", clampf(final_ratio, 0.0, 1.0), 0.4).from(0.0)

		tw.tween_callback(func() -> void:
			_exp_done_count += 1
			if _exp_done_count >= total_chars:
				_phase_animating = false
				_advance_phase()
		)

	# 經驗已套用到 CharacterData，立即存檔以持久化等級/經驗
	GameState.save_game()


func _animate_exp_gain_label(label: Label, target_exp: int) -> void:
	if label == null:
		return
	label.text = "+0EXP"
	if target_exp <= 0:
		return

	var tw := create_tween()
	_exp_tweens.append(tw)
	tw.tween_method(func(value: float) -> void:
		if is_instance_valid(label):
			label.text = "+%dEXP" % int(round(value))
	, 0.0, float(target_exp), 0.65)
	tw.tween_callback(func() -> void:
		if is_instance_valid(label):
			label.text = "+%dEXP" % target_exp
	)


func _finalize_exp_phase() -> void:
	# 跳過時：確保所有角色都已加完經驗（可能已在 _play_exp_phase 中加過）
	for info in _char_cards:
		var c: CharacterData = info.char_data
		var bar_fill: ColorRect = info.bar_fill
		var lv_label: Label = info.lv_label
		var exp_gain_label: Label = info.get("exp_gain_label", null) as Label
		var exp_ratio: float = float(c.current_exp) / float(maxi(c.exp_to_next_level(), 1))
		bar_fill.scale.x = clampf(exp_ratio, 0.0, 1.0)
		lv_label.text = "Lv.%d" % c.level
		if exp_gain_label != null:
			exp_gain_label.text = "+%dEXP" % _total_exp


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
	_result_exit_started = true
	if _tap_button != null:
		_tap_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var played_post_dialog: bool = await _play_post_dialog_after_result()
	# 漸隱勝利音樂（存於 GameState）
	GameState.fade_out_bgm(0.5)
	GameState.fade_to_scene("res://scenes/map.tscn", 0.05 if played_post_dialog else 0.4)


func _play_post_dialog_after_result() -> bool:
	var stage: StageData = GameState.selected_stage
	if stage == null or stage.post_dialog == null:
		return false
	if stage.post_dialog.lines.is_empty():
		return false
	GameState.fade_out_bgm(0.4)
	await _fade_out_before_post_dialog()
	var dialog_control: Control = _DialogBoxScene.instantiate() as Control
	if dialog_control == null:
		return false
	_post_dialog_active = true
	_dev_tab_tap_tracking = false
	dialog_control.set("auto_start", false)
	dialog_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog_control.z_index = 500
	add_child(dialog_control)
	dialog_control.call("start", stage.post_dialog, true, true, true)
	await dialog_control.tree_exited
	_post_dialog_active = false
	return true


func _fade_out_before_post_dialog() -> void:
	var black := ColorRect.new()
	black.color = Color(0, 0, 0, 0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	black.z_index = 400
	add_child(black)
	var tw := create_tween()
	tw.tween_property(black, "color:a", 1.0, 0.35)
	await tw.finished


# ── F9 角色矩形偏移 Debug 面板 ────────────────────────────────

var _debug_panel: Control = null

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
		name_lbl.text = "── %s ──" % Locale.tr_ui(c.character_name)
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
