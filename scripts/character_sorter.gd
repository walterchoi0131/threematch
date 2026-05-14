## CharacterSorter — 角色列表排序共用工具。
## 提供排序模式列舉、排序函數、以及生成排序按鈕列。
## 由 characters_screen.gd 與 prepare_screen.gd 共用。
class_name CharacterSorter
extends RefCounted

enum Mode { LEVEL, ATK, HP, MAGIC, TYPE }
const ELEMENT_FILTER_ALL := -1


## 對 (index, character) 配對陣列排序，回傳排序後的新陣列。
## 每個項目格式：{ "i": int (原始索引), "c": CharacterData }
## ascending: true → 由小至大；false → 由大至小（預設值）。
static func sort_indexed(chars: Array, mode: int, ascending: bool = false) -> Array:
	var indexed: Array = []
	for i in chars.size():
		indexed.append({"i": i, "c": chars[i]})

	match mode:
		Mode.LEVEL:
			indexed.sort_custom(func(a, b) -> bool:
				return a.c.level < b.c.level if ascending else a.c.level > b.c.level)
		Mode.ATK:
			indexed.sort_custom(func(a, b) -> bool:
				return a.c.get_atk() < b.c.get_atk() if ascending else a.c.get_atk() > b.c.get_atk())
		Mode.HP:
			indexed.sort_custom(func(a, b) -> bool:
				return a.c.get_max_hp() < b.c.get_max_hp() if ascending else a.c.get_max_hp() > b.c.get_max_hp())
		Mode.MAGIC:
			indexed.sort_custom(func(a, b) -> bool:
				return a.c.get_magic() < b.c.get_magic() if ascending else a.c.get_magic() > b.c.get_magic())
		Mode.TYPE:
			indexed.sort_custom(func(a, b) -> bool:
				return int(a.c.gem_type) < int(b.c.gem_type) if ascending else int(a.c.gem_type) > int(b.c.gem_type))
	return indexed


## 建立排序按鈕列。on_changed 接收 (mode: int, ascending: bool)。
## 點擊已選中的按鈕會切換升降冪；點擊其他按鈕則切到該模式並重設為降冪（TYPE 預設升冪）。
static func make_sort_buttons(initial_mode: int, on_changed: Callable, initial_ascending: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var entries: Array = [
		{"k": "SORT_LEVEL", "m": Mode.LEVEL},
		{"k": "SORT_ATK", "m": Mode.ATK},
		{"k": "SORT_HP", "m": Mode.HP},
		{"k": "SORT_MAGIC", "m": Mode.MAGIC},
		{"k": "SORT_TYPE", "m": Mode.TYPE},
	]
	# 共用狀態：當前模式 + 升降冪
	var state: Dictionary = {"mode": initial_mode, "asc": initial_ascending}
	var btns: Array = []   # [{btn, mode, base_text}]

	var refresh_labels := func() -> void:
		for info: Dictionary in btns:
			var b: Button = info.btn
			var base: String = info.base_text
			var m: int = info.mode
			if m == state.mode:
				b.text = "%s %s" % [base, "▲" if state.asc else "▼"]
				b.button_pressed = true
			else:
				b.text = base
				b.button_pressed = false

	for entry: Dictionary in entries:
		var btn := Button.new()
		var base_text: String = Locale.tr_ui(entry.k)
		btn.text = base_text
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(72, 28)
		var m: int = entry.m
		btn.pressed.connect(func() -> void:
			if state.mode == m:
				state.asc = not state.asc
			else:
				state.mode = m
				state.asc = (m == Mode.TYPE)  # TYPE 預設升冪，其餘降冪
			refresh_labels.call()
			on_changed.call(state.mode, state.asc)
		)
		row.add_child(btn)
		btns.append({"btn": btn, "mode": m, "base_text": base_text})

	refresh_labels.call()
	return row


## 建立「下拉式」排序選擇器：單一按鈕，點擊彈出選單。
## 行為：點選與當前相同模式 → 切換升降冪；點選不同模式 → 切到該模式並重設預設冪。
static func make_sort_dropdown(initial_mode: int, on_changed: Callable, initial_ascending: bool = false) -> Button:
	var entries: Array = [
		{"k": "SORT_LEVEL", "m": Mode.LEVEL},
		{"k": "SORT_ATK", "m": Mode.ATK},
		{"k": "SORT_HP", "m": Mode.HP},
		{"k": "SORT_MAGIC", "m": Mode.MAGIC},
		{"k": "SORT_TYPE", "m": Mode.TYPE},
	]
	var state: Dictionary = {"mode": initial_mode, "asc": initial_ascending}

	var btn := Button.new()
	btn.toggle_mode = false
	btn.custom_minimum_size = Vector2(120, 32)
	btn.focus_mode = Control.FOCUS_NONE

	# 深色圓角按鈕樣式（仿圖示風格）
	for st: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		var base := Color(0.12, 0.10, 0.16, 0.95)
		if st == "hover":
			base = base.lightened(0.1)
		elif st == "pressed":
			base = base.darkened(0.15)
		sb.bg_color = base
		sb.set_corner_radius_all(10)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.45, 0.35, 0.55, 0.95)
		sb.set_content_margin_all(8)
		btn.add_theme_stylebox_override(st, sb)
	btn.add_theme_color_override("font_color", Color(0.92, 0.92, 0.96))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)

	var popup := PopupMenu.new()
	btn.add_child(popup)
	for entry: Dictionary in entries:
		popup.add_item(Locale.tr_ui(entry.k), entry.m)

	var refresh := func() -> void:
		for entry: Dictionary in entries:
			if entry.m == state.mode:
				btn.text = "%s %s" % [Locale.tr_ui(entry.k), "▲" if state.asc else "▼"]
				break

	btn.pressed.connect(func() -> void:
		var pos: Vector2 = btn.get_screen_position() + Vector2(0.0, btn.size.y)
		popup.position = Vector2i(pos)
		popup.popup()
	)
	popup.id_pressed.connect(func(id: int) -> void:
		if state.mode == id:
			state.asc = not state.asc
		else:
			state.mode = id
			state.asc = (id == Mode.TYPE)
		refresh.call()
		on_changed.call(state.mode, state.asc)
	)
	refresh.call()
	return btn


