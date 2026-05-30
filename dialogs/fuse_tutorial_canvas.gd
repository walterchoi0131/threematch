## FuseTutorialCanvas — 教學第 2 步（教融合寶石）後彈出的覆蓋面板。
## 顯示隊伍 4 位角色每位的融合提示，沿用 character_detail 的格式：
##   左：以 portrait_offset/scale 渲染的角色圖（與戰鬥角色面板一致）。
##   右：對每個 responding_skill 顯示 [合成寶石 N+] ▶ [融合寶石] ▶ [爆發範圍 5×5]。
## 點擊 OK 按鈕關閉。
class_name FuseTutorialCanvas
extends RefCounted

const FONT_PATH := "res://assets/fonts/RussoOne-Regular.ttf"
const INSTRUCTION_SCALE: float = 1.5
const SKILL_GEM_SIZE: float = 44.0 * INSTRUCTION_SCALE
const SKILL_NUMBER_FONT_SIZE: int = 33
const SKILL_ARROW_FONT_SIZE: int = 24
const SKILL_CHAIN_SEPARATION: int = 9
const SKILL_ROW_SEPARATION: int = 6
const BLAST_PREVIEW_CELL_SIZE: float = 9.0 * INSTRUCTION_SCALE
const BLAST_PREVIEW_SEPARATION: int = 2
const PANEL_MARGIN_X: float = 12.0
const PANEL_MARGIN_Y: float = 20.0
const MAX_PANEL_WIDTH: float = 680.0
const MAX_PANEL_HEIGHT: float = 540.0
const PANEL_WIDTH_SCALE: float = 0.85
const PANEL_HEIGHT_SCALE: float = 1.20
const BATTLE_ROW_SIDE_MARGIN: float = 16.0
const BATTLE_ROW_CARD_GAP: float = 4.0
const BATTLE_ROW_HEIGHT: float = 60.0
const PANEL_BASE_HEIGHT: float = 132.0

const NAME_TO_UPPER: Dictionary = {
	"Fireball": Block.UpperType.FIREBALL,
	"Fire Pillar": Block.UpperType.FIRE_PILLAR_X,
	"Water Slash": Block.UpperType.WATER_SLASH,
	"Justice Slash": Block.UpperType.SAINT_CROSS,
	"Saint Cross": Block.UpperType.SAINT_CROSS,
	"Leaf Shield": Block.UpperType.LEAF_SHIELD,
	"Snowball": Block.UpperType.SNOWBALL,
	"Porcupine": Block.UpperType.PORCUPINE,
	"Turtle": Block.UpperType.TURTLE,
	"Bamboo Supply": Block.UpperType.BAMBOO_SUPPLY,
	"Wood Spear": Block.UpperType.WOOD_SPEAR_UP,
}


## 建立並 attach 到 parent。
## party: Array[CharacterData]
## on_close: 關閉時的 Callable
static func build(parent: Node, party: Array, on_close: Callable) -> Control:
	var viewport_size: Vector2 = ViewportUtils.get_size()
	var max_width: float = minf(MAX_PANEL_WIDTH, viewport_size.x - PANEL_MARGIN_X * 2.0)
	var panel_width: float = maxf(max_width * PANEL_WIDTH_SCALE, 320.0)
	var battle_card_size: Vector2 = _battle_panel_card_size(maxi(party.size(), 1))
	var row_height: float = _row_height_for(battle_card_size.y)
	var max_height: float = minf(MAX_PANEL_HEIGHT, viewport_size.y - PANEL_MARGIN_Y * 2.0)
	var target_height: float = _estimated_panel_height(party.size(), row_height) * PANEL_HEIGHT_SCALE
	var panel_height: float = minf(target_height, max_height)

	var layer := CanvasLayer.new()
	layer.layer = 70
	parent.add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(panel_width, 0)
	panel.offset_left = -panel_width * 0.5
	panel.offset_right = panel_width * 0.5
	panel.offset_top = -panel_height * 0.5
	panel.offset_bottom = panel_height * 0.5
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.12, 0.18, 0.97)
	bg.set_border_width_all(2)
	bg.border_color = Color(0.85, 0.72, 0.30, 1.0)
	bg.set_corner_radius_all(12)
	bg.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", bg)
	root.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := _styled_label(Locale.tr_ui("FUSE_HINT"), 26, Color(1.0, 0.92, 0.30))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var rows_scroll := ScrollContainer.new()
	rows_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(rows_scroll)

	var rows_vbox := VBoxContainer.new()
	rows_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_vbox.add_theme_constant_override("separation", 8)
	rows_scroll.add_child(rows_vbox)

	for c: CharacterData in party:
		if c == null:
			continue
		rows_vbox.add_child(_make_row(c, battle_card_size))

	var ok_row := HBoxContainer.new()
	ok_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(ok_row)

	var ok_btn := Button.new()
	ok_btn.text = "OK"
	ok_btn.custom_minimum_size = Vector2(140, 40)
	ok_row.add_child(ok_btn)

	var closing := {"done": false}
	var do_close := func() -> void:
		if closing.done:
			return
		closing.done = true
		layer.queue_free()
		if on_close.is_valid():
			on_close.call()
	ok_btn.pressed.connect(do_close)

	return root


