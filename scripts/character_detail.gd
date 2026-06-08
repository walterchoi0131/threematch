## CharacterDetail（角色詳細畫面）— 顯示單一角色的完整資訊。
## 包括頭像、名稱、等級、攻擊/血量、各類技能等。
## 可以 「全畫面」（current_scene）或 「覆蓋層」（被他人隱式實例化）兩種模式開啟，
## 後者用於詳細畫面返回時保留 characters_screen 的捲動⼏排序狀態。
extends Node2D

signal closed

const CARD_BG_COLOR := Color(0.09, 0.09, 0.14, 1)   # 與地圖背景一致
const CARD_BORDER_COLOR := Color(0.45, 0.5, 0.65, 1)
const CARD_MARGIN := 16.0                            # 卡片到螢幕邊距
const ENTER_DUR := 0.28
const EXIT_DUR := 0.22
const UPGRADE_HOLD_DURATION := 0.9
const UPGRADE_TEXT_DARK := Color(0.25, 0.26, 0.30, 1.0)
const UPGRADE_TEXT_LIGHT := Color(0.92, 0.92, 0.96, 1.0)
const UPGRADE_TEXT_UNLOCKED := Color(0.9, 0.9, 0.95, 1.0)
const UPGRADE_SLOT_DARK := Color(0.05, 0.055, 0.065, 1.0)
const SE_OPEN := preload("res://assets/se/card_draw_3.wav")
const JOB_ICON_PATHS: Dictionary = {
	"attacker": "res://assets/jobs/attacker.png",
	"breaker": "res://assets/jobs/breaker.png",
	"tactictian": "res://assets/jobs/tactictian.png",
	"wizard": "res://assets/jobs/wizard.png",
}

var _char: CharacterData  # 要顯示的角色資料
var _card: Control = null
var _closing: bool = false
var _upgrade_hold_tween: Tween = null
var _upgrade_hold_token: int = 0
var _upgrade_hold_completed: bool = false


func _ready() -> void:
	_char = GameState.detail_character
	if _char == null:
		if get_tree().current_scene == self:
			get_tree().change_scene_to_file("res://scenes/characters.tscn")
		else:
			closed.emit()
		return
	_build_ui()
	_play_open_animation()


func _build_ui() -> void:
	var vp: Vector2 = ViewportUtils.get_size()

	# 以 CanvasLayer 包住所有 UI，避免被外部 Node2D / OverlayFrame 的座標位移影響
	# （此節點以覆蓋層方式開啟時，根 Node2D 會繼承 OverlayFrame 位置，
	# 直接掛 Control 會跟著偏移；CanvasLayer 為螢幕對齊不受影響）
	var layer := CanvasLayer.new()
	layer.layer = 70
	add_child(layer)

	# ── 全螢幕底色（避免卡片邊距外露透明）──
	var screen_bg := ColorRect.new()
	screen_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen_bg.color = CARD_BG_COLOR
	screen_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen_bg)

	# ── 卡片容器（pivot 置中，供 zoom 動畫使用）──
	_card = Control.new()
	_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_card.offset_left = CARD_MARGIN
	_card.offset_top = CARD_MARGIN
	_card.offset_right = -CARD_MARGIN
	_card.offset_bottom = -CARD_MARGIN
	_card.pivot_offset = Vector2((vp.x - CARD_MARGIN * 2.0) * 0.5, (vp.y - CARD_MARGIN * 2.0) * 0.5)
	layer.add_child(_card)

	# ── 卡片背景（地圖配色 + 邊框 + 圓角）──
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = CARD_BG_COLOR
	card_style.border_color = CARD_BORDER_COLOR
	card_style.set_border_width_all(2)
	card_style.set_corner_radius_all(12)
	card_style.shadow_color = Color(0, 0, 0, 0.5)
	card_style.shadow_size = 8
	bg.add_theme_stylebox_override("panel", card_style)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(bg)

	var bottom_reserve: float = 84.0  # 保留給 Back 按鈕
	var card_w: float = vp.x - CARD_MARGIN * 2.0
	var card_h: float = vp.y - CARD_MARGIN * 2.0

	var scroll := ScrollContainer.new()
	scroll.offset_left = 0.0
	scroll.offset_top = 0.0
	scroll.offset_right = card_w
	scroll.offset_bottom = card_h - bottom_reserve
	_card.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.custom_minimum_size = Vector2(card_w, 0)
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)

	# ── 頂部標題列：左元素徽章 + 中央名稱牌 ──
	_build_header(vbox, card_w)

	# ── 大型角色圖（含背景框）──
	_build_portrait_area(vbox, card_w)

	# ── Lv + EXP 列 ──
	_build_lv_exp_row(vbox, card_w)

	# ── 三項屬性徽章（ATK / HP / MAG）──
	_build_stats_row(vbox, card_w)

	# ── 技能區 ──
	_build_skills_section(vbox, card_w)

	# 底部空間（避免被 Back 按鈕遮住）
	var spacer_bottom := Control.new()
	spacer_bottom.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(spacer_bottom)

	# ── Back button ── (置中在卡片底部保留區)
	var back_btn := Button.new()
	back_btn.text = Locale.tr_ui("BACK")
	var btn_w: float = 196.0
	var btn_h: float = 40.0
	back_btn.offset_left = (card_w - btn_w) * 0.5
	back_btn.offset_top = card_h - bottom_reserve + 20.0
	back_btn.offset_right = back_btn.offset_left + btn_w
	back_btn.offset_bottom = back_btn.offset_top + btn_h
	back_btn.pressed.connect(_on_back_pressed)
	_card.add_child(back_btn)


