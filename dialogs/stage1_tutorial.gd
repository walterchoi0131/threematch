## Stage1Tutorial — 第一關戰鬥教學步驟資料。
## 步驟 1：教玩家點擊綠色寶石消除，發動普通攻擊。
extends RefCounted

const _DialogLine := preload("res://scripts/dialog_line.gd")


static func make_steps() -> Array:
	# 綠寶石群位置：(4,5), (5,5), (4,6)
	var green_positions: Array[Vector2i] = [
		Vector2i(4, 5), Vector2i(5, 5), Vector2i(4, 6),
	]

	# 紅寶石群位置：(0,0)-(2,2) — 3×3 方塊（共 9 顆，觸發火焰炸彈融合）
	var red_positions: Array[Vector2i] = [
		Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2),
		Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2),
		Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2),
	]

	return [
		# ── 步驟 1：教普攻（消除綠寶石）──
		{
			"pre_dialog": [
				_line("husky", "normal",
					"看到棋盤上那些發亮的綠色寶石了嗎？\n點擊任意一顆，就能消除所有相連的同色寶石，發動攻擊！",
					"See those glowing green gems on the board?\nTap any one of them to destroy all connected gems of the same color and launch an attack!"),
			],
			"highlight": green_positions,
			"hand_pos": Vector2i(4, 5),
			"filter": green_positions,
			"post_dialog": [
				_line("husky", "normal",
					"做得好！消除的寶石越多，傷害就越高。",
					"Well done! The more gems you destroy, the more damage you deal."),
			],
		},
		# ── 步驟 2：教融合（9 顆紅寶石 → 火焰炸彈）──
		{
			"pre_dialog": [
				_line("husky", "normal",
					"看到左上角那一大群紅色寶石了嗎？\n點擊其中一顆——當消除數量夠多，角色會將它們融合成強力的炸彈寶石！",
					"See that big cluster of red gems in the corner?\nTap any one — when enough gems are destroyed, your character will fuse them into a powerful bomb gem!"),
			],
			"highlight": red_positions,
			"hand_pos": Vector2i(1, 1),
			"filter": red_positions,
			"post_dialog": [
				_line("husky", "normal",
					"融合寶石是即時的，不會消耗回合！",
					"Fusing gems is instant — it won't cost you a turn!"),
				_line("husky", "normal",
					"每位角色都有獨特的融合技能，\n試著不同組合來打造你的隊伍吧！",
					"Every character has a unique fusion style.\nTry different combinations to build your team!"),
			],
		},
	]


static func _line(char_id: String, emotion: String, zh: String, en: String) -> _DialogLine:
	var dl := _DialogLine.new()
	dl.character_id = char_id
	dl.emotion = emotion
	dl.position = "left"
	dl.action = "none"
	dl.text_zh = zh
	dl.text_en = en
	dl.shake = false
	return dl


## 第三波開始：教敵人攻擊倒計時 + 點擊切換目標
static func make_round3_dialog() -> Array:
	return [
		_line("husky", "normal",
			"注意每隻敵人圖示下方的數字——\n那是它距離攻擊你還剩幾回合！",
			"Notice the number below each enemy portrait —\nthat's how many turns until it attacks you!"),
		_line("husky", "normal",
			"點擊敵人可以切換攻擊目標。\n優先擊倒倒計時最短的敵人！",
			"Tap an enemy to switch your attack target.\nPrioritize the one with the lowest countdown!"),
	]


## Boss 擊敗後收尾對話（勝利橫幅前）
static func make_victory_dialog() -> Array:
	return [
		_line("husky", "normal",
			"你做到了！第一關的所有敵人都被你打敗了！",
			"You did it! Every enemy in Stage 1 has been defeated!"),
		_line("husky", "normal",
			"繼續成長吧——更強大的冒險在前方等著你！",
			"Keep growing stronger — greater adventures lie ahead!"),
	]
