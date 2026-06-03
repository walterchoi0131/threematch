## GameState（遊戲狀態）— 跨場景的持久化單例（Autoload）。
## 儲存當前選擇的關卡、隊伍、擁有的角色等。
extends Node

signal inventory_changed
signal skill_upgrades_changed
signal save_cleared

const MAX_PARTY_SIZE := 4  # 隊伍最大人數
const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 1
const DEFAULT_CHARACTER_LEVEL := 5
const DEFAULT_CHARACTER_EXP := 0
const DEFAULT_CHARACTER_PATHS := [
	"res://characters/char_boar.tres",
	"res://characters/char_raccoon.tres",
	"res://characters/char_fox.tres",
	"res://characters/char_husky.tres",
	"res://characters/char_panda.tres",
	"res://characters/char_polar.tres",
	"res://characters/char_polarz.tres",
	"res://characters/char_shark.tres",
	"res://characters/char_dragon.tres",
	"res://characters/char_gory.tres",
]
const STARTING_CHARACTER_PATHS := [
	"res://characters/char_dragon.tres",
	"res://characters/char_panda.tres",
	"res://characters/char_shark.tres",
]

var selected_stage: StageData = null           # 當前選擇的關卡
var selected_party: Array[CharacterData] = []  # 當前選擇的隊伍
var detail_character: CharacterData = null      # 要查看詳細資訊的角色
var stage_edit_mode: bool = false               # 以棋盤編輯模式進入 main.tscn（不持久化）

var owned_characters: Array[CharacterData] = []  # 玩家擁有的所有角色

var gold: int = 0                      # 玩家持有金幣
var inventory: Dictionary = {}         # 玩家物品庫存，key = ItemDefs.Type，value = int
var skill_upgrade_levels: Dictionary = {}  # key = SkillUpgradeUtils.get_skill_key(), value = int

## 已通關的關卡 id 集合（例如 "1-1"）。用於世界地圖解鎖。
var cleared_stages: Dictionary = {}    # key = stage_id (String), value = true

## 上次出戰使用的隊伍（CharacterData resource_path 陣列）。
## 關卡如未設定 fixed party（set_party），準備畫面預選此隊伍。
var last_used_party_paths: Array[String] = []

## 取得上次使用的隊伍 CharacterData 陣列（只含現持有者）
func get_last_used_party() -> Array[CharacterData]:
	var result: Array[CharacterData] = []
	for p in last_used_party_paths:
		for c: CharacterData in owned_characters:
			if c != null and c.resource_path == p:
				result.append(c)
				break
	return result

## 記錄本場出戰隊伍（由 main 在勝利且無 fixed party 時呼叫）
func set_last_used_party(chars: Array[CharacterData]) -> void:
	last_used_party_paths.clear()
	for c in chars:
		if c != null and c.resource_path != "":
			last_used_party_paths.append(c.resource_path)
	save_game()

## 標記指定 stage_id 為已通關
func mark_stage_cleared(stage_id: String) -> void:
	if stage_id == "":
		return
	cleared_stages[stage_id] = true
	save_game()

## 是否已通關
func is_stage_cleared(stage_id: String) -> bool:
	return stage_id != "" and cleared_stages.has(stage_id)

# ── 戰鬥結算暫存（戰鬥勝利後寫入，結算場景讀取） ──
var last_battle_loot: Dictionary = {}              # key=ItemDefs.Type, value=int
var last_battle_party: Array[CharacterData] = []   # 出戰角色（結算用）
var last_battle_exp: int = 0                       # 本場獲得的總經驗值

# ── 持久化 BGM 播放器（跨場景存活）──
var bgm_player: AudioStreamPlayer = null
var _bgm_id: String = ""        # 目前 BGM 識別字串（用於避免重複啟動同一首）
var _bgm_fade_tween: Tween = null

const _BGM_DEFAULT_VOLUME_DB := 0.0
const _BGM_SILENT_VOLUME_DB := -40.0

