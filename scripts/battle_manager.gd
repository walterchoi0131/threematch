## BattleManager: mediates between the Board (gem blasting) and the combat system.
class_name BattleManager
extends Node

const EnemyScene := preload("res://scenes/enemy.tscn")

signal player_hp_changed(current: int, maximum: int)
signal player_shield_changed(current: int, maximum: int, reason: String)
signal player_defeated()
signal round_cleared()
signal battle_won()
signal turn_changed(turn: int)
## Emitted when an enemy attacks; Main handles projectile VFX then calls apply_player_damage.
signal enemy_attacked(enemy: Enemy, damage: int)
signal enemy_lightbreak_attacked(enemy: Enemy, damage: int, light_count: int)
## Emitted when an enemy casts stone magic; Main handles board transmutation VFX.
signal enemy_stone_magic_cast(enemy: Enemy)
signal enemy_long_pressed(enemy: Enemy)
signal round_transitioning()  ## 波次轉換中（鎖定棋盤用）
signal round_spawned(round_idx: int)  ## 一波敵人已生成完畢
signal loot_dropped(enemy_data: EnemyData, results: Array, enemy_level: int)  ## 敵人死亡時擁骨的戰利品 (results = Array[Dictionary])
signal turn_gem_blasts_changed()  ## 本回合寶石計數（含 pending_skill_blasts）變動
# ── references set by Main ────────────────────────────────────────────
var enemy_container: HBoxContainer

# ── state ─────────────────────────────────────────────────────────────
var characters: Array[CharacterData] = []

var current_round: int = 0
var stage_rounds: Array[Array] = []
var stage_rounds_init_cd: Array[Array] = []
var stage_rounds_enemy_levels: Array[Array] = []
var stage_rounds_main_bosses: Array[Array] = []
var stage_mode: int = 0  # StageData.Mode（0 = NORMAL, 1 = ESCAPE）

var active_enemies: Array[Enemy] = []
var targeted_enemy: Enemy = null

var player_max_hp: int = 0
var player_current_hp: int = 0
var player_shield: int = 0
var player_shield_damaged_this_turn: bool = false

var is_round_transitioning: bool = false

var turn: int = 0

# ── skill state ───────────────────────────────────────────────────────
var skill_cooldowns: Dictionary = {}       # char_index -> int (turns remaining)
var turn_gem_blasts: Dictionary = {}       # Block.Type -> int (gems blasted this turn)
var pending_skill_blasts: Dictionary = {}  # Block.Type -> int (技能儲存的额外計數，下次以該 type 正常攻擊時計入並清零)
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
	characters = chars.duplicate()
	stage_rounds = stage.rounds
	stage_rounds_init_cd = stage.rounds_init_cd
	stage_rounds_enemy_levels = stage.rounds_enemy_levels
	stage_rounds_main_bosses = stage.rounds_main_bosses
	stage_mode = stage.mode

	# 玩家總血量 = 所有角色的最大 HP 加總
	player_max_hp = 0
	for c in characters:
		player_max_hp += c.get_max_hp()
	player_current_hp = player_max_hp
	player_hp_changed.emit(player_current_hp, player_max_hp)
	player_shield = 0
	player_shield_damaged_this_turn = false
	player_shield_changed.emit(player_shield, player_max_hp, "reset")

	# 初始化技能冷卻
	skill_cooldowns.clear()
	for i in characters.size():
		var active_cd: int = SkillUpgradeUtils.effective_active_cd(characters[i])
		if active_cd > 0:
			skill_cooldowns[i] = active_cd

	turn_gem_blasts.clear()
	pending_skill_blasts.clear()
	last_blast_positions.clear()
	turn = 0
	current_round = 0
	logic_turn = 0
	logic_pending_enemy_attack = false
	logic_enemy_hp.clear()
	logic_enemy_cd.clear()
	# ESCAPE 模式：不生成敵人，勝負由 main.gd 透過 refill 計數判定
	if stage_mode == StageData.Mode.ESCAPE:
		return
	_spawn_round(current_round)


func add_temporary_character(character: CharacterData, add_current_hp: bool = true) -> int:
	if character == null:
		return -1
	characters.append(character)
	var index: int = characters.size() - 1
	var added_hp: int = character.get_max_hp()
	player_max_hp += added_hp
	if add_current_hp:
		player_current_hp = mini(player_current_hp + added_hp, player_max_hp)
	else:
		player_current_hp = mini(player_current_hp, player_max_hp)
	var active_cd: int = SkillUpgradeUtils.effective_active_cd(character)
	if active_cd > 0:
		skill_cooldowns[index] = active_cd
	player_hp_changed.emit(player_current_hp, player_max_hp)
	player_shield_changed.emit(player_shield, player_max_hp, "max_changed")
	return index


