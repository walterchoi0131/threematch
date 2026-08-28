## PrepareScreen（戰前準備畫面）— 選擇隊伍、預覽 Boss、檢視關卡寶石分佈。
## 以覆蓋層方式由 map.gd 開啟，關閉時 emit `closed` 訊號。
extends Control

signal closed

const FONT_PATH := "res://assets/fonts/game_ui_font.tres"
const CharacterSorter = preload("res://scripts/character_sorter.gd")
const RosterLayout = preload("res://scripts/roster_layout.gd")
const PREP_BATTLE_BG_SHADER := preload("res://shaders/prepare_battle_background_fade.gdshader")

var _font: Font
var _stage: StageData
var stage_override: StageData = null

# ── 選擇狀態 ──
var _selected_indices: Array[int] = []
var _card_panels: Array[PanelContainer] = []
var _card_styles: Array[Dictionary] = []  # [{normal, selected}]
var _card_lv_labels: Array[Label] = []    # 每張 roster 卡片的 Lv. 標籤（TYPE 排序時顯示）
var _card_selection_badges: Array[Control] = []
var _sort_mode: int = CharacterSorter.Mode.LEVEL
var _sort_ascending: bool = false
var _element_filter: int = CharacterSorter.ELEMENT_FILTER_ALL
var _roster_grid: Control = null

# ── UI 節點 ──
var _confirm_btn: Button = null
var _auto_team_btn: Button = null
var _team_summary: HBoxContainer = null   # 頂部隊伍縮圖列
var _team_summary_cards: Array[Control] = []
var _debug_panel: Control = null

# ── 卡片尺寸 ──
var _card_size: float = 100.0  # 單張方形卡边長 = vp.x / 7
const BATTLE_CHARACTER_ROW_MARGIN_X: float = 16.0
const BATTLE_CHARACTER_ROW_HEIGHT: float = 60.0
const PREP_BATTLE_BG_HEIGHT: float = 320.0
const PREP_BATTLE_BG_EDGE_FADE: float = 0.2
const PREP_BATTLE_BG_TOP_MASK_HEIGHT: float = 86.0
const PREP_BATTLE_BG_BOTTOM_MASK_HEIGHT: float = 132.0
const PREP_LOWER_SECTION_OFFSET_Y: float =0.0
const PREP_TOP_ROW_HEIGHT: float = 272.0


func _ready() -> void:
	_font = load(FONT_PATH)
	_stage = stage_override if stage_override != null else GameState.selected_stage
	if _stage == null:
		closed.emit()
		return
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		_toggle_debug_panel()


