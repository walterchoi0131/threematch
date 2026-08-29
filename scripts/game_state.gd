## GameState（遊戲狀態）— 跨場景的持久化單例（Autoload）。
## 儲存當前選擇的關卡、隊伍、擁有的角色等。
extends Node

signal inventory_changed
signal skill_upgrades_changed
signal owned_characters_changed
signal save_cleared

const MAX_PARTY_SIZE := 4  # 隊伍最大人數
const SAVE_PATH := "user://save.json"
const SAVE_VERSION := 3
const _STAGE_ID_MIGRATION_V1_TO_V2 := {
	"1-2": "1-4",
	"1-3": "1-5",
	"1-4": "1-6",
	"1-5": "1-7",
	"1-6": "1-8",
}
const _STAGE_ID_MIGRATION_V2_TO_V3 := {
	"1-4": "",
	"1-5": "1-4",
	"1-6": "1-5",
	"1-7": "1-6",
	"1-8": "1-7",
}
const _MAIN_STAGE_PREREQUISITES := {
	"1-2": "1-1",
	"1-3": "1-2",
	"1-4": "1-3",
	"1-5": "1-4",
	"1-6": "1-5",
	"1-7": "1-6",
}
const DEFAULT_CHARACTER_LEVEL := 5
const DEFAULT_CHARACTER_EXP := 0
const GOLD_ECONOMIC_MULTIPLIER := 50
const DEFAULT_CHARACTER_PATHS := [
	"res://characters/char_raccoon.tres",
	"res://characters/char_fox.tres",
	"res://characters/char_husky.tres",
	"res://characters/char_panda.tres",
	"res://characters/char_polarz.tres",
	"res://characters/char_shark.tres",
	"res://characters/char_dragon.tres",
	"res://characters/char_gory.tres",
	"res://characters/char_owen.tres",
	"res://characters/char_duan.tres",
	"res://characters/char_ginger.tres",
	"res://characters/char_mini.tres",
	"res://characters/char_boarz.tres",
	"res://characters/char_giz.tres",
]
const REMOVED_CHARACTER_PATHS := {
	"res://characters/char_boar.tres": true,
	"res://characters/char_polar.tres": true,
}
const STARTING_CHARACTER_PATHS := [
	"res://characters/char_dragon.tres",
	"res://characters/char_panda.tres",
	"res://characters/char_shark.tres",
]

var selected_stage: StageData = null           # 當前選擇的關卡
var selected_party: Array[CharacterData] = []  # 當前選擇的隊伍
var battle_strength_adjustment_enabled: bool = false
var battle_strength_adjustment_level: int = 0
var detail_character: CharacterData = null      # 要查看詳細資訊的角色
var stage_edit_mode: bool = false               # 以棋盤編輯模式進入 main.tscn（不持久化）
var dev_mode: bool = false
var map_unlock_pop_source_stage_id: String = ""

var owned_characters: Array[CharacterData] = []  # 玩家擁有的所有角色

var gold: int = 0                      # 玩家持有金幣
var inventory: Dictionary = {}         # 玩家物品庫存，key = ItemDefs.Type，value = int
var skill_upgrade_levels: Dictionary = {}  # key = SkillUpgradeUtils.get_skill_key(), value = int
var claimed_stage_rewards: Dictionary = {}

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
	var was_already_cleared: bool = cleared_stages.has(stage_id)
	cleared_stages[stage_id] = true
	if not was_already_cleared:
		map_unlock_pop_source_stage_id = stage_id
	save_game()


func consume_map_unlock_pop_source_stage_id() -> String:
	var stage_id: String = map_unlock_pop_source_stage_id
	map_unlock_pop_source_stage_id = ""
	return stage_id

## 是否已通關
func is_stage_cleared(stage_id: String) -> bool:
	return stage_id != "" and cleared_stages.has(stage_id)


func is_stage_reward_claimed(stage_id: String) -> bool:
	return stage_id != "" and claimed_stage_rewards.has(stage_id)


func mark_stage_reward_claimed(stage_id: String, auto_save: bool = true) -> void:
	if stage_id == "":
		return
	claimed_stage_rewards[stage_id] = true
	if auto_save:
		save_game()


