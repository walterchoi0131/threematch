extends Node2D

const ProjectileScript := preload("res://scripts/projectile.gd")
const GemParticleScript := preload("res://scripts/gem_particle.gd")
const TrailProjectileScript := preload("res://scripts/trail_projectile.gd")
const SlashEffectScript := preload("res://scripts/slash_effect.gd")
const DamageNumberScript := preload("res://scripts/damage_number.gd")
const BulletProjectileScript := preload("res://scripts/bullet_projectile.gd")

# ── scene references ──────────────────────────────────────────────────
@onready var board: Node2D = $Board
@onready var battle_manager: BattleManager = $BattleManager
@onready var fx_layer: CanvasLayer = $FXLayer
@onready var score_label: Label = $UILayer/TopBar/ScoreLabel
@onready var turn_label: Label = $UILayer/TopBar/TurnLabel
@onready var round_label: Label = $UILayer/TopBar/RoundLabel
@onready var player_hp_label: Label = $UILayer/PlayerHPBar/HpLabel
@onready var player_hp_fill: ColorRect = $UILayer/PlayerHPBar/Fill
@onready var enemy_container: HBoxContainer = $UILayer/EnemyRow
@onready var character_panel: HBoxContainer = $UILayer/CharacterRow
@onready var status_label: Label = $UILayer/StatusLabel
@onready var return_button: Button = $UILayer/ReturnButton

# ── game data ─────────────────────────────────────────────────────────
const CHAR_BOAR := preload("res://characters/char_boar.tres")
const CHAR_RACCOON := preload("res://characters/char_raccoon.tres")
const CHAR_FOX := preload("res://characters/char_fox.tres")
const CHAR_HUSKY := preload("res://characters/char_husky.tres")

var party: Array[CharacterData] = []
var current_stage: StageData = null
var _upper_blast_positions: Dictionary = {}  # gem_type -> Array of global positions (for upper gem VFX)
var _is_upper_gem_turn: bool = false  # set when an upper gem click is in progress
var _chain_atk_bonus: float = 0.0    # accumulated chain ATK bonus (0.10 per chain)

# ── VFX 粒子池 ──
const MAX_VFX_PARTICLES := 16
var _vfx_pool: Array = []

# ── 攻擊交錯延遲（多角色連打時，下一位開始攻擊前等待的秒數）──
const ATTACK_STAGGER_SEC := 0.2

# ── 戰鬥日誌 ──
const LOG_PANEL_WIDTH := 272
const LOG_ENTRY_HEIGHT := 40
const GAME_X_OFFSET := 280  # 遊戲內容向右偏移量
const GEM_ICON_PATHS := {
	Block.Type.RED: "res://assets/gems/gem_red.png",
	Block.Type.BLUE: "res://assets/gems/gem_blue.png",
	Block.Type.GREEN: "res://assets/gems/gem_green.png",
	Block.Type.LIGHT: "res://assets/gems/gem_light.png",
}
const UPPER_GEM_ICON_PATHS := {
	Block.UpperType.FIREBALL: "res://assets/gems/gem_fire_bomb.png",
	Block.UpperType.FIRE_PILLAR_X: "res://assets/gems/gem_fire_turnado.png",
	Block.UpperType.FIRE_PILLAR_Y: "res://assets/gems/gem_fire_turnado.png",
	Block.UpperType.SAINT_CROSS: "res://assets/gems/gem_saint_cross.png",
}
var _log_scroll: ScrollContainer = null
var _log_vbox: VBoxContainer = null
var _speed_label: Label = null

# ── SE ───────────────────────────────────────────────────────
var _se_blast: AudioStream = null
var _se_freeze: AudioStream = null
var _se_impact: AudioStream = null


# ── 生命週期 ───────────────────────────────────────────────────

## 初始化：設定關卡、隊伍、連接信號、初始化戰鬥系統
func _ready() -> void:
	current_stage = GameState.selected_stage
	if current_stage == null:
		current_stage = preload("res://stages/stage_dev.tres")

	party = GameState.selected_party.duplicate()
	if party.is_empty():
		party = [CHAR_BOAR, CHAR_RACCOON, CHAR_HUSKY]

	board.gems_blasted.connect(_on_gems_blasted)
	board.score_changed.connect(_on_score_changed)
	board.upper_gem_clicked.connect(_on_upper_gem_clicked)
	board.upper_blast_completed.connect(_on_upper_blast_completed)

	battle_manager.enemy_container = enemy_container
	battle_manager.player_hp_changed.connect(_on_player_hp_changed)
	battle_manager.player_defeated.connect(_on_player_defeated)
	battle_manager.round_cleared.connect(_on_round_cleared)
	battle_manager.round_transitioning.connect(_on_round_transitioning)
	battle_manager.battle_won.connect(_on_battle_won)
	battle_manager.turn_changed.connect(_on_turn_changed)
	battle_manager.enemy_attacked.connect(_on_enemy_attacked)

	character_panel.setup(party)
	character_panel.active_skill_activated.connect(_on_active_skill_activated)
	battle_manager.setup(current_stage, party)
	status_label.visible = false
	return_button.visible = false

	_se_blast = load("res://assets/se/111.wav")
	_se_freeze = load("res://assets/se/skef_freeze.mp3")
	_se_impact = load("res://assets/se/skef_atk1_B.mp3")

	_setup_dev_log()
	_update_skill_ui()
	_setup_fuse_hints()
	_style_player_hp_label()
	_play_bgm()