func _start_alpha_pulse(target: CanvasItem, low_alpha: float, high_alpha: float, duration: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var safe_duration: float = maxf(duration, 0.05)
	var tw: Tween = target.create_tween()
	tw.tween_property(target, "modulate:a", low_alpha, safe_duration) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(target, "modulate:a", high_alpha, safe_duration) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tw.finished.connect(func() -> void:
		if is_instance_valid(target):
			_start_alpha_pulse(target, low_alpha, high_alpha, safe_duration)
	)


func _toggle_debug_panel() -> void:
	if _debug_panel != null:
		_debug_panel.queue_free()
		_debug_panel = null
		return
	var chars: Array = []
	for c in GameState.owned_characters:
		chars.append(c)
	_debug_panel = SquareDebugPanel.build(self, chars, _apply_square_to_cards)


## 將 c.square_scale / square_offset 套用到目前畫面上的角色選擇格；隊伍縮圖維持戰鬥面板姿勢。
func _apply_square_to_cards(c: CharacterData) -> void:
	# 角色選擇格 — 由 owned_characters 索引對應
	var idx: int = GameState.owned_characters.find(c)
	if idx >= 0 and idx < _card_panels.size():
		_apply_square_pose_to_panel(_card_panels[idx], c)
	# 隊伍縮圖 — 任何顯示此角色的 slot 卡片，使用 battle panel pose
	for i in _selected_indices.size():
		if _selected_indices[i] == idx and i < _team_summary_cards.size():
			_apply_battle_pose_to_panel(_team_summary_cards[i] as Control, c)


func _apply_square_pose_to_panel(card: Control, c: CharacterData) -> void:
	if card == null or not card.has_meta("_portrait"):
		return
	var p: TextureRect = card.get_meta("_portrait") as TextureRect
	if p == null:
		return
	p.scale = Vector2(c.square_scale, c.square_scale)
	p.position = c.square_offset


func _apply_battle_pose_to_panel(card: Control, c: CharacterData) -> void:
	if card == null or not card.has_meta("_portrait"):
		return
	var p: TextureRect = card.get_meta("_portrait") as TextureRect
	if p == null:
		return
	p.scale = Vector2(c.portrait_scale, c.portrait_scale)
	p.position = c.portrait_offset


# ── UI 建構 ──────────────────────────────────────────────────

func _build_ui() -> void:
	# 計算卡片尺寸：1/7 viewport 寬度
	_card_size = ViewportUtils.get_size().x / 7.0
	_ensure_selection_slots()

	# 背景：黑色垂直漸層 —— 中間 90% 不透明、上下 80%
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	grad.colors = PackedColorArray([
		Color(0, 0, 0, 0.8),
		Color(0, 0, 0, 0.9),
		Color(0, 0, 0, 0.8),
	])
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0, 0)
	grad_tex.fill_to = Vector2(0, 1)
	grad_tex.width = 4
	grad_tex.height = 256
	bg.texture = grad_tex
	add_child(bg)

	_add_battle_background_preview()

	# 全螢幕垂直排列容器
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 16.0
	root.offset_top = 12.0
	root.offset_right = -16.0
	root.offset_bottom = -12.0
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	# ── 關卡標題（靠左）──
	var stage_title := _make_header_label(Locale.tr_ui(_stage.stage_name), Color(1.0, 0.9, 0.3))
	stage_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(stage_title)

	# ── 頂部：隊伍縮圖 | 元素分佈 | BOSS ──
	_build_top_row(root)

	var lower_section_spacer := Control.new()
	lower_section_spacer.custom_minimum_size = Vector2(0, PREP_LOWER_SECTION_OFFSET_Y)
	root.add_child(lower_section_spacer)

	# ── 角色選擇標題列：左「角色選擇」、右排序按鈕 ──
	var sel_header := HBoxContainer.new()
	sel_header.add_theme_constant_override("separation", 4)
	root.add_child(sel_header)

	var sel_label := _make_header_label(Locale.tr_ui("CHAR_SELECTION"), Color(0.85, 0.85, 0.9))
	sel_header.add_child(sel_label)

	_auto_team_btn = _make_auto_team_button()
	sel_header.add_child(_auto_team_btn)

	var sel_spacer := Control.new()
	sel_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_header.add_child(sel_spacer)

	var element_bar: HBoxContainer = CharacterSorter.make_element_filter_bar(_element_filter, _on_element_filter_changed, GameState.owned_characters, false, true)
	sel_header.add_child(element_bar)

	var sort_row: Button = CharacterSorter.make_sort_dropdown(_sort_mode, _on_sort_changed, _sort_ascending, true)
	sel_header.add_child(sort_row)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_build_roster_grid(scroll)

	# ── 底部按鈕列 ──
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 40)
	btn_row.custom_minimum_size = Vector2(0, 52)
	root.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = Locale.tr_ui("CANCEL")
	cancel_btn.custom_minimum_size = Vector2(140, 48)
	_apply_solid_button_style(cancel_btn, Color(0.35, 0.32, 0.40))
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = Locale.tr_ui("EMBARK")
	_confirm_btn.custom_minimum_size = Vector2(140, 48)
	_apply_solid_button_style(_confirm_btn, Color(0.85, 0.55, 0.20))
	_confirm_btn.pressed.connect(_on_confirm)
	btn_row.add_child(_confirm_btn)

	# 自動選取：關卡指定隊伍則使用之；否則預選上次出戰隊伍；都沒有則預選前 N 個角色
	if _stage.set_party.size() > 0:
		for c: CharacterData in _stage.set_party:
			var idx: int = GameState.owned_characters.find(c)
			if idx >= 0 and not _selection_has(idx):
				_toggle_select(idx)
		# 將未選中的角色卡片半透明顯示
		for i in _card_panels.size():
			if not _selection_has(i):
				_card_panels[i].modulate = Color(1, 1, 1, 0.35)
	else:
		var last_party: Array[CharacterData] = GameState.get_last_used_party()
		if last_party.size() > 0:
			for c: CharacterData in last_party:
				var idx: int = GameState.owned_characters.find(c)
				if idx >= 0 and not _selection_has(idx) and _selected_count() < GameState.MAX_PARTY_SIZE:
					_toggle_select(idx)
		else:
			var auto_count: int = mini(GameState.owned_characters.size(), GameState.MAX_PARTY_SIZE)
			for i in auto_count:
				_toggle_select(i)


# ── 頂部：隊伍縮圖 | 元素分佈 | BOSS ────────────────────

