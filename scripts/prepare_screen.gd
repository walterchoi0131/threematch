## PrepareScreen（戰前準備畫面）— 選擇隊伍、預覽 Boss、檢視關卡寶石分佈。
## 取代原本 map.gd 的 inline picker overlay。
extends Control

const FONT_PATH := "res://assets/fonts/RussoOne-Regular.ttf"
const VIEWPORT_W := 856.0
const VIEWPORT_H := 1024.0
const CharacterSorter = preload("res://scripts/character_sorter.gd")
const RosterLayout = preload("res://scripts/roster_layout.gd")

var _font: Font
var _stage: StageData

# ── 選擇狀態 ──
var _selected_indices: Array[int] = []
var _card_panels: Array[PanelContainer] = []
var _card_styles: Array[Dictionary] = []  # [{normal, selected}]
var _sort_mode: int = CharacterSorter.Mode.LEVEL
var _roster_grid: Control = null

# ── UI 節點 ──
var _count_label: Label = null
var _confirm_btn: Button = null
var _slot_row: HBoxContainer = null       # 已選角色欄位
var _slot_cards: Array[Control] = []      # 欄位中的角色卡 / 空位


func _ready() -> void:
	_font = load(FONT_PATH)
	_stage = GameState.selected_stage
	if _stage == null:
		get_tree().change_scene_to_file("res://scenes/map.tscn")
		return
	_build_ui()


# ── UI 建構 ──────────────────────────────────────────────────

func _build_ui() -> void:
	# 背景
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.07, 0.12, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# 全螢幕垂直排列容器
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 24.0
	root.offset_top = 12.0
	root.offset_right = -24.0
	root.offset_bottom = -12.0
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	# ── 關卡標題（靠左）──
	var stage_title := _make_label(Locale.tr_ui(_stage.stage_name), 26, Color(1.0, 0.9, 0.3))
	stage_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	root.add_child(stage_title)

	# ── Boss 預覽 + 寶石圓餅（合併為同一個全寬度區塊）──
	_build_info_box(root)

	# ── 已選隊伍欄位 ──
	_build_slot_section(root)

	# ── 角色選擇標題列：左「角色選擇」、右排序按鈕 ──
	var sel_header := HBoxContainer.new()
	sel_header.add_theme_constant_override("separation", 8)
	root.add_child(sel_header)

	var sel_label := _make_label(Locale.tr_ui("CHAR_SELECTION"), 18, Color(0.85, 0.85, 0.9))
	sel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sel_header.add_child(sel_label)

	var sort_row: HBoxContainer = CharacterSorter.make_sort_buttons(_sort_mode, _on_sort_changed)
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
	cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(cancel_btn)

	_confirm_btn = Button.new()
	_confirm_btn.text = Locale.tr_ui("EMBARK")
	_confirm_btn.custom_minimum_size = Vector2(140, 48)
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


# ── Boss + 寶石分佈（合併為單一全寬區塊） ────────────────────

func _build_info_box(parent: VBoxContainer) -> void:
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
	hbox.add_theme_constant_override("separation", 16)
	box.add_child(hbox)

	# ── 左側：Boss 資訊 ──
	_build_boss_content(hbox)

	# ── 右側：寶石圓餅 ──
	_build_pie_content(hbox)


func _build_boss_content(parent: HBoxContainer) -> void:
	var boss: EnemyData = _get_stage_boss()
	if boss == null:
		return

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(vbox)

	# Boss 頭像
	if boss.portrait_texture:
		var portrait := TextureRect.new()
		portrait.texture = boss.portrait_texture
		portrait.custom_minimum_size = Vector2(80, 80)
		portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(portrait)
	else:
		var portrait := ColorRect.new()
		portrait.custom_minimum_size = Vector2(80, 80)
		portrait.color = boss.portrait_color
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vbox.add_child(portrait)

	var boss_name := _make_label(boss.enemy_name, 16, Color(1.0, 0.85, 0.85))
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(boss_name)

	var boss_lv := _make_label("Lv.%d" % boss.enemy_level, 13, Color(0.7, 0.7, 0.75))
	boss_lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(boss_lv)

	var boss_stats := _make_label(
		"HP %d  ATK %d" % [boss.max_hp, boss.attack_damage],
		11, Color(0.6, 0.6, 0.65))
	boss_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(boss_stats)

	var bottom_row := HBoxContainer.new()
	bottom_row.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom_row.add_theme_constant_override("separation", 8)
	vbox.add_child(bottom_row)

	var elem_tex: Texture2D = Block.GEM_TEXTURES.get(boss.element)
	if elem_tex:
		var gem := TextureRect.new()
		gem.texture = elem_tex
		gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gem.custom_minimum_size = Vector2(24, 24)
		gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bottom_row.add_child(gem)
	else:
		var elem_color: Color = Block.COLORS.get(boss.element, Color.WHITE)
		var gem := ColorRect.new()
		gem.custom_minimum_size = Vector2(24, 24)
		gem.color = elem_color
		gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bottom_row.add_child(gem)

	var round_info := _make_label(
		"%s: %d" % [Locale.tr_ui("ROUNDS"), _stage.rounds.size()],
		11, Color(0.55, 0.55, 0.6))
	bottom_row.add_child(round_info)