static func _make_row(c: CharacterData, battle_card_size: Vector2) -> Control:
	var row_h: float = _row_height_for(battle_card_size.y)
	var portrait_size: Vector2 = Vector2(battle_card_size.x, battle_card_size.y)

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, row_h)
	row.clip_contents = true
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.08, 0.10, 0.16, 1.0)
	row_style.set_corner_radius_all(8)
	row_style.set_content_margin_all(6)
	row.add_theme_stylebox_override("panel", row_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(hbox)

	var portrait_clip := Control.new()
	portrait_clip.custom_minimum_size = portrait_size
	portrait_clip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	portrait_clip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	portrait_clip.clip_contents = true
	portrait_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(portrait_clip)

	# 角色圖：與戰鬥角色面板相同的 portrait_scale / portrait_offset。
	if c.portrait_texture != null:
		var portrait := TextureRect.new()
		portrait.texture = c.portrait_texture
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.custom_minimum_size = Vector2(300, 300)
		portrait.size = Vector2(300, 300)
		portrait.pivot_offset = Vector2.ZERO
		portrait.scale = Vector2(c.portrait_scale, c.portrait_scale)
		portrait.position = c.portrait_offset
		portrait_clip.add_child(portrait)

	# 右：每個 responding_skill 一條 [hint] ▶ [upper] ▶ [blast]
	var skills_box := VBoxContainer.new()
	skills_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	skills_box.size_flags_stretch_ratio = 1.0
	skills_box.add_theme_constant_override("separation", 4)
	hbox.add_child(skills_box)

	var elem_color: Color = Block.COLORS.get(c.gem_type, Color(0.4, 0.6, 1.0))
	var base_gem_tex: Texture2D = Block.GEM_TEXTURES.get(c.gem_type, null)

	for skill: Dictionary in c.responding_skills:
		var sname: String = skill.get("name", "")
		if sname == "":
			continue
		var fuse_label: String = str(skill.get("fuse_label", skill.get("threshold", "")))
		var upper_type: int = NAME_TO_UPPER.get(sname, -1)
		var gem_tex: Texture2D = Block.UPPER_GEM_TEXTURES.get(upper_type, null) if upper_type >= 0 else null
		var pattern: Array = _blast_pattern_for(upper_type)
		skills_box.add_child(_make_skill_chain(fuse_label, base_gem_tex, gem_tex, upper_type, pattern, elem_color))

	return row


## 構建 [合成提示 N+] ▶ [融合寶石] ▶ [爆發範圍] 一條水平鏈。
static func _make_skill_chain(fuse_label: String, base_gem_tex: Texture2D, upper_gem_tex: Texture2D, upper_type: int, pattern: Array, elem_color: Color) -> Control:
	var chain := HBoxContainer.new()
	chain.add_theme_constant_override("separation", SKILL_CHAIN_SEPARATION)
	chain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chain.alignment = BoxContainer.ALIGNMENT_BEGIN

	if fuse_label != "" and base_gem_tex != null:
		chain.add_child(_make_fuse_hint_box(fuse_label, base_gem_tex, SKILL_GEM_SIZE))
		chain.add_child(_make_arrow_label())

	if upper_gem_tex != null:
		chain.add_child(_make_upper_gem_box(upper_type, upper_gem_tex, SKILL_GEM_SIZE))

	if pattern.size() > 0:
		chain.add_child(_make_arrow_label())
		chain.add_child(_make_blast_preview_box(pattern, elem_color))

	return chain


static func _make_fuse_hint_box(fuse_label: String, base_gem_tex: Texture2D, gem_size: float) -> Control:
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(gem_size, gem_size)
	stack.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var gem := TextureRect.new()
	gem.texture = base_gem_tex
	gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gem.set_anchors_preset(Control.PRESET_FULL_RECT)
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(gem)

	var num := Label.new()
	num.text = "%s+" % fuse_label
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	var f: Font = load(FONT_PATH)
	if f != null:
		num.add_theme_font_override("font", f)
	num.add_theme_font_size_override("font_size", SKILL_NUMBER_FONT_SIZE)
	num.add_theme_color_override("font_color", Color.WHITE)
	num.add_theme_color_override("font_outline_color", Color.BLACK)
	num.add_theme_constant_override("outline_size", 5)
	num.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	num.add_theme_constant_override("shadow_offset_x", 2)
	num.add_theme_constant_override("shadow_offset_y", 2)
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(num)
	return stack


static func _make_gem_box(tex: Texture2D, gem_size: float) -> Control:
	var gem := TextureRect.new()
	gem.texture = tex
	gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gem.custom_minimum_size = Vector2(gem_size, gem_size)
	gem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return gem


static func _make_upper_gem_box(upper_type: int, tex: Texture2D, gem_size: float) -> Control:
	return _make_gem_box(tex, gem_size)


static func _make_arrow_label() -> Label:
	var arrow := Label.new()
	arrow.text = "▶"
	arrow.add_theme_font_size_override("font_size", SKILL_ARROW_FONT_SIZE)
	arrow.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return arrow


static func _make_blast_preview_box(pattern: Array, elem_color: Color) -> Control:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", BLAST_PREVIEW_SEPARATION)
	grid.add_theme_constant_override("v_separation", BLAST_PREVIEW_SEPARATION)
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.size_flags_horizontal = Control.SIZE_SHRINK_END
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hit: Dictionary = {}
	for p in pattern:
		hit[p] = true

	var cell: float = BLAST_PREVIEW_CELL_SIZE
	var fill_col: Color = elem_color
	fill_col.a = 1.0
	var empty_col: Color = Color(0.13, 0.15, 0.22, 1.0)
	for y in 5:
		for x in 5:
			var rect := ColorRect.new()
			rect.custom_minimum_size = Vector2(cell, cell)
			rect.color = fill_col if hit.has(Vector2i(x, y)) else empty_col
			grid.add_child(rect)
	return grid


static func _battle_panel_card_size(card_count: int) -> Vector2:
	var viewport_size: Vector2 = ViewportUtils.get_size()
	var safe_count: int = maxi(card_count, 1)
	var usable_width: float = maxf(viewport_size.x - BATTLE_ROW_SIDE_MARGIN * 2.0, 0.0)
	var gap_total: float = BATTLE_ROW_CARD_GAP * float(maxi(safe_count - 1, 0))
	var card_width: float = maxf((usable_width - gap_total) / float(safe_count), BATTLE_ROW_HEIGHT)
	return Vector2(card_width, BATTLE_ROW_HEIGHT)


static func _row_height_for(battle_row_height: float) -> float:
	return maxf(battle_row_height, SKILL_GEM_SIZE) + 10.0


static func _estimated_panel_height(card_count: int, row_height: float) -> float:
	return PANEL_BASE_HEIGHT + float(card_count) * row_height + float(maxi(card_count - 1, 0)) * 8.0


static func _blast_pattern_for(upper_type: int) -> Array:
	match upper_type:
		Block.UpperType.FIREBALL:
			return [
				Vector2i(2, 0),
				Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
				Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2),
				Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3),
				Vector2i(2, 4),
			]
		Block.UpperType.FIRE_PILLAR_X:
			var cells: Array = []
			for x in 5: cells.append(Vector2i(x, 2))
			return cells
		Block.UpperType.FIRE_PILLAR_Y, Block.UpperType.WATER_SLASH:
			var cells_y: Array = []
			for y in 5: cells_y.append(Vector2i(2, y))
			return cells_y
		Block.UpperType.SAINT_CROSS:
			return [Vector2i(2, 0), Vector2i(2, 1), Vector2i(0, 2), Vector2i(1, 2), Vector2i(2, 2),
					Vector2i(3, 2), Vector2i(4, 2), Vector2i(2, 3), Vector2i(2, 4)]
		Block.UpperType.SNOWBALL:
			var cells_b: Array = []
			for x in range(1, 4):
				for y in range(1, 4):
					cells_b.append(Vector2i(x, y))
			return cells_b
		Block.UpperType.LEAF_SHIELD:
			return [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
					Vector2i(1, 2),                  Vector2i(3, 2),
					Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)]
		Block.UpperType.PORCUPINE, Block.UpperType.TURTLE:
			return [Vector2i(2, 2)]
		Block.UpperType.BAMBOO_SUPPLY:
			return [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
					Vector2i(1, 2),                  Vector2i(3, 2),
					Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)]
		Block.UpperType.WOOD_SPEAR_UP:
			return [Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 0), Vector2i(1, 0), Vector2i(3, 0)]
		Block.UpperType.WOOD_SPEAR_DOWN:
			return [Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(1, 4), Vector2i(3, 4)]
	return []


static func _styled_label(text: String, size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	var f: Font = load(FONT_PATH)
	if f != null:
		lbl.add_theme_font_override("font", f)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl
