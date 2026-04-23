## BattleManager: mediates between the Board (gem blasting) and the combat system.
class_name BattleManager
extends Node

const EnemyScene := preload("res://scenes/enemy.tscn")

signal player_hp_changed(current: int, maximum: int)
signal player_defeated()
signal round_cleared()
signal battle_won()
signal turn_changed(turn: int)
## Emitted when an enemy attacks; Main handles projectile VFX then calls apply_player_damage.
signal enemy_attacked(enemy: Enemy, damage: int)
signal round_transitioning()  ## 波次轉換中（鎖定棋盤用）
signal round_spawned(round_idx: int)  ## 一波敵人已生成完畢
signal loot_dropped(enemy_data: EnemyData, results: Array)  ## 敵人死亡時擁骨的戰利品 (results = Array[Dictionary])

# ── references set by Main ────────────────────────────────────────────
var enemy_container: HBoxContainer

# ── state ─────────────────────────────────────────────────────────────
var characters: Array[CharacterData] = []

var current_round: int = 0
var stage_rounds: Array[Array] = []
var stage_rounds_init_cd: Array[Array] = []

var active_enemies: Array[Enemy] = []
var targeted_enemy: Enemy = null

var player_max_hp: int = 0
var player_current_hp: int = 0

var is_round_transitioning: bool = false

var turn: int = 0

# ── skill state ───────────────────────────────────────────────────────
var skill_cooldowns: Dictionary = {}       # char_index -> int (turns remaining)
var turn_gem_blasts: Dictionary = {}       # Block.Type -> int (gems blasted this turn)
var last_blast_positions: Array[Vector2i] = []  # positions of the last normal blast (for line detection)

# ── 邏輯狀態（State/UI 分離：用於連續爆破預測驗證）──────────
# 邏輯敵人 HP — 點擊瞬間預扣，視覺由動畫驅動更新
var logic_enemy_hp: Dictionary = {}        # Enemy node -> int
# 邏輯敗人 CD — 與 enemy.turns_until_attack 平行預測
var logic_enemy_cd: Dictionary = {}        # Enemy node -> int
# 邏輯回合計數 — 每次成功 queue 的爆破即遞增
var logic_turn: int = 0
# 預測下回合會觸發敵人攻擊（阻擋玩家輸入直到視覺敵人攻擊播完）
var logic_pending_enemy_attack: bool = false


# ── 初始化 ─────────────────────────────────────────────────────

## 設定關卡與角色資料，初始化血量、冷卻、並生成第一波敎人
func setup(stage: StageData, chars: Array[CharacterData]) -> void:
	characters = chars
	stage_rounds = stage.rounds
	stage_rounds_init_cd = stage.rounds_init_cd

	# 玩家總血量 = 所有角色的最大 HP 加總
	player_max_hp = 0
	for c in characters:
		player_max_hp += c.get_max_hp()
	player_current_hp = player_max_hp
	player_hp_changed.emit(player_current_hp, player_max_hp)

	# 初始化技能冷卻
	skill_cooldowns.clear()
	for i in characters.size():
		if characters[i].active_skill_cd > 0:
			skill_cooldowns[i] = characters[i].active_skill_cd

	turn_gem_blasts.clear()
	last_blast_positions.clear()
	turn = 0
	current_round = 0
	logic_turn = 0
	logic_pending_enemy_attack = false
	logic_enemy_hp.clear()
	logic_enemy_cd.clear()
	_spawn_round(current_round)


# ── 波次管理 ──────────────────────────────────────────────────

## 生成指定波次的敎人
func _spawn_round(round_idx: int) -> void:
	for e in active_enemies:
		if is_instance_valid(e):
			e.queue_free()
	active_enemies.clear()
	targeted_enemy = null

	if round_idx >= stage_rounds.size():
		battle_won.emit()
		return

	var enemy_list: Array = stage_rounds[round_idx]
	var init_cd_list: Array = []
	if round_idx < stage_rounds_init_cd.size():
		init_cd_list = stage_rounds_init_cd[round_idx]
	for i in enemy_list.size():
		var ed: EnemyData = enemy_list[i]
		var enemy: Enemy = EnemyScene.instantiate()
		enemy_container.add_child(enemy)
		var init_cd: int = -1
		if i < init_cd_list.size():
			init_cd = int(init_cd_list[i])
		enemy.setup(ed, init_cd)
		enemy.pressed.connect(_on_enemy_pressed)
		enemy.died.connect(_on_enemy_died)
		active_enemies.append(enemy)
		# 同步邏輯敗人 HP 與 CD
		logic_enemy_hp[enemy] = enemy.current_hp
		logic_enemy_cd[enemy] = enemy.turns_until_attack

	if active_enemies.size() > 0:
		_set_target(active_enemies[0])
	round_spawned.emit(round_idx)


