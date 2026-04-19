## CharacterData（角色資料）— 定義角色的屬性、成長、技能等資料。
## 以 .tres 資源檔形式儲存在 characters/ 資料夾中。
class_name CharacterData
extends Resource

enum SkillType { NONE, PASSIVE, ACTIVE, RESPONDING }  # 技能類型列舉

@export var character_name: String = "Hero"  # 角色名稱
@export var gem_type: Block.Type = Block.Type.RED  # 對應的寶石類型（決定哪種寶石觸發攻擊）
@export var level: int = 5            # 等級
@export var base_atk: int = 2         # 基礎攻擊力
@export var atk_growth: float = 0.6   # 每級攻擊力成長
@export var base_hp: int = 50         # 基礎血量
@export var hp_growth: float = 8.0    # 每級血量成長
@export var portrait_texture: Texture2D  # 頭像貼圖
@export var portrait_color: Color = Color(0.91, 0.26, 0.21)  # 頭像備用顏色
@export var portrait_scale: float = 1.0          # 頭像縮放（相對於卡片容器）
@export var portrait_offset: Vector2 = Vector2.ZERO  # 頭像偏移（相對於卡片左上角）

# ── 技能定義 ─────────────────────────────────────────────────
@export var passive_skill_name: String = ""   # 被動技能名稱
@export var passive_skill_desc: String = ""   # 被動技能描述
@export var active_skill_name: String = ""    # 主動技能名稱
@export var active_skill_desc: String = ""    # 主動技能描述
@export var active_skill_cd: int = 0          # 主動技能冷卻回合數

## 回應技能陣列。每個項目：
##   { "name": 名稱, "desc": 描述, "threshold": 觸發門檻,
##     "priority": 優先級, "trigger_type": 觸發方式 }
## trigger_type = "count"（N+ 同類寶石）或 "line"（N+ 連續排列）。
## 優先級數字越小，同時觸發時越優先執行。
@export var responding_skills: Array[Dictionary] = []


## 計算當前等級的攻擊力
func get_atk() -> int:
	return base_atk + int(floor(level * atk_growth))


## 計算當前等級的最大血量
func get_max_hp() -> int:
	return base_hp + int(floor(level * hp_growth))
