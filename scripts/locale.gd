## Locale — 全域語系管理（Autoload）。
## 簡易雙語支援：繁體中文 ("zh") 與英文 ("en")。
extends Node

const _DialogLine := preload("res://scripts/dialog_line.gd")

var current_locale: String = "zh"

# ── UI 翻譯字典 ──────────────────────────────────────────────
var _translations: Dictionary = {
	"BATTLE_RESULT": {"zh": "戰鬥結算", "en": "BATTLE RESULT"},
	"VICTORY": {"zh": "勝利！", "en": "VICTORY!"},
	"DEFEATED": {"zh": "戰敗", "en": "DEFEATED"},
	"GOLD": {"zh": "金幣", "en": "Gold"},
	"EXP": {"zh": "經驗值", "en": "EXP"},
	"LV_UP": {"zh": "升級！", "en": "Lv UP!"},
	"TAP_CONTINUE": {"zh": "點擊繼續", "en": "Tap to continue"},
	"RESTART": {"zh": "重新開始", "en": "Restart"},
	"RETURN_MAP": {"zh": "返回地圖", "en": "Return to Map"},
	"INVENTORY": {"zh": "背包", "en": "Inventory"},
	"NO_ITEMS": {"zh": "尚無物品", "en": "No items yet."},
	"BACK_MAP": {"zh": "返回地圖", "en": "Back to Map"},
	"CHARACTERS": {"zh": "角色", "en": "CHARACTERS"},
	"BACK": {"zh": "返回", "en": "Back"},
	"SKILLS": {"zh": "技能", "en": "Skills"},
	"PASSIVE": {"zh": "被動", "en": "Passive"},
	"ACTIVE": {"zh": "主動", "en": "Active"},
	"RESPONDING": {"zh": "回應", "en": "Responding"},
	"STAGE_BOSS": {"zh": "關卡 Boss", "en": "STAGE BOSS"},
	"SELECT_PARTY": {"zh": "選擇隊伍", "en": "SELECT PARTY"},
	"CONFIRM": {"zh": "確認", "en": "Confirm"},
	"EMBARK": {"zh": "出發", "en": "Embark"},
	"CANCEL": {"zh": "取消", "en": "Cancel"},
	"ROUNDS": {"zh": "波數", "en": "Rounds"},
	"GEM_DISTRIBUTION": {"zh": "寶石分佈", "en": "Gem Distribution"},
	"ELEMENT_DISTRIBUTION": {"zh": "元素分佈", "en": "Element Distribution"},
	"BOSS": {"zh": "頭目", "en": "BOSS"},
	"BACK_SHORT": {"zh": "返回", "en": "Back"},
	"NO_SELECTION": {"zh": "尚未選擇", "en": "No selection"},
	"SORT_BY": {"zh": "排序", "en": "Sort"},
	"SORT_LEVEL": {"zh": "等級", "en": "Lv"},
	"SORT_ATK": {"zh": "攻擊", "en": "ATK"},
	"SORT_HP": {"zh": "血量", "en": "HP"},
	"SORT_MAGIC": {"zh": "魔力", "en": "MAG"},
	"SORT_TYPE": {"zh": "屬性", "en": "Type"},
	"FIXED": {"zh": "固定", "en": "FIXED"},
	"SKIP": {"zh": "跳過", "en": "Skip"},
	"COOLDOWN": {"zh": "冷卻回合", "en": "Cooldown"},
	"FUSE_HINT": {"zh": "合成提示", "en": "Fuse"},
	"BLAST_AREA": {"zh": "爆發範圍", "en": "Blast"},
	"ROSTER": {"zh": "角色名冊", "en": "ROSTER"},
	"PARTY": {"zh": "隊伍", "en": "Party"},
	"CHAR_SELECTION": {"zh": "角色選擇", "en": "Characters Selection"},
	"STAGE_SELECT": {"zh": "關卡選擇", "en": "STAGE SELECT"},
	"Dev Stage": {"zh": "實戰訓教", "en": "Stage 1 — Slay the Slimes"},
}


## 取得 UI 翻譯文字
func tr_ui(key: String) -> String:
	var entry: Dictionary = _translations.get(key, {})
	if entry.is_empty():
		return key
	return entry.get(current_locale, entry.get("en", key))


## 從 DialogLine 取得當前語系的文字
func get_dialog_text(line: _DialogLine) -> String:
	if current_locale == "en":
		return line.text_en if not line.text_en.is_empty() else line.text_zh
	return line.text_zh if not line.text_zh.is_empty() else line.text_en