# ── Header：左元素徽章 + 中央名稱牌 ─────────────────────────
func _build_header(parent: VBoxContainer, card_w: float) -> void:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(card_w, 64)
	parent.add_child(holder)

	var elem_color: Color = Block.COLORS.get(_char.gem_type, _char.portrait_color)

	# 中央名稱牌
	var plate := PanelContainer.new()
	var plate_style := StyleBoxFlat.new()
	plate_style.bg_color = Color(0.10, 0.13, 0.22, 1.0)
	plate_style.border_color = Color(0.85, 0.72, 0.35)
	plate_style.set_border_width_all(3)
	plate_style.set_corner_radius_all(28)
	plate_style.content_margin_left = 32
	plate_style.content_margin_right = 32
	plate_style.content_margin_top = 8
	plate_style.content_margin_bottom = 8
	plate.add_theme_stylebox_override("panel", plate_style)
	plate.set_anchors_preset(Control.PRESET_CENTER)
	plate.position = Vector2(card_w * 0.5, 32)
	plate.size = Vector2(0, 0)
	holder.add_child(plate)

	var name_lbl := Label.new()
	name_lbl.text = Locale.tr_ui(_char.character_name)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 30)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	name_lbl.add_theme_constant_override("outline_size", 4)
	plate.add_child(name_lbl)

	# 置中（依量測之後位置調整）
	plate.set_meta("_card_w", card_w)
	plate.resized.connect(func() -> void:
		plate.position = Vector2((card_w - plate.size.x) * 0.5, 16)
	)

	# 左側元素徽章（圓形 + 寶石）
	var badge_size: float = 56.0
	var badge := PanelContainer.new()
	var badge_style := StyleBoxFlat.new()
	badge_style.bg_color = Color(0.08, 0.10, 0.18, 1.0)
	badge_style.border_color = Color(0.85, 0.72, 0.35)
	badge_style.set_border_width_all(3)
	badge_style.set_corner_radius_all(int(badge_size * 0.5))
	badge_style.content_margin_left = 4
	badge_style.content_margin_right = 4
	badge_style.content_margin_top = 4
	badge_style.content_margin_bottom = 4
	badge.add_theme_stylebox_override("panel", badge_style)
	badge.position = Vector2(8, 4)
	badge.size = Vector2(badge_size, badge_size)
	holder.add_child(badge)

	var gem_tex: Texture2D = Block.GEM_TEXTURES.get(_char.gem_type)
	if gem_tex:
		var gem := TextureRect.new()
		gem.texture = gem_tex
		gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		badge.add_child(gem)
	else:
		var gem_color := ColorRect.new()
		gem_color.color = elem_color
		badge.add_child(gem_color)


# ── 大型角色圖區 ─────────────────────────────────────────────
func _build_portrait_area(parent: VBoxContainer, card_w: float) -> void:
	var elem_color: Color = Block.COLORS.get(_char.gem_type, _char.portrait_color)

	var frame := PanelContainer.new()
	var frame_style := StyleBoxFlat.new()
	# 用元素色暗化作為背景
	var dark: Color = elem_color.darkened(0.55)
	dark.a = 1.0
	frame_style.bg_color = dark
	frame_style.border_color = Color(0.85, 0.72, 0.35)
	frame_style.set_border_width_all(2)
	frame_style.set_corner_radius_all(10)
	frame_style.content_margin_left = 0
	frame_style.content_margin_right = 0
	frame_style.content_margin_top = 0
	frame_style.content_margin_bottom = 0
	frame.add_theme_stylebox_override("panel", frame_style)
	frame.custom_minimum_size = Vector2(card_w - 16.0, 360)
	parent.add_child(frame)

	# 裁切容器，避免 portrait 用 scale/offset 時溢出
	var clip := Control.new()
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(clip)

	if _char.portrait_texture:
		var portrait := TextureRect.new()
		portrait.texture = _char.portrait_texture
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.set_anchors_preset(Control.PRESET_FULL_RECT)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(portrait)
	else:
		var rect := ColorRect.new()
		rect.color = _char.portrait_color
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		clip.add_child(rect)


# ── Lv 徽章 + EXP 進度條 ─────────────────────────────────────
func _build_lv_exp_row(parent: VBoxContainer, card_w: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	# Lv 牌
	var lv_plate := PanelContainer.new()
	var lv_style := StyleBoxFlat.new()
	lv_style.bg_color = Color(0.10, 0.13, 0.22, 1.0)
	lv_style.border_color = Color(0.85, 0.72, 0.35)
	lv_style.set_border_width_all(2)
	lv_style.set_corner_radius_all(18)
	lv_style.content_margin_left = 18
	lv_style.content_margin_right = 18
	lv_style.content_margin_top = 6
	lv_style.content_margin_bottom = 6
	lv_plate.add_theme_stylebox_override("panel", lv_style)
	row.add_child(lv_plate)

	var lv_lbl := Label.new()
	lv_lbl.text = "Lv %d" % _char.level
	lv_lbl.add_theme_font_size_override("font_size", 22)
	lv_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	lv_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lv_lbl.add_theme_constant_override("outline_size", 3)
	lv_plate.add_child(lv_lbl)

	# EXP 區
	var exp_plate := PanelContainer.new()
	exp_plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var exp_style := StyleBoxFlat.new()
	exp_style.bg_color = Color(0.10, 0.13, 0.22, 1.0)
	exp_style.border_color = Color(0.85, 0.72, 0.35)
	exp_style.set_border_width_all(2)
	exp_style.set_corner_radius_all(18)
	exp_style.content_margin_left = 14
	exp_style.content_margin_right = 14
	exp_style.content_margin_top = 6
	exp_style.content_margin_bottom = 6
	exp_plate.add_theme_stylebox_override("panel", exp_style)
	row.add_child(exp_plate)

	var exp_h := HBoxContainer.new()
	exp_h.add_theme_constant_override("separation", 10)
	exp_plate.add_child(exp_h)

	var exp_label := Label.new()
	exp_label.text = "EXP"
	exp_label.add_theme_font_size_override("font_size", 16)
	exp_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	exp_h.add_child(exp_label)

	var exp_max: int = _char.exp_to_next_level()
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = maxi(exp_max, 1)
	bar.value = clampi(_char.current_exp, 0, exp_max)
	bar.show_percentage = false
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.custom_minimum_size = Vector2(120, 18)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.04, 0.06, 0.1, 1.0)
	bar_bg.set_corner_radius_all(8)
	var bar_fg := StyleBoxFlat.new()
	bar_fg.bg_color = Color(0.30, 0.65, 1.0)
	bar_fg.set_corner_radius_all(8)
	bar.add_theme_stylebox_override("background", bar_bg)
	bar.add_theme_stylebox_override("fill", bar_fg)
	exp_h.add_child(bar)

	var exp_val := Label.new()
	exp_val.text = "%d / %d" % [_char.current_exp, exp_max]
	exp_val.add_theme_font_size_override("font_size", 14)
	exp_val.add_theme_color_override("font_color", Color.WHITE)
	exp_h.add_child(exp_val)