func claim_stage_reward_if_unclaimed(stage_id: String, auto_save: bool = true) -> bool:
	if is_stage_reward_claimed(stage_id):
		return false
	mark_stage_reward_claimed(stage_id, auto_save)
	return true

# ── 戰鬥結算暫存（戰鬥勝利後寫入，結算場景讀取） ──
var last_battle_loot: Dictionary = {}              # key=ItemDefs.Type, value=int
var last_battle_party: Array[CharacterData] = []   # 出戰角色（結算用）
var last_battle_exp: int = 0                       # 本場獲得的總經驗值
var last_battle_reward_characters: Array[CharacterData] = []

# ── 持久化 BGM 播放器（跨場景存活）──
var bgm_player: AudioStreamPlayer = null
var _bgm_id: String = ""        # 目前 BGM 識別字串（用於避免重複啟動同一首）
var _bgm_fade_tween: Tween = null

const _BGM_DEFAULT_VOLUME_DB := 0.0
const _BGM_SILENT_VOLUME_DB := -40.0
const RUNTIME_PREWARM_CACHE_LIMIT := 24
const _LOADING_FONT := preload("res://assets/fonts/game_ui_font.tres")
const LOADING_FADE_DURATION := 0.28
const LOADING_BOUNCE_INTERVAL := 0.2
const LOADING_BOUNCE_DURATION := 1.0
const LOADING_TEXT := "Loading"
const LOADING_LETTER_WIDTH := 34.0
const _DIALOG_CHAR_ID_ALIAS := {
	"raccoon": "raccoon_baby",
}

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
var _runtime_prewarm_cache: Dictionary = {}
var _runtime_prewarm_pending: Dictionary = {}
var _runtime_prewarm_order: Array[String] = []
var _scene_transition_serial: int = 0
var _loading_layer: CanvasLayer = null
var _loading_root: Control = null
var _loading_letter_slots: Array[Control] = []
var _loading_active: bool = false
var _loading_serial: int = 0
var _stage_loading_transition_active: bool = false


func prewarm_resource(path: String) -> void:
	var clean_path := path.strip_edges()
	if clean_path.is_empty() or _runtime_prewarm_cache.has(clean_path) \
			or _runtime_prewarm_pending.has(clean_path) or not ResourceLoader.exists(clean_path):
		return
	var request_error: Error = ResourceLoader.load_threaded_request(clean_path)
	if request_error != OK:
		return
	_runtime_prewarm_pending[clean_path] = true
	call_deferred("_collect_prewarmed_resource", clean_path)