## 啟動 BGM（替換舊播放器）。若 id 相同且正在播放則跳過。
func play_bgm(stream: AudioStream, loop: bool = false, id: String = "") -> void:
	var new_id := id if id != "" else stream.resource_path
	if _bgm_id != "" and _bgm_id == new_id and bgm_player != null and is_instance_valid(bgm_player) and bgm_player.playing:
		return
	stop_bgm()
	_bgm_id = new_id
	bgm_player = _make_bgm_player(stream, loop)
	bgm_player.volume_db = _BGM_DEFAULT_VOLUME_DB
	bgm_player.play()

## 漸隱當前 BGM 並啟動新 BGM 漸入（交叉淡入淡出）
## loop_delay > 0 時，循環之間插入指定秒數的延遲（用於戰鬥 BGM）。
func crossfade_bgm(stream: AudioStream, loop: bool = false, duration: float = 0.6, id: String = "", loop_delay: float = 0.0) -> void:
	var new_id := id if id != "" else stream.resource_path
	if _bgm_id != "" and _bgm_id == new_id and bgm_player != null and is_instance_valid(bgm_player) and bgm_player.playing:
		return
	# 殺掉先前的 fade tween
	if _bgm_fade_tween != null and _bgm_fade_tween.is_valid():
		_bgm_fade_tween.kill()
	# 淡出舊播放器（並在淡出後釋放）
	var old_player: AudioStreamPlayer = bgm_player
	if old_player != null and is_instance_valid(old_player) and old_player.playing:
		var fade_out := create_tween()
		fade_out.tween_property(old_player, "volume_db", _BGM_SILENT_VOLUME_DB, duration)
		fade_out.tween_callback(func() -> void:
			if is_instance_valid(old_player):
				old_player.stop()
				old_player.queue_free()
		)
	# 建立新播放器，從靜音開始淡入
	_bgm_id = new_id
	bgm_player = _make_bgm_player(stream, loop and loop_delay <= 0.0)
	bgm_player.volume_db = _BGM_SILENT_VOLUME_DB
	bgm_player.play()
	# 手動循環（內建 loop=false），於 finished 後延遲再播
	if loop and loop_delay > 0.0:
		_setup_loop_with_delay(bgm_player, loop_delay)
	if duration <= 0.0:
		# duration=0：直接設定為預設音量，不做淡入
		bgm_player.volume_db = _BGM_DEFAULT_VOLUME_DB
		_bgm_fade_tween = null
	else:
		_bgm_fade_tween = create_tween()
		_bgm_fade_tween.tween_property(bgm_player, "volume_db", _BGM_DEFAULT_VOLUME_DB, duration)

## 漸隱並停止當前 BGM
func fade_out_bgm(duration: float = 0.6) -> void:
	if bgm_player == null or not is_instance_valid(bgm_player) or not bgm_player.playing:
		stop_bgm()
		return
	if _bgm_fade_tween != null and _bgm_fade_tween.is_valid():
		_bgm_fade_tween.kill()
	var player := bgm_player
	bgm_player = null
	_bgm_id = ""
	_bgm_fade_tween = create_tween()
	_bgm_fade_tween.tween_property(player, "volume_db", _BGM_SILENT_VOLUME_DB, duration)
	_bgm_fade_tween.tween_callback(func() -> void:
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	)

## 立即停止並釋放 BGM 播放器
func stop_bgm() -> void:
	if _bgm_fade_tween != null and _bgm_fade_tween.is_valid():
		_bgm_fade_tween.kill()
	_bgm_fade_tween = null
	if bgm_player != null and is_instance_valid(bgm_player):
		bgm_player.stop()
		bgm_player.queue_free()
	bgm_player = null
	_bgm_id = ""


# ── 場景轉場淡入淡出 ─────────────────────────────────────────

var _fade_layer: CanvasLayer = null
var _fade_rect: ColorRect = null
var _pending_fade_in: bool = false

func _ensure_fade_layer() -> void:
	if _fade_layer != null and is_instance_valid(_fade_layer):
		return
	_fade_layer = CanvasLayer.new()
	_fade_layer.layer = 128
	add_child(_fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade_layer.add_child(_fade_rect)

## 淡出當前畫面到黑，然後切換到指定場景。新場景若呼叫 fade_in_if_pending
## 則會在載入後自動從黑淡入。
func fade_to_scene(path: String, duration: float = 0.45) -> void:
	_ensure_fade_layer()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, duration)
	tw.tween_callback(func() -> void:
		_pending_fade_in = true
		get_tree().change_scene_to_file(path)
	)

