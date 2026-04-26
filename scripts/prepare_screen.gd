## PrepareScreen（戰前準備畫面）— 選擇隊伍、預覽 Boss、檢視關卡寶石分佈。
## 以覆蓋層方式由 map.gd 開啟，關閉時 emit `closed` 訊號。
extends Control

signal closed

const FONT_PATH := "res://assets/fonts/RussoOne-Regular.ttf"
const CharacterSorter = preload("res://scripts/character_sorter.gd")
const RosterLayout = preload("res://scripts/roster_layout.gd")

var _font: Font
var _stage: StageData

# ── 選擇狀態 ──
var _selected_indices: Array[int] = []
var _card_panels: Array[PanelContainer] = []
var _card_styles: Array[Dictionary] = []  # [{normal, selected}]
var _card_lv_labels: Array[Label] = []    # 每張 roster 卡片的 Lv. 標籤（TYPE 排序時顯示）
var _sort_mode: int = CharacterSorter.Mode.TYPE
var _sort_ascending: bool = true   # TYPE 預設升冪
var _roster_grid: Control = null

# ── UI 節點 ──
var _confirm_btn: Button = null
var _team_summary: VBoxContainer = null   # 頂部隊伍縮圖列
var _team_summary_cards: Array[Control] = []
var _debug_panel: Control = null

# ── 卡片尺寸 ──
var _card_size: float = 100.0  # 單張方形卡边長 = vp.x / 7
const SUMMARY_CARD_RATIO: float = 0.85  # 頂部隊伍卡相對 roster 卡的縮放


func _ready() -> void:
	_font = load(FONT_PATH)
	_stage = GameState.selected_stage
	if _stage == null:
		closed.emit()
		return
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
	_debug_panel = SquareDebugPanel.build(self, chars, _apply_square_to_cards)


## 將 c.square_scale / square_offset 套用到目前畫面上「所有」顯示該角色的卡片頭像
func _apply_square_to_cards(c: CharacterData) -> void:
	# 角色選擇格 — 由 owned_characters 索引對應
	var idx: int = GameState.owned_characters.find(c)
	if idx >= 0 and idx < _card_panels.size():
		_apply_to_panel(_card_panels[idx], c)
	# 隊伍縮圖 — 任何顯示此角色的 slot 卡片
	for i in _selected_indices.size():
		if _selected_indices[i] == idx and i < _team_summary_cards.size():
			_apply_to_panel(_team_summary_cards[i] as Control, c)


func _apply_to_panel(card: Control, c: CharacterData) -> void:
	if card == null or not card.has_meta("_portrait"):
		return
	var p: TextureRect = card.get_meta("_portrait") as TextureRect
	if p == null:
		return
	p.scale = Vector2(c.square_scale, c.square_scale)
	p.position = c.square_offset


# ── UI 建構 ──────────────────────────────────────────────────

func _build_ui() -> void:
	# 計算卡片尺寸：1/7 viewport 寬度
	_card_size = ViewportUtils.get_size().x / 7.0

	# 背景
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

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

	# ── 頂部三欄：隊伍縮圖 | 元素分佈 | BOSS ──
	_build_top_row(root)

	# ── 角色選擇標題列：左「角色選擇」、右排序按鈕 ──
	var sel_header := HBoxContainer.new()
	sel_header.add_theme_constant_override("separation", 8)
	root.add_child(sel_header)

	var sel_label := _make_header_label(Locale.tr_ui("CHAR_SELECTION"), Color(0.85, 0.85, 0.9))
	sel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_header.add_child(sel_label)

	var sort_row: Button = CharacterSorter.make_sort_dropdown(_sort_mode, _on_sort_changed, _sort_ascending)
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

	# 自動選取：關卡指定隊伍則使用之；否則預選前 N 個角色
	if _stage.set_party.size() > 0:
		for c: CharacterData in _stage.set_party:
			var idx: int = GameState.owned_characters.find(c)
			if idx >= 0 and not _selected_indices.has(idx):
				_toggle_select(idx)
		# 將未選中的角色卡片半透明顯示
		for i in _card_panels.size():
			if not _selected_indices.has(i):
				_card_panels[i].modulate = Color(1, 1, 1, 0.35)
	else:
		var auto_count: int = mini(GameState.owned_characters.size(), GameState.MAX_PARTY_SIZE)
		for i in auto_count:
			_toggle_select(i)


