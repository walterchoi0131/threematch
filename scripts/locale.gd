## Locale — 全域語系管理（Autoload）。
## 簡易雙語支援：繁體中文 ("zh") 與英文 ("en")。
extends Node

const _DialogLine := preload("res://scripts/dialog_line.gd")

var current_locale: String = "zh"

# ── UI 翻譯字典 ──────────────────────────────────────────────
var _translations: Dictionary = {
	"BATTLE_RESULT": {"zh": "戰鬥結算", "en": "BATTLE RESULT"},
	"VICTORY": {"zh": "勝利！", "en": "VICTORY!"},
	"COMPLETE": {"zh": "完成", "en": "COMPLETE"},
	"DEFEATED": {"zh": "戰敗", "en": "DEFEATED"},
	"PUZZLE_WRONG_DEFEAT": {"zh": "再試一次?", "en": "Try again?"},
	"PUZZLE_TURNS_LEFT": {"zh": "剩餘步數", "en": "Turn Left"},
	"GOLD": {"zh": "金幣", "en": "Gold"},
	"LOOT": {"zh": "戰利品", "en": "Loot"},
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
	"NO_PASSIVE": {"zh": "沒有被動技能。", "en": "No passive skills."},
	"ENEMY_PASSIVE_REQUIREMENT": {"zh": "被動條件", "en": "Passive Gate"},
	"Gem Gate": {"zh": "顆數元素盾", "en": "Gem Gate"},
	"Gem Gate DESC": {"zh": "一回合內爆破少於 %d 顆%s寶石才能造成傷害。", "en": "Requires %d+ %s gems blasted this turn to deal normal damage."},
	"ELEMENT_FIRE": {"zh": "火", "en": "Fire"},
	"ELEMENT_WATER": {"zh": "水", "en": "Water"},
	"ELEMENT_LEAF": {"zh": "葉", "en": "Leaf"},
	"ELEMENT_LIGHT": {"zh": "光", "en": "Light"},
	"ELEMENT_DARK": {"zh": "暗", "en": "Dark"},
	"FUSE": {"zh": "合成", "en": "Fuse"},
	"STAGE_BOSS": {"zh": "關卡 Boss", "en": "STAGE BOSS"},
	"SELECT_PARTY": {"zh": "選擇隊員", "en": "SELECT PARTY"},
	"DEPLOYED": {"zh": "出戰", "en": "DEPLOYED"},
	"AUTO_TEAM": {"zh": "自動組隊", "en": "Auto Team"},
	"ENEMY_INTENT_DUEL": {"zh": "決鬥", "en": "Duel"},
	"CONFIRM": {"zh": "確認", "en": "Confirm"},
	"EMBARK": {"zh": "出發", "en": "Embark"},
	"CANCEL": {"zh": "取消", "en": "Cancel"},
	"ROUNDS": {"zh": "波數", "en": "Rounds"},
	"ROUND_SWITCH_TITLE": {"zh": "回合 %d/%d", "en": "Round %d/%d"},
	"GEM_DISTRIBUTION": {"zh": "寶石分佈", "en": "Gem Distribution"},
	"ELEMENT_DISTRIBUTION": {"zh": "元素分佈", "en": "Element Distribution"},
	"BOSS": {"zh": "頭目", "en": "BOSS"},
	"BACK_SHORT": {"zh": "返回", "en": "Back"},
	"NO_SELECTION": {"zh": "尚未選擇", "en": "No selection"},
	"START_TUTORIAL_OK": {"zh": "好咧!", "en": "OK"},
	"START_TUTORIAL_SKIP": {"zh": "好好好", "en": "Skip"},
	"START_TUTORIAL_NEXT": {"zh": "下一頁", "en": "Next"},
	"SORT_BY": {"zh": "排序", "en": "Sort"},
	"ALL": {"zh": "全部", "en": "All"},
	"SORT_LEVEL": {"zh": "等級", "en": "Lv"},
	"SORT_ATK": {"zh": "攻擊", "en": "ATK"},
	"SORT_HP": {"zh": "血量", "en": "HP"},
	"SORT_MAGIC": {"zh": "魔力", "en": "MAG"},
	"SORT_TYPE": {"zh": "屬性", "en": "Type"},
	"FIXED": {"zh": "固定", "en": "FIXED"},
	"SKIP": {"zh": "跳過", "en": "Skip"},
	"FAST_FORWARD": {"zh": "快進", "en": "Fast Forward"},
	"COOLDOWN": {"zh": "冷卻回合", "en": "Cooldown"},
	"FUSE_HINT": {"zh": "符石合成", "en": "Gem Fuse"},
	"BLAST_AREA": {"zh": "爆發範圍", "en": "Blast"},
	"COMBO": {"zh": "連擊", "en": "Combo"},
	"UPPER_GEM": {"zh": "上級寶石", "en": "Upper Gem"},
	"JOB": {"zh": "定位", "en": "Job"},
	"JOB_ATTACKER": {"zh": "攻擊手", "en": "Attacker"},
	"JOB_BREAKER": {"zh": "爆破專家", "en": "Breaker"},
	"JOB_TACTICTIAN": {"zh": "戰術大師", "en": "Tactician"},
	"JOB_WIZARD": {"zh": "巫師", "en": "Wizard"},
	"FUSE_SUMMARY_BOARD_BLAST": {"zh": "爆破版面，連擊準備", "en": "Board blast, Chain setup"},
	"FUSE_SUMMARY_CHAIN_BURST": {"zh": "累積寶石，單次爆發", "en": "Acummulate and single burst"},
	"FUSE_SUMMARY_HEAL": {"zh": "生命恢復", "en": "Life recovery"},
	"FUSE_SUMMARY_BLAST_HEAL_ATTACK": {"zh": "爆破版面，生命恢復，攻擊", "en": "Board blast, life recovery, attack"},
	"FUSE_SUMMARY_SINGLE_BURST": {"zh": "單次爆發", "en": "Single burst"},
	"FUSE_SUMMARY_ATTACK": {"zh": "攻擊", "en": "Attack"},
	"Lightbreak Attack": {"zh": "破光攻撃", "en": "Lightbreak Attack"},
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
	"Iceball": {"zh": "冰球", "en": "Iceball"},
	"Iceball DESC": {"zh": "8 顆以上水寶石合成時，在點擊處生成 INSTANT 冰球。冰球會立刻飛向目標敵人，造成 Polarz 魔力 × 10 傷害，且不消耗回合。", "en": "Fuse 8+ water gems to create an INSTANT Iceball. It immediately flies to the target enemy, deals Polarz magic x10 damage, and does not consume the turn."},
	"Leaf Shield": {"zh": "葉盾", "en": "Leaf Shield"},
	"Leaf Shield DESC": {"zh": "在點擊處生成葉盾寶石;點擊回復 ATK×5 HP;吸收敵方攻擊(50%減傷)。", "en": "Create a Leaf Shield gem. Click to heal ATK×5. Absorbs enemy attacks (50% dmg reduction)."},
	"Porcupine": {"zh": "召喚:豪豬", "en": "Summon: Porcupine"},
	"Porcupine DESC": {"zh": "在點擊處召喚建築豪豬寶石。建築爆發範圍為自身 1x1，並擁有內在值；長按 2 秒可拆除且不消耗回合。每回合所有角色攻擊後,以全隊魔力 × 0.5 攻擊敵方。", "en": "Summon a building Porcupine gem at the tapped cell. Buildings blast only their own 1x1 cell and keep their intrinsic value; long-press for 2s to dismantle without consuming the turn. After all party attacks each turn, attacks the first enemy for ΣTeamMagic × 0.5."},
	"Turtle": {"zh": "召喚:烏龜", "en": "Summon: Turtle"},
	"Turtle DESC": {"zh": "在點擊處召喚建築烏龜寶石。建築爆發範圍為自身 1x1，並擁有內在值；長按 2 秒可拆除且不消耗回合。每回合所有角色攻擊後,以全隊魔力 × 0.8 為玩家回血。", "en": "Summon a building Turtle gem at the tapped cell. Buildings blast only their own 1x1 cell and keep their intrinsic value; long-press for 2s to dismantle without consuming the turn. After all party attacks each turn, heals the player for ΣTeamMagic × 0.8."},
	"Bamboo Supply": {"zh": "竹葉補給", "en": "Bamboo Supply"},
	"Bamboo Supply DESC": {"zh": "在點擊處生成竹葉補給寶石；爆炸時消除周圍 8 格並回復阿潘魔力 × 4.8 HP。", "en": "Create a Bamboo Supply gem. Blasts surrounding 8 cells and heals Pan for magic × 4.8."},
	"Wood Spear": {"zh": "木槍", "en": "Wood Spear"},
	"Wood Spear DESC": {"zh": "7 顆以上葉寶石合成時，在點擊處生成木槍寶石；點擊該格上半部時朝上，下半部時朝下。爆發會沿方向貫穿至第一個障礙或邊界，形成箭頭並穿透障礙後 1 格，可破壞木板與木結構。", "en": "Fuse 7+ leaf gems to create a Wood Spear gem at the tapped cell. Tapping the upper half of that cell points it up; tapping the lower half points it down. On blast, it pierces to the first obstacle or edge, forms an arrow head, penetrates 1 cell past obstacles, and breaks breakable structures."},
	"Wood Spear DESC DYNAMIC": {"zh": "%d 顆以上葉寶石合成時，在點擊處生成木槍寶石。點擊該格上半部時朝上，下半部時朝下。爆發會沿方向貫穿至第一個障礙或邊界，形成箭頭並穿透障礙後 1 格，可破壞木板與木結構。", "en": "Fuse %d+ leaf gems to create a Wood Spear gem at the tapped cell. Tapping the upper half of that cell points it up; tapping the lower half points it down. On blast, it pierces to the first obstacle or edge, forms an arrow head, penetrates 1 cell past obstacles, and breaks breakable structures."},
	"Wood Spear DESC DYNAMIC PIERCE": {"zh": "%d 顆以上葉寶石合成時，在點擊處生成木槍寶石。點擊該格上半部時朝上，下半部時朝下。爆發會破壞可破壞障礙並繼續飛行，直到不可破壞障礙或邊界。", "en": "Fuse %d+ leaf gems to create a Wood Spear gem at the tapped cell. Tapping the upper half points it up; tapping the lower half points it down. On blast, it breaks breakable obstacles and keeps flying until an unbreakable obstacle or the edge."},

	# ── 角色名稱 ──
	"Boar": {"zh": "野豬", "en": "Boar"},
	"Raccoon": {"zh": "浣熊", "en": "Raccoon"},
	"Elder Raccoon": {"zh": "浣熊長老", "en": "Elder Raccoon"},
	"Panda": {"zh": "阿潘", "en": "Pan"},
	"Fox": {"zh": "小狐", "en": "Fox"},
	"Husky": {"zh": "索爾", "en": "Thor"},
	"Thor": {"zh": "索爾", "en": "Thor"},
	"Polar": {"zh": "阿極", "en": "Polar"},
	"Polarz": {"zh": "極極", "en": "Polarz"},
	"Dragon": {"zh": "米洛", "en": "Milo"},
	"Shark": {"zh": "埃德", "en": "Ed"},
	"Pan": {"zh": "阿潘", "en": "Pan"},
	"Milo": {"zh": "米洛", "en": "Milo"},
	"Ed": {"zh": "埃德", "en": "Ed"},
	"Gory": {"zh": "戈爾", "en": "Gory"},
	"Owen": {"zh": "奧云", "en": "Owen"},
	"Flame": {"zh": "炎", "en": "Flame"},
	"Tide": {"zh": "潮", "en": "Tide"},
	"Hero": {"zh": "英雄", "en": "Hero"},

	# ── 對話用角色暱稱（與正式名稱可不同；key = "DIALOG_" + char_id 大寫） ──
	"DIALOG_husky":   {"zh": "索爾", "en": "Thor"},
	"DIALOG_fox":     {"zh": "小狐",       "en": "Fox"},
	"DIALOG_polar":   {"zh": "阿極",       "en": "Polar"},
	"DIALOG_polarz":  {"zh": "極極",       "en": "Polarz"},
	"DIALOG_raccoon": {"zh": "小浣",       "en": "Raccoon"},
	"DIALOG_boar":    {"zh": "山豬",       "en": "Boar"},
	"DIALOG_panda":   {"zh": "阿潘",       "en": "Pan"},
	"DIALOG_dragon":  {"zh": "米洛",       "en": "Milo"},
	"DIALOG_shark":   {"zh": "埃德",       "en": "Ed"},
	"DIALOG_gory":    {"zh": "戈爾",       "en": "Gory"},
	"DIALOG_owen":    {"zh": "奧云",       "en": "Owen"},

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
	"冰球法印": {"zh": "冰球法印", "en": "Iceball Sigil"},
	"冰球法印 DESC": {"zh": "在棋盤右上與左下各生成一圈 8 顆水寶石。CD：5 回合。", "en": "Create two 8-gem water circles at the top-right and bottom-left of the board. CD: 5 turns."},
	"Blast": {"zh": "爆炸", "en": "Blast"},
	"Blast DESC": {"zh": "由上至下爆破整個棋盤的每一行。CD：1 回合。", "en": "Blast every row from top to bottom. CD: 1 turn."},
	"Leaf Spear Call": {"zh": "葉矛喚來", "en": "Leaf Spear Call"},
	"Leaf Spear Call DESC": {"zh": "選擇頂列或底列 1 格，在該格生成朝棋盤內側刺出的木槍寶石；頂列朝下，底列朝上。CD：4 回合。", "en": "Select one top-row or bottom-row cell to create an inward-facing Wood Spear gem there; top row points down, bottom row points up. CD: 4 turns."},
	"Leaf Spear Call DESC DYNAMIC": {"zh": "選擇頂列或底列 %d 格，在每格生成朝棋盤內側刺出的木槍寶石；頂列朝下，底列朝上。CD：%d 回合。", "en": "Select %d top-row or bottom-row cells to create inward-facing Wood Spear gems there; top row points down, bottom row points up. CD: %d turns."},

	# ── 技能寶石強化 ──
	"SKILL_UPGRADE_TITLE": {"zh": "寶石強化", "en": "Gem Upgrade"},
	"SKILL_UPGRADE_CONFIRM_TITLE": {"zh": "確認強化", "en": "Confirm Upgrade"},
	"SKILL_UPGRADE_CONFIRM_BODY": {"zh": "消耗 1 顆%s強化此技能？", "en": "Spend 1 %s to upgrade this skill?"},
	"SKILL_UPGRADE_COST": {"zh": "消耗：%s ×%d", "en": "Cost: %s x%d"},
	"SKILL_UPGRADE_NOT_ENOUGH": {"zh": "%s不足", "en": "Not enough %s"},
	"SKILL_UPGRADE_MAXED": {"zh": "已強化完成", "en": "Fully upgraded"},
	"ITEM_SAPPHIRE": {"zh": "藍寶石", "en": "Sapphire"},
	"UPGRADE_GORY_LEAF_SPEAR_EXTRA_1": {"zh": "可額外選擇 1 格生成木槍。", "en": "Pick 1 extra cell to create a Wood Spear."},
	"UPGRADE_GORY_LEAF_SPEAR_EXTRA_2": {"zh": "可額外選擇 2 格生成木槍。", "en": "Pick 2 extra cells to create Wood Spears."},
	"UPGRADE_GORY_LEAF_SPEAR_CD_1": {"zh": "冷卻回合 -1。", "en": "Cooldown -1."},
	"UPGRADE_GORY_WOOD_SPEAR_PIERCE_BREAKABLE": {"zh": "木槍破壞可破壞障礙後，現在會繼續飛行。", "en": "Wood Spear now keeps flying after breaking a breakable obstacle."},
	"UPGRADE_GORY_WOOD_SPEAR_THRESHOLD_1": {"zh": "合成需求 -1。", "en": "Fusing requirement -1."},

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
	"SPELL_CHAIN": {"zh": "法術連撃", "en": "Spell Chain"},
	"SPELL_CHAIN_SHORT": {"zh": "法", "en": "spell"},
	"咒術印記: 陽光射線": {"zh": "咒術印記：陽光射線", "en": "Spell Sigil: Sunbeam"},
	"咒術印記: 陽光射線 DESC": {"zh": "將棋盤左上與右下各 2×3 格轉為葉寶石。CD：4 回合。", "en": "Turn two 2x3 piles at the top-left and bottom-right of the board into leaf gems. CD: 4 turns."},
	"Leaf Ray": {"zh": "葉光射線", "en": "Leaf Ray"},
	"Leaf Ray DESC": {"zh": "6 顆以上葉寶石合成時，生成立即咒語葉光射線。寶石會向敵人發射 1 秒射線，造成施放者魔力 × 3.5 傷害。", "en": "Fuse 6+ leaf gems to create an instant Leaf Ray. The gem fires a 1s ray at an enemy, dealing caster magic x3.5 damage."},
	"TAP_HERO_TO_USE_SKILL": {"zh": "點擊角色使用技能", "en": "Tap the hero to use skill"},
}