## 若上一步是 fade_to_scene 則從黑淡入；否則無動作。
func fade_in_if_pending(duration: float = 0.45) -> void:
	if not _pending_fade_in:
		return
	_pending_fade_in = false
	_ensure_fade_layer()
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 0.0, duration)
	tw.tween_callback(func() -> void:
		_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	)

## 內部：建立 AudioStreamPlayer（必要時複製並設定 loop）
func _make_bgm_player(stream: AudioStream, loop: bool) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	if loop and stream is AudioStreamMP3:
		var dup: AudioStreamMP3 = (stream as AudioStreamMP3).duplicate() as AudioStreamMP3
		dup.loop = true
		player.stream = dup
	else:
		player.stream = stream
	add_child(player)
	return player


## 內部：為播放器附加「播完延遲再循環」的行為。
## 注意：呼叫前 player.stream 應為非 loop 版本。
func _setup_loop_with_delay(player: AudioStreamPlayer, delay: float) -> void:
	# 在 player 上記錄狀態，避免重複連接
	if player.has_meta("_loop_delay_attached"):
		return
	player.set_meta("_loop_delay_attached", true)
	player.finished.connect(func() -> void:
		# 延遲後若播放器仍是當前的 BGM 才重播
		await get_tree().create_timer(delay).timeout
		if is_instance_valid(player) and player == bgm_player:
			player.play()
	)


## 新增戰利品到玩家存貨
func add_loot(type: ItemDefs.Type, amount: int) -> void:
	if amount <= 0:
		return
	if type == ItemDefs.Type.GOLD:
		gold += amount
	else:
		var current: int = inventory.get(type, 0)
		inventory[type] = current + amount
	inventory_changed.emit()
	save_game()


func get_inventory_count(type: ItemDefs.Type) -> int:
	if type == ItemDefs.Type.GOLD:
		return gold
	return int(inventory.get(type, 0))


func consume_item(type: ItemDefs.Type, amount: int, auto_save: bool = true) -> bool:
	if amount <= 0:
		return true
	if get_inventory_count(type) < amount:
		return false
	if type == ItemDefs.Type.GOLD:
		gold -= amount
	else:
		var remaining: int = int(inventory.get(type, 0)) - amount
		if remaining > 0:
			inventory[type] = remaining
		elif inventory.has(type):
			inventory.erase(type)
	inventory_changed.emit()
	if auto_save:
		save_game()
	return true


func get_skill_upgrade_level(character: CharacterData, kind: String, skill_index: int = 0) -> int:
	var key: String = SkillUpgradeUtils.get_skill_key(character, kind, skill_index)
	if key == "":
		return 0
	return int(skill_upgrade_levels.get(key, 0))


func try_upgrade_skill(character: CharacterData, kind: String, skill_index: int = 0) -> Dictionary:
	var defs: Array[Dictionary] = SkillUpgradeUtils.get_upgrade_defs(character, kind, skill_index)
	if defs.is_empty():
		return {"ok": false, "reason": "NO_UPGRADES"}
	var current: int = get_skill_upgrade_level(character, kind, skill_index)
	if current >= defs.size():
		return {"ok": false, "reason": "MAX_LEVEL"}
	if not consume_item(SkillUpgradeUtils.COST_ITEM_TYPE, SkillUpgradeUtils.COST_ITEM_AMOUNT, false):
		return {"ok": false, "reason": "NOT_ENOUGH_ITEM"}
	var key: String = SkillUpgradeUtils.get_skill_key(character, kind, skill_index)
	skill_upgrade_levels[key] = current + 1
	skill_upgrades_changed.emit()
	save_game()
	return {"ok": true, "level": current + 1}