## 設定融合提示：從隊伍角色中收集融合技能並傳遞給棋盤
func _setup_fuse_hints() -> void:
	var fuse_skills: Array[Dictionary] = []
	for c in party:
		for skill: Dictionary in c.responding_skills:
			var fuse_label: String = skill.get("fuse_label", "")
			if fuse_label.is_empty():
				continue
			fuse_skills.append({
				"gem_type": c.gem_type,
				"threshold": skill.get("threshold", 0),
				"label": fuse_label,
				"trigger_type": skill.get("trigger_type", "count"),
				"priority": skill.get("priority", 99),
			})
	board.set_fuse_skills(fuse_skills)


# ── BGM ───────────────────────────────────────────────────────

## 播放一次性音效
func _play_sfx(stream: AudioStream) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


## 播放關卡背景音樂
func _play_bgm() -> void:
	if current_stage.bgm != null:
		var player := AudioStreamPlayer.new()
		player.stream = current_stage.bgm
		add_child(player)
		player.play()


# ── 開發戰鬥日誌 ──────────────────────────────────────────────

## 建立戰鬥日誌 UI（視窗左側獨立區域，不影響右側遊戲畫面）
func _setup_dev_log() -> void:
	var outer := VBoxContainer.new()
	outer.name = "BattleLogOuter"
	outer.offset_left = 4
	outer.offset_top = 4
	outer.offset_right = LOG_PANEL_WIDTH
	outer.offset_bottom = 1020

	var panel := Control.new()
	panel.name = "BattleLog"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.clip_contents = true

	_log_scroll = ScrollContainer.new()
	_log_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	_log_vbox = VBoxContainer.new()
	_log_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_log_scroll.add_child(_log_vbox)

	panel.add_child(_log_scroll)
	outer.add_child(panel)

	# ── 速度調整滑桿區 ──
	var speed_section := VBoxContainer.new()
	speed_section.name = "SpeedSection"

	var speed_title := Label.new()
	speed_title.text = "Projectile Speed"
	speed_title.add_theme_font_size_override("font_size", 14)
	speed_title.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	speed_section.add_child(speed_title)

	_speed_label = Label.new()
	_speed_label.text = "x%.2f" % TrailProjectileScript.speed_divisor
	_speed_label.add_theme_font_size_override("font_size", 13)
	_speed_label.add_theme_color_override("font_color", Color(1, 0.9, 0.4))
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_section.add_child(_speed_label)

	var slider := HSlider.new()
	slider.min_value = 0.1
	slider.max_value = 5.0
	slider.step = 0.1
	slider.value = TrailProjectileScript.speed_divisor
	slider.custom_minimum_size = Vector2(LOG_PANEL_WIDTH - 8, 28)
	slider.value_changed.connect(func(v: float) -> void:
		TrailProjectileScript.speed_divisor = v
		if _speed_label:
			_speed_label.text = "x%.2f" % v
	)
	speed_section.add_child(slider)

	outer.add_child(speed_section)

	# ── 重新開始按鈕 ──
	var restart_btn := Button.new()
	restart_btn.text = "Restart Battle"
	restart_btn.custom_minimum_size = Vector2(LOG_PANEL_WIDTH - 8, 36)
	restart_btn.pressed.connect(_on_restart_pressed)
	outer.add_child(restart_btn)

	$UILayer.add_child(outer)


## 取得寶石圖示的 BBCode（有貼圖用 [img]，否則用彩色文字）
func _gem_bbcode(gem_type: Block.Type) -> String:
	if GEM_ICON_PATHS.has(gem_type):
		return "[img=25]%s[/img]" % GEM_ICON_PATHS[gem_type]
	var c: Color = Block.COLORS.get(gem_type, Color.WHITE)
	return "[color=#%s]%s[/color]" % [c.to_html(false), Block.ICONS.get(gem_type, "?")]


## 取得高階寶石圖示的 BBCode
func _upper_gem_bbcode(upper_type: Block.UpperType) -> String:
	if UPPER_GEM_ICON_PATHS.has(upper_type):
		return "[img=25]%s[/img]" % UPPER_GEM_ICON_PATHS[upper_type]
	return "?"


## 格式化攻擊日誌 BBCode：寶石圖示 數量 × ⚔ATK [×多段] [×屬性] [×連鏈] = 傷害
func _format_atk_bbcode(gem_type: Block.Type, gem_count: int, atk: int, damage: int, multi_hits: int = 1, element_mult: float = 1.0, chain_mult: float = 1.0) -> String:
	var s := "%s%d × ⚔%d" % [_gem_bbcode(gem_type), gem_count, atk]
	if multi_hits > 1:
		s += " ×%d" % multi_hits
	if element_mult > 1.0:
		s += " ×%.1f" % element_mult
	if chain_mult > 1.0:
		s += " ×%.1f鎖" % chain_mult
	s += " = %d" % damage
	return s


## 格式化融合日誌 BBCode：寶石圖示 數量 → 高階寶石圖示
func _format_fuse_bbcode(gem_type: Block.Type, gem_count: int, upper_type: Block.UpperType) -> String:
	return "%s%d → %s" % [_gem_bbcode(gem_type), gem_count, _upper_gem_bbcode(upper_type)]


