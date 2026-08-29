## RosterLayout — 依排序模式重新排列角色卡片，並於卡片底部顯示對應指標。
## 元素分組/篩選由 CharacterSorter 的元素列處理；本類負責平面排序與卡片排列。
## 由 characters_screen.gd 與 prepare_screen.gd 共用。
class_name RosterLayout
extends RefCounted

const CharacterSorterRef = preload("res://scripts/character_sorter.gd")
const FONT_PATH := "res://assets/fonts/game_ui_font.tres"
const ATK_ICON_PATH := "res://assets/slash.png"
const GROUP_BG_ALPHA := 0.25
const GROUP_ICON_ALPHA := 0.5
const GROUP_ICON_SIZE := 28.0

## 套用排序到容器。
## host: 會清空並重建為新的佈局
## entries: [{ "i": int, "c": CharacterData, "card": Control }]
## sort_mode: CharacterSorter.Mode
## columns: 每列卡片數
## ascending: 是否升冪排序（預設降冪）
## element_filter: CharacterSorter.ELEMENT_FILTER_ALL 表示不篩選，其他值為 Block.Type。
static func apply(host: Control, entries: Array, sort_mode: int, columns: int = 5, ascending: bool = false, element_filter: int = CharacterSorterRef.ELEMENT_FILTER_ALL) -> void:
	# 1) 將所有卡片從原父節點移除
	for e: Dictionary in entries:
		var card: Control = e.card
		if card.get_parent() != null:
			card.get_parent().remove_child(card)
		_set_metric_badge(card, e, sort_mode)

	# 2) 清空 host 現有內容
	for child in host.get_children():
		child.queue_free()

	# 3) 篩選 + 排序
	var visible_entries: Array[Dictionary] = []
	for e: Dictionary in entries:
		var c: CharacterData = e.c
		if element_filter != CharacterSorterRef.ELEMENT_FILTER_ALL and int(c.gem_type) != element_filter:
			continue
		visible_entries.append(e)
	var sorted_entries: Array[Dictionary] = _sort_entries(visible_entries, sort_mode, ascending)

	# 4) 將 FIXED 角色穩定地排到最前（不論排序模式）
	var fixed_first: Array[Dictionary] = []
	var rest: Array[Dictionary] = []
	for entry: Dictionary in sorted_entries:
		if entry.get("is_fixed", false):
			fixed_first.append(entry)
		else:
			rest.append(entry)
	sorted_entries = fixed_first + rest

	_build_grouped_layout(host, sorted_entries, columns)


static func _sort_entries(entries: Array[Dictionary], sort_mode: int, ascending: bool) -> Array[Dictionary]:
	var sorted: Array[Dictionary] = entries.duplicate()
	match sort_mode:
		CharacterSorterRef.Mode.LEVEL:
			sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var ac: CharacterData = a.c
				var bc: CharacterData = b.c
				return ac.level < bc.level if ascending else ac.level > bc.level)
		CharacterSorterRef.Mode.ATK:
			sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var ac: CharacterData = a.c
				var bc: CharacterData = b.c
				return ac.get_atk() < bc.get_atk() if ascending else ac.get_atk() > bc.get_atk())
		CharacterSorterRef.Mode.HP:
			sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var ac: CharacterData = a.c
				var bc: CharacterData = b.c
				return ac.get_max_hp() < bc.get_max_hp() if ascending else ac.get_max_hp() > bc.get_max_hp())
		CharacterSorterRef.Mode.MAGIC:
			sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var ac: CharacterData = a.c
				var bc: CharacterData = b.c
				return ac.get_magic() < bc.get_magic() if ascending else ac.get_magic() > bc.get_magic())
		CharacterSorterRef.Mode.TYPE:
			sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var ac: CharacterData = a.c
				var bc: CharacterData = b.c
				return int(ac.gem_type) < int(bc.gem_type) if ascending else int(ac.gem_type) > int(bc.gem_type))
	return sorted


# ── 內部：扁平網格 ──────────────────────────────────────────

static func _build_flat_grid(host: Control, sorted_entries: Array[Dictionary], columns: int) -> void:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.add_child(grid)

	for entry: Dictionary in sorted_entries:
		var card: Control = entry.card
		grid.add_child(card)


# ── 內部：依元素分組 ────────────────────────────────────────

