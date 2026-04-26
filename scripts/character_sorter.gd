## CharacterSorter — 角色列表排序共用工具。
## 提供排序模式列舉、排序函數、以及生成排序按鈕列。
## 由 characters_screen.gd 與 prepare_screen.gd 共用。
class_name CharacterSorter
extends RefCounted

enum Mode { LEVEL, ATK, HP, MAGIC, TYPE }


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