## 新增一筆日誌條目（三層結構：元素漸層 + 角色眼部肖像 + 文字）
func _add_log_entry(bbcode_text: String, gem_type: Block.Type = Block.Type.RED, char_data: CharacterData = null) -> void:
	if _log_vbox == null:
		return

	var entry := Control.new()
	entry.custom_minimum_size = Vector2(LOG_PANEL_WIDTH, LOG_ENTRY_HEIGHT)

	# Layer 1: 元素色漸層背景（左→右：半透明色→全透明）
	var grad_rect := TextureRect.new()
	var grad_tex := GradientTexture2D.new()
	var grad := Gradient.new()
	var elem_color: Color = Block.COLORS.get(gem_type, Color.WHITE)
	grad.set_color(0, Color(elem_color.r, elem_color.g, elem_color.b, 0.7))
	grad.set_color(1, Color(elem_color.r, elem_color.g, elem_color.b, 0.0))
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0, 0.5)
	grad_tex.fill_to = Vector2(1, 0.5)
	grad_tex.width = LOG_PANEL_WIDTH
	grad_tex.height = LOG_ENTRY_HEIGHT
	grad_rect.texture = grad_tex
	grad_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(grad_rect)

	# Layer 2: 角色肖像裁切（只顯示眼部區域，0.1 縮放 + 半透明）
	# 裁切參數說明：region = Rect2(x起始%, y起始%, 寬度%, 高度%)
	#   Boar 眼部約在圖片 15%~35% 高度；Raccoon 約 18%~32%；Fox 約 20%~38%
	#   若需調整，修改下方 eye_y (Y起始比例) 和 eye_h (高度比例)
	if char_data != null and char_data.portrait_texture != null:
		var portrait := TextureRect.new()
		var atlas := AtlasTexture.new()
		atlas.atlas = char_data.portrait_texture
		var tex_size := char_data.portrait_texture.get_size()
		var eye_y := 0.15   # ← 調整此值改變裁切 Y 起始位置 (0.0=頂部, 1.0=底部)
		var eye_h := 0.20   # ← 調整此值改變裁切高度
		var eye_x := 0.10   # ← 調整此值改變裁切 X 起始位置
		var eye_w := 0.80   # ← 調整此值改變裁切寬度
		atlas.region = Rect2(tex_size.x * eye_x, tex_size.y * eye_y, tex_size.x * eye_w, tex_size.y * eye_h)
		portrait.texture = atlas
		portrait.custom_minimum_size = Vector2(LOG_PANEL_WIDTH * 0.1, LOG_ENTRY_HEIGHT)
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.modulate = Color(1, 1, 1, 0.35)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait.scale = Vector2(0.1, 0.1)
		portrait.position = Vector2(2, (LOG_ENTRY_HEIGHT - LOG_ENTRY_HEIGHT * 0.1) * 0.5)
		entry.add_child(portrait)

	# Layer 3: 文字（白色 + 黑色描邊）— 使用 VBoxContainer 垂直置中
	var text_wrap := VBoxContainer.new()
	text_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	text_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	text_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.text = bbcode_text
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rtl.add_theme_font_size_override("normal_font_size", 20)
	rtl.add_theme_color_override("default_color", Color.WHITE)
	rtl.add_theme_constant_override("outline_size", 4)
	rtl.add_theme_color_override("font_outline_color", Color.BLACK)
	text_wrap.add_child(rtl)
	entry.add_child(text_wrap)

	_log_vbox.add_child(entry)

	# 自動捲動到底部
	await get_tree().process_frame
	if is_instance_valid(_log_scroll):
		_log_scroll.scroll_vertical = int(_log_scroll.get_v_scroll_bar().max_value)


# ── 傷害數字輔助方法 ──────────────────────────────────────────

## 在指定位置生成浮動傷害數字
func _spawn_damage_number(pos: Vector2, amount: int, color: Color, random_x_offset: bool = false, is_super: bool = false) -> void:
	var dn := Node2D.new()
	dn.set_script(DamageNumberScript)
	fx_layer.add_child(dn)
	dn.show_number(pos, amount, color, random_x_offset, is_super)


# ── 棋盤回呼 ─────────────────────────────────────────────────

## 寶石消除後的主要處理流程：
## 1. 記錄消除資料
## 2. 檢查是否觸發融合技能（火球/火柱）
## 3. 融合流程：粒子飛向點擊位置 → 放置高階寶石 → 掉落填充
## 4. 普通流程：粒子飛向角色卡 → 攻擊動畫 → 回應技能 → 結束回合
func _on_gems_blasted(gem_type: Block.Type, count: int, global_positions: Array) -> void:
	_play_sfx(_se_blast)
	board.is_busy = true  # 鎖定棋盤直到整個攻擊序列結束
	# 將全局座標轉換為網格座標（用於直線檢測）
	var grid_positions: Array[Vector2i] = []
	for gp in global_positions:
		var local_pos: Vector2 = board.to_local(gp)
		grid_positions.append(board.world_to_grid(local_pos))

	# 記錄消除資料以觸發回應技能
	battle_manager.record_blast(gem_type, count, grid_positions)

	# 高階寶石連鏈爆炸期間跳過攻擊序列（統一在結束時計算傷害）
	if _is_upper_gem_turn:
		# 儲存每種寶石的爆炸位置（用於 VFX 起始點）
		if not _upper_blast_positions.has(gem_type):
			_upper_blast_positions[gem_type] = []
		_upper_blast_positions[gem_type].append_array(global_positions)
		return

	# 先檢查回應技能以決定流程
	var responses := battle_manager.check_responding_skills(board)
	var _upper_gem_skills: Array[String] = ["Fireball", "Fire Pillar", "Justice Slash"]
	var is_fuse: bool = responses.size() > 0 and (responses[0].skill_name as String) in _upper_gem_skills

	if is_fuse:
		# ── 融合流程：告訴棋盤跳過掉落，我們在放置高階寶石後再處理 ──
		board.skip_collapse = true

		var fuse_target: Vector2 = board.to_global(board.grid_to_world(board.last_tapped_pos))
		var color: Color = Block.COLORS[gem_type]
		var particle_duration := 1.05  # 與普通爆炸 VFX 飛行速度一致
		# 寶石粒子飛向點擊位置
		var fuse_total: int = mini(global_positions.size(), MAX_VFX_PARTICLES)
		for idx in fuse_total:
			var particle: Node2D = _acquire_particle()
			if particle == null:
				break
			var gem_pos: Vector2 = global_positions[idx]
			var spread: float = (float(idx) / max(fuse_total - 1, 1)) * 2.0 - 1.0 if fuse_total > 1 else 0.0
			particle.launch(gem_pos, fuse_target, color, particle_duration, spread)
		await get_tree().create_timer(particle_duration / TrailProjectileScript.speed_divisor + 0.05).timeout

		# 在點擊位置放置高階寶石（寶石仍在因為跳過了掉落）
		for resp in responses:
			await _execute_responding_skill(resp)

		# Now collapse remaining gems around the upper gem
		await board.do_collapse()

		battle_manager.finish_turn()
		await _process_turn_start_passives()
		_update_skill_ui()
		if not battle_manager.is_round_transitioning:
			board.is_busy = false
		return

	# ── 普通攻擊流程（透過通用管線）──
	var blasted_dict: Dictionary = { gem_type: count }
	var blast_pos_dict: Dictionary = { gem_type: global_positions }
	await _process_blast_results(blasted_dict, blast_pos_dict)

	# 第3階段：執行非融合的回應技能（如葉風暴）
	for resp in responses:
		await _execute_responding_skill(resp)

	battle_manager.finish_turn()

	# 第4階段：回合開始的被動技能（如浣熊的光合作用）
	await _process_turn_start_passives()

	_update_skill_ui()
	if not battle_manager.is_round_transitioning:
		board.is_busy = false