# ── 波次管理 ──────────────────────────────────────────────────

## 生成指定波次的敎人
func _spawn_round(round_idx: int) -> void:
	for e in active_enemies:
		if is_instance_valid(e):
			e.queue_free()
	active_enemies.clear()	# 也清理上一波残留的随位佔位符（已隱藏的死敷人豍點）
	for child in enemy_container.get_children():
		child.queue_free()
	targeted_enemy = null

	if round_idx >= stage_rounds.size():
		battle_won.emit()
		return

	var enemy_list: Array = stage_rounds[round_idx]
	var init_cd_list: Array = []
	if round_idx < stage_rounds_init_cd.size():
		init_cd_list = stage_rounds_init_cd[round_idx]
	var level_list: Array = []
	if round_idx < stage_rounds_enemy_levels.size():
		level_list = stage_rounds_enemy_levels[round_idx]
	var boss_list: Array = []
	var has_spawn_boss_list: bool = false
	if round_idx < stage_rounds_main_bosses.size() and stage_rounds_main_bosses[round_idx] is Array:
		boss_list = stage_rounds_main_bosses[round_idx]
		has_spawn_boss_list = true
	for i in enemy_list.size():
		var ed: EnemyData = enemy_list[i]
		var enemy: Enemy = EnemyScene.instantiate()
		enemy.battle_manager_ref = self
		enemy_container.add_child(enemy)
		var init_cd: int = -1
		if i < init_cd_list.size():
			init_cd = int(init_cd_list[i])
		var spawn_level: int = ed.enemy_level
		if i < level_list.size():
			spawn_level = int(level_list[i])
		spawn_level = clampi(spawn_level, 1, 99)
		var estimated_team_hp: int = estimate_team_max_hp_for_level(spawn_level)
		var estimated_max_hp: int = get_enemy_hp_for_level(ed, spawn_level)
		var main_boss_spawn: bool = false
		if has_spawn_boss_list:
			main_boss_spawn = i < boss_list.size() and bool(boss_list[i])
		else:
			main_boss_spawn = ed.is_main_boss
		enemy.setup(ed, init_cd, spawn_level, estimated_team_hp, estimated_max_hp, main_boss_spawn)
		enemy.pressed.connect(_on_enemy_pressed)
		enemy.long_pressed.connect(func(long_enemy: Enemy) -> void:
			enemy_long_pressed.emit(long_enemy)
		)
		enemy.died.connect(_on_enemy_died)
		active_enemies.append(enemy)
		# 同步邏輯敗人 HP 與 CD
		logic_enemy_hp[enemy] = enemy.current_hp
		logic_enemy_cd[enemy] = enemy.turns_until_attack

	round_spawned.emit(round_idx)


## 取得本波的「主要 Boss」敵人節點。
## 規則：1) 優先返回關卡 spawn 標記的敵人；
## 2) 若該波是最後一波且無人標記，回傳該波最後生成的敵人；
## 3) 否則回傳 null。
func get_main_boss_for_round(round_idx: int) -> Enemy:
	for e: Enemy in active_enemies:
		if not is_instance_valid(e):
			continue
		if e.is_main_boss_spawn:
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
	turn_gem_blasts_changed.emit()