# ── 頂部三欄：我的隊伍 | 元素分佈 | BOSS ────────────────────

func _build_top_row(parent: VBoxContainer) -> void:
	var box := PanelContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.14, 0.10, 0.18, 1)
	style.set_border_width_all(2)
	style.border_color = Color(0.7, 0.35, 0.35, 1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	box.add_theme_stylebox_override("panel", style)
	parent.add_child(box)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	box.add_child(hbox)

	# 左：我的隊伍（4 張小卡片）
	_build_team_summary(hbox)
	# 中：元素分佈圓餅
	_build_pie_content(hbox)
	# 右：Boss
	_build_boss_content(hbox)


# ── 左欄：我的隊伍縮圖 ───────────────────────────────────────

func _build_team_summary(parent: HBoxContainer) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(vbox)

	var title := _make_label(Locale.tr_ui("PARTY"), 20, Color(0.85, 0.85, 0.9))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vbox.add_child(title)

	_team_summary = VBoxContainer.new()
	_team_summary.add_theme_constant_override("separation", 4)
	_team_summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_team_summary)

	_refresh_team_summary()


func _refresh_team_summary() -> void:
	if _team_summary == null:
		return
	for child in _team_summary.get_children():
		child.queue_free()
	_team_summary_cards.clear()

	var row_h: float = _card_size * SUMMARY_CARD_RATIO * 0.5
	for i in GameState.MAX_PARTY_SIZE:
		var row: PanelContainer = PanelContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size = Vector2(0, row_h)
		var hbox: HBoxContainer = HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)
		row.add_child(hbox)

		if i < _selected_indices.size():
			var c: CharacterData = GameState.owned_characters[_selected_indices[i]]
			var elem_color: Color = Block.COLORS.get(c.gem_type, c.portrait_color)
			row.add_theme_stylebox_override("panel", _make_team_row_style(elem_color))

			# 左：純頭像（無邊框、無元素圖示），套用 square_scale / square_offset
			var portrait_card: Control = _make_team_portrait(c, row_h)
			var idx_in_owned: int = _selected_indices[i]
			portrait_card.gui_input.connect(_on_team_card_input.bind(idx_in_owned))
			hbox.add_child(portrait_card)

			# 右：名稱（上）+ 元素圖示與 Lv（下）
			var info_v := VBoxContainer.new()
			info_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info_v.size_flags_vertical = Control.SIZE_EXPAND_FILL
			info_v.alignment = BoxContainer.ALIGNMENT_CENTER
			info_v.add_theme_constant_override("separation", 2)
			hbox.add_child(info_v)

			var name_lbl := _make_label(Locale.tr_ui(c.character_name), 18, Color.WHITE)
			name_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
			name_lbl.add_theme_constant_override("outline_size", 4)
			info_v.add_child(name_lbl)

			var meta_h := HBoxContainer.new()
			meta_h.add_theme_constant_override("separation", 4)
			info_v.add_child(meta_h)

			var elem_tex: Texture2D = Block.GEM_TEXTURES.get(c.gem_type)
			if elem_tex:
				var gem := TextureRect.new()
				gem.texture = elem_tex
				gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				gem.custom_minimum_size = Vector2(20, 20)
				gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
				meta_h.add_child(gem)

			var lv_lbl := _make_label("Lv.%d" % c.level, 16, Color(1.0, 0.95, 0.7))
			lv_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
			lv_lbl.add_theme_constant_override("outline_size", 3)
			meta_h.add_child(lv_lbl)

			_team_summary_cards.append(portrait_card)
		else:
			row.add_theme_stylebox_override("panel", _make_empty_team_row_style())
			var slot: Control = _make_empty_summary_slot(row_h)
			hbox.add_child(slot)
			_team_summary_cards.append(slot)

		_team_summary.add_child(row)

	if _confirm_btn:
		_confirm_btn.disabled = _selected_indices.is_empty()


## 建立隊伍欄列左側純頭像：無邊框，套用 square_scale / square_offset，固定方形大小。
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
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.custom_minimum_size = Vector2(300, 300)
		portrait.size = Vector2(300, 300)
		portrait.pivot_offset = Vector2.ZERO
		portrait.scale = Vector2(c.square_scale, c.square_scale)
		portrait.position = c.square_offset
		clip.add_child(portrait)
		clip.set_meta("_portrait", portrait)
		clip.set_meta("_is_square", true)
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


