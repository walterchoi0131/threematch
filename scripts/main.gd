extends Node2D

const ProjectileScript := preload("res://scripts/projectile.gd")
const GemParticleScript := preload("res://scripts/gem_particle.gd")
const TrailProjectileScript := preload("res://scripts/trail_projectile.gd")
const SlashEffectScript := preload("res://scripts/slash_effect.gd")
const DamageNumberScript := preload("res://scripts/damage_number.gd")
const BulletProjectileScript := preload("res://scripts/bullet_projectile.gd")
const _BattleDialog := preload("res://scripts/battle_dialog.gd")
const _TutorialManager := preload("res://scripts/tutorial_manager.gd")
const _Stage1Tutorial := preload("res://dialogs/stage1_tutorial.gd")

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
const CHAR_PANDA := preload("res://characters/char_panda.tres")
const CHAR_POLAR := preload("res://characters/char_polar.tres")

var party: Array[CharacterData] = []
var current_stage: StageData = null
var _upper_blast_positions: Dictionary = {}  # gem_type -> Array of global positions (for upper gem VFX)
var _is_upper_gem_turn: bool = false  # set when an upper gem click is in progress
var _chain_atk_bonus: float = 0.0    # accumulated chain ATK bonus (0.10 per chain)
var _pending_saint_cross_count: int = 0  # 本次連鏈中累積的聖十字觸發次數
var _live_chain_label: Label = null       # 連鏈計數標籤 — "×N!" 動態部分
var _live_chain_header: Label = null      # 連鏈計數標籤 — "Chain" 靜態部分
var _live_chain_count: int = 0            # 目前連鏈計數（對應 upper_gem_chain_triggered 次數）

# ── 並行融合狀態 ──
var _fuse_pipeline_active: bool = false  # 融合管線正在執行中
var _concurrent_fuses: Array = []        # 並行融合資料 [{ tapped_pos, responses, arrival_msec, gem_type, count, grid_positions }]

# ── VFX 粒子池 ──
const MAX_VFX_PARTICLES := 16
var _vfx_pool: Array = []

# ── 攻擊交錯延遲（多角色連打時，下一位開始攻擊前等待的秒數）──
const ATTACK_STAGGER_SEC := 0.2

# ── 教學系統 ──
var _battle_dialog: _BattleDialog = null
var _tutorial_manager: _TutorialManager = null

# ── 戰鬥日誌 ──
const LOG_PANEL_WIDTH := 272
const LOG_ENTRY_HEIGHT := 40
const GAME_X_OFFSET := 0  # 遊戲內容向右偏移量（日誌面板已隱藏）
const GEM_ICON_PATHS := {
	Block.Type.RED: "res://assets/gems/gem_red.png",
	Block.Type.BLUE: "res://assets/gems/gem_blue.png",
	Block.Type.GREEN: "res://assets/gems/gem_green.png",
	Block.Type.LIGHT: "res://assets/gems/gem_light.png",
}
const UPPER_GEM_ICON_PATHS := {
	Block.UpperType.FIREBALL: "res://assets/gems/gem_fireball.png",
	Block.UpperType.FIRE_PILLAR_X: "res://assets/gems/gem_fire_turnado.png",
	Block.UpperType.FIRE_PILLAR_Y: "res://assets/gems/gem_fire_turnado.png",
	Block.UpperType.SAINT_CROSS: "res://assets/gems/gem_saint_cross.png",
	Block.UpperType.LEAF_SHIELD: "res://assets/gems/gem_leafshield.png",
	Block.UpperType.SNOWBALL: "res://assets/gems/gem_snowball.png",
	Block.UpperType.WATER_SLASH_X: "res://assets/gems/gem_watersword.png",
	Block.UpperType.WATER_SLASH_Y: "res://assets/gems/gem_watersword.png",
}
var _log_scroll: ScrollContainer = null
var _log_vbox: VBoxContainer = null
var _speed_label: Label = null

# ── SE ───────────────────────────────────────────────────────
var _se_blast: AudioStream = null
var _se_freeze: AudioStream = null
var _se_impact: AudioStream = null

# ── BGM 預覽模式狀態 ──
var _bgm_player: AudioStreamPlayer = null   # 背景音樂播放器引用
var _bgm_preview_tween: Tween = null         # 音量/速度 tween

# ── 戰利品 ───────────────────────────────────────────────────
var _battle_loot: Dictionary = {}  # 本場戰鬥積累的戰利品; key=ItemDefs.Type, value=int
var _battle_exp: int = 0           # 本場戰鬥積累的經驗值
var _defeat_overlay: Control = null  # 敗戰覆蓋層
var _victory_overlay: Control = null  # 勝利覆蓋層
const BGM_PREVIEW_VOLUME_DB := -5.0         # 預覽模式音量 (dB)
const BGM_PREVIEW_PITCH := 1               # 預覽模式BGM播放速度
const BGM_PREVIEW_TIME_SCALE := 0.6          # 預覽模式遊戲速度
const BGM_FADE_DUR := 0.25                   # 音量/速度漸變時間


# ── 生命週期 ───────────────────────────────────────────────────

## 初始化：設定關卡、隊伍、連接信號、初始化戰鬥系統
func _ready() -> void:
	# 從準備/對話畫面淡入
	GameState.fade_in_if_pending(0.4)

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
	board.upper_gem_chain_triggered.connect(_on_upper_gem_chain_triggered)
	board.blast_preview_entered.connect(_on_blast_preview_entered)
	board.blast_preview_exited.connect(_on_blast_preview_exited)

	battle_manager.enemy_container = enemy_container
	battle_manager.player_hp_changed.connect(_on_player_hp_changed)
	battle_manager.player_defeated.connect(_on_player_defeated)
	battle_manager.round_cleared.connect(_on_round_cleared)
	battle_manager.round_transitioning.connect(_on_round_transitioning)
	battle_manager.battle_won.connect(_on_battle_won)
	battle_manager.turn_changed.connect(_on_turn_changed)
	battle_manager.enemy_attacked.connect(_on_enemy_attacked)
	battle_manager.loot_dropped.connect(_on_loot_dropped)

	character_panel.setup(party)
	character_panel.active_skill_activated.connect(_on_active_skill_activated)
	battle_manager.setup(current_stage, party)
	status_label.visible = false
	return_button.visible = false

	_se_blast = load("res://assets/se/111.wav")
	_se_freeze = load("res://assets/se/skef_freeze.mp3")
	_se_impact = load("res://assets/se/skef_atk1_B.mp3")

	#_setup_dev_log()  # 開發日誌已隱藏
	_update_skill_ui()
	_setup_fuse_hints()
	_style_player_hp_label()
	_play_bgm()

	_play_stage_intro()


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