## 根據寶石類型和數量計算攻擊資料（傷害、目標、是否克制）
func get_attack_data(gem_type: Block.Type, count: int) -> Array:
	var attacks := []
	# 消耗 pending_skill_blasts（技能儲存的额外數量）：
	# 1) 計入此次攻擊（count += pending） 2) 將其累入 turn_gem_blasts，
	# 讓寶石計量器仍以「合併後總數」顯示。
	var pending: int = int(pending_skill_blasts.get(gem_type, 0))
	if pending > 0:
		count += pending
		turn_gem_blasts[gem_type] = int(turn_gem_blasts.get(gem_type, 0)) + pending
		pending_skill_blasts[gem_type] = 0
		turn_gem_blasts_changed.emit()
	var sim_hp: Dictionary = {}
	for e in active_enemies:
		if is_instance_valid(e):
			sim_hp[e] = e.current_hp
	var target := targeted_enemy
	if target != null and (not is_instance_valid(target) or int(sim_hp.get(target, 0)) <= 0):
		target = null
	for i in characters.size():
		var c := characters[i]
		if c.gem_type != gem_type:
			continue
		var hit_target: Enemy = target if is_instance_valid(target) and int(sim_hp.get(target, 0)) > 0 else _get_best_enemy_for_attack(c, count, sim_hp)
		if hit_target == null:
			for e in active_enemies:
				if is_instance_valid(e) and e.defer_death:
					hit_target = e
					break
		if hit_target == null:
			continue
		var base_dmg := c.get_atk() * count
		var mult := 1.0
		if hit_target != null:
			mult = get_element_multiplier(c.gem_type, hit_target.data.element)
		var dmg := int(base_dmg * mult)
		var predicted_dmg: int = get_enemy_damage_after_passives(hit_target, dmg)
		attacks.append({
			"char_index": i,
			"gem_type": gem_type,
			"count": count,
			"damage": dmg,
			"target": hit_target,
			"is_super": mult > 1.0,
		})
		sim_hp[hit_target] = int(sim_hp.get(hit_target, hit_target.current_hp)) - predicted_dmg
		if target == hit_target and int(sim_hp.get(hit_target, 0)) <= 0:
			target = null
	return attacks


func _get_best_enemy_for_attack(character: CharacterData, count: int, sim_hp: Dictionary) -> Enemy:
	var kill_enemy: Enemy = null
	var kill_remaining_hp: int = -1
	var kill_raw_damage: int = -1
	var best_enemy: Enemy = null
	var best_effective_damage: int = -1
	var best_raw_damage: int = -1
	for e in active_enemies:
		if not is_instance_valid(e):
			continue
		var remaining_hp: int = int(sim_hp.get(e, 0))
		if remaining_hp <= 0:
			continue
		var raw_damage: int = int(float(character.get_atk() * count) * get_element_multiplier(character.gem_type, e.data.element))
		var predicted_damage: int = get_enemy_damage_after_passives(e, raw_damage)
		var effective_damage: int = mini(predicted_damage, remaining_hp)
		if predicted_damage >= remaining_hp and (remaining_hp > kill_remaining_hp or (remaining_hp == kill_remaining_hp and raw_damage > kill_raw_damage)):
			kill_enemy = e
			kill_remaining_hp = remaining_hp
			kill_raw_damage = raw_damage
		if effective_damage > best_effective_damage or (effective_damage == best_effective_damage and raw_damage > best_raw_damage):
			best_enemy = e
			best_effective_damage = effective_damage
			best_raw_damage = raw_damage
	if kill_enemy != null:
		return kill_enemy
	return best_enemy


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


func get_enemy_damage_after_passives(enemy: Enemy, raw_damage: int) -> int:
	if raw_damage <= 0 or enemy == null or not is_instance_valid(enemy) or enemy.data == null:
		return maxi(0, raw_damage)
	match int(enemy.data.passive_type):
		EnemyData.PassiveType.REQUIRE_GEM_COUNT_DAMAGE_GATE:
			var required_count: int = EnemyData.clamp_passive_required_gem_count(enemy.data.passive_required_gem_count)
			var blasted_count: int = int(turn_gem_blasts.get(enemy.data.passive_required_gem_type, 0))
			if blasted_count < required_count:
				return mini(raw_damage, EnemyData.PASSIVE_REDUCED_DAMAGE_DEFAULT)
	return raw_damage


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


func add_player_shield(amount: int) -> void:
	if amount <= 0:
		return
	player_shield += amount
	player_shield_changed.emit(player_shield, player_max_hp, "gain")


## 檢查被動技能觸發，返回最多一個觸發的技能。
## 融合候選優先規則：需求寶石數高者優先；同需求時隊伍前排優先。
## 每個項目：{ char_index, skill_name, priority, threshold, skill_dict }
func check_responding_skills(board_ref: Node2D = null) -> Array:
	var candidates := []
	for i in characters.size():
		var c: CharacterData = characters[i]
		for skill_index in c.responding_skills.size():
			var skill: Dictionary = c.responding_skills[skill_index]
			var skill_name: String = skill.get("name", "")
			var threshold: int = SkillUpgradeUtils.responding_threshold(c, skill_index, skill)
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
					"threshold": threshold,
					"skill_order": skill_index,
					"skill_dict": skill,
				})

	if candidates.is_empty():
		return []

	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_threshold: int = int(a.get("threshold", 0))
		var b_threshold: int = int(b.get("threshold", 0))
		if a_threshold != b_threshold:
			return a_threshold > b_threshold
		var a_char_index: int = int(a.get("char_index", 999))
		var b_char_index: int = int(b.get("char_index", 999))
		if a_char_index != b_char_index:
			return a_char_index < b_char_index
		var a_priority: int = int(a.get("priority", 99))
		var b_priority: int = int(b.get("priority", 99))
		if a_priority != b_priority:
			return a_priority < b_priority
		return int(a.get("skill_order", 999)) < int(b.get("skill_order", 999))
	)
	# 僅返回勝出的單一技能
	return [candidates[0]]


