## CharacterSorter — 角色列表排序共用工具。
## 提供排序模式列舉、排序函數、以及生成排序按鈕列。
## 由 characters_screen.gd 與 prepare_screen.gd 共用。
class_name CharacterSorter
extends RefCounted

enum Mode { LEVEL, ATK, HP, TYPE }


## 對 (index, character) 配對陣列排序，回傳排序後的新陣列。
## 每個項目格式：{ "i": int (原始索引), "c": CharacterData }
static func sort_indexed(chars: Array, mode: int) -> Array:
	var indexed: Array = []
	for i in chars.size():
		indexed.append({"i": i, "c": chars[i]})

	match mode:
		Mode.LEVEL:
			indexed.sort_custom(func(a, b) -> bool: return a.c.level > b.c.level)
		Mode.ATK:
			indexed.sort_custom(func(a, b) -> bool: return a.c.get_atk() > b.c.get_atk())
		Mode.HP:
			indexed.sort_custom(func(a, b) -> bool: return a.c.get_max_hp() > b.c.get_max_hp())
		Mode.TYPE:
			indexed.sort_custom(func(a, b) -> bool: return int(a.c.gem_type) < int(b.c.gem_type))
	return indexed


## 建立排序按鈕列。on_changed 接收一個參數 (mode: int)。
## 預設選中 initial_mode 對應的按鈕。
static func make_sort_buttons(initial_mode: int, on_changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var entries: Array = [
		{"k": "SORT_LEVEL", "m": Mode.LEVEL},
		{"k": "SORT_ATK", "m": Mode.ATK},
		{"k": "SORT_HP", "m": Mode.HP},
		{"k": "SORT_TYPE", "m": Mode.TYPE},
	]
	var btns: Array = []
	for entry: Dictionary in entries:
		var btn := Button.new()
		btn.text = Locale.tr_ui(entry.k)
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(56, 28)
		var m: int = entry.m
		btn.pressed.connect(func() -> void:
			for b: Button in btns:
				b.button_pressed = (b == btn)
			on_changed.call(m)
		)
		if m == initial_mode:
			btn.button_pressed = true
		row.add_child(btn)
		btns.append(btn)
	return row