# ── 進場動畫 ──────────────────────────────────────────────────

## 進場動畫：黑幕淡出 → 角色卡從底部滑入 → 寶石隨機浮現
func _play_stage_intro() -> void:
	board.is_busy = true

	# 建立全螢幕黑色遮罩
	var black_overlay := ColorRect.new()
	black_overlay.color = Color.BLACK
	black_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	black_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black_overlay.z_index = 200
	fx_layer.add_child(black_overlay)

	board.hide_all_gems()

	# 等一幀讓 UI 佈局完成後再讀取卡片位置
	await get_tree().process_frame
	character_panel.prepare_intro()

	# ── 黑幕與寶石同時啟動；卡片延遲 1 秒後啟動 ──
	var fade_tw := create_tween()
	fade_tw.tween_property(black_overlay, "color:a", 0.0, 3.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	fade_tw.tween_callback(black_overlay.queue_free)

	board.play_gems_intro()  # fire-and-forget，立即開始

	# 等 0.5 秒後啟動卡片滑入
	await get_tree().create_timer(0.5).timeout
	character_panel.play_intro_slide()  # fire-and-forget

	# 再等 2.9 秒（黑幕共 3.4 秒）完成後解鎖棋盤
	await get_tree().create_timer(2.9).timeout

	# ── 教學模式 ──
	if current_stage.is_tutorial:
		_start_battle_tutorial()
	else:
		board.is_busy = false


## 啟動戰鬥教學流程
func _start_battle_tutorial() -> void:
	# 建立戰鬥對話面板（全螢幕，內含暗色覆蓋層 + 底部對話面板）
	_battle_dialog = _BattleDialog.new()
	_battle_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	$UILayer.add_child(_battle_dialog)

	# 建立教學管理器
	_tutorial_manager = _TutorialManager.new()
	add_child(_tutorial_manager)
	_tutorial_manager.setup(board, _battle_dialog)
	_tutorial_manager.tutorial_finished.connect(_on_tutorial_finished)

	var steps: Array = _Stage1Tutorial.make_steps()
	_tutorial_manager.start(steps)


## 教學完成回呼
func _on_tutorial_finished() -> void:
	board.is_busy = false
	# 隱藏教學對話面板
	if _battle_dialog != null:
		_battle_dialog.visible = false


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
		GameState.crossfade_bgm(current_stage.bgm, true, 0.6, "stage:" + current_stage.stage_name)
		_bgm_player = GameState.bgm_player


## 長按預覽開始：漸變降低 BGM 音量、播放速度、遊戲速度
func _on_blast_preview_entered() -> void:
	if _bgm_preview_tween != null and _bgm_preview_tween.is_valid():
		_bgm_preview_tween.kill()
	_bgm_preview_tween = create_tween().set_parallel(true)
	_bgm_preview_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	if _bgm_player != null and is_instance_valid(_bgm_player):
		_bgm_preview_tween.tween_property(_bgm_player, "volume_db", BGM_PREVIEW_VOLUME_DB, BGM_FADE_DUR) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		_bgm_preview_tween.tween_property(_bgm_player, "pitch_scale", BGM_PREVIEW_PITCH, BGM_FADE_DUR) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_bgm_preview_tween.tween_property(Engine, "time_scale", BGM_PREVIEW_TIME_SCALE, BGM_FADE_DUR) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## 長按預覽結束：漸變還原 BGM 音量、播放速度、遊戲速度
func _on_blast_preview_exited() -> void:
	if _bgm_preview_tween != null and _bgm_preview_tween.is_valid():
		_bgm_preview_tween.kill()
	_bgm_preview_tween = create_tween().set_parallel(true)
	_bgm_preview_tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	if _bgm_player != null and is_instance_valid(_bgm_player):
		_bgm_preview_tween.tween_property(_bgm_player, "volume_db", 0.0, BGM_FADE_DUR) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		_bgm_preview_tween.tween_property(_bgm_player, "pitch_scale", 1.0, BGM_FADE_DUR) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_bgm_preview_tween.tween_property(Engine, "time_scale", 1.0, BGM_FADE_DUR) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


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

	# 高階寶石連鏈爆炸期間跳過攻擊序列（統一在結束時計算傷害）
	if _is_upper_gem_turn:
		battle_manager.record_blast(gem_type, count, grid_positions)
		# 儲存每種寶石的爆炸位置（用於 VFX 起始點）
		if not _upper_blast_positions.has(gem_type):
			_upper_blast_positions[gem_type] = []
		_upper_blast_positions[gem_type].append_array(global_positions)
		return

	# 並行融合：融合管線執行期間的消除信號
	if _fuse_pipeline_active:
		_handle_concurrent_fuse_blast(gem_type, count, grid_positions, global_positions)
		return

	# 記錄消除資料以觸發回應技能
	battle_manager.record_blast(gem_type, count, grid_positions)

	# 先檢查回應技能以決定流程
	var responses := battle_manager.check_responding_skills(board)
	var _upper_gem_skills: Array[String] = ["Fireball", "Fire Pillar", "Justice Slash", "Leaf Shield", "Snowball", "Water Slash"]
	var is_fuse: bool = responses.size() > 0 and (responses[0].skill_name as String) in _upper_gem_skills

	if is_fuse:
		# ── 融合管線（不消耗回合）──
		await _execute_fuse_pipeline(gem_type, global_positions, responses)
		return

	# ── 普通攻擊流程（透過通用管線）──
	var blasted_dict: Dictionary = { gem_type: count }
	var blast_pos_dict: Dictionary = { gem_type: global_positions }
	await _process_blast_results(blasted_dict, blast_pos_dict)

	# 第3階段：執行非融合的回應技能（如葉風暴）
	for resp in responses:
		await _execute_responding_skill(resp)

	# 第4階段：結束回合（敵人行動 + 被動技能 + 解鎖棋盤）
	await _end_player_turn()


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


# ── 回合管線 ─────────────────────────────────────────────────────

## 融合管線：放置高階寶石（不消耗回合）
## 粒子飛向點擊位置 → 放置高階寶石 → 處理並行融合 → 掉落填充 → 清除消除資料 → 解鎖棋盤
func _execute_fuse_pipeline(gem_type: Block.Type, global_positions: Array, responses: Array) -> void:
	board.skip_collapse = true
	board.is_fusing = true
	_fuse_pipeline_active = true
	_concurrent_fuses.clear()

	var first_tapped_pos: Vector2i = board.last_tapped_pos
	var fuse_target: Vector2 = board.to_global(board.grid_to_world(first_tapped_pos))
	var color: Color = Block.COLORS[gem_type]
	var particle_duration := 1.05
	var fuse_total: int = mini(global_positions.size(), MAX_VFX_PARTICLES)
	for idx in fuse_total:
		var particle: Node2D = _acquire_particle()
		if particle == null:
			break
		var gem_pos: Vector2 = global_positions[idx]
		var spread: float = (float(idx) / max(fuse_total - 1, 1)) * 2.0 - 1.0 if fuse_total > 1 else 0.0
		particle.launch(gem_pos, fuse_target, color, particle_duration, spread)
	await get_tree().create_timer(particle_duration / TrailProjectileScript.speed_divisor + 0.05).timeout

	# 放置第一個融合的高階寶石
	board.last_tapped_pos = first_tapped_pos
	for resp in responses:
		await _execute_responding_skill(resp)

	# 處理所有並行融合（等待其粒子到達後放置高階寶石）
	while _concurrent_fuses.size() > 0:
		var cf: Dictionary = _concurrent_fuses.pop_front()
		var now := Time.get_ticks_msec()
		var arrival: int = cf.arrival_msec
		if now < arrival:
			var wait_sec: float = float(arrival - now) / 1000.0
			await get_tree().create_timer(wait_sec).timeout
		# 設定此並行融合的資料供 _execute_responding_skill 讀取
		board.last_tapped_pos = cf.tapped_pos as Vector2i
		battle_manager.turn_gem_blasts = { cf.gem_type: cf.count }
		battle_manager.last_blast_positions = cf.grid_positions as Array[Vector2i]
		for resp in cf.responses:
			await _execute_responding_skill(resp)

	_fuse_pipeline_active = false
	board.is_fusing = false

	await board.do_collapse()

	# 不消耗回合，僅清除消除資料
	battle_manager.reset_blast_data()
	_update_skill_ui()
	if not battle_manager.is_round_transitioning:
		board.is_busy = false


## 處理並行融合的 gems_blasted 信號：立即發射粒子並記錄待處理資料
func _handle_concurrent_fuse_blast(gem_type: Block.Type, count: int, grid_positions: Array[Vector2i], global_positions: Array) -> void:
	# 暫存並替換 battle_manager 狀態以檢查此次消除的回應技能
	var saved_blasts: Dictionary = battle_manager.turn_gem_blasts.duplicate()
	var saved_positions: Array[Vector2i] = battle_manager.last_blast_positions.duplicate()
	battle_manager.turn_gem_blasts = {}
	battle_manager.last_blast_positions = []
	battle_manager.record_blast(gem_type, count, grid_positions)
	var responses := battle_manager.check_responding_skills(board)
	# 還原 battle_manager 狀態
	battle_manager.turn_gem_blasts = saved_blasts
	battle_manager.last_blast_positions = saved_positions

	var _upper_gem_skills: Array[String] = ["Fireball", "Fire Pillar", "Justice Slash", "Leaf Shield", "Snowball", "Water Slash"]
	var is_fuse: bool = responses.size() > 0 and (responses[0].skill_name as String) in _upper_gem_skills
	if not is_fuse:
		return

	# 立即發射粒子（與第一次融合動畫並行）
	var tapped_pos: Vector2i = board._concurrent_fuse_tapped_pos
	board._concurrent_fuse_tapped_pos = Vector2i(-1, -1)
	var fuse_target: Vector2 = board.to_global(board.grid_to_world(tapped_pos))
	var color: Color = Block.COLORS[gem_type]
	var particle_duration := 1.05
	var fuse_total: int = mini(global_positions.size(), MAX_VFX_PARTICLES)
	for idx in fuse_total:
		var particle: Node2D = _acquire_particle()
		if particle == null:
			break
		var gem_pos: Vector2 = global_positions[idx]
		var spread: float = (float(idx) / max(fuse_total - 1, 1)) * 2.0 - 1.0 if fuse_total > 1 else 0.0
		particle.launch(gem_pos, fuse_target, color, particle_duration, spread)
	var arrival_msec: int = Time.get_ticks_msec() + int((particle_duration / TrailProjectileScript.speed_divisor + 0.05) * 1000)
	_concurrent_fuses.append({
		"tapped_pos": tapped_pos,
		"responses": responses,
		"arrival_msec": arrival_msec,
		"gem_type": gem_type,
		"count": count,
		"grid_positions": grid_positions,
	})


## 結束玩家回合管線：turn++ → 1 秒延遲 → 敵人行動 → 被動技能 → 解鎖棋盤
func _end_player_turn() -> void:
	battle_manager.finish_turn()

	# 敵人行動前 1 秒延遲
	if battle_manager.has_enemies_to_attack():
		await get_tree().create_timer(1.0).timeout

	var did_attack: bool = await battle_manager.do_enemy_phase()
	if did_attack:
		# 等待最後一個敵人投射物落地
		await get_tree().create_timer(0.5 / TrailProjectileScript.speed_divisor + 0.15).timeout

	await _process_turn_start_passives()
	_update_skill_ui()
	if not battle_manager.is_round_transitioning:
		board.is_busy = false


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

		# 無對應角色時跳過 VFX
		if attacks.is_empty():
			continue

		# 多角色共享同類寶石時，每位角色分配自己的粒子
		var per_char: int = maxi(1, chain_total / attacks.size())
		for atk_idx in attacks.size():
			var card_center: Vector2 = character_panel.get_card_screen_center(attacks[atk_idx].char_index)
			var char_particles: int = per_char if atk_idx < attacks.size() - 1 else chain_total - per_char * (attacks.size() - 1)
			for i in char_particles:
				var particle: Node2D = _acquire_particle()
				if particle == null:
					break
				var global_idx: int = per_char * atk_idx + i
				var spread: float = (float(global_idx) / max(chain_total - 1, 1)) * 2.0 - 1.0 if chain_total > 1 else 0.0
				var from_pos: Vector2 = blast_pos_list[global_idx % blast_pos_list.size()] if blast_pos_list.size() > 0 else board.global_position + Vector2(board.columns * 32, board.rows * 32)
				particle.launch(from_pos, card_center, color, particle_duration, spread)

		# 套用連鏈加成並排入攻擊佇列
		for attack in attacks:
			var chain_mult: float = 1.0 + chain_bonus
			attack.damage = int(attack.damage * chain_mult)
			attack["chain_mult"] = chain_mult
			all_attacks.append(attack)

	# 等待所有 VFX 同時飛抵目標（僅在有攻擊時等待）
	if all_attacks.size() > 0:
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
		"Leaf Shield":
			# Place a Leaf Shield upper gem at the tapped position
			var pos: Vector2i = board.last_tapped_pos
			board.place_upper_gem(pos, Block.UpperType.LEAF_SHIELD, Block.Type.GREEN)
			_play_sfx(_se_freeze)
			var _lc: CharacterData = party[resp.char_index]
			var _lc_count: int = int(battle_manager.turn_gem_blasts.get(_lc.gem_type, 0))
			_add_log_entry(_format_fuse_bbcode(_lc.gem_type, _lc_count, Block.UpperType.LEAF_SHIELD), _lc.gem_type, _lc)
			await get_tree().create_timer(0.15).timeout
		"Snowball":
			# Place a Snowball upper gem at the tapped position
			var pos: Vector2i = board.last_tapped_pos
			board.place_upper_gem(pos, Block.UpperType.SNOWBALL, Block.Type.BLUE)
			_play_sfx(_se_freeze)
			var _sc: CharacterData = party[resp.char_index]
			var _sc_count: int = int(battle_manager.turn_gem_blasts.get(_sc.gem_type, 0))
			_add_log_entry(_format_fuse_bbcode(_sc.gem_type, _sc_count, Block.UpperType.SNOWBALL), _sc.gem_type, _sc)
			await get_tree().create_timer(0.15).timeout
		"Water Slash":
			# Place a Water Slash upper gem based on blast direction (row or col)
			var pos: Vector2i = board.last_tapped_pos
			var blast_dir: String = board.get_line_direction(battle_manager.last_blast_positions)
			var slash_type: Block.UpperType
			if blast_dir == "horizontal":
				slash_type = Block.UpperType.WATER_SLASH_X
			else:
				slash_type = Block.UpperType.WATER_SLASH_Y
			board.place_upper_gem(pos, slash_type)
			_play_sfx(_se_freeze)
			var _wc: CharacterData = party[resp.char_index]
			var _wc_count: int = int(battle_manager.turn_gem_blasts.get(_wc.gem_type, 0))
			_add_log_entry(_format_fuse_bbcode(_wc.gem_type, _wc_count, slash_type), _wc.gem_type, _wc)
			await get_tree().create_timer(0.15).timeout


# ── upper gem handlers ───────────────────────────────────────────────

## 高階寶石被點擊時：設定爆炸模式
func _on_upper_gem_clicked() -> void:
	_is_upper_gem_turn = true
	_chain_atk_bonus = 0.0
	_pending_saint_cross_count = 0
	_upper_blast_positions.clear()
	_live_chain_count = 0
	if is_instance_valid(_live_chain_label):
		_live_chain_label.queue_free()
		_live_chain_label = null
	if is_instance_valid(_live_chain_header):
		_live_chain_header.queue_free()
		_live_chain_header = null


## 連鎖爆炸中波及特殊高階寶石時：即時觸發其獨有效果
func _on_upper_gem_chain_triggered(upper_type: Block.UpperType) -> void:
	_live_chain_count += 1
	if _live_chain_count >= 2:
		_update_chain_label(_live_chain_count)
	match upper_type:
		Block.UpperType.LEAF_SHIELD:
			# 葉盾：治療 Panda ATK × 5
			var panda_data: CharacterData = null
			var panda_index := -1
			for i in party.size():
				if party[i].character_name == "Panda":
					panda_data = party[i]
					panda_index = i
					break
			var heal_atk: int = panda_data.get_atk() if panda_data != null else 5
			var heal_amount: int = heal_atk * 5
			battle_manager.apply_heal(heal_amount)
			if panda_index >= 0:
				character_panel.show_heal_text(panda_index, heal_amount)
			_add_log_entry("[b]葉盾[/b] %s 回覆 %d HP" % [_gem_bbcode(Block.Type.GREEN), heal_amount], Block.Type.GREEN, panda_data)
		Block.UpperType.SAINT_CROSS:
			# 聖十字：標記需要在結算時執行聖十字效果
			_pending_saint_cross_count += 1


## 高階寶石爆炸完成後：統一結算所有累積的獨有效果 + VFX 攻擊
func _on_upper_blast_completed(chain_count: int, blasted_by_type: Dictionary, _triggered_upper: Block.UpperType) -> void:
	var chain_mult: float = 1.0 + (chain_count - 1) * 0.10
	var had_saint_cross := _pending_saint_cross_count > 0

	# ── 結算所有累積的聖十字效果 ──
	if had_saint_cross:
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
		var holy_damage := int(total_enemy_gems * 50 * base_atk * chain_mult * _pending_saint_cross_count)
		# 對所有存活敵人造成傷害
		for enemy in battle_manager.active_enemies:
			if is_instance_valid(enemy) and enemy.current_hp > 0:
				enemy.take_damage(holy_damage)
				_spawn_damage_number(enemy.get_global_rect().get_center(), holy_damage, Block.COLORS[Block.Type.LIGHT], true)
				await get_tree().create_timer(0.15).timeout
		# 回復 20% 最大血量（每個聖十字各回復一次）
		var heal_amount := int(floor(battle_manager.player_max_hp * 0.2)) * _pending_saint_cross_count
		battle_manager.apply_heal(heal_amount)
		if husky_index >= 0:
			character_panel.show_heal_text(husky_index, heal_amount)
		var cross_str := "×%d " % _pending_saint_cross_count if _pending_saint_cross_count > 1 else ""
		var chain_str := (" ×%.1f鎖" % chain_mult) if chain_count >= 2 else ""
		_add_log_entry("[b]聖十字[/b] %s%s %d × ⚔%d%s = %d 回覆%d" % [cross_str, _gem_bbcode(Block.Type.LIGHT), total_enemy_gems, base_atk, chain_str, holy_damage, heal_amount], Block.Type.LIGHT, husky_data)
		_pending_saint_cross_count = 0

	# ── 處理所有非聖十字的寶石類型：透過通用管線播放 VFX → 攻擊 ──
	var vfx_blasted: Dictionary = {}
	var vfx_positions: Dictionary = {}
	for bt in blasted_by_type:
		# 聖十字已用獨有公式處理 LIGHT 傷害，跳過避免重複
		if bt as Block.Type == Block.Type.LIGHT and had_saint_cross:
			continue
		vfx_blasted[bt] = blasted_by_type[bt]
	for bt in _upper_blast_positions:
		if bt as Block.Type == Block.Type.LIGHT and had_saint_cross:
			continue
		vfx_positions[bt] = _upper_blast_positions[bt]

	_chain_atk_bonus = (chain_count - 1) * 0.10

	if not vfx_blasted.is_empty():
		await _process_blast_results(vfx_blasted, vfx_positions, _chain_atk_bonus)

	# 連鏈標籤淡出
	if is_instance_valid(_live_chain_label):
		var fade_tw := create_tween()
		fade_tw.tween_interval(0.3)
		fade_tw.tween_property(_live_chain_label, "modulate:a", 0.0, 0.4)
		fade_tw.tween_callback(_live_chain_label.queue_free)
		_live_chain_label = null
	if is_instance_valid(_live_chain_header):
		var fade_tw2 := create_tween()
		fade_tw2.tween_interval(0.3)
		fade_tw2.tween_property(_live_chain_header, "modulate:a", 0.0, 0.4)
		fade_tw2.tween_callback(_live_chain_header.queue_free)
		_live_chain_header = null

	# 重置狀態
	_is_upper_gem_turn = false
	_chain_atk_bonus = 0.0

	await _end_player_turn()


## 建立或更新連鏈數字標籤，並播放 pop 彈跳動畫
func _update_chain_label(count: int) -> void:
	var screen_cx: float = get_viewport_rect().size.x / 2.0
	var screen_cy: float = get_viewport_rect().size.y / 2.0
	var base_font_size: int = 60
	var font_size: int = int(base_font_size * pow(1.1, count - 2))
	var base_pop_scale: float = 1.4
	var pop_scale: float = base_pop_scale * pow(1.1, count - 2)

	# "Chain" 靜態標籤 — 只建立一次
	if not is_instance_valid(_live_chain_header):
		_live_chain_header = Label.new()
		_live_chain_header.text = "Chain"
		_live_chain_header.add_theme_font_size_override("font_size", 26)
		_live_chain_header.add_theme_color_override("font_color", Color.WHITE)
		_live_chain_header.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_live_chain_header.add_theme_constant_override("outline_size", 4)
		_live_chain_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_live_chain_header.custom_minimum_size = Vector2(200, 0)
		_live_chain_header.z_index = 100
		_live_chain_header.position = Vector2(screen_cx - 100.0, screen_cy - 80.0)
		fx_layer.add_child(_live_chain_header)

	# "×N!" 動態標籤 — 只建立一次，之後只更新內容
	if not is_instance_valid(_live_chain_label):
		_live_chain_label = Label.new()
		_live_chain_label.add_theme_color_override("font_color", Color.WHITE)
		_live_chain_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_live_chain_label.add_theme_constant_override("outline_size", 8)
		_live_chain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_live_chain_label.custom_minimum_size = Vector2(200, 0)
		_live_chain_label.z_index = 100
		_live_chain_label.position = Vector2(screen_cx - 100.0, screen_cy - 50.0)
		fx_layer.add_child(_live_chain_label)

	_live_chain_label.text = "×%d!" % count
	_live_chain_label.add_theme_font_size_override("font_size", font_size)
	_live_chain_label.modulate.a = 1.0
	_live_chain_label.pivot_offset = Vector2(100.0, font_size * 0.55)
	_live_chain_label.scale = Vector2(0.5, 0.5)

	var tw := create_tween()
	tw.tween_property(_live_chain_label, "scale", Vector2(pop_scale, pop_scale), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_live_chain_label, "scale", Vector2(1.0, 1.0), 0.1).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


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
		"止水明鏡":
			# 止水明鏡：將棋盤上所有火寶石轉換為水寶石
			battle_manager.use_active_skill(char_index)
			board.convert_all_of_type(Block.Type.RED, Block.Type.BLUE)
			_add_log_entry("止水明鏡：%s→%s" % [_gem_bbcode(Block.Type.RED), _gem_bbcode(Block.Type.BLUE)], Block.Type.BLUE, c)
			await get_tree().create_timer(0.4).timeout
			_update_skill_ui()
		"龍焰領域":
			# 龍焰領域：進入火焰範圍選擇模式，點擊後將範圍內寶石轉換為火寶石
			battle_manager.use_active_skill(char_index)
			_update_skill_ui()
			board.enter_selection_mode(Block.Type.RED, "fireball")
			var positions: Array = await board.selection_confirmed
			var converted := 0
			for pos in positions:
				var p: Vector2i = pos as Vector2i
				if board.grid[p.x][p.y] != null and board.grid[p.x][p.y].block_type != Block.Type.RED:
					board._animate_gem_morph(board.grid[p.x][p.y], Block.Type.RED)
					converted += 1
			_add_log_entry("龍焰領域：%d→%s" % [converted, _gem_bbcode(Block.Type.RED)], Block.Type.RED, c)
			await get_tree().create_timer(0.4).timeout
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
			await _end_player_turn()
		"打雪仗":
			# 打雪仗：動員棋盤上所有雪球飛向目標敵人，每顆造成 ATK×10 傷害
			var snowballs: Array[Vector2i] = board.find_upper_gems(Block.UpperType.SNOWBALL)
			if snowballs.is_empty():
				return
			battle_manager.use_active_skill(char_index)
			board.is_busy = true
			var target: Enemy = battle_manager.targeted_enemy
			if target == null or not is_instance_valid(target) or target.current_hp <= 0:
				for e in battle_manager.active_enemies:
					if is_instance_valid(e) and e.current_hp > 0:
						target = e
						break
			if target == null:
				board.is_busy = false
				_update_skill_ui()
				return
			var polar_atk := c.get_atk()
			var snowball_dmg := polar_atk * 10
			var snowball_count := snowballs.size()

			# ── 第 1 階段：逐顆浮起 ──
			var float_height := 32.0  # 半格高度
			var sb_blocks: Array[Block] = []
			var sb_float_tweens: Array[Tween] = []
			for i in snowball_count:
				var sb_pos: Vector2i = snowballs[i]
				var block: Block = board.grid[sb_pos.x][sb_pos.y]
				if block == null:
					continue
				# 從棋盤網格移除但保留節點
				board.grid[sb_pos.x][sb_pos.y] = null
				# 記錄全域位置後重新掛載到 FX 層
				var gpos: Vector2 = block.global_position
				block.get_parent().remove_child(block)
				fx_layer.add_child(block)
				block.global_position = gpos
				block.z_index = 10
				sb_blocks.append(block)
				# 浮起動畫：0.7 秒向上移動 float_height
				var float_tw := create_tween()
				float_tw.tween_property(block, "global_position:y", gpos.y - float_height, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
				await float_tw.finished
				# 浮起完成後開始循環漂浮
				var bob_tw := create_tween().set_loops()
				var bob_base: float = block.global_position.y
				bob_tw.tween_property(block, "global_position:y", bob_base - 6.0, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
				bob_tw.tween_property(block, "global_position:y", bob_base + 6.0, 0.5).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
				sb_float_tweens.append(bob_tw)

			# 啟用延遲死亡
			for enemy in battle_manager.active_enemies:
				if is_instance_valid(enemy):
					enemy.defer_death = true

			# ── 第 2 階段：預計算目標，fire-and-forget 發射 ──
			var fly_duration := 0.4

			# 預計算每顆雪球的目標與傷害（依序分配存活敵人的 HP）
			var sim_hp: Dictionary = {}  # enemy -> simulated remaining HP
			for enemy in battle_manager.active_enemies:
				if is_instance_valid(enemy):
					sim_hp[enemy] = enemy.current_hp
			var sb_targets: Array[Enemy] = []
			var sb_damages: Array[int] = []
			var sb_supers: Array[bool] = []
			for i in sb_blocks.size():
				# 若目標已被模擬擊殺，切換到下一個
				if not is_instance_valid(target) or sim_hp.get(target, 0) <= 0:
					var new_target: Enemy = null
					for e in battle_manager.active_enemies:
						if is_instance_valid(e) and sim_hp.get(e, 0) > 0:
							new_target = e
							break
					if new_target != null:
						target = new_target
				var mult: float = battle_manager.get_element_multiplier(c.gem_type, target.data.element)
				var final_dmg: int = int(snowball_dmg * mult)
				sb_targets.append(target)
				sb_damages.append(final_dmg)
				sb_supers.append(mult > 1.0)
				sim_hp[target] = sim_hp.get(target, 0) - final_dmg

			# 逐顆發射（fire-and-forget，不等抵達）
			for i in sb_blocks.size():
				var block: Block = sb_blocks[i]
				if not is_instance_valid(block):
					continue
				# 停止漂浮循環
				if i < sb_float_tweens.size() and sb_float_tweens[i] != null:
					sb_float_tweens[i].kill()
				var hit_target: Enemy = sb_targets[i]
				var hit_dmg: int = sb_damages[i]
				var hit_super: bool = sb_supers[i]
				var target_pos: Vector2 = hit_target.get_global_rect().get_center() if is_instance_valid(hit_target) else board.global_position
				# 飛行動畫（fire-and-forget）
				var fly_tw := create_tween()
				fly_tw.set_parallel(true)
				fly_tw.tween_property(block, "global_position", target_pos, fly_duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				fly_tw.tween_property(block, "scale", Vector2(0.6, 0.6), fly_duration)
				fly_tw.tween_property(block, "modulate:a", 0.5, fly_duration * 0.8).set_delay(fly_duration * 0.2)
				# 抵達時造成傷害並銷毀
				fly_tw.finished.connect(func() -> void:
					if is_instance_valid(hit_target) and (hit_target.current_hp > 0 or hit_target.defer_death):
						hit_target.take_damage(hit_dmg)
						_spawn_damage_number(hit_target.get_global_rect().get_center(), hit_dmg, Block.COLORS[Block.Type.BLUE], true, hit_super)
						_play_sfx(_se_impact)
					if is_instance_valid(block):
						block.queue_free()
				)
				# 0.3 秒後發射下一顆
				if i < sb_blocks.size() - 1:
					await get_tree().create_timer(0.3).timeout

			# 等最後一顆雪球抵達
			await get_tree().create_timer(fly_duration + 0.05).timeout

			# 結算延遲死亡
			for enemy in battle_manager.active_enemies.duplicate():
				if is_instance_valid(enemy):
					enemy.defer_death = false
					if enemy.current_hp <= 0:
						enemy.finalize_death()
			_add_log_entry("[b]打雪仗[/b] %s ×%d ⚔%d = %d" % [_gem_bbcode(Block.Type.BLUE), snowball_count, snowball_dmg, snowball_dmg * snowball_count], Block.Type.BLUE, c)
			await board._collapse_and_fill()
			await _end_player_turn()


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
## 若棋盤上有葉盾，消耗一個葉盾並減少 50% 傷害
func _on_enemy_attacked(enemy: Enemy, damage: int) -> void:
	if not is_instance_valid(enemy):
		battle_manager.apply_player_damage(damage)
		return
	var from_pos: Vector2 = enemy.get_global_rect().get_center()
	var color: Color = enemy.data.portrait_color

	# ── 葉盾被動防禦：消耗一個葉盾，傷害減半 ──
	var shields: Array[Vector2i] = board.find_upper_gems(Block.UpperType.LEAF_SHIELD)
	if shields.size() > 0:
		var shield_pos: Vector2i = shields[0]
		var shield_block: Block = board.grid[shield_pos.x][shield_pos.y]
		var shield_global: Vector2 = shield_block.global_position if shield_block != null else board.to_global(board.grid_to_world(shield_pos))
		var reduced_damage: int = int(damage * 0.5)

		# 粒子飛向葉盾位置
		var trail := Node2D.new()
		trail.set_script(TrailProjectileScript)
		fx_layer.add_child(trail)
		trail.deduct_hp.connect(func() -> void:
			board.destroy_upper_gem_at(shield_pos)
			battle_manager.apply_player_damage(reduced_damage)
			_spawn_damage_number(shield_global, reduced_damage, Color(1.0, 0.3, 0.3))
			_play_sfx(_se_impact)
			# 找到 Panda 角色用於日誌
			var panda_data: CharacterData = null
			for i in party.size():
				if party[i].character_name == "Panda":
					panda_data = party[i]
					break
			_add_log_entry("[b]葉盾[/b] 擋下攻擊！%d → %d" % [damage, reduced_damage], Block.Type.GREEN, panda_data)
			# 盾牌消失後觸發棋盤掌落填充
			board._collapse_and_fill()
		, CONNECT_ONE_SHOT)
		trail.launch(from_pos, shield_global, color, 0.5)
		return

	# ── 正常流程 ──
	var to_pos: Vector2 = player_hp_fill.get_global_rect().get_center()

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
	# 交叉淡入 One More Run（存於 GameState）
	GameState.crossfade_bgm(load("res://assets/music/One More Run.mp3"), false, 0.6, "defeat")
	_bgm_player = GameState.bgm_player
	_show_defeat_overlay()


## 顯示敗戰覆蓋層
func _show_defeat_overlay() -> void:
	if _defeat_overlay != null:
		return
	var font: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
	var ui_layer: CanvasLayer = $UILayer

	_defeat_overlay = Control.new()
	_defeat_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_defeat_overlay)

	# 暗色背景（fade-in）
	var dark_bg := ColorRect.new()
	dark_bg.color = Color(0.0, 0.0, 0.0, 0.0)
	dark_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_defeat_overlay.add_child(dark_bg)
	var fade_tw := create_tween()
	fade_tw.tween_property(dark_bg, "color:a", 0.85, 0.3)

	# 中央容器
	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER)
	center.offset_left = -140.0
	center.offset_top = -80.0
	center.offset_right = 140.0
	center.offset_bottom = 80.0
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 32)
	_defeat_overlay.add_child(center)

	# "DEFEATED" 標題
	var title := Label.new()
	title.text = Locale.tr_ui("DEFEATED")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	title.add_theme_constant_override("outline_size", 4)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	center.add_child(title)

	# 按鈕列
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 24)
	center.add_child(btn_row)

	var restart_btn := Button.new()
	restart_btn.text = Locale.tr_ui("RESTART")
	restart_btn.custom_minimum_size = Vector2(130, 48)
	restart_btn.pressed.connect(_on_defeat_restart)
	btn_row.add_child(restart_btn)

	var return_btn := Button.new()
	return_btn.text = Locale.tr_ui("RETURN_MAP")
	return_btn.custom_minimum_size = Vector2(160, 48)
	return_btn.pressed.connect(_on_return_pressed)
	btn_row.add_child(return_btn)


