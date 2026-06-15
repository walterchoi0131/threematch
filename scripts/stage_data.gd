## StageData（關卡資料）— 定義關卡的棋盤配置、允許寶石、敎人波次等。
class_name StageData
extends Resource

## 關卡背景圖片列舉
enum Background {
	NONE = 0,
	BREEZE = 1,
}

## 關卡模式列舉
##  NORMAL — 一般戰鬥（依 rounds 出怪）
##  ESCAPE — 逃脫模式：無敵人，玩家須消除/補充指定數量寶石以勝利
##  PUZZLE — 解謎模式：無敵人，玩家須達成 puzzle goal 以勝利
enum Mode {
	NORMAL = 0,
	ESCAPE = 1,
	PUZZLE = 2,
}

## Puzzle mode goal 類型
enum PuzzleGoalKind {
	BREAK_COUNT = 0,
}

## 背景圖片路徑對應表
const BACKGROUND_PATHS: Dictionary = {
	Background.BREEZE: "res://assets/background/breeze.jpg",
}

const DEFAULT_AREA: String = "ruin"
const CELL_HOLE: int = -10
const CELL_WATER_SWORD: int = -11
const FALLBACK_BATTLE_BG_PATH: String = "res://assets/battle_background/battle_bg_forest.png"
const AREA_KEYS: Array[String] = [
	"aurora",
	"church",
	"dessert",
	"dungeon",
	"forest",
	"heaven",
	"iceberg",
	"meadow",
	"ruin",
	"school",
	"swamp",
	"underwater",
	"volcano",
]

## 關卡地區資訊。key 需對應 assets/stage_spot/spot_<area>.png。
const AREA_INFO: Dictionary = {
	"aurora": {
		"spot_path": "res://assets/stage_spot/spot_aurora.png",
		"battle_bg_path": "res://assets/battle_background/battle_bg_aurora.png",
	},
	"church": {
		"spot_path": "res://assets/stage_spot/spot_church.png",
		"battle_bg_path": "res://assets/battle_background/battle_bg_church.png",
	},
	"dessert": {
		"spot_path": "res://assets/stage_spot/spot_dessert.png",
		"battle_bg_path": "res://assets/battle_background/battle_bg_dessert.png",
	},
	"dungeon": {
		"spot_path": "res://assets/stage_spot/spot_dungeon.png",
		"battle_bg_path": "res://assets/battle_background/battle_bg_dungeon.png",
	},
	"forest": {
		"spot_path": "res://assets/stage_spot/spot_forest.png",
		"battle_bg_path": "res://assets/battle_background/battle_bg_forest.png",
	},
	"heaven": {
		"spot_path": "res://assets/stage_spot/spot_heaven.png",
		"battle_bg_path": "res://assets/battle_background/battle_bg_heaven.png",
	},
	"iceberg": {
		"spot_path": "res://assets/stage_spot/spot_iceberg.png",
		"battle_bg_path": "res://assets/battle_background/battle_bg_iceberg.png",
	},
	"meadow": {
		"spot_path": "res://assets/stage_spot/spot_meadow.png",
		"battle_bg_path": "res://assets/battle_background/battle_bg_meadow.png",
	},
	"ruin": {
		"spot_path": "res://assets/stage_spot/spot_ruin.png",
		"battle_bg_path": "res://assets/battle_background/battle_bg_ruin.png",
	},
	"school": {
		"spot_path": "res://assets/stage_spot/spot_school.png",
		"battle_bg_path": "res://assets/battle_background/battle_bg_school.png",
	},
	"swamp": {
		"spot_path": "res://assets/stage_spot/spot_swamp.png",
		"battle_bg_path": "res://assets/battle_background/battle_bg_swamp.png",
	},
	"underwater": {
		"spot_path": "res://assets/stage_spot/spot_underwater.png",
		"battle_bg_path": "res://assets/battle_background/battle_bg_underwater.png",
	},
	"volcano": {
		"spot_path": "res://assets/stage_spot/spot_volcano.png",
		"battle_bg_path": "res://assets/battle_background/battle_bg_volcano.png",
	},
}


static func get_area_info(area_key: String) -> Dictionary:
	var key: String = normalize_area(area_key)
	var info: Dictionary = AREA_INFO.get(key, AREA_INFO[DEFAULT_AREA]) as Dictionary
	return info


static func normalize_area(area_key: String) -> String:
	var key: String = area_key.strip_edges()
	return key if AREA_INFO.has(key) else DEFAULT_AREA


static func get_stage_spot_path(area_key: String) -> String:
	var info: Dictionary = get_area_info(area_key)
	var path: String = info.get("spot_path", "") as String
	return path


static func get_battle_background_path(area_key: String) -> String:
	var info: Dictionary = get_area_info(area_key)
	var path: String = info.get("battle_bg_path", FALLBACK_BATTLE_BG_PATH) as String
	return FALLBACK_BATTLE_BG_PATH if path.is_empty() else path


func get_element_distribution() -> Dictionary:
	var distribution: Dictionary = {}
	if not element_weights.is_empty():
		for i in allowed_types.size():
			var type_value: int = int(allowed_types[i])
			if not Block.is_random_gem_type_value(type_value):
				continue
			var weight: int = 0
			if i < element_weights.size():
				weight = int(element_weights[i])
			if weight > 0:
				distribution[type_value] = weight
	if distribution.is_empty():
		distribution = _default_element_distribution()
	return distribution