func _make_empty_summary_slot(s: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = 0
	panel.custom_minimum_size = Vector2(s, s)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.6)
	style.set_border_width_all(2)
	style.border_color = Color(0.25, 0.25, 0.35, 0.5)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.text = "+"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _font != null:
		lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)
	return panel


func _on_team_card_input(event: InputEvent, idx_in_owned: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _is_party_locked():
		return
	if _selected_indices.has(idx_in_owned):
		_toggle_select(idx_in_owned)


func _build_boss_content(parent: HBoxContainer) -> void:
	var boss: EnemyData = _get_stage_boss()
	if boss == null:
		return

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_SHRINK_END
	vbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	parent.add_child(vbox)

	# 標題：BOSS（靠右）
	var boss_title := _make_label(Locale.tr_ui("BOSS"), 20, Color(0.85, 0.85, 0.9))
	boss_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	boss_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(boss_title)

	# Boss 頭像 — 套用與角色相同的「方形卡片」風格（靠右）
	var boss_card: PanelContainer = _make_boss_square_card(boss)
	boss_card.size_flags_horizontal = Control.SIZE_SHRINK_END
	boss_card.custom_minimum_size = Vector2(120, 120)
	vbox.add_child(boss_card)


## 以「正方形角色卡」風格建立 Boss 預覽卡片（仿 CharacterCard.make_square）。
func _make_boss_square_card(boss: EnemyData) -> PanelContainer:
	var char_color: Color = Block.COLORS.get(boss.element, boss.portrait_color)

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.1, 1.0)
	bg_style.set_corner_radius_all(10)
	bg_style.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", bg_style)

	# AspectRatio 強制正方形 + 裁切
	var aspect := AspectRatioContainer.new()
	aspect.ratio = 1.0
	aspect.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
	aspect.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
	aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	aspect.set_anchors_preset(Control.PRESET_FULL_RECT)
	aspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(aspect)
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	aspect.add_child(clip)

	# 頭像
	if boss.portrait_texture:
		var portrait := TextureRect.new()
		portrait.texture = boss.portrait_texture
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
		clip.add_child(portrait)
	else:
		var portrait_rect := ColorRect.new()
		portrait_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		portrait_rect.color = boss.portrait_color
		portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(portrait_rect)

	# 雙層彩色邊框
	var inner_border := Panel.new()
	inner_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inner_style := StyleBoxFlat.new()
	inner_style.draw_center = false
	inner_style.border_color = char_color
	inner_style.set_border_width_all(4)
	inner_style.set_corner_radius_all(10)
	inner_border.add_theme_stylebox_override("panel", inner_style)
	panel.add_child(inner_border)

	var outer_border := Panel.new()
	outer_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var outer_style := StyleBoxFlat.new()
	outer_style.draw_center = false
	outer_style.border_color = char_color.darkened(0.35)
	outer_style.set_border_width_all(2)
	outer_style.set_corner_radius_all(10)
	outer_border.add_theme_stylebox_override("panel", outer_style)
	panel.add_child(outer_border)

	# 元素寶石圖示已移除（Boss 不顯示元素圖示）；保留 gem_layer 作為 Lv 徽章定位容器
	var gem_layer := Control.new()
	gem_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gem_layer.clip_contents = false
	panel.add_child(gem_layer)

	# Lv. 徽章（左下角）
	var boss_lv_font: Font = load(FONT_PATH)
	var boss_lv_label := Label.new()
	boss_lv_label.text = "Lv.%d" % boss.enemy_level
	if boss_lv_font != null:
		boss_lv_label.add_theme_font_override("font", boss_lv_font)
	boss_lv_label.add_theme_font_size_override("font_size", 32)
	boss_lv_label.add_theme_color_override("font_color", Color.WHITE)
	boss_lv_label.add_theme_color_override("font_outline_color", Color.BLACK)
	boss_lv_label.add_theme_constant_override("outline_size", 5)
	boss_lv_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_lv_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	boss_lv_label.grow_horizontal = Control.GROW_DIRECTION_END
	boss_lv_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	boss_lv_label.offset_left = 4.0
	boss_lv_label.offset_top = -44.0
	boss_lv_label.offset_right = 4.0
	boss_lv_label.offset_bottom = 0.0
	gem_layer.add_child(boss_lv_label)

	return panel