func _ready() -> void:
	owned_characters.clear()

	# 為關卡設定對話（程式碼建構）
	var _stage_dev: StageData = preload("res://stages/stage_dev.tres")
	var _Stage1Intro := preload("res://dialogs/stage1_intro.gd")
	if _stage_dev.pre_dialog == null:
		_stage_dev.pre_dialog = _Stage1Intro.make()

	# 設定教學模式與固定棋盤佈局
	_stage_dev.is_tutorial = true
	if _stage_dev.fixed_layout.is_empty():
		_stage_dev.fixed_layout = _build_stage1_layout()
	# 第三波（index 2）三隻史萊姆的初始 CD：2, 3, 1
	_stage_dev.rounds_init_cd = [[], [], [2, 3, 1], []]
	# 第一關固定隊伍：dragon, shark, panda；husky 由戰鬥教學中途加入
	_stage_dev.set_party = [
		preload("res://characters/char_dragon.tres"),
		preload("res://characters/char_shark.tres"),
		preload("res://characters/char_panda.tres"),
	]

	# 嘗試載入持久化存檔（覆寫 owned_characters / inventory / gold / cleared_stages）
	var loaded_save: bool = load_game()
	if not loaded_save:
		owned_characters.clear()
	_ensure_starting_characters_if_empty()


# ── 持久化存檔 ───────────────────────────────────────────────