## 取得本波的「主要 Boss」敵人節點。
## 規則：1) 優先返回 data.is_main_boss == true 的敵人；
## 2) 若該波是最後一波且無人標記，回傳該波最後生成的敵人；
## 3) 否則回傳 null。
func get_main_boss_for_round(round_idx: int) -> Enemy:
	for e: Enemy in active_enemies:
		if not is_instance_valid(e):
			continue
		if e.data != null and e.data.is_main_boss:
			return e
	if round_idx == stage_rounds.size() - 1 and active_enemies.size() > 0:
		# 最後一波 fallback：最後生成的（陣列尾端）視為主要 Boss
		var last: Enemy = active_enemies[active_enemies.size() - 1]
		if is_instance_valid(last):
			return last
	return null


## 設定攻擊目標敎人
func _set_target(enemy: Enemy) -> void:
	if targeted_enemy != null and is_instance_valid(targeted_enemy):
		targeted_enemy.set_targeted(false)
	targeted_enemy = enemy
	if targeted_enemy != null:
		targeted_enemy.set_targeted(true)


# ── 寶石消除 / 攻擊計算 ──────────────────────────────────────

## 記錄本回合消除的寶石資訊
func record_blast(gem_type: Block.Type, count: int, positions: Array[Vector2i] = []) -> void:
	turn_gem_blasts[gem_type] = turn_gem_blasts.get(gem_type, 0) + count
	if positions.size() > 0:
		last_blast_positions = positions


## 根據寶石類型和數量計算攻擊資料（傷害、目標、是否克制）
func get_attack_data(gem_type: Block.Type, count: int) -> Array:
	var attacks := []
	# 若當前目標已失效，嘗試自動切換到下一個存活敵人
	var target := targeted_enemy
	if target == null or not is_instance_valid(target) or target.current_hp <= 0:
		target = null
		for e in active_enemies:
			if is_instance_valid(e) and e.current_hp > 0:
				target = e
				break
		if target != null:
			_set_target(target)
	for i in characters.size():
		var c := characters[i]
		if c.gem_type != gem_type:
			continue
		if target == null:
			continue
		var base_dmg := c.get_atk() * count
		var mult := 1.0
		if target != null:
			mult = get_element_multiplier(c.gem_type, target.data.element)
		var dmg := int(base_dmg * mult)
		attacks.append({
			"char_index": i,
			"gem_type": gem_type,
			"count": count,
			"damage": dmg,
			"target": target,
			"is_super": mult > 1.0,
		})
	return attacks


## 元素克制：火→葉、葉→水、水→火 = 1.5倍
func get_element_multiplier(attacker_element: Block.Type, defender_element: Block.Type) -> float:
	# 火（紅）克制 葉（綠）
	if attacker_element == Block.Type.RED and defender_element == Block.Type.GREEN:
		return 1.5
	# 葉（綠）克制 水（藍）
	if attacker_element == Block.Type.GREEN and defender_element == Block.Type.BLUE:
		return 1.5
	# 水（藍）克制 火（紅）
	if attacker_element == Block.Type.BLUE and defender_element == Block.Type.RED:
		return 1.5
	return 1.0


## 取得野豬「飲水」被動的治療量（傷害的 50%）
func get_heal_amount(char_index: int, damage: int) -> int:
	var c := characters[char_index]
	if c.passive_skill_name == "Drinking":
		return int(floor(damage * 0.5))
	return 0


## 回復玩家血量
func apply_heal(amount: int) -> void:
	if amount <= 0:
		return
	player_current_hp = min(player_current_hp + amount, player_max_hp)
	player_hp_changed.emit(player_current_hp, player_max_hp)