func _build_top_row(parent: VBoxContainer) -> void:
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(0, PREP_TOP_ROW_HEIGHT)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(stage)

	var team_host := HBoxContainer.new()
	team_host.anchor_left = 0.0
	team_host.anchor_top = 1.0
	team_host.anchor_right = 1.0
	team_host.anchor_bottom = 1.0
	team_host.offset_left = 0.0
	team_host.offset_top = -BATTLE_CHARACTER_ROW_HEIGHT
	team_host.offset_right = 0.0
	team_host.offset_bottom = 0.0
	stage.add_child(team_host)
	_build_team_summary(team_host)

	var pie_host := HBoxContainer.new()
	pie_host.anchor_left = 0.5
	pie_host.anchor_top = 0.0
	pie_host.anchor_right = 0.5
	pie_host.anchor_bottom = 0.0
	pie_host.offset_left = -100.0
	pie_host.offset_top = -104.0
	pie_host.offset_right = 100.0
	pie_host.offset_bottom = 0.0
	stage.add_child(pie_host)
	_build_pie_content(pie_host)

	var boss_host := HBoxContainer.new()
	boss_host.alignment = BoxContainer.ALIGNMENT_END
	boss_host.anchor_left = 1.0
	boss_host.anchor_top = 0.0
	boss_host.anchor_right = 1.0
	boss_host.anchor_bottom = 0.0
	boss_host.offset_left = -210.0
	boss_host.offset_top = -12.0
	boss_host.offset_right = -24.0
	boss_host.offset_bottom = 168.0
	stage.add_child(boss_host)
	_build_boss_content(boss_host)


func _add_battle_background_preview() -> void:
	if _stage == null:
		return
	var path: String = StageData.get_battle_background_path(_stage.area)
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		return

	var battle_bg := TextureRect.new()
	battle_bg.anchor_left = 0.0
	battle_bg.anchor_top = 0.0
	battle_bg.anchor_right = 1.0
	battle_bg.anchor_bottom = 0.0
	battle_bg.offset_left = 0.0
	battle_bg.offset_top = 0.0
	battle_bg.offset_right = 0.0
	battle_bg.offset_bottom = PREP_BATTLE_BG_HEIGHT
	battle_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	battle_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	battle_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	battle_bg.texture = texture

	var material := ShaderMaterial.new()
	material.shader = PREP_BATTLE_BG_SHADER
	material.set_shader_parameter("fade_start", 1.0 - PREP_BATTLE_BG_EDGE_FADE)
	material.set_shader_parameter("edge_fade", PREP_BATTLE_BG_EDGE_FADE)
	battle_bg.material = material
	add_child(battle_bg)
	_add_battle_background_edge_masks()


func _add_battle_background_edge_masks() -> void:
	_add_battle_background_mask(
		0.0,
		PREP_BATTLE_BG_TOP_MASK_HEIGHT,
		_make_vertical_gradient_texture(Color(0, 0, 0, 0.82), Color(0, 0, 0, 0.0)))
	_add_battle_background_mask(
		PREP_BATTLE_BG_HEIGHT - PREP_BATTLE_BG_BOTTOM_MASK_HEIGHT,
		PREP_BATTLE_BG_HEIGHT,
		_make_vertical_gradient_texture(Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.92)))


func _add_battle_background_mask(top: float, bottom: float, texture: Texture2D) -> void:
	var mask := TextureRect.new()
	mask.anchor_left = 0.0
	mask.anchor_top = 0.0
	mask.anchor_right = 1.0
	mask.anchor_bottom = 0.0
	mask.offset_left = 0.0
	mask.offset_top = top
	mask.offset_right = 0.0
	mask.offset_bottom = bottom
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mask.stretch_mode = TextureRect.STRETCH_SCALE
	mask.texture = texture
	add_child(mask)


func _make_vertical_gradient_texture(top_color: Color, bottom_color: Color) -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([top_color, bottom_color])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_LINEAR
	texture.fill_from = Vector2(0.0, 0.0)
	texture.fill_to = Vector2(0.0, 1.0)
	texture.width = 4
	texture.height = 128
	return texture


func _make_top_column() -> HBoxContainer:
	var col := HBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_stretch_ratio = 1.0
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return col


func _make_auto_team_button() -> Button:
	var button := Button.new()
	button.text = Locale.tr_ui("AUTO_TEAM")
	button.custom_minimum_size = Vector2(74, 28)
	button.disabled = _is_party_locked()
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", _font)
	button.add_theme_font_size_override("font_size", 12)
	_apply_compact_button_style(button, Color(0.35, 0.42, 0.55))
	button.pressed.connect(_on_auto_team_pressed)
	return button


func _apply_compact_button_style(btn: Button, base_color: Color) -> void:
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		var c: Color = base_color
		if state == "hover":
			c = base_color.lightened(0.10)
		elif state == "pressed":
			c = base_color.darkened(0.15)
		elif state == "disabled":
			c = base_color.darkened(0.30)
		c.a = 1.0
		sb.bg_color = c
		sb.set_corner_radius_all(5)
		sb.set_border_width_all(1)
		sb.border_color = base_color.darkened(0.4)
		sb.content_margin_left = 2.0
		sb.content_margin_right = 2.0
		sb.content_margin_top = 1.0
		sb.content_margin_bottom = 1.0
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)


# ── 左欄：我的隊伍縮圖 ───────────────────────────────────────

