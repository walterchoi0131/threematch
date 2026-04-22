## Stage 1 序章對話資料 — 元素學院開學，Husky 教學，Dragon / Shark / Raccoon 互動。
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
			"元素學院——古老的石造教室裡，陽光透過彩繪玻璃灑落。空氣中瀰漫著微弱的魔力氣息。\n新生們坐得筆直，緊張地望向講台。",
			"The Elemental Academy — sunlight filters through stained glass into the ancient stone classroom.\nThe freshmen sit upright, staring nervously at the podium.",
			bgm),
		_line("husky", "normal", "left", "enter",
			"歡迎來到元素學院。我們的世界由四大元素構成——火、水、草、光。",
			"Welcome to the Elemental Academy. Our world is shaped by four elements — Fire, Water, Leaf, and Light."),
		_line("dragon", "normal", "right", "enter",
			"老師老師！所以我們可以噴火對嗎！！我超會噴火的！！",
			"Professor, professor! So we get to breathe fire, right?! I'm SO good at breathing fire!!"),
		_line("shark", "normal", "right", "enter",
			"……那是你個人的事。別打斷上課。",
			"...That's your own business. Don't interrupt the lesson."),
		_line("raccoon", "normal", "right", "none",
			"（小聲）鯊鯊說話好嚇人⋯⋯",
			"(quietly) Shark is kind of scary..."),
		_line("husky", "normal", "left", "none",
			"元素之間存在相剋關係。火焚草、草吸水、水滅火。記住這些，戰場上會救你一命。",
			"Elements counter each other — Fire burns Leaf, Leaf absorbs Water, Water douses Fire. Remember this."),
		_line("dragon", "normal", "right", "none",
			"所以水剋草、草剋火、火剋水？！對嗎老師！我答對了嗎！",
			"So Water beats Leaf, Leaf beats Fire, Fire beats Water?! Right?! Did I get it right, Professor?!"),
		_line("shark", "normal", "right", "none",
			"完全反過來。",
			"You got it completely backwards."),
		_line("dragon", "normal", "right", "none",
			"啊！？",
			"Huh?!"),
		_line("raccoon", "normal", "right", "none",
			"⋯⋯火焚草，所以火剋草，老師剛才說了。",
			"...Fire burns Leaf, so Fire beats Leaf. The professor just said that."),
		_line("dragon", "normal", "right", "none",
			"喔喔喔！！對！！我早就知道了！！",
			"Ohhhh!! Right!! I knew that all along!!"),
		_line("shark", "normal", "right", "none",
			"（嘆氣）",
			"(sighs)"),
		_line("husky", "normal", "left", "none",
			"那麼，光元素呢？",
			"Now then — what about the Light element?"),
		_line("dragon", "normal", "right", "none",
			"光！！光是最強的吧！！因為光可以照亮黑暗！！",
			"Light!! Light is definitely the strongest!! Because light shines through darkness!!"),
		_line("shark", "normal", "right", "none",
			"……目前沒有已知的剋制元素。這不等於「最強」，只是尚未解明。",
			"...There is currently no known counter element. That does not mean 'strongest.' It means unexplained."),
		_line("raccoon", "normal", "right", "none",
			"⋯⋯為什麼老師的表情變奇怪了⋯⋯",
			"...Why does the professor's expression look strange all of a sudden..."),
		_line("husky", "normal", "left", "none",
			"⋯⋯",
			"..."),
		_line("dragon", "normal", "right", "none",
			"老師你沒事吧！！臉色好白！！",
			"Professor, are you okay?! Your face went pale!!"),
		_line("shark", "normal", "right", "none",
			"閉嘴。",
			"Be quiet."),
		_line("husky", "normal", "left", "none",
			"好了。今天是你們第一堂實戰課。前往指定地點，消滅出沒的魔物。",
			"That's enough. Today is your first practical combat lesson. Proceed to the designated area and eliminate the monsters."),
		_line("dragon", "normal", "right", "none",
			"耶耶耶！！終於可以打架了！！衝啊！！",
			"YES YES YES!! Finally we get to fight!! CHARGE!!"),
		_line("shark", "normal", "right", "none",
			"……先等隊形好嗎。",
			"...Can you wait for formation first?"),
		_line("raccoon", "normal", "right", "none",
			"我⋯⋯我跟在後面就好⋯⋯",
			"I'll... I'll just stay in the back..."),
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
