## UpperGemDefs — 高階寶石定義表。
## 集中管理每種 UpperType 的元素類型、預覽色、顯示名稱等。
class_name UpperGemDefs
extends RefCounted

## 單一高階寶石的定義
class Def:
	var element: Block.Type        ## 對應的寶石元素類型
	var preview_color: Color       ## 預覽模式覆蓋層顏色
	var display_name: String       ## 顯示名稱
	# ── 爆炸 VFX（可選，空路徑 = 不播放）──
	var blast_vfx_path: String     ## sprite sheet 資源路徑
	var blast_vfx_cols: int        ## sprite sheet 欄數
	var blast_vfx_rows: int        ## sprite sheet 行數
	var blast_vfx_frames: int      ## 總幀數
	var blast_vfx_scale: float     ## VFX 縮放倍率
	var blast_vfx_speed: float     ## 每幀秒數
	var blast_vfx_start_frame: int ## sprite sheet 起始幀（從第幾格開始播放）
	# ── 爆炸音效（預留）──
	var blast_se_path: String      ## 音效資源路徑

	func _init(
		p_element: Block.Type,
		p_preview_color: Color,
		p_display_name: String,
		p_blast_vfx_path: String = "",
		p_blast_vfx_cols: int = 1,
		p_blast_vfx_rows: int = 1,
		p_blast_vfx_frames: int = 0,
		p_blast_vfx_scale: float = 1.0,
		p_blast_vfx_speed: float = 0.03,
		p_blast_se_path: String = "",
		p_blast_vfx_start_frame: int = 0,
	) -> void:
		element = p_element
		preview_color = p_preview_color
		display_name = p_display_name
		blast_vfx_path = p_blast_vfx_path
		blast_vfx_cols = p_blast_vfx_cols
		blast_vfx_rows = p_blast_vfx_rows
		blast_vfx_frames = p_blast_vfx_frames
		blast_vfx_scale = p_blast_vfx_scale
		blast_vfx_speed = p_blast_vfx_speed
		blast_se_path = p_blast_se_path
		blast_vfx_start_frame = p_blast_vfx_start_frame


## 所有高階寶石定義（不含 NONE）
const _DATA: Dictionary = {}

const DEFAULT_FUSE_THRESHOLD: Dictionary = {
	Block.UpperType.FIREBALL: 9,
	Block.UpperType.FIRE_PILLAR_X: 4,
	Block.UpperType.FIRE_PILLAR_Y: 4,
	Block.UpperType.SAINT_CROSS: 9,
	Block.UpperType.LEAF_SHIELD: 4,
	Block.UpperType.SNOWBALL: 4,
	Block.UpperType.ICEBALL: 8,
	Block.UpperType.WATER_SLASH: 4,
	Block.UpperType.PORCUPINE: 9,
	Block.UpperType.TURTLE: 5,
	Block.UpperType.BAMBOO_SUPPLY: 6,
	Block.UpperType.WOOD_SPEAR_UP: 7,
	Block.UpperType.WOOD_SPEAR_DOWN: 7,
	Block.UpperType.LIGHT_SHIELD: 6,
	Block.UpperType.LEAF_RAY: 6,
	Block.UpperType.LIGHT_TRIANGLE: 6,
	Block.UpperType.FIRE_GREATSWORD: 6,
	Block.UpperType.FIRE_HAMMER: 5,
}

const UPGRADE_EFFECTS: Dictionary = {
	Block.UpperType.WOOD_SPEAR_UP: [
		{
			"desc_key": "UPGRADE_GORY_WOOD_SPEAR_PIERCE_BREAKABLE",
			"effects": {
				"wood_spear_pierce_breakable": 1,
			},
		},
		{
			"desc_key": "UPGRADE_GORY_WOOD_SPEAR_THRESHOLD_1",
			"effects": {
				"threshold_delta": -1,
			},
		},
	],
	Block.UpperType.WOOD_SPEAR_DOWN: [
		{
			"desc_key": "UPGRADE_GORY_WOOD_SPEAR_PIERCE_BREAKABLE",
			"effects": {
				"wood_spear_pierce_breakable": 1,
			},
		},
		{
			"desc_key": "UPGRADE_GORY_WOOD_SPEAR_THRESHOLD_1",
			"effects": {
				"threshold_delta": -1,
			},
		},
	],
}

## 靜態查詢表（在腳本載入時初始化）
static var _defs: Dictionary = {}
static var _initialized := false


