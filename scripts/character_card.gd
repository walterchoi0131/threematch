## CharacterCard — 可重用的角色卡片建構工具。
## 用於角色列表、準備畫面、戰鬥結算等場景。
class_name CharacterCard
extends RefCounted

const FONT_PATH := "res://assets/fonts/RussoOne-Regular.ttf"


## 卡片尺寸配置
enum CardSize { SMALL, MEDIUM, LARGE }

## 尺寸參數 — {card_size, portrait_size, name_size, lv_size, stat_size, gem_size}
const SIZE_PRESETS: Dictionary = {
	CardSize.SMALL: {
		"card": Vector2(110, 160),
		"portrait": Vector2(100, 100),
		"name_font": 12,
		"lv_font": 14,
		"stat_font": 0,
		"gem": 0,
		"show_stats": false,
		"show_gem": false,
	},
	CardSize.MEDIUM: {
		"card": Vector2(230, 300),
		"portrait": Vector2(200, 200),
		"name_font": 20,
		"lv_font": 16,
		"stat_font": 13,
		"gem": 24,
		"show_stats": true,
		"show_gem": true,
	},
	CardSize.LARGE: {
		"card": Vector2(340, 420),
		"portrait": Vector2(300, 300),
		"name_font": 26,
		"lv_font": 20,
		"stat_font": 16,
		"gem": 32,
		"show_stats": true,
		"show_gem": true,
	},
}


## 建立戰鬥風格角色卡（頭像 + 元素圖示，無文字）。
## 回傳 Dictionary: {panel, portrait, gem_icon, glow}
## portrait 可能為 null（角色無貼圖時）。
## 供 CharacterPanel 附加冷卻標籤、放射光芒、點擊事件。
## 注意：本函數用於「戰鬥中」角色列，非正方形；套用 portrait_scale / portrait_offset。
static func make_battle(c: CharacterData) -> Dictionary:
	return _make_battle_like(c, false)


## 建立「方形」風格角色卡（無文字，強制正方形）。
## 用於戰前準備畫面、角色選擇格 — 套用 square_scale / square_offset。
## 回傳 Dictionary: {panel, portrait, gem_icon, glow}
static func make_square(c: CharacterData) -> Dictionary:
	return _make_battle_like(c, true)


## 內部：共用建構流程。
## square=true → AspectRatioContainer 強制正方形 + square_scale/offset
## square=false → 全矩形裁切 + portrait_scale/offset
static func _make_battle_like(c: CharacterData, square: bool) -> Dictionary:
	var gem_size: int = 56 if square else 28
	var char_color: Color = c.portrait_color

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.08, 0.08, 0.1, 1.0)
	bg_style.set_corner_radius_all(10)
	bg_style.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", bg_style)

	# 發光層（最底，alpha=0）
	var glow := ColorRect.new()
	glow.color = Color(1.0, 0.9, 0.2, 0.0)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(glow)

	# 裁切容器（頭像在此層，clip_contents 防止溢出）
	var clip: Control
	if square:
		# 以 AspectRatioContainer 包裹，讓裁切區永遠呈現正方形
		var aspect := AspectRatioContainer.new()
		aspect.ratio = 1.0
		aspect.alignment_horizontal = AspectRatioContainer.ALIGNMENT_CENTER
		aspect.alignment_vertical = AspectRatioContainer.ALIGNMENT_CENTER
		aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
		aspect.set_anchors_preset(Control.PRESET_FULL_RECT)
		aspect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(aspect)
		clip = Control.new()
		clip.clip_contents = true
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		aspect.add_child(clip)
	else:
		clip = Control.new()
		clip.clip_contents = true
		clip.set_anchors_preset(Control.PRESET_FULL_RECT)
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(clip)

	# 頭像
	var portrait_ref: TextureRect = null
	if c.portrait_texture:
		var portrait := TextureRect.new()
		portrait.texture = c.portrait_texture
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.custom_minimum_size = Vector2(300, 300)
		portrait.size = Vector2(300, 300)
		portrait.pivot_offset = Vector2.ZERO
		if square:
			portrait.scale = Vector2(c.square_scale, c.square_scale)
			portrait.position = c.square_offset
		else:
			portrait.scale = Vector2(c.portrait_scale, c.portrait_scale)
			portrait.position = c.portrait_offset
		clip.add_child(portrait)
		portrait_ref = portrait
		panel.set_meta("_portrait", portrait)
		panel.set_meta("_is_square", square)
	else:
		var portrait := ColorRect.new()
		portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
		portrait.color = c.portrait_color
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(portrait)

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

	# 元素寶石圖示（左上角）
	var gem_layer := Control.new()
	gem_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gem_layer.clip_contents = false
	panel.add_child(gem_layer)

	var gem_icon := TextureRect.new()
	var gem_tex: Texture2D = Block.GEM_TEXTURES.get(c.gem_type)
	if gem_tex:
		gem_icon.texture = gem_tex
	gem_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gem_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gem_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gem_icon.pivot_offset = Vector2(gem_size * 0.5, gem_size * 0.5)
	gem_icon.offset_left = -gem_size * 0.5
	gem_icon.offset_right = gem_size * 0.5
	gem_icon.offset_top = -gem_size * 0.5
	gem_icon.offset_bottom = gem_size * 0.5
	gem_layer.add_child(gem_icon)

	return {
		"panel": panel,
		"portrait": portrait_ref,
		"gem_icon": gem_icon,
		"glow": glow,
	}


