## StageData（關卡資料）— 定義關卡的棋盤配置、允許寶石、敎人波次等。
class_name StageData
extends Resource

@export var stage_name: String = "Stage 1"  # 關卡名稱
@export var allowed_types: Array[Block.Type] = [Block.Type.RED, Block.Type.BLUE, Block.Type.GREEN]  # 允許的寶石類型
@export var min_match: int = 2   # 最少連接數才可消除
@export var columns: int = 8     # 棋盤欄位數
@export var rows: int = 8        # 棋盤行數

## 每一波是一個 EnemyData 陣列。
## rounds[0] = 第一波，rounds[1] = 第二波，以此類推。
@export var rounds: Array[Array] = []

@export var bgm: AudioStream = null  # 關卡背景音樂