static func _ensure_init() -> void:
	if _initialized:
		return
	_initialized = true
	_defs[Block.UpperType.FIREBALL] = Def.new(
		Block.Type.RED,
		Color(1.0, 0.30, 0.15),
		"Fireball",
		"res://assets/vfx/explosionbig.png", 10, 2, 11, 3.0, 0.03,
	)
	_defs[Block.UpperType.FIRE_PILLAR_X] = Def.new(
		Block.Type.RED,
		Color(1.0, 0.40, 0.10),
		"Fire Pillar X",
	)
	_defs[Block.UpperType.FIRE_PILLAR_Y] = Def.new(
		Block.Type.RED,
		Color(1.0, 0.40, 0.10),
		"Fire Pillar Y",
	)
	_defs[Block.UpperType.SAINT_CROSS] = Def.new(
		Block.Type.LIGHT,
		Color(1.0, 0.92, 0.23),
		"Saint Cross",
		"res://assets/animation/Smite_spritesheet.png", 11, 1, 11, 2.0, 0.04,
	)
	_defs[Block.UpperType.LEAF_SHIELD] = Def.new(
		Block.Type.GREEN,
		Color(0.30, 0.80, 0.35),
		"Leaf Shield",
	)
	_defs[Block.UpperType.PORCUPINE] = Def.new(
		Block.Type.GREEN,
		Color(0.30, 0.80, 0.35),
		"Porcupine",
	)
	_defs[Block.UpperType.TURTLE] = Def.new(
		Block.Type.GREEN,
		Color(0.30, 0.80, 0.35),
		"Turtle",
	)
	_defs[Block.UpperType.BAMBOO_SUPPLY] = Def.new(
		Block.Type.GREEN,
		Color(0.30, 0.80, 0.35),
		"Bamboo Supply",
	)
	_defs[Block.UpperType.WOOD_SPEAR_UP] = Def.new(
		Block.Type.GREEN,
		Color(0.30, 0.85, 0.42),
		"Wood Spear Up",
	)
	_defs[Block.UpperType.WOOD_SPEAR_DOWN] = Def.new(
		Block.Type.GREEN,
		Color(0.30, 0.85, 0.42),
		"Wood Spear Down",
	)
	_defs[Block.UpperType.SNOWBALL] = Def.new(
		Block.Type.BLUE,
		Color(0.35, 0.60, 1.0),
		"Snowball",
		"res://assets/music/IceShatter_2_96x96.png", 49, 1, 49, 3.0, 0.03,
	)
	_defs[Block.UpperType.ICEBALL] = Def.new(
		Block.Type.BLUE,
		Color(0.55, 0.82, 1.0),
		"Iceball",
		"res://assets/music/IceShatter_2_96x96.png", 49, 1, 49, 3.0, 0.03,
	)
	_defs[Block.UpperType.LIGHT_SHIELD] = Def.new(
		Block.Type.LIGHT,
		Color(0.55, 0.82, 1.0),
		"Light Shield",
	)
	_defs[Block.UpperType.LEAF_RAY] = Def.new(
		Block.Type.GREEN,
		Color(0.62, 1.0, 0.12),
		"Leaf Ray",
	)
	_defs[Block.UpperType.LIGHT_TRIANGLE] = Def.new(
		Block.Type.LIGHT,
		Color(1.0, 0.92, 0.23),
		"Light Triangle",
	)
	_defs[Block.UpperType.FIRE_GREATSWORD] = Def.new(
		Block.Type.RED,
		Color(1.0, 0.38, 0.12),
		"Fire Greatsword",
	)
	_defs[Block.UpperType.FIRE_HAMMER] = Def.new(
		Block.Type.RED,
		Color(1.0, 0.30, 0.10),
		"Fire Hammer",
		"res://assets/vfx/explosionbig.png", 10, 2, 11, 3.0, 0.03,
	)
	_defs[Block.UpperType.WATER_SLASH] = Def.new(
		Block.Type.BLUE,
		Color(0.25, 0.60, 1.0),
		"Water Slash",
		"res://assets/animation/RetroImpactEffectPack5C.png", 9, 30, 9, 1.5, 0.04,
		"", 180,
	)


## 取得指定高階寶石的定義。找不到時回傳 null。
static func get_def(ut: Block.UpperType) -> Def:
	_ensure_init()
	return _defs.get(ut)


## 取得預覽色。找不到時回傳 fallback。
static func get_preview_color(ut: Block.UpperType, fallback: Color = Color(1.0, 0.35, 0.15)) -> Color:
	_ensure_init()
	var d: Def = _defs.get(ut)
	if d != null:
		return d.preview_color
	return fallback


## 取得元素類型。找不到時回傳 RED。
static func get_element(ut: Block.UpperType, fallback: Block.Type = Block.Type.RED) -> Block.Type:
	_ensure_init()
	var d: Def = _defs.get(ut)
	if d != null:
		return d.element
	return fallback


static func get_default_fuse_threshold(ut: Block.UpperType, fallback: int = 1) -> int:
	return int(DEFAULT_FUSE_THRESHOLD.get(ut, fallback))


static func get_upgrade_effects(ut: Block.UpperType) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source: Array = UPGRADE_EFFECTS.get(ut, [])
	for entry in source:
		if entry is Dictionary:
			result.append((entry as Dictionary).duplicate(true))
	return result