func _on_score_changed(new_score: int) -> void:
	score_label.text = "Score: %d" % new_score


## 從池中取得一個可用的 VFX 粒子節點（池滿且全忙時回傳 null）
func _acquire_particle() -> Node2D:
	for p in _vfx_pool:
		if p.is_available:
			return p
	if _vfx_pool.size() < MAX_VFX_PARTICLES:
		var p := Node2D.new()
		p.set_script(TrailProjectileScript)
		fx_layer.add_child(p)
		p.setup()
		_vfx_pool.append(p)
		return p
	return null


# ── 通用消除處理管線 ─────────────────────────────────────────────

## 處理一批消除結果：VFX 飛向角色卡 → 角色攻擊動畫
## blasted_by_type: { Block.Type -> count }
## blast_positions: { Block.Type -> Array[Vector2] } 全域座標（用於 VFX 起始點）
## chain_bonus: 連鏈 ATK 加成倍率（例如 0.10 = 加 10%）
func _process_blast_results(blasted_by_type: Dictionary, blast_positions: Dictionary, chain_bonus: float = 0.0) -> void:
	var particle_duration := 1.05
	var all_attacks: Array = []

	# 計算各類型的粒子預算（按比例分配 MAX_VFX_PARTICLES）
	var total_raw := 0
	for k in blasted_by_type:
		total_raw += mini(blasted_by_type[k] as int, 8)

	for gem_type_key in blasted_by_type:
		var gem_type: Block.Type = gem_type_key as Block.Type
		var count: int = blasted_by_type[gem_type_key]
		var attacks := battle_manager.get_attack_data(gem_type, count)
		var color: Color = Block.COLORS[gem_type]
		var raw: int = mini(count, 8)
		var budget: int = maxi(1, roundi(float(MAX_VFX_PARTICLES) * raw / total_raw)) if total_raw > 0 else 1
		var chain_total: int = mini(raw, budget)
		var blast_pos_list: Array = blast_positions.get(gem_type, [])

		# 決定粒子飛往的目標位置
		var card_center: Vector2
		if attacks.size() > 0:
			card_center = character_panel.get_card_screen_center(attacks[0].char_index)
		else:
			var found_card := false
			for ci in party.size():
				if party[ci].gem_type == gem_type:
					card_center = character_panel.get_card_screen_center(ci)
					found_card = true
					break
			if not found_card:
				card_center = board.global_position + Vector2(board.columns * 32, -30)

		# 發射 VFX 粒子（從池取得）
		for i in chain_total:
			var particle: Node2D = _acquire_particle()
			if particle == null:
				break
			var spread: float = (float(i) / max(chain_total - 1, 1)) * 2.0 - 1.0 if chain_total > 1 else 0.0
			var from_pos: Vector2 = blast_pos_list[i % blast_pos_list.size()] if blast_pos_list.size() > 0 else board.global_position + Vector2(board.columns * 32, board.rows * 32)
			particle.launch(from_pos, card_center, color, particle_duration, spread)

		# 套用連鏈加成並排入攻擊佇列
		for attack in attacks:
			var chain_mult: float = 1.0 + chain_bonus
			attack.damage = int(attack.damage * chain_mult)
			attack["chain_mult"] = chain_mult
			all_attacks.append(attack)

	# 等待所有 VFX 同時飛抵目標
	if blasted_by_type.size() > 0:
		await get_tree().create_timer(particle_duration / TrailProjectileScript.speed_divisor + 0.05).timeout

	# 啟用延遲死亡：攻擊序列中最後一隻怪不會立刻死亡（過殺機制）
	for enemy in battle_manager.active_enemies:
		if is_instance_valid(enemy):
			enemy.defer_death = true

	# 依序播放所有角色攻擊動畫（每位之間只間隔 ATTACK_STAGGER_SEC，不等上一位完成）
	for i in all_attacks.size():
		_play_attack_sequence(all_attacks[i])  # fire-and-forget
		if i < all_attacks.size() - 1:
			await get_tree().create_timer(ATTACK_STAGGER_SEC).timeout
	# 等待最後一位攻擊的投射物落地（最長飛行時間 + 餘裕）
	await get_tree().create_timer(0.5 / TrailProjectileScript.speed_divisor + 0.15).timeout

	# 攻擊序列結束：結算所有延遲死亡的敵人
	for enemy in battle_manager.active_enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.defer_death = false
			if enemy.current_hp <= 0:
				enemy.finalize_death()


