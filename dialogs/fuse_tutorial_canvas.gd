## FuseTutorialCanvas — 教學第 2 步（教融合寶石）後彈出的覆蓋面板。
## 顯示隊伍 4 位角色每位的融合提示，沿用 character_detail 的格式：
##   左：以 rectangular_offset/scale 渲染的角色圖（底/左/右裁切，頂部可溢出）。
##   右：對每個 responding_skill 顯示 [合成寶石 N+] ▶ [融合寶石] ▶ [爆發範圍 5×5]。
## 點擊 OK 按鈕關閉。
class_name FuseTutorialCanvas
extends RefCounted

const FONT_PATH := "res://assets/fonts/RussoOne-Regular.ttf"

const NAME_TO_UPPER: Dictionary = {
	"Fireball": Block.UpperType.FIREBALL,
	"Fire Pillar": Block.UpperType.FIRE_PILLAR_X,
	"Water Slash": Block.UpperType.WATER_SLASH_X,
	"Justice Slash": Block.UpperType.SAINT_CROSS,
	"Saint Cross": Block.UpperType.SAINT_CROSS,
	"Leaf Shield": Block.UpperType.LEAF_SHIELD,
	"Snowball": Block.UpperType.SNOWBALL,
	"Porcupine": Block.UpperType.PORCUPINE,
	"Turtle": Block.UpperType.TURTLE,
}


## 建立並 attach 到 parent。
## party: Array[CharacterData]
## on_close: 關閉時的 Callable
static func build(parent: Node, party: Array, on_close: Callable) -> Control:
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
	panel.custom_minimum_size = Vector2(640, 0)
	panel.offset_left = -340
	panel.offset_right = 340
	panel.offset_top = -300
	panel.offset_bottom = 300
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

	for c: CharacterData in party:
		if c == null:
			continue
		vbox.add_child(_make_row(c))

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


static func _make_row(c: CharacterData) -> Control:
	const ROW_H: float = 96.0
	const PORTRAIT_W: float = 96.0
	const IMG_SIZE: float = 300.0 * 4.0

	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_H + 8)
	row.clip_contents = true
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.08, 0.10, 0.16, 1.0)
	row_style.set_corner_radius_all(8)
	row_style.set_content_margin_all(6)
	row.add_theme_stylebox_override("panel", row_style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	# 佔位（保留左側寬度，讓技能區不從最左邊開始）
	var placeholder := Control.new()
	placeholder.custom_minimum_size = Vector2(PORTRAIT_W, ROW_H)
	placeholder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	placeholder.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(placeholder)

	# 角色圖：絕對定位，底-左錨點，4× 尺寸，頂部溢出
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
		portrait.offset_left   = 0.0
		portrait.offset_top    = -IMG_SIZE
		portrait.offset_right  = IMG_SIZE
		portrait.offset_bottom = 0.0
		portrait.pivot_offset  = Vector2(0, IMG_SIZE)
		portrait.scale = Vector2(c.rectangular_scale, c.rectangular_scale)
		portrait.position += c.rectangular_offset
		row.add_child(portrait)

	# 右：每個 responding_skill 一條 [hint] ▶ [upper] ▶ [blast]
	var skills_box := VBoxContainer.new()
	skills_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
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
		skills_box.add_child(_make_skill_chain(fuse_label, base_gem_tex, gem_tex, pattern, elem_color))

	return row


## 構建 [合成提示 N+] ▶ [融合寶石] ▶ [爆發範圍] 一條水平鏈。
static func _make_skill_chain(fuse_label: String, base_gem_tex: Texture2D, upper_gem_tex: Texture2D, pattern: Array, elem_color: Color) -> Control:
	var chain := HBoxContainer.new()
	chain.add_theme_constant_override("separation", 6)
	chain.alignment = BoxContainer.ALIGNMENT_BEGIN

	if fuse_label != "" and base_gem_tex != null:
		chain.add_child(_make_fuse_hint_box(fuse_label, base_gem_tex, 44.0))
		chain.add_child(_make_arrow_label())

	if upper_gem_tex != null:
		chain.add_child(_make_gem_box(upper_gem_tex, 44.0))

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
	num.add_theme_font_size_override("font_size", 22)
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


static func _make_arrow_label() -> Label:
	var arrow := Label.new()
	arrow.text = "▶"
	arrow.add_theme_font_size_override("font_size", 16)
	arrow.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return arrow


static func _make_blast_preview_box(pattern: Array, elem_color: Color) -> Control:
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var hit: Dictionary = {}
	for p in pattern:
		hit[p] = true

	var cell: float = 9.0
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


static func _blast_pattern_for(upper_type: int) -> Array:
	match upper_type:
		Block.UpperType.FIREBALL:
			return [Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 3), Vector2i(1, 2), Vector2i(3, 2)]
		Block.UpperType.FIRE_PILLAR_X, Block.UpperType.WATER_SLASH_X:
			var cells: Array = []
			for x in 5: cells.append(Vector2i(x, 2))
			return cells
		Block.UpperType.FIRE_PILLAR_Y, Block.UpperType.WATER_SLASH_Y:
			var cells_y: Array = []
			for y in 5: cells_y.append(Vector2i(2, y))
			return cells_y
		Block.UpperType.SAINT_CROSS:
			return [Vector2i(2, 2), Vector2i(0, 0), Vector2i(1, 1), Vector2i(3, 3), Vector2i(4, 4),
					Vector2i(0, 4), Vector2i(1, 3), Vector2i(3, 1), Vector2i(4, 0)]
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