func _collect_prewarmed_resource(path: String) -> void:
	while _runtime_prewarm_pending.has(path):
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			await get_tree().process_frame
			continue
		_runtime_prewarm_pending.erase(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			var resource: Resource = ResourceLoader.load_threaded_get(path)
			if resource != null:
				_store_prewarmed_resource(path, resource)
		return


func _store_prewarmed_resource(path: String, resource: Resource) -> void:
	_runtime_prewarm_cache[path] = resource
	_runtime_prewarm_order.erase(path)
	_runtime_prewarm_order.append(path)
	while _runtime_prewarm_order.size() > RUNTIME_PREWARM_CACHE_LIMIT:
		var oldest_path: String = _runtime_prewarm_order.pop_front()
		_runtime_prewarm_cache.erase(oldest_path)


func _await_prewarmed_resource(path: String) -> Resource:
	if _runtime_prewarm_cache.has(path):
		_runtime_prewarm_order.erase(path)
		_runtime_prewarm_order.append(path)
		return _runtime_prewarm_cache[path] as Resource
	prewarm_resource(path)
	while _runtime_prewarm_pending.has(path):
		await get_tree().process_frame
	return _runtime_prewarm_cache.get(path, null) as Resource


func _append_loading_path(paths: Array[String], path: String) -> void:
	var clean_path := path.strip_edges()
	if not clean_path.is_empty() and ResourceLoader.exists(clean_path) and not paths.has(clean_path):
		paths.append(clean_path)


func _append_dialog_loading_paths(paths: Array[String], sequence: DialogSequence) -> void:
	if sequence == null:
		return
	for line: DialogLine in sequence.lines:
		if line == null or line.character_id.is_empty():
			continue
		var profile: Dictionary = sequence.get_cast_profile(line.character_id)
		var enemy_path: String = String(profile.get("enemy_path", "")).strip_edges()
		if not enemy_path.is_empty():
			_append_loading_path(paths, enemy_path)
			continue
		if line.emotion == "normal" or line.emotion.is_empty():
			continue
		var aliased_id: String = String(_DIALOG_CHAR_ID_ALIAS.get(line.character_id, line.character_id))
		_append_loading_path(paths, "res://assets/characters/%s_%s.png" % [aliased_id, line.emotion])


func _get_stage_loading_paths(stage: StageData) -> Array[String]:
	var paths: Array[String] = []
	_append_loading_path(paths, "res://scenes/dialog_box.tscn")
	_append_loading_path(paths, "res://scenes/main.tscn")
	if stage == null:
		return paths
	var battle_bg_path: String = stage.battle_background_override_path.strip_edges()
	if battle_bg_path.is_empty():
		battle_bg_path = StageData.get_battle_background_path(stage.area)
	_append_loading_path(paths, battle_bg_path)
	_append_loading_path(paths, stage.battle_music_override_path)
	_append_loading_path(paths, StageData.get_dialog_background_path(stage.area))
	_append_dialog_loading_paths(paths, stage.pre_dialog)
	_append_dialog_loading_paths(paths, stage.post_dialog)
	return paths


func _ensure_loading_screen() -> void:
	if is_instance_valid(_loading_root):
		return
	_loading_layer = CanvasLayer.new()
	_loading_layer.layer = 240
	add_child(_loading_layer)

	_loading_root = Control.new()
	_loading_root.name = "StageLoadingScreen"
	_loading_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_loading_root.visible = false
	_loading_layer.add_child(_loading_root)

	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_root.add_child(background)

	var content := Control.new()
	content.anchor_left = 0.5
	content.anchor_top = 0.5
	content.anchor_right = 0.5
	content.anchor_bottom = 0.5
	content.offset_left = -250.0
	content.offset_top = -60.0
	content.offset_right = 250.0
	content.offset_bottom = 60.0
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_root.add_child(content)

	var total_width: float = float(LOADING_TEXT.length()) * LOADING_LETTER_WIDTH
	var start_x: float = (content.size.x - total_width) * 0.5
	_loading_letter_slots.clear()
	for index in LOADING_TEXT.length():
		var letter := Label.new()
		letter.text = LOADING_TEXT.substr(index, 1)
		letter.position = Vector2(start_x + float(index) * LOADING_LETTER_WIDTH, 30.0)
		letter.size = Vector2(LOADING_LETTER_WIDTH, 48.0)
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.add_theme_font_override("font", _LOADING_FONT)
		letter.add_theme_font_size_override("font_size", 30)
		letter.add_theme_color_override("font_color", Color.WHITE)
		letter.add_theme_color_override("font_outline_color", Color.BLACK)
		letter.add_theme_constant_override("outline_size", 4)
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		letter.set_meta("loading_home_y", letter.position.y)
		content.add_child(letter)
		_loading_letter_slots.append(letter)


func _run_loading_bounce_loop(serial: int) -> void:
	while _loading_active and serial == _loading_serial:
		if _loading_letter_slots.is_empty():
			await get_tree().create_timer(LOADING_BOUNCE_INTERVAL).timeout
			continue
		for slot in _loading_letter_slots:
			if not _loading_active or serial != _loading_serial:
				return
			if is_instance_valid(slot):
				var home_y: float = float(slot.get_meta("loading_home_y", slot.position.y))
				var bounce := create_tween()
				bounce.tween_property(slot, "position:y", home_y - 14.0, LOADING_BOUNCE_DURATION * 0.4) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				bounce.tween_property(slot, "position:y", home_y, LOADING_BOUNCE_DURATION * 0.6) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
			await get_tree().create_timer(LOADING_BOUNCE_INTERVAL).timeout


func show_stage_loading(stage: StageData) -> void:
	_ensure_loading_screen()
	_loading_serial += 1
	var serial := _loading_serial
	_loading_active = true
	_loading_root.modulate.a = 0.0
	_loading_root.visible = true
	_loading_root.mouse_filter = Control.MOUSE_FILTER_STOP

	var loading_paths: Array[String] = _get_stage_loading_paths(stage)
	for path in loading_paths:
		prewarm_resource(path)
	_run_loading_bounce_loop(serial)
	var minimum_visible_seconds := 1.0
	var minimum_end_msec: int = Time.get_ticks_msec() + int(minimum_visible_seconds * 1000.0)
	var fade_in := create_tween()
	fade_in.tween_property(_loading_root, "modulate:a", 1.0, LOADING_FADE_DURATION)
	await fade_in.finished

	while serial == _loading_serial:
		var has_pending := false
		for path in loading_paths:
			if _runtime_prewarm_pending.has(path):
				has_pending = true
				break
		if not has_pending and Time.get_ticks_msec() >= minimum_end_msec:
			return
		await get_tree().process_frame


func hide_stage_loading() -> void:
	if not is_instance_valid(_loading_root) or not _loading_root.visible:
		return
	_loading_active = false
	_loading_serial += 1
	var fade_out := create_tween()
	fade_out.tween_property(_loading_root, "modulate:a", 0.0, LOADING_FADE_DURATION)
	await fade_out.finished
	_loading_root.visible = false
	_loading_root.mouse_filter = Control.MOUSE_FILTER_IGNORE


func load_stage_and_change_scene(stage: StageData, path: String) -> void:
	if _stage_loading_transition_active:
		return
	_stage_loading_transition_active = true
	_scene_transition_serial += 1
	_pending_fade_in = false
	await show_stage_loading(stage)
	var packed_scene: PackedScene = await _await_prewarmed_resource(path) as PackedScene
	if packed_scene != null:
		get_tree().change_scene_to_packed(packed_scene)
	else:
		get_tree().change_scene_to_file(path)
	await get_tree().process_frame
	await get_tree().process_frame
	await hide_stage_loading()
	_stage_loading_transition_active = false

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
	_scene_transition_serial += 1
	var transition_serial := _scene_transition_serial
	prewarm_resource(path)
	_ensure_fade_layer()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, duration)
	tw.tween_callback(_finish_scene_transition.bind(path, transition_serial))