# ── 攻擊特效 ───────────────────────────────────────────────────

## 播放單次攻擊序列：角色卡上彈 → 攻擊特效 → 角色卡回位（全部非阻塞，fire-and-forget）
func _play_attack_sequence(attack: Dictionary) -> void:
	var char_index: int = attack.char_index
	var gem_type: Block.Type = attack.gem_type as Block.Type
	var damage: int = attack.damage
	var gem_count: int = attack.count
	var target_ref: Variant = attack.get("target")
	var target: Enemy = target_ref as Enemy if is_instance_valid(target_ref) else null
	var is_super: bool = attack.get("is_super", false)

	# 若原目標已失效，嘗試重新選擇一個存活敵人；若無存活敵人則過殺原目標
	if not is_instance_valid(target) or target.current_hp <= 0:
		var new_target: Enemy = null
		for e in enemy_container.get_children():
			if is_instance_valid(e) and (e as Enemy).current_hp > 0:
				new_target = e as Enemy
				break
		if new_target != null:
			target = new_target
		elif is_instance_valid(target) and target.defer_death:
			pass  # 過殺：繼續攻擊延遲死亡的最後一隻怪
		else:
			target = null

	var char_data := party[char_index]
	var mult: float = 1.5 if is_super else 1.0
	var chain_mult: float = attack.get("chain_mult", 1.0)

	# Raccoon 不需要 target（自行選擇隨機存活敵人），其他角色需要
	if target == null and char_data.character_name != "Raccoon":
		return

	# 角色卡片向上彈起
	await character_panel.play_card_attack_up(char_index)

	# 根據角色類型播放不同的攻擊特效
	match char_data.character_name:
		"Boar":  # 水屬性 — 斬擊特效 + 治療
			if is_instance_valid(target):
				var slash := Node2D.new()
				slash.set_script(SlashEffectScript)
				fx_layer.add_child(slash)
				var target_pos := target.get_global_rect().get_center()
				slash.deduct_hp.connect(func():
					if is_instance_valid(target):
						target.take_damage(damage)
						_spawn_damage_number(target.get_global_rect().get_center(), damage, Block.COLORS[gem_type], true, is_super)
					_play_sfx(_se_impact)
				, CONNECT_ONE_SHOT)
				await slash.play(target_pos)
			_add_log_entry(_format_atk_bbcode(gem_type, gem_count, char_data.get_atk(), damage, 1, mult, chain_mult), gem_type, char_data)
			# 「飲水」被動：治療傷害的 50%
			var heal := battle_manager.get_heal_amount(char_index, damage)
			if heal > 0:
				battle_manager.apply_heal(heal)
				character_panel.show_heal_text(char_index, heal)
			_add_log_entry("%s [b]飲水[/b] [color=#44ff88]+%d[/color]" % [_gem_bbcode(gem_type), heal], gem_type, char_data)
		"Raccoon":  # 葉屬性 — 每 3 個寶石發射 1 枝箭，每枝隨機攻擊一個存活敵人
			var arrow_count := ceili(float(gem_count) / 3.0)
			var arrow_damage := char_data.get_atk() * 3
			var card_center: Vector2 = character_panel.get_card_screen_center(char_index)
			# 計算總傷害用於日誌摘要
			var total_arrow_dmg := 0
			var any_super := false
			for arrow_idx in arrow_count:
				# 發射前即時選擇一個隨機存活敵人
				var living: Array = []
				for e in enemy_container.get_children():
					if is_instance_valid(e) and (e as Enemy).current_hp > 0:
						living.append(e)
				if living.is_empty():
					# 過殺：退而攻擊延遲死亡的敵人
					for e in enemy_container.get_children():
						if is_instance_valid(e) and (e as Enemy).defer_death:
							living.append(e)
				if living.is_empty():
					break
				var arrow_target: Enemy = living[randi() % living.size()]
				var arrow_mult := battle_manager.get_element_multiplier(char_data.gem_type, arrow_target.data.element)
				var arrow_final := int(arrow_damage * arrow_mult)
				var arrow_super := arrow_mult > 1.0
				if arrow_super:
					any_super = true
				total_arrow_dmg += arrow_final
				var target_pos := arrow_target.get_global_rect().get_center()
				var bullet := Node2D.new()
				bullet.set_script(BulletProjectileScript)
				fx_layer.add_child(bullet)
				var captured_target := arrow_target
				var captured_dmg := arrow_final
				bullet.deduct_hp.connect(func():
					if is_instance_valid(captured_target) and (captured_target.current_hp > 0 or captured_target.defer_death):
						captured_target.take_damage(captured_dmg)
						_spawn_damage_number(captured_target.get_global_rect().get_center(), captured_dmg, Block.COLORS[gem_type], true, arrow_super)
						_play_sfx(_se_impact)
				, CONNECT_ONE_SHOT)
				bullet.play(card_center, target_pos)
				if arrow_idx < arrow_count - 1:
					await get_tree().create_timer(0.2).timeout
			# 箭矢摘要日誌
			var raccoon_mult: float = 1.5 if any_super else 1.0
			_add_log_entry(_format_atk_bbcode(gem_type, gem_count, char_data.get_atk(), total_arrow_dmg, arrow_count, raccoon_mult, chain_mult), gem_type, char_data)
			# 等待最後一枝箭矢到達
			await get_tree().create_timer(0.45).timeout
		_:  # 預設攻擊：拖尾弧光從角色卡飛向敵人
			if is_instance_valid(target):
				var card_center: Vector2 = character_panel.get_card_screen_center(char_index)
				var target_pos := target.get_global_rect().get_center()
				var color: Color = Block.COLORS[gem_type]
				var trail := Node2D.new()
				trail.set_script(TrailProjectileScript)
				fx_layer.add_child(trail)
				var captured_target := target
				var captured_dmg := damage
				trail.deduct_hp.connect(func():
					if is_instance_valid(captured_target) and (captured_target.current_hp > 0 or captured_target.defer_death):
						captured_target.take_damage(captured_dmg)
						_spawn_damage_number(captured_target.get_global_rect().get_center(), captured_dmg, color, true, is_super)
					_play_sfx(_se_impact)
				, CONNECT_ONE_SHOT)
				trail.launch(card_center, target_pos, color, 0.5)
				await get_tree().create_timer(0.5 / TrailProjectileScript.speed_divisor + 0.05).timeout
			_add_log_entry(_format_atk_bbcode(gem_type, gem_count, char_data.get_atk(), damage, 1, mult, chain_mult), gem_type, char_data)

	# Card moves back (non-blocking)
	character_panel.play_card_return(char_index)