static func _build_grouped_layout(host: Control, sorted_entries: Array[Dictionary], columns: int) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.add_child(vbox)

	var groups: Dictionary = {}
	var chars: Array = []
	for entry: Dictionary in sorted_entries:
		var c: CharacterData = entry.c
		chars.append(c)
		var element_type: int = int(c.gem_type)
		if not groups.has(element_type):
			groups[element_type] = []
		(groups[element_type] as Array).append(entry)

	for element_type: int in CharacterSorterRef.get_element_filter_order(chars):
		if not groups.has(element_type):
			continue
		var group_panel := PanelContainer.new()
		group_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bg_color: Color = Block.COLORS.get(element_type, Color.GRAY)
		bg_color.a = GROUP_BG_ALPHA
		var style := StyleBoxFlat.new()
		style.bg_color = bg_color
		style.set_corner_radius_all(10)
		style.set_content_margin_all(8)
		group_panel.add_theme_stylebox_override("panel", style)
		vbox.add_child(group_panel)

		var grid := GridContainer.new()
		grid.columns = columns
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		group_panel.add_child(grid)

		for entry: Dictionary in groups[element_type]:
			var card: Control = entry.card
			grid.add_child(card)

		var gem_tex: Texture2D = Block.GEM_TEXTURES.get(element_type)
		if gem_tex != null:
			var overlay := Control.new()
			overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			overlay.custom_minimum_size = Vector2.ZERO
			group_panel.add_child(overlay)

			var icon := TextureRect.new()
			icon.texture = gem_tex
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(GROUP_ICON_SIZE, GROUP_ICON_SIZE)
			icon.size = Vector2(GROUP_ICON_SIZE, GROUP_ICON_SIZE)
			icon.modulate = Color(1, 1, 1, GROUP_ICON_ALPHA)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			icon.position = -Vector2(GROUP_ICON_SIZE + 6, GROUP_ICON_SIZE + 6)
			overlay.add_child(icon)


# ── 內部：指標徽章（底部左）──────────────────────────────

static func _set_metric_badge(card: Control, entry: Dictionary, mode: int) -> void:
	var c: CharacterData = entry.c
	# 尋找或建立 overlay
	var overlay: Control = null
	if card.has_meta("_metric_overlay"):
		overlay = card.get_meta("_metric_overlay") as Control
		if not is_instance_valid(overlay):
			overlay = null
	if overlay == null:
		overlay = Control.new()
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(overlay)
		card.set_meta("_metric_overlay", overlay)

	# 清空
	for child in overlay.get_children():
		child.queue_free()

	# 建立 badge 容器（底部左）
	var badge_panel := PanelContainer.new()
	badge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	badge_panel.position = Vector2(-3, -27)
	badge_panel.add_theme_stylebox_override("panel", _make_badge_radial_style())
	overlay.add_child(badge_panel)

	var badge := HBoxContainer.new()
	badge.add_theme_constant_override("separation", 4)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_panel.add_child(badge)

	var text: String = ""
	var icon_path: String = ""
	var text_color: Color = Color.WHITE
	match mode:
		CharacterSorterRef.Mode.LEVEL:
			text = "Lv. %d" % int(entry.get("display_level", c.level))
			text_color = entry.get("level_color", Color.WHITE) as Color
		CharacterSorterRef.Mode.ATK:
			text = "%d" % c.get_atk()
			icon_path = ATK_ICON_PATH
		CharacterSorterRef.Mode.HP:
			text = "%d" % c.get_max_hp()
			icon_path = ATK_ICON_PATH
		CharacterSorterRef.Mode.TYPE:
			# TYPE 模式只負責元素排序，左上元素圖示已足夠，不另加指標徽章。
			overlay.visible = false
			return

	overlay.visible = true

	if icon_path != "":
		var tex: Texture2D = load(icon_path) as Texture2D
		if tex != null:
			var icon := TextureRect.new()
			icon.texture = tex
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(18, 18)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.add_child(icon)

	var font: Font = load(FONT_PATH)
	var lbl := Label.new()
	lbl.text = text
	if font != null:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", text_color)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(lbl)


static func _make_badge_radial_style() -> StyleBoxTexture:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.72, 1.0])
	gradient.colors = PackedColorArray([
		Color(0, 0, 0, 0.62),
		Color(0, 0, 0, 0.42),
		Color(0, 0, 0, 0.0),
	])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.35, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 48
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.set_content_margin(SIDE_LEFT, 6.0)
	style.set_content_margin(SIDE_RIGHT, 10.0)
	style.set_content_margin(SIDE_TOP, 3.0)
	style.set_content_margin(SIDE_BOTTOM, 3.0)
	return style