func _build_team_summary(parent: HBoxContainer) -> void:
	_team_summary = HBoxContainer.new()
	_team_summary.add_theme_constant_override("separation", _battle_character_panel_separation())
	_team_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_team_summary.alignment = BoxContainer.ALIGNMENT_BEGIN
	parent.add_child(_team_summary)

	_refresh_team_summary()


func _battle_character_panel_separation() -> int:
	return get_theme_constant("separation", "HBoxContainer")


func _battle_character_panel_card_size() -> Vector2:
	var total_width: float = ViewportUtils.get_size().x - BATTLE_CHARACTER_ROW_MARGIN_X * 2.0
	var separation_total: float = float(maxi(GameState.MAX_PARTY_SIZE - 1, 0) * _battle_character_panel_separation())
	var card_width: float = (total_width - separation_total) / float(GameState.MAX_PARTY_SIZE)
	return Vector2(card_width, BATTLE_CHARACTER_ROW_HEIGHT)


func _refresh_team_summary() -> void:
	if _team_summary == null:
		return
	for child in _team_summary.get_children():
		child.queue_free()
	_team_summary_cards.clear()

	var battle_card_size: Vector2 = _battle_character_panel_card_size()
	for i in GameState.MAX_PARTY_SIZE:
		var selected_index: int = _selected_indices[i] if i < _selected_indices.size() else -1
		if selected_index >= 0 and selected_index < GameState.owned_characters.size():
			var c: CharacterData = GameState.owned_characters[selected_index]
			var card_data: Dictionary = CharacterCard.make_battle(c)
			var card: PanelContainer = card_data.panel
			card.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
			card.custom_minimum_size = battle_card_size
			card.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			card.mouse_filter = Control.MOUSE_FILTER_STOP
			card.gui_input.connect(_on_team_card_input.bind(selected_index))
			_team_summary.add_child(card)
			_team_summary_cards.append(card)
		else:
			var locked_empty: bool = _is_locked_empty_party_slot(i)
			var slot_label: String = "X" if locked_empty else "+"
			var slot: PanelContainer = _make_empty_summary_slot(battle_card_size.x, slot_label, locked_empty)
			slot.custom_minimum_size = battle_card_size
			_team_summary.add_child(slot)
			var blink_label: Label = slot.get_node_or_null("Label") as Label
			if blink_label != null and not locked_empty:
				_start_alpha_pulse(blink_label, 0.25, 1.0, 0.6)
			_team_summary_cards.append(slot)

	if _confirm_btn:
		_confirm_btn.disabled = _selected_count() == 0


func _is_locked_empty_party_slot(slot_index: int) -> bool:
	return _is_party_locked() and _stage != null and slot_index >= _stage.set_party.size()


## 建立隊伍欄列左側純頭像：無邊框，套用 battle panel pose，固定方形大小。
func _make_team_portrait(c: CharacterData, s: float) -> Control:
	var clip := Control.new()
	clip.custom_minimum_size = Vector2(s, s)
	clip.size_flags_horizontal = 0
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_STOP
	if c.portrait_texture:
		var portrait := TextureRect.new()
		portrait.texture = c.portrait_texture
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.custom_minimum_size = Vector2(300, 300)
		portrait.size = Vector2(300, 300)
		portrait.pivot_offset = Vector2.ZERO
		portrait.scale = Vector2(c.portrait_scale, c.portrait_scale)
		portrait.position = c.portrait_offset
		clip.add_child(portrait)
		clip.set_meta("_portrait", portrait)
		clip.set_meta("_is_battle_panel_pose", true)
	else:
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.color = c.portrait_color
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(rect)
	return clip


## 為隊伍欄列產生「左色 → 右透明」的水平漸層 StyleBox。
func _make_team_row_style(elem: Color) -> StyleBoxTexture:
	var grad := Gradient.new()
	grad.set_color(0, Color(elem.r, elem.g, elem.b, 0.85))
	grad.set_color(1, Color(elem.r, elem.g, elem.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 256
	tex.height = 8
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.set_content_margin_all(4)
	return sb


func _make_empty_team_row_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.12, 0.4)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(4)
	return sb


func _make_empty_summary_slot(s: float, label_text: String = "+", locked: bool = false) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = 0
	panel.custom_minimum_size = Vector2(s, s)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.78 if locked else 0.6)
	style.set_border_width_all(2)
	style.border_color = Color(0.45, 0.25, 0.28, 0.75) if locked else Color(0.25, 0.25, 0.35, 0.5)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.name = "Label"
	lbl.text = label_text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _font != null:
		lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.45, 0.45) if locked else Color(0.5, 0.5, 0.6))
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)
	return panel