# ── responding skills ─────────────────────────────────────────────────

func _execute_responding_skill(resp: Dictionary) -> void:
	var skill_name: String = resp.skill_name
	match skill_name:
		"Leaf Storm":
			# Convert 3 gems → leaf, priority RED > BLUE
			var priority: Array[Block.Type] = [Block.Type.RED, Block.Type.BLUE]
			board.convert_gems(Block.Type.GREEN, 3, priority)
			var _rc: CharacterData = party[resp.char_index]
			_add_log_entry("[b]葉風暴[/b] %s ×3" % [_gem_bbcode(Block.Type.GREEN)], Block.Type.GREEN, _rc)
			await get_tree().create_timer(0.4).timeout
		"Fireball":
			# Place a Fireball upper gem at the tapped position
			var pos: Vector2i = board.last_tapped_pos
			board.place_upper_gem(pos, Block.UpperType.FIREBALL)
			_play_sfx(_se_freeze)
			var _fc: CharacterData = party[resp.char_index]
			var _fc_count: int = int(battle_manager.turn_gem_blasts.get(_fc.gem_type, 0))
			_add_log_entry(_format_fuse_bbcode(_fc.gem_type, _fc_count, Block.UpperType.FIREBALL), _fc.gem_type, _fc)
			await get_tree().create_timer(0.15).timeout
		"Fire Pillar":
			# Place a Fire Pillar upper gem based on blast direction
			var pos: Vector2i = board.last_tapped_pos
			var blast_dir: String = board.get_line_direction(battle_manager.last_blast_positions)
			var pillar_type: Block.UpperType
			if blast_dir == "horizontal":
				pillar_type = Block.UpperType.FIRE_PILLAR_X
			else:
				pillar_type = Block.UpperType.FIRE_PILLAR_Y
			board.place_upper_gem(pos, pillar_type)
			_play_sfx(_se_freeze)
			var _pc: CharacterData = party[resp.char_index]
			var _pc_count: int = int(battle_manager.turn_gem_blasts.get(_pc.gem_type, 0))
			_add_log_entry(_format_fuse_bbcode(_pc.gem_type, _pc_count, pillar_type), _pc.gem_type, _pc)
			await get_tree().create_timer(0.15).timeout
		"Justice Slash":
			# Place a Saint Cross upper gem at the tapped position
			var pos: Vector2i = board.last_tapped_pos
			board.place_upper_gem(pos, Block.UpperType.SAINT_CROSS)
			_play_sfx(_se_freeze)
			var _hc: CharacterData = party[resp.char_index]
			var _hc_count: int = int(battle_manager.turn_gem_blasts.get(_hc.gem_type, 0))
			_add_log_entry(_format_fuse_bbcode(_hc.gem_type, _hc_count, Block.UpperType.SAINT_CROSS), _hc.gem_type, _hc)
			await get_tree().create_timer(0.15).timeout


# ── upper gem handlers ───────────────────────────────────────────────

## 高階寶石被點擊時：設定爆炸模式
func _on_upper_gem_clicked() -> void:
	_is_upper_gem_turn = true
	_chain_atk_bonus = 0.0
	_upper_blast_positions.clear()