## 檢查被動技能觸發，返回最多一個觸發的技能（優先級最高的）。
## 每個項目：{ char_index, skill_name, priority, skill_dict }
func check_responding_skills(board_ref: Node2D = null) -> Array:
	var candidates := []
	for i in characters.size():
		var c := characters[i]
		for skill: Dictionary in c.responding_skills:
			var skill_name: String = skill.get("name", "")
			var threshold: int = skill.get("threshold", 0)
			var priority: int = skill.get("priority", 99)
			var trigger_type: String = skill.get("trigger_type", "count")

			var blasted: int = turn_gem_blasts.get(c.gem_type, 0)

			var triggered := false
			match trigger_type:
				"count":
					triggered = blasted >= threshold
				"line":
					# Need board_ref to check line match in last_blast_positions
					if board_ref != null and blasted >= threshold:
						triggered = board_ref.has_line_match(last_blast_positions, threshold)

			if triggered:
				candidates.append({
					"char_index": i,
					"skill_name": skill_name,
					"priority": priority,
					"skill_dict": skill,
				})

	if candidates.is_empty():
		return []

	# 依優先級排序 — 數字最小的獲勝
	candidates.sort_custom(func(a, b): return a.priority < b.priority)
	# 僅返回優先級最高的單一技能
	return [candidates[0]]


## 檢查角色的主動技能是否已就緒
func is_active_ready(char_index: int) -> bool:
	if not skill_cooldowns.has(char_index):
		return false
	return skill_cooldowns[char_index] <= 0


## 使用主動技能，重置冷卻
func use_active_skill(char_index: int) -> void:
	var c := characters[char_index]
	skill_cooldowns[char_index] = c.active_skill_cd


## 取得角色的當前冷卻回合數
func get_cooldown(char_index: int) -> int:
	return skill_cooldowns.get(char_index, -1)


## 結束回合：遞增回合計數、減少冷卻、清除本回合資料（不含敵人行動）
func finish_turn() -> void:
	turn += 1
	turn_changed.emit(turn)

	# 冷卻遞減
	for i in skill_cooldowns:
		if skill_cooldowns[i] > 0:
			skill_cooldowns[i] -= 1

	turn_gem_blasts.clear()
	last_blast_positions.clear()
	_update_enemy_cds()


## 清除本回合消除資料（融合管線用：不消耗回合）
func reset_blast_data() -> void:
	turn_gem_blasts.clear()
	last_blast_positions.clear()


## 本回合是否有敵人即將行動
func has_enemies_to_attack() -> bool:
	for enemy: Enemy in active_enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.turns_until_attack <= 0:
			return true
	return false


## 更新敎人的攻擊倒數顯示（每回合 -1，下限 0）
func _update_enemy_cds() -> void:
	for enemy: Enemy in active_enemies:
		if not is_instance_valid(enemy):
			continue
		var nv: int = enemy.turns_until_attack - 1
		if nv < 0:
			nv = 0
		enemy.update_cd(nv)


## 執行敵人行動階段（交錯攻擊），回傳是否有敵人發動攻擊
func do_enemy_phase() -> bool:
	var attacking: Array[Enemy] = []
	for enemy: Enemy in active_enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.turns_until_attack <= 0:
			attacking.append(enemy)
	if attacking.is_empty():
		return false
	for i in attacking.size():
		# 重置下一次攻擊 CD（同步邏輯與視覺）
		attacking[i].turns_until_attack = attacking[i].data.attack_interval
		logic_enemy_cd[attacking[i]] = attacking[i].data.attack_interval
		attacking[i].flash_attack()
		_enemy_attack(attacking[i])
		if i < attacking.size() - 1:
			await get_tree().create_timer(0.2).timeout
	return true


## 敎人執行攻擊
func _enemy_attack(enemy: Enemy) -> void:
	enemy_attacked.emit(enemy, enemy.data.attack_damage)


## 對玩家造成傷害
func apply_player_damage(amount: int) -> void:
	player_current_hp = max(0, player_current_hp - amount)
	player_hp_changed.emit(player_current_hp, player_max_hp)
	if player_current_hp <= 0:
		player_defeated.emit()


# ── 邏輯狀態 API（State/UI 分離）─────────────────────────────

