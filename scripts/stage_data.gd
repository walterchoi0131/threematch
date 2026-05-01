## StageData（關卡資料）— 定義關卡的棋盤配置、允許寶石、敎人波次等。
class_name StageData
extends Resource

## 關卡背景圖片列舉
enum Background {
	NONE = 0,
	BREEZE = 1,
}

## 背景圖片路徑對應表
const BACKGROUND_PATHS: Dictionary = {
	Background.BREEZE: "res://assets/background/breeze.jpg",
}

## 關卡編號（Chapter-Stage 格式，例如 "1-1"）。用於存檔與解鎖判定。
@export var stage_id: String = ""
## 前置關卡 id：必須先通關此關卡才會解鎖本關。空字串 = 無前置（一律可玩）。
@export var prerequisite_stage_id: String = ""
## 世界地圖連線：本關卡通往下一關的 stage_id 列表（可一對多）。
@export var connects_to: Array[String] = []
@export var stage_name: String = "Stage 1"  # 關卡名稱
@export var allowed_types: Array[Block.Type] = [Block.Type.RED, Block.Type.BLUE, Block.Type.GREEN]  # 允許的寶石類型
@export var min_match: int = 2   # 最少連接數才可消除
@export var columns: int = 8     # 棋盤欄位數
@export var rows: int = 8        # 棋盤行數

## 每一波是一個 EnemyData 陣列。
## rounds[0] = 第一波，rounds[1] = 第二波，以此類推。
@export var rounds: Array[Array] = []

## 每個敌人生成時的初始 CD（取代 attack_interval）。
## 与 rounds 平行的嵌套陣列：rounds_init_cd[round][i] = int。
## 留空、長度不足或值 ≤ 0 表示使用 EnemyData.attack_interval 預設。
@export var rounds_init_cd: Array[Array] = []

@export var background: Background = Background.NONE  # 關卡背景圖片
@export var bgm: AudioStream = null  # 關卡背景音樂

const _DialogSequence := preload("res://scripts/dialog_sequence.gd")
@export var pre_dialog: _DialogSequence = null  # 戰鬥前 AVG 對話（可選）

## 教學模式：啟用後使用固定棋盤並觸發教學流程
@export var is_tutorial: bool = false

## 固定隊伍：若非空，玩家必須使用此隊伍出戰（無法在準備畫面更改）
@export var set_party: Array[CharacterData] = []

## 固定棋盤佈局（二維陣列 [x][y] = Block.Type）。空陣列 = 隨機生成。
@export var fixed_layout: Array = []