## 將目前持久狀態寫入 user://save.json
func save_game() -> void:
	var data: Dictionary = _serialize()
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("GameState: cannot open save file for writing: %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()


## 從 user://save.json 讀取存檔；不存在或失敗回傳 false。
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_warning("GameState: save file is not a valid JSON object")
		return false
	var d: Dictionary = parsed
	var ver: int = int(d.get("version", 0))
	if ver != SAVE_VERSION:
		push_warning("GameState: save version %d is not supported (expect %d); ignoring" % [ver, SAVE_VERSION])
		return false
	_deserialize(d)
	return true


## 刪除存檔並將 in-memory 狀態重置為初始值（不立即重新存檔）。
func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		# 上述對 user:// 路徑可能無效；改用 DirAccess.open("user://") 後 remove
		var dir := DirAccess.open("user://")
		if dir != null and dir.file_exists("save.json"):
			dir.remove("save.json")
	# 重置記憶體中的持久狀態
	cleared_stages.clear()
	inventory.clear()
	skill_upgrade_levels.clear()
	selected_party.clear()
	detail_character = null
	last_used_party_paths.clear()
	last_battle_loot.clear()
	last_battle_party.clear()
	last_battle_exp = 0
	gold = 0
	owned_characters.clear()
	_ensure_starting_characters_if_empty()
	inventory_changed.emit()
	skill_upgrades_changed.emit()
	save_cleared.emit()


func reset_owned_character_progress(auto_save: bool = true) -> void:
	_reset_characters_progress(owned_characters)
	if auto_save:
		save_game()


func _ensure_starting_characters_if_empty() -> void:
	if owned_characters.size() > 0:
		return
	for path: String in STARTING_CHARACTER_PATHS:
		var res: Resource = load(path)
		if res is CharacterData:
			grant_character(res as CharacterData, true)
	save_game()


func grant_character(character: CharacterData, reset_progress: bool = true) -> bool:
	if character == null:
		return false
	var path: String = character.resource_path
	for owned: CharacterData in owned_characters:
		if owned == character:
			return false
		if path != "" and owned != null and owned.resource_path == path:
			return false
	if reset_progress:
		_reset_character_progress(character)
	owned_characters.append(character)
	return true


func debug_grant_all_characters(auto_save: bool = true) -> int:
	var added: int = 0
	for character: CharacterData in _load_default_characters():
		if grant_character(character, true):
			added += 1
	if auto_save:
		save_game()
	return added


func get_character_catalog() -> Array[CharacterData]:
	return _load_default_characters()


func _load_default_characters() -> Array[CharacterData]:
	var result: Array[CharacterData] = []
	for path in DEFAULT_CHARACTER_PATHS:
		var res: Resource = load(str(path))
		if res is CharacterData:
			result.append(res as CharacterData)
	return result


func _reset_characters_progress(characters: Array[CharacterData]) -> void:
	for c: CharacterData in characters:
		_reset_character_progress(c)


func _reset_character_progress(c: CharacterData) -> void:
	if c == null:
		return
	c.level = DEFAULT_CHARACTER_LEVEL
	c.current_exp = DEFAULT_CHARACTER_EXP


func _serialize() -> Dictionary:
	var char_entries: Array = []
	for c: CharacterData in owned_characters:
		if c != null and c.resource_path != "":
			char_entries.append({
				"path": c.resource_path,
				"level": c.level,
				"exp": c.current_exp,
			})
	var inv: Dictionary = {}
	for k in inventory.keys():
		inv[str(int(k))] = int(inventory[k])
	return {
		"version": SAVE_VERSION,
		"gold": gold,
		"owned_characters": char_entries,
		"inventory": inv,
		"skill_upgrade_levels": skill_upgrade_levels.duplicate(),
		"cleared_stages": cleared_stages.keys(),
		"last_used_party": Array(last_used_party_paths),
	}


func _deserialize(d: Dictionary) -> void:
	gold = int(d.get("gold", 0))

	var loaded_chars: Array[CharacterData] = []
	for entry in d.get("owned_characters", []):
		var path: String = ""
		var lvl: int = -1
		var xp: int = -1
		if entry is Dictionary:
			path = str(entry.get("path", ""))
			lvl = int(entry.get("level", -1))
			xp = int(entry.get("exp", -1))
		else:
			path = str(entry)
		if path == "":
			continue
		var res: Resource = load(path)
		if res is CharacterData:
			var cd: CharacterData = res
			cd.level = lvl if lvl > 0 else DEFAULT_CHARACTER_LEVEL
			cd.current_exp = xp if xp >= 0 else DEFAULT_CHARACTER_EXP
			loaded_chars.append(cd)
		else:
			push_warning("GameState: cannot load CharacterData at %s" % path)
	if loaded_chars.size() > 0:
		owned_characters = loaded_chars
	else:
		_reset_characters_progress(owned_characters)

	inventory.clear()
	var inv: Dictionary = d.get("inventory", {})
	for k in inv.keys():
		inventory[int(k)] = int(inv[k])

	skill_upgrade_levels.clear()
	var upgrades: Dictionary = d.get("skill_upgrade_levels", {})
	for k in upgrades.keys():
		var level: int = int(upgrades[k])
		if level > 0:
			skill_upgrade_levels[str(k)] = level

	cleared_stages.clear()
	for sid in d.get("cleared_stages", []):
		cleared_stages[str(sid)] = true

	last_used_party_paths.clear()
	for p in d.get("last_used_party", []):
		var s := str(p)
		if s != "":
			last_used_party_paths.append(s)


## 建構第一關固定棋盤佈局（8×8）
## 設計：col 0 為一條 7 顆火寶石的縱向火柱（教融合用），中段 (4,4)/(5,4)/(4,5)
## 為 3 顆綠葉相連（教普攻用）。
static func _build_stage1_layout() -> Array:
	# R=Fire, B=Water, G=Leaf, L=Light
	const R := Block.Type.RED
	const B := Block.Type.BLUE
	const G := Block.Type.GREEN
	const L := Block.Type.LIGHT
	# 依設計圖直接列出每一列（row 0 為最上方）
	# 已套用使用者修正：col 0 row 3 葉 → 火
	var rows: Array = [
		[R, B, B, B, G, G, L, L],  # row 0
		[R, B, B, L, B, B, B, G],  # row 1
		[R, L, L, B, B, B, L, G],  # row 2
		[R, L, L, L, R, L, L, L],  # row 3 (col0 was G, 改為 R)
		[R, L, G, R, G, G, R, L],  # row 4
		[R, L, R, R, G, B, R, L],  # row 5
		[R, R, R, B, L, L, L, L],  # row 6
		[L, L, L, R, B, L, L, G],  # row 7
	]
	# 轉成 layout[x][y]
	var layout: Array = []
	layout.resize(8)
	for x in 8:
		var col: Array = []
		col.resize(8)
		for y in 8:
			col[y] = rows[y][x]
		layout[x] = col
	return layout
