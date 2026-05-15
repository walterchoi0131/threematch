## EnemyData（敎人資料）— 定義敎人的屬性、攻擊力、攻擊間隔、元素等。
class_name EnemyData
extends Resource

enum ActionType { ATTACK, STONE_MAGIC }

@export var enemy_name: String = "Slime"     # 敎人名稱
@export var enemy_level: int = 1              # 敎人等級（用於計算經驗掉落）
@export var max_hp: int = 50                  # 最大血量
@export var attack_damage: int = 6            # 基礎攻擊力
@export var attack_coeff: float = 1.0         # 攻擊係數（最終傷害 = 基礎攻擊力 × 係數）
@export var attack_interval: int = 3          # 每過 N 回合行動一次
@export var action_pattern: Array[ActionType] = [ActionType.ATTACK]  # 敵人實際行動循環（等待回合由 attack_interval / rounds_init_cd 表示）
@export var portrait_color: Color = Color(0.2, 0.7, 0.2)  # 敎人頭像色
@export var portrait_texture: Texture2D = null  # 敎人頭像貼圖
## 元素屬性：RED=火、BLUE=水、GREEN=葉
@export var element: Block.Type = Block.Type.GREEN
## 是否為「主要 Boss」：戰鬥場上方會顯示此敵人的 Boss 血條
@export var is_main_boss: bool = false
## 掉落表：敵人死亡時依序擲骰每個條目
@export var loot_table: Array[LootItem] = []


## 計算此敵人本次普通攻擊的最終傷害
func get_attack_damage() -> int:
	return maxi(0, int(round(float(attack_damage) * attack_coeff)))


## 取得指定 pattern index 對應的行動；空 pattern 退回普通攻擊
func get_action_at(pattern_index: int) -> ActionType:
	if action_pattern.is_empty():
		return ActionType.ATTACK
	var index: int = posmod(pattern_index, action_pattern.size())
	return action_pattern[index]


## 取得下一個行動 index；空 pattern 維持 0
func get_next_action_index(pattern_index: int) -> int:
	if action_pattern.is_empty():
		return 0
	return posmod(pattern_index + 1, action_pattern.size())


## 計算此敵人掉落的經驗值
func get_exp_drop() -> int:
	return int(floor(25.0 * pow(enemy_level, 1.2)))
