## CharacterDetail（角色詳細畫面）— 顯示單一角色的完整資訊。
## 包括頭像、名稱、等級、攻擊/血量、各類技能等。
extends Node2D

var _char: CharacterData  # 要顯示的角色資料


func _ready() -> void:
	_char = GameState.detail_character
	if _char == null:
		get_tree().change_scene_to_file("res://scenes/characters.tscn")
		return
	_build_ui()


func _build_ui() -> void:
	# Background
	var bg := ColorRect.new()
	bg.offset_right = 576.0
	bg.offset_bottom = 1024.0
	bg.color = Color(0.09, 0.09, 0.14, 1)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var layer := CanvasLayer.new()
	add_child(layer)

	var scroll := ScrollContainer.new()
	scroll.offset_left = 0.0
	scroll.offset_top = 0.0
	scroll.offset_right = 576.0
	scroll.offset_bottom = 920.0
	layer.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.custom_minimum_size = Vector2(576, 0)
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)

	# ── Top spacing ──
	var spacer_top := Control.new()
	spacer_top.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer_top)

	# ── Portrait (large, centered) ──
	var portrait_container := CenterContainer.new()
	portrait_container.custom_minimum_size = Vector2(576, 300)
	vbox.add_child(portrait_container)

	if _char.portrait_texture:
		var portrait := TextureRect.new()
		portrait.texture = _char.portrait_texture
		portrait.custom_minimum_size = Vector2(260, 280)
		portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait_container.add_child(portrait)
	else:
		var portrait := ColorRect.new()
		portrait.custom_minimum_size = Vector2(260, 280)
		portrait.color = _char.portrait_color
		portrait_container.add_child(portrait)

	# ── Name ──
	var name_lbl := Label.new()
	name_lbl.text = _char.character_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 32)
	name_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	vbox.add_child(name_lbl)

	# ── Level ──
	var lv_lbl := Label.new()
	lv_lbl.text = "Lv. %d" % _char.level
	lv_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv_lbl.add_theme_font_size_override("font_size", 18)
	lv_lbl.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	vbox.add_child(lv_lbl)

	# ── Separator ──
	var sep1 := HSeparator.new()
	sep1.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(sep1)

	# ── Stats row ──
	var stats_box := HBoxContainer.new()
	stats_box.alignment = BoxContainer.ALIGNMENT_CENTER
	stats_box.add_theme_constant_override("separation", 60)
	vbox.add_child(stats_box)

	var atk_lbl := Label.new()
	atk_lbl.text = "ATK  %d" % _char.get_atk()
	atk_lbl.add_theme_font_size_override("font_size", 22)
	atk_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.3))
	stats_box.add_child(atk_lbl)

	var hp_lbl := Label.new()
	hp_lbl.text = "HP  %d" % _char.get_max_hp()
	hp_lbl.add_theme_font_size_override("font_size", 22)
	hp_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.4))
	stats_box.add_child(hp_lbl)

	# ── Separator ──
	var sep2 := HSeparator.new()
	sep2.custom_minimum_size = Vector2(0, 8)
	vbox.add_child(sep2)

	# ── Skills section ──
	var skills_title := Label.new()
	skills_title.text = "Skills"
	skills_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	skills_title.add_theme_font_size_override("font_size", 24)
	skills_title.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	vbox.add_child(skills_title)

	# Passive
	if _char.passive_skill_name != "":
		_add_skill_entry(vbox, "Passive", _char.passive_skill_name, _char.passive_skill_desc, Color(0.3, 0.75, 0.95))

	# Active
	if _char.active_skill_name != "":
		_add_skill_entry(vbox, "Active", _char.active_skill_name, _char.active_skill_desc, Color(1.0, 0.65, 0.2))

	# Responding — iterate the array of responding skills
	for skill: Dictionary in _char.responding_skills:
		var sname: String = skill.get("name", "")
		var sdesc: String = skill.get("desc", "")
		if sname != "":
			_add_skill_entry(vbox, "Responding", sname, sdesc, Color(0.6, 0.9, 0.4))

	# ── Back button ──
	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.offset_left = 200.0
	back_btn.offset_top = 940.0
	back_btn.offset_right = 376.0
	back_btn.offset_bottom = 980.0
	back_btn.pressed.connect(_on_back_pressed)
	layer.add_child(back_btn)


func _add_skill_entry(parent: VBoxContainer, type_tag: String, skill_name: String, desc: String, tag_color: Color) -> void:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	parent.add_child(margin)

	var card := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.14, 0.22, 1)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_right = 6
	style.corner_radius_bottom_left = 6
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	card.add_theme_stylebox_override("panel", style)
	margin.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)

	# Tag + name row
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)

	var tag := Label.new()
	tag.text = "[%s]" % type_tag
	tag.add_theme_font_size_override("font_size", 13)
	tag.add_theme_color_override("font_color", tag_color)
	row.add_child(tag)

	var nm := Label.new()
	nm.text = skill_name
	nm.add_theme_font_size_override("font_size", 16)
	nm.add_theme_color_override("font_color", Color(1, 1, 1))
	row.add_child(nm)

	# Description
	if desc != "":
		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.add_theme_font_size_override("font_size", 13)
		desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(desc_lbl)


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/characters.tscn")
