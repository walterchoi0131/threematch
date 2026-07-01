## CharacterData（角色資料）— 定義角色的屬性、成長、技能等資料。
## 以 .tres 資源檔形式儲存在 characters/ 資料夾中。
class_name CharacterData
extends Resource

enum SkillType { NONE, PASSIVE, ACTIVE, RESPONDING }  # 技能類型列舉
enum GrowthMode { LINEAR, WEAK_EARLY_STRONG_LATE, STRONG_EARLY_WEAK_LATE }

const STAT_LEVEL_MIN: int = 1
const STAT_LEVEL_MAX: int = 99

@export var character_name: String = "Hero"  # 角色名稱
@export var job_id: String = ""              # Job/play style id: attacker, breaker, tactictian, wizard
@export var gem_type: Block.Type = Block.Type.RED  # 對應的寶石類型（決定哪種寶石觸發攻擊）
@export var level: int = 5            # 等級（玩家角色預設 Lv5）
var current_exp: int = 0              # 當前累積經驗值（不存入 .tres，執行時管理）
@export var base_atk: int = 2         # 基礎攻擊力
@export var atk_growth: float = 6.0   # 每級攻擊力成長係數
@export var atk_growth_mode: GrowthMode = GrowthMode.LINEAR
@export var base_hp: int = 50         # 基礎血量
@export var hp_growth: float = 8.0    # 每級血量成長
@export var hp_growth_mode: GrowthMode = GrowthMode.LINEAR
@export var base_magic: int = 2       # 基礎魔力（部分主動技倍率以此計算）
@export var magic_growth: float = 5.0 # 每級魔力成長係數
@export var magic_growth_mode: GrowthMode = GrowthMode.LINEAR
@export var portrait_texture: Texture2D  # 頭像貼圖
@export var portrait_color: Color = Color(0.91, 0.26, 0.21)  # 頭像備用顏色
@export var portrait_scale: float = 1.0          # 頭像縮放（相對於卡片容器）
@export var portrait_offset: Vector2 = Vector2.ZERO  # 頭像偏移（相對於卡片左上角）
@export var dialog_square_scale: float = 1.0          # 戰鬥對話頭像縮放【Battle Dialog】
@export var dialog_square_offset: Vector2 = Vector2.ZERO  # 戰鬥對話頭像偏移【Battle Dialog】
@export var dialog_phase_scale: float = 1.0          # 劇情對話階段大立繪縮放【Dialog Phase】
@export var dialog_phase_offset: Vector2 = Vector2.ZERO  # 劇情對話階段大立繪偏移【Dialog Phase】
@export var square_scale: float = 1.0          # 方形卡片頭像縮放（角色列表 / 準備畫面）
@export var square_offset: Vector2 = Vector2.ZERO  # 方形卡片頭像偏移（角色列表 / 準備畫面）
@export var rectangular_scale: float = 1.0          # 矩形列頭像縮放（戰鬥結算 / 教學列）
@export var rectangular_offset: Vector2 = Vector2.ZERO  # 矩形列頭像偏移（戰鬥結算 / 教學列）
@export var loot_log_scale: float = 1.0
@export var loot_log_offset: Vector2 = Vector2.ZERO

# ── 技能定義 ─────────────────────────────────────────────────
@export var passive_skill_name: String = ""   # 被動技能名稱
@export var passive_skill_desc: String = ""   # 被動技能描述
@export var active_skill_name: String = ""    # 主動技能名稱
@export var active_skill_desc: String = ""    # 主動技能描述
@export var active_skill_cd: int = 0          # 主動技能冷卻回合數
@export var active_unlock_stage_id: String = ""  # 主動技能解鎖所需通關 stage_id；空字串 = 無限制
@export var has_break_essence: bool = false   # 主動技能是否具「BREAK」屬性（可連同 PLANK 一併拆除）
@export var active_skill_blast: bool = false  # 主動技能是否具「爆破」屬性（可拆可破壞障礙與敵方高階寶石）
@export var active_skill_upgrades: Array[Dictionary] = []  # 主動技能寶石強化定義（玩家進度存在 GameState）

## 回應技能陣列。每個項目：
##   { "name": 名稱, "desc": 描述, "threshold": 觸發門檻,
##     "priority": 優先級, "trigger_type": 觸發方式 }
## trigger_type = "count"（N+ 同類寶石）或 "line"（N+ 連續排列）。
## 優先級數字越小，同時觸發時越優先執行。
## 合成寶石技能的升級效果綁定在 UpperGemDefs，玩家升級等級存在 GameState。
@export var responding_skills: Array[Dictionary] = []


## 計算當前等級的攻擊力
func get_atk() -> int:
	return get_atk_at_level(level)


## 計算指定等級的攻擊力
func get_atk_at_level(level_value: int) -> int:
	return _calc_stat_at_level(base_atk, atk_growth, atk_growth_mode, level_value)


## 計算當前等級的最大血量
func get_max_hp() -> int:
	return get_max_hp_at_level(level)


## 計算指定等級的最大血量
func get_max_hp_at_level(level_value: int) -> int:
	return _calc_stat_at_level(base_hp, hp_growth, hp_growth_mode, level_value)


## 計算當前等級的魔力（用於部分主動技傷害倍率）
func get_magic() -> int:
	return get_magic_at_level(level)


## 計算指定等級的魔力（用於部分主動技傷害倍率）
func get_magic_at_level(level_value: int) -> int:
	return _calc_stat_at_level(base_magic, magic_growth, magic_growth_mode, level_value)


func has_active_skill_blast() -> bool:
	return active_skill_blast or has_break_essence


## 使用同一套成長曲線計算數值，確保 Debug 預覽與實戰一致。
func _calc_stat_at_level(base_value: int, growth_value: float, mode: GrowthMode, level_value: int) -> int:
	var clamped_level: int = clampi(level_value, STAT_LEVEL_MIN, STAT_LEVEL_MAX)
	var progress: float = float(clamped_level) / float(STAT_LEVEL_MAX)
	var curve: float = progress
	match mode:
		GrowthMode.WEAK_EARLY_STRONG_LATE:
			curve = progress * progress
		GrowthMode.STRONG_EARLY_WEAK_LATE:
			curve = 1.0 - pow(1.0 - progress, 2.0)
		_:
			curve = progress
	var total_growth: float = float(STAT_LEVEL_MAX) * growth_value
	return base_value + int(floor(total_growth * curve))


## 升到下一級所需的總經驗值
func exp_to_next_level() -> int:
	return int(floor(80.0 * pow(level, 1.5)))


## 增加經驗值並處理升級。回傳升級次數（0 = 未升級）。
func add_exp(amount: int) -> int:
	var levels_gained: int = 0
	current_exp += amount
	while current_exp >= exp_to_next_level():
		current_exp -= exp_to_next_level()
		level += 1
		levels_gained += 1
	return levels_gained