# ── ATK / HP / MAG 三屬性徽章 ─────────────────────────────────
func _build_stats_row(parent: VBoxContainer, _card_w: float) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 18)
	parent.add_child(row)

	if _char.job_id != "":
		row.add_child(_make_job_badge(_char.job_id))
	row.add_child(_make_stat_badge("ATK", _char.get_atk(), Color(1.0, 0.45, 0.30)))
	row.add_child(_make_stat_badge("HP", _char.get_max_hp(), Color(0.45, 0.85, 0.45)))
	row.add_child(_make_stat_badge("MAG", _char.get_magic(), Color(0.55, 0.55, 1.0)))


func _make_job_badge(job_id: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(166, 56)
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.10, 0.13, 0.22, 1.0)
	style.border_color = Color(0.85, 0.72, 0.35)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.content_margin_left = 8
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)

	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_path: String = str(JOB_ICON_PATHS.get(job_id, ""))
	if icon_path != "" and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path) as Texture2D
	row.add_child(icon)

	var labels := VBoxContainer.new()
	labels.add_theme_constant_override("separation", -2)
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(labels)

	var title := Label.new()
	title.text = Locale.tr_ui("JOB")
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.8, 0.82, 0.92))
	labels.add_child(title)

	var name := Label.new()
	name.text = Locale.tr_ui("JOB_" + job_id.to_upper())
	name.add_theme_font_size_override("font_size", 18)
	name.add_theme_color_override("font_color", Color.WHITE)
	name.add_theme_color_override("font_outline_color", Color.BLACK)
	name.add_theme_constant_override("outline_size", 3)
	labels.add_child(name)

	return panel


func _make_stat_badge(label: String, value: int, color: Color) -> Control:
	# 圓形徽章 + 數字
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)

	var icon_size: float = 44.0
	var icon := PanelContainer.new()
	var icon_style := StyleBoxFlat.new()
	var dark: Color = color.darkened(0.4)
	dark.a = 1.0
	icon_style.bg_color = dark
	icon_style.border_color = color.lightened(0.2)
	icon_style.set_border_width_all(3)
	icon_style.set_corner_radius_all(int(icon_size * 0.5))
	icon_style.content_margin_left = 6
	icon_style.content_margin_right = 6
	icon_style.content_margin_top = 6
	icon_style.content_margin_bottom = 6
	icon.add_theme_stylebox_override("panel", icon_style)
	icon.custom_minimum_size = Vector2(icon_size, icon_size)
	box.add_child(icon)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", -2)
	box.add_child(info)

	var label_lbl := Label.new()
	label_lbl.text = label
	label_lbl.add_theme_font_size_override("font_size", 13)
	label_lbl.add_theme_color_override("font_color", color)
	info.add_child(label_lbl)

	var val_lbl := Label.new()
	val_lbl.text = "%d" % value
	val_lbl.add_theme_font_size_override("font_size", 24)
	val_lbl.add_theme_color_override("font_color", Color.WHITE)
	val_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	val_lbl.add_theme_constant_override("outline_size", 3)
	info.add_child(val_lbl)

	return box


# ── 技能區 ───────────────────────────────────────────────────
func _build_skills_section(parent: VBoxContainer, _card_w: float) -> void:
	# 標題列：兩側金色裝飾線 + 中央「技能」
	var title_row := HBoxContainer.new()
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 12)
	parent.add_child(title_row)

	var skills_title := Label.new()
	skills_title.text = Locale.tr_ui("SKILLS")
	skills_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skills_title.add_theme_font_size_override("font_size", 26)
	skills_title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	skills_title.add_theme_color_override("font_outline_color", Color.BLACK)
	skills_title.add_theme_constant_override("outline_size", 3)
	title_row.add_child(skills_title)

	# Passive — 不顯示寶石
	if _char.passive_skill_name != "":
		_add_skill_entry(parent, Locale.tr_ui("PASSIVE"), Locale.tr_or(_char.passive_skill_name, _char.passive_skill_name), Locale.tr_or(_char.passive_skill_name + " DESC", _char.passive_skill_desc), 0, null, "", [])

	# Active — 不顯示寶石
	if _char.active_skill_name != "":
		_add_skill_entry(parent, Locale.tr_ui("ACTIVE"), Locale.tr_or(_char.active_skill_name, _char.active_skill_name), SkillUpgradeUtils.get_active_description(_char), SkillUpgradeUtils.effective_active_cd(_char), null, "", [], SkillUpgradeUtils.KIND_ACTIVE, 0)

	# Responding — 顯示對應融合寶石、合成提示與爆發範圍
	for skill_index in range(_char.responding_skills.size()):
		var skill: Dictionary = _char.responding_skills[skill_index]
		var sname: String = skill.get("name", "")
		if sname == "":
			continue
		# 查找本地化名稱與描述（以 sname 為鍵，沒找到則使用原始字串）
		var display_name: String = Locale.tr_ui(sname)
		if display_name == sname or display_name == "":
			display_name = sname
		var upper_type: int = _resolve_responding_upper(sname)
		var gem_tex: Texture2D = Block.UPPER_GEM_TEXTURES.get(upper_type, null) if upper_type >= 0 else null
		var fuse_label: String = SkillUpgradeUtils.responding_fuse_label(_char, skill_index, skill)
		var pattern: Array = _blast_pattern_for(upper_type)
		_add_skill_entry(parent, Locale.tr_ui("RESPONDING"), display_name, SkillUpgradeUtils.get_responding_description(_char, skill_index, skill), 0, gem_tex, fuse_label, pattern, SkillUpgradeUtils.KIND_RESPONDING, skill_index)


