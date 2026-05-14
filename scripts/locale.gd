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
	"EXIT": {"zh": "離開", "en": "Exit"},
	"INVENTORY": {"zh": "背包", "en": "Inventory"},
	"NO_ITEMS": {"zh": "尚無物品", "en": "No items yet."},
	"BACK_MAP": {"zh": "返回地圖", "en": "Back to Map"},
	"CHARACTERS": {"zh": "角色", "en": "CHARACTERS"},
	"BACK": {"zh": "返回", "en": "Back"},
	"SKILLS": {"zh": "技能", "en": "Skills"},
	"PASSIVE": {"zh": "被動", "en": "Passive"},
	"ACTIVE": {"zh": "主動", "en": "Active"},
	"RESPONDING": {"zh": "合成", "en": "Fuse"},
	"FUSE": {"zh": "合成", "en": "Fuse"},
	"STAGE_BOSS": {"zh": "關卡 Boss", "en": "STAGE BOSS"},
	"SELECT_PARTY": {"zh": "選擇隊員", "en": "SELECT PARTY"},
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
	"ALL": {"zh": "全部", "en": "All"},
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
	"COMBO": {"zh": "連擊", "en": "Combo"},
	"UPPER_GEM": {"zh": "上級寶石", "en": "Upper Gem"},
	"ROSTER": {"zh": "角色名冊", "en": "ROSTER"},
	"PARTY": {"zh": "隊伍", "en": "Party"},
	"CHAR_SELECTION": {"zh": "角色選擇", "en": "Characters Selection"},
	"STAGE_SELECT": {"zh": "關卡選擇", "en": "STAGE SELECT"},
	"MAP": {"zh": "地圖", "en": "Map"},
	"Dev Stage": {"zh": "實戰訓教", "en": "Stage 1 — Slay the Slimes"},

	# ── 融合技能名稱與描述 ──
	"Fireball": {"zh": "火球", "en": "Fireball"},
	"Fireball DESC": {"zh": "在點擊處生成火球寶石；點擊後造成 3×3 範圍爆炸，並向上下左右各延伸 1 格。", "en": "Create a Fireball gem at tapped cell. Click to detonate: 3×3 area plus 1 extra cell in each cardinal direction."},
	"Fire Pillar": {"zh": "火柱", "en": "Fire Pillar"},
	"Fire Pillar DESC": {"zh": "在點擊處生成火柱寶石；點擊後依方向引發整列/整欄爆炸。", "en": "Create a Fire Pillar gem; row/column blast on click."},
	"Justice Slash": {"zh": "正義斬", "en": "Justice Slash"},
	"Justice Slash DESC": {"zh": "在點擊處生成聖十字寶石；點擊後造成 X 形範圍傷害並回血。", "en": "Create a Saint Cross gem. X-shaped blast and heal on click."},
	"Water Slash": {"zh": "狂鯊連撃", "en": "Shark Frenzy"},
	"Water Slash DESC": {"zh": "在點擊處生成狂鯊寶石。點擊後連鎖貫穿所有狂鯊並沿欄縱向爆炸。", "en": "Place a Shark Frenzy gem. On tap, chain through all Shark gems and blast each column."},
	"Snowball": {"zh": "雪球", "en": "Snowball"},
	"Snowball DESC": {"zh": "在點擊處生成雪球寶石；點擊後造成 3×3 範圍傷害。", "en": "Create a Snowball gem. 3×3 area blast on click."},
	"Leaf Shield": {"zh": "葉盾", "en": "Leaf Shield"},
	"Leaf Shield DESC": {"zh": "在點擊處生成葉盾寶石;點擊回復 ATK×5 HP;吸收敵方攻擊(50%減傷)。", "en": "Create a Leaf Shield gem. Click to heal ATK×5. Absorbs enemy attacks (50% dmg reduction)."},
	"Porcupine": {"zh": "召喚:豪豬", "en": "Summon: Porcupine"},
	"Porcupine DESC": {"zh": "在點擊處召喚豪豬寶石。爆炸時只消除自身。每回合所有角色攻擊後,以全隊魔力 × 0.5 攻擊敵方。", "en": "Summon a Porcupine gem at the tapped cell. Self-blast only. After all party attacks each turn, attacks the first enemy for ΣTeamMagic × 0.5."},
	"Turtle": {"zh": "召喚:烏龜", "en": "Summon: Turtle"},
	"Turtle DESC": {"zh": "在點擊處召喚烏龜寶石。爆炸時只消除自身。每回合所有角色攻擊後,以全隊魔力 × 0.8 為玩家回血。", "en": "Summon a Turtle gem at the tapped cell. Self-blast only. After all party attacks each turn, heals the player for ΣTeamMagic × 0.8."},
	"Bamboo Supply": {"zh": "竹葉補給", "en": "Bamboo Supply"},
	"Bamboo Supply DESC": {"zh": "在點擊處生成竹葉補給寶石；爆炸時消除周圍 8 格並回復 Panda 魔力 × 1.6 HP。", "en": "Create a Bamboo Supply gem. Blasts surrounding 8 cells and heals Panda for magic × 1.6."},

	# ── 角色名稱 ──
	"Boar": {"zh": "野豬", "en": "Boar"},
	"Raccoon": {"zh": "浣熊", "en": "Raccoon"},
	"Elder Raccoon": {"zh": "浣熊長老", "en": "Elder Raccoon"},
	"Panda": {"zh": "阿潘", "en": "Panda"},
	"Fox": {"zh": "小狐", "en": "Fox"},
	"Husky": {"zh": "哈士奇", "en": "Husky"},
	"Polar": {"zh": "阿極", "en": "Polar"},
	"Dragon": {"zh": "小焰", "en": "Dragon"},
	"Shark": {"zh": "鯊魚", "en": "Shark"},
	"Flame": {"zh": "炎", "en": "Flame"},
	"Tide": {"zh": "潮", "en": "Tide"},
	"Hero": {"zh": "英雄", "en": "Hero"},

	# ── 對話用角色暱稱（與正式名稱可不同；key = "DIALOG_" + char_id 大寫） ──
	"DIALOG_husky":   {"zh": "哈士奇老師", "en": "Prof. Husky"},
	"DIALOG_fox":     {"zh": "小狐",       "en": "Fox"},
	"DIALOG_polar":   {"zh": "阿極",       "en": "Polar"},
	"DIALOG_raccoon": {"zh": "小浣",       "en": "Raccoon"},
	"DIALOG_boar":    {"zh": "山豬",       "en": "Boar"},
	"DIALOG_panda":   {"zh": "阿潘",       "en": "Panda"},
	"DIALOG_dragon":  {"zh": "小焰",       "en": "Dragon"},
	"DIALOG_shark":   {"zh": "鯊鯊",       "en": "Shark"},

	# ── 主動技能名稱與描述 ──
	"Attack Form": {"zh": "攻擊形態", "en": "Attack Form"},
	"Attack Form DESC": {"zh": "將棋盤上所有火寶石轉換為水寶石。CD：5 回合。", "en": "Convert all fire gems on the board into water gems. CD: 5 turns."},
	"Tranquil Mirror": {"zh": "止水明鏡", "en": "Tranquil Mirror"},
	"Tranquil Mirror DESC": {"zh": "將棋盤上所有火寶石轉換為水寶石。CD：5 回合。", "en": "Convert all fire gems on the board into water gems. CD: 5 turns."},
	"居合。水": {"zh": "居合。水", "en": "Iai: Tidal"},
	"居合。水 DESC": {"zh": "消除棋盤上所有水寶石，數量儲存於下一次水屬性攻擊時併入。", "en": "Blast all water gems on the board. The destroyed count is added to the next water attack."},
	"Dragon Flame Domain": {"zh": "龍焰領域", "en": "Dragon Flame Domain"},
	"Dragon Flame Domain DESC": {"zh": "選擇棋盤上一塊區域：火球形狀（3×3 + 延伸）內的寶石全部轉為火寶石。CD：3 回合。", "en": "Select an area on the board: all gems in the fireball-shaped area (3×3 + extensions) are converted to fire gems. CD: 3 turns."},
	"There shall be light": {"zh": "光輝降臨", "en": "There shall be light"},
	"There shall be light DESC": {"zh": "進入選擇模式：懸停預覽十字範圍，點擊確認將該範圍寶石轉為光寶石。CD：3 回合。", "en": "Enter selection mode: hover to preview a cross shape, click to convert those gems into light gems. CD: 3 turns."},
	"Resurgence": {"zh": "生息", "en": "Resurgence"},
	"Resurgence DESC": {"zh": "選擇一顆寶石，將其上下左右四鄰轉換為相同元素。CD：4 回合。", "en": "Select a gem; convert its four neighbors to the same element. CD: 4 turns."},
	"Resurgence+": {"zh": "生息.強", "en": "Resurgence+"},
	"Resurgence+ DESC": {"zh": "選擇一顆寶石，將其上下左右四鄰轉換為相同元素，並使被點擊的寶石獲得 X5 效果（消除/連鎖/合成時計為 5 顆）。CD：6 回合。", "en": "Select a gem; convert its four neighbors to the same element and grant the tapped gem X5 (counts as 5 when blasted/chained/fused). CD: 6 turns."},
	"Snowball Fight": {"zh": "打雪仗", "en": "Snowball Fight"},
	"Snowball Fight DESC": {"zh": "動員棋盤上所有雪球寶石飛向目標敵人，每顆造成 ATK×10 傷害。CD：5 回合。", "en": "Mobilize all Snowball gems on the board to attack the targeted enemy. Each snowball deals ATK×10 damage. CD: 5 turns."},
	"Blast": {"zh": "爆炸", "en": "Blast"},
	"Blast DESC": {"zh": "由上至下爆破整個棋盤的每一行。CD：1 回合。", "en": "Blast every row from top to bottom. CD: 1 turn."},

	# ── 被動技能名稱與描述 ──
	"Drinking": {"zh": "飲水", "en": "Drinking"},
	"Drinking DESC": {"zh": "水寶石攻擊時，額外回復攻擊傷害的 50%。", "en": "Water gems also heal you for 50% of attack damage."},
	"Photosynthesis": {"zh": "光合作用", "en": "Photosynthesis"},
	"Photosynthesis DESC": {"zh": "每回合開始時，將 3 顆寶石轉為葉寶石（優先紅 > 藍）。", "en": "At the start of each turn, convert 3 gems into leaf gems (priority Red > Blue)."},

	# ── 戰鬥日誌標籤 ──
	"LOG_LEAF_STORM": {"zh": "葉風暴", "en": "Leaf Storm"},
	"LOG_LEAF_SHIELD_HEAL": {"zh": "葉盾", "en": "Leaf Shield"},
	"LOG_SAINT_CROSS": {"zh": "聖十字", "en": "Saint Cross"},
	"LOG_HEAL": {"zh": "回覆", "en": "Heal"},
	"LOG_STORE": {"zh": "儲存", "en": "Stored"},
	"LOG_CONVERT_TO": {"zh": "轉換為", "en": "→"},
	"TAP_HERO_TO_USE_SKILL": {"zh": "點擊角色使用技能", "en": "Tap the hero to use skill"},
}


## 取得 UI 翻譯文字
func tr_ui(key: String) -> String:
	var entry: Dictionary = _translations.get(key, {})
	if entry.is_empty():
		return key
	return entry.get(current_locale, entry.get("en", key))


## 嘗試翻譯 key；若無對應條目則回傳 fallback（用於 .tres 描述等可能未本地化的字串）。
func tr_or(key: String, fallback: String) -> String:
	if key == "":
		return fallback
	var entry: Dictionary = _translations.get(key, {})
	if entry.is_empty():
		return fallback
	return entry.get(current_locale, entry.get("en", fallback))


## 從 DialogLine 取得當前語系的文字
func get_dialog_text(line: _DialogLine) -> String:
	if current_locale == "en":
		return line.text_en if not line.text_en.is_empty() else line.text_zh
	return line.text_zh if not line.text_zh.is_empty() else line.text_en