## 檢查角色的主動技能是否已就緒
func is_active_ready(char_index: int) -> bool:
	if not skill_cooldowns.has(char_index):
		return false
	return skill_cooldowns[char_index] <= 0


## 使用主動技能，重置冷卻
func use_active_skill(char_index: int) -> void:
	var c: CharacterData = characters[char_index]
	skill_cooldowns[char_index] = SkillUpgradeUtils.effective_active_cd(c)


## 取得角色的當前冷卻回合數
func get_cooldown(char_index: int) -> int:
	return skill_cooldowns.get(char_index, -1)


## 重置所有角色主動技能冷卻（偵錯用）
func reset_all_skill_cooldowns() -> void:
	for i in skill_cooldowns:
		skill_cooldowns[i] = 0


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
	turn_gem_blasts_changed.emit()
	_update_enemy_cds()


## 清除本回合消除資料（融合管線用：不消耗回合）
func reset_blast_data() -> void:
	turn_gem_blasts.clear()
	last_blast_positions.clear()
	turn_gem_blasts_changed.emit()


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
		var enemy: Enemy = attacking[i]
		var action_type: int = enemy.get_current_action()
		var action_percent: int = enemy.get_current_attack_percent()
		var action_count: int = enemy.get_current_action_count()
		# 重置下一次行動 CD（同步邏輯與視覺），REST 只聚合為 CD 不單獨播放
		var next_cd: int = enemy.advance_to_next_active_action()
		enemy.turns_until_attack = next_cd
		logic_enemy_cd[enemy] = next_cd
		enemy.flash_action(action_type, action_percent, action_count)
		_enemy_act(enemy, action_type, action_percent, action_count)
		if i < attacking.size() - 1:
			await get_tree().create_timer(0.2).timeout
	return true


## 敎人執行目前 pattern 行動
func _enemy_act(enemy: Enemy, action_type: int, action_percent: int, action_count: int) -> void:
	match action_type:
		EnemyData.ActionType.STONE_MAGIC:
			enemy_stone_magic_cast.emit(enemy)
		EnemyData.ActionType.REST:
			pass
		EnemyData.ActionType.BREAK_LIGHT_ATTACK:
			enemy_lightbreak_attacked.emit(
				enemy,
				get_attack_percent_damage_for_level(enemy.spawn_level, action_percent),
				EnemyData.clamp_action_count(action_count)
			)
		_:
			enemy_attacked.emit(enemy, get_attack_percent_damage_for_level(enemy.spawn_level, action_percent))


func estimate_team_max_hp_for_level(level_value: int) -> int:
	var total_hp: int = 0
	var clamped_level: int = clampi(level_value, CharacterData.STAT_LEVEL_MIN, CharacterData.STAT_LEVEL_MAX)
	for c: CharacterData in characters:
		if c == null:
			continue
		total_hp += c.get_max_hp_at_level(clamped_level)
	return total_hp


func estimate_team_attack_power_for_level(level_value: int) -> int:
	var total_attack: int = 0
	var clamped_level: int = clampi(level_value, CharacterData.STAT_LEVEL_MIN, CharacterData.STAT_LEVEL_MAX)
	for c: CharacterData in characters:
		if c == null:
			continue
		total_attack += c.get_atk_at_level(clamped_level)
	return total_attack


func get_attack_percent_damage_for_level(level_value: int, attack_percent: int) -> int:
	var estimated_hp: int = estimate_team_max_hp_for_level(level_value)
	var clamped_percent: int = EnemyData.clamp_attack_percent(attack_percent)
	return maxi(1, int(round(float(estimated_hp) * float(clamped_percent) / 100.0)))


func get_enemy_hp_for_level(enemy_data: EnemyData, level_value: int) -> int:
	if enemy_data == null:
		return 1
	var estimated_attack_power: int = estimate_team_attack_power_for_level(level_value)
	return enemy_data.get_max_hp_for_attack_power(estimated_attack_power)