## 由回應技能名稱對應到 UpperType（無對應時回傳 -1）。
func _resolve_responding_upper(skill_name: String) -> int:
	const NAME_TO_UPPER: Dictionary = {
		"Fireball": Block.UpperType.FIREBALL,
		"Fire Pillar": Block.UpperType.FIRE_PILLAR_X,
		"Water Slash": Block.UpperType.WATER_SLASH,
		"Justice Slash": Block.UpperType.SAINT_CROSS,
		"Saint Cross": Block.UpperType.SAINT_CROSS,
		"Leaf Shield": Block.UpperType.LEAF_SHIELD,
		"Snowball": Block.UpperType.SNOWBALL,
		"Iceball": Block.UpperType.ICEBALL,
		"Porcupine": Block.UpperType.PORCUPINE,
		"Turtle": Block.UpperType.TURTLE,
		"Bamboo Supply": Block.UpperType.BAMBOO_SUPPLY,
		"Wood Spear": Block.UpperType.WOOD_SPEAR_UP,
		"光之盾": Block.UpperType.LIGHT_SHIELD,
	}
	return NAME_TO_UPPER.get(skill_name, -1)


## 回傳 5x5 預覽格中要點亮的格子座標（中心為 (2,2)）。
func _blast_pattern_for(upper_type: int) -> Array:
	match upper_type:
		Block.UpperType.FIREBALL:
			# 十字（中心 + 上下左右各延 1 格）
			return [Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 3), Vector2i(1, 2), Vector2i(3, 2)]
		Block.UpperType.FIRE_PILLAR_X:
			# 整列
			var cells: Array = []
			for x in 5: cells.append(Vector2i(x, 2))
			return cells
		Block.UpperType.FIRE_PILLAR_Y, Block.UpperType.WATER_SLASH:
			var cells_y: Array = []
			for y in 5: cells_y.append(Vector2i(2, y))
			return cells_y
		Block.UpperType.SAINT_CROSS:
			# X 形
			return [Vector2i(2, 2), Vector2i(0, 0), Vector2i(1, 1), Vector2i(3, 3), Vector2i(4, 4),
					Vector2i(0, 4), Vector2i(1, 3), Vector2i(3, 1), Vector2i(4, 0)]
		Block.UpperType.SNOWBALL:
			# 3x3 中心區
			var cells_b: Array = []
			for x in range(1, 4):
				for y in range(1, 4):
					cells_b.append(Vector2i(x, y))
			return cells_b
		Block.UpperType.ICEBALL:
			return [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
					Vector2i(1, 2),                  Vector2i(3, 2),
					Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)]
		Block.UpperType.LEAF_SHIELD:
			# 環形（3x3 外圈）
			return [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
					Vector2i(1, 2),                  Vector2i(3, 2),
					Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)]
		Block.UpperType.PORCUPINE, Block.UpperType.TURTLE, Block.UpperType.LIGHT_SHIELD:
			# 只爆自身（中心格）
			return [Vector2i(2, 2)]
		Block.UpperType.BAMBOO_SUPPLY:
			# 環形（3x3 外圈）
			return [Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1),
					Vector2i(1, 2),                  Vector2i(3, 2),
					Vector2i(1, 3), Vector2i(2, 3), Vector2i(3, 3)]
		Block.UpperType.WOOD_SPEAR_UP:
			return [Vector2i(2, 2), Vector2i(2, 1), Vector2i(2, 0), Vector2i(1, 0), Vector2i(3, 0)]
		Block.UpperType.WOOD_SPEAR_DOWN:
			return [Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(1, 4), Vector2i(3, 4)]
	return []


func _add_skill_entry(parent: VBoxContainer, type_tag: String, skill_name: String, desc: String, cooldown: int, gem_override: Texture2D, fuse_label: String, blast_pattern: Array, upgrade_kind: String = "", upgrade_index: int = 0) -> void:
	var elem_color: Color = Block.COLORS.get(_char.gem_type, Color(0.4, 0.6, 1.0))

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.12, 0.22, 1.0)
	style.border_color = Color(0.85, 0.72, 0.35)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	card.add_child(hbox)

	# ── 左：合成提示（基本元素寶石 + 4+）→ 箭頭 → 融合寶石 → 箭頭 → 爆發範圍
	if gem_override != null:
		# 合成提示徽章（基本元素寶石 + "4+" 傷害字樣）
		if fuse_label != "":
			var base_gem_tex: Texture2D = Block.GEM_TEXTURES.get(_char.gem_type, null)
			hbox.add_child(_make_fuse_hint_box(fuse_label, base_gem_tex))
			hbox.add_child(_make_arrow_label())

		# 融合寶石
		hbox.add_child(_make_gem_box(elem_color, gem_override, 64.0))

		# 爆發範圍 5x5 預覽 + 箭頭
		if blast_pattern.size() > 0:
			hbox.add_child(_make_arrow_label())
			hbox.add_child(_make_blast_preview_box(blast_pattern, elem_color))

	# 右：技能名稱、描述、冷卻
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	hbox.add_child(info)

	# 名稱列：[類型] 名稱
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	info.add_child(name_row)

	var tag_lbl := Label.new()
	tag_lbl.text = "[%s]" % type_tag
	tag_lbl.add_theme_font_size_override("font_size", 13)
	tag_lbl.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	name_row.add_child(tag_lbl)

	var nm := Label.new()
	nm.text = skill_name
	nm.add_theme_font_size_override("font_size", 20)
	nm.add_theme_color_override("font_color", Color.WHITE)
	nm.add_theme_color_override("font_outline_color", Color.BLACK)
	nm.add_theme_constant_override("outline_size", 3)
	name_row.add_child(nm)

	if upgrade_kind != "" and SkillUpgradeUtils.has_upgrades(_char, upgrade_kind, upgrade_index):
		name_row.add_child(_make_upgrade_slots(upgrade_kind, upgrade_index, 22.0))

	if cooldown > 0:
		var cd_inline := Label.new()
		cd_inline.text = "⏱︎ %d" % cooldown
		cd_inline.add_theme_font_size_override("font_size", 14)
		cd_inline.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
		cd_inline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cd_inline.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		name_row.add_child(cd_inline)

	# 描述
	if desc != "":
		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.add_theme_font_size_override("font_size", 14)
		desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc_lbl)


