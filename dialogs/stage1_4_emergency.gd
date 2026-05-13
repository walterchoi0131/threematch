## Stage1-4 木板掉落緊急事件對話。
extends RefCounted

const _DialogLine := preload("res://scripts/dialog_line.gd")


static func _line(char_id: String, emotion: String, zh: String, en: String, position: String = "left") -> _DialogLine:
	var dl := _DialogLine.new()
	dl.character_id = char_id
	dl.emotion = emotion
	dl.position = position
	dl.action = "none"
	dl.text_zh = zh
	dl.text_en = en
	dl.shake = false
	return dl


## 木板從天而降後 → 隊伍對話（恐慌）
static func make_pre_dialog() -> Array:
	return [
		_line("panda", "normal",
			"嗚哇——！！怎麼會突然掉下這麼多木板！？",
			"Whoa—!! Why are so many planks suddenly falling!?"),
		_line("shark", "normal",
			"該死……這樣下去棋盤要被堵滿了。",
			"Damn it… at this rate the board's going to be jammed."),
		_line("dragon", "normal",
			"……（思考）……\n我必須做點什麼……如果是火焰……或許能燒穿這些木板。",
			"……(thinking)……\nI have to do something… with my flame… maybe I can burn through these planks."),
	]


## 玩家發動龍焰領域後 → 隊伍對話（讚賞 + 害羞）
static func make_post_dialog() -> Array:
	return [
		_line("panda", "normal",
			"哇——！龍哥好厲害！木板一下就被燒掉了！",
			"Wow—! Dragon, you're amazing! The planks burned right up!"),
		_line("dragon", "normal",
			"沒、沒什麼啦……",
			"I-it's nothing…"),
		_line("shark", "normal",
			"别停，繼續前進！",
			"Keep moving!"),
	]
