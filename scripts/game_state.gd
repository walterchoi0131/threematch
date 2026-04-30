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

## 已通關的關卡 id 集合（例如 "1-1"）。用於世界地圖解鎖。
var cleared_stages: Dictionary = {}    # key = stage_id (String), value = true

## 標記指定 stage_id 為已通關
func mark_stage_cleared(stage_id: String) -> void:
	if stage_id == "":
		return
	cleared_stages[stage_id] = true

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
		preload("res://characters/char_shark.tres"),
		preload("res://characters/char_dragon.tres"),
	]

	# 為關卡設定對話（程式碼建構）
	var _stage_dev: StageData = preload("res://stages/stage_dev.tres")
	var _Stage1Intro := preload("res://dialogs/stage1_intro.gd")
	if _stage_dev.pre_dialog == null:
		_stage_dev.pre_dialog = _Stage1Intro.make()

	# 設定教學模式與固定棋盤佈局
	_stage_dev.is_tutorial = true
	_stage_dev.fixed_layout = _build_stage1_layout()
	# 第三波（index 2）三隻史萊姆的初始 CD：2, 3, 1
	_stage_dev.rounds_init_cd = [[], [], [2, 3, 1], []]
	# 第一關固定隊伍：husky, dragon, shark, raccoon
	_stage_dev.set_party = [
		preload("res://characters/char_husky.tres"),
		preload("res://characters/char_dragon.tres"),
		preload("res://characters/char_shark.tres"),
		preload("res://characters/char_raccoon.tres"),
	]


## 建構第一關固定棋盤佈局（8×8）
## 設計：col 0 為一條 7 顆火寶石的縱向火柱（教融合用），中段 (4,4)/(5,4)/(4,5)
## 為 3 顆綠葉相連（教普攻用）。
static func _build_stage1_layout() -> Array:
	# R=Fire, B=Water, G=Leaf, L=Gold
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