func _make_upgrade_slots(kind: String, skill_index: int, slot_size: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var elem_color: Color = Block.COLORS.get(_char.gem_type, Color(0.4, 0.6, 1.0))
	var max_level: int = SkillUpgradeUtils.get_max_level(_char, kind, skill_index)
	var current_level: int = SkillUpgradeUtils.get_unlocked_level(_char, kind, skill_index)
	for i in range(max_level):
		var slot := _make_upgrade_slot_button(i < current_level, elem_color, slot_size)
		slot.pressed.connect(func() -> void:
			_show_upgrade_dialog(kind, skill_index)
		)
		row.add_child(slot)
	return row


func _make_upgrade_slot_button(lit: bool, elem_color: Color, slot_size: float) -> Button:
	var btn := Button.new()
	btn.text = ""
	btn.custom_minimum_size = Vector2(slot_size, slot_size)
	btn.focus_mode = Control.FOCUS_NONE
	btn.flat = false
	btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = elem_color if lit else Color.BLACK
	style.border_color = Color(1.0, 0.86, 0.18)
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(slot_size * 0.5))
	var hover := style.duplicate() as StyleBoxFlat
	hover.bg_color = style.bg_color.lightened(0.15)
	var pressed := style.duplicate() as StyleBoxFlat
	pressed.bg_color = style.bg_color.darkened(0.12)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return btn


func _show_upgrade_dialog(kind: String, skill_index: int) -> void:
	var defs: Array[Dictionary] = SkillUpgradeUtils.get_upgrade_defs(_char, kind, skill_index)
	if defs.is_empty():
		return
	var elem_color: Color = Block.COLORS.get(_char.gem_type, Color(0.4, 0.6, 1.0))
	_upgrade_hold_token += 1
	_upgrade_hold_completed = false
	if _upgrade_hold_tween != null and _upgrade_hold_tween.is_valid():
		_upgrade_hold_tween.kill()
	var layer := CanvasLayer.new()
	layer.layer = 95
	add_child(layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.58)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			layer.queue_free()
	)
	layer.add_child(dim)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -230.0
	panel.offset_right = 230.0
	panel.offset_top = -190.0
	panel.offset_bottom = 190.0
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.12, 0.2, 0.98)
	style.border_color = Color(0.85, 0.72, 0.35)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)
	layer.set_meta("_upgrade_vbox", vbox)
	_build_upgrade_dialog_content(vbox, layer, kind, skill_index, elem_color)


func _build_upgrade_dialog_content(vbox: VBoxContainer, dialog_layer: CanvasLayer, kind: String, skill_index: int, elem_color: Color) -> void:
	var defs: Array[Dictionary] = SkillUpgradeUtils.get_upgrade_defs(_char, kind, skill_index)
	var current_level: int = SkillUpgradeUtils.get_unlocked_level(_char, kind, skill_index)
	var title := Label.new()
	title.text = Locale.tr_ui("SKILL_UPGRADE_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35))
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 3)
	vbox.add_child(title)

	for i in range(defs.size()):
		var upgrade: Dictionary = defs[i]
		var is_unlocked: bool = i < current_level
		var is_next_upgrade: bool = i == current_level and current_level < defs.size()
		var row_panel := PanelContainer.new()
		row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_panel.clip_contents = true
		var row_style := StyleBoxFlat.new()
		row_style.bg_color = Color(0.075, 0.09, 0.14, 0.92) if is_unlocked else Color(0.035, 0.04, 0.05, 0.96)
		row_style.border_color = Color(0.34, 0.38, 0.48, 0.9) if is_unlocked else Color(0.12, 0.13, 0.16, 1.0)
		row_style.set_border_width_all(1)
		row_style.set_corner_radius_all(6)
		row_style.content_margin_left = 8
		row_style.content_margin_right = 8
		row_style.content_margin_top = 7
		row_style.content_margin_bottom = 7
		row_panel.add_theme_stylebox_override("panel", row_style)
		row_panel.mouse_filter = Control.MOUSE_FILTER_STOP if is_next_upgrade else Control.MOUSE_FILTER_IGNORE
		vbox.add_child(row_panel)

		var row_body := Control.new()
		row_body.custom_minimum_size = Vector2(0.0, 48.0)
		row_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row_panel.add_child(row_body)

		var row_fill: Control = _make_upgrade_row_fill(elem_color)
		row_body.add_child(row_fill)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.z_index = 1
		row_body.add_child(row)

		var row_info: Dictionary = {
			"row": row_panel,
			"row_body": row_body,
			"row_fill": row_fill,
			"fill_ratio": 1.0 if is_unlocked else 0.0,
		}
		row_body.resized.connect(func() -> void:
			_set_upgrade_row_background_fill(row_info, float(row_info.get("fill_ratio", 0.0)))
		)

		var slot: Control = _make_upgrade_progress_slot(elem_color, 30.0, is_unlocked)
		row_info["slot"] = slot
		row.add_child(slot)

		var info: Control = _make_upgrade_fill_label(SkillUpgradeUtils.get_upgrade_text(upgrade), is_unlocked)
		row_info["text"] = info
		row.add_child(info)
		_set_upgrade_row_fill_ratio(float(row_info["fill_ratio"]), row_info)

		if is_next_upgrade:
			row_panel.gui_input.connect(_on_upgrade_hold_row_gui_input.bind(kind, skill_index, dialog_layer, row_info, elem_color))

	var cost := Label.new()
	if current_level >= defs.size():
		cost.text = Locale.tr_ui("SKILL_UPGRADE_MAXED")
	else:
		cost.text = Locale.tr_ui("SKILL_UPGRADE_COST") % [Locale.tr_ui("ITEM_SAPPHIRE"), SkillUpgradeUtils.COST_ITEM_AMOUNT]
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.add_theme_font_size_override("font_size", 14)
	cost.add_theme_color_override("font_color", Color(0.55, 0.78, 1.0))
	vbox.add_child(cost)


func _rebuild_upgrade_dialog_content(dialog_layer: CanvasLayer, kind: String, skill_index: int, elem_color: Color) -> void:
	if not is_instance_valid(dialog_layer) or not dialog_layer.has_meta("_upgrade_vbox"):
		return
	var vbox: VBoxContainer = dialog_layer.get_meta("_upgrade_vbox") as VBoxContainer
	if vbox == null:
		return
	for child in vbox.get_children():
		vbox.remove_child(child)
		child.queue_free()
	_build_upgrade_dialog_content(vbox, dialog_layer, kind, skill_index, elem_color)