## 敗戰後重新開始
func _on_defeat_restart() -> void:
	if _defeat_overlay != null:
		_defeat_overlay.queue_free()
		_defeat_overlay = null
	_battle_loot.clear()
	_battle_exp = 0
	board.is_busy = false
	board.restart()
	status_label.visible = false
	return_button.visible = false
	battle_manager.setup(current_stage, party)
	_update_skill_ui()


## 波次轉換中：鎖定棋盤避免玩家在過場期間操作
func _on_round_transitioning() -> void:
	board.is_busy = true


## 波次清除
func _on_round_cleared() -> void:
	round_label.text = "Round: %d" % (battle_manager.current_round + 1)
	# Round 3（0-indexed = 2）教學：敵人意圖 + 切換目標
	if current_stage.is_tutorial and battle_manager.current_round == 2 and _battle_dialog != null:
		_battle_dialog.show_lines(_Stage1Tutorial.make_round3_dialog())
		await _battle_dialog.all_lines_finished
	# 最後一波（Boss 波）：切換 BGM + 顯示 Boss 出場演出
	if battle_manager.current_round == battle_manager.stage_rounds.size() - 1:
		await _show_boss_intro()
	board.is_busy = false


## Boss 出場演出：切換 BGM 為 fez_boss 循環、顯示 Boss 名稱全螢幕遮罩、淡出後返回
func _show_boss_intro() -> void:
	# 交叉淡入 Boss BGM（循環播放，存於 GameState）
	GameState.crossfade_bgm(load("res://assets/music/fez_boss.mp3"), true, 0.8, "boss")
	_bgm_player = GameState.bgm_player

	# Boss 警告橫幅文字
	var boss_name := "BOSS INCOMING"

	var font: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
	var ui_layer: CanvasLayer = $UILayer

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = 50
	ui_layer.add_child(overlay)

	# 半透明黑色背景
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.0, 0.0, 0.0)
	overlay.add_child(bg)

	# Boss 名稱標籤
	var title_lbl := Label.new()
	title_lbl.text = boss_name
	title_lbl.add_theme_font_override("font", font)
	title_lbl.add_theme_font_size_override("font_size", 64)
	title_lbl.add_theme_color_override("font_color", Color(0.91, 0.26, 0.21))
	title_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	title_lbl.add_theme_constant_override("shadow_offset_x", 3)
	title_lbl.add_theme_constant_override("shadow_offset_y", 3)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_lbl.modulate.a = 0.0
	overlay.add_child(title_lbl)

	# Fade in
	var tw_in := create_tween().set_parallel(true)
	tw_in.tween_property(bg, "color", Color(0.0, 0.0, 0.0, 0.65), 0.4)
	tw_in.tween_property(title_lbl, "modulate:a", 1.0, 0.4)
	await tw_in.finished

	await get_tree().create_timer(1.8).timeout

	# Fade out
	var tw_out := create_tween().set_parallel(true)
	tw_out.tween_property(bg, "color", Color(0.0, 0.0, 0.0, 0.0), 0.4)
	tw_out.tween_property(title_lbl, "modulate:a", 0.0, 0.4)
	await tw_out.finished
	overlay.queue_free()