func _finish_scene_transition(path: String, transition_serial: int) -> void:
	var packed_scene: PackedScene = await _await_prewarmed_resource(path) as PackedScene
	if transition_serial != _scene_transition_serial:
		return
	_pending_fade_in = true
	if packed_scene != null:
		get_tree().change_scene_to_packed(packed_scene)
	else:
		get_tree().change_scene_to_file(path)

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
	if stream is AudioStreamMP3:
		var dup: AudioStreamMP3 = (stream as AudioStreamMP3).duplicate() as AudioStreamMP3
		dup.loop = loop
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
	var level := int(skill_upgrade_levels.get(key, 0))
	if level > 0 or kind != SkillUpgradeUtils.KIND_RESPONDING:
		return level
	var legacy_key := SkillUpgradeUtils.get_legacy_skill_key(character, kind, skill_index)
	var legacy_level := int(skill_upgrade_levels.get(legacy_key, 0))
	if legacy_level > 0:
		skill_upgrade_levels[key] = legacy_level
	return legacy_level


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

	var _stage_dev: StageData = preload("res://stages/stage_dev.tres")

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
	if ver < 1 or ver > SAVE_VERSION:
		push_warning("GameState: save version %d is not supported (expect 1..%d); ignoring" % [ver, SAVE_VERSION])
		return false
	_deserialize(d, ver)
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
	claimed_stage_rewards.clear()
	selected_party.clear()
	detail_character = null
	last_used_party_paths.clear()
	last_battle_loot.clear()
	last_battle_party.clear()
	last_battle_exp = 0
	last_battle_reward_characters.clear()
	gold = 0
	owned_characters.clear()
	_ensure_starting_characters_if_empty()
	inventory_changed.emit()
	skill_upgrades_changed.emit()
	owned_characters_changed.emit()
	save_cleared.emit()


func reset_owned_character_progress(auto_save: bool = true) -> void:
	_reset_characters_progress(owned_characters)
	skill_upgrade_levels.clear()
	skill_upgrades_changed.emit()
	if auto_save:
		save_game()


