## EnemyData（敎人資料）— 定義敎人的屬性、攻擊力、攻擊間隔、元素等。
class_name EnemyData
extends Resource

@export var enemy_name: String = "Slime"     # 敎人名稱
@export var max_hp: int = 50                  # 最大血量
@export var attack_damage: int = 6            # 每次攻擊的傷害
@export var attack_interval: int = 3          # 每過 N 回合攻擊一次
@export var portrait_color: Color = Color(0.2, 0.7, 0.2)  # 敎人頭像色
@export var portrait_texture: Texture2D = null  # 敎人頭像貼圖
## 元素屬性：RED=火、BLUE=水、GREEN=葉
@export var element: Block.Type = Block.Type.GREEN
## 掉落表：敵人死亡時依序擲骰每個條目
@export var loot_table: Array[LootItem] = []
