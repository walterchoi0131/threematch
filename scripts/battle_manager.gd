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

# ── references set by Main ────────────────────────────────────────────
var enemy_container: HBoxContainer

# ── state ─────────────────────────────────────────────────────────────
var characters: Array[CharacterData] = []

var current_round: int = 0
var stage_rounds: Array[Array] = []

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


# ── 初始化 ─────────────────────────────────────────────────────

## 設定關卡與角色資料，初始化血量、冷卻、並生成第一波敎人
func setup(stage: StageData, chars: Array[CharacterData]) -> void:
	characters = chars
	stage_rounds = stage.rounds

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
	for ed: EnemyData in enemy_list:
		var enemy: Enemy = EnemyScene.instantiate()
		enemy_container.add_child(enemy)
		enemy.setup(ed)
		enemy.pressed.connect(_on_enemy_pressed)
		enemy.died.connect(_on_enemy_died)
		active_enemies.append(enemy)

	if active_enemies.size() > 0:
		_set_target(active_enemies[0])


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
		# Raccoon 自行選目標，即使 target 為 null 也允許攻擊
		if target == null and c.character_name != "Raccoon":
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


## 結束回合：遞增回合計數、減少冷卻、清除本回合資料、處理敎人行動
func finish_turn() -> void:
	turn += 1
	turn_changed.emit(turn)

	# 冷卻遞減
	for i in skill_cooldowns:
		if skill_cooldowns[i] > 0:
			skill_cooldowns[i] -= 1

	turn_gem_blasts.clear()
	last_blast_positions.clear()
	_process_enemy_turns()
	_update_enemy_cds()


## 更新敎人的攻擊倒數顯示
func _update_enemy_cds() -> void:
	for enemy: Enemy in active_enemies:
		if not is_instance_valid(enemy):
			continue
		var remainder: int = turn % enemy.data.attack_interval
		if remainder == 0:
			continue
		enemy.update_cd(enemy.data.attack_interval - remainder)


## 處理所有敎人的回合行動（交錯攻擊，每位間隔一小段時間）
func _process_enemy_turns() -> void:
	var attacking: Array[Enemy] = []
	for enemy: Enemy in active_enemies:
		if not is_instance_valid(enemy):
			continue
		if turn % enemy.data.attack_interval == 0:
			attacking.append(enemy)
	for i in attacking.size():
		attacking[i].flash_attack()
		_enemy_attack(attacking[i])
		if i < attacking.size() - 1:
			await get_tree().create_timer(0.2).timeout


## 敎人執行攻擊
func _enemy_attack(enemy: Enemy) -> void:
	enemy_attacked.emit(enemy, enemy.data.attack_damage)


## 對玩家造成傷害
func apply_player_damage(amount: int) -> void:
	player_current_hp = max(0, player_current_hp - amount)
	player_hp_changed.emit(player_current_hp, player_max_hp)
	if player_current_hp <= 0:
		player_defeated.emit()


# ── 敎人信號處理 ─────────────────────────────────────────────

## 玩家點擊敎人時設定為攻擊目標
func _on_enemy_pressed(enemy: Enemy) -> void:
	_set_target(enemy)


## 敎人死亡時：移除、重新指定目標、檢查是否進入下一波
func _on_enemy_died(dead_enemy: Enemy) -> void:
	active_enemies.erase(dead_enemy)
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
