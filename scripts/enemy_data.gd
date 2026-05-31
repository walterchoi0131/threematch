## EnemyData（敎人資料）— 定義敵人的基本資料與行動序列。
class_name EnemyData
extends Resource

enum ActionType { ATTACK_15, STONE_MAGIC, REST }

const HP_PERCENT_MIN: int = 500
const HP_PERCENT_MAX: int = 10000
const ATTACK_PERCENT_MIN: int = 1
const ATTACK_PERCENT_MAX: int = 200
const ATTACK_PERCENT_DEFAULT: int = 15

@export var enemy_name: String = "Slime"     # 敎人名稱
@export var enemy_level: int = 1              # Legacy: 新流程由關卡 spawn level 決定
@export var max_hp: int = HP_PERCENT_MIN      # HP 百分比：實際 HP = 同等級玩家隊伍估算 ATK × max_hp%
@export var attack_damage: int = 0            # Legacy: 新流程使用 Attack X%
@export var attack_coeff: float = 1.0         # Legacy: 新流程不使用固定攻擊係數
@export var attack_interval: int = 0          # Legacy: 新流程由 REST 行動聚合為 CD
@export var action_pattern: Array[ActionType] = [ActionType.ATTACK_15]  # REST 會聚合成 CD，非 REST 才會實際行動
@export var action_percents: Array[int] = [ATTACK_PERCENT_DEFAULT]       # 與 action_pattern 平行；攻擊行動的 X%
@export var portrait_color: Color = Color(0.2, 0.7, 0.2)  # 敎人頭像色
@export var portrait_texture: Texture2D = null  # 敎人頭像貼圖
## 元素屬性：RED=火、BLUE=水、GREEN=葉
@export var element: Block.Type = Block.Type.GREEN
## Legacy: 主要 Boss 現在由關卡 spawn 設定，保留此欄位只為讀取舊資源
@export var is_main_boss: bool = false
## 掉落表：敵人死亡時依序擲骰每個條目
@export var loot_table: Array[LootItem] = []


func get_hp_percent() -> int:
	return clamp_hp_percent(max_hp)


func get_max_hp_for_attack_power(estimated_attack_power: int) -> int:
	var base_attack: int = maxi(1, estimated_attack_power)
	return maxi(1, int(round(float(base_attack) * float(get_hp_percent()) / 100.0)))


static func clamp_hp_percent(value: int) -> int:
	return clampi(value, HP_PERCENT_MIN, HP_PERCENT_MAX)


static func clamp_attack_percent(value: int) -> int:
	return clampi(value, ATTACK_PERCENT_MIN, ATTACK_PERCENT_MAX)


## 取得指定 pattern index 對應的行動；空 pattern 退回普通攻擊
func get_action_at(pattern_index: int) -> ActionType:
	if action_pattern.is_empty():
		return ActionType.ATTACK_15
	var index: int = posmod(pattern_index, action_pattern.size())
	return action_pattern[index]


func get_action_percent_at(pattern_index: int) -> int:
	if action_pattern.is_empty():
		return ATTACK_PERCENT_DEFAULT
	var index: int = posmod(pattern_index, action_pattern.size())
	if index >= action_percents.size():
		return ATTACK_PERCENT_DEFAULT
	return clamp_attack_percent(int(action_percents[index]))


## 取得下一個行動 index；空 pattern 維持 0
func get_next_action_index(pattern_index: int) -> int:
	if action_pattern.is_empty():
		return 0
	return posmod(pattern_index + 1, action_pattern.size())


func has_active_action() -> bool:
	if action_pattern.is_empty():
		return true
	for action: ActionType in action_pattern:
		if action != ActionType.REST:
			return true
	return false


func is_rest_action(action_type: int) -> bool:
	return action_type == ActionType.REST


func get_action_label(action_type: int, attack_percent: int = ATTACK_PERCENT_DEFAULT) -> String:
	match action_type:
		ActionType.STONE_MAGIC:
			return "Stone Magic"
		ActionType.REST:
			return "Rest"
		_:
			return "Attack %d%%" % clamp_attack_percent(attack_percent)


## 計算此敵人掉落的經驗值
func get_exp_drop_for_level(level_value: int) -> int:
	var clamped_level: int = clampi(level_value, 1, 99)
	return int(floor(25.0 * pow(clamped_level, 1.2)))
