## Stage 1-3 Owen sanctuary story battle dialogue.
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


static func _narration(zh: String, en: String) -> _DialogLine:
	return _line("", "normal", zh, en)


static func make_turn1_dialog() -> Array:
	return [
		_line("husky", "normal",
			"你為什麼要這樣做！",
			"Why are you doing this!"),
		_line("owen", "normal",
			"我受夠像你這種偽善者統治這個國家了。",
			"Im sick of hypocrite like you ruling the country.", "right"),
		_line("owen", "normal",
			"迎接一個再也沒有光的世界吧。",
			"Prepare for a world with no light anymore.", "right"),
	]


static func make_husky_near_death_dialog() -> Array:
	return [
		_line("husky", "normal",
			"光元素，好稀薄...",
			"Damn... the light element is so scarce..."),
		_line("husky", "normal",
			"到此為止了嗎...",
			"Could this be my end?"),
		_line("dragon", "normal",
			"住手!!",
			"Stop!!"),
	]


static func make_rescue_dialog() -> Array:
	return [
		_line("panda", "normal",
			"老師！你還好嗎？",
			"Teacher! Are you okay?"),
		_line("shark", "normal",
			"看來我們總算趕上了。",
			"Guess we have made up on time."),
		_line("dragon", "normal",
			"老師！你說過團隊合作！永遠都要團隊合作！",
			"Teacher! You said teamwork! Always teamwork!"),
		_line("husky", "normal",
			"這不是你們能應付戰鬥！快點離開這裡！",
			"This is not a fight you can handle! Get out of here!"),
		_line("dragon", "normal",
			"我們已經是初級冒險者了！可不要小看我們！",
			"We are already novice adventurers! Don't underestimate us!"),
		_line("panda", "normal",
			"你是誰？為什麼要傷害老師？",
			"Who are you? Why are you hurting teacher?"),
		_line("owen", "normal",
			"蛆蟲小輩，一同收拾了你們。",
			"...", "right"),
		_line("dragon", "normal",
			"管他的，來大幹一場！",
			"Screw it, lets just 大幹一場!"),
	]


static func make_light_hint_dialog() -> Array:
	return [
		_line("dragon", "normal",
			"為什麼他完全沒受傷？",
			"Why he is not hurting at all?"),
		_line("shark", "normal",
			"我們的攻擊對他沒有作用！",
			"Our attack has no effect on him!"),
		_line("panda", "normal",
			"天吶！！該怎麼辦？！",
			"Oh no!! What should we do?!"),
		_line("husky", "normal",
			"只有光元素才能對它造成傷害。",
			"Only light element can hurt him."),
			_line("husky", "normal",
			"這裡的光元素已經不多了。",
			"There is not much light element left here."),
		_line("husky", "normal",
			"你們答應我，記住一件事。",
			"Guys, promise me to remember one thing."),
		_line("husky", "normal",
			"永遠不要拋棄心中的希望之光。",
			"Never abandon the light of hope in your heart."),
	]


static func make_finale_dialog() -> Array:
	return [
		_line("owen", "normal",
			"不可能……這源源不絕的希望之光...",
			"Impossible... this endless light of hope...", "right"),
		_line("husky", "normal",
			"這或許能為你們爭取足夠時間逃跑...",
			"This may buy you guys enough time to escape..."),
		_line("husky", "normal",
			"跑……現在就跑！！",
			"Run..run now!!"),
		_narration("Husky 倒下了。", "Husky fell down."),
		_line("panda", "normal",
			"老師！",
			"Teacher!"),
		_line("dragon", "normal",
			"老師！",
			"Teacher!"),
		_line("owen", "normal",
			"我還以為你能撐久一點。",
			"I thought you could last a little longer.", "right"),
		_line("dragon", "normal",
			"你這混蛋！！",
			"You damn!!"),
		_line("shark", "normal",
			"米洛！我們得跑！！不能辜負老師的犧牲！！",
			"Run! Teacher said run!!"),
		_line("dragon", "normal",
			"我不會拋下我的老師！",
			"I will not abandon my teacher!"),
		_line("panda", "normal",
			"米洛……老師……",
			"米洛……老師……",
			"Milo... Teacher..."),
		_line("panda", "normal",
			"*哭泣*",
			"*cry*"),
		_line("owen", "normal",
			"衛兵，抓著他們。",
			"Guards, grab them.", "right"),
		_line("shark", "normal",
			"快跑！！",
			"Run!!"),
		_line("dragon", "normal",
			"我不走！！你要走就自己走，膽小鬼！",
			"I am not leaving!! If you gonna leave leave by yourself coward!"),
		_line("shark", "normal",
			"*揍了 米洛 一拳*",
			"*punched milo*"),
		 _line("shark", "normal",
			"清醒一點！！這不是什麼逞英雄遊戲！！",
			"Wake up!! This is not a game of heroics!!"),
			_line("panda", "normal",
			"！！！",
			"!!!"),
		_line("dragon", "normal",
			"！！！",
			"!!!"),
		_narration("埃德 抓住 米洛 和 潘 的手，逃離了現場。", "Ed grabbed milo and pan's hand and escaped the 現場."),
	]