func _build_pie_content(parent: HBoxContainer) -> void:
	var allowed: Array = _stage.allowed_types
	var count: int = allowed.size()
	if count == 0:
		return
	var ratio: float = 1.0 / float(count)

	const PIE_SIZE: float = 200.0
	const ICON_SIZE: float = 44.0  # 原本 22 的 2 倍
	var pie_container := Control.new()
	pie_container.custom_minimum_size = Vector2(PIE_SIZE, PIE_SIZE)
	pie_container.clip_contents = true  # 圖示溢出時裁切
	parent.add_child(pie_container)

	# 半透明切片資料
	var slices: Array[Dictionary] = []
	for t in allowed:
		var color: Color = Block.COLORS.get(t, Color.GRAY)
		color.a = 0.5
		slices.append({"ratio": ratio, "color": color})

	var pie := _PieDrawer.new()
	pie.slices = slices
	pie.set_anchors_preset(Control.PRESET_FULL_RECT)
	pie_container.add_child(pie)

	# 在每個切片中心放置半透明、放大的寶石圖示
	var pie_center: Vector2 = Vector2(PIE_SIZE * 0.5, PIE_SIZE * 0.5)
	var pie_radius: float = PIE_SIZE * 0.45
	var icon_radius: float = pie_radius * 0.55
	var start_angle: float = -PI * 0.5
	for i in count:
		var sweep: float = ratio * TAU
		var mid_angle: float = start_angle + sweep * 0.5
		var icon_pos: Vector2 = pie_center + Vector2(cos(mid_angle), sin(mid_angle)) * icon_radius
		var t: int = allowed[i]
		var gem_tex: Texture2D = Block.GEM_TEXTURES.get(t)
		if gem_tex:
			var icon := TextureRect.new()
			icon.texture = gem_tex
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
			icon.size = Vector2(ICON_SIZE, ICON_SIZE)
			icon.position = icon_pos - Vector2(ICON_SIZE * 0.5, ICON_SIZE * 0.5)
			icon.modulate = Color(1, 1, 1, 0.5)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pie_container.add_child(icon)
		start_angle += sweep


# ── 已選角色欄位 ──────────────────────────────────────────────

func _build_slot_section(parent: VBoxContainer) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	parent.add_child(header)

	var party_label := _make_label(Locale.tr_ui("PARTY"), 18, Color(1.0, 0.9, 0.3))
	party_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(party_label)

	# 保留隱藏的 count_label，避免下游 _refresh_slots 發生 null 存取
	_count_label = Label.new()
	_count_label.visible = false

	_slot_row = HBoxContainer.new()
	_slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_slot_row.add_theme_constant_override("separation", 8)
	parent.add_child(_slot_row)

	_refresh_slots()


func _refresh_slots() -> void:
	for child in _slot_row.get_children():
		child.queue_free()
	_slot_cards.clear()

	for i in GameState.MAX_PARTY_SIZE:
		if i < _selected_indices.size():
			var c: CharacterData = GameState.owned_characters[_selected_indices[i]]
			var data: Dictionary = CharacterCard.make_battle(c)
			var card: PanelContainer = data.panel
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.custom_minimum_size = Vector2(0, 60)
			var idx_in_owned: int = _selected_indices[i]
			card.gui_input.connect(_on_slot_card_input.bind(idx_in_owned))
			_slot_row.add_child(card)
			_slot_cards.append(card)
		else:
			var empty := _make_empty_battle_slot()
			_slot_row.add_child(empty)
			_slot_cards.append(empty)

	_count_label.text = "%d / %d" % [_selected_indices.size(), GameState.MAX_PARTY_SIZE]
	if _confirm_btn:
		_confirm_btn.disabled = _selected_indices.is_empty()


func _make_empty_battle_slot() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size = Vector2(0, 60)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.6)
	style.set_border_width_all(2)
	style.border_color = Color(0.25, 0.25, 0.35, 0.5)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", style)
	var lbl := Label.new()
	lbl.text = "?"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.35, 0.35, 0.4))
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)
	return panel


# ── 角色選擇網格 ──────────────────────────────────────────────

func _build_roster_grid(parent: ScrollContainer) -> void:
	var host := VBoxContainer.new()
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(host)
	_roster_grid = host

	_card_panels.clear()
	_card_styles.clear()

	var fixed_set: Dictionary = {}
	if _is_party_locked():
		for c: CharacterData in _stage.set_party:
			fixed_set[c] = true

	for i in GameState.owned_characters.size():
		var c: CharacterData = GameState.owned_characters[i]
		var data: Dictionary = CharacterCard.make_battle_selectable(c)
		var panel: PanelContainer = data.panel
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		panel.custom_minimum_size = Vector2(0, 60)
		panel.gui_input.connect(_on_roster_card_input.bind(i))
		_card_panels.append(panel)
		_card_styles.append({
			"normal": data.style_normal,
			"selected": data.style_selected,
		})
		if fixed_set.has(c):
			_add_fixed_overlay(panel)

	_apply_sort()


func _add_fixed_overlay(panel: PanelContainer) -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(overlay)

	var lbl := Label.new()
	lbl.text = Locale.tr_ui("FIXED")
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", _font)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(lbl)

	var tw := lbl.create_tween().set_loops()
	tw.tween_property(lbl, "modulate:a", 0.35, 0.7)
	tw.tween_property(lbl, "modulate:a", 1.0, 0.7)


func _on_sort_changed(mode: int) -> void:
	_sort_mode = mode
	_apply_sort()


func _apply_sort() -> void:
	if _roster_grid == null:
		return
	var entries: Array = []
	for i in GameState.owned_characters.size():
		entries.append({"i": i, "c": GameState.owned_characters[i], "card": _card_panels[i]})
	RosterLayout.apply(_roster_grid, entries, _sort_mode, 4)


# ── 選擇邏輯 ──────────────────────────────────────────────────

func _on_roster_card_input(event: InputEvent, index: int) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	# 關卡限定隊伍時不允許修改
	if _is_party_locked():
		return
	_toggle_select(index)


## 點擊已選欄位的角色：取消選取
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
	_refresh_slots()


func _on_cancel() -> void:
	get_tree().change_scene_to_file("res://scenes/map.tscn")


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