func _make_upgrade_row_fill_style(_elem_color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	var bg: Color = CARD_BG_COLOR
	bg.a = 0.55
	style.bg_color = bg
	style.border_color = Color(0.85, 0.72, 0.35, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style


func _make_upgrade_row_fill(elem_color: Color) -> Control:
	var fill_clip := Control.new()
	fill_clip.clip_contents = true
	fill_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var fill_panel := PanelContainer.new()
	fill_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill_panel.add_theme_stylebox_override("panel", _make_upgrade_row_fill_style(elem_color))
	fill_clip.add_child(fill_panel)

	fill_clip.set_meta("_fill_panel", fill_panel)
	return fill_clip


func _set_upgrade_row_background_fill(row_info: Dictionary, ratio: float) -> void:
	var row_body: Control = row_info.get("row_body", null) as Control
	var fill_clip: Control = row_info.get("row_fill", null) as Control
	if row_body == null or fill_clip == null or not fill_clip.has_meta("_fill_panel"):
		return
	var fill_panel: PanelContainer = fill_clip.get_meta("_fill_panel") as PanelContainer
	if fill_panel == null:
		return
	var body_size: Vector2 = row_body.size
	if body_size.x <= 0.0 or body_size.y <= 0.0:
		body_size = row_body.custom_minimum_size
	var fill_w: float = body_size.x * clampf(ratio, 0.0, 1.0)
	fill_clip.position = Vector2.ZERO
	fill_clip.size = Vector2(fill_w, body_size.y)
	fill_panel.position = Vector2.ZERO
	fill_panel.size = body_size


func _make_upgrade_slot_style(color: Color, slot_size: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(1.0, 0.86, 0.18)
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(slot_size * 0.5))
	return style


func _make_upgrade_progress_slot(elem_color: Color, slot_size: float, filled: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(slot_size, slot_size)
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var base := PanelContainer.new()
	base.set_anchors_preset(Control.PRESET_FULL_RECT)
	base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	base.add_theme_stylebox_override("panel", _make_upgrade_slot_style(UPGRADE_SLOT_DARK, slot_size))
	holder.add_child(base)

	var fill_clip := Control.new()
	fill_clip.clip_contents = true
	fill_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(fill_clip)

	var fill_panel := PanelContainer.new()
	fill_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill_panel.add_theme_stylebox_override("panel", _make_upgrade_slot_style(CARD_BG_COLOR, slot_size))
	fill_clip.add_child(fill_panel)

	holder.set_meta("_fill_clip", fill_clip)
	holder.set_meta("_fill_panel", fill_panel)
	holder.resized.connect(func() -> void:
		_set_upgrade_slot_fill(holder, 1.0 if filled else float(holder.get_meta("_fill_ratio", 0.0)))
	)
	_set_upgrade_slot_fill(holder, 1.0 if filled else 0.0)
	return holder


func _set_upgrade_slot_fill(slot: Control, ratio: float) -> void:
	if slot == null:
		return
	slot.set_meta("_fill_ratio", ratio)
	if not slot.has_meta("_fill_clip") or not slot.has_meta("_fill_panel"):
		return
	var fill_clip: Control = slot.get_meta("_fill_clip") as Control
	var fill_panel: Control = slot.get_meta("_fill_panel") as Control
	if fill_clip == null or fill_panel == null:
		return
	var slot_size: Vector2 = slot.size
	if slot_size.x <= 0.0 or slot_size.y <= 0.0:
		slot_size = slot.custom_minimum_size
	var fill_w: float = slot_size.x * clampf(ratio, 0.0, 1.0)
	fill_clip.position = Vector2.ZERO
	fill_clip.size = Vector2(fill_w, slot_size.y)
	fill_panel.position = Vector2.ZERO
	fill_panel.size = slot_size


func _make_upgrade_fill_label(text: String, filled: bool) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0.0, 48.0)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var dark_label := Label.new()
	dark_label.text = text
	dark_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dark_label.add_theme_font_size_override("font_size", 16)
	dark_label.add_theme_color_override("font_color", UPGRADE_TEXT_UNLOCKED if filled else UPGRADE_TEXT_DARK)
	dark_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(dark_label)

	var fill_clip := Control.new()
	fill_clip.clip_contents = true
	fill_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(fill_clip)

	var light_label := Label.new()
	light_label.text = text
	light_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	light_label.add_theme_font_size_override("font_size", 16)
	light_label.add_theme_color_override("font_color", UPGRADE_TEXT_LIGHT)
	light_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fill_clip.add_child(light_label)

	holder.set_meta("_dark_label", dark_label)
	holder.set_meta("_fill_clip", fill_clip)
	holder.set_meta("_light_label", light_label)
	holder.resized.connect(func() -> void:
		_set_upgrade_text_fill(holder, float(holder.get_meta("_fill_ratio", 1.0 if filled else 0.0)))
	)
	_set_upgrade_text_fill(holder, 1.0 if filled else 0.0)
	return holder


func _set_upgrade_text_fill(holder: Control, ratio: float) -> void:
	if holder == null:
		return
	holder.set_meta("_fill_ratio", ratio)
	if not holder.has_meta("_dark_label") or not holder.has_meta("_fill_clip") or not holder.has_meta("_light_label"):
		return
	var dark_label: Label = holder.get_meta("_dark_label") as Label
	var fill_clip: Control = holder.get_meta("_fill_clip") as Control
	var light_label: Label = holder.get_meta("_light_label") as Label
	if dark_label == null or fill_clip == null or light_label == null:
		return
	var holder_size: Vector2 = holder.size
	if holder_size.x <= 0.0 or holder_size.y <= 0.0:
		holder_size = holder.custom_minimum_size
	dark_label.position = Vector2.ZERO
	dark_label.size = holder_size
	var fill_w: float = holder_size.x * clampf(ratio, 0.0, 1.0)
	fill_clip.position = Vector2.ZERO
	fill_clip.size = Vector2(fill_w, holder_size.y)
	light_label.position = Vector2.ZERO
	light_label.size = holder_size


func _set_upgrade_row_fill_ratio(ratio: float, row_info: Dictionary) -> void:
	var clamped: float = clampf(ratio, 0.0, 1.0)
	row_info["fill_ratio"] = clamped
	var slot: Control = row_info.get("slot", null) as Control
	var text_holder: Control = row_info.get("text", null) as Control
	_set_upgrade_row_background_fill(row_info, clamped)
	_set_upgrade_slot_fill(slot, clamped)
	_set_upgrade_text_fill(text_holder, clamped)


func _on_upgrade_hold_row_gui_input(event: InputEvent, kind: String, skill_index: int, dialog_layer: CanvasLayer, row_info: Dictionary, elem_color: Color) -> void:
	if _upgrade_hold_completed:
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event as InputEventMouseButton
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		if mouse_event.pressed:
			_start_upgrade_hold(kind, skill_index, dialog_layer, row_info, elem_color)
		else:
			_cancel_upgrade_hold(row_info)


func _start_upgrade_hold(kind: String, skill_index: int, dialog_layer: CanvasLayer, row_info: Dictionary, elem_color: Color) -> void:
	var item_name: String = Locale.tr_ui("ITEM_SAPPHIRE")
	if GameState.get_inventory_count(SkillUpgradeUtils.COST_ITEM_TYPE) < SkillUpgradeUtils.COST_ITEM_AMOUNT:
		_show_message_dialog(Locale.tr_ui("SKILL_UPGRADE_NOT_ENOUGH") % item_name)
		return
	_upgrade_hold_token += 1
	var token: int = _upgrade_hold_token
	if _upgrade_hold_tween != null and _upgrade_hold_tween.is_valid():
		_upgrade_hold_tween.kill()
	_set_upgrade_row_fill_ratio(0.0, row_info)
	_upgrade_hold_tween = create_tween()
	_upgrade_hold_tween.tween_method(Callable(self, "_set_upgrade_row_fill_ratio").bind(row_info), 0.0, 1.0, UPGRADE_HOLD_DURATION) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_run_upgrade_hold_completion(kind, skill_index, dialog_layer, row_info, elem_color, token)


func _cancel_upgrade_hold(row_info: Dictionary) -> void:
	if _upgrade_hold_completed:
		return
	if float(row_info.get("fill_ratio", 0.0)) >= 0.999:
		return
	_upgrade_hold_token += 1
	if _upgrade_hold_tween != null and _upgrade_hold_tween.is_valid():
		_upgrade_hold_tween.kill()
	var current_ratio: float = float(row_info.get("fill_ratio", 0.0))
	_upgrade_hold_tween = create_tween()
	_upgrade_hold_tween.tween_method(Callable(self, "_set_upgrade_row_fill_ratio").bind(row_info), current_ratio, 0.0, 0.14) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

func _run_upgrade_hold_completion(kind: String, skill_index: int, dialog_layer: CanvasLayer, row_info: Dictionary, elem_color: Color, token: int) -> void:
	if _upgrade_hold_tween == null:
		return
	await _upgrade_hold_tween.finished
	if token != _upgrade_hold_token or _upgrade_hold_completed:
		return
	_upgrade_hold_completed = true
	var result: Dictionary = GameState.try_upgrade_skill(_char, kind, skill_index)
	if bool(result.get("ok", false)):
		_set_upgrade_row_fill_ratio(1.0, row_info)
		await _play_upgrade_hold_success(row_info, elem_color, dialog_layer)
		_rebuild_ui_preserving_upgrade_dialog(dialog_layer)
		_rebuild_upgrade_dialog_content(dialog_layer, kind, skill_index, elem_color)
		_upgrade_hold_completed = false
	else:
		_upgrade_hold_completed = false
		_set_upgrade_row_fill_ratio(0.0, row_info)
		_show_message_dialog(_upgrade_error_text(str(result.get("reason", ""))))


func _play_upgrade_hold_success(row_info: Dictionary, elem_color: Color, dialog_layer: CanvasLayer) -> void:
	var slot: Control = row_info.get("slot", null) as Control
	var text_holder: Control = row_info.get("text", null) as Control
	if slot != null:
		slot.pivot_offset = slot.size * 0.5
	if text_holder != null:
		text_holder.pivot_offset = text_holder.size * 0.5
	_spawn_upgrade_confetti(row_info, elem_color, dialog_layer)
	var tw := create_tween().set_parallel(true)
	if slot != null:
		tw.tween_property(slot, "scale", Vector2(1.26, 1.26), 0.13).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(slot, "scale", Vector2.ONE, 0.16).set_delay(0.13).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	if text_holder != null:
		tw.tween_property(text_holder, "scale", Vector2(1.045, 1.045), 0.13).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_property(text_holder, "scale", Vector2.ONE, 0.16).set_delay(0.13).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await get_tree().create_timer(0.55).timeout


func _spawn_upgrade_confetti(row_info: Dictionary, elem_color: Color, dialog_layer: CanvasLayer) -> void:
	if not is_instance_valid(dialog_layer):
		return
	var row: Control = row_info.get("row", null) as Control
	if row == null:
		return
	var origin: Vector2 = row.get_global_rect().get_center()
	var colors: Array[Color] = [
		elem_color.lightened(0.25),
		Color(1.0, 0.86, 0.22, 1.0),
		Color(0.95, 0.95, 1.0, 1.0),
		elem_color.darkened(0.1),
	]
	for i in range(30):
		var piece := ColorRect.new()
		piece.color = colors[i % colors.size()]
		piece.size = Vector2(randf_range(4.0, 8.0), randf_range(8.0, 15.0))
		piece.position = origin
		piece.pivot_offset = piece.size * 0.5
		piece.rotation = randf_range(0.0, TAU)
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dialog_layer.add_child(piece)

		var angle: float = randf_range(-PI, 0.0)
		var distance: float = randf_range(70.0, 160.0)
		var end_pos: Vector2 = origin + Vector2(cos(angle), sin(angle)) * distance + Vector2(randf_range(-34.0, 34.0), randf_range(-14.0, 70.0))
		var spin: float = piece.rotation + randf_range(-5.5, 5.5)
		var tw := piece.create_tween().set_parallel(true)
		tw.tween_property(piece, "position", end_pos, randf_range(0.42, 0.68)).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(piece, "rotation", spin, 0.62).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(piece, "modulate:a", 0.0, 0.24).set_delay(0.36)
		tw.finished.connect(func() -> void:
			if is_instance_valid(piece):
				piece.queue_free()
		, CONNECT_ONE_SHOT)


func _show_message_dialog(message: String) -> void:
	var dialog := AcceptDialog.new()
	dialog.title = Locale.tr_ui("SKILL_UPGRADE_TITLE")
	dialog.dialog_text = message
	dialog.ok_button_text = Locale.tr_ui("CONFIRM")
	add_child(dialog)
	dialog.popup_centered(Vector2i(320, 140))


func _upgrade_error_text(reason: String) -> String:
	if reason == "MAX_LEVEL":
		return Locale.tr_ui("SKILL_UPGRADE_MAXED")
	if reason == "NOT_ENOUGH_ITEM":
		return Locale.tr_ui("SKILL_UPGRADE_NOT_ENOUGH") % Locale.tr_ui("ITEM_SAPPHIRE")
	return reason


func _rebuild_ui() -> void:
	for child in get_children():
		child.queue_free()
	_build_ui()


func _rebuild_ui_preserving_upgrade_dialog(dialog_layer: CanvasLayer) -> void:
	var should_restore: bool = is_instance_valid(dialog_layer) and dialog_layer.get_parent() == self
	if should_restore:
		remove_child(dialog_layer)
	_rebuild_ui()
	if should_restore and is_instance_valid(dialog_layer):
		add_child(dialog_layer)


# ── 技能條輔助元件 ─────────────────────────────────────────

func _make_gem_box(elem_color: Color, tex: Texture2D, gem_size: float) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var gem := TextureRect.new()
	gem.texture = tex
	gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gem.custom_minimum_size = Vector2(gem_size, gem_size)
	gem.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(gem)

	# 與「合成提示」/「爆發範圍」一致的下方標題
	var caption := Label.new()
	caption.text = Locale.tr_ui("UPPER_GEM")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	v.add_child(caption)

	# 避免未使用警告（保留參數以維持簽名一致）
	var _ec := elem_color
	return v


func _make_arrow_label() -> Label:
	var arrow := Label.new()
	arrow.text = "▶"
	arrow.add_theme_font_size_override("font_size", 18)
	arrow.add_theme_color_override("font_color", Color(0.85, 0.72, 0.35))
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return arrow


func _make_fuse_hint_box(fuse_label: String, base_gem_tex: Texture2D) -> Control:
	# 外層容器：上方寶石+數字疊圖、下方文字標題
	var gem_size: float = 64.0
	var wrap := VBoxContainer.new()
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	wrap.add_theme_constant_override("separation", 2)
	wrap.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# 寶石 + 「N+」字樣以 Control 疊放
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(gem_size, gem_size)
	wrap.add_child(stack)

	if base_gem_tex != null:
		var gem := TextureRect.new()
		gem.texture = base_gem_tex
		gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		gem.set_anchors_preset(Control.PRESET_FULL_RECT)
		stack.add_child(gem)

	# 「N+」傷害字樣（Russo One、白字、黑色描邊+陰影）
	var num := Label.new()
	num.text = "%s+" % fuse_label
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dmg_font: Font = load("res://assets/fonts/game_ui_font.tres")
	if dmg_font != null:
		num.add_theme_font_override("font", dmg_font)
	num.add_theme_font_size_override("font_size", 30)
	num.add_theme_color_override("font_color", Color.WHITE)
	num.add_theme_color_override("font_outline_color", Color.BLACK)
	num.add_theme_constant_override("outline_size", 5)
	num.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	num.add_theme_constant_override("shadow_offset_x", 2)
	num.add_theme_constant_override("shadow_offset_y", 2)
	stack.add_child(num)

	# 下方標題「合成提示」
	var hint := Label.new()
	hint.text = Locale.tr_ui("FUSE_HINT")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	wrap.add_child(hint)

	return wrap


func _make_blast_preview_box(pattern: Array, elem_color: Color) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	# 5x5 grid（GridContainer + 25 個 ColorRect）
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 1)
	grid.add_theme_constant_override("v_separation", 1)
	v.add_child(grid)

	var hit: Dictionary = {}
	for p in pattern:
		hit[p] = true

	var cell: float = 11.0
	var fill_col: Color = elem_color
	fill_col.a = 1.0
	var empty_col: Color = Color(0.13, 0.15, 0.22, 1.0)
	for y in 5:
		for x in 5:
			var rect := ColorRect.new()
			rect.custom_minimum_size = Vector2(cell, cell)
			rect.color = fill_col if hit.has(Vector2i(x, y)) else empty_col
			grid.add_child(rect)

	var caption := Label.new()
	caption.text = Locale.tr_ui("BLAST_AREA")
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	v.add_child(caption)

	return v


func _on_back_pressed() -> void:
	_play_close_animation()


# ── Zoom 動畫 ──────────────────────────────────────────────────

func _play_open_animation() -> void:
	if _card == null:
		return
	_card.scale = Vector2(0.6, 0.6)
	_card.modulate.a = 0.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_card, "scale", Vector2.ONE, ENTER_DUR) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_card, "modulate:a", 1.0, ENTER_DUR * 0.6)
	# 開場 SE
	var sfx := AudioStreamPlayer.new()
	sfx.stream = SE_OPEN
	sfx.finished.connect(sfx.queue_free)
	add_child(sfx)
	sfx.play()


func _play_close_animation() -> void:
	if _closing:
		return
	_closing = true
	if _card == null:
		_emit_close()
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_card, "scale", Vector2(0.6, 0.6), EXIT_DUR) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_card, "modulate:a", 0.0, EXIT_DUR)
	tw.chain().tween_callback(_emit_close)


func _emit_close() -> void:
	if get_tree().current_scene == self:
		get_tree().change_scene_to_file("res://scenes/characters.tscn")
	else:
		closed.emit()