func _build_pie_content(parent: HBoxContainer) -> void:
	var allowed: Array = _stage.allowed_types
	var count: int = allowed.size()
	if count == 0:
		return
	var ratio: float = 1.0 / float(count)

	const PIE_SIZE: float = 140.0
	const ICON_SIZE: float = 56.0  # 元素圖示

	# 包一層 VBox 以容納標題 + 圓餅
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	parent.add_child(vbox)

	var pie_title := _make_label(Locale.tr_ui("ELEMENT_DISTRIBUTION"), 20, Color(0.85, 0.85, 0.9))
	pie_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vbox.add_child(pie_title)

	var pie_container := Control.new()
	pie_container.custom_minimum_size = Vector2(PIE_SIZE, PIE_SIZE)
	pie_container.clip_contents = true  # 圖示溢出時裁切
	vbox.add_child(pie_container)

	# 背景切片
	var slices: Array[Dictionary] = []
	for t in allowed:
		var color: Color = Block.COLORS.get(t, Color.GRAY)
		color.a = 0.5
		slices.append({"ratio": ratio, "color": color})

	var pie := _PieDrawer.new()
	pie.slices = slices
	pie.set_anchors_preset(Control.PRESET_FULL_RECT)
	pie_container.add_child(pie)

	# 每個切片：用 _SliceClipper（CLIP_CHILDREN_ONLY）將圖示裁切到扇形範圍內
	var pie_center: Vector2 = Vector2(PIE_SIZE * 0.5, PIE_SIZE * 0.5)
	var pie_radius: float = PIE_SIZE * 0.45
	var icon_radius: float = pie_radius * 0.55 + 35.0  # 向半徑方向移動 35px
	var start_angle: float = -PI * 0.5
	for i in count:
		var sweep: float = ratio * TAU
		var mid_angle: float = start_angle + sweep * 0.5
		var icon_pos: Vector2 = pie_center + Vector2(cos(mid_angle), sin(mid_angle)) * icon_radius
		var t: int = allowed[i]
		var gem_tex: Texture2D = Block.GEM_TEXTURES.get(t)
		if gem_tex:
			var clipper := _SliceClipper.new()
			clipper.slice_start = start_angle
			clipper.slice_sweep = sweep
			clipper.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
			clipper.set_anchors_preset(Control.PRESET_FULL_RECT)
			pie_container.add_child(clipper)

			var icon := TextureRect.new()
			icon.texture = gem_tex
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
			icon.size = Vector2(ICON_SIZE, ICON_SIZE)
			icon.position = icon_pos - Vector2(ICON_SIZE * 0.5, ICON_SIZE * 0.5)
			icon.modulate = Color(1, 1, 1, 0.5)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			clipper.add_child(icon)
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
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(overlay)

	var lbl := Label.new()
	lbl.text = Locale.tr_ui("FIXED")
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

	var tw := lbl.create_tween().set_loops()
	tw.tween_property(lbl, "modulate:a", 0.35, 0.7)
	tw.tween_property(lbl, "modulate:a", 1.0, 0.7)


func _on_sort_changed(mode: int, ascending: bool) -> void:
	_sort_mode = mode
	_sort_ascending = ascending
	_update_lv_labels_visibility()
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
	RosterLayout.apply(_roster_grid, entries, _sort_mode, 6, _sort_ascending)


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
	if _selected_indices.has(index):
		_toggle_select(index)


func _is_party_locked() -> bool:
	return _stage != null and _stage.set_party.size() > 0


func _toggle_select(index: int) -> void:
	if _selected_indices.has(index):
		_selected_indices.erase(index)
		_card_panels[index].add_theme_stylebox_override("panel", _card_styles[index].normal)
	else:
		if _selected_indices.size() >= GameState.MAX_PARTY_SIZE:
			return
		_selected_indices.append(index)
		_card_panels[index].add_theme_stylebox_override("panel", _card_styles[index].selected)
	_refresh_team_summary()


func _on_cancel() -> void:
	closed.emit()


func _on_confirm() -> void:
	if _selected_indices.is_empty():
		return
	GameState.selected_party.clear()
	for idx in _selected_indices:
		GameState.selected_party.append(GameState.owned_characters[idx])

	# 有對話 → 先進對話場景；否則直接進戰鬥
	var next_path: String = "res://scenes/main.tscn"
	if _stage.pre_dialog != null and _stage.pre_dialog.lines.size() > 0:
		next_path = "res://scenes/dialog_box.tscn"
	GameState.fade_to_scene(next_path)


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
