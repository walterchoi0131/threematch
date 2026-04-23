## RosterLayout — 依排序模式重新排列角色卡片，並於卡片底部顯示對應指標。
## 當排序模式為 TYPE 時，按元素分組，每組有半透明同色背景 + 右下元素圖示。
## 由 characters_screen.gd 與 prepare_screen.gd 共用。
class_name RosterLayout
extends RefCounted

const CharacterSorterRef = preload("res://scripts/character_sorter.gd")
const FONT_PATH := "res://assets/fonts/RussoOne-Regular.ttf"
const ATK_ICON_PATH := "res://assets/slash.png"

const GROUP_BG_ALPHA := 0.25
const GROUP_ICON_ALPHA := 0.5
const GROUP_ICON_SIZE := 56.0


## 套用排序到容器。
## host: 會清空並重建為新的佈局
## entries: [{ "i": int, "c": CharacterData, "card": Control }]
## sort_mode: CharacterSorter.Mode
## columns: 每列卡片數
## ascending: 是否升冪排序（預設降冪）
static func apply(host: Control, entries: Array, sort_mode: int, columns: int = 5, ascending: bool = false) -> void:
	# 1) 將所有卡片從原父節點移除
	for e: Dictionary in entries:
		var card: Control = e.card
		if card.get_parent() != null:
			card.get_parent().remove_child(card)
		_set_metric_badge(card, e.c, sort_mode)

	# 2) 清空 host 現有內容
	for child in host.get_children():
		child.queue_free()

	# 3) 排序
	var chars: Array = []
	for e: Dictionary in entries:
		chars.append(e.c)
	var sorted_idx: Array = CharacterSorterRef.sort_indexed(chars, sort_mode, ascending)

	# 4) 將 FIXED 角色穩定地排到最前（不論排序模式）
	var fixed_first: Array = []
	var rest: Array = []
	for entry: Dictionary in sorted_idx:
		var owned_idx: int = entry.i
		if entries[owned_idx].get("is_fixed", false):
			fixed_first.append(entry)
		else:
			rest.append(entry)
	sorted_idx = fixed_first + rest

	if sort_mode == CharacterSorterRef.Mode.TYPE:
		_build_grouped_layout(host, entries, sorted_idx, columns)
	else:
		_build_flat_grid(host, entries, sorted_idx, columns)


# ── 內部：扁平網格 ──────────────────────────────────────────

static func _build_flat_grid(host: Control, entries: Array, sorted_idx: Array, columns: int) -> void:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.add_child(grid)

	for entry: Dictionary in sorted_idx:
		var owned_idx: int = entry.i
		var card: Control = entries[owned_idx].card
		grid.add_child(card)


# ── 內部：依元素分組 ────────────────────────────────────────

static func _build_grouped_layout(host: Control, entries: Array, sorted_idx: Array, columns: int) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host.add_child(vbox)

	# 依 gem_type 聚合
	var groups: Dictionary = {}     # type -> Array[owned_idx]
	var order: Array = []           # 首次出現順序
	for entry: Dictionary in sorted_idx:
		var owned_idx: int = entry.i
		var t: int = int(entries[owned_idx].c.gem_type)
		if not groups.has(t):
			groups[t] = []
			order.append(t)
		groups[t].append(owned_idx)

	for t in order:
		var group_panel := PanelContainer.new()
		group_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bg_color: Color = Block.COLORS.get(t, Color.GRAY)
		bg_color.a = GROUP_BG_ALPHA
		var style := StyleBoxFlat.new()
		style.bg_color = bg_color
		style.set_corner_radius_all(10)
		style.set_content_margin_all(8)
		group_panel.add_theme_stylebox_override("panel", style)
		vbox.add_child(group_panel)

		# PanelContainer 會讓所有子節點疊在同一矩形上；先放 GridContainer
		# 以決定最小高度，再放元素圖示 overlay 於右下角。
		var grid := GridContainer.new()
		grid.columns = columns
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		group_panel.add_child(grid)

		for owned_idx: int in groups[t]:
			grid.add_child(entries[owned_idx].card)

		# 右下元素圖示（半透明，不攔截滑鼠）
		var gem_tex: Texture2D = Block.GEM_TEXTURES.get(t)
		if gem_tex:
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

static func _set_metric_badge(card: Control, c: CharacterData, mode: int) -> void:
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
	var badge := HBoxContainer.new()
	badge.add_theme_constant_override("separation", 4)
	badge.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	badge.position = Vector2(6, -44)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(badge)

	var text: String = ""
	var icon_path: String = ""
	match mode:
		CharacterSorterRef.Mode.LEVEL:
			text = "Lv. %d" % c.level
		CharacterSorterRef.Mode.ATK:
			text = "%d" % c.get_atk()
			icon_path = ATK_ICON_PATH
		CharacterSorterRef.Mode.HP:
			text = "%d" % c.get_max_hp()
			icon_path = ATK_ICON_PATH
		CharacterSorterRef.Mode.TYPE:
			# TYPE 模式已以分組呈現，徽章不顯示
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
			icon.custom_minimum_size = Vector2(36, 36)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			badge.add_child(icon)

	var font: Font = load(FONT_PATH)
	var lbl := Label.new()
	lbl.text = text
	if font != null:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(lbl)