## 邏輯側：對指定 gem_type 的爆破預扣敵人 HP 並推進邏輯回合。
## 由 board.gd 在 click queue 時即時呼叫，模擬未來戰鬥狀態。
func logic_apply_blast(gem_type: int, count: int) -> void:
	var target: Enemy = _logic_get_target(gem_type)
	for c in characters:
		if c.gem_type != gem_type:
			continue
		var hit: Enemy = target
		if hit == null:
			continue
		var base_dmg: int = c.get_atk() * count
		var mult: float = get_element_multiplier(c.gem_type, hit.data.element)
		var dmg: int = int(base_dmg * mult)
		logic_enemy_hp[hit] = max(0, logic_enemy_hp.get(hit, 0) - dmg)

	logic_turn += 1
	# 邏輯敗人 CD 同步遞減
	for e in active_enemies:
		if not is_instance_valid(e):
			continue
		if logic_enemy_hp.get(e, 0) <= 0:
			continue
		logic_enemy_cd[e] = int(logic_enemy_cd.get(e, e.turns_until_attack)) - 1
	if _has_logic_enemies_to_attack():
		logic_pending_enemy_attack = true


## 取得邏輯側目前主攻擊目標（活著的敵人；優先 targeted_enemy）
func _logic_get_target(_gem_type: int = -1) -> Enemy:
	if targeted_enemy != null and is_instance_valid(targeted_enemy) and logic_enemy_hp.get(targeted_enemy, 0) > 0:
		return targeted_enemy
	for e in active_enemies:
		if is_instance_valid(e) and logic_enemy_hp.get(e, 0) > 0:
			return e
	return null


## 邏輯側：是否有敵人即將發動攻擊（依 logic_enemy_cd）
func _has_logic_enemies_to_attack() -> bool:
	for e in active_enemies:
		if not is_instance_valid(e):
			continue
		if logic_enemy_hp.get(e, 0) <= 0:
			continue
		if int(logic_enemy_cd.get(e, 1)) <= 0:
			return true
	return false


## 邏輯側：是否仍可接受新的爆破輸入
##   false 表示應阻擋輸入：(1) 邏輯敵人全滅 (2) 邏輯預測下回合敵人攻擊
func logic_can_blast() -> bool:
	if logic_pending_enemy_attack:
		return false
	for e in logic_enemy_hp:
		if logic_enemy_hp[e] > 0:
			return true
	return false


## 視覺敵人攻擊播放完成後呼叫，解除邏輯阻擋
func clear_logic_pending_attack() -> void:
	logic_pending_enemy_attack = false


## 將邏輯狀態重置為與視覺一致（無 queued click 的安全點時呼叫）
func resync_logic_state() -> void:
	logic_turn = turn
	logic_enemy_hp.clear()
	logic_enemy_cd.clear()
	for e in active_enemies:
		if is_instance_valid(e):
			logic_enemy_hp[e] = e.current_hp
			logic_enemy_cd[e] = e.turns_until_attack
	logic_pending_enemy_attack = false


# ── 敎人信號處理 ─────────────────────────────────────────────

## 玩家點擊敎人時設定為攻擊目標
func _on_enemy_pressed(enemy: Enemy) -> void:
	_set_target(enemy)


## 敎人死亡時：移除、重新指定目標、檢查是否進入下一波
func _on_enemy_died(dead_enemy: Enemy) -> void:	# 擲骰掉落表
	var loot_results: Array = []
	for entry: LootItem in dead_enemy.data.loot_table:
		var result: Dictionary = entry.roll()
		if not result.is_empty():
			loot_results.append(result)
	if not loot_results.is_empty():
		loot_dropped.emit(dead_enemy.data, loot_results)
	active_enemies.erase(dead_enemy)
	logic_enemy_hp.erase(dead_enemy)
	if targeted_enemy == dead_enemy:
		targeted_enemy = null
		if active_enemies.size() > 0:
			_set_target(active_enemies[0])

	if not active_enemies.is_empty():
		return

	# 本波敎人全滅 — 進入下一波
	is_round_transitioning = true
	round_transitioning.emit()
	await get_tree().create_timer(0.5).timeout
	current_round += 1
	_spawn_round(current_round)
	is_round_transitioning = false
	if current_round < stage_rounds.size():
		round_cleared.emit()