func reset_map_progress(auto_save: bool = true) -> void:
	cleared_stages.clear()
	claimed_stage_rewards.clear()
	last_used_party_paths.clear()
	if auto_save:
		save_game()


func reset_owned_character_list(auto_save: bool = true) -> void:
	owned_characters.clear()
	skill_upgrade_levels.clear()
	selected_party.clear()
	detail_character = null
	last_used_party_paths.clear()
	for path: String in STARTING_CHARACTER_PATHS:
		var res: Resource = load(path)
		if res is CharacterData:
			grant_character(res as CharacterData, true, false)
	skill_upgrades_changed.emit()
	owned_characters_changed.emit()
	if auto_save:
		save_game()


func _ensure_starting_characters_if_empty() -> void:
	if owned_characters.size() > 0:
		return
	for path: String in STARTING_CHARACTER_PATHS:
		var res: Resource = load(path)
		if res is CharacterData:
			grant_character(res as CharacterData, true, false)
	owned_characters_changed.emit()
	save_game()


func grant_character(character: CharacterData, reset_progress: bool = true, notify: bool = true) -> bool:
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
	if notify:
		owned_characters_changed.emit()
	return true


func debug_grant_all_characters(auto_save: bool = true) -> int:
	var added: int = 0
	for character: CharacterData in _load_default_characters():
		if grant_character(character, true, false):
			added += 1
	if added > 0:
		owned_characters_changed.emit()
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
		"claimed_stage_rewards": claimed_stage_rewards.keys(),
		"last_used_party": Array(last_used_party_paths),
	}


func _deserialize(d: Dictionary, save_version: int = SAVE_VERSION) -> void:
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
		if path == "" or REMOVED_CHARACTER_PATHS.has(path):
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
	_migrate_global_responding_upgrade_keys()

	cleared_stages.clear()
	for sid in d.get("cleared_stages", []):
		var migrated_stage_id: String = _migrate_stage_id(str(sid), save_version)
		if migrated_stage_id != "":
			cleared_stages[migrated_stage_id] = true

	claimed_stage_rewards.clear()
	for sid in d.get("claimed_stage_rewards", []):
		var migrated_reward_stage_id: String = _migrate_stage_id(str(sid), save_version)
		if migrated_reward_stage_id != "":
			claimed_stage_rewards[migrated_reward_stage_id] = true
	_repair_main_stage_progression()

	last_used_party_paths.clear()
	for p in d.get("last_used_party", []):
		var s := str(p)
		if s != "" and not REMOVED_CHARACTER_PATHS.has(s):
			last_used_party_paths.append(s)


func _migrate_stage_id(stage_id: String, save_version: int) -> String:
	if save_version <= 1 and _STAGE_ID_MIGRATION_V1_TO_V2.has(stage_id):
		stage_id = String(_STAGE_ID_MIGRATION_V1_TO_V2[stage_id])
	if save_version <= 2 and _STAGE_ID_MIGRATION_V2_TO_V3.has(stage_id):
		stage_id = String(_STAGE_ID_MIGRATION_V2_TO_V3[stage_id])
	return stage_id


func _migrate_global_responding_upgrade_keys() -> void:
	var migrated: Dictionary = {}
	for raw_key in skill_upgrade_levels.keys():
		var key := str(raw_key)
		var global_key := SkillUpgradeUtils.responding_upgrade_key_from_legacy_key(key)
		if global_key == "":
			continue
		var level := int(skill_upgrade_levels.get(key, 0))
		var existing := int(skill_upgrade_levels.get(global_key, 0))
		var pending := int(migrated.get(global_key, 0))
		migrated[global_key] = maxi(maxi(existing, pending), level)
	for key in migrated.keys():
		skill_upgrade_levels[key] = int(migrated[key])


func _repair_main_stage_progression() -> void:
	var changed := true
	while changed:
		changed = false
		for stage_id in cleared_stages.keys():
			var current_id := str(stage_id)
			if not _MAIN_STAGE_PREREQUISITES.has(current_id):
				continue
			var prereq_id: String = String(_MAIN_STAGE_PREREQUISITES[current_id])
			if prereq_id != "" and not cleared_stages.has(prereq_id):
				cleared_stages[prereq_id] = true
				changed = true


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