## 敵人死亡掉落戰利品：存入本場積累、更新 GameState、顯示浮動文字
func _on_loot_dropped(enemy_data: EnemyData, results: Array) -> void:
	# 累計本場經驗值
	_battle_exp += enemy_data.get_exp_drop()

	# 找出死亡的敵人節點以取得浮動文字位置（若找不到就用螢幕中央）
	var popup_pos := Vector2(get_viewport().get_visible_rect().size / 2)
	for enemy in battle_manager.active_enemies:
		if is_instance_valid(enemy) and enemy.data == enemy_data:
			popup_pos = enemy.get_global_rect().get_center()
			break

	for result: Dictionary in results:
		var type: ItemDefs.Type = result.type
		var amount: int = result.amount
		# 積累到本場計數
		var current: int = _battle_loot.get(type, 0)
		_battle_loot[type] = current + amount
		# 浮動文字
		var label_text := "+%d %s" % [amount, ItemDefs.get_display_name(type)]
		var color: Color = ItemDefs.get_color(type)
		var dn := Node2D.new()
		dn.set_script(DamageNumberScript)
		fx_layer.add_child(dn)
		dn.show_text(popup_pos, label_text, color)


## 戰鬥勝利
func _on_battle_won() -> void:
	board.is_busy = true
	# ── 最後一隻敵人死亡 → 立刻交叉淡入勝利音樂（在收尾對話之前）──
	GameState.crossfade_bgm(load("res://assets/music/fez_winfare.mp3"), false, 0.5, "winfare")
	_bgm_player = GameState.bgm_player
	# ── 教學：Boss 擊敗後收尾對話（勝利橫幅前）──
	if current_stage.is_tutorial and _battle_dialog != null:
		_battle_dialog.show_lines(_Stage1Tutorial.make_victory_dialog())
		await _battle_dialog.all_lines_finished
		_battle_dialog.visible = false

	# 將本場戰利品存入 GameState
	for type: ItemDefs.Type in _battle_loot:
		GameState.add_loot(type, _battle_loot[type])

	# 將結算資料寫入 GameState（結算場景讀取）
	GameState.last_battle_loot = _battle_loot.duplicate()
	GameState.last_battle_party = party.duplicate()
	GameState.last_battle_exp = _battle_exp

	_show_victory_overlay()