## 對玩家造成傷害
func apply_player_damage(amount: int) -> void:
	var remaining_damage: int = maxi(0, amount)
	if remaining_damage <= 0:
		return
	if player_shield > 0:
		var absorbed: int = mini(player_shield, remaining_damage)
		player_shield -= absorbed
		remaining_damage -= absorbed
		player_shield_damaged_this_turn = true
		player_shield_changed.emit(player_shield, player_max_hp, "break" if player_shield <= 0 else "damage")
	if remaining_damage <= 0:
		return
	player_current_hp = max(0, player_current_hp - remaining_damage)
	player_hp_changed.emit(player_current_hp, player_max_hp)
	if player_current_hp <= 0:
		player_defeated.emit()


func settle_player_shield_after_enemy_phase() -> void:
	if player_shield_damaged_this_turn and player_shield > 0:
		player_shield = 0
		player_shield_changed.emit(player_shield, player_max_hp, "falloff")
	player_shield_damaged_this_turn = false


# ── 邏輯狀態 API（State/UI 分離）─────────────────────────────

## 邏輯側：對指定 gem_type 的爆破預扣敵人 HP 並推進邏輯回合。
## 由 board.gd 在 click queue 時即時呼叫，模擬未來戰鬥狀態。
func logic_apply_blast(gem_type: int, count: int) -> void:
	var target: Enemy = _logic_get_target(gem_type)
	for c in characters:
		if c.gem_type != gem_type:
			continue
		var hit: Enemy = target if is_instance_valid(target) and int(logic_enemy_hp.get(target, 0)) > 0 else _logic_get_best_target_for_attack(c, count)
		if hit == null:
			continue
		target = hit
		var base_dmg: int = c.get_atk() * count
		var mult: float = get_element_multiplier(c.gem_type, hit.data.element)
		var dmg: int = int(base_dmg * mult)
		var predicted_dmg: int = get_enemy_damage_after_passives(hit, dmg)
		logic_enemy_hp[hit] = max(0, logic_enemy_hp.get(hit, 0) - predicted_dmg)
		if target == hit and int(logic_enemy_hp.get(hit, 0)) <= 0:
			target = null

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
	return null


func _logic_get_best_target_for_attack(character: CharacterData, count: int) -> Enemy:
	var kill_enemy: Enemy = null
	var kill_remaining_hp: int = -1
	var kill_raw_damage: int = -1
	var best_enemy: Enemy = null
	var best_effective_damage: int = -1
	var best_raw_damage: int = -1
	for e in active_enemies:
		if not is_instance_valid(e):
			continue
		var remaining_hp: int = int(logic_enemy_hp.get(e, 0))
		if remaining_hp <= 0:
			continue
		var raw_damage: int = int(float(character.get_atk() * count) * get_element_multiplier(character.gem_type, e.data.element))
		var predicted_damage: int = get_enemy_damage_after_passives(e, raw_damage)
		var effective_damage: int = mini(predicted_damage, remaining_hp)
		if predicted_damage >= remaining_hp and (remaining_hp > kill_remaining_hp or (remaining_hp == kill_remaining_hp and raw_damage > kill_raw_damage)):
			kill_enemy = e
			kill_remaining_hp = remaining_hp
			kill_raw_damage = raw_damage
		if effective_damage > best_effective_damage or (effective_damage == best_effective_damage and raw_damage > best_raw_damage):
			best_enemy = e
			best_effective_damage = effective_damage
			best_raw_damage = raw_damage
	if kill_enemy != null:
		return kill_enemy
	return best_enemy


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
	# 逃脫模式（無敵人）：永遠允許輸入
	if stage_mode == StageData.Mode.ESCAPE:
		return true
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
	if targeted_enemy == enemy:
		_set_target(null)
	else:
		_set_target(enemy)


## 敎人死亡時：移除、重新指定目標、檢查是否進入下一波
func _on_enemy_died(dead_enemy: Enemy) -> void:	# 擲骰掉落表
	var loot_results: Array = []
	for entry: LootItem in dead_enemy.data.loot_table:
		var result: Dictionary = entry.roll()
		if not result.is_empty():
			loot_results.append(result)
	if not loot_results.is_empty():
		loot_dropped.emit(dead_enemy.data, loot_results, dead_enemy.spawn_level)
	active_enemies.erase(dead_enemy)
	logic_enemy_hp.erase(dead_enemy)
	if targeted_enemy == dead_enemy:
		targeted_enemy = null

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