## 建立角色卡片。回傳 PanelContainer。
static func make(c: CharacterData, size: CardSize = CardSize.MEDIUM) -> PanelContainer:
	var preset: Dictionary = SIZE_PRESETS[size]
	var font: Font = load(FONT_PATH)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = preset.card

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.14, 0.22, 1)
	style.set_border_width_all(2)
	style.border_color = Color(0.35, 0.4, 0.55, 1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# 頭像（帶裁切容器，套用 portrait_scale / portrait_offset）
	var clip := Control.new()
	clip.custom_minimum_size = preset.portrait
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(clip)

	if c.portrait_texture:
		var portrait := TextureRect.new()
		portrait.texture = c.portrait_texture
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.custom_minimum_size = preset.portrait
		portrait.size = preset.portrait
		portrait.scale = Vector2(c.square_scale, c.square_scale)
		portrait.position = c.square_offset
		clip.add_child(portrait)
		panel.set_meta("_portrait", portrait)
	else:
		var portrait := ColorRect.new()
		portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
		portrait.color = c.portrait_color
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(portrait)

	# 名字
	var name_lbl := Label.new()
	name_lbl.text = c.character_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_override("font", font)
	name_lbl.add_theme_font_size_override("font_size", preset.name_font)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_lbl)

	# 等級
	var lv_lbl := Label.new()
	lv_lbl.text = "Lv.%d" % c.level
	lv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_lbl.add_theme_font_override("font", font)
	lv_lbl.add_theme_font_size_override("font_size", preset.lv_font)
	lv_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	lv_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(lv_lbl)

	# 寶石圖示 + 數值 (MEDIUM/LARGE)
	if preset.show_stats:
		var stat_row := HBoxContainer.new()
		stat_row.alignment = BoxContainer.ALIGNMENT_CENTER
		stat_row.add_theme_constant_override("separation", 6)
		vbox.add_child(stat_row)

		# 元素寶石圖示
		if preset.show_gem:
			var gem_tex: Texture2D = Block.GEM_TEXTURES.get(c.gem_type)
			if gem_tex:
				var gem_icon := TextureRect.new()
				gem_icon.texture = gem_tex
				gem_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				gem_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
				gem_icon.custom_minimum_size = Vector2(preset.gem, preset.gem)
				gem_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
				stat_row.add_child(gem_icon)

		# ATK / HP
		var stat_lbl := Label.new()
		stat_lbl.text = "ATK %d  HP %d" % [c.get_atk(), c.get_max_hp()]
		stat_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stat_lbl.add_theme_font_size_override("font_size", preset.stat_font)
		stat_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
		stat_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stat_row.add_child(stat_lbl)

	return panel


## 建立角色卡（含選中邊框樣式切換）。回傳 {panel, style_normal, style_selected}。
static func make_selectable(c: CharacterData, size: CardSize = CardSize.MEDIUM) -> Dictionary:
	var panel := make(c, size)

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.12, 0.14, 0.22, 1)
	style_normal.set_border_width_all(3)
	style_normal.border_color = Color(0.35, 0.4, 0.55, 1)
	style_normal.set_corner_radius_all(8)
	style_normal.set_content_margin_all(6)

	var style_selected := StyleBoxFlat.new()
	style_selected.bg_color = Color(0.2, 0.24, 0.35, 1)
	style_selected.set_border_width_all(3)
	style_selected.border_color = Color(1.0, 0.85, 0.2, 1)
	style_selected.set_corner_radius_all(8)
	style_selected.set_content_margin_all(6)

	panel.add_theme_stylebox_override("panel", style_normal)

	return {
		"panel": panel,
		"style_normal": style_normal,
		"style_selected": style_selected,
	}


## 戰鬥風格角色卡（無文字）+ 可選取邊框。回傳 {panel, style_normal, style_selected}。
static func make_battle_selectable(c: CharacterData) -> Dictionary:
	return _wrap_selectable(make_battle(c), c)


## 方形角色卡（無文字、強制正方形）+ 可選取邊框。回傳 {panel, style_normal, style_selected}。
static func make_square_selectable(c: CharacterData) -> Dictionary:
	return _wrap_selectable(make_square(c), c)


static func _wrap_selectable(data: Dictionary, _c: CharacterData) -> Dictionary:
	var panel: PanelContainer = data.panel

	var style_normal := StyleBoxFlat.new()
	style_normal.bg_color = Color(0.08, 0.08, 0.1, 1.0)
	style_normal.set_corner_radius_all(10)
	style_normal.set_content_margin_all(0)

	var style_selected := StyleBoxFlat.new()
	style_selected.bg_color = Color(0.12, 0.14, 0.2, 1.0)
	style_selected.set_border_width_all(4)
	style_selected.border_color = Color(1.0, 0.85, 0.2, 1)
	style_selected.set_corner_radius_all(10)
	style_selected.set_content_margin_all(0)

	panel.add_theme_stylebox_override("panel", style_normal)

	return {
		"panel": panel,
		"style_normal": style_normal,
		"style_selected": style_selected,
	}


## 建立空的卡片佔位（用於未填滿的隊伍欄位）
static func make_empty_slot(size: CardSize = CardSize.MEDIUM) -> PanelContainer:
	var preset: Dictionary = SIZE_PRESETS[size]
	var font: Font = load(FONT_PATH)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = preset.card

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.6)
	style.set_border_width_all(2)
	style.border_color = Color(0.25, 0.25, 0.35, 0.5)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", style)

	var lbl := Label.new()
	lbl.text = "?"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", Color(0.3, 0.3, 0.4, 0.5))
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(lbl)

	return panel
