## ItemDefs — 掉落物品定義表。
## 集中管理所有 Item 類型的名稱、顏色等元資料。
class_name ItemDefs
extends RefCounted

enum Type {
	GOLD,
	SAPPHIRE,
}

class Def:
	var display_name: String
	var color: Color

	func _init(p_display_name: String, p_color: Color) -> void:
		display_name = p_display_name
		color = p_color


static var _defs: Dictionary = {}
static var _initialized := false


static func _ensure_init() -> void:
	if _initialized:
		return
	_initialized = true
	_defs[Type.GOLD]     = Def.new("Gold",     Color(1.0, 0.85, 0.15))
	_defs[Type.SAPPHIRE] = Def.new("Sapphire", Color(0.25, 0.55, 1.0))


static func get_def(type: Type) -> Def:
	_ensure_init()
	return _defs.get(type)


static func get_display_name(type: Type) -> String:
	_ensure_init()
	var d: Def = _defs.get(type)
	return d.display_name if d != null else "Unknown"


static func get_color(type: Type) -> Color:
	_ensure_init()
	var d: Def = _defs.get(type)
	return d.color if d != null else Color.WHITE