func get_element_weight_for_type(type_value: int) -> int:
	var distribution: Dictionary = get_element_distribution()
	return int(distribution.get(type_value, 0))


func get_element_weights_for_allowed_types() -> Array[int]:
	var weights: Array[int] = []
	var distribution: Dictionary = get_element_distribution()
	for type_value in allowed_types:
		weights.append(maxi(0, int(distribution.get(int(type_value), 0))))
	return weights


func _default_element_distribution() -> Dictionary:
	match stage_id:
		"1-4":
			return {
				Block.Type.RED: 32,
				Block.Type.BLUE: 32,
				Block.Type.GREEN: 31,
				Block.Type.LIGHT: 5,
			}
		"1-5":
			return {
				Block.Type.RED: 60,
				Block.Type.BLUE: 10,
				Block.Type.GREEN: 10,
				Block.Type.LIGHT: 20,
			}
		"1-6":
			return {
				Block.Type.RED: 25,
				Block.Type.BLUE: 25,
				Block.Type.GREEN: 25,
				Block.Type.DARK: 25,
			}

	var distribution: Dictionary = {}
	for type_value in allowed_types:
		var normalized: int = int(type_value)
		if Block.is_random_gem_type_value(normalized):
			distribution[normalized] = 1
	return distribution

## 關卡編號（Chapter-Stage 格式，例如 "1-1"）。用於存檔與解鎖判定。
@export var stage_id: String = ""
## 前置關卡 id：必須先通關此關卡才會解鎖本關。空字串 = 無前置（一律可玩）。
@export var prerequisite_stage_id: String = ""
## 世界地圖連線：本關卡通往下一關的 stage_id 列表（可一對多）。
@export var connects_to: Array[String] = []
@export var stage_name: String = "Stage 1"  # 關卡名稱
@export var element_weights: Array[int] = []
@export var allowed_types: Array[Block.Type] = [Block.Type.RED, Block.Type.BLUE, Block.Type.GREEN]  # 允許的寶石類型
@export var min_match: int = 2   # 最少連接數才可消除
@export var columns: int = 8     # 棋盤欄位數
@export var rows: int = 8        # 棋盤行數
@export_enum("aurora", "church", "dessert", "dungeon", "forest", "heaven", "iceberg", "meadow", "ruin", "school", "swamp", "underwater", "volcano") var area: String = DEFAULT_AREA  # 關卡地區 key
@export var battle_background_override_path: String = ""
@export var battle_music_override_path: String = ""
@export var stretch_battle_background: bool = false
@export var one_time_reward_item_type: ItemDefs.Type = ItemDefs.Type.GOLD
@export var one_time_reward_item_amount: int = 0
@export var one_time_reward_character: CharacterData = null

## 每一波是一個 EnemyData 陣列。
## rounds[0] = 第一波，rounds[1] = 第二波，以此類推。
@export var rounds: Array[Array] = []

## 每個敌人生成時的初始 CD（取代 attack_interval）。
## 与 rounds 平行的嵌套陣列：rounds_init_cd[round][i] = int。
## 留空、長度不足或值 ≤ 0 表示使用行動序列前置 REST 數量。
## 可用來讓使用 action_pattern 的敵人在開場多等待幾回合。
@export var rounds_init_cd: Array[Array] = []

## 每個敵人生成時的等級，與 rounds 平行。
## 留空、長度不足或值 ≤ 0 時會 fallback 到舊 EnemyData.enemy_level 或 1。
@export var rounds_enemy_levels: Array[Array] = []

## 每個敵人生成時是否作為主要 Boss，與 rounds 平行。
## 留空時舊關卡可 fallback 到 EnemyData.is_main_boss 或最後一波最後一隻。
@export var rounds_main_bosses: Array[Array] = []

@export var background: Background = Background.NONE  # 關卡背景圖片
@export var bgm: AudioStream = null  # 關卡背景音樂

## 關卡模式（NORMAL = 一般戰鬥；ESCAPE = 逃脫模式；PUZZLE = 解謎目標）
@export var mode: Mode = Mode.NORMAL
## 逃脫模式所需累計補充寶石數量（達成 → 勝利）
@export var escape_refill_target: int = 0
## Puzzle mode 目標：目前只支援 BREAK_COUNT。
@export var puzzle_goal_kind: PuzzleGoalKind = PuzzleGoalKind.BREAK_COUNT
@export var puzzle_goal_target_type: int = Block.Type.RED
@export var puzzle_goal_required_count: int = 10
@export var puzzle_turn_limit: int = 30

const _DialogSequence := preload("res://scripts/dialog_sequence.gd")
@export var pre_dialog: _DialogSequence = null  # 戰鬥前 AVG 對話（可選）
@export var post_dialog: _DialogSequence = null  # 戰鬥後 AVG 對話（可選）

## 教學模式：啟用後使用固定棋盤並觸發教學流程
@export var is_tutorial: bool = false

## 固定隊伍：若非空，玩家必須使用此隊伍出戰（無法在準備畫面更改）
@export var set_party: Array[CharacterData] = []

## 固定棋盤佈局（二維陣列 [x][y] = Block.Type）。空陣列 = 隨機生成。
## 可部分指定：負值或未寫入的格子會保留開場隨機寶石。
@export var fixed_layout: Array = []
@export var drop_start_rows: Array[int] = []
