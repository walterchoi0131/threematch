## GameState（遊戲狀態）— 跨場景的持久化單例（Autoload）。
## 儲存當前選擇的關卡、隊伍、擁有的角色等。
extends Node

const MAX_PARTY_SIZE := 4  # 隊伍最大人數

var selected_stage: StageData = null           # 當前選擇的關卡
var selected_party: Array[CharacterData] = []  # 當前選擇的隊伍
var detail_character: CharacterData = null      # 要查看詳細資訊的角色

var owned_characters: Array[CharacterData] = []  # 玩家擁有的所有角色

var gold: int = 0                      # 玩家持有金幣
var inventory: Dictionary = {}         # 玩家物品庫存，key = ItemDefs.Type，value = int


## 新增戰利品到玩家存貨
func add_loot(type: ItemDefs.Type, amount: int) -> void:
	if type == ItemDefs.Type.GOLD:
		gold += amount
	else:
		var current: int = inventory.get(type, 0)
		inventory[type] = current + amount


func _ready() -> void:
	# 預載初始角色
	owned_characters = [
		preload("res://characters/char_boar.tres"),
		preload("res://characters/char_raccoon.tres"),
		preload("res://characters/char_fox.tres"),
		preload("res://characters/char_husky.tres"),
		preload("res://characters/char_panda.tres"),
		preload("res://characters/char_polar.tres"),
	]

	# 為關卡設定對話（程式碼建構）
	var _stage_dev: StageData = preload("res://stages/stage_dev.tres")
	var _Stage1Intro := preload("res://dialogs/stage1_intro.gd")
	if _stage_dev.pre_dialog == null:
		_stage_dev.pre_dialog = _Stage1Intro.make()

	# 設定教學模式與固定棋盤佈局
	_stage_dev.is_tutorial = true
	_stage_dev.fixed_layout = _build_stage1_layout()


## 建構第一關固定棋盤佈局（8×8）
## 3 色無相鄰重複排列 + 紅色 3×3 在 (0,0)-(2,2) + 綠色群在 (4,5), (5,5), (4,6)
static func _build_stage1_layout() -> Array:
	# R=0, B=1, G=2, L=6（Light）
	const R := Block.Type.RED
	const B := Block.Type.BLUE
	const L := Block.Type.LIGHT
	const G := Block.Type.GREEN
	# 基礎 3 色棋盤模式（避免任何 2+ 相鄰同色）
	# 行列交替 pattern: (x+y)%3 → R/B/L
	var layout: Array = []
	layout.resize(8)
	for x in 8:
		var col: Array = []
		col.resize(8)
		for y in 8:
			var idx: int = (x + y) % 3
			match idx:
				0: col[y] = R
				1: col[y] = B
				2: col[y] = L
		layout[x] = col
	# 紅色 3×3 方塊（火焰炸彈融合用，共 9 顆）
	for rx in range(0, 3):
		for ry in range(0, 3):
			layout[rx][ry] = R
	# 隔離紅色方塊（相鄰 RED 改為 BLUE，防止 BFS 擴散）
	layout[3][0] = B   # (3,0) base=R → B
	layout[0][3] = B   # (0,3) base=R → B
	# 放置綠色群
	layout[4][5] = G
	layout[5][5] = G
	layout[4][6] = G
	return layout
