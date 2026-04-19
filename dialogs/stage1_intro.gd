## Stage 1 序章對話資料 — 元素學院開學，Husky 教學，Fox / Polar / Raccoon 互動。
## 用法：preload("res://dialogs/stage1_intro.gd").make()
class_name Stage1Intro
extends RefCounted

const _DialogLine := preload("res://scripts/dialog_line.gd")
const _DialogSequence := preload("res://scripts/dialog_sequence.gd")


static func make() -> _DialogSequence:
	var seq := _DialogSequence.new()

	# 背景
	if ResourceLoader.exists("res://assets/background/classroom.png"):
		seq.background = load("res://assets/background/classroom.png")

	# 音樂
	var bgm: AudioStream = null
	if ResourceLoader.exists("res://assets/music/Wild Arms 2 - The Town to the Western Winds.mp3"):
		bgm = load("res://assets/music/Wild Arms 2 - The Town to the Western Winds.mp3")

	seq.lines = [
		_line("", "normal", "left", "none",
			"元素學院——古老的石造教室裡，陽光透過彩繪玻璃灑落，空氣中瀰漫著微弱的魔力氣息。\n新生們在木椅上坐得筆直，期待又緊張地望向講台。",
			"The Elemental Academy — sunlight filters through stained glass into the ancient stone classroom. A faint hum of magic lingers in the air.\nThe freshmen sit upright in their wooden chairs, gazing at the podium with a mix of excitement and nervousness.",
			bgm),
		_line("husky", "normal", "left", "enter",
			"歡迎來到元素學院。我們的世界由四大元素構成——水、火、草、光。",
			"Welcome to the Elemental Academy. Our world is shaped by four elements — Water, Fire, Leaf, and Light."),
		_line("husky", "normal", "left", "none",
			"你們每個人體內都流淌著元素之力。學會引導它，就能施展強大的魔法。",
			"Each of you carries elemental energy within. Learn to channel it, and you can perform powerful magic."),
		_line("fox", "normal", "right", "enter",
			"（小聲）哇，聽起來超帥的！我已經等不及了！",
			"(whispering) Wow, that sounds so cool! I can't wait!"),
		_line("raccoon", "normal", "right", "enter",
			"噓⋯⋯安靜啦小狐，老師在看你了。",
			"Shh... keep it down, Fox. The professor is looking at you."),
		_line("husky", "normal", "left", "none",
			"元素之間存在相剋關係——火焚草、草吸水、水滅火。記住這些，戰場上會救你一命。",
			"Elements counter each other — Fire burns Leaf, Leaf absorbs Water, Water douses Fire. Remember this. It could save your life."),
		_line("polar", "normal", "right", "enter",
			"老師，那光元素呢？光跟誰相剋？",
			"Professor, what about Light? What is Light strong against?"),
		_line("husky", "normal", "left", "none",
			"光⋯⋯是特殊的元素。目前來說，沒有任何元素能剋制它。",
			"Light... is a special element. As of now, nothing counters it."),
		_line("raccoon", "normal", "right", "none",
			"欸？那這樣不就不平衡了嗎？",
			"Huh? Then doesn't that make it unbalanced?"),
		_line("husky", "normal", "left", "none",
			"⋯⋯",
			"..."),
		_line("fox", "normal", "right", "none",
			"老師不回答了欸⋯⋯哈哈，一定有什麼秘密！",
			"The professor isn't answering... haha, there must be a secret!"),
		_line("polar", "normal", "right", "none",
			"也許以後會學到吧？老師的表情好嚴肅⋯⋯",
			"Maybe we'll learn about it later? The professor looks so serious..."),
		_line("raccoon", "normal", "right", "none",
			"我覺得⋯⋯還是不要追問比較好⋯⋯",
			"I think... it's better not to ask further..."),
		_line("husky", "normal", "left", "none",
			"好了，別胡鬧了。",
			"Alright, stop messing around."),
		_line("husky", "normal", "left", "none",
			"今天是你們的第一堂實戰課。準備好面對真正的魔物了嗎？",
			"Today is your first practical combat lesson. Are you ready to face real monsters?"),
		_line("fox", "normal", "right", "none",
			"終於！我等這一天等好久了！衝啊！！",
			"Finally! I've been waiting forever for this! Let's gooo!!"),
		_line("raccoon", "normal", "right", "none",
			"嗚嗚⋯⋯我還沒準備好⋯⋯",
			"*whimpers* ...I'm not ready yet..."),
		_line("husky", "normal", "left", "none",
			"出發。記住——元素之力不是武器，而是守護的意志。",
			"Move out. Remember — elemental power is not a weapon. It is the will to protect."),
	]
	return seq


static func _line(char_id: String, emotion: String, pos: String, action: String, zh: String, en: String, music: AudioStream = null) -> _DialogLine:
	var dl := _DialogLine.new()
	dl.character_id = char_id
	dl.emotion = emotion
	dl.position = pos
	dl.action = action
	dl.text_zh = zh
	dl.text_en = en
	dl.shake = true
	dl.music = music
	return dl