func _on_team_card_input(event: InputEvent, idx_in_owned: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _is_party_locked():
		return
	if _selection_has(idx_in_owned):
		_toggle_select(idx_in_owned)


func _build_boss_content(parent: HBoxContainer) -> void:
	var boss: EnemyData = _get_stage_boss()
	if boss == null:
		return

	var boss_box := Control.new()
	boss_box.custom_minimum_size = Vector2(190, 180)
	boss_box.size_flags_horizontal = Control.SIZE_SHRINK_END
	boss_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	boss_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(boss_box)

	var backdrop := TextureRect.new()
	backdrop.anchor_left = 0.5
	backdrop.anchor_top = 0.5
	backdrop.anchor_right = 0.5
	backdrop.anchor_bottom = 0.5
	backdrop.offset_left = -108.0
	backdrop.offset_top = -104.0
	backdrop.offset_right = 108.0
	backdrop.offset_bottom = 104.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.texture = _make_boss_radial_texture()
	boss_box.add_child(backdrop)

	var image := TextureRect.new()
	image.anchor_left = 0.5
	image.anchor_top = 0.5
	image.anchor_right = 0.5
	image.anchor_bottom = 0.5
	image.offset_left = -80.0
	image.offset_top = -80.0
	image.offset_right = 80.0
	image.offset_bottom = 80.0
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if boss.portrait_texture:
		image.texture = boss.portrait_texture
	boss_box.add_child(image)


func _make_boss_radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	gradient.colors = PackedColorArray([
		Color(0, 0, 0, 0.88),
		Color(0, 0, 0, 0.52),
		Color(0, 0, 0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	return texture


func _make_pie_radial_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.58, 1.0])
	gradient.colors = PackedColorArray([
		Color(0, 0, 0, 0.76),
		Color(0, 0, 0, 0.46),
		Color(0, 0, 0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 256
	texture.height = 256
	return texture


func _build_pie_content(parent: HBoxContainer) -> void:
	var distribution: Dictionary = _stage.get_element_distribution()
	var allowed: Array = []
	var total_weight: int = 0
	var ordered_types: Array[int] = [
		Block.Type.RED,
		Block.Type.BLUE,
		Block.Type.GREEN,
		Block.Type.LIGHT,
		Block.Type.DARK,
	]
	for type_value: int in ordered_types:
		var normalized: int = int(type_value)
		var weight: int = int(distribution.get(normalized, 0))
		if weight <= 0:
			continue
		allowed.append(normalized)
		total_weight += weight
	for type_variant in distribution.keys():
		var normalized: int = int(type_variant)
		if allowed.has(normalized):
			continue
		var weight: int = int(distribution.get(normalized, 0))
		if weight <= 0:
			continue
		allowed.append(normalized)
		total_weight += weight
	var count: int = allowed.size()
	if count == 0 or total_weight <= 0:
		return

	const PIE_SIZE: float = 112.0
	const ICON_SIZE: float = 44.8  # 元素圖示

	# 用 CenterContainer 將圓餅在 pie_col 內置中
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(center)

	var pie_container := _RotatingPieContainer.new()
	pie_container.custom_minimum_size = Vector2(PIE_SIZE, PIE_SIZE)
	pie_container.size = Vector2(PIE_SIZE, PIE_SIZE)
	pie_container.clip_contents = false
	pie_container.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(pie_container)

	var backdrop_size: float = PIE_SIZE * 1.75
	var backdrop := TextureRect.new()
	backdrop.texture = _make_pie_radial_texture()
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.size = Vector2(backdrop_size, backdrop_size)
	backdrop.position = Vector2(PIE_SIZE * 0.5, PIE_SIZE * 0.5) - backdrop.size * 0.5
	pie_container.add_child(backdrop)

	# 背景切片
	var slices: Array[Dictionary] = []
	for t in allowed:
		var ratio: float = float(int(distribution.get(int(t), 0))) / float(total_weight)
		var color: Color = Block.COLORS.get(t, Color.GRAY)
		color.a = 1.0
		slices.append({"ratio": ratio, "color": color})

	var pie := _PieDrawer.new()
	pie.slices = slices
	pie.set_anchors_preset(Control.PRESET_FULL_RECT)
	pie_container.add_child(pie)

	# 每個切片：圖示可溢出圓餅邊界顯示
	var pie_center: Vector2 = Vector2(PIE_SIZE * 0.5, PIE_SIZE * 0.5)
	var pie_radius: float = PIE_SIZE * 0.45
	var icon_radius: float = pie_radius * 0.55 + 28.0
	var start_angle: float = -PI * 0.5
	for i in count:
		var ratio: float = float(int(distribution.get(int(allowed[i]), 0))) / float(total_weight)
		var sweep: float = ratio * TAU
		var mid_angle: float = start_angle + sweep * 0.5
		var icon_pos: Vector2 = pie_center + Vector2(cos(mid_angle), sin(mid_angle)) * icon_radius
		var t: int = allowed[i]
		var gem_tex: Texture2D = Block.GEM_TEXTURES.get(t)
		if gem_tex:
			var icon := _CounterRotatingPieIcon.new()
			icon.texture = gem_tex
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
			icon.size = Vector2(ICON_SIZE, ICON_SIZE)
			icon.pivot_offset = icon.size * 0.5
			icon.position = icon_pos - Vector2(ICON_SIZE * 0.5, ICON_SIZE * 0.5)
			icon.modulate = Color.WHITE
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pie_container.add_child(icon)
		start_angle += sweep


# ── 已選角色欄位 ──────────────────────────────────────────────
# 隊伍選取現以頂部隊伍縮圖取代，不再需要底部 slot section。


# ── 角色選擇網格 ──────────────────────────────────────────────

func _build_roster_grid(parent: ScrollContainer) -> void:
	var host := VBoxContainer.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(host)
	_roster_grid = host

	_card_panels.clear()
	_card_styles.clear()
	_card_lv_labels.clear()
	_card_selection_badges.clear()

	var fixed_set: Dictionary = {}
	if _is_party_locked():
		for c: CharacterData in _stage.set_party:
			fixed_set[c] = true

	for i in GameState.owned_characters.size():
		var c: CharacterData = GameState.owned_characters[i]
		var data: Dictionary = CharacterCard.make_square_selectable(c)
		var panel: PanelContainer = data.panel
		panel.size_flags_horizontal = 0
		panel.custom_minimum_size = Vector2(_card_size, _card_size)
		panel.gui_input.connect(_on_roster_card_input.bind(i))
		_card_panels.append(panel)
		_card_styles.append({
			"normal": data.style_normal,
			"selected": data.style_selected,
		})
		_card_lv_labels.append(data.get("lv_label"))
		if fixed_set.has(c):
			_add_fixed_overlay(panel)
			panel.set_meta("_has_fixed_overlay", true)
		var badge: Control = _add_selection_badge(panel)
		_card_selection_badges.append(badge)

	_update_lv_labels_visibility()
	_apply_sort()


func _update_lv_labels_visibility() -> void:
	var show: bool = _sort_mode == CharacterSorter.Mode.TYPE
	for lbl: Label in _card_lv_labels:
		if lbl != null:
			lbl.visible = show


## 套用「實心」按鈕樣式（不透明背景）— 確保按鈕在覆蓋層上仍清晰可見。
func _apply_solid_button_style(btn: Button, base_color: Color) -> void:
	for state: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		var c: Color = base_color
		if state == "hover":
			c = base_color.lightened(0.10)
		elif state == "pressed":
			c = base_color.darkened(0.15)
		elif state == "disabled":
			c = base_color.darkened(0.30)
		c.a = 1.0
		sb.bg_color = c
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(2)
		sb.border_color = base_color.darkened(0.4)
		sb.set_content_margin_all(8)
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)


func _add_fixed_overlay(panel: PanelContainer) -> void:
	_add_state_overlay(panel, Locale.tr_ui("FIXED"))


func _add_state_overlay(panel: PanelContainer, text: String) -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(overlay)

	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 仿粗體：用 FontVariation 增加筆畫粗細
	var bold_font := FontVariation.new()
	bold_font.base_font = _font
	bold_font.variation_embolden = 1.0
	lbl.add_theme_font_override("font", bold_font)
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(lbl)

	_start_alpha_pulse(lbl, 0.35, 1.0, 0.7)
	return overlay


func _on_sort_changed(mode: int, ascending: bool) -> void:
	_sort_mode = mode
	_sort_ascending = ascending
	_update_lv_labels_visibility()
	_apply_sort()


func _on_element_filter_changed(element_filter: int) -> void:
	_element_filter = element_filter
	_apply_sort()


func _apply_sort() -> void:
	if _roster_grid == null:
		return
	var fixed_set: Dictionary = {}
	if _is_party_locked():
		for c: CharacterData in _stage.set_party:
			fixed_set[c] = true
	var entries: Array = []
	for i in GameState.owned_characters.size():
		var ch: CharacterData = GameState.owned_characters[i]
		entries.append({
			"i": i,
			"c": ch,
			"card": _card_panels[i],
			"is_fixed": fixed_set.has(ch),
		})
	RosterLayout.apply(_roster_grid, entries, _sort_mode, 6, _sort_ascending, _element_filter)


func _on_auto_team_pressed() -> void:
	if _is_party_locked():
		return
	var indices: Array[int] = _build_auto_team_indices()
	if indices.is_empty():
		return
	_replace_selected_indices(indices)


func _build_auto_team_indices() -> Array[int]:
	var candidates: Array[Dictionary] = []
	var allowed: Array = _stage.allowed_types if _stage != null else []
	for raw_type in allowed:
		var gem_type: Block.Type = raw_type as Block.Type
		var best_index: int = -1
		var best_level: int = -1
		for i in GameState.owned_characters.size():
			var ch: CharacterData = GameState.owned_characters[i]
			if ch == null or ch.gem_type != gem_type:
				continue
			if ch.level > best_level:
				best_index = i
				best_level = ch.level
		if best_index >= 0:
			candidates.append({
				"index": best_index,
				"level": best_level,
				"type": gem_type,
			})

	if candidates.size() > GameState.MAX_PARTY_SIZE:
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var level_a: int = int(a["level"])
			var level_b: int = int(b["level"])
			if level_a == level_b:
				return int(a["index"]) < int(b["index"])
			return level_a > level_b
		)

	var chosen: Array[int] = []
	var used: Dictionary = {}
	for entry: Dictionary in candidates:
		if chosen.size() >= GameState.MAX_PARTY_SIZE:
			break
		var index: int = int(entry["index"])
		if used.has(index):
			continue
		chosen.append(index)
		used[index] = true

	if chosen.size() < GameState.MAX_PARTY_SIZE:
		var fillers: Array[Dictionary] = []
		for i in GameState.owned_characters.size():
			if used.has(i):
				continue
			var ch: CharacterData = GameState.owned_characters[i]
			if ch == null:
				continue
			fillers.append({"index": i, "level": ch.level})
		fillers.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var level_a: int = int(a["level"])
			var level_b: int = int(b["level"])
			if level_a == level_b:
				return int(a["index"]) < int(b["index"])
			return level_a > level_b
		)
		for entry: Dictionary in fillers:
			if chosen.size() >= GameState.MAX_PARTY_SIZE:
				break
			var index: int = int(entry["index"])
			chosen.append(index)
			used[index] = true

	return chosen


func _replace_selected_indices(indices: Array[int]) -> void:
	var previous: Array[int] = _selected_party_indices()
	for index: int in previous:
		_set_roster_card_selected(index, false)
	_ensure_selection_slots()
	for slot in GameState.MAX_PARTY_SIZE:
		_selected_indices[slot] = -1
	var next_slot: int = 0
	for index: int in indices:
		if index < 0 or index >= GameState.owned_characters.size():
			continue
		if _selection_has(index):
			continue
		if next_slot >= GameState.MAX_PARTY_SIZE:
			break
		_selected_indices[next_slot] = index
		next_slot += 1
		_set_roster_card_selected(index, true)
	_refresh_team_summary()
	_apply_sort()


# ── 選擇邏輯 ──────────────────────────────────────────────────

func _on_roster_card_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	# 關卡限定隊伍時不允許修改
	if _is_party_locked():
		return
	_toggle_select(index)


## 點擊已選欄位的角色：取消選取（仍供其他路徑使用；頂部隊伍縮圖以 _on_team_card_input 處理）
func _on_slot_card_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _is_party_locked():
		return
	if _selection_has(index):
		_toggle_select(index)


func _is_party_locked() -> bool:
	return _stage != null and _stage.set_party.size() > 0


func _ensure_selection_slots() -> void:
	while _selected_indices.size() < GameState.MAX_PARTY_SIZE:
		_selected_indices.append(-1)
	if _selected_indices.size() > GameState.MAX_PARTY_SIZE:
		_selected_indices.resize(GameState.MAX_PARTY_SIZE)


func _selected_count() -> int:
	_ensure_selection_slots()
	var count: int = 0
	for index: int in _selected_indices:
		if index >= 0:
			count += 1
	return count


func _selection_has(index: int) -> bool:
	return _selection_slot_for_index(index) >= 0


func _selection_slot_for_index(index: int) -> int:
	_ensure_selection_slots()
	for slot in _selected_indices.size():
		if _selected_indices[slot] == index:
			return slot
	return -1


func _first_empty_selection_slot() -> int:
	_ensure_selection_slots()
	for slot in _selected_indices.size():
		if _selected_indices[slot] < 0:
			return slot
	return -1


func _selected_party_indices() -> Array[int]:
	_ensure_selection_slots()
	var indices: Array[int] = []
	for index: int in _selected_indices:
		if index >= 0 and index < GameState.owned_characters.size():
			indices.append(index)
	return indices


func _toggle_select(index: int) -> void:
	var existing_slot: int = _selection_slot_for_index(index)
	if existing_slot >= 0:
		_selected_indices[existing_slot] = -1
		_set_roster_card_selected(index, false)
	else:
		var empty_slot: int = _first_empty_selection_slot()
		if empty_slot < 0:
			return
		_selected_indices[empty_slot] = index
		_set_roster_card_selected(index, true)
	_refresh_team_summary()


func _set_roster_card_selected(index: int, selected: bool) -> void:
	if index < 0 or index >= _card_panels.size():
		return
	var style: StyleBox = _card_styles[index].selected if selected else _card_styles[index].normal
	var panel: PanelContainer = _card_panels[index]
	panel.add_theme_stylebox_override("panel", style)
	if index < _card_selection_badges.size() and is_instance_valid(_card_selection_badges[index]):
		var has_fixed_overlay: bool = panel.has_meta("_has_fixed_overlay") and bool(panel.get_meta("_has_fixed_overlay"))
		_card_selection_badges[index].visible = selected and not has_fixed_overlay


func _add_selection_badge(panel: PanelContainer) -> Control:
	var overlay: Control = _add_state_overlay(panel, Locale.tr_ui("DEPLOYED"))
	overlay.z_index = 30
	overlay.visible = false
	return overlay


func _on_cancel() -> void:
	closed.emit()


func _on_confirm() -> void:
	if _selected_count() == 0 or (_confirm_btn != null and _confirm_btn.disabled):
		return
	GameState.selected_party.clear()
	for idx in _selected_party_indices():
		GameState.selected_party.append(GameState.owned_characters[idx])

	# 有對話 → 先進對話場景；否則直接進戰鬥
	var next_path: String = "res://scenes/main.tscn"
	if _stage.pre_dialog != null and _stage.pre_dialog.lines.size() > 0:
		next_path = "res://scenes/dialog_box.tscn"
	if _confirm_btn != null:
		_confirm_btn.disabled = true
	GameState.load_stage_and_change_scene(_stage, next_path)


# ── 工具 ──────────────────────────────────────────────────────

func _get_stage_boss() -> EnemyData:
	if _stage.rounds.is_empty():
		return null
	var last_round: Array = _stage.rounds[_stage.rounds.size() - 1]
	if last_round.is_empty():
		return null
	return last_round[last_round.size() - 1] as EnemyData


func _make_label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


## 統一表頭樣式：font_size=20、color=(0.85,0.85,0.9)；color 參數保留仅為相容。
func _make_header_label(text: String, _color: Color = Color(0.85, 0.85, 0.9)) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


# ── 扇形圖示裁切節點 ─────────────────────────────────────────
## 以扇形多邊形作為裁切遮罩（CLIP_CHILDREN_ONLY：自身不渲染，子節點裁切到扇形內）
class _SliceClipper extends Control:
	var slice_start: float = 0.0
	var slice_sweep: float = 0.0

	func _draw() -> void:
		var center: Vector2 = size * 0.5
		var radius: float = minf(size.x, size.y) * 0.45
		var seg_count: int = 64
		var steps: int = maxi(int(seg_count * slice_sweep / TAU), 2)
		var points := PackedVector2Array()
		points.append(center)
		for j in steps + 1:
			var angle: float = slice_start + slice_sweep * (float(j) / float(steps))
			points.append(center + Vector2(cos(angle), sin(angle)) * radius)
		draw_colored_polygon(points, Color.WHITE)


# ── 圓餅圖繪製內部類 ─────────────────────────────────────────

class _PieDrawer extends Control:
	var slices: Array = []  # [{ratio: float, color: Color}]

	func _draw() -> void:
		var center: Vector2 = size * 0.5
		var radius: float = minf(size.x, size.y) * 0.45
		if slices.is_empty():
			draw_circle(center, radius, Color(0.2, 0.2, 0.25))
			return

		var start_angle: float = -PI * 0.5  # 12 點方向開始
		var seg_count: int = 64

		for slice: Dictionary in slices:
			var ratio: float = slice.ratio
			var color: Color = slice.color
			if ratio <= 0.0:
				continue
			var sweep: float = ratio * TAU
			var points := PackedVector2Array()
			points.append(center)
			var steps: int = maxi(int(seg_count * ratio), 2)
			for j in steps + 1:
				var angle: float = start_angle + sweep * (float(j) / float(steps))
				points.append(center + Vector2(cos(angle), sin(angle)) * radius)
			draw_colored_polygon(points, color)
			start_angle += sweep

		# 外框
		var outline_pts := PackedVector2Array()
		for j in seg_count + 1:
			var angle: float = float(j) / float(seg_count) * TAU - PI * 0.5
			outline_pts.append(center + Vector2(cos(angle), sin(angle)) * radius)
		draw_polyline(outline_pts, Color(0.4, 0.4, 0.5, 0.6), 1.5)


class _RotatingPieContainer extends Control:
	const ROTATION_SPEED: float = TAU / 80.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		pivot_offset = size * 0.5
		set_process(true)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			pivot_offset = size * 0.5

	func _process(delta: float) -> void:
		rotation = fmod(rotation + ROTATION_SPEED * delta, TAU)


class _CounterRotatingPieIcon extends TextureRect:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		pivot_offset = size * 0.5
		set_process(true)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_RESIZED:
			pivot_offset = size * 0.5

	func _process(_delta: float) -> void:
		var parent_control: Control = get_parent() as Control
		if parent_control == null:
			return
		rotation = -parent_control.rotation