## 高階寶石爆炸完成後：計算連鏈加成、播放攻擊序列
func _on_upper_blast_completed(chain_count: int, blasted_by_type: Dictionary, triggered_upper: Block.UpperType) -> void:
	# ── 聖十字特殊處理：全部敵方寶石 × 50 攻擊力 + 回復 20% HP ──
	if triggered_upper == Block.UpperType.SAINT_CROSS:
		var total_enemy_gems := 0
		for bt in blasted_by_type:
			total_enemy_gems += blasted_by_type[bt] as int
		# 找到 Husky 角色計算 ATK
		var husky_data: CharacterData = null
		var husky_index := -1
		for i in party.size():
			if party[i].gem_type == Block.Type.LIGHT:
				husky_data = party[i]
				husky_index = i
				break
		var base_atk := husky_data.get_atk() if husky_data != null else 5
		var chain_mult: float = 1.0 + (chain_count - 1) * 0.10
		var holy_damage := int(total_enemy_gems * 50 * base_atk * chain_mult)
		# 連鏈 ≥ 2 時顯示連鏈 UI
		if chain_count >= 2:
			_show_chain_label(chain_count)
			await get_tree().create_timer(0.6).timeout
		# 對所有存活敵人造成傷害
		for enemy in battle_manager.active_enemies:
			if is_instance_valid(enemy) and enemy.current_hp > 0:
				enemy.take_damage(holy_damage)
				_spawn_damage_number(enemy.get_global_rect().get_center(), holy_damage, Block.COLORS[Block.Type.LIGHT], true)
				await get_tree().create_timer(0.15).timeout
		# 回復 20% 最大血量
		var heal_amount := int(floor(battle_manager.player_max_hp * 0.2))
		battle_manager.apply_heal(heal_amount)
		if husky_index >= 0:
			character_panel.show_heal_text(husky_index, heal_amount)
		var chain_str := (" ×%.1f鎖" % chain_mult) if chain_count >= 2 else ""
		_add_log_entry("[b]聖十字[/b] %s %d × ⚔%d%s = %d 回覆%d" % [_gem_bbcode(Block.Type.LIGHT), total_enemy_gems, base_atk, chain_str, holy_damage, heal_amount], Block.Type.LIGHT, husky_data)
		# 重置狀態
		_is_upper_gem_turn = false
		_chain_atk_bonus = 0.0
		battle_manager.finish_turn()
		await _process_turn_start_passives()
		_update_skill_ui()
		if not battle_manager.is_round_transitioning:
			board.is_busy = false
		return
	# 計算連鏈攻擊加成（每層連鏈 +10%，首次不加）
	_chain_atk_bonus = (chain_count - 1) * 0.10

	# 連鏈 ≥ 2 時顯示連鏈 UI
	if chain_count >= 2:
		_show_chain_label(chain_count)
		await get_tree().create_timer(0.6).timeout

	# 透過通用管線播放 VFX → 攻擊
	await _process_blast_results(blasted_by_type, _upper_blast_positions, _chain_atk_bonus)

	# 重置狀態
	_is_upper_gem_turn = false
	_chain_atk_bonus = 0.0

	battle_manager.finish_turn()
	await _process_turn_start_passives()
	_update_skill_ui()
	if not battle_manager.is_round_transitioning:
		board.is_busy = false