## 顯示勝利覆蓋層（5 秒後或點擊後跳轉結算場景）
func _show_victory_overlay() -> void:
	if _victory_overlay != null:
		return
	var font: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
	var ui_layer: CanvasLayer = $UILayer

	_victory_overlay = Control.new()
	_victory_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(_victory_overlay)

	# 暗色背景（fade-in）
	var dark_bg := ColorRect.new()
	dark_bg.color = Color(0.0, 0.0, 0.0, 0.0)
	dark_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_victory_overlay.add_child(dark_bg)
	var fade_tw := create_tween()
	fade_tw.tween_property(dark_bg, "color:a", 0.85, 0.3)

	# "VICTORY!" 標題（bounce 動畫）
	var title := Label.new()
	title.text = Locale.tr_ui("VICTORY")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.offset_left = -200.0
	title.offset_top = -40.0
	title.offset_right = 200.0
	title.offset_bottom = 40.0
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	title.add_theme_constant_override("outline_size", 4)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	title.pivot_offset = Vector2(200, 40)
	title.scale = Vector2(0.0, 0.0)
	_victory_overlay.add_child(title)

	# Bounce-in 動畫
	var bounce_tw := create_tween()
	bounce_tw.tween_property(title, "scale", Vector2(1.15, 1.15), 0.25) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	bounce_tw.tween_property(title, "scale", Vector2(0.95, 0.95), 0.1)
	bounce_tw.tween_property(title, "scale", Vector2(1.0, 1.0), 0.1)

	# 點擊任意處或 5 秒後跳轉結算
	var tap_btn := Button.new()
	tap_btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	tap_btn.flat = true
	tap_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	tap_btn.pressed.connect(_go_to_battle_result)
	_victory_overlay.add_child(tap_btn)

	get_tree().create_timer(5.0).timeout.connect(_go_to_battle_result)


## 跳轉至戰鬥結算場景
func _go_to_battle_result() -> void:
	if not is_inside_tree():
		return
	# 防止重複觸發
	if _victory_overlay == null:
		return
	var overlay := _victory_overlay
	_victory_overlay = null

	# 黑幕過渡
	var black := ColorRect.new()
	black.color = Color(0.0, 0.0, 0.0, 0.0)
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(black)
	var tw := create_tween()
	tw.tween_property(black, "color:a", 1.0, 0.5)
	tw.tween_callback(func() -> void:
		get_tree().change_scene_to_file("res://scenes/battle_result.tscn")
	)


## 重新開始戰鬥
func _on_restart_pressed() -> void:
	_battle_loot.clear()
	_battle_exp = 0
	board.is_busy = false
	board.restart()
	status_label.visible = false
	return_button.visible = false
	battle_manager.setup(current_stage, party)
	_update_skill_ui()


## 返回地圖
func _on_return_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map.tscn")