## 建立獨立元素篩選列：全部 + 目前名冊中存在的元素圖示。
## on_changed 接收 (element_filter: int)，ELEMENT_FILTER_ALL 代表不篩選。
static func make_element_filter_bar(initial_filter: int, on_changed: Callable, characters: Array = []) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_SHRINK_END

	var state: Dictionary = {"filter": initial_filter}
	var btns: Array[Dictionary] = []

	var all_btn := Button.new()
	all_btn.text = Locale.tr_ui("ALL")
	all_btn.toggle_mode = true
	all_btn.focus_mode = Control.FOCUS_NONE
	all_btn.custom_minimum_size = Vector2(52, 32)
	row.add_child(all_btn)
	btns.append({"btn": all_btn, "filter": ELEMENT_FILTER_ALL, "color": Color(0.22, 0.22, 0.28, 1.0)})

	for element_type: int in get_element_filter_order(characters):
		var btn := Button.new()
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(38, 32)
		var tex: Texture2D = Block.GEM_TEXTURES.get(element_type)
		if tex != null:
			btn.icon = tex
		else:
			btn.text = str(Block.ICONS.get(element_type, "?"))
		row.add_child(btn)
		var element_color: Color = Block.COLORS.get(element_type, Color.GRAY)
		btns.append({"btn": btn, "filter": element_type, "color": element_color})

	var refresh := func() -> void:
		for info: Dictionary in btns:
			var btn: Button = info.btn
			var filter_value: int = int(info.filter)
			var selected: bool = filter_value == int(state.filter)
			btn.button_pressed = selected
			_apply_filter_button_style(btn, info.color, selected)

	for info: Dictionary in btns:
		var btn: Button = info.btn
		var filter_value: int = int(info.filter)
		btn.pressed.connect(func() -> void:
			state.filter = filter_value
			refresh.call()
			on_changed.call(filter_value)
		)

	refresh.call()
	return row


static func get_element_filter_order(characters: Array) -> Array[int]:
	var preferred: Array[int] = [
		Block.Type.LIGHT,
		Block.Type.RED,
		Block.Type.GREEN,
		Block.Type.BLUE,
		Block.Type.DARK,
		Block.Type.YELLOW,
		Block.Type.PURPLE,
		Block.Type.ORANGE,
	]
	var present: Dictionary = {}
	for item in characters:
		if item == null or item is not CharacterData:
			continue
		var c: CharacterData = item as CharacterData
		var element_type: int = int(c.gem_type)
		if element_type >= 0 and element_type < int(Block.Type.PLANK):
			present[element_type] = true

	var order: Array[int] = []
	for element_type: int in preferred:
		if present.has(element_type):
			order.append(element_type)
	for key in present.keys():
		var element_type: int = int(key)
		if not order.has(element_type):
			order.append(element_type)
	return order


static func _apply_filter_button_style(btn: Button, base_color: Color, selected: bool) -> void:
	for state_name: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		var bg_color: Color = Color(0.10, 0.10, 0.13, 0.92)
		var border_color: Color = Color(base_color.r, base_color.g, base_color.b, 0.72)
		if selected:
			bg_color = Color(base_color.r, base_color.g, base_color.b, 0.72)
			border_color = Color(base_color.r, base_color.g, base_color.b, 1.0).lightened(0.25)
		if state_name == "hover":
			bg_color = bg_color.lightened(0.10)
		elif state_name == "pressed":
			bg_color = bg_color.darkened(0.12)
		sb.bg_color = bg_color
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(2)
		sb.border_color = border_color
		sb.set_content_margin_all(5)
		btn.add_theme_stylebox_override(state_name, sb)
	btn.add_theme_color_override("font_color", Color(0.95, 0.95, 0.98))
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
