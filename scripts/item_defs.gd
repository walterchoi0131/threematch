## ItemDefs — 掉落物品定義表。
## 集中管理所有 Item 類型的名稱、顏色等元資料。
class_name ItemDefs
extends RefCounted

const SAPPHIRE_IMAGE := preload("res://assets/blocks/puzzle_key_gem.png")
const SAPPHIRE_SHINING_COLOR := Color(0.43, 0.83, 0.79, 0.62)

enum Type {
	GOLD,
	SAPPHIRE,
}

class Def:
	var name: String
	var display_name: String
	var color: Color
	var image: Texture2D
	var shining_color: Variant
	var size_multiplier: float

	func _init(p_name: String, p_display_name: String, p_color: Color, p_image: Texture2D = null, p_shining_color: Variant = null, p_size_multiplier: float = 1.0) -> void:
		name = p_name
		display_name = p_display_name
		color = p_color
		image = p_image
		shining_color = p_shining_color
		size_multiplier = maxf(0.1, p_size_multiplier)


static var _defs: Dictionary = {}
static var _initialized := false


static func _ensure_init() -> void:
	if _initialized:
		return
	_initialized = true
	_defs[Type.GOLD]     = Def.new("gold", "Gold", Color(1.0, 0.85, 0.15))
	_defs[Type.SAPPHIRE] = Def.new("sapphire", "Sapphire", Color(0.25, 0.55, 1.0), SAPPHIRE_IMAGE, SAPPHIRE_SHINING_COLOR, 1.5)


static func get_def(type: Type) -> Def:
	_ensure_init()
	return _defs.get(type)


static func get_display_name(type: Type) -> String:
	_ensure_init()
	var d: Def = _defs.get(type)
	return d.display_name if d != null else "Unknown"


static func get_name(type: Type) -> String:
	_ensure_init()
	var d: Def = _defs.get(type)
	return d.name if d != null else "unknown"


static func get_color(type: Type) -> Color:
	_ensure_init()
	var d: Def = _defs.get(type)
	return d.color if d != null else Color.WHITE


static func get_image(type: Type) -> Texture2D:
	_ensure_init()
	var d: Def = _defs.get(type)
	return d.image if d != null else null


static func get_shining_color(type: Type) -> Variant:
	_ensure_init()
	var d: Def = _defs.get(type)
	return d.shining_color if d != null else null


static func get_size_multiplier(type: Type) -> float:
	_ensure_init()
	var d: Def = _defs.get(type)
	return d.size_multiplier if d != null else 1.0