## 顯示連鏈數字標籤（縮放彈跳 + 淡出）
func _show_chain_label(chain_count: int) -> void:
	var label := Label.new()
	label.text = "Chain ×%d!" % chain_count
	label.add_theme_font_size_override("font_size", 40)
	label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 6)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(get_viewport_rect().size.x / 2 - 100, get_viewport_rect().size.y / 2 - 40)
	label.z_index = 100
	label.scale = Vector2(0.5, 0.5)
	fx_layer.add_child(label)

	var tw := create_tween()
	tw.tween_property(label, "scale", Vector2(1.2, 1.2), 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(label, "scale", Vector2(1.0, 1.0), 0.1)
	tw.tween_interval(0.4)
	tw.tween_property(label, "modulate:a", 0.0, 0.3)
	tw.tween_callback(label.queue_free)


# ── 回合開始被動技能 ──────────────────────────────────────────

## 處理回合開始時的被動技能（如浣熊的光合作用）
func _process_turn_start_passives() -> void:
	for i in party.size():
		var c := party[i]
		if c.passive_skill_name == "Photosynthesis":
			# 光合作用：轉 3 個寶石為葉（優先紅 > 藍）
			var priority: Array[Block.Type] = [Block.Type.RED, Block.Type.BLUE]
			board.convert_gems(Block.Type.GREEN, 3, priority)
			_add_log_entry("光合作用：3→%s" % _gem_bbcode(Block.Type.GREEN), Block.Type.GREEN, c)
			await get_tree().create_timer(0.4).timeout


# ── 主動技能 ─────────────────────────────────────────────────

## 角色主動技能觸發（玩家點擊角色卡片）
func _on_active_skill_activated(char_index: int) -> void:
	if board.is_busy:
		return
	if not battle_manager.is_active_ready(char_index):
		return

	var c := party[char_index]
	match c.active_skill_name:
		"Attack Form":
			# 攻擊形態：將所有火寶石轉為水寶石
			battle_manager.use_active_skill(char_index)
			board.convert_all_of_type(Block.Type.RED, Block.Type.BLUE)
			_add_log_entry("攻擊形態：%s→%s" % [_gem_bbcode(Block.Type.RED), _gem_bbcode(Block.Type.BLUE)], Block.Type.BLUE, c)
			await get_tree().create_timer(0.4).timeout
			_update_skill_ui()
		"There shall be light":
			# 光輝降臨：進入選擇模式，懸停預覽十字範圍，點擊確認轉換為光寶石
			battle_manager.use_active_skill(char_index)
			_update_skill_ui()
			board.enter_selection_mode(Block.Type.LIGHT)
			# 等待玩家點擊確認
			var positions: Array = await board.selection_confirmed
			# 轉換十字範圍內的寶石
			var converted := 0
			for pos in positions:
				var p: Vector2i = pos as Vector2i
				if board.grid[p.x][p.y] != null and board.grid[p.x][p.y].block_type != Block.Type.LIGHT:
					board._animate_gem_morph(board.grid[p.x][p.y], Block.Type.LIGHT)
					converted += 1
			_add_log_entry("光輝降臨：%d→%s" % [converted, _gem_bbcode(Block.Type.LIGHT)], Block.Type.LIGHT, c)
			await get_tree().create_timer(0.4).timeout
		"爆炸":
			# 爆炸：由上到下逐行消除所有寶石，VFX 飛向角色卡 → 攻擊，然後填充
			battle_manager.use_active_skill(char_index)
			board.is_busy = true
			_is_upper_gem_turn = true
			_upper_blast_positions.clear()
			var blasted: Dictionary = await board.blast_all_rows_sequential(0.12)
			_is_upper_gem_turn = false
			await board._collapse_and_fill()
			# 統計總消除數
			var total_gems := 0
			for bt in blasted:
				total_gems += blasted[bt] as int
			_add_log_entry("爆炸：%s 消除 %d 顆寶石" % [_gem_bbcode(Block.Type.RED), total_gems], Block.Type.RED, c)
			# 透過通用管線播放 VFX → 攻擊
			await _process_blast_results(blasted, _upper_blast_positions)
			battle_manager.finish_turn()
			await _process_turn_start_passives()
			_update_skill_ui()
			if not battle_manager.is_round_transitioning:
				board.is_busy = false


## 更新技能 UI（冷卻顯示、就緒發光）
func _update_skill_ui() -> void:
	for i in party.size():
		var cd := battle_manager.get_cooldown(i)
		if cd < 0:
			# 無主動技能
			character_panel.update_cooldown(i, -1)
			continue
		character_panel.update_cooldown(i, cd)
		if cd <= 0:
			character_panel.start_glow(i)


# ── 敎人攻擊特效 ─────────────────────────────────────────────

## 敎人攻擊時：拖尾弧光從敎人飛向玩家血條
func _on_enemy_attacked(enemy: Enemy, damage: int) -> void:
	if not is_instance_valid(enemy):
		battle_manager.apply_player_damage(damage)
		return
	var from_pos: Vector2 = enemy.get_global_rect().get_center()
	var to_pos: Vector2 = player_hp_fill.get_global_rect().get_center()
	var color: Color = enemy.data.portrait_color

	var trail := Node2D.new()
	trail.set_script(TrailProjectileScript)
	fx_layer.add_child(trail)
	trail.deduct_hp.connect(func() -> void:
		battle_manager.apply_player_damage(damage)
		_spawn_damage_number(to_pos, damage, Color(1.0, 0.3, 0.3))
		_play_sfx(_se_impact)
	, CONNECT_ONE_SHOT)
	trail.launch(from_pos, to_pos, color, 0.5)


# ── 戰鬥回呼 ──────────────────────────────────────────────────

## 玩家血量變化時更新 UI（血條動畫 + 受傷/治療閃光）
func _on_player_hp_changed(current: int, maximum: int) -> void:
	player_hp_label.text = "%d" % current
	var ratio: float = float(current) / float(maximum) if maximum > 0 else 0.0
	var hp_tween := create_tween()
	hp_tween.tween_property(player_hp_fill, "scale:x", ratio, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# 治療時閃綠，受傷時閃紅
	var current_ratio: float = player_hp_fill.scale.x
	if ratio > current_ratio:
		var heal_tween := create_tween()
		heal_tween.tween_property(player_hp_fill, "color", Color(0.2, 0.9, 0.3), 0.1)
		heal_tween.tween_property(player_hp_fill, "color", Color(0.87, 0.12, 0.12), 0.2)
	else:
		var dmg_tween := create_tween()
		dmg_tween.tween_property(player_hp_fill, "color", Color(1.0, 0.8, 0.8), 0.1)
		dmg_tween.tween_property(player_hp_fill, "color", Color(0.87, 0.12, 0.12), 0.2)


## 回合數變更時更新 UI
func _on_turn_changed(t: int) -> void:
	turn_label.text = "Turn: %d" % t
	round_label.text = "Round: %d" % (battle_manager.current_round + 1)


## 為玩家血量標籤套用 Russo One 字型＋黑色描邊
func _style_player_hp_label() -> void:
	var font: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
	player_hp_label.add_theme_font_override("font", font)
	player_hp_label.add_theme_font_size_override("font_size", 16)
	player_hp_label.add_theme_color_override("font_color", Color.WHITE)
	player_hp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	player_hp_label.add_theme_constant_override("outline_size", 6)
	player_hp_label.add_theme_constant_override("margin_left", 8)


## 玩家戰敗
func _on_player_defeated() -> void:
	board.is_busy = true
	status_label.text = "DEFEATED..."
	status_label.modulate = Color(1, 0.3, 0.3)
	status_label.visible = true
	return_button.visible = true


## 波次轉換中：鎖定棋盤避免玩家在過場期間操作
func _on_round_transitioning() -> void:
	board.is_busy = true


## 波次清除
func _on_round_cleared() -> void:
	round_label.text = "Round: %d" % (battle_manager.current_round + 1)
	board.is_busy = false


## 戰鬥勝利
func _on_battle_won() -> void:
	board.is_busy = true
	status_label.text = "VICTORY!"
	status_label.modulate = Color(1, 0.9, 0.2)
	status_label.visible = true
	return_button.visible = true


## 重新開始戰鬥
func _on_restart_pressed() -> void:
	board.is_busy = false
	board.restart()
	status_label.visible = false
	return_button.visible = false
	battle_manager.setup(current_stage, party)
	_update_skill_ui()


## 返回地圖
func _on_return_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map.tscn")