## 取得 UI 翻譯文字
func tr_ui(key: String) -> String:
	var ginger_override := _ginger_translations(key)
	if not ginger_override.is_empty():
		return ginger_override
	var entry: Dictionary = _translations.get(key, {})
	if entry.is_empty():
		return key
	return entry.get(current_locale, entry.get("en", key))


func _ginger_translations(key: String) -> String:
	var zh := current_locale != "en"
	match key:
		"Ginger":
			return "啊橘" if zh else "Ginger"
		"DIALOG_ginger":
			return "啊橘" if zh else "Ginger"
		"Mini":
			return "米尼" if zh else "Mini"
		"DIALOG_mini":
			return "米尼" if zh else "Mini"
		"Boarz":
			return "Boarz" if zh else "Boarz"
		"DIALOG_boarz":
			return "Boarz" if zh else "Boarz"
		"Giz":
			return "古茲" if zh else "Giz"
		"DIALOG_giz":
			return "古茲" if zh else "Giz"
		"Wood Spirit Attack":
			return "木靈攻撃" if zh else "Wood Spirit Attack"
		"Wood Spirit Attack DESC":
			return "呼叫場上屬於自己的綠寶石之塔發射葉光射線，造成自身魔力 7 倍木元素攻擊。CD: 4 回合。" if zh else "Call your Emerald Towers on the board to fire leaf rays, dealing caster magic x7 leaf damage. CD: 4 turns."
		"Light Energy Transfer":
			return "光能轉移" if zh else "Light Energy Transfer"
		"Light Energy Transfer DESC":
			return "將棋盤上的普通光寶石轉為木寶石。CD: 5 回合。" if zh else "Convert normal light gems on the board into leaf gems. CD: 5 turns."
		"Emerald Tower":
			return "召喚: 木靈" if zh else "Emerald Tower"
		"Emerald Tower DESC":
			return "6+ 光寶石召喚木屬性的綠寶石之塔[建築物]。爆炸時提供 6 木元素攻擊；玩家回合結束時依召喚者魔力發射 7 倍攻擊，並將附近 3 格轉為木寶石。" if zh else "Fuse 6+ light gems to summon a leaf-element Emerald Tower building. Its blast contributes 6 leaf attack; at player turn end it fires magic x7 and converts 3 nearby cells to leaf."
		"Green to Fire":
			return "燃薪猛火" if zh else "Green to Fire"
		"Green to Fire DESC":
			return "將棋盤上所有木珠轉成火珠。CD: 5 回合。" if zh else "Convert all leaf gems on the board into fire gems. CD: 5 turns."
		"燃薪猛火":
			return "燃薪猛火" if zh else "Kindling Blaze"
		"燃薪猛火 DESC":
			return "將棋盤上所有木珠轉成火珠。CD: 5 回合。" if zh else "Convert all leaf gems on the board into fire gems. CD: 5 turns."
		"Kindling Blaze":
			return "燃薪猛火" if zh else "Kindling Blaze"
		"Kindling Blaze DESC":
			return "將棋盤上的所有木寶石轉為火寶石。CD: 5 回合。" if zh else "Convert all leaf gems on the board into fire gems. CD: 5 turns."
		"Forge":
			return "鑄造" if zh else "Forge"
		"Forge DESC":
			return "點擊任一可鑄造上珠，使其直接升 1 Lv；或點擊普通寶石，使它變成 x3 狀態。CD: 4 回合。" if zh else "Select a forge upper gem to upgrade it by 1 level, or select a normal gem to grant x3. CD: 4 turns."
		"Fire Greatsword":
			return "鑄造: 火焰巨劍" if zh else "Fire Greatsword"
		"Fire Greatsword DESC":
			return "6+ 火珠鑄造成火焰巨劍。再次融合時會升級最近的 Lv1/Lv2 火焰巨劍，最高 Lv3。" if zh else "6+ fire gems forge a Fire Greatsword. Re-fusing upgrades the nearest existing Lv1/Lv2 Fire Greatsword up to Lv3."
		"Fire Hammer":
			return "火焰巨鎔" if zh else "Fire Hammer"
		"Fire Hammer DESC":
			return "5+ 火珠鑄造成火焰巨鎔。Lv1 爆自身九宮格，Lv2 使用米洛火球範圍，Lv3 使用更大的火球範圍。" if zh else "5+ fire gems forge a Fire Hammer. Lv1 blasts its 3x3 area, Lv2 uses Milo's fireball area, and Lv3 uses the larger fireball area."
		"Holy Triangle Seal":
			return "咒印: 聖光三角之印" if zh else "Holy Triangle Seal"
		"Holy Triangle Seal DESC":
			return "選擇棋盤位置，將聖光三角之印範圍轉換為光寶石。CD: 4 回合。" if zh else "Select the board and convert the Holy Triangle sigil into light gems. CD: 4 turns."
		"Light Triangle":
			return "聖光三角" if zh else "Light Triangle"
		"Light Triangle DESC":
			return "6+ 光寶石融合成即時法術聖光三角，射向敵人造成使用者魔力 6 倍傷害。若法術 combo 數為 3/6/9...，額外增加 1 倍傷害，投射物變大並持續旋轉。" if zh else "Fuse 6+ light gems to create an instant Light Triangle. It shoots at an enemy for caster magic x6 damage. Every 3rd spell combo deals +100% damage with a larger spinning projectile."
	return ""


## 嘗試翻譯 key；若無對應條目則回傳 fallback（用於 .tres 描述等可能未本地化的字串）。
func tr_or(key: String, fallback: String) -> String:
	if key == "":
		return fallback
	var ginger_override := _ginger_translations(key)
	if not ginger_override.is_empty():
		return ginger_override
	var entry: Dictionary = _translations.get(key, {})
	if entry.is_empty():
		return fallback
	return entry.get(current_locale, entry.get("en", fallback))


## 從 DialogLine 取得當前語系的文字
func get_dialog_text(line: _DialogLine) -> String:
	if current_locale == "en":
		return line.text_en if not line.text_en.is_empty() else line.text_zh
	return line.text_zh if not line.text_zh.is_empty() else line.text_en
