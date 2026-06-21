extends Node2D

const ProjectileScript := preload("res://scripts/projectile.gd")
const GemParticleScript := preload("res://scripts/gem_particle.gd")
const TrailProjectileScript := preload("res://scripts/trail_projectile.gd")
const SlashEffectScript := preload("res://scripts/slash_effect.gd")
const LeafRayLaserVfxScript := preload("res://scripts/leaf_ray_laser_vfx.gd")
const DamageNumberScript := preload("res://scripts/damage_number.gd")
const BulletProjectileScript := preload("res://scripts/bullet_projectile.gd")
const SelectionDimOverlayScript := preload("res://scripts/selection_dim_overlay.gd")
const PuzzleGoalPulseParticlesScript := preload("res://scripts/upper_gem_pulse_particles.gd")
const PuzzleGoalRayBurstScript := preload("res://scripts/ray_burst.gd")
const GoldCoin3DProxyScript := preload("res://scripts/gold_coin_3d_proxy.gd")
const BattleVfx3DLayerScript := preload("res://scripts/battle_vfx_3d_layer.gd")
const _BattleDialog := preload("res://scripts/battle_dialog.gd")
const _TutorialManager := preload("res://scripts/tutorial_manager.gd")
const _Stage1Tutorial := preload("res://dialogs/stage1_tutorial.gd")
const _DialogLine := preload("res://scripts/dialog_line.gd")
const _DialogBoxScene := preload("res://scenes/dialog_box.tscn")
const SHIELD_ICON_TEXTURE := preload("res://assets/gems/shield.png")
const PUZZLE_KEY_HUD_BASE_TEXTURE := preload("res://assets/blocks/puzzle_key_unlocked.png")
const PUZZLE_KEY_HUD_GEM_TEXTURE := preload("res://assets/blocks/puzzle_key_gem.png")
const PUZZLE_KEY_HUD_AURA_COLOR := Color(0.18, 0.95, 0.86, 0.62)
const GOLD_COIN_VIEWPORT_SIZE := 72
const GOLD_COIN_FLOOR_DROP := Vector2(0.0, 46.0)
const GOLD_COIN_DROP_DURATION := 0.34
const GOLD_COIN_SPIN_HOLD_DURATION := 0.5
const GOLD_COIN_FLY_DURATION := 0.728
const GOLD_COIN_FADE_DURATION := 0.18
const LOOT_FLY_ICON_SIZE := 52
const LOOT_TOAST_SIZE := Vector2(184.0, 64.0)
const LOOT_TOAST_GAP := 8.0
const LOOT_TOAST_ICON_SIZE := 56
const LOOT_TOAST_RIGHT_MARGIN := 16.0
const LOOT_TOAST_TOP_OFFSET := 48.0
const LOOT_TOAST_SLIDE_IN_DURATION := 0.18
const LOOT_TOAST_HOLD_DURATION := 1.15
const LOOT_TOAST_SLIDE_OUT_DURATION := 0.28

signal loot_animations_finished()
signal loot_flights_finished()

# ── scene references ──────────────────────────────────────────────────
@onready var board = $Board
@onready var battle_manager: BattleManager = $BattleManager
@onready var fx_layer: CanvasLayer = $FXLayer
@onready var score_label: Label = $UILayer/TopBar/ScoreLabel
@onready var turn_label: Label = $UILayer/TopBar/TurnLabel
@onready var round_label: Label = $UILayer/TopBar/RoundLabel
@onready var player_hp_label: Label = $UILayer/PlayerHPBar/HpLabel
@onready var player_hp_fill: ColorRect = $UILayer/PlayerHPBar/Fill
@onready var enemy_container: HBoxContainer = $UILayer/EnemyRow
@onready var character_panel: HBoxContainer = $UILayer/CharacterRow
@onready var gem_meter: GemMeter = $UILayer/GemMeter
@onready var status_label: Label = $UILayer/StatusLabel
@onready var return_button: Button = $UILayer/ReturnButton
@onready var _battle_bg_rect: TextureRect = $BattleBackground
@onready var _escape_refill_label: Label = $UILayer/EscapeRefillLabel
var _player_hp_gradient_fill: TextureRect = null

# ── 逃脫模式狀態 ─────────────────────────────────────────────
var _escape_mode: bool = false
var _escape_distance_target: int = 0
var _escape_distance_traveled: int = 0
var _escape_distance_remaining: int = 0
var _escape_distance_displayed: int = 0
var _escape_won: bool = false
var _escape_goal_wood_row: int = -1
var _escape_distance_number_label: Label = null
var _escape_distance_unit_label: Label = null
var _escape_distance_tween: Tween = null
var _stage14_escape_intro_done: bool = false
var _escape_failed: bool = false

# ── Puzzle 模式狀態 ───────────────────────────────────────────
var _puzzle_mode: bool = false
var _puzzle_goal_required: int = 0
var _puzzle_goal_progress: int = 0
var _puzzle_goal_remaining: int = 0
var _puzzle_goal_displayed: int = 0
var _puzzle_goal_completed: bool = false
var _puzzle_goal_panel: PanelContainer = null
var _puzzle_goal_icon_slot: Control = null
var _puzzle_goal_icon: TextureRect = null
var _puzzle_goal_icon_gem: TextureRect = null
var _puzzle_goal_icon_ray: Node2D = null
var _puzzle_goal_icon_fx: Node2D = null
var _puzzle_goal_prefix_label: Label = null
var _puzzle_goal_number_label: Label = null
var _puzzle_goal_target_label: Label = null
var _puzzle_goal_tween: Tween = null
var _puzzle_turn_limit: int = 0
var _puzzle_turns_left: int = 0
var _puzzle_turns_displayed: int = 0
var _puzzle_turn_limit_failed: bool = false
var _puzzle_turn_prefix_label: Label = null
var _puzzle_turn_number_label: Label = null
var _puzzle_turn_suffix_label: Label = null
var _puzzle_turn_tween: Tween = null
var _puzzle_turn_warning_tween: Tween = null

# ── Stage 1-5 急難奇蹟事件 ─────────────────────────────────
var _plank_event_pending: bool = false
var _plank_event_done: bool = false
var _plank_event_deferred_check_running: bool = false
const ESCAPE_METERS_PER_ROW := 10
const ESCAPE_SCROLL_RESET_ROW := 1
const _PLANK_EVENT_DISTANCE := 200
const _Stage1_4Emergency := preload("res://dialogs/stage1_4_emergency.gd")
const _Stage1_3Owen := preload("res://dialogs/stage1_3_owen.gd")
const OWEN_STORY_STAGE_ID := "1-4"
const ESCAPE_PLANK_STAGE_ID := "1-5"

## 主動技能完整執行完成信號（供外部事件 await 完成狀態使用）
signal active_skill_finished(char_index: int)

# ── game data ─────────────────────────────────────────────────────────
const CHAR_BOAR := preload("res://characters/char_boar.tres")
const CHAR_RACCOON := preload("res://characters/char_raccoon.tres")
const CHAR_PANDA := preload("res://characters/char_panda.tres")
const CHAR_FOX := preload("res://characters/char_fox.tres")
const CHAR_HUSKY := preload("res://characters/char_husky.tres")
const CHAR_POLAR := preload("res://characters/char_polar.tres")
const CHAR_POLARZ := preload("res://characters/char_polarz.tres")
const CHAR_DRAGON := preload("res://characters/char_dragon.tres")
const CHAR_SHARK := preload("res://characters/char_shark.tres")
const CHAR_GORY := preload("res://characters/char_gory.tres")
const UPPER_GEM_SKILLS: Array[String] = ["Fireball", "Fire Pillar", "Justice Slash", "Leaf Shield", "Snowball", "Iceball", "Water Slash", "Porcupine", "Turtle", "Bamboo Supply", "Wood Spear", "光之盾", "Leaf Ray"]
const ICEBALL_MAGIC_MULT := 10
const ICEBALL_DEBRIS_SHARDS := 7
const LEAF_RAY_MAGIC_MULT := 3.5
const LEAF_RAY_LASER_DURATION := 1.0
const LEAF_RAY_DAMAGE_TICK_INTERVAL := 0.2
const LEAF_RAY_DEBRIS_SHARDS := 9
const COMBO_UI_MARGIN := Vector2(28.0, 92.0)
const COMBO_UI_SLOT_GAP := 142.0
const COMBO_UI_VALUE_OFFSET_Y := 20.0
const COMBO_UI_MIN_TOP_GAP := 46.0
const SPELL_CHAIN_WAVE_AMPLITUDE := 8.0
const SPELL_CHAIN_WAVE_PERIOD := 0.62

var party: Array[CharacterData] = []
var _guest_result_exclusions: Dictionary = {}
var current_stage: StageData = null
var _stage13_result_party: Array[CharacterData] = []
var _stage13_event_running: bool = false
var _stage13_turn1_done: bool = false
var _stage13_rescue_done: bool = false
var _stage13_join_turn: int = -1
var _stage13_light_hint_done: bool = false
var _stage13_husky_active_used: bool = false
var _stage13_owen_light_hit_pending: bool = false
var _stage13_floor_finale_scheduled: bool = false
var _stage13_victory_triggered: bool = false
var _temporary_active_unlocks: Dictionary = {}
var _upper_blast_positions: Dictionary = {}  # gem_type -> Array of global positions (for upper gem VFX)
var _is_upper_gem_turn: bool = false  # set when an upper gem click is in progress
var _chain_atk_bonus: float = 0.0    # accumulated chain ATK bonus (0.10 per chain)
var _pending_saint_cross_count: int = 0  # 本次連鏈中累積的聖十字觸發次數
var _live_chain_label: Label = null       # 連鏈計數標籤 — "×N!" 動態部分
var _live_chain_header: Label = null      # 連鏈計數標籤 — "Chain" 靜態部分
var _live_chain_count: int = 0            # 目前連鏈計數（對應 upper_gem_chain_triggered 次數）
var _spell_chain_label: Control = null    # 法術連撃計數標籤 — "×N!" 動態部分
var _spell_chain_header: Label = null     # 法術連撃計數標籤 — 靜態部分
var _spell_chain_count: int = 0           # 目前 INSTANT 融合連擊數
var _active_board_selection_running: bool = false
var _active_board_selection_char_index: int = -1
const ACTIVE_SELECTION_DIM_LAYER := 90
const ACTIVE_SELECTION_DIM_ALPHA := 0.62
const ACTIVE_SELECTION_DIM_FADE := 0.16
var _active_selection_dim_layer: CanvasLayer = null
var _active_selection_dim_overlay: Control = null
var _active_selection_dim_tween: Tween = null
var _active_selection_preview_positions: Array[Vector2i] = []
var _stage_intro_gems_ready: bool = false
var _initial_boss_intro_shown: bool = false
var _player_shield_overlay: ColorRect = null
var _player_shield_badge: Control = null
var _player_shield_icon: TextureRect = null
var _player_shield_label: Label = null
var _player_shield_tween: Tween = null
var _player_shield_badge_tween: Tween = null
var _enemy_board_effects_pending: int = 0
var _auto_enemy_active_cds: Dictionary = {}
var _battle_shake_tween: Tween = null
var _round_walk_tween: Tween = null
var _battle_shake_original_positions: Dictionary = {}

# ── 並行融合狀態 ──
var _fuse_pipeline_active: bool = false  # 融合管線正在執行中
var _instant_fuse_pipeline_active: bool = false
var _concurrent_fuses: Array = []        # 並行融合資料 [{ tapped_pos, responses, arrival_msec, gem_type, count, grid_positions }]
var _active_instant_upper_tasks: Array[Dictionary] = []
var _pending_instant_upper_tasks: Array[Dictionary] = []
var _reserved_instant_upper_tasks: Array[Dictionary] = []
var _instant_upper_resolvers: Dictionary = {}
var _instant_upper_predictors: Dictionary = {}
var _instant_upper_effect_worker_running: bool = false
var _next_instant_upper_follow_trail: Node2D = null
const INSTANT_UPPER_TRANSFER_METHOD_FLY := 0
const INSTANT_UPPER_TRANSFER_METHOD_VOID := 1
const INSTANT_UPPER_TRANSFER_METHOD := INSTANT_UPPER_TRANSFER_METHOD_FLY
const INSTANT_UPPER_ORBIT_FLY_DURATION := 0.6
const INSTANT_UPPER_VOID_SHRINK_DURATION := 0.7
const INSTANT_UPPER_VOID_APPEAR_DURATION := 0.22
const INSTANT_UPPER_ORBIT_RADIUS := 36.0
const INSTANT_UPPER_ORBIT_PERIOD := 1.05
const INSTANT_UPPER_ORBIT_SCALE := Vector2.ONE
const INSTANT_UPPER_TRAIL_OFFSET := Vector2(0.0, 18.0)
const INSTANT_UPPER_ORBIT_TILT := -0.52
const INSTANT_UPPER_ORBIT_Y_SCALE := 0.42
const INSTANT_UPPER_ORBIT_SPEED_STEP := 0.22
const INSTANT_UPPER_ORBIT_MIN_PERIOD := 0.42

# ── 攻擊管線佇列（State/UI 分離：blast 動畫與角色攻擊解耦）──
# 每個 item: { gem_type, count, global_positions, grid_positions, responses }
var _attack_queue: Array = []
var _attack_worker_running: bool = false

# ── VFX 粒子池 ──
const MAX_VFX_PARTICLES := 16
const TRANSMUTE_TRAILS_PER_CELL := 8
const TRANSMUTE_TRAIL_POOL_SIZE := 128
var _vfx_pool: Array = []

# ── 攻擊交錯延遲（多角色連打時，下一位開始攻擊前等待的秒數）──
const ATTACK_STAGGER_SEC := 0.2

# ── 教學系統 ──
var _battle_dialog: _BattleDialog = null
var _tutorial_manager: _TutorialManager = null
var _enemy_popup_layer: CanvasLayer = null

# ── 戰鬥日誌 ──
const LOG_PANEL_WIDTH := 272
const LOG_ENTRY_HEIGHT := 40
const GAME_X_OFFSET := 0  # 遊戲內容向右偏移量（日誌面板已隱藏）
const GEM_ICON_PATHS := {
	Block.Type.RED: "res://assets/gems/gem_red.png",
	Block.Type.BLUE: "res://assets/gems/gem_blue.png",
	Block.Type.GREEN: "res://assets/gems/gem_leaf3.png",
	Block.Type.LIGHT: "res://assets/gems/gem_light.png",
	Block.Type.DARK: "res://assets/gems/gem_moon.png",
}
const UPPER_GEM_ICON_PATHS := {
	Block.UpperType.FIREBALL: "res://assets/gems/gem_fireball.png",
	Block.UpperType.FIRE_PILLAR_X: "res://assets/gems/gem_fire_turnado.png",
	Block.UpperType.FIRE_PILLAR_Y: "res://assets/gems/gem_fire_turnado.png",
	Block.UpperType.SAINT_CROSS: "res://assets/gems/gem_saint_cross.png",
	Block.UpperType.LEAF_SHIELD: "res://assets/gems/gem_leafshield.png",
	Block.UpperType.SNOWBALL: "res://assets/gems/gem_snowball.png",
	Block.UpperType.ICEBALL: "res://assets/gems/gem_iceball.png",
	Block.UpperType.WATER_SLASH: "res://assets/gems/gem_shark.png",
	Block.UpperType.BAMBOO_SUPPLY: "res://assets/gems/gem_bamboo.png",
	Block.UpperType.WOOD_SPEAR_UP: "res://assets/gems/gem_wood_spear.png",
	Block.UpperType.WOOD_SPEAR_DOWN: "res://assets/gems/gem_wood_spear.png",
	Block.UpperType.LIGHT_SHIELD: "res://assets/gems/gem_light_shield.png",
	Block.UpperType.LEAF_RAY: "res://assets/gems/gem_leaf_ray.png",
}
var _log_scroll: ScrollContainer = null
var _log_vbox: VBoxContainer = null
var _speed_label: Label = null

# ── SE ───────────────────────────────────────────────────────
var _se_blast: AudioStream = null
var _se_freeze: AudioStream = null
var _se_impact: AudioStream = null
var _se_join_team: AudioStream = null
var _se_thor_active: AudioStream = null
var _se_goal_achieve: AudioStream = null
var _se_water_bubble: AudioStream = null
var _se_solar_beam_shining: AudioStream = null
var _se_stone_impacts: Array[AudioStream] = []

# ── BGM 預覽模式狀態 ──
var _bgm_player: AudioStreamPlayer = null   # 背景音樂播放器引用
var _bgm_preview_tween: Tween = null         # 音量/速度 tween

# ── 戰利品 ───────────────────────────────────────────────────
var _battle_loot: Dictionary = {}  # 本場戰鬥積累的戰利品; key=ItemDefs.Type, value=int
var _battle_exp: int = 0           # 本場戰鬥積累的經驗值
var _loot_toast_totals: Dictionary = {}
var _active_loot_animation_count: int = 0
var _active_loot_flight_count: int = 0
var _active_loot_toasts: Array[Dictionary] = []
var _loot_toast_queue: Array[Dictionary] = []
var _loot_toast_starting: bool = false
var _battle_vfx_3d_layer: BattleVfx3DLayer = null
var _defeat_overlay: Control = null  # 敗戰覆蓋層
var _victory_overlay: Control = null  # 勝利覆蓋層
const BGM_PREVIEW_VOLUME_DB := -5.0         # 預覽模式音量 (dB)
const BGM_PREVIEW_PITCH := 1               # 預覽模式BGM播放速度
const BGM_PREVIEW_TIME_SCALE := 0.6          # 預覽模式遊戲速度
const BGM_FADE_DUR := 0.25                   # 音量/速度漸變時間
const STAGE_EDITOR_GEM_TYPES: Array[int] = [
	Block.Type.RED,
	Block.Type.BLUE,
	Block.Type.GREEN,
	Block.Type.LIGHT,
	Block.Type.DARK,
	Block.Type.PLANK,
	Block.Type.ROCK,
	Block.Type.WOOD_STRUCTURE,
	Block.Type.PUZZLE_KEY,
	StageData.CELL_WATER_SWORD,
	StageData.CELL_HOLE,
]
const STAGE_EDITOR_DISTRIBUTION_TYPES: Array[int] = [
	Block.Type.RED,
	Block.Type.BLUE,
	Block.Type.GREEN,
	Block.Type.LIGHT,
	Block.Type.DARK,
]
const STAGE_EDITOR_GOAL_TARGET_TYPES: Array[int] = [
	Block.Type.RED,
	Block.Type.BLUE,
	Block.Type.GREEN,
	Block.Type.LIGHT,
	Block.Type.DARK,
	Block.Type.PLANK,
	Block.Type.PUZZLE_KEY,
]
const STAGE_EDITOR_ENEMY_ROOT := "res://enemies"
const STAGE_EDITOR_GENERATED_MANIFEST := "res://assets/enemy/generated/enemy_manifest.json"
const STAGE_EDITOR_DIALOG_BACKGROUND_ROOT := "res://assets/dialog_background"
const STAGE_EDITOR_DIALOG_MUSIC_ROOT := "res://assets/music"
const STAGE_EDITOR_TAB_BEFORE := "before"
const STAGE_EDITOR_TAB_BOARD := "board"
const STAGE_EDITOR_TAB_AFTER := "after"

var _stage_editor_panel: PanelContainer = null
var _stage_editor_root_box: VBoxContainer = null
var _stage_editor_area_panel: PanelContainer = null
var _stage_editor_tab_panel: PanelContainer = null
var _stage_editor_dialog_panel: PanelContainer = null
var _stage_editor_palette_scroll: ScrollContainer = null
var _stage_editor_palette_grid: GridContainer = null
var _stage_editor_value_buttons: Dictionary = {}
var _stage_editor_tab_buttons: Dictionary = {}
var _stage_editor_mode_buttons: Dictionary = {}
var _stage_editor_current_tab: String = STAGE_EDITOR_TAB_BOARD
var _stage_editor_selected_value: int = Block.Type.RED
var _stage_editor_selected_area: String = StageData.DEFAULT_AREA
var _stage_editor_area_option: OptionButton = null
var _stage_editor_bg_override_option: OptionButton = null
var _stage_editor_music_override_option: OptionButton = null
var _stage_editor_boss_bgm_option: OptionButton = null
var _stage_editor_stretch_bg_check: CheckButton = null
var _stage_editor_area_spot_preview: TextureRect = null
var _stage_editor_distribution_spins: Dictionary = {}
var _stage_editor_drop_start_spins: Dictionary = {}
var _stage_editor_reward_item_option: OptionButton = null
var _stage_editor_reward_amount_edit: LineEdit = null
var _stage_editor_reward_character_option: OptionButton = null
var _stage_editor_dialog_target: String = ""
var _stage_editor_dialog_title_label: Label = null
var _stage_editor_dialog_line_list: VBoxContainer = null
var _stage_editor_dialog_cast_list: HBoxContainer = null
var _stage_editor_dialog_add_cast_option: OptionButton = null
var _stage_editor_dialog_background_option: OptionButton = null
var _stage_editor_dialog_music_option: OptionButton = null
var _stage_editor_dialog_exit_cast_option: OptionButton = null
var _stage_editor_dialog_exit_side_option: CheckButton = null
var _stage_editor_dialog_selected_index: int = -1
var _stage_editor_dialog_character_edit: LineEdit = null
var _stage_editor_dialog_emotion_edit: LineEdit = null
var _stage_editor_dialog_position_option: OptionButton = null
var _stage_editor_dialog_action_option: OptionButton = null
var _stage_editor_dialog_shake_check: CheckBox = null
var _stage_editor_dialog_text_zh_edit: TextEdit = null
var _stage_editor_dialog_text_en_edit: TextEdit = null
var _stage_editor_dialog_refreshing: bool = false
var _stage_editor_character_catalog: Array[Dictionary] = []
var _stage_editor_character_by_id: Dictionary = {}
var _stage_editor_dialog_background_catalog: Array[Dictionary] = []
var _stage_editor_dialog_music_catalog: Array[Dictionary] = []
var _stage_editor_test_dialog: Control = null
var _stage_editor_enemy_area_panel: Control = null
var _stage_editor_prev_round_button: Button = null
var _stage_editor_next_round_button: Button = null
var _stage_editor_add_round_button: Button = null
var _stage_editor_remove_round_button: Button = null
var _stage_editor_enemy_area_round_label: Label = null
var _stage_editor_enemy_area_slots: Control = null
var _stage_editor_goal_target_option: OptionButton = null
var _stage_editor_goal_count_spin: SpinBox = null
var _stage_editor_goal_turn_spin: SpinBox = null
var _stage_editor_current_round_index: int = 0
var _stage_editor_rounds_container: VBoxContainer = null
var _stage_editor_rounds_list: VBoxContainer = null
var _stage_editor_rounds_expanded: bool = true
var _stage_editor_enemy_picker_panel: PanelContainer = null
var _stage_editor_enemy_picker_grid: GridContainer = null
var _stage_editor_enemy_picker_round_index: int = -1
var _stage_editor_enemy_picker_level_spin: SpinBox = null
var _stage_editor_rounds: Array[Array] = []
var _stage_editor_rounds_init_cd: Array[Array] = []
var _stage_editor_rounds_enemy_levels: Array[Array] = []
var _stage_editor_rounds_main_bosses: Array[Array] = []
var _stage_editor_available_enemies: Array[Dictionary] = []


func _is_stage13_story_battle() -> bool:
	return current_stage != null and current_stage.stage_id == OWEN_STORY_STAGE_ID


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
		var last: Array[CharacterData] = GameState.get_last_used_party()
		if last.size() > 0:
			party = last
		else:
			party = [CHAR_DRAGON, CHAR_SHARK, CHAR_PANDA, CHAR_HUSKY]
	if _is_stage13_story_battle():
		_stage13_result_party = party.duplicate()
		party = [CHAR_HUSKY]
		_guest_result_exclusions[CHAR_HUSKY] = true

	if GameState.stage_edit_mode:
		call_deferred("_setup_stage_edit_mode")
		return

	board.gems_blasted.connect(_on_gems_blasted)
	board.score_changed.connect(_on_score_changed)
	board.upper_gem_clicked.connect(_on_upper_gem_clicked)
	board.upper_blast_completed.connect(_on_upper_blast_completed)
	board.upper_gem_chain_triggered.connect(_on_upper_gem_chain_triggered)
	board.selection_preview_changed.connect(_on_board_selection_preview_changed)
	board.blast_preview_entered.connect(_on_blast_preview_entered)
	board.blast_preview_exited.connect(_on_blast_preview_exited)
	board.enemy_break_pulse.connect(_on_enemy_break_pulse)
	board.gems_refilled.connect(_on_gems_refilled)
	board.escape_marker_moved.connect(_on_escape_marker_moved)
	board.goal_cells_broken.connect(_on_goal_cells_broken)
	# 燃燒數到定時：在每次實際點擊拆除回合有新寶石生成前由連鎖回呼觸發
	board.pre_refill_hook = func() -> void:
		if board._blast_refill_armed:
			board._blast_refill_armed = false
			await _apply_burning_tick()
	# State/UI 分離：board 需引用 battle_manager 以查詢邏輯狀態
	board.battle_manager_ref = battle_manager
	board.fuse_preflight_handler = Callable(self, "_can_accept_concurrent_fuse")

	battle_manager.enemy_container = enemy_container
	battle_manager.auto_enemy_action_handler = Callable(self, "_handle_auto_enemy_action")
	battle_manager.round_transition_wait_handler = Callable(self, "_wait_for_loot_flights_finished")
	_register_instant_upper_resolvers()
	battle_manager.player_hp_changed.connect(_on_player_hp_changed)
	battle_manager.player_shield_changed.connect(_on_player_shield_changed)
	battle_manager.player_defeated.connect(_on_player_defeated)
	battle_manager.round_cleared.connect(_on_round_cleared)
	battle_manager.round_transitioning.connect(_on_round_transitioning)
	battle_manager.battle_won.connect(_on_battle_won)
	battle_manager.turn_changed.connect(_on_turn_changed)
	battle_manager.enemy_attacked.connect(_on_enemy_attacked)
	battle_manager.enemy_lightbreak_attacked.connect(_on_enemy_lightbreak_attacked)
	battle_manager.enemy_stone_magic_cast.connect(_on_enemy_stone_magic_cast)
	battle_manager.enemy_long_pressed.connect(_on_enemy_long_pressed)
	battle_manager.loot_dropped.connect(_on_loot_dropped)
	battle_manager.round_spawned.connect(_on_round_spawned)
	battle_manager.turn_gem_blasts_changed.connect(_refresh_gem_meter)

	character_panel.setup(party)
	character_panel.active_skill_activated.connect(_on_active_skill_activated)
	character_panel.active_skill_selection_cancelled.connect(_on_active_skill_selection_cancelled)
	_setup_boss_bar()
	_setup_player_shield_ui()
	battle_manager.setup(current_stage, party)
	status_label.visible = false
	return_button.text = Locale.tr_ui("EXIT")
	return_button.visible = true
	_setup_kill_all_button()
	_setup_escape_hud()
	_setup_puzzle_goal_hud()
	_prewarm_trail_projectile_pool(TRANSMUTE_TRAIL_POOL_SIZE)

	_se_blast = _load_audio_stream("res://assets/se/111.wav")
	_se_freeze = _load_audio_stream("res://assets/se/skef_freeze.mp3")
	_se_impact = _load_audio_stream("res://assets/se/skef_atk1_B.mp3")
	_se_join_team = _load_audio_stream("res://assets/se/join_team2.mp3")
	_se_thor_active = _load_audio_stream("res://assets/se/magical_star_transmu.mp3")
	_se_goal_achieve = _load_audio_stream("res://assets/se/goal_achieve.mp3")
	_se_water_bubble = _load_audio_stream("res://assets/se/water_bubble.mp3")
	_se_solar_beam_shining = _load_audio_stream("res://assets/se/solar_beam_shining.mp3")
	_se_stone_impacts = [
		_load_audio_stream("res://assets/se/stone1.mp3"),
		_load_audio_stream("res://assets/se/stone2.mp3"),
	]

	#_setup_dev_log()  # 開發日誌已隱藏
	_update_skill_ui()
	_setup_fuse_hints()
	_style_player_hp_label()
	_style_player_hp_bar()
	_play_bgm()

	_apply_stage_background()
	_layout_board()
	ViewportUtils.viewport_changed.connect(_on_viewport_changed)
	_apply_safe_area()

	_play_stage_intro()


## 套用關卡地區背景圖片。
func _apply_stage_background() -> void:
	if current_stage == null:
		_battle_bg_rect.visible = false
		return
	var override_path: String = current_stage.battle_background_override_path.strip_edges()
	var path: String = override_path if not override_path.is_empty() else StageData.get_battle_background_path(current_stage.area)
	if not override_path.is_empty() and not ResourceLoader.exists(path):
		path = StageData.get_battle_background_path(current_stage.area)
	if path.is_empty():
		_battle_bg_rect.visible = false
		return
	var texture: Texture2D = load(path) as Texture2D
	if texture == null:
		_battle_bg_rect.visible = false
		return
	_battle_bg_rect.texture = texture
	_battle_bg_rect.visible = true


## 依當前 viewport 大小縮放與置中棋盤。
func _layout_board() -> void:
	var vp: Vector2 = ViewportUtils.get_size()
	var board_columns: int = current_stage.columns if current_stage != null else 8
	var board_w: float = float(board_columns) * 64.0
	# 棋盤左右各保留 16px 邊距；最多放大到讓棋盤填滿可用寬度
	var max_w: float = vp.x - 32.0
	var s: float = max(0.1, max_w / board_w)
	board.scale = Vector2(s, s)
	board.position = Vector2((vp.x - board_w * s) * 0.5, vp.y * 0.22)
	_battle_bg_rect.position = Vector2(0.0, 0.0)
	if current_stage != null and current_stage.stretch_battle_background:
		_battle_bg_rect.size = vp
	else:
		var battle_bg_height: float = maxf(board.position.y + 16.0, vp.y * 0.34)
		_battle_bg_rect.size = Vector2(vp.x, battle_bg_height)


## Viewport 改變時重排棋盤與 UI。
func _on_viewport_changed(_size: Vector2) -> void:
	_layout_board()
	_apply_safe_area()
	if battle_manager != null and battle_manager.player_shield > 0:
		_update_player_shield_layout()
	_refresh_active_selection_dim_holes()
	_layout_stage_editor_enemy_area()
	_layout_stage_editor_ui()
	_layout_stage_editor_enemy_picker_panel()
	_position_combo_ui()


func _get_combo_ui_origin() -> Vector2:
	var bg_left: float = _battle_bg_rect.position.x if is_instance_valid(_battle_bg_rect) else 0.0
	var bg_top: float = _battle_bg_rect.position.y if is_instance_valid(_battle_bg_rect) else 0.0
	var bg_bottom: float = board.position.y
	var y: float = maxf(bg_top + COMBO_UI_MIN_TOP_GAP, bg_bottom - COMBO_UI_MARGIN.y)
	return Vector2(bg_left + COMBO_UI_MARGIN.x, y)


func _position_combo_pair(header: Control, value: Control, origin: Vector2) -> void:
	if is_instance_valid(header):
		header.position = origin
	if is_instance_valid(value):
		value.position = origin + Vector2(0.0, COMBO_UI_VALUE_OFFSET_Y)


func _position_combo_ui() -> void:
	var origin: Vector2 = _get_combo_ui_origin()
	var has_normal: bool = is_instance_valid(_live_chain_header) or is_instance_valid(_live_chain_label)
	var has_spell: bool = is_instance_valid(_spell_chain_header) or is_instance_valid(_spell_chain_label)
	_position_combo_pair(_live_chain_header, _live_chain_label, origin)
	var spell_origin: Vector2 = origin
	if has_normal and has_spell:
		spell_origin.x += COMBO_UI_SLOT_GAP
	_position_combo_pair(_spell_chain_header, _spell_chain_label, spell_origin)
	if _escape_mode:
		_position_escape_distance_label()



func _apply_safe_area() -> void:
	var insets: Vector4 = ViewportUtils.get_safe_insets()
	var top_inset: float = insets.x
	var bottom_inset: float = insets.z
	var top_bar: Control = $UILayer/TopBar
	if top_bar:
		top_bar.offset_top = top_inset
		top_bar.offset_bottom = top_inset + 40.0
	var char_row: Control = character_panel
	if char_row:
		char_row.offset_top = -200.0 - bottom_inset
		char_row.offset_bottom = -140.0 - bottom_inset
		character_panel.refresh_slot_sizes()
	var hp_bar: Control = $UILayer/PlayerHPBar
	if hp_bar:
		hp_bar.offset_top = -234.0 - bottom_inset
		hp_bar.offset_bottom = -210.0 - bottom_inset
	var restart_btn: Control = $UILayer/RestartButton
	if restart_btn:
		restart_btn.offset_top = -96.0 - bottom_inset
		restart_btn.offset_bottom = -56.0 - bottom_inset
	var ret_btn: Control = $UILayer/ReturnButton
	if ret_btn:
		ret_btn.offset_top = -96.0 - bottom_inset
		ret_btn.offset_bottom = -56.0 - bottom_inset


func _setup_stage_edit_mode() -> void:
	_hide_battle_ui_for_stage_editor()
	board.set_edit_mode(true)
	board.set_edit_paint_value(_stage_editor_selected_value)
	_stage_editor_load_area_state()
	_stage_editor_load_round_state()
	_apply_stage_background()
	_layout_board()
	if not ViewportUtils.viewport_changed.is_connected(_on_viewport_changed):
		ViewportUtils.viewport_changed.connect(_on_viewport_changed)
	_apply_safe_area()
	_build_stage_editor_enemy_area()
	_build_stage_editor_ui()
	_stage_editor_select_tab(STAGE_EDITOR_TAB_BOARD)
	_set_stage_editor_status("Ready")


func _hide_battle_ui_for_stage_editor() -> void:
	var top_bar: Control = $UILayer/TopBar
	top_bar.visible = false
	var hp_bar: Control = $UILayer/PlayerHPBar
	hp_bar.visible = false
	enemy_container.visible = false
	character_panel.visible = false
	gem_meter.visible = false
	status_label.visible = false
	return_button.visible = false
	_escape_refill_label.visible = false
	var restart_button: Button = $UILayer/RestartButton
	restart_button.visible = false
	board.battle_manager_ref = null


func _build_stage_editor_ui() -> void:
	_stage_editor_load_character_catalog()
	_stage_editor_load_dialog_background_catalog()
	_stage_editor_load_dialog_music_catalog()
	_build_stage_editor_area_panel()
	_build_stage_editor_tab_panel()
	_build_stage_editor_dialog_panel()
	if _stage_editor_panel != null:
		return
	_stage_editor_panel = PanelContainer.new()
	_stage_editor_panel.name = "StageEditorToolbar"
	_stage_editor_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.12, 0.94)
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_color = Color(0.42, 0.52, 0.72, 0.9)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	_stage_editor_panel.add_theme_stylebox_override("panel", panel_style)
	$UILayer.add_child(_stage_editor_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_stage_editor_panel.add_child(margin)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 0)
	margin.add_child(root_box)
	_stage_editor_root_box = root_box

	var palette_scroll := ScrollContainer.new()
	palette_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	palette_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	palette_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.add_child(palette_scroll)
	_stage_editor_palette_scroll = palette_scroll

	var button_grid := GridContainer.new()
	button_grid.columns = STAGE_EDITOR_GEM_TYPES.size()
	button_grid.add_theme_constant_override("h_separation", 4)
	button_grid.add_theme_constant_override("v_separation", 6)
	button_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	palette_scroll.add_child(button_grid)
	_stage_editor_palette_grid = button_grid

	for gem_type: int in STAGE_EDITOR_GEM_TYPES:
		var value_button: Button = _make_stage_editor_value_button(gem_type, _stage_editor_type_name(gem_type))
		button_grid.add_child(value_button)
		_stage_editor_value_buttons[gem_type] = value_button

	var drop_row := GridContainer.new()
	drop_row.columns = current_stage.columns if current_stage != null else 8
	drop_row.add_theme_constant_override("h_separation", 2)
	drop_row.add_theme_constant_override("v_separation", 0)
	drop_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_box.add_child(drop_row)

	_stage_editor_drop_start_spins.clear()
	var editor_columns: int = current_stage.columns if current_stage != null else 8
	for column_index in editor_columns:
		drop_row.add_child(_make_stage_editor_drop_start_spin(column_index))

	root_box.add_child(_make_stage_editor_reward_row())

	_refresh_stage_editor_value_buttons()
	_refresh_stage_editor_area_panel()
	_layout_stage_editor_ui()


func _stage_editor_load_area_state() -> void:
	if current_stage == null:
		_stage_editor_selected_area = StageData.DEFAULT_AREA
		return
	_stage_editor_selected_area = StageData.normalize_area(current_stage.area)
	current_stage.area = _stage_editor_selected_area


func _build_stage_editor_area_panel() -> void:
	if _stage_editor_area_panel != null:
		return
	_stage_editor_distribution_spins.clear()
	_stage_editor_area_panel = PanelContainer.new()
	_stage_editor_area_panel.name = "StageEditorAreaPanel"
	_stage_editor_area_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage_editor_area_panel.custom_minimum_size = Vector2(420, 108)
	_stage_editor_area_panel.add_theme_stylebox_override("panel", _make_stage_editor_panel_style(Color(0.05, 0.06, 0.09, 0.95)))
	$UILayer.add_child(_stage_editor_area_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 4)
	_stage_editor_area_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	margin.add_child(row)

	var selector_box := VBoxContainer.new()
	selector_box.add_theme_constant_override("separation", 1)
	selector_box.custom_minimum_size = Vector2(116, 0)
	row.add_child(selector_box)

	var title := Label.new()
	title.text = "Map Area"
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
	selector_box.add_child(title)

	_stage_editor_area_option = OptionButton.new()
	_stage_editor_area_option.focus_mode = Control.FOCUS_NONE
	_stage_editor_area_option.fit_to_longest_item = false
	_stage_editor_area_option.custom_minimum_size = Vector2(112, 28)
	_stage_editor_area_option.add_theme_font_size_override("font_size", 11)
	for area_key: String in StageData.AREA_KEYS:
		var item_index: int = _stage_editor_area_option.item_count
		_stage_editor_area_option.add_item(area_key)
		_stage_editor_area_option.set_item_metadata(item_index, area_key)
	_stage_editor_area_option.item_selected.connect(_on_stage_editor_area_selected)
	selector_box.add_child(_stage_editor_area_option)

	var override_label := Label.new()
	override_label.text = "BG Override"
	override_label.add_theme_font_size_override("font_size", 8)
	override_label.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
	selector_box.add_child(override_label)

	_stage_editor_bg_override_option = OptionButton.new()
	_stage_editor_bg_override_option.focus_mode = Control.FOCUS_NONE
	_stage_editor_bg_override_option.custom_minimum_size = Vector2(112, 24)
	_stage_editor_bg_override_option.add_theme_font_size_override("font_size", 10)
	_stage_editor_make_compact_option_button(_stage_editor_bg_override_option)
	_stage_editor_bg_override_option.item_selected.connect(_on_stage_editor_bg_override_selected)
	selector_box.add_child(_stage_editor_bg_override_option)

	var spot_box := VBoxContainer.new()
	spot_box.add_theme_constant_override("separation", 1)
	row.add_child(spot_box)

	var spot_top_row := HBoxContainer.new()
	spot_top_row.add_theme_constant_override("separation", 2)
	spot_box.add_child(spot_top_row)

	_stage_editor_area_spot_preview = TextureRect.new()
	_stage_editor_area_spot_preview.name = "SpotPreview"
	_stage_editor_area_spot_preview.custom_minimum_size = Vector2(48, 44)
	_stage_editor_area_spot_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_stage_editor_area_spot_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_stage_editor_area_spot_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_editor_area_spot_preview.tooltip_text = "Spot"
	spot_top_row.add_child(_stage_editor_area_spot_preview)

	_stage_editor_stretch_bg_check = CheckButton.new()
	_stage_editor_stretch_bg_check.text = "Full BG"
	_stage_editor_stretch_bg_check.focus_mode = Control.FOCUS_NONE
	_stage_editor_stretch_bg_check.custom_minimum_size = Vector2(66, 20)
	_stage_editor_stretch_bg_check.add_theme_font_size_override("font_size", 8)
	_stage_editor_stretch_bg_check.tooltip_text = "Stretch battle background to the full screen."
	_stage_editor_stretch_bg_check.toggled.connect(_on_stage_editor_stretch_bg_toggled)
	spot_top_row.add_child(_stage_editor_stretch_bg_check)

	var music_box := VBoxContainer.new()
	music_box.add_theme_constant_override("separation", 1)
	music_box.custom_minimum_size = Vector2(104, 0)
	spot_box.add_child(music_box)

	var music_override_label := Label.new()
	music_override_label.text = "Music Override"
	music_override_label.add_theme_font_size_override("font_size", 8)
	music_override_label.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
	music_box.add_child(music_override_label)

	_stage_editor_music_override_option = OptionButton.new()
	_stage_editor_music_override_option.focus_mode = Control.FOCUS_NONE
	_stage_editor_music_override_option.custom_minimum_size = Vector2(104, 22)
	_stage_editor_music_override_option.add_theme_font_size_override("font_size", 10)
	_stage_editor_make_compact_option_button(_stage_editor_music_override_option)
	_stage_editor_music_override_option.item_selected.connect(_on_stage_editor_music_override_selected)
	music_box.add_child(_stage_editor_music_override_option)

	var boss_bgm_label := Label.new()
	boss_bgm_label.text = "Boss BGM"
	boss_bgm_label.add_theme_font_size_override("font_size", 8)
	boss_bgm_label.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
	music_box.add_child(boss_bgm_label)

	_stage_editor_boss_bgm_option = OptionButton.new()
	_stage_editor_boss_bgm_option.focus_mode = Control.FOCUS_NONE
	_stage_editor_boss_bgm_option.custom_minimum_size = Vector2(104, 22)
	_stage_editor_boss_bgm_option.add_theme_font_size_override("font_size", 10)
	_stage_editor_make_compact_option_button(_stage_editor_boss_bgm_option)
	_stage_editor_boss_bgm_option.item_selected.connect(_on_stage_editor_boss_bgm_selected)
	music_box.add_child(_stage_editor_boss_bgm_option)

	var distribution_box := VBoxContainer.new()
	distribution_box.add_theme_constant_override("separation", 2)
	distribution_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(distribution_box)

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 4)
	distribution_box.add_child(action_row)

	action_row.add_child(_make_stage_editor_mode_button("Normal", StageData.Mode.NORMAL))
	action_row.add_child(_make_stage_editor_mode_button("Escape", StageData.Mode.ESCAPE))
	action_row.add_child(_make_stage_editor_mode_button("Puzzle", StageData.Mode.PUZZLE))
	action_row.add_child(_make_stage_editor_command_button("Clear", _on_stage_editor_clear_pressed))
	action_row.add_child(_make_stage_editor_command_button("Save", _on_stage_editor_save_pressed))
	action_row.add_child(_make_stage_editor_command_button("Back", _on_stage_editor_back_pressed))

	var dist_title := Label.new()
	dist_title.text = Locale.tr_ui("ELEMENT_DISTRIBUTION")
	dist_title.add_theme_font_size_override("font_size", 11)
	dist_title.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
	distribution_box.add_child(dist_title)

	var dist_row := HBoxContainer.new()
	dist_row.add_theme_constant_override("separation", 2)
	distribution_box.add_child(dist_row)

	for type_value: int in STAGE_EDITOR_DISTRIBUTION_TYPES:
		dist_row.add_child(_make_stage_editor_distribution_spin(type_value))
	_refresh_stage_editor_mode_buttons()


func _make_stage_editor_distribution_spin(type_value: int) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(40, 0)
	box.add_theme_constant_override("separation", 1)

	var label := Label.new()
	label.text = _stage_editor_distribution_label(type_value)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Block.COLORS.get(type_value, Color.WHITE).lightened(0.2))
	box.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = 0
	spin.max_value = 100
	spin.step = 1
	spin.value = current_stage.get_element_weight_for_type(type_value) if current_stage != null else 1
	spin.custom_minimum_size = Vector2(40, 24)
	spin.get_line_edit().custom_minimum_size = Vector2(18, 0)
	spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	spin.tooltip_text = "Random board generation weight."
	spin.value_changed.connect(_on_stage_editor_distribution_changed.bind(type_value))
	box.add_child(spin)
	_stage_editor_distribution_spins[type_value] = spin
	return box


func _make_stage_editor_drop_start_spin(column_index: int) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(48, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 1)

	var label := Label.new()
	label.text = "C%d" % (column_index + 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 9)
	label.add_theme_color_override("font_color", Color(0.72, 0.86, 1.0, 1.0))
	box.add_child(label)

	var stepper := HBoxContainer.new()
	stepper.add_theme_constant_override("separation", 1)
	stepper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(stepper)

	var minus_button := Button.new()
	minus_button.text = "-"
	minus_button.focus_mode = Control.FOCUS_NONE
	minus_button.custom_minimum_size = Vector2(14, 22)
	minus_button.add_theme_font_size_override("font_size", 10)
	minus_button.tooltip_text = "Move drop start up."
	minus_button.pressed.connect(_on_stage_editor_drop_start_step.bind(column_index, -1))
	stepper.add_child(minus_button)

	var value_edit := LineEdit.new()
	value_edit.text = str(_stage_editor_get_drop_start_value(column_index))
	value_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_edit.custom_minimum_size = Vector2(20, 22)
	value_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_edit.add_theme_font_size_override("font_size", 12)
	value_edit.tooltip_text = "Gem drop start row for this column."
	value_edit.text_submitted.connect(_on_stage_editor_drop_start_text_submitted.bind(column_index))
	value_edit.focus_exited.connect(_on_stage_editor_drop_start_focus_exited.bind(column_index))
	stepper.add_child(value_edit)

	var plus_button := Button.new()
	plus_button.text = "+"
	plus_button.focus_mode = Control.FOCUS_NONE
	plus_button.custom_minimum_size = Vector2(14, 22)
	plus_button.add_theme_font_size_override("font_size", 10)
	plus_button.tooltip_text = "Move drop start down."
	plus_button.pressed.connect(_on_stage_editor_drop_start_step.bind(column_index, 1))
	stepper.add_child(plus_button)

	_stage_editor_drop_start_spins[column_index] = value_edit
	return box


func _make_stage_editor_reward_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var reward_label := Label.new()
	reward_label.text = "Clear Reward"
	reward_label.custom_minimum_size = Vector2(82, 22)
	reward_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reward_label.add_theme_font_size_override("font_size", 10)
	reward_label.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
	row.add_child(reward_label)

	_stage_editor_reward_item_option = OptionButton.new()
	_stage_editor_reward_item_option.focus_mode = Control.FOCUS_NONE
	_stage_editor_reward_item_option.custom_minimum_size = Vector2(92, 24)
	_stage_editor_reward_item_option.add_theme_font_size_override("font_size", 10)
	_stage_editor_reward_item_option.tooltip_text = "Stage clear reward item. Enemy loot is edited on each enemy card."
	_stage_editor_make_compact_option_button(_stage_editor_reward_item_option)
	_stage_editor_reward_item_option.item_selected.connect(_on_stage_editor_reward_changed)
	row.add_child(_stage_editor_reward_item_option)

	_stage_editor_reward_amount_edit = LineEdit.new()
	_stage_editor_reward_amount_edit.custom_minimum_size = Vector2(48, 24)
	_stage_editor_reward_amount_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_editor_reward_amount_edit.add_theme_font_size_override("font_size", 11)
	_stage_editor_reward_amount_edit.tooltip_text = "Stage clear reward item amount."
	_stage_editor_reward_amount_edit.text_submitted.connect(func(_text: String) -> void: _on_stage_editor_reward_changed(0))
	_stage_editor_reward_amount_edit.focus_exited.connect(func() -> void: _on_stage_editor_reward_changed(0))
	row.add_child(_stage_editor_reward_amount_edit)

	_stage_editor_reward_character_option = OptionButton.new()
	_stage_editor_reward_character_option.focus_mode = Control.FOCUS_NONE
	_stage_editor_reward_character_option.custom_minimum_size = Vector2(150, 24)
	_stage_editor_reward_character_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_editor_reward_character_option.add_theme_font_size_override("font_size", 10)
	_stage_editor_reward_character_option.tooltip_text = "Stage clear reward character. Enemy loot is edited on each enemy card."
	_stage_editor_make_compact_option_button(_stage_editor_reward_character_option)
	_stage_editor_reward_character_option.item_selected.connect(_on_stage_editor_reward_changed)
	row.add_child(_stage_editor_reward_character_option)

	_refresh_stage_editor_reward_controls()
	return row

func _build_stage_editor_tab_panel() -> void:
	if _stage_editor_tab_panel != null:
		return
	_stage_editor_tab_panel = PanelContainer.new()
	_stage_editor_tab_panel.name = "StageEditorTabs"
	_stage_editor_tab_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage_editor_tab_panel.add_theme_stylebox_override("panel", _make_stage_editor_panel_style(Color(0.04, 0.05, 0.08, 0.96)))
	$UILayer.add_child(_stage_editor_tab_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_stage_editor_tab_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)

	row.add_child(_make_stage_editor_tab_button("Before", STAGE_EDITOR_TAB_BEFORE))
	row.add_child(_make_stage_editor_tab_button("Board", STAGE_EDITOR_TAB_BOARD))
	row.add_child(_make_stage_editor_tab_button("After", STAGE_EDITOR_TAB_AFTER))


func _make_stage_editor_tab_button(label_text: String, tab_id: String) -> Button:
	var button := Button.new()
	button.text = label_text
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(104, 38)
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(_stage_editor_select_tab.bind(tab_id))
	_stage_editor_tab_buttons[tab_id] = button
	return button


func _build_stage_editor_dialog_panel() -> void:
	if _stage_editor_dialog_panel != null:
		return
	_stage_editor_dialog_panel = PanelContainer.new()
	_stage_editor_dialog_panel.name = "StageEditorDialogEditor"
	_stage_editor_dialog_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage_editor_dialog_panel.visible = false
	_stage_editor_dialog_panel.add_theme_stylebox_override("panel", _make_stage_editor_panel_style(Color(0.04, 0.05, 0.08, 0.97)))
	$UILayer.add_child(_stage_editor_dialog_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_stage_editor_dialog_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 6)
	root.add_child(header_row)

	_stage_editor_dialog_title_label = Label.new()
	_stage_editor_dialog_title_label.text = "Dialog"
	_stage_editor_dialog_title_label.add_theme_font_size_override("font_size", 16)
	_stage_editor_dialog_title_label.add_theme_color_override("font_color", Color.WHITE)
	_stage_editor_dialog_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(_stage_editor_dialog_title_label)

	var bg_label := Label.new()
	bg_label.text = "BG"
	bg_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bg_label.add_theme_font_size_override("font_size", 12)
	bg_label.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
	header_row.add_child(bg_label)

	_stage_editor_dialog_background_option = OptionButton.new()
	_stage_editor_dialog_background_option.focus_mode = Control.FOCUS_NONE
	_stage_editor_dialog_background_option.custom_minimum_size = Vector2(132, 30)
	_stage_editor_dialog_background_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_editor_make_compact_option_button(_stage_editor_dialog_background_option)
	_stage_editor_dialog_background_option.item_selected.connect(_on_stage_editor_dialog_background_selected)
	header_row.add_child(_stage_editor_dialog_background_option)

	var music_label := Label.new()
	music_label.text = "Init BGM"
	music_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	music_label.add_theme_font_size_override("font_size", 12)
	music_label.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
	header_row.add_child(music_label)

	_stage_editor_dialog_music_option = OptionButton.new()
	_stage_editor_dialog_music_option.focus_mode = Control.FOCUS_NONE
	_stage_editor_dialog_music_option.custom_minimum_size = Vector2(132, 30)
	_stage_editor_dialog_music_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_editor_make_compact_option_button(_stage_editor_dialog_music_option)
	_stage_editor_dialog_music_option.item_selected.connect(_on_stage_editor_dialog_music_selected)
	header_row.add_child(_stage_editor_dialog_music_option)

	header_row.add_child(_make_stage_editor_small_button("Test Play", _on_stage_editor_dialog_test_play_pressed, Vector2(86, 30)))

	var cast_row := HBoxContainer.new()
	cast_row.add_theme_constant_override("separation", 6)
	root.add_child(cast_row)

	var cast_label := Label.new()
	cast_label.text = "Cast"
	cast_label.custom_minimum_size = Vector2(44, 0)
	cast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cast_label.add_theme_font_size_override("font_size", 12)
	cast_label.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
	cast_row.add_child(cast_label)

	_stage_editor_dialog_cast_list = HBoxContainer.new()
	_stage_editor_dialog_cast_list.add_theme_constant_override("separation", 4)
	_stage_editor_dialog_cast_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cast_row.add_child(_stage_editor_dialog_cast_list)

	_stage_editor_dialog_add_cast_option = OptionButton.new()
	_stage_editor_dialog_add_cast_option.focus_mode = Control.FOCUS_NONE
	_stage_editor_dialog_add_cast_option.custom_minimum_size = Vector2(148, 30)
	cast_row.add_child(_stage_editor_dialog_add_cast_option)
	cast_row.add_child(_make_stage_editor_small_button("Add Cast", _on_stage_editor_dialog_add_cast_pressed, Vector2(78, 30)))

	var exit_row := HBoxContainer.new()
	exit_row.add_theme_constant_override("separation", 6)
	root.add_child(exit_row)

	var exit_label := Label.new()
	exit_label.text = "Exit"
	exit_label.custom_minimum_size = Vector2(44, 0)
	exit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	exit_label.add_theme_font_size_override("font_size", 12)
	exit_label.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
	exit_row.add_child(exit_label)

	_stage_editor_dialog_exit_cast_option = OptionButton.new()
	_stage_editor_dialog_exit_cast_option.focus_mode = Control.FOCUS_NONE
	_stage_editor_dialog_exit_cast_option.custom_minimum_size = Vector2(148, 30)
	exit_row.add_child(_stage_editor_dialog_exit_cast_option)

	_stage_editor_dialog_exit_side_option = CheckButton.new()
	_stage_editor_dialog_exit_side_option.focus_mode = Control.FOCUS_NONE
	_stage_editor_dialog_exit_side_option.custom_minimum_size = Vector2(92, 30)
	_stage_editor_dialog_exit_side_option.text = "Left"
	_stage_editor_dialog_exit_side_option.toggled.connect(_on_stage_editor_dialog_exit_side_toggled)
	exit_row.add_child(_stage_editor_dialog_exit_side_option)
	exit_row.add_child(_make_stage_editor_small_button("Add Exit", _on_stage_editor_dialog_add_exit_pressed, Vector2(78, 30)))

	var line_scroll := ScrollContainer.new()
	line_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	line_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	line_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(line_scroll)

	_stage_editor_dialog_line_list = VBoxContainer.new()
	_stage_editor_dialog_line_list.add_theme_constant_override("separation", 6)
	_stage_editor_dialog_line_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line_scroll.add_child(_stage_editor_dialog_line_list)


func _stage_editor_make_form_label(label_text: String) -> Label:
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(86, 0)
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


func _stage_editor_make_line_edit_field(parent: VBoxContainer, label_text: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	row.add_child(_stage_editor_make_form_label(label_text))
	var edit := LineEdit.new()
	edit.focus_mode = Control.FOCUS_CLICK
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return edit


func _stage_editor_make_option_field(parent: VBoxContainer, label_text: String, values: Array[String]) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	row.add_child(_stage_editor_make_form_label(label_text))
	var option := OptionButton.new()
	option.focus_mode = Control.FOCUS_NONE
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for value: String in values:
		var item_index: int = option.item_count
		option.add_item(value)
		option.set_item_metadata(item_index, value)
	row.add_child(option)
	return option


func _stage_editor_make_text_edit_field(parent: VBoxContainer, label_text: String) -> TextEdit:
	var label := _stage_editor_make_form_label(label_text)
	parent.add_child(label)
	var edit := TextEdit.new()
	edit.custom_minimum_size = Vector2(0, 92)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	parent.add_child(edit)
	return edit


func _stage_editor_select_tab(tab_id: String) -> void:
	if tab_id != STAGE_EDITOR_TAB_BEFORE and tab_id != STAGE_EDITOR_TAB_BOARD and tab_id != STAGE_EDITOR_TAB_AFTER:
		return
	_stage_editor_current_tab = tab_id
	var board_tab: bool = tab_id == STAGE_EDITOR_TAB_BOARD
	if board != null and board.has_method("set_edit_input_enabled"):
		board.set_edit_input_enabled(board_tab)
	if board_tab:
		board.set_edit_paint_value(_stage_editor_selected_value)
		_stage_editor_dialog_target = ""
	else:
		_stage_editor_dialog_target = tab_id
		var sequence: DialogSequence = _stage_editor_get_or_create_dialog_sequence(tab_id)
		if sequence != null and sequence.lines.size() > 0 and _stage_editor_dialog_selected_index < 0:
			_stage_editor_dialog_selected_index = 0
		_refresh_stage_editor_dialog_editor()
	if _stage_editor_panel != null:
		_stage_editor_panel.visible = board_tab
	if _stage_editor_area_panel != null:
		_stage_editor_area_panel.visible = board_tab
	if _stage_editor_enemy_area_panel != null:
		_stage_editor_enemy_area_panel.visible = board_tab
	if _stage_editor_enemy_picker_panel != null and not board_tab:
		_stage_editor_enemy_picker_panel.visible = false
	if _stage_editor_dialog_panel != null:
		_stage_editor_dialog_panel.visible = not board_tab
	_update_stage_editor_tab_buttons()
	_layout_stage_editor_ui()


func _update_stage_editor_tab_buttons() -> void:
	for key in _stage_editor_tab_buttons.keys():
		var button: Button = _stage_editor_tab_buttons[key]
		button.set_pressed_no_signal(String(key) == _stage_editor_current_tab)


func _stage_editor_get_or_create_dialog_sequence(target: String) -> DialogSequence:
	if current_stage == null:
		return null
	if target == STAGE_EDITOR_TAB_BEFORE:
		if current_stage.pre_dialog == null:
			current_stage.pre_dialog = DialogSequence.new()
		return current_stage.pre_dialog
	if target == STAGE_EDITOR_TAB_AFTER:
		if current_stage.post_dialog == null:
			current_stage.post_dialog = DialogSequence.new()
		return current_stage.post_dialog
	return null


func _stage_editor_active_dialog_sequence() -> DialogSequence:
	if _stage_editor_dialog_target.is_empty():
		return null
	return _stage_editor_get_or_create_dialog_sequence(_stage_editor_dialog_target)


func _stage_editor_load_character_catalog() -> void:
	if not _stage_editor_character_catalog.is_empty():
		return
	_stage_editor_character_catalog.clear()
	_stage_editor_character_by_id.clear()
	var dir := DirAccess.open("res://characters")
	if dir == null:
		return
	var files: PackedStringArray = dir.get_files()
	files.sort()
	for file_name: String in files:
		var extension: String = file_name.get_extension().to_lower()
		if extension != "tres" and extension != "res":
			continue
		var resource_path: String = "res://characters/" + file_name
		var resource: Resource = load(resource_path)
		var character: CharacterData = resource as CharacterData
		if character == null:
			continue
		var char_id: String = _stage_editor_character_id_from_path(resource_path)
		var display_name: String = Locale.tr_ui(character.character_name)
		if display_name.strip_edges().is_empty():
			display_name = char_id.capitalize()
		var entry: Dictionary = {
			"id": char_id,
			"name": display_name,
			"resource_path": resource_path,
			"portrait_texture": character.portrait_texture,
		}
		_stage_editor_character_catalog.append(entry)
		_stage_editor_character_by_id[char_id] = entry


func _stage_editor_load_dialog_background_catalog() -> void:
	if not _stage_editor_dialog_background_catalog.is_empty():
		return
	_stage_editor_dialog_background_catalog.clear()
	var dir := DirAccess.open(STAGE_EDITOR_DIALOG_BACKGROUND_ROOT)
	if dir == null:
		return
	var files: PackedStringArray = dir.get_files()
	files.sort()
	for file_name: String in files:
		var extension: String = file_name.get_extension().to_lower()
		if extension != "png" and extension != "jpg" and extension != "jpeg" and extension != "webp":
			continue
		var resource_path: String = STAGE_EDITOR_DIALOG_BACKGROUND_ROOT + "/" + file_name
		if not ResourceLoader.exists(resource_path):
			continue
		_stage_editor_dialog_background_catalog.append({
			"name": _stage_editor_dialog_background_display_name(resource_path),
			"resource_path": resource_path,
		})


func _stage_editor_load_dialog_music_catalog() -> void:
	if not _stage_editor_dialog_music_catalog.is_empty():
		return
	_stage_editor_dialog_music_catalog.clear()
	var dir := DirAccess.open(STAGE_EDITOR_DIALOG_MUSIC_ROOT)
	if dir == null:
		return
	var files: PackedStringArray = dir.get_files()
	files.sort()
	for file_name: String in files:
		var extension: String = file_name.get_extension().to_lower()
		if extension != "mp3" and extension != "ogg" and extension != "wav":
			continue
		var resource_path: String = STAGE_EDITOR_DIALOG_MUSIC_ROOT + "/" + file_name
		if not ResourceLoader.exists(resource_path):
			continue
		_stage_editor_dialog_music_catalog.append({
			"name": _stage_editor_dialog_music_display_name(resource_path),
			"resource_path": resource_path,
		})


func _stage_editor_dialog_background_display_name(resource_path: String) -> String:
	var file_base: String = resource_path.get_file().get_basename()
	if file_base.begins_with("dialog_bg_"):
		file_base = file_base.substr(10)
	return file_base.replace("_", " ").capitalize()


func _stage_editor_dialog_music_display_name(resource_path: String) -> String:
	return resource_path.get_file().get_basename().replace("_", " ").capitalize()


func _stage_editor_populate_dialog_background_selector(option: OptionButton, selected_path: String, placeholder: String = "switchBG") -> void:
	_stage_editor_make_compact_option_button(option)
	option.clear()
	_stage_editor_add_option_item(option, placeholder, "")
	for entry: Dictionary in _stage_editor_dialog_background_catalog:
		_stage_editor_add_option_item(option, String(entry.get("name", "BG")), String(entry.get("resource_path", "")))
	_stage_editor_select_option_value(option, selected_path)


func _stage_editor_populate_dialog_music_selector(option: OptionButton, selected_path: String, placeholder: String = "switchBGM", include_stop: bool = true) -> void:
	_stage_editor_make_compact_option_button(option)
	option.clear()
	_stage_editor_add_option_item(option, placeholder, "")
	if include_stop:
		_stage_editor_add_option_item(option, "Stop BGM", "__stop__")
	for entry: Dictionary in _stage_editor_dialog_music_catalog:
		_stage_editor_add_option_item(option, String(entry.get("name", "BGM")), String(entry.get("resource_path", "")))
	_stage_editor_select_option_value(option, selected_path)


func _stage_editor_make_compact_option_button(option: OptionButton) -> void:
	option.fit_to_longest_item = false
	option.clip_text = true
	option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS


func _stage_editor_dialog_line_background_path(line: DialogLine) -> String:
	if line == null or line.background == null:
		return ""
	return line.background.resource_path


func _stage_editor_dialog_audio_path(stream: AudioStream) -> String:
	return stream.resource_path if stream != null else ""


func _stage_editor_character_id_from_path(resource_path: String) -> String:
	var file_base: String = resource_path.get_file().get_basename()
	if file_base.begins_with("char_"):
		return file_base.substr(5)
	return file_base


func _stage_editor_character_display_name(char_id: String) -> String:
	if char_id.is_empty():
		return "旁白"
	var entry: Dictionary = _stage_editor_character_by_id.get(char_id, {})
	if not entry.is_empty():
		return String(entry.get("name", char_id.capitalize()))
	return Locale.tr_or("DIALOG_" + char_id, char_id.capitalize())


func _stage_editor_ensure_dialog_cast(sequence: DialogSequence) -> void:
	if sequence == null:
		return
	var known: Dictionary = {}
	for cast_variant in sequence.cast:
		var cast_id: String = String(cast_variant).strip_edges()
		if cast_id.is_empty() or known.has(cast_id):
			continue
		known[cast_id] = true
	for line: DialogLine in sequence.lines:
		var char_id: String = line.character_id.strip_edges()
		if char_id.is_empty() or known.has(char_id):
			continue
		sequence.cast.append(char_id)
		known[char_id] = true


func _stage_editor_first_cast_id(sequence: DialogSequence) -> String:
	if sequence != null and not sequence.cast.is_empty():
		return String(sequence.cast[0])
	if not _stage_editor_character_catalog.is_empty():
		var entry: Dictionary = _stage_editor_character_catalog[0]
		return String(entry.get("id", ""))
	return ""


func _stage_editor_dialog_line_references_cast(sequence: DialogSequence, char_id: String) -> bool:
	if sequence == null or char_id.is_empty():
		return false
	for line: DialogLine in sequence.lines:
		if line.character_id == char_id:
			return true
	return false


func _stage_editor_add_option_item(option: OptionButton, label_text: String, value: String) -> void:
	var item_index: int = option.item_count
	option.add_item(label_text)
	option.set_item_metadata(item_index, value)


func _stage_editor_make_dialog_line() -> DialogLine:
	var line := DialogLine.new()
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	line.character_id = _stage_editor_first_cast_id(sequence)
	line.emotion = "normal"
	line.position = "left"
	line.text_zh = ""
	line.text_en = ""
	line.action = "none"
	line.shake = true
	line.stop_music = false
	return line


func _stage_editor_copy_dialog_line(source: DialogLine) -> DialogLine:
	var line := DialogLine.new()
	line.character_id = source.character_id
	line.emotion = source.emotion
	line.position = source.position
	line.text_zh = source.text_zh
	line.text_en = source.text_en
	line.action = source.action
	line.shake = source.shake
	line.music = source.music
	line.stop_music = source.stop_music
	line.sound_effect = source.sound_effect
	line.background = source.background
	return line


func _stage_editor_get_selected_dialog_line() -> DialogLine:
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	if sequence == null:
		return null
	if _stage_editor_dialog_selected_index < 0 or _stage_editor_dialog_selected_index >= sequence.lines.size():
		return null
	return sequence.lines[_stage_editor_dialog_selected_index]


func _refresh_stage_editor_dialog_editor() -> void:
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	if _stage_editor_dialog_title_label != null:
		var title: String = "Board"
		if _stage_editor_dialog_target == STAGE_EDITOR_TAB_BEFORE:
			title = "Before Dialog"
		elif _stage_editor_dialog_target == STAGE_EDITOR_TAB_AFTER:
			title = "After Dialog"
		_stage_editor_dialog_title_label.text = title
	_stage_editor_ensure_dialog_cast(sequence)
	_refresh_stage_editor_dialog_background_option(sequence)
	_refresh_stage_editor_dialog_music_option(sequence)
	_refresh_stage_editor_dialog_cast_controls(sequence)
	_refresh_stage_editor_dialog_line_list()


func _refresh_stage_editor_dialog_background_option(sequence: DialogSequence) -> void:
	if _stage_editor_dialog_background_option == null:
		return
	_stage_editor_dialog_refreshing = true
	_stage_editor_dialog_background_option.clear()
	_stage_editor_add_option_item(_stage_editor_dialog_background_option, "None", "")
	for entry: Dictionary in _stage_editor_dialog_background_catalog:
		_stage_editor_add_option_item(_stage_editor_dialog_background_option, String(entry.get("name", "BG")), String(entry.get("resource_path", "")))
	var selected_path: String = ""
	if sequence != null and sequence.background != null:
		selected_path = sequence.background.resource_path
	_stage_editor_select_option_value(_stage_editor_dialog_background_option, selected_path)
	_stage_editor_dialog_background_option.disabled = sequence == null
	_stage_editor_dialog_refreshing = false


func _refresh_stage_editor_dialog_music_option(sequence: DialogSequence) -> void:
	if _stage_editor_dialog_music_option == null:
		return
	_stage_editor_dialog_refreshing = true
	_stage_editor_populate_dialog_music_selector(
		_stage_editor_dialog_music_option,
		_stage_editor_dialog_audio_path(sequence.initial_music) if sequence != null else "",
		"None",
		false)
	_stage_editor_dialog_music_option.disabled = sequence == null
	_stage_editor_dialog_refreshing = false


func _refresh_stage_editor_dialog_cast_controls(sequence: DialogSequence) -> void:
	if _stage_editor_dialog_cast_list != null:
		for child in _stage_editor_dialog_cast_list.get_children():
			_stage_editor_dialog_cast_list.remove_child(child)
			child.queue_free()
	if sequence == null:
		return
	for cast_variant in sequence.cast:
		var char_id: String = String(cast_variant)
		var button := Button.new()
		button.text = _stage_editor_character_display_name(char_id) + " x"
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(82, 28)
		button.add_theme_font_size_override("font_size", 11)
		var is_referenced: bool = _stage_editor_dialog_line_references_cast(sequence, char_id)
		button.tooltip_text = "Drag to row" if is_referenced else "Drag to row / click to remove"
		button.set_drag_forwarding(
			Callable(self, "_stage_editor_get_cast_drag_data").bind(button, char_id),
			Callable(self, "_stage_editor_no_drop_data"),
			Callable(self, "_stage_editor_ignore_drop_data"))
		button.pressed.connect(_on_stage_editor_dialog_remove_cast_pressed.bind(char_id))
		_stage_editor_dialog_cast_list.add_child(button)

	if _stage_editor_dialog_add_cast_option != null:
		_stage_editor_dialog_add_cast_option.clear()
		for entry in _stage_editor_character_catalog:
			var entry_id: String = String(entry.get("id", ""))
			if entry_id.is_empty() or sequence.cast.has(entry_id):
				continue
			_stage_editor_add_option_item(_stage_editor_dialog_add_cast_option, String(entry.get("name", entry_id.capitalize())), entry_id)
		_stage_editor_dialog_add_cast_option.disabled = _stage_editor_dialog_add_cast_option.item_count == 0

	if _stage_editor_dialog_exit_cast_option != null:
		_stage_editor_dialog_exit_cast_option.clear()
		for cast_variant in sequence.cast:
			var char_id: String = String(cast_variant)
			_stage_editor_add_option_item(_stage_editor_dialog_exit_cast_option, _stage_editor_character_display_name(char_id), char_id)
		_stage_editor_dialog_exit_cast_option.disabled = _stage_editor_dialog_exit_cast_option.item_count == 0
	if _stage_editor_dialog_exit_side_option != null:
		_stage_editor_dialog_exit_side_option.disabled = sequence.cast.is_empty()


func _refresh_stage_editor_dialog_line_list() -> void:
	if _stage_editor_dialog_line_list == null:
		return
	for child in _stage_editor_dialog_line_list.get_children():
		_stage_editor_dialog_line_list.remove_child(child)
		child.queue_free()
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	if sequence == null:
		return
	if sequence.lines.is_empty():
		_stage_editor_dialog_selected_index = -1
		var empty_label := Label.new()
		empty_label.text = "No rows yet. Use + to add the first line."
		empty_label.add_theme_color_override("font_color", Color(0.78, 0.84, 0.92, 1.0))
		_stage_editor_dialog_line_list.add_child(empty_label)
		_stage_editor_dialog_line_list.add_child(_stage_editor_make_dialog_add_row())
		return
	_stage_editor_dialog_selected_index = clampi(_stage_editor_dialog_selected_index, 0, sequence.lines.size() - 1)
	for line_index in sequence.lines.size():
		var line: DialogLine = sequence.lines[line_index]
		_stage_editor_dialog_line_list.add_child(_stage_editor_make_dialog_row(line_index, line, sequence))
	_stage_editor_dialog_line_list.add_child(_stage_editor_make_dialog_add_row())


func _stage_editor_make_dialog_add_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var button := Button.new()
	button.text = "+"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0, 38)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 20)
	button.pressed.connect(_on_stage_editor_dialog_add_line_pressed)
	button.set_drag_forwarding(
		Callable(self, "_stage_editor_no_drag_data"),
		Callable(self, "_stage_editor_can_drop_on_dialog_add_row"),
		Callable(self, "_stage_editor_drop_on_dialog_add_row"))
	row.add_child(button)

	var switch_bg_option := OptionButton.new()
	switch_bg_option.focus_mode = Control.FOCUS_NONE
	switch_bg_option.custom_minimum_size = Vector2(120, 38)
	switch_bg_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_editor_populate_dialog_background_selector(switch_bg_option, "", "switchBG")
	switch_bg_option.item_selected.connect(_on_stage_editor_dialog_add_switch_bg_selected.bind(switch_bg_option))
	row.add_child(switch_bg_option)

	var switch_bgm_option := OptionButton.new()
	switch_bgm_option.focus_mode = Control.FOCUS_NONE
	switch_bgm_option.custom_minimum_size = Vector2(120, 38)
	switch_bgm_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_editor_populate_dialog_music_selector(switch_bgm_option, "", "switchBGM", true)
	switch_bgm_option.item_selected.connect(_on_stage_editor_dialog_add_switch_bgm_selected.bind(switch_bgm_option))
	row.add_child(switch_bgm_option)

	return row


func _stage_editor_make_dialog_row(line_index: int, line: DialogLine, sequence: DialogSequence) -> Control:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_stage_editor_panel_style(Color(0.07, 0.08, 0.12, 0.88)))
	panel.set_drag_forwarding(
		Callable(self, "_stage_editor_get_row_drag_data").bind(panel, line_index),
		Callable(self, "_stage_editor_can_drop_on_dialog_row").bind(line_index),
		Callable(self, "_stage_editor_drop_on_dialog_row").bind(line_index))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 7)
	panel.add_child(margin)

	var row_box := VBoxContainer.new()
	row_box.add_theme_constant_override("separation", 6)
	row_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(row_box)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 5)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_box.add_child(controls)

	var drag_handle := Label.new()
	drag_handle.text = "::"
	drag_handle.custom_minimum_size = Vector2(22, 30)
	drag_handle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drag_handle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drag_handle.add_theme_font_size_override("font_size", 14)
	drag_handle.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
	drag_handle.mouse_filter = Control.MOUSE_FILTER_STOP
	drag_handle.set_drag_forwarding(
		Callable(self, "_stage_editor_get_row_drag_data").bind(drag_handle, line_index),
		Callable(self, "_stage_editor_can_drop_on_dialog_row").bind(line_index),
		Callable(self, "_stage_editor_drop_on_dialog_row").bind(line_index))
	controls.add_child(drag_handle)

	var number_label := Label.new()
	number_label.text = "%02d" % [line_index + 1]
	number_label.custom_minimum_size = Vector2(34, 30)
	number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number_label.add_theme_font_size_override("font_size", 12)
	number_label.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
	controls.add_child(number_label)

	if _stage_editor_dialog_line_is_switch_bg(line):
		var event_label := Label.new()
		event_label.text = "Switch BG"
		event_label.custom_minimum_size = Vector2(86, 30)
		event_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		event_label.add_theme_font_size_override("font_size", 13)
		event_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0, 1.0))
		controls.add_child(event_label)

		var bg_option := OptionButton.new()
		bg_option.focus_mode = Control.FOCUS_NONE
		bg_option.custom_minimum_size = Vector2(108, 30)
		bg_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_stage_editor_populate_dialog_background_selector(bg_option, _stage_editor_dialog_line_background_path(line), "BG")
		bg_option.item_selected.connect(_on_stage_editor_dialog_row_switch_bg_selected.bind(line_index, bg_option))
		_stage_editor_forward_dialog_row_drop(bg_option, line_index)
		controls.add_child(bg_option)

		var bgm_option := OptionButton.new()
		bgm_option.focus_mode = Control.FOCUS_NONE
		bgm_option.custom_minimum_size = Vector2(108, 30)
		bgm_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var selected_bgm_path: String = "__stop__" if line.stop_music else _stage_editor_dialog_audio_path(line.music)
		_stage_editor_populate_dialog_music_selector(bgm_option, selected_bgm_path, "BGM no change", true)
		bgm_option.item_selected.connect(_on_stage_editor_dialog_row_switch_bgm_selected.bind(line_index, bgm_option))
		_stage_editor_forward_dialog_row_drop(bgm_option, line_index)
		controls.add_child(bgm_option)

		var event_spacer := Control.new()
		event_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		controls.add_child(event_spacer)

		controls.add_child(_make_stage_editor_small_button("Dup", _on_stage_editor_dialog_row_duplicate_pressed.bind(line_index), Vector2(44, 30)))
		controls.add_child(_make_stage_editor_small_button("Del", _on_stage_editor_dialog_row_delete_pressed.bind(line_index), Vector2(42, 30)))

		var event_row := HBoxContainer.new()
		event_row.add_theme_constant_override("separation", 6)
		row_box.add_child(event_row)

		var indicator := Label.new()
		indicator.text = "BG"
		indicator.custom_minimum_size = Vector2(64, 42)
		indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		indicator.add_theme_font_size_override("font_size", 14)
		indicator.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
		event_row.add_child(indicator)

		var description := Label.new()
		var bg_path: String = _stage_editor_dialog_line_background_path(line)
		description.text = "Fade switch to %s%s" % [
			_stage_editor_dialog_background_display_name(bg_path) if not bg_path.is_empty() else "None",
			_stage_editor_dialog_line_music_summary(line),
		]
		description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		description.clip_text = true
		description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		description.add_theme_font_size_override("font_size", 13)
		description.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
		event_row.add_child(description)
		return panel

	if _stage_editor_dialog_line_is_switch_bgm(line):
		var event_label := Label.new()
		event_label.text = "Switch BGM"
		event_label.custom_minimum_size = Vector2(92, 30)
		event_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		event_label.add_theme_font_size_override("font_size", 13)
		event_label.add_theme_color_override("font_color", Color(0.95, 0.95, 1.0, 1.0))
		controls.add_child(event_label)

		var bgm_option := OptionButton.new()
		bgm_option.focus_mode = Control.FOCUS_NONE
		bgm_option.custom_minimum_size = Vector2(126, 30)
		bgm_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var selected_bgm_event_path: String = "__stop__" if line.stop_music else _stage_editor_dialog_audio_path(line.music)
		_stage_editor_populate_dialog_music_selector(bgm_option, selected_bgm_event_path, "BGM no change", true)
		bgm_option.item_selected.connect(_on_stage_editor_dialog_row_switch_bgm_selected.bind(line_index, bgm_option))
		_stage_editor_forward_dialog_row_drop(bgm_option, line_index)
		controls.add_child(bgm_option)

		var event_spacer := Control.new()
		event_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		controls.add_child(event_spacer)

		controls.add_child(_make_stage_editor_small_button("Dup", _on_stage_editor_dialog_row_duplicate_pressed.bind(line_index), Vector2(44, 30)))
		controls.add_child(_make_stage_editor_small_button("Del", _on_stage_editor_dialog_row_delete_pressed.bind(line_index), Vector2(42, 30)))

		var event_row := HBoxContainer.new()
		event_row.add_theme_constant_override("separation", 6)
		row_box.add_child(event_row)

		var indicator := Label.new()
		indicator.text = "BGM"
		indicator.custom_minimum_size = Vector2(64, 42)
		indicator.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		indicator.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		indicator.add_theme_font_size_override("font_size", 14)
		indicator.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
		event_row.add_child(indicator)

		var description := Label.new()
		description.text = _stage_editor_dialog_line_music_summary(line).strip_edges()
		description.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		description.clip_text = true
		description.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		description.add_theme_font_size_override("font_size", 13)
		description.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
		event_row.add_child(description)
		return panel

	var speaker_option := OptionButton.new()
	speaker_option.focus_mode = Control.FOCUS_NONE
	speaker_option.custom_minimum_size = Vector2(112, 30)
	speaker_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_editor_make_compact_option_button(speaker_option)
	_stage_editor_populate_cast_dropdown(speaker_option, sequence, line.character_id)
	speaker_option.item_selected.connect(_on_stage_editor_dialog_row_speaker_selected.bind(line_index, speaker_option))
	_stage_editor_forward_dialog_row_drop(speaker_option, line_index)
	controls.add_child(speaker_option)

	var side_switch := CheckButton.new()
	side_switch.focus_mode = Control.FOCUS_NONE
	side_switch.custom_minimum_size = Vector2(76, 30)
	side_switch.button_pressed = line.position == "right"
	side_switch.text = "Right" if side_switch.button_pressed else "Left"
	side_switch.toggled.connect(_on_stage_editor_dialog_row_side_toggled.bind(line_index, side_switch))
	_stage_editor_forward_dialog_row_drop(side_switch, line_index)
	controls.add_child(side_switch)

	var action_option := OptionButton.new()
	action_option.focus_mode = Control.FOCUS_NONE
	action_option.custom_minimum_size = Vector2(76, 30)
	_stage_editor_make_compact_option_button(action_option)
	_stage_editor_add_option_item(action_option, "none", "none")
	_stage_editor_add_option_item(action_option, "enter", "enter")
	_stage_editor_add_option_item(action_option, "exit", "exit")
	_stage_editor_select_option_value(action_option, line.action)
	action_option.item_selected.connect(_on_stage_editor_dialog_row_action_selected.bind(line_index, action_option))
	_stage_editor_forward_dialog_row_drop(action_option, line_index)
	controls.add_child(action_option)

	var shake_check := CheckBox.new()
	shake_check.text = "Shake"
	shake_check.focus_mode = Control.FOCUS_NONE
	shake_check.button_pressed = line.shake
	shake_check.custom_minimum_size = Vector2(70, 30)
	shake_check.toggled.connect(_on_stage_editor_dialog_row_shake_toggled.bind(line_index))
	controls.add_child(shake_check)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_child(spacer)

	controls.add_child(_make_stage_editor_small_button("Dup", _on_stage_editor_dialog_row_duplicate_pressed.bind(line_index), Vector2(44, 30)))
	controls.add_child(_make_stage_editor_small_button("Del", _on_stage_editor_dialog_row_delete_pressed.bind(line_index), Vector2(42, 30)))

	var text_row := HBoxContainer.new()
	text_row.add_theme_constant_override("separation", 6)
	text_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_box.add_child(text_row)

	text_row.add_child(_stage_editor_make_character_indicator(line.character_id))
	if _stage_editor_dialog_line_is_exit(line):
		var exit_label := Label.new()
		exit_label.text = "Exit animation only"
		exit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		exit_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		exit_label.add_theme_font_size_override("font_size", 13)
		exit_label.add_theme_color_override("font_color", Color(0.82, 0.9, 1.0, 1.0))
		text_row.add_child(exit_label)
	else:
		var zh_edit: TextEdit = _stage_editor_make_row_text_edit(line.text_zh, "zh")
		zh_edit.text_changed.connect(_on_stage_editor_dialog_row_text_zh_changed.bind(zh_edit, line_index))
		_stage_editor_forward_dialog_row_drop(zh_edit, line_index)
		text_row.add_child(zh_edit)

		var en_edit: TextEdit = _stage_editor_make_row_text_edit(line.text_en, "en")
		en_edit.text_changed.connect(_on_stage_editor_dialog_row_text_en_changed.bind(en_edit, line_index))
		_stage_editor_forward_dialog_row_drop(en_edit, line_index)
		text_row.add_child(en_edit)

	return panel


func _stage_editor_forward_dialog_row_drop(control: Control, line_index: int) -> void:
	control.set_drag_forwarding(
		Callable(self, "_stage_editor_no_drag_data"),
		Callable(self, "_stage_editor_can_drop_on_dialog_row").bind(line_index),
		Callable(self, "_stage_editor_drop_on_dialog_row").bind(line_index))


func _stage_editor_make_character_indicator(char_id: String) -> Control:
	if char_id.is_empty():
		var panel := PanelContainer.new()
		panel.custom_minimum_size = Vector2(64, 64)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.tooltip_text = _stage_editor_character_display_name(char_id)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.10, 0.10, 0.13, 0.88)
		style.border_color = Color(0.42, 0.42, 0.50, 0.9)
		style.set_border_width_all(1)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(4)
		panel.add_theme_stylebox_override("panel", style)
		var label := Label.new()
		label.text = _stage_editor_character_display_name(char_id)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 14)
		label.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95, 1.0))
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(label)
		return panel
	var indicator := TextureRect.new()
	indicator.custom_minimum_size = Vector2(64, 64)
	indicator.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	indicator.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	indicator.texture = _stage_editor_character_portrait_texture(char_id)
	indicator.tooltip_text = _stage_editor_character_display_name(char_id)
	return indicator


func _stage_editor_character_portrait_texture(char_id: String) -> Texture2D:
	var entry: Dictionary = _stage_editor_character_by_id.get(char_id, {})
	if entry.is_empty():
		return null
	return entry.get("portrait_texture", null) as Texture2D


func _stage_editor_dialog_line_is_exit(line: DialogLine) -> bool:
	return line != null and line.action == "exit"


func _stage_editor_dialog_line_is_switch_bg(line: DialogLine) -> bool:
	return line != null and line.action == "switch_bg"


func _stage_editor_dialog_line_is_switch_bgm(line: DialogLine) -> bool:
	return line != null and line.action == "switch_bgm"


func _stage_editor_dialog_line_music_summary(line: DialogLine) -> String:
	if line == null:
		return ""
	if line.stop_music:
		return " / Fade out BGM"
	var music_path: String = _stage_editor_dialog_audio_path(line.music)
	if music_path.is_empty():
		return " / BGM no change"
	return " / BGM: %s" % _stage_editor_dialog_music_display_name(music_path)


func _stage_editor_make_row_text_edit(text_value: String, placeholder: String) -> TextEdit:
	var edit := TextEdit.new()
	edit.text = text_value
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(96, 64)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.size_flags_stretch_ratio = 1.0
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	return edit


func _stage_editor_populate_cast_dropdown(option: OptionButton, sequence: DialogSequence, selected_id: String) -> void:
	option.clear()
	if sequence == null:
		option.disabled = true
		return
	_stage_editor_add_option_item(option, _stage_editor_character_display_name(""), "")
	for cast_variant in sequence.cast:
		var char_id: String = String(cast_variant)
		_stage_editor_add_option_item(option, _stage_editor_character_display_name(char_id), char_id)
	option.disabled = option.item_count == 0
	if option.item_count > 0:
		_stage_editor_select_option_value(option, selected_id)


func _stage_editor_dialog_line_button_text(line_index: int, line: DialogLine) -> String:
	var speaker: String = _stage_editor_character_display_name(line.character_id)
	var preview: String = line.text_zh.strip_edges()
	if preview.is_empty():
		preview = line.text_en.strip_edges()
	preview = preview.replace("\n", " ")
	if preview.length() > 42:
		preview = preview.substr(0, 42) + "..."
	return "%02d  %s  %s\n%s" % [line_index + 1, speaker, line.position, preview]


func _refresh_stage_editor_dialog_form() -> void:
	_stage_editor_dialog_refreshing = true
	var line: DialogLine = _stage_editor_get_selected_dialog_line()
	var has_line: bool = line != null
	if _stage_editor_dialog_title_label != null:
		var title: String = "Board"
		if _stage_editor_dialog_target == STAGE_EDITOR_TAB_BEFORE:
			title = "Before Dialog"
		elif _stage_editor_dialog_target == STAGE_EDITOR_TAB_AFTER:
			title = "After Dialog"
		_stage_editor_dialog_title_label.text = title
	_stage_editor_set_dialog_form_enabled(has_line)
	if not has_line:
		_stage_editor_dialog_character_edit.text = ""
		_stage_editor_dialog_emotion_edit.text = ""
		_stage_editor_select_option_value(_stage_editor_dialog_position_option, "left")
		_stage_editor_select_option_value(_stage_editor_dialog_action_option, "none")
		_stage_editor_dialog_shake_check.button_pressed = false
		_stage_editor_dialog_text_zh_edit.text = ""
		_stage_editor_dialog_text_en_edit.text = ""
		_stage_editor_dialog_refreshing = false
		return
	_stage_editor_dialog_character_edit.text = line.character_id
	_stage_editor_dialog_emotion_edit.text = line.emotion
	_stage_editor_select_option_value(_stage_editor_dialog_position_option, line.position)
	_stage_editor_select_option_value(_stage_editor_dialog_action_option, line.action)
	_stage_editor_dialog_shake_check.button_pressed = line.shake
	_stage_editor_dialog_text_zh_edit.text = line.text_zh
	_stage_editor_dialog_text_en_edit.text = line.text_en
	_stage_editor_dialog_refreshing = false


func _stage_editor_set_dialog_form_enabled(enabled: bool) -> void:
	if _stage_editor_dialog_character_edit != null:
		_stage_editor_dialog_character_edit.editable = enabled
	if _stage_editor_dialog_emotion_edit != null:
		_stage_editor_dialog_emotion_edit.editable = enabled
	if _stage_editor_dialog_position_option != null:
		_stage_editor_dialog_position_option.disabled = not enabled
	if _stage_editor_dialog_action_option != null:
		_stage_editor_dialog_action_option.disabled = not enabled
	if _stage_editor_dialog_shake_check != null:
		_stage_editor_dialog_shake_check.disabled = not enabled
	if _stage_editor_dialog_text_zh_edit != null:
		_stage_editor_dialog_text_zh_edit.editable = enabled
	if _stage_editor_dialog_text_en_edit != null:
		_stage_editor_dialog_text_en_edit.editable = enabled


func _stage_editor_select_option_value(option: OptionButton, value: String) -> void:
	if option == null:
		return
	for item_index in option.item_count:
		if String(option.get_item_metadata(item_index)) == value:
			option.select(item_index)
			return
	if option.item_count > 0:
		option.select(0)


func _stage_editor_get_option_value(option: OptionButton) -> String:
	if option == null or option.selected < 0:
		return ""
	return String(option.get_item_metadata(option.selected))


func _stage_editor_no_drag_data(_at_position: Vector2) -> Variant:
	return null


func _stage_editor_no_drop_data(_at_position: Vector2, _data: Variant) -> bool:
	return false


func _stage_editor_ignore_drop_data(_at_position: Vector2, _data: Variant) -> void:
	pass


func _stage_editor_get_cast_drag_data(_at_position: Vector2, source_control: Control, char_id: String) -> Variant:
	if char_id.is_empty():
		return null
	source_control.set_drag_preview(_stage_editor_make_drag_preview(_stage_editor_character_display_name(char_id), _stage_editor_character_portrait_texture(char_id)))
	return {"type": "cast_character", "char_id": char_id}


func _stage_editor_get_row_drag_data(_at_position: Vector2, source_control: Control, line_index: int) -> Variant:
	var line: DialogLine = _stage_editor_get_dialog_line_at(line_index)
	if line == null:
		return null
	var label_text: String = "%02d %s" % [line_index + 1, _stage_editor_character_display_name(line.character_id)]
	if _stage_editor_dialog_line_is_switch_bg(line):
		label_text = "%02d Switch BG" % [line_index + 1]
	elif _stage_editor_dialog_line_is_switch_bgm(line):
		label_text = "%02d Switch BGM" % [line_index + 1]
	source_control.set_drag_preview(_stage_editor_make_drag_preview(label_text, _stage_editor_character_portrait_texture(line.character_id)))
	return {"type": "dialog_row", "line_index": line_index}


func _stage_editor_make_drag_preview(label_text: String, texture: Texture2D = null) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_stage_editor_panel_style(Color(0.08, 0.09, 0.12, 0.96)))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)
	if texture != null:
		var icon := TextureRect.new()
		icon.texture = texture
		icon.custom_minimum_size = Vector2(34, 34)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)
	var label := Label.new()
	label.text = label_text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	row.add_child(label)
	return panel


func _stage_editor_can_drop_on_dialog_row(_at_position: Vector2, data: Variant, _line_index: int) -> bool:
	if not (data is Dictionary):
		return false
	var drag_data: Dictionary = data
	return drag_data.get("type", "") == "cast_character" or drag_data.get("type", "") == "dialog_row"


func _stage_editor_drop_on_dialog_row(_at_position: Vector2, data: Variant, target_index: int) -> void:
	if not (data is Dictionary):
		return
	var drag_data: Dictionary = data
	var drag_type: String = String(drag_data.get("type", ""))
	if drag_type == "cast_character":
		var target_line: DialogLine = _stage_editor_get_dialog_line_at(target_index)
		if _stage_editor_dialog_line_is_switch_bg(target_line) or _stage_editor_dialog_line_is_switch_bgm(target_line):
			return
		_stage_editor_set_dialog_line_character(target_index, String(drag_data.get("char_id", "")))
	elif drag_type == "dialog_row":
		_stage_editor_reorder_dialog_line(int(drag_data.get("line_index", -1)), target_index)


func _stage_editor_can_drop_on_dialog_add_row(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var drag_data: Dictionary = data
	return drag_data.get("type", "") == "cast_character" or drag_data.get("type", "") == "dialog_row"


func _stage_editor_drop_on_dialog_add_row(_at_position: Vector2, data: Variant) -> void:
	if not (data is Dictionary):
		return
	var drag_data: Dictionary = data
	var drag_type: String = String(drag_data.get("type", ""))
	if drag_type == "cast_character":
		_stage_editor_add_dialog_line_for_character(String(drag_data.get("char_id", "")))
	elif drag_type == "dialog_row":
		var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
		if sequence != null:
			_stage_editor_reorder_dialog_line(int(drag_data.get("line_index", -1)), sequence.lines.size())


func _stage_editor_ensure_default_cast(sequence: DialogSequence) -> void:
	if sequence == null or not sequence.cast.is_empty():
		return
	var char_id: String = _stage_editor_first_cast_id(sequence)
	if not char_id.is_empty():
		sequence.cast.append(char_id)


func _stage_editor_get_dialog_line_at(line_index: int) -> DialogLine:
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	if sequence == null or line_index < 0 or line_index >= sequence.lines.size():
		return null
	return sequence.lines[line_index]


func _stage_editor_set_dialog_line_character(line_index: int, char_id: String) -> void:
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	var line: DialogLine = _stage_editor_get_dialog_line_at(line_index)
	if sequence == null or line == null:
		return
	if not char_id.is_empty() and not sequence.cast.has(char_id):
		sequence.cast.append(char_id)
	line.character_id = char_id
	line.emotion = "normal"
	_refresh_stage_editor_dialog_editor()


func _stage_editor_add_dialog_line_for_character(char_id: String) -> void:
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	if sequence == null or char_id.is_empty():
		return
	if not sequence.cast.has(char_id):
		sequence.cast.append(char_id)
	var line: DialogLine = _stage_editor_make_dialog_line()
	line.character_id = char_id
	line.action = "none"
	sequence.lines.append(line)
	_stage_editor_dialog_selected_index = sequence.lines.size() - 1
	_refresh_stage_editor_dialog_editor()


func _stage_editor_add_switch_bg_line(resource_path: String) -> void:
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	if sequence == null or resource_path.is_empty():
		return
	var texture: Texture2D = load(resource_path) as Texture2D
	if texture == null:
		return
	var line := DialogLine.new()
	line.character_id = ""
	line.emotion = "normal"
	line.position = "left"
	line.text_zh = ""
	line.text_en = ""
	line.action = "switch_bg"
	line.shake = false
	line.background = texture
	var insert_index: int = sequence.lines.size()
	sequence.lines.insert(insert_index, line)
	_stage_editor_dialog_selected_index = insert_index
	_refresh_stage_editor_dialog_editor()


func _stage_editor_add_switch_bgm_line(resource_path: String, stop_music: bool = false) -> void:
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	if sequence == null:
		return
	var line := DialogLine.new()
	line.character_id = ""
	line.emotion = "normal"
	line.position = "left"
	line.text_zh = ""
	line.text_en = ""
	line.action = "switch_bgm"
	line.shake = false
	line.stop_music = stop_music
	if not stop_music and not resource_path.is_empty():
		line.music = load(resource_path) as AudioStream
	if not stop_music and line.music == null:
		return
	var insert_index: int = sequence.lines.size()
	sequence.lines.insert(insert_index, line)
	_stage_editor_dialog_selected_index = insert_index
	_refresh_stage_editor_dialog_editor()


func _stage_editor_reorder_dialog_line(source_index: int, target_index: int) -> void:
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	if sequence == null:
		return
	if source_index < 0 or source_index >= sequence.lines.size():
		return
	var clamped_target: int = clampi(target_index, 0, sequence.lines.size())
	if source_index == clamped_target or source_index + 1 == clamped_target:
		return
	var line: DialogLine = sequence.lines[source_index]
	sequence.lines.remove_at(source_index)
	var insert_index: int = clamped_target
	if source_index < clamped_target:
		insert_index -= 1
	insert_index = clampi(insert_index, 0, sequence.lines.size())
	sequence.lines.insert(insert_index, line)
	_stage_editor_dialog_selected_index = insert_index
	_refresh_stage_editor_dialog_editor()


func _on_stage_editor_dialog_add_cast_pressed() -> void:
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	if sequence == null or _stage_editor_dialog_add_cast_option == null:
		return
	var char_id: String = _stage_editor_get_option_value(_stage_editor_dialog_add_cast_option)
	if char_id.is_empty() or sequence.cast.has(char_id):
		return
	sequence.cast.append(char_id)
	_refresh_stage_editor_dialog_editor()


func _on_stage_editor_dialog_remove_cast_pressed(char_id: String) -> void:
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	if sequence == null or _stage_editor_dialog_line_references_cast(sequence, char_id):
		return
	sequence.cast.erase(char_id)
	_refresh_stage_editor_dialog_editor()


func _on_stage_editor_dialog_background_selected(_item_index: int) -> void:
	if _stage_editor_dialog_refreshing:
		return
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	if sequence == null:
		return
	var resource_path: String = _stage_editor_get_option_value(_stage_editor_dialog_background_option)
	if resource_path.is_empty():
		sequence.background = null
		return
	var texture: Texture2D = load(resource_path) as Texture2D
	sequence.background = texture


func _on_stage_editor_dialog_music_selected(_item_index: int) -> void:
	if _stage_editor_dialog_refreshing:
		return
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	if sequence == null:
		return
	var resource_path: String = _stage_editor_get_option_value(_stage_editor_dialog_music_option)
	if resource_path.is_empty():
		sequence.initial_music = null
		return
	sequence.initial_music = load(resource_path) as AudioStream


func _on_stage_editor_dialog_add_switch_bg_selected(_item_index: int, option: OptionButton) -> void:
	var resource_path: String = _stage_editor_get_option_value(option)
	_stage_editor_select_option_value(option, "")
	if resource_path.is_empty():
		return
	_stage_editor_add_switch_bg_line(resource_path)


func _on_stage_editor_dialog_add_switch_bgm_selected(_item_index: int, option: OptionButton) -> void:
	var resource_path: String = _stage_editor_get_option_value(option)
	_stage_editor_select_option_value(option, "")
	if resource_path.is_empty():
		return
	if resource_path == "__stop__":
		_stage_editor_add_switch_bgm_line("", true)
	else:
		_stage_editor_add_switch_bgm_line(resource_path, false)


func _on_stage_editor_dialog_row_switch_bg_selected(_item_index: int, line_index: int, option: OptionButton) -> void:
	var line: DialogLine = _stage_editor_get_dialog_line_at(line_index)
	if line == null:
		return
	var resource_path: String = _stage_editor_get_option_value(option)
	if resource_path.is_empty():
		return
	var texture: Texture2D = load(resource_path) as Texture2D
	if texture == null:
		return
	line.background = texture
	_refresh_stage_editor_dialog_line_list()


func _on_stage_editor_dialog_row_switch_bgm_selected(_item_index: int, line_index: int, option: OptionButton) -> void:
	var line: DialogLine = _stage_editor_get_dialog_line_at(line_index)
	if line == null:
		return
	var resource_path: String = _stage_editor_get_option_value(option)
	line.music = null
	line.stop_music = false
	if resource_path == "__stop__":
		line.stop_music = true
	elif not resource_path.is_empty():
		line.music = load(resource_path) as AudioStream
	_refresh_stage_editor_dialog_line_list()


func _on_stage_editor_dialog_exit_side_toggled(button_pressed: bool) -> void:
	if _stage_editor_dialog_exit_side_option != null:
		_stage_editor_dialog_exit_side_option.text = "Right" if button_pressed else "Left"


func _on_stage_editor_dialog_add_exit_pressed() -> void:
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	if sequence == null:
		return
	_stage_editor_ensure_default_cast(sequence)
	var char_id: String = _stage_editor_get_option_value(_stage_editor_dialog_exit_cast_option)
	if char_id.is_empty():
		char_id = _stage_editor_first_cast_id(sequence)
	if char_id.is_empty():
		return
	var line: DialogLine = _stage_editor_make_dialog_line()
	line.character_id = char_id
	line.position = "right" if _stage_editor_dialog_exit_side_option != null and _stage_editor_dialog_exit_side_option.button_pressed else "left"
	line.action = "exit"
	line.shake = false
	line.text_zh = ""
	line.text_en = ""
	sequence.lines.append(line)
	_stage_editor_dialog_selected_index = sequence.lines.size() - 1
	_refresh_stage_editor_dialog_editor()


func _on_stage_editor_dialog_test_play_pressed() -> void:
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	if sequence == null:
		return
	_stage_editor_ensure_dialog_cast(sequence)
	if _stage_editor_test_dialog != null and is_instance_valid(_stage_editor_test_dialog):
		_stage_editor_test_dialog.queue_free()
	var dialog_control: Control = _DialogBoxScene.instantiate() as Control
	if dialog_control == null:
		return
	_stage_editor_test_dialog = dialog_control
	dialog_control.set("auto_start", false)
	dialog_control.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog_control.z_index = 500
	dialog_control.connect("dialog_finished", Callable(self, "_on_stage_editor_dialog_test_play_finished"))
	$UILayer.add_child(dialog_control)
	dialog_control.call("start", sequence, true)


func _on_stage_editor_dialog_test_play_finished() -> void:
	_stage_editor_test_dialog = null


func _on_stage_editor_dialog_row_speaker_selected(_item_index: int, line_index: int, option: OptionButton) -> void:
	_stage_editor_set_dialog_line_character(line_index, _stage_editor_get_option_value(option))


func _on_stage_editor_dialog_row_side_selected(_item_index: int, line_index: int, option: OptionButton) -> void:
	var line: DialogLine = _stage_editor_get_dialog_line_at(line_index)
	if line != null:
		line.position = _stage_editor_get_option_value(option)


func _on_stage_editor_dialog_row_side_toggled(button_pressed: bool, line_index: int, switch_button: CheckButton) -> void:
	var line: DialogLine = _stage_editor_get_dialog_line_at(line_index)
	if line == null:
		return
	line.position = "right" if button_pressed else "left"
	switch_button.text = "Right" if button_pressed else "Left"


func _on_stage_editor_dialog_row_action_selected(_item_index: int, line_index: int, option: OptionButton) -> void:
	var line: DialogLine = _stage_editor_get_dialog_line_at(line_index)
	if line == null:
		return
	line.action = _stage_editor_get_option_value(option)
	if line.action == "exit":
		line.text_zh = ""
		line.text_en = ""
		line.shake = false
	_refresh_stage_editor_dialog_editor()


func _on_stage_editor_dialog_row_shake_toggled(button_pressed: bool, line_index: int) -> void:
	var line: DialogLine = _stage_editor_get_dialog_line_at(line_index)
	if line != null:
		line.shake = button_pressed


func _on_stage_editor_dialog_row_text_zh_changed(edit: TextEdit, line_index: int) -> void:
	var line: DialogLine = _stage_editor_get_dialog_line_at(line_index)
	if line != null:
		line.text_zh = edit.text


func _on_stage_editor_dialog_row_text_en_changed(edit: TextEdit, line_index: int) -> void:
	var line: DialogLine = _stage_editor_get_dialog_line_at(line_index)
	if line != null:
		line.text_en = edit.text


func _on_stage_editor_dialog_row_duplicate_pressed(line_index: int) -> void:
	_stage_editor_dialog_selected_index = line_index
	_on_stage_editor_dialog_duplicate_line_pressed()


func _on_stage_editor_dialog_row_delete_pressed(line_index: int) -> void:
	_stage_editor_dialog_selected_index = line_index
	_on_stage_editor_dialog_delete_line_pressed()


func _on_stage_editor_dialog_row_move_up_pressed(line_index: int) -> void:
	_stage_editor_dialog_selected_index = line_index
	_on_stage_editor_dialog_move_line_up_pressed()


func _on_stage_editor_dialog_row_move_down_pressed(line_index: int) -> void:
	_stage_editor_dialog_selected_index = line_index
	_on_stage_editor_dialog_move_line_down_pressed()


func _on_stage_editor_dialog_line_selected(line_index: int) -> void:
	_stage_editor_dialog_selected_index = line_index
	_refresh_stage_editor_dialog_editor()


func _on_stage_editor_dialog_add_line_pressed() -> void:
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	if sequence == null:
		return
	_stage_editor_ensure_default_cast(sequence)
	var line: DialogLine = _stage_editor_make_dialog_line()
	sequence.lines.append(line)
	_stage_editor_dialog_selected_index = sequence.lines.size() - 1
	_refresh_stage_editor_dialog_editor()


func _on_stage_editor_dialog_duplicate_line_pressed() -> void:
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	var source: DialogLine = _stage_editor_get_selected_dialog_line()
	if sequence == null or source == null:
		return
	var line: DialogLine = _stage_editor_copy_dialog_line(source)
	var insert_index: int = _stage_editor_dialog_selected_index + 1
	sequence.lines.insert(insert_index, line)
	_stage_editor_dialog_selected_index = insert_index
	_refresh_stage_editor_dialog_editor()


func _on_stage_editor_dialog_delete_line_pressed() -> void:
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	if sequence == null:
		return
	if _stage_editor_dialog_selected_index < 0 or _stage_editor_dialog_selected_index >= sequence.lines.size():
		return
	sequence.lines.remove_at(_stage_editor_dialog_selected_index)
	if sequence.lines.is_empty():
		_stage_editor_dialog_selected_index = -1
	else:
		_stage_editor_dialog_selected_index = mini(_stage_editor_dialog_selected_index, sequence.lines.size() - 1)
	_refresh_stage_editor_dialog_editor()


func _on_stage_editor_dialog_move_line_up_pressed() -> void:
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	if sequence == null or _stage_editor_dialog_selected_index <= 0:
		return
	var line: DialogLine = sequence.lines[_stage_editor_dialog_selected_index]
	sequence.lines.remove_at(_stage_editor_dialog_selected_index)
	_stage_editor_dialog_selected_index -= 1
	sequence.lines.insert(_stage_editor_dialog_selected_index, line)
	_refresh_stage_editor_dialog_editor()


func _on_stage_editor_dialog_move_line_down_pressed() -> void:
	var sequence: DialogSequence = _stage_editor_active_dialog_sequence()
	if sequence == null:
		return
	if _stage_editor_dialog_selected_index < 0 or _stage_editor_dialog_selected_index >= sequence.lines.size() - 1:
		return
	var line: DialogLine = sequence.lines[_stage_editor_dialog_selected_index]
	sequence.lines.remove_at(_stage_editor_dialog_selected_index)
	_stage_editor_dialog_selected_index += 1
	sequence.lines.insert(_stage_editor_dialog_selected_index, line)
	_refresh_stage_editor_dialog_editor()


func _on_stage_editor_dialog_character_changed(new_text: String) -> void:
	if _stage_editor_dialog_refreshing:
		return
	var line: DialogLine = _stage_editor_get_selected_dialog_line()
	if line != null:
		line.character_id = new_text.strip_edges()


func _on_stage_editor_dialog_emotion_changed(new_text: String) -> void:
	if _stage_editor_dialog_refreshing:
		return
	var line: DialogLine = _stage_editor_get_selected_dialog_line()
	if line != null:
		line.emotion = new_text.strip_edges()


func _on_stage_editor_dialog_position_selected(_item_index: int) -> void:
	if _stage_editor_dialog_refreshing:
		return
	var line: DialogLine = _stage_editor_get_selected_dialog_line()
	if line != null:
		line.position = _stage_editor_get_option_value(_stage_editor_dialog_position_option)


func _on_stage_editor_dialog_action_selected(_item_index: int) -> void:
	if _stage_editor_dialog_refreshing:
		return
	var line: DialogLine = _stage_editor_get_selected_dialog_line()
	if line != null:
		line.action = _stage_editor_get_option_value(_stage_editor_dialog_action_option)


func _on_stage_editor_dialog_shake_toggled(button_pressed: bool) -> void:
	if _stage_editor_dialog_refreshing:
		return
	var line: DialogLine = _stage_editor_get_selected_dialog_line()
	if line != null:
		line.shake = button_pressed


func _on_stage_editor_dialog_text_zh_changed() -> void:
	if _stage_editor_dialog_refreshing:
		return
	var line: DialogLine = _stage_editor_get_selected_dialog_line()
	if line != null:
		line.text_zh = _stage_editor_dialog_text_zh_edit.text


func _on_stage_editor_dialog_text_en_changed() -> void:
	if _stage_editor_dialog_refreshing:
		return
	var line: DialogLine = _stage_editor_get_selected_dialog_line()
	if line != null:
		line.text_en = _stage_editor_dialog_text_en_edit.text


func _make_stage_editor_value_button(value: int, label_text: String) -> Button:
	var button := Button.new()
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(58, 58)
	button.tooltip_text = label_text
	button.add_theme_font_size_override("font_size", 13)
	if value == StageData.CELL_HOLE:
		button.text = "X"
		button.add_theme_color_override("font_color", Color(0.78, 0.86, 1.0, 1.0))
	elif value == StageData.CELL_WATER_SWORD:
		button.icon = load(UPPER_GEM_ICON_PATHS[Block.UpperType.WATER_SLASH]) as Texture2D
		button.expand_icon = true
	elif Block.GEM_TEXTURES.has(value):
		var icon_texture: Texture2D = Block.GEM_TEXTURES[value]
		button.icon = icon_texture
		button.expand_icon = true
	else:
		button.text = ""
		button.add_theme_color_override("font_color", Block.COLORS.get(value, Color.WHITE))
	button.pressed.connect(_on_stage_editor_value_selected.bind(value))
	return button


func _make_stage_editor_command_button(label_text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = label_text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(60, 24)
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(callback)
	return button


func _make_stage_editor_mode_button(label_text: String, mode_value: int) -> Button:
	var button := Button.new()
	button.text = label_text
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(62, 24)
	button.add_theme_font_size_override("font_size", 11)
	button.tooltip_text = "Stage mode: %s" % label_text
	button.pressed.connect(_on_stage_editor_mode_button_pressed.bind(mode_value))
	_stage_editor_mode_buttons[mode_value] = button
	return button


func _refresh_stage_editor_mode_buttons() -> void:
	if current_stage == null:
		return
	for mode_key in _stage_editor_mode_buttons.keys():
		var button: Button = _stage_editor_mode_buttons[mode_key]
		if button != null:
			button.set_pressed_no_signal(int(mode_key) == int(current_stage.mode))


func _make_stage_editor_small_button(label_text: String, callback: Callable, min_size: Vector2 = Vector2(34, 32)) -> Button:
	var button := Button.new()
	button.text = label_text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = min_size
	button.add_theme_font_size_override("font_size", 12)
	button.pressed.connect(callback)
	return button


func _make_stage_editor_panel_style(bg_color: Color = Color(0.08, 0.09, 0.12, 0.94)) -> StyleBoxFlat:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = bg_color
	panel_style.border_width_top = 2
	panel_style.border_width_bottom = 2
	panel_style.border_width_left = 2
	panel_style.border_width_right = 2
	panel_style.border_color = Color(0.42, 0.52, 0.72, 0.9)
	panel_style.corner_radius_top_left = 8
	panel_style.corner_radius_top_right = 8
	panel_style.corner_radius_bottom_left = 8
	panel_style.corner_radius_bottom_right = 8
	return panel_style


func _stage_editor_set_control_rect(control: Control, rect: Rect2) -> void:
	control.anchor_left = 0.0
	control.anchor_top = 0.0
	control.anchor_right = 0.0
	control.anchor_bottom = 0.0
	control.offset_left = rect.position.x
	control.offset_top = rect.position.y
	control.offset_right = rect.position.x + rect.size.x
	control.offset_bottom = rect.position.y + rect.size.y


func _stage_editor_load_round_state() -> void:
	_stage_editor_rounds.clear()
	_stage_editor_rounds_init_cd.clear()
	_stage_editor_rounds_enemy_levels.clear()
	_stage_editor_rounds_main_bosses.clear()
	if current_stage == null:
		return
	for round_index in current_stage.rounds.size():
		var source_round: Array = current_stage.rounds[round_index]
		var round_copy: Array = []
		for enemy_variant in source_round:
			if enemy_variant is EnemyData:
				round_copy.append(_stage_editor_make_editable_enemy_copy(enemy_variant as EnemyData))
		_stage_editor_rounds.append(round_copy)

		var cd_copy: Array = []
		var source_cd: Array = []
		if round_index < current_stage.rounds_init_cd.size() and current_stage.rounds_init_cd[round_index] is Array:
			source_cd = current_stage.rounds_init_cd[round_index]
		for enemy_index in round_copy.size():
			var cd_value: int = 0
			if enemy_index < source_cd.size():
				cd_value = maxi(0, int(source_cd[enemy_index]))
			cd_copy.append(cd_value)
		_stage_editor_rounds_init_cd.append(cd_copy)

		var level_copy: Array = []
		var source_levels: Array = []
		if round_index < current_stage.rounds_enemy_levels.size() and current_stage.rounds_enemy_levels[round_index] is Array:
			source_levels = current_stage.rounds_enemy_levels[round_index]
		for enemy_index in round_copy.size():
			var enemy_data: EnemyData = round_copy[enemy_index]
			var level_value: int = enemy_data.enemy_level
			if enemy_index < source_levels.size():
				level_value = int(source_levels[enemy_index])
			level_copy.append(clampi(level_value, 1, 99))
		_stage_editor_rounds_enemy_levels.append(level_copy)

		var boss_copy: Array = []
		var source_bosses: Array = []
		var has_source_bosses: bool = false
		if round_index < current_stage.rounds_main_bosses.size() and current_stage.rounds_main_bosses[round_index] is Array:
			source_bosses = current_stage.rounds_main_bosses[round_index]
			has_source_bosses = true
		for enemy_index in round_copy.size():
			var enemy_data: EnemyData = round_copy[enemy_index]
			var boss_value: bool = false
			if has_source_bosses:
				boss_value = enemy_index < source_bosses.size() and bool(source_bosses[enemy_index])
			else:
				boss_value = enemy_data.is_main_boss
			boss_copy.append(boss_value)
		_stage_editor_rounds_main_bosses.append(boss_copy)
	_stage_editor_normalize_cd_lists()
	_stage_editor_clamp_current_round_index()


func _stage_editor_make_editable_enemy_copy(source: EnemyData) -> EnemyData:
	if source == null:
		return null
	var copy: EnemyData = source.duplicate(true) as EnemyData
	if copy == null:
		return source
	var source_path: String = String(source.get_meta("stage_editor_source_path", source.resource_path)).strip_edges()
	copy.resource_path = ""
	copy.set_meta("stage_editor_source_path", source_path)
	if source.resource_path.is_empty() and copy.stage_extra_loot_table.is_empty():
		for loot: LootItem in copy.loot_table:
			if loot == null:
				continue
			if loot.item_type != ItemDefs.Type.GOLD:
				copy.stage_extra_loot_table.append(loot)
	copy.loot_table = []
	for loot: LootItem in copy.stage_extra_loot_table:
		if loot != null:
			loot.resource_path = ""
	return copy


func _stage_editor_normalize_cd_lists() -> void:
	while _stage_editor_rounds_init_cd.size() < _stage_editor_rounds.size():
		_stage_editor_rounds_init_cd.append([])
	while _stage_editor_rounds_init_cd.size() > _stage_editor_rounds.size():
		_stage_editor_rounds_init_cd.remove_at(_stage_editor_rounds_init_cd.size() - 1)
	while _stage_editor_rounds_enemy_levels.size() < _stage_editor_rounds.size():
		_stage_editor_rounds_enemy_levels.append([])
	while _stage_editor_rounds_enemy_levels.size() > _stage_editor_rounds.size():
		_stage_editor_rounds_enemy_levels.remove_at(_stage_editor_rounds_enemy_levels.size() - 1)
	while _stage_editor_rounds_main_bosses.size() < _stage_editor_rounds.size():
		_stage_editor_rounds_main_bosses.append([])
	while _stage_editor_rounds_main_bosses.size() > _stage_editor_rounds.size():
		_stage_editor_rounds_main_bosses.remove_at(_stage_editor_rounds_main_bosses.size() - 1)
	for round_index in _stage_editor_rounds.size():
		var round_list: Array = _stage_editor_rounds[round_index]
		var cd_list: Array = _stage_editor_rounds_init_cd[round_index]
		while cd_list.size() < round_list.size():
			cd_list.append(0)
		while cd_list.size() > round_list.size():
			cd_list.remove_at(cd_list.size() - 1)
		_stage_editor_rounds_init_cd[round_index] = cd_list
		var level_list: Array = _stage_editor_rounds_enemy_levels[round_index]
		while level_list.size() < round_list.size():
			var enemy_data: EnemyData = round_list[level_list.size()]
			level_list.append(clampi(enemy_data.enemy_level, 1, 99))
		while level_list.size() > round_list.size():
			level_list.remove_at(level_list.size() - 1)
		for enemy_index in level_list.size():
			level_list[enemy_index] = clampi(int(level_list[enemy_index]), 1, 99)
		_stage_editor_rounds_enemy_levels[round_index] = level_list
		var boss_list: Array = _stage_editor_rounds_main_bosses[round_index]
		while boss_list.size() < round_list.size():
			boss_list.append(false)
		while boss_list.size() > round_list.size():
			boss_list.remove_at(boss_list.size() - 1)
		for enemy_index in boss_list.size():
			boss_list[enemy_index] = bool(boss_list[enemy_index])
		_stage_editor_rounds_main_bosses[round_index] = boss_list


func _stage_editor_clamp_current_round_index() -> void:
	if _stage_editor_rounds.is_empty():
		_stage_editor_current_round_index = 0
		return
	_stage_editor_current_round_index = clampi(_stage_editor_current_round_index, 0, _stage_editor_rounds.size() - 1)


func _build_stage_editor_enemy_area() -> void:
	if _stage_editor_enemy_area_panel != null:
		return
	_stage_editor_enemy_area_panel = ColorRect.new()
	_stage_editor_enemy_area_panel.name = "StageEditorEnemyArea"
	_stage_editor_enemy_area_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	(_stage_editor_enemy_area_panel as ColorRect).color = Color(0.02, 0.025, 0.04, 0.82)
	$UILayer.add_child(_stage_editor_enemy_area_panel)

	_stage_editor_prev_round_button = _make_stage_editor_small_button("<-", _on_stage_editor_prev_round_pressed, Vector2(42, 30))
	_stage_editor_enemy_area_panel.add_child(_stage_editor_prev_round_button)

	_stage_editor_enemy_area_round_label = Label.new()
	_stage_editor_enemy_area_round_label.text = "Round"
	_stage_editor_enemy_area_round_label.add_theme_font_size_override("font_size", 13)
	_stage_editor_enemy_area_round_label.add_theme_color_override("font_color", Color.WHITE)
	_stage_editor_enemy_area_round_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_editor_enemy_area_panel.add_child(_stage_editor_enemy_area_round_label)

	_stage_editor_next_round_button = _make_stage_editor_small_button("->", _on_stage_editor_next_round_pressed, Vector2(42, 30))
	_stage_editor_enemy_area_panel.add_child(_stage_editor_next_round_button)
	_stage_editor_add_round_button = _make_stage_editor_small_button("+", _on_stage_editor_add_round_from_area_pressed, Vector2(32, 30))
	_stage_editor_enemy_area_panel.add_child(_stage_editor_add_round_button)
	_stage_editor_remove_round_button = _make_stage_editor_small_button("-", _on_stage_editor_remove_current_round_pressed, Vector2(32, 30))
	_stage_editor_enemy_area_panel.add_child(_stage_editor_remove_round_button)

	_stage_editor_enemy_area_slots = Control.new()
	_stage_editor_enemy_area_slots.name = "EnemySlots"
	_stage_editor_enemy_area_slots.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_editor_enemy_area_slots.clip_contents = true
	_stage_editor_enemy_area_panel.add_child(_stage_editor_enemy_area_slots)

	_layout_stage_editor_enemy_area()
	_refresh_stage_editor_enemy_area()


func _layout_stage_editor_enemy_area() -> void:
	if _stage_editor_enemy_area_panel == null:
		return
	var viewport_size: Vector2 = ViewportUtils.get_size()
	var insets: Vector4 = ViewportUtils.get_safe_insets()
	var panel_height := 184.0
	var panel_top: float = maxf(44.0 + insets.x, board.position.y - panel_height - 6.0)
	var panel_width: float = maxf(120.0, viewport_size.x - 24.0)
	_stage_editor_set_control_rect(_stage_editor_enemy_area_panel, Rect2(12.0, panel_top, panel_width, panel_height))
	_stage_editor_set_control_rect(_stage_editor_prev_round_button, Rect2(8.0, 8.0, 38.0, 28.0))
	_stage_editor_set_control_rect(_stage_editor_remove_round_button, Rect2(panel_width - 40.0, 8.0, 32.0, 28.0))
	_stage_editor_set_control_rect(_stage_editor_add_round_button, Rect2(panel_width - 76.0, 8.0, 32.0, 28.0))
	_stage_editor_set_control_rect(_stage_editor_next_round_button, Rect2(panel_width - 120.0, 8.0, 38.0, 28.0))
	_stage_editor_set_control_rect(_stage_editor_enemy_area_round_label, Rect2(50.0, 8.0, maxf(80.0, panel_width - 176.0), 28.0))
	_stage_editor_set_control_rect(_stage_editor_enemy_area_slots, Rect2(8.0, 42.0, panel_width - 16.0, 136.0))


func _stage_editor_is_normal_mode() -> bool:
	return current_stage == null or int(current_stage.mode) == int(StageData.Mode.NORMAL)


func _stage_editor_is_valid_goal_target(type_value: int) -> bool:
	return STAGE_EDITOR_GOAL_TARGET_TYPES.has(type_value)


func _stage_editor_goal_target_label(type_value: int) -> String:
	return _stage_editor_type_name(type_value).to_upper()


func _stage_editor_sync_enemy_area_mode_controls() -> void:
	var normal_mode: bool = _stage_editor_is_normal_mode()
	for button in [
		_stage_editor_prev_round_button,
		_stage_editor_next_round_button,
		_stage_editor_add_round_button,
		_stage_editor_remove_round_button,
	]:
		if button != null:
			button.visible = normal_mode
	if _stage_editor_rounds_container != null:
		_stage_editor_rounds_container.visible = normal_mode and _stage_editor_rounds_expanded
	if _stage_editor_enemy_picker_panel != null and not normal_mode:
		_stage_editor_enemy_picker_panel.visible = false


func _refresh_stage_editor_no_enemy_area(title_text: String, detail_text: String) -> void:
	if _stage_editor_enemy_area_round_label != null:
		_stage_editor_enemy_area_round_label.text = title_text
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	_stage_editor_enemy_area_slots.add_child(box)
	_stage_editor_set_control_rect(box, Rect2(0.0, 4.0, 360.0, 72.0))

	var title := Label.new()
	title.text = title_text
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(title)

	var detail := Label.new()
	detail.text = detail_text
	detail.add_theme_font_size_override("font_size", 13)
	detail.add_theme_color_override("font_color", Color(0.78, 0.86, 0.95, 1.0))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(detail)


func _refresh_stage_editor_goal_area() -> void:
	if current_stage == null:
		return
	current_stage.puzzle_goal_kind = StageData.PuzzleGoalKind.BREAK_COUNT
	if not _stage_editor_is_valid_goal_target(int(current_stage.puzzle_goal_target_type)):
		current_stage.puzzle_goal_target_type = Block.Type.RED
	if _stage_editor_enemy_area_round_label != null:
		_stage_editor_enemy_area_round_label.text = "Puzzle Goal"

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _make_stage_editor_panel_style(Color(0.11, 0.12, 0.18, 0.94)))
	_stage_editor_enemy_area_slots.add_child(panel)
	_stage_editor_set_control_rect(panel, Rect2(0.0, 0.0, 540.0, 78.0))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var icon := TextureRect.new()
	icon.texture = Block.GEM_TEXTURES.get(int(current_stage.puzzle_goal_target_type), null)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(44, 44)
	row.add_child(icon)

	var target_box := VBoxContainer.new()
	target_box.add_theme_constant_override("separation", 2)
	target_box.custom_minimum_size = Vector2(132, 0)
	row.add_child(target_box)

	var target_label := Label.new()
	target_label.text = "Target"
	target_label.add_theme_font_size_override("font_size", 11)
	target_label.add_theme_color_override("font_color", Color(0.76, 0.84, 0.95, 1.0))
	target_box.add_child(target_label)

	_stage_editor_goal_target_option = OptionButton.new()
	_stage_editor_goal_target_option.focus_mode = Control.FOCUS_NONE
	_stage_editor_goal_target_option.custom_minimum_size = Vector2(122, 28)
	var selected_index := 0
	for type_value: int in STAGE_EDITOR_GOAL_TARGET_TYPES:
		var item_index: int = _stage_editor_goal_target_option.item_count
		_stage_editor_goal_target_option.add_item(_stage_editor_goal_target_label(type_value))
		_stage_editor_goal_target_option.set_item_metadata(item_index, type_value)
		if type_value == int(current_stage.puzzle_goal_target_type):
			selected_index = item_index
	_stage_editor_goal_target_option.select(selected_index)
	_stage_editor_goal_target_option.item_selected.connect(_on_stage_editor_goal_target_selected)
	target_box.add_child(_stage_editor_goal_target_option)

	var count_box := VBoxContainer.new()
	count_box.add_theme_constant_override("separation", 2)
	count_box.custom_minimum_size = Vector2(96, 0)
	row.add_child(count_box)

	var count_label := Label.new()
	count_label.text = "Required"
	count_label.add_theme_font_size_override("font_size", 11)
	count_label.add_theme_color_override("font_color", Color(0.76, 0.84, 0.95, 1.0))
	count_box.add_child(count_label)

	_stage_editor_goal_count_spin = SpinBox.new()
	_stage_editor_goal_count_spin.min_value = 0
	_stage_editor_goal_count_spin.max_value = 999
	_stage_editor_goal_count_spin.step = 1
	_stage_editor_goal_count_spin.value = maxi(0, current_stage.puzzle_goal_required_count)
	_stage_editor_goal_count_spin.custom_minimum_size = Vector2(92, 28)
	_stage_editor_goal_count_spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_editor_goal_count_spin.value_changed.connect(_on_stage_editor_goal_count_changed)
	count_box.add_child(_stage_editor_goal_count_spin)

	var turn_box := VBoxContainer.new()
	turn_box.add_theme_constant_override("separation", 2)
	turn_box.custom_minimum_size = Vector2(96, 0)
	row.add_child(turn_box)

	var turn_label := Label.new()
	turn_label.text = "Turn Left"
	turn_label.add_theme_font_size_override("font_size", 11)
	turn_label.add_theme_color_override("font_color", Color(0.76, 0.84, 0.95, 1.0))
	turn_box.add_child(turn_label)

	_stage_editor_goal_turn_spin = SpinBox.new()
	_stage_editor_goal_turn_spin.min_value = 1
	_stage_editor_goal_turn_spin.max_value = 999
	_stage_editor_goal_turn_spin.step = 1
	_stage_editor_goal_turn_spin.value = maxi(1, current_stage.puzzle_turn_limit)
	_stage_editor_goal_turn_spin.custom_minimum_size = Vector2(92, 28)
	_stage_editor_goal_turn_spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_editor_goal_turn_spin.value_changed.connect(_on_stage_editor_goal_turn_changed)
	turn_box.add_child(_stage_editor_goal_turn_spin)

	var hint := Label.new()
	hint.text = "Break Count"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.95, 0.82, 0.42, 1.0))
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hint)


func _refresh_stage_editor_enemy_area() -> void:
	if _stage_editor_enemy_area_slots == null:
		return
	_stage_editor_sync_enemy_area_mode_controls()
	_stage_editor_goal_target_option = null
	_stage_editor_goal_count_spin = null
	_stage_editor_goal_turn_spin = null
	for child in _stage_editor_enemy_area_slots.get_children():
		_stage_editor_enemy_area_slots.remove_child(child)
		child.queue_free()

	if current_stage != null and current_stage.mode == StageData.Mode.PUZZLE:
		_refresh_stage_editor_goal_area()
		return

	if current_stage != null and current_stage.mode == StageData.Mode.ESCAPE:
		_refresh_stage_editor_no_enemy_area("Escape Mode", "No monster waves. Escape distance decides victory.")
		return

	_stage_editor_normalize_cd_lists()
	_stage_editor_clamp_current_round_index()

	if _stage_editor_rounds.is_empty():
		if _stage_editor_enemy_area_round_label != null:
			_stage_editor_enemy_area_round_label.text = "No rounds"
		var add_round_slot: Control = _make_stage_editor_add_round_slot()
		_stage_editor_enemy_area_slots.add_child(add_round_slot)
		_stage_editor_set_control_rect(add_round_slot, Rect2(0.0, 0.0, 116.0, 78.0))
		return

	var round_index: int = _stage_editor_current_round_index
	var round_list: Array = _stage_editor_rounds[round_index]
	if _stage_editor_enemy_area_round_label != null:
		_stage_editor_enemy_area_round_label.text = "Round %d / %d  (%d enemies)" % [round_index + 1, _stage_editor_rounds.size(), round_list.size()]
	var card_width := 180.0
	var card_height := 132.0
	var gap := 8.0
	var x := 0.0
	for enemy_index in round_list.size():
		var card: Control = _make_stage_editor_enemy_area_card(round_index, enemy_index)
		_stage_editor_enemy_area_slots.add_child(card)
		_stage_editor_set_control_rect(card, Rect2(x, 0.0, card_width, card_height))
		x += card_width + gap
	var add_enemy_slot: Control = _make_stage_editor_add_enemy_slot(round_index)
	_stage_editor_enemy_area_slots.add_child(add_enemy_slot)
	_stage_editor_set_control_rect(add_enemy_slot, Rect2(x, 27.0, 78.0, 78.0))


func _make_stage_editor_add_round_slot() -> Control:
	var button := Button.new()
	button.text = "+ Round"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(116, 84)
	button.add_theme_font_size_override("font_size", 14)
	button.pressed.connect(_on_stage_editor_add_round_from_area_pressed)
	return button


func _make_stage_editor_add_enemy_slot(round_index: int) -> Control:
	var button := Button.new()
	button.text = "+"
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(78, 78)
	button.add_theme_font_size_override("font_size", 30)
	button.tooltip_text = "Add enemy"
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.46)
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_color = Color(0.78, 0.86, 1.0, 0.72)
	style.corner_radius_top_left = 39
	style.corner_radius_top_right = 39
	style.corner_radius_bottom_left = 39
	style.corner_radius_bottom_right = 39
	button.add_theme_stylebox_override("normal", style)
	button.add_theme_stylebox_override("hover", style)
	button.add_theme_stylebox_override("pressed", style)
	button.pressed.connect(_on_stage_editor_add_enemy_pressed.bind(round_index))
	return button


func _make_stage_editor_enemy_area_card(round_index: int, enemy_index: int) -> Control:
	var enemy_list: Array = _stage_editor_rounds[round_index]
	var cd_list: Array = _stage_editor_rounds_init_cd[round_index]
	var level_list: Array = _stage_editor_rounds_enemy_levels[round_index]
	var boss_list: Array = _stage_editor_rounds_main_bosses[round_index]
	var enemy_data: EnemyData = enemy_list[enemy_index]
	var cd_value: int = int(cd_list[enemy_index])
	var level_value: int = int(level_list[enemy_index])
	var is_boss_spawn: bool = bool(boss_list[enemy_index])

	var card := ColorRect.new()
	card.color = Color(0.06, 0.07, 0.10, 0.9)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var portrait := TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = enemy_data.portrait_texture
	card.add_child(portrait)
	_stage_editor_set_control_rect(portrait, Rect2(4.0, 4.0, 42.0, 42.0))

	var name_label := Label.new()
	name_label.text = enemy_data.get_display_name()
	var source_path: String = String(enemy_data.get_meta("stage_editor_source_path", enemy_data.resource_path))
	name_label.tooltip_text = source_path if not source_path.is_empty() else enemy_data.get_display_name()
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(name_label)
	_stage_editor_set_control_rect(name_label, Rect2(50.0, 4.0, 98.0, 24.0))

	var remove_button: Button = _make_stage_editor_small_button("X", _on_stage_editor_remove_enemy_pressed.bind(round_index, enemy_index), Vector2(22, 22))
	card.add_child(remove_button)
	_stage_editor_set_control_rect(remove_button, Rect2(154.0, 4.0, 22.0, 22.0))

	var level_label := Label.new()
	level_label.text = "Lv%d" % level_value
	level_label.add_theme_font_size_override("font_size", 10)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(level_label)
	_stage_editor_set_control_rect(level_label, Rect2(50.0, 28.0, 46.0, 20.0))

	var boss_button: Button = _make_stage_editor_small_button("B", _on_stage_editor_boss_toggle_pressed.bind(round_index, enemy_index), Vector2(22, 22))
	boss_button.tooltip_text = "Main boss spawn"
	boss_button.modulate = Color(1.0, 0.86, 0.32) if is_boss_spawn else Color(0.72, 0.76, 0.86)
	card.add_child(boss_button)
	_stage_editor_set_control_rect(boss_button, Rect2(154.0, 28.0, 22.0, 22.0))

	var minus_button: Button = _make_stage_editor_small_button("-", _on_stage_editor_cd_delta_pressed.bind(round_index, enemy_index, -1), Vector2(22, 22))
	card.add_child(minus_button)
	_stage_editor_set_control_rect(minus_button, Rect2(4.0, 52.0, 22.0, 22.0))
	var cd_label := Label.new()
	cd_label.text = "CD %s" % ("Auto" if cd_value <= 0 else str(cd_value))
	cd_label.add_theme_font_size_override("font_size", 10)
	cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(cd_label)
	_stage_editor_set_control_rect(cd_label, Rect2(28.0, 52.0, 46.0, 22.0))
	var plus_button: Button = _make_stage_editor_small_button("+", _on_stage_editor_cd_delta_pressed.bind(round_index, enemy_index, 1), Vector2(22, 22))
	card.add_child(plus_button)
	_stage_editor_set_control_rect(plus_button, Rect2(76.0, 52.0, 22.0, 22.0))
	var auto_button: Button = _make_stage_editor_small_button("A", _on_stage_editor_cd_auto_pressed.bind(round_index, enemy_index), Vector2(22, 22))
	card.add_child(auto_button)
	_stage_editor_set_control_rect(auto_button, Rect2(100.0, 52.0, 22.0, 22.0))

	var loot_entry: LootItem = _stage_editor_get_primary_loot(enemy_data)
	var loot_caption := Label.new()
	loot_caption.text = "Loot"
	loot_caption.add_theme_font_size_override("font_size", 9)
	loot_caption.add_theme_color_override("font_color", Color(0.78, 0.86, 0.95, 1.0))
	card.add_child(loot_caption)
	_stage_editor_set_control_rect(loot_caption, Rect2(4.0, 78.0, 36.0, 16.0))

	var loot_option := OptionButton.new()
	loot_option.focus_mode = Control.FOCUS_NONE
	loot_option.add_theme_font_size_override("font_size", 9)
	_stage_editor_make_compact_option_button(loot_option)
	var selected_loot_type: Variant = null
	if loot_entry != null:
		selected_loot_type = loot_entry.item_type
	_stage_editor_populate_item_option(loot_option, selected_loot_type, true, false)
	loot_option.item_selected.connect(_on_stage_editor_enemy_loot_item_selected.bind(round_index, enemy_index, loot_option))
	card.add_child(loot_option)
	_stage_editor_set_control_rect(loot_option, Rect2(38.0, 76.0, 76.0, 24.0))

	var chance_spin := SpinBox.new()
	chance_spin.min_value = 0
	chance_spin.max_value = 100
	chance_spin.step = 5
	chance_spin.value = roundf((loot_entry.drop_chance if loot_entry != null else 0.0) * 100.0)
	chance_spin.suffix = "%"
	chance_spin.add_theme_font_size_override("font_size", 9)
	chance_spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	chance_spin.value_changed.connect(_on_stage_editor_enemy_loot_chance_changed.bind(round_index, enemy_index))
	card.add_child(chance_spin)
	_stage_editor_set_control_rect(chance_spin, Rect2(116.0, 76.0, 60.0, 24.0))

	var count_spin := SpinBox.new()
	count_spin.min_value = 1
	count_spin.max_value = 999
	count_spin.step = 1
	count_spin.value = _stage_editor_get_loot_count(loot_entry)
	count_spin.add_theme_font_size_override("font_size", 9)
	count_spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_spin.value_changed.connect(_on_stage_editor_enemy_loot_count_changed.bind(round_index, enemy_index))
	card.add_child(count_spin)
	_stage_editor_set_control_rect(count_spin, Rect2(116.0, 102.0, 60.0, 24.0))

	var count_caption := Label.new()
	count_caption.text = "Count"
	count_caption.add_theme_font_size_override("font_size", 9)
	count_caption.add_theme_color_override("font_color", Color(0.78, 0.86, 0.95, 1.0))
	card.add_child(count_caption)
	_stage_editor_set_control_rect(count_caption, Rect2(76.0, 104.0, 38.0, 18.0))
	return card


func _build_stage_editor_rounds_panel() -> void:
	if _stage_editor_rounds_container != null:
		return
	if _stage_editor_root_box == null:
		return
	_stage_editor_rounds_container = VBoxContainer.new()
	_stage_editor_rounds_container.name = "StageEditorRoundsInline"
	_stage_editor_rounds_container.add_theme_constant_override("separation", 6)
	_stage_editor_rounds_container.visible = _stage_editor_is_normal_mode() and _stage_editor_rounds_expanded
	_stage_editor_rounds_container.custom_minimum_size = Vector2(0, 154)
	_stage_editor_rounds_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_editor_root_box.add_child(_stage_editor_rounds_container)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	_stage_editor_rounds_container.add_child(header_row)

	var title := Label.new()
	title.text = "Rounds"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)

	header_row.add_child(_make_stage_editor_small_button("Add Round", _on_stage_editor_add_round_pressed, Vector2(78, 28)))

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 142)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stage_editor_rounds_container.add_child(scroll)

	_stage_editor_rounds_list = VBoxContainer.new()
	_stage_editor_rounds_list.add_theme_constant_override("separation", 6)
	_stage_editor_rounds_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_stage_editor_rounds_list)

	_refresh_stage_editor_rounds_panel()


func _build_stage_editor_enemy_picker_panel() -> void:
	if _stage_editor_enemy_picker_panel != null:
		return
	_stage_editor_enemy_picker_panel = PanelContainer.new()
	_stage_editor_enemy_picker_panel.name = "StageEditorEnemyPicker"
	_stage_editor_enemy_picker_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage_editor_enemy_picker_panel.visible = false
	_stage_editor_enemy_picker_panel.z_index = 160
	_stage_editor_enemy_picker_panel.add_theme_stylebox_override("panel", _make_stage_editor_panel_style(Color(0.04, 0.05, 0.08, 0.98)))
	$UILayer.add_child(_stage_editor_enemy_picker_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_stage_editor_enemy_picker_panel.add_child(margin)

	var root_box := VBoxContainer.new()
	root_box.add_theme_constant_override("separation", 8)
	margin.add_child(root_box)

	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
	root_box.add_child(header_row)

	var title := Label.new()
	title.text = "Add Enemy"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_row.add_child(title)

	var level_label := Label.new()
	level_label.text = "Lv"
	level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	level_label.add_theme_font_size_override("font_size", 13)
	level_label.add_theme_color_override("font_color", Color(0.86, 0.92, 1.0))
	header_row.add_child(level_label)

	_stage_editor_enemy_picker_level_spin = SpinBox.new()
	_stage_editor_enemy_picker_level_spin.min_value = 1
	_stage_editor_enemy_picker_level_spin.max_value = 99
	_stage_editor_enemy_picker_level_spin.step = 1
	_stage_editor_enemy_picker_level_spin.value = 1
	_stage_editor_enemy_picker_level_spin.custom_minimum_size = Vector2(82, 32)
	_stage_editor_enemy_picker_level_spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage_editor_enemy_picker_level_spin.tooltip_text = "Spawn level for the enemy you add."
	header_row.add_child(_stage_editor_enemy_picker_level_spin)

	header_row.add_child(_make_stage_editor_small_button("Close", _on_stage_editor_enemy_picker_close_pressed, Vector2(64, 32)))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(scroll)

	_stage_editor_enemy_picker_grid = GridContainer.new()
	_stage_editor_enemy_picker_grid.columns = 2
	_stage_editor_enemy_picker_grid.add_theme_constant_override("h_separation", 6)
	_stage_editor_enemy_picker_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_stage_editor_enemy_picker_grid)
	_layout_stage_editor_enemy_picker_panel()


func _refresh_stage_editor_rounds_panel() -> void:
	if _stage_editor_rounds_container != null:
		_stage_editor_rounds_container.visible = _stage_editor_is_normal_mode() and _stage_editor_rounds_expanded
	if _stage_editor_rounds_list == null:
		return
	if not _stage_editor_is_normal_mode():
		return
	_stage_editor_normalize_cd_lists()
	for child in _stage_editor_rounds_list.get_children():
		_stage_editor_rounds_list.remove_child(child)
		child.queue_free()

	if _stage_editor_rounds.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No rounds yet. Add a round to begin."
		empty_label.add_theme_color_override("font_color", Color(0.8, 0.86, 0.95, 1.0))
		_stage_editor_rounds_list.add_child(empty_label)
		return

	for round_index in _stage_editor_rounds.size():
		_stage_editor_rounds_list.add_child(_make_stage_editor_round_section(round_index))


func _make_stage_editor_round_section(round_index: int) -> Control:
	var round_list: Array = _stage_editor_rounds[round_index]
	var section := PanelContainer.new()
	section.add_theme_stylebox_override("panel", _make_stage_editor_panel_style(Color(0.12, 0.13, 0.18, 0.92)))
	var row_count: int = maxi(1, round_list.size())
	section.custom_minimum_size = Vector2(0, 72 + row_count * 128)
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	section.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)

	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 4)
	box.add_child(header)

	var title := Label.new()
	title.text = "Round %d  (%d enemies)" % [round_index + 1, round_list.size()]
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var round_buttons := HBoxContainer.new()
	round_buttons.add_theme_constant_override("separation", 6)
	header.add_child(round_buttons)
	round_buttons.add_child(_make_stage_editor_small_button("Add Enemy", _on_stage_editor_add_enemy_pressed.bind(round_index), Vector2(92, 28)))
	round_buttons.add_child(_make_stage_editor_small_button("Remove Round", _on_stage_editor_remove_round_pressed.bind(round_index), Vector2(102, 28)))

	if round_list.is_empty():
		var empty_label := Label.new()
		empty_label.text = "Empty round (add at least one enemy before saving)."
		empty_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.55, 1.0))
		box.add_child(empty_label)
		return section

	for enemy_index in round_list.size():
		box.add_child(_make_stage_editor_enemy_row(round_index, enemy_index))
	return section


func _make_stage_editor_enemy_row(round_index: int, enemy_index: int) -> Control:
	var enemy_list: Array = _stage_editor_rounds[round_index]
	var cd_list: Array = _stage_editor_rounds_init_cd[round_index]
	var level_list: Array = _stage_editor_rounds_enemy_levels[round_index]
	var boss_list: Array = _stage_editor_rounds_main_bosses[round_index]
	var enemy_data: EnemyData = enemy_list[enemy_index]
	var level_value: int = int(level_list[enemy_index])
	var is_boss_spawn: bool = bool(boss_list[enemy_index])
	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size = Vector2(0, 122)
	row_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_panel.add_theme_stylebox_override("panel", _make_stage_editor_panel_style(Color(0.06, 0.07, 0.11, 0.98)))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 6)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 6)
	margin.add_theme_constant_override("margin_bottom", 5)
	row_panel.add_child(margin)

	var row_box := VBoxContainer.new()
	row_box.add_theme_constant_override("separation", 4)
	row_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(row_box)

	var info_row := HBoxContainer.new()
	info_row.add_theme_constant_override("separation", 6)
	info_row.custom_minimum_size = Vector2(0, 48)
	info_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_box.add_child(info_row)

	var portrait_box := PanelContainer.new()
	portrait_box.custom_minimum_size = Vector2(46, 46)
	portrait_box.add_theme_stylebox_override("panel", _make_stage_editor_panel_style(Color(0.02, 0.025, 0.04, 1.0)))
	info_row.add_child(portrait_box)

	var portrait := TextureRect.new()
	portrait.custom_minimum_size = Vector2(46, 46)
	portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture = enemy_data.portrait_texture
	portrait_box.add_child(portrait)

	var name_label := Label.new()
	var source_path: String = String(enemy_data.get_meta("stage_editor_source_path", enemy_data.resource_path))
	var source_name: String = source_path.get_file() if not source_path.is_empty() else "inline"
	name_label.text = enemy_data.get_display_name()
	name_label.tooltip_text = source_name
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.9, 0.94, 1.0, 1.0))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_row.add_child(name_label)
	info_row.add_child(_make_stage_editor_small_button("X", _on_stage_editor_remove_enemy_pressed.bind(round_index, enemy_index), Vector2(30, 30)))

	var cd_value: int = int(cd_list[enemy_index])
	var control_row := HBoxContainer.new()
	control_row.add_theme_constant_override("separation", 6)
	control_row.custom_minimum_size = Vector2(0, 30)
	control_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_box.add_child(control_row)

	var cd_label := Label.new()
	cd_label.text = "CD %s" % ("Auto" if cd_value <= 0 else str(cd_value))
	cd_label.custom_minimum_size = Vector2(58, 0)
	cd_label.add_theme_font_size_override("font_size", 11)
	cd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	control_row.add_child(cd_label)
	control_row.add_child(_make_stage_editor_small_button("-", _on_stage_editor_cd_delta_pressed.bind(round_index, enemy_index, -1), Vector2(34, 30)))
	control_row.add_child(_make_stage_editor_small_button("+", _on_stage_editor_cd_delta_pressed.bind(round_index, enemy_index, 1), Vector2(34, 30)))
	control_row.add_child(_make_stage_editor_small_button("Auto", _on_stage_editor_cd_auto_pressed.bind(round_index, enemy_index), Vector2(54, 30)))
	var level_label := Label.new()
	level_label.text = "Lv %d" % level_value
	level_label.custom_minimum_size = Vector2(52, 0)
	level_label.add_theme_font_size_override("font_size", 11)
	level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	control_row.add_child(level_label)
	control_row.add_child(_make_stage_editor_small_button("-", _on_stage_editor_level_delta_pressed.bind(round_index, enemy_index, -1), Vector2(34, 30)))
	control_row.add_child(_make_stage_editor_small_button("+", _on_stage_editor_level_delta_pressed.bind(round_index, enemy_index, 1), Vector2(34, 30)))
	var boss_button: Button = _make_stage_editor_small_button("Boss", _on_stage_editor_boss_toggle_pressed.bind(round_index, enemy_index), Vector2(58, 30))
	boss_button.tooltip_text = "Use this spawn as the main boss"
	boss_button.modulate = Color(1.0, 0.86, 0.32) if is_boss_spawn else Color(0.72, 0.76, 0.86)
	control_row.add_child(boss_button)

	var loot_row := HBoxContainer.new()
	loot_row.add_theme_constant_override("separation", 6)
	loot_row.custom_minimum_size = Vector2(0, 30)
	loot_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_box.add_child(loot_row)

	var loot_label := Label.new()
	loot_label.text = "Loot"
	loot_label.custom_minimum_size = Vector2(42, 0)
	loot_label.add_theme_font_size_override("font_size", 11)
	loot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loot_row.add_child(loot_label)

	var loot_entry: LootItem = _stage_editor_get_primary_loot(enemy_data)
	var loot_option := OptionButton.new()
	loot_option.focus_mode = Control.FOCUS_NONE
	loot_option.custom_minimum_size = Vector2(92, 28)
	loot_option.add_theme_font_size_override("font_size", 10)
	_stage_editor_make_compact_option_button(loot_option)
	var selected_loot_type: Variant = null
	if loot_entry != null:
		selected_loot_type = loot_entry.item_type
	_stage_editor_populate_item_option(loot_option, selected_loot_type, true, false)
	loot_option.item_selected.connect(_on_stage_editor_enemy_loot_item_selected.bind(round_index, enemy_index, loot_option))
	loot_row.add_child(loot_option)

	var chance_spin := SpinBox.new()
	chance_spin.min_value = 0
	chance_spin.max_value = 100
	chance_spin.step = 5
	chance_spin.value = roundf((loot_entry.drop_chance if loot_entry != null else 0.0) * 100.0)
	chance_spin.suffix = "%"
	chance_spin.custom_minimum_size = Vector2(76, 28)
	chance_spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	chance_spin.value_changed.connect(_on_stage_editor_enemy_loot_chance_changed.bind(round_index, enemy_index))
	loot_row.add_child(chance_spin)

	var count_label := Label.new()
	count_label.text = "Count"
	count_label.add_theme_font_size_override("font_size", 11)
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	loot_row.add_child(count_label)

	var count_spin := SpinBox.new()
	count_spin.min_value = 1
	count_spin.max_value = 999
	count_spin.step = 1
	count_spin.value = _stage_editor_get_loot_count(loot_entry)
	count_spin.custom_minimum_size = Vector2(70, 28)
	count_spin.get_line_edit().alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_spin.value_changed.connect(_on_stage_editor_enemy_loot_count_changed.bind(round_index, enemy_index))
	loot_row.add_child(count_spin)
	return row_panel


func _stage_editor_populate_item_option(option: OptionButton, selected_type: Variant, include_none: bool = false, include_gold: bool = true) -> void:
	if option == null:
		return
	option.clear()
	if include_none:
		_stage_editor_add_option_item(option, "None", "")
	if include_gold:
		_stage_editor_add_option_item(option, ItemDefs.get_display_name(ItemDefs.Type.GOLD), str(int(ItemDefs.Type.GOLD)))
	_stage_editor_add_option_item(option, ItemDefs.get_display_name(ItemDefs.Type.SAPPHIRE), str(int(ItemDefs.Type.SAPPHIRE)))
	var selected_value: String = ""
	if selected_type != null:
		selected_value = str(int(selected_type))
	_stage_editor_select_option_value(option, selected_value)


func _stage_editor_get_primary_loot(enemy_data: EnemyData) -> LootItem:
	if enemy_data == null:
		return null
	for loot: LootItem in enemy_data.stage_extra_loot_table:
		if loot != null:
			return loot
	return null


func _stage_editor_get_loot_count(loot: LootItem) -> int:
	if loot == null:
		return 1
	return maxi(1, maxi(int(loot.amount_min), int(loot.amount_max)))


func _stage_editor_set_enemy_primary_loot(enemy_data: EnemyData, loot: LootItem) -> void:
	if enemy_data == null:
		return
	var loot_table: Array[LootItem] = []
	if loot != null:
		loot.resource_path = ""
		loot_table.append(loot)
	enemy_data.stage_extra_loot_table = loot_table


func _stage_editor_ensure_primary_loot(enemy_data: EnemyData, fallback_type: ItemDefs.Type = ItemDefs.Type.SAPPHIRE) -> LootItem:
	var loot: LootItem = _stage_editor_get_primary_loot(enemy_data)
	if loot != null:
		return loot
	loot = LootItem.new()
	loot.item_type = fallback_type
	loot.amount_min = 1
	loot.amount_max = 1
	loot.drop_chance = 1.0
	_stage_editor_set_enemy_primary_loot(enemy_data, loot)
	return loot


func _on_stage_editor_enemy_loot_item_selected(_item_index: int, round_index: int, enemy_index: int, option: OptionButton) -> void:
	if not _stage_editor_has_enemy_slot(round_index, enemy_index):
		return
	var enemy_list: Array = _stage_editor_rounds[round_index]
	var enemy_data: EnemyData = enemy_list[enemy_index]
	var value: String = _stage_editor_get_option_value(option)
	if value.is_empty():
		_stage_editor_set_enemy_primary_loot(enemy_data, null)
	else:
		var loot: LootItem = _stage_editor_ensure_primary_loot(enemy_data, int(value) as ItemDefs.Type)
		loot.item_type = int(value) as ItemDefs.Type
		loot.amount_min = _stage_editor_get_loot_count(loot)
		loot.amount_max = loot.amount_min
	_stage_editor_rounds[round_index] = enemy_list
	_refresh_stage_editor_rounds_panel()
	_refresh_stage_editor_enemy_area()
	_set_stage_editor_status("Enemy loot updated")


func _on_stage_editor_enemy_loot_chance_changed(value: float, round_index: int, enemy_index: int) -> void:
	if not _stage_editor_has_enemy_slot(round_index, enemy_index):
		return
	var enemy_list: Array = _stage_editor_rounds[round_index]
	var enemy_data: EnemyData = enemy_list[enemy_index]
	var had_loot := _stage_editor_get_primary_loot(enemy_data) != null
	var loot: LootItem = _stage_editor_ensure_primary_loot(enemy_data)
	loot.drop_chance = clampf(value / 100.0, 0.0, 1.0)
	_stage_editor_rounds[round_index] = enemy_list
	if not had_loot:
		_refresh_stage_editor_rounds_panel()
		_refresh_stage_editor_enemy_area()
	_set_stage_editor_status("Enemy loot chance: %d%%" % int(round(value)))


func _on_stage_editor_enemy_loot_count_changed(value: float, round_index: int, enemy_index: int) -> void:
	if not _stage_editor_has_enemy_slot(round_index, enemy_index):
		return
	var enemy_list: Array = _stage_editor_rounds[round_index]
	var enemy_data: EnemyData = enemy_list[enemy_index]
	var had_loot := _stage_editor_get_primary_loot(enemy_data) != null
	var loot: LootItem = _stage_editor_ensure_primary_loot(enemy_data)
	var count: int = maxi(1, int(round(value)))
	loot.amount_min = count
	loot.amount_max = count
	_stage_editor_rounds[round_index] = enemy_list
	if not had_loot:
		_refresh_stage_editor_rounds_panel()
		_refresh_stage_editor_enemy_area()
	_set_stage_editor_status("Enemy loot count: %d" % count)


func _layout_stage_editor_enemy_picker_panel() -> void:
	if _stage_editor_enemy_picker_panel == null:
		return
	var viewport_size: Vector2 = ViewportUtils.get_size()
	var panel_width: float = minf(620.0, viewport_size.x - 40.0)
	var panel_height: float = minf(720.0, viewport_size.y - 120.0)
	if _stage_editor_enemy_picker_grid != null:
		_stage_editor_enemy_picker_grid.columns = 1 if panel_width < 520.0 else 2
	var panel_left: float = (viewport_size.x - panel_width) * 0.5
	var panel_top: float = (viewport_size.y - panel_height) * 0.5
	_stage_editor_enemy_picker_panel.anchor_left = 0.0
	_stage_editor_enemy_picker_panel.anchor_top = 0.0
	_stage_editor_enemy_picker_panel.anchor_right = 0.0
	_stage_editor_enemy_picker_panel.anchor_bottom = 0.0
	_stage_editor_enemy_picker_panel.offset_left = panel_left
	_stage_editor_enemy_picker_panel.offset_right = panel_left + panel_width
	_stage_editor_enemy_picker_panel.offset_top = panel_top
	_stage_editor_enemy_picker_panel.offset_bottom = panel_top + panel_height


func _on_stage_editor_rounds_pressed() -> void:
	_refresh_stage_editor_enemy_area()
	_set_stage_editor_status("Enemy area refreshed")
	_layout_stage_editor_ui()


func _on_stage_editor_prev_round_pressed() -> void:
	if _stage_editor_rounds.is_empty():
		return
	_stage_editor_current_round_index = posmod(_stage_editor_current_round_index - 1, _stage_editor_rounds.size())
	_refresh_stage_editor_enemy_area()


func _on_stage_editor_next_round_pressed() -> void:
	if _stage_editor_rounds.is_empty():
		return
	_stage_editor_current_round_index = posmod(_stage_editor_current_round_index + 1, _stage_editor_rounds.size())
	_refresh_stage_editor_enemy_area()


func _on_stage_editor_add_round_from_area_pressed() -> void:
	var insert_index: int = _stage_editor_current_round_index + 1 if not _stage_editor_rounds.is_empty() else 0
	_stage_editor_rounds.insert(insert_index, [])
	_stage_editor_rounds_init_cd.insert(insert_index, [])
	_stage_editor_rounds_enemy_levels.insert(insert_index, [])
	_stage_editor_rounds_main_bosses.insert(insert_index, [])
	_stage_editor_current_round_index = insert_index
	_refresh_stage_editor_enemy_area()
	_set_stage_editor_status("Round added")


func _on_stage_editor_remove_current_round_pressed() -> void:
	if _stage_editor_rounds.is_empty():
		return
	_stage_editor_rounds.remove_at(_stage_editor_current_round_index)
	_stage_editor_rounds_init_cd.remove_at(_stage_editor_current_round_index)
	_stage_editor_rounds_enemy_levels.remove_at(_stage_editor_current_round_index)
	_stage_editor_rounds_main_bosses.remove_at(_stage_editor_current_round_index)
	_stage_editor_clamp_current_round_index()
	_refresh_stage_editor_enemy_area()
	_set_stage_editor_status("Round removed")


func _on_stage_editor_rounds_close_pressed() -> void:
	_stage_editor_rounds_expanded = true
	if _stage_editor_rounds_container != null:
		_stage_editor_rounds_container.visible = _stage_editor_is_normal_mode()
		_refresh_stage_editor_rounds_panel()
	_layout_stage_editor_ui()


func _stage_editor_default_picker_level(round_index: int) -> int:
	if round_index < 0 or round_index >= _stage_editor_rounds_enemy_levels.size():
		return 1
	var level_list: Array = _stage_editor_rounds_enemy_levels[round_index]
	if level_list.is_empty():
		return 1
	return clampi(int(level_list[level_list.size() - 1]), 1, 99)


func _on_stage_editor_add_round_pressed() -> void:
	_stage_editor_rounds.append([])
	_stage_editor_rounds_init_cd.append([])
	_stage_editor_rounds_enemy_levels.append([])
	_stage_editor_rounds_main_bosses.append([])
	_stage_editor_current_round_index = _stage_editor_rounds.size() - 1
	_refresh_stage_editor_rounds_panel()
	_refresh_stage_editor_enemy_area()
	_set_stage_editor_status("Round added")
	_layout_stage_editor_ui()


func _on_stage_editor_remove_round_pressed(round_index: int) -> void:
	if round_index < 0 or round_index >= _stage_editor_rounds.size():
		return
	_stage_editor_rounds.remove_at(round_index)
	_stage_editor_rounds_init_cd.remove_at(round_index)
	_stage_editor_rounds_enemy_levels.remove_at(round_index)
	_stage_editor_rounds_main_bosses.remove_at(round_index)
	_stage_editor_clamp_current_round_index()
	_refresh_stage_editor_rounds_panel()
	_refresh_stage_editor_enemy_area()
	_set_stage_editor_status("Round removed")
	_layout_stage_editor_ui()


func _on_stage_editor_add_enemy_pressed(round_index: int) -> void:
	if round_index < 0 or round_index >= _stage_editor_rounds.size():
		return
	_stage_editor_enemy_picker_round_index = round_index
	if _stage_editor_enemy_picker_panel == null:
		_build_stage_editor_enemy_picker_panel()
	if _stage_editor_enemy_picker_level_spin != null:
		_stage_editor_enemy_picker_level_spin.value = _stage_editor_default_picker_level(round_index)
	_stage_editor_available_enemies = _stage_editor_load_available_enemies()
	_refresh_stage_editor_enemy_picker()
	if _stage_editor_enemy_picker_panel != null:
		_stage_editor_enemy_picker_panel.visible = true
	_set_stage_editor_status("Pick an enemy")


func _on_stage_editor_remove_enemy_pressed(round_index: int, enemy_index: int) -> void:
	if not _stage_editor_has_enemy_slot(round_index, enemy_index):
		return
	var enemy_list: Array = _stage_editor_rounds[round_index]
	var cd_list: Array = _stage_editor_rounds_init_cd[round_index]
	var level_list: Array = _stage_editor_rounds_enemy_levels[round_index]
	var boss_list: Array = _stage_editor_rounds_main_bosses[round_index]
	enemy_list.remove_at(enemy_index)
	cd_list.remove_at(enemy_index)
	level_list.remove_at(enemy_index)
	boss_list.remove_at(enemy_index)
	_stage_editor_rounds[round_index] = enemy_list
	_stage_editor_rounds_init_cd[round_index] = cd_list
	_stage_editor_rounds_enemy_levels[round_index] = level_list
	_stage_editor_rounds_main_bosses[round_index] = boss_list
	_refresh_stage_editor_rounds_panel()
	_refresh_stage_editor_enemy_area()
	_set_stage_editor_status("Enemy removed")
	_layout_stage_editor_ui()


func _on_stage_editor_cd_delta_pressed(round_index: int, enemy_index: int, delta: int) -> void:
	if not _stage_editor_has_enemy_slot(round_index, enemy_index):
		return
	var cd_list: Array = _stage_editor_rounds_init_cd[round_index]
	cd_list[enemy_index] = maxi(0, int(cd_list[enemy_index]) + delta)
	_stage_editor_rounds_init_cd[round_index] = cd_list
	_refresh_stage_editor_rounds_panel()
	_refresh_stage_editor_enemy_area()
	_layout_stage_editor_ui()


func _on_stage_editor_cd_auto_pressed(round_index: int, enemy_index: int) -> void:
	if not _stage_editor_has_enemy_slot(round_index, enemy_index):
		return
	var cd_list: Array = _stage_editor_rounds_init_cd[round_index]
	cd_list[enemy_index] = 0
	_stage_editor_rounds_init_cd[round_index] = cd_list
	_refresh_stage_editor_rounds_panel()
	_refresh_stage_editor_enemy_area()
	_layout_stage_editor_ui()


func _on_stage_editor_level_delta_pressed(round_index: int, enemy_index: int, delta: int) -> void:
	if not _stage_editor_has_enemy_slot(round_index, enemy_index):
		return
	var level_list: Array = _stage_editor_rounds_enemy_levels[round_index]
	level_list[enemy_index] = clampi(int(level_list[enemy_index]) + delta, 1, 99)
	_stage_editor_rounds_enemy_levels[round_index] = level_list
	_refresh_stage_editor_rounds_panel()
	_refresh_stage_editor_enemy_area()
	_layout_stage_editor_ui()


func _on_stage_editor_boss_toggle_pressed(round_index: int, enemy_index: int) -> void:
	if not _stage_editor_has_enemy_slot(round_index, enemy_index):
		return
	var boss_list: Array = _stage_editor_rounds_main_bosses[round_index]
	var next_value: bool = not bool(boss_list[enemy_index])
	for i in boss_list.size():
		boss_list[i] = false
	boss_list[enemy_index] = next_value
	_stage_editor_rounds_main_bosses[round_index] = boss_list
	_refresh_stage_editor_rounds_panel()
	_refresh_stage_editor_enemy_area()
	_layout_stage_editor_ui()


func _stage_editor_has_enemy_slot(round_index: int, enemy_index: int) -> bool:
	if round_index < 0 or round_index >= _stage_editor_rounds.size():
		return false
	var enemy_list: Array = _stage_editor_rounds[round_index]
	return enemy_index >= 0 and enemy_index < enemy_list.size()


func _on_stage_editor_enemy_picker_close_pressed() -> void:
	if _stage_editor_enemy_picker_panel != null:
		_stage_editor_enemy_picker_panel.visible = false
	_stage_editor_enemy_picker_round_index = -1


func _refresh_stage_editor_enemy_picker() -> void:
	if _stage_editor_enemy_picker_grid == null:
		return
	for child in _stage_editor_enemy_picker_grid.get_children():
		_stage_editor_enemy_picker_grid.remove_child(child)
		child.queue_free()
	if _stage_editor_available_enemies.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No EnemyData resources found in res://enemies."
		empty_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.55, 1.0))
		_stage_editor_enemy_picker_grid.add_child(empty_label)
		return
	for entry: Dictionary in _stage_editor_available_enemies:
		_stage_editor_enemy_picker_grid.add_child(_make_stage_editor_enemy_picker_button(entry))


func _make_stage_editor_enemy_picker_button(entry: Dictionary) -> Button:
	var enemy_data: EnemyData = entry.get("data", null) as EnemyData
	var resource_path: String = String(entry.get("path", ""))
	var display_name: String = String(entry.get("name", ""))
	if enemy_data != null:
		display_name = enemy_data.get_display_name()
	if display_name.is_empty():
		display_name = resource_path.get_file()
	var button := Button.new()
	button.text = "%s\n%s" % [display_name, resource_path.get_file()]
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(250, 72)
	button.add_theme_font_size_override("font_size", 11)
	if enemy_data != null and enemy_data.portrait_texture != null:
		button.icon = enemy_data.portrait_texture
		button.expand_icon = true
	button.tooltip_text = resource_path
	button.pressed.connect(_on_stage_editor_enemy_entry_picked.bind(entry))
	return button


func _on_stage_editor_enemy_entry_picked(entry: Dictionary) -> void:
	var enemy_data: EnemyData = entry.get("data", null) as EnemyData
	if enemy_data == null:
		_set_stage_editor_status("Enemy load failed", false)
		return
	var spawn_level: int = enemy_data.enemy_level
	if _stage_editor_enemy_picker_level_spin != null:
		spawn_level = int(_stage_editor_enemy_picker_level_spin.value)
	_on_stage_editor_enemy_picked(enemy_data, spawn_level)


func _on_stage_editor_enemy_picked(enemy_data: EnemyData, spawn_level: int = -1) -> void:
	var round_index: int = _stage_editor_enemy_picker_round_index
	if round_index < 0 or round_index >= _stage_editor_rounds.size():
		return
	var editable_enemy: EnemyData = _stage_editor_make_editable_enemy_copy(enemy_data)
	if editable_enemy == null:
		return
	var enemy_list: Array = _stage_editor_rounds[round_index]
	var cd_list: Array = _stage_editor_rounds_init_cd[round_index]
	var level_list: Array = _stage_editor_rounds_enemy_levels[round_index]
	var boss_list: Array = _stage_editor_rounds_main_bosses[round_index]
	enemy_list.append(editable_enemy)
	cd_list.append(0)
	var level_value: int = spawn_level if spawn_level > 0 else editable_enemy.enemy_level
	level_list.append(clampi(level_value, 1, 99))
	boss_list.append(false)
	_stage_editor_rounds[round_index] = enemy_list
	_stage_editor_rounds_init_cd[round_index] = cd_list
	_stage_editor_rounds_enemy_levels[round_index] = level_list
	_stage_editor_rounds_main_bosses[round_index] = boss_list
	if _stage_editor_enemy_picker_panel != null:
		_stage_editor_enemy_picker_panel.visible = false
	_stage_editor_enemy_picker_round_index = -1
	_refresh_stage_editor_rounds_panel()
	_stage_editor_current_round_index = round_index
	_refresh_stage_editor_enemy_area()
	_set_stage_editor_status("Enemy added")
	_layout_stage_editor_ui()


func _stage_editor_load_available_enemies() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	_stage_editor_collect_enemy_resources(STAGE_EDITOR_ENEMY_ROOT, results)
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: String = String(a.get("label", ""))
		var right: String = String(b.get("label", ""))
		return left.naturalnocasecmp_to(right) < 0
	)
	return results


func _stage_editor_collect_enemy_resources(dir_path: String, results: Array[Dictionary]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and (file_name.ends_with(".tres") or file_name.ends_with(".res")):
			var resource_path: String = "%s/%s" % [dir_path, file_name]
			var resource: Resource = load(resource_path)
			if resource is EnemyData:
				var enemy_data: EnemyData = resource as EnemyData
				results.append({
					"data": enemy_data,
					"path": resource_path,
					"label": "%s %s" % [enemy_data.get_display_name(), resource_path],
				})
		file_name = dir.get_next()
	dir.list_dir_end()


func _stage_editor_collect_manifest_enemies(results: Array[Dictionary]) -> void:
	if not FileAccess.file_exists(STAGE_EDITOR_GENERATED_MANIFEST):
		return
	var file := FileAccess.open(STAGE_EDITOR_GENERATED_MANIFEST, FileAccess.READ)
	if file == null:
		return
	var manifest_text: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(manifest_text)
	if not (parsed is Dictionary):
		return
	var manifest: Dictionary = parsed
	var entries: Array = manifest.get("entries", [])
	for entry_variant in entries:
		if not (entry_variant is Dictionary):
			continue
		var entry: Dictionary = entry_variant
		if not bool(entry.get("enabled", true)):
			continue
		var image_path: String = String(entry.get("image_path", ""))
		if image_path.is_empty():
			continue
		var display_name: String = String(entry.get("display_name", "")).strip_edges()
		if display_name.is_empty():
			display_name = String(entry.get("provisional_id", image_path.get_file())).strip_edges()
		results.append({
			"manifest_entry": entry,
			"name": display_name,
			"path": image_path,
			"label": "%s %s" % [display_name, image_path],
		})


func _stage_editor_make_manifest_enemy(entry: Dictionary) -> EnemyData:
	var image_path: String = String(entry.get("image_path", ""))
	if image_path.is_empty():
		return null
	var texture_resource: Resource = load(image_path)
	var enemy_data := EnemyData.new()
	var display_name: String = String(entry.get("display_name", "")).strip_edges()
	if display_name.is_empty():
		display_name = String(entry.get("provisional_id", image_path.get_file())).strip_edges()
	enemy_data.enemy_name = display_name
	enemy_data.enemy_name_en = display_name
	enemy_data.max_hp = EnemyData.clamp_hp_percent(int(entry.get("max_hp", EnemyData.HP_PERCENT_MIN)))
	enemy_data.element = int(entry.get("element", Block.Type.DARK)) as Block.Type
	if texture_resource is Texture2D:
		enemy_data.portrait_texture = texture_resource as Texture2D
	var portrait_values: Array = entry.get("portrait_color", [])
	if portrait_values.size() >= 4:
		enemy_data.portrait_color = Color(float(portrait_values[0]), float(portrait_values[1]), float(portrait_values[2]), float(portrait_values[3]))
	var action_values: Array = entry.get("action_pattern", [])
	var action_pattern: Array[EnemyData.ActionType] = []
	for action_variant in action_values:
		var action_value: EnemyData.ActionType = int(action_variant) as EnemyData.ActionType
		action_pattern.append(action_value)
	if action_pattern.is_empty():
		action_pattern.append(EnemyData.ActionType.ATTACK_15)
	var action_percent_values: Array = entry.get("action_percents", [])
	var action_percents: Array[int] = []
	for action_index in action_pattern.size():
		var percent_value: int = EnemyData.ATTACK_PERCENT_DEFAULT
		if action_index < action_percent_values.size():
			percent_value = int(action_percent_values[action_index])
		action_percents.append(EnemyData.clamp_attack_percent(percent_value))
	var action_count_values: Array = entry.get("action_counts", [])
	var action_counts: Array[int] = []
	for action_index in action_pattern.size():
		var count_value: int = EnemyData.ACTION_COUNT_DEFAULT
		if action_index < action_count_values.size():
			count_value = int(action_count_values[action_index])
		action_counts.append(EnemyData.clamp_action_count(count_value))
	var rest_count: int = maxi(0, int(entry.get("attack_interval", 0)))
	var timed_pattern: Array[EnemyData.ActionType] = []
	var timed_percents: Array[int] = []
	var timed_counts: Array[int] = []
	for _rest_index in rest_count:
		timed_pattern.append(EnemyData.ActionType.REST)
		timed_percents.append(EnemyData.ATTACK_PERCENT_DEFAULT)
		timed_counts.append(EnemyData.ACTION_COUNT_DEFAULT)
	for action_index in action_pattern.size():
		timed_pattern.append(action_pattern[action_index])
		timed_percents.append(action_percents[action_index])
		timed_counts.append(action_counts[action_index])
	enemy_data.action_pattern = timed_pattern
	enemy_data.action_percents = timed_percents
	enemy_data.action_counts = timed_counts
	var auto_character_path: String = String(entry.get("auto_character", "")).strip_edges()
	if not auto_character_path.is_empty():
		var auto_character_resource: Resource = load(auto_character_path)
		if auto_character_resource is CharacterData:
			enemy_data.auto_character = auto_character_resource as CharacterData
	enemy_data.auto_gem_atk_power = maxf(float(entry.get("auto_gem_atk_power", enemy_data.auto_gem_atk_power)), 0.0)
	enemy_data.auto_use_max_skill_upgrades = bool(entry.get("auto_use_max_skill_upgrades", enemy_data.auto_use_max_skill_upgrades))
	var loot := LootItem.new()
	loot.amount_min = int(entry.get("loot_min", 1))
	loot.amount_max = int(entry.get("loot_max", 1))
	loot.drop_chance = 1.0
	var loot_table: Array[LootItem] = []
	loot_table.append(loot)
	enemy_data.loot_table = loot_table
	return enemy_data


func _stage_editor_type_name(value: int) -> String:
	match value:
		Block.Type.RED:
			return "Red"
		Block.Type.BLUE:
			return "Blue"
		Block.Type.GREEN:
			return "Green"
		Block.Type.LIGHT:
			return "Light"
		Block.Type.DARK:
			return "Dark"
		Block.Type.PLANK:
			return "Plank"
		Block.Type.ROCK:
			return "Rock"
		Block.Type.WOOD_STRUCTURE:
			return "woodStructure"
		Block.Type.PUZZLE_KEY:
			return "Puzzle Key"
		StageData.CELL_WATER_SWORD:
			return "Water Sword"
		StageData.CELL_HOLE:
			return "Hole"
		_:
			return "Gem"


func _stage_editor_distribution_label(value: int) -> String:
	match value:
		Block.Type.RED:
			return "R"
		Block.Type.BLUE:
			return "B"
		Block.Type.GREEN:
			return "G"
		Block.Type.LIGHT:
			return "L"
		Block.Type.DARK:
			return "D"
		_:
			return _stage_editor_type_name(value).substr(0, 1)


func _on_stage_editor_value_selected(value: int) -> void:
	_stage_editor_selected_value = value
	board.set_edit_paint_value(value)
	_refresh_stage_editor_value_buttons()
	_set_stage_editor_status(_stage_editor_type_name(value))


func _refresh_stage_editor_value_buttons() -> void:
	for key in _stage_editor_value_buttons.keys():
		var button: Button = _stage_editor_value_buttons[key]
		button.set_pressed_no_signal(int(key) == _stage_editor_selected_value)


func _refresh_stage_editor_area_panel() -> void:
	if current_stage != null:
		_stage_editor_selected_area = StageData.normalize_area(current_stage.area)
	else:
		_stage_editor_selected_area = StageData.DEFAULT_AREA
	if _stage_editor_area_option != null:
		for item_index in _stage_editor_area_option.item_count:
			var item_area: String = String(_stage_editor_area_option.get_item_metadata(item_index))
			if item_area == _stage_editor_selected_area:
				_stage_editor_area_option.select(item_index)
				break
	if _stage_editor_area_spot_preview != null:
		var spot_path: String = StageData.get_stage_spot_path(_stage_editor_selected_area)
		_stage_editor_area_spot_preview.texture = load(spot_path) as Texture2D
		_stage_editor_area_spot_preview.tooltip_text = spot_path
	if _stage_editor_bg_override_option != null:
		var selected_override: String = current_stage.battle_background_override_path if current_stage != null else ""
		_stage_editor_populate_dialog_background_selector(_stage_editor_bg_override_option, selected_override, "NULL")
	if _stage_editor_music_override_option != null:
		var selected_music_override: String = current_stage.battle_music_override_path if current_stage != null else ""
		_stage_editor_populate_dialog_music_selector(_stage_editor_music_override_option, selected_music_override, "NULL", false)
	if _stage_editor_boss_bgm_option != null:
		var selected_boss_bgm: String = _stage_editor_dialog_audio_path(current_stage.boss_bgm) if current_stage != null else ""
		_stage_editor_populate_dialog_music_selector(_stage_editor_boss_bgm_option, selected_boss_bgm, "NULL", false)
	if _stage_editor_stretch_bg_check != null:
		_stage_editor_stretch_bg_check.set_pressed_no_signal(current_stage != null and current_stage.stretch_battle_background)
	if current_stage != null:
		for key in _stage_editor_distribution_spins.keys():
			var spin: SpinBox = _stage_editor_distribution_spins[key]
			spin.set_value_no_signal(current_stage.get_element_weight_for_type(int(key)))
		for key in _stage_editor_drop_start_spins.keys():
			var drop_edit: LineEdit = _stage_editor_drop_start_spins[key]
			drop_edit.text = str(_stage_editor_get_drop_start_value(int(key)))
	_refresh_stage_editor_reward_controls()


func _stage_editor_get_drop_start_value(column_index: int) -> int:
	if current_stage == null or column_index < 0 or column_index >= current_stage.columns:
		return 0
	if column_index >= current_stage.drop_start_rows.size():
		return 0
	return clampi(int(current_stage.drop_start_rows[column_index]), 0, current_stage.rows - 1)


func _refresh_stage_editor_reward_controls() -> void:
	if _stage_editor_reward_item_option != null:
		_stage_editor_reward_item_option.clear()
		_stage_editor_add_option_item(_stage_editor_reward_item_option, "None", "")
		_stage_editor_add_option_item(_stage_editor_reward_item_option, ItemDefs.get_display_name(ItemDefs.Type.GOLD), str(int(ItemDefs.Type.GOLD)))
		_stage_editor_add_option_item(_stage_editor_reward_item_option, ItemDefs.get_display_name(ItemDefs.Type.SAPPHIRE), str(int(ItemDefs.Type.SAPPHIRE)))
		var selected_item: String = ""
		if current_stage != null and current_stage.one_time_reward_item_amount > 0:
			selected_item = str(int(current_stage.one_time_reward_item_type))
		_stage_editor_select_option_value(_stage_editor_reward_item_option, selected_item)

	if _stage_editor_reward_amount_edit != null:
		var amount: int = current_stage.one_time_reward_item_amount if current_stage != null else 0
		_stage_editor_reward_amount_edit.text = str(maxi(0, amount))

	if _stage_editor_reward_character_option != null:
		_stage_editor_reward_character_option.clear()
		_stage_editor_add_option_item(_stage_editor_reward_character_option, "No Clear Character", "")
		for entry: Dictionary in _stage_editor_character_catalog:
			_stage_editor_add_option_item(
				_stage_editor_reward_character_option,
				String(entry.get("name", "Character")),
				String(entry.get("resource_path", ""))
			)
		var selected_character: String = ""
		if current_stage != null and current_stage.one_time_reward_character != null:
			selected_character = current_stage.one_time_reward_character.resource_path
		_stage_editor_select_option_value(_stage_editor_reward_character_option, selected_character)


func _on_stage_editor_reward_changed(_item_index: int) -> void:
	if current_stage == null:
		return
	current_stage.one_time_reward_item_type = _stage_editor_get_reward_item_type_from_ui()
	current_stage.one_time_reward_item_amount = _stage_editor_get_reward_amount_from_ui()
	current_stage.one_time_reward_character = _stage_editor_get_reward_character_from_ui()
	if _stage_editor_reward_amount_edit != null:
		_stage_editor_reward_amount_edit.text = str(current_stage.one_time_reward_item_amount)
	_set_stage_editor_status("Reward updated")


func _stage_editor_get_reward_item_type_from_ui() -> ItemDefs.Type:
	if _stage_editor_reward_item_option == null:
		return ItemDefs.Type.GOLD
	var value: String = _stage_editor_get_option_value(_stage_editor_reward_item_option)
	if value.is_empty():
		return ItemDefs.Type.GOLD
	return int(value)


func _stage_editor_get_reward_amount_from_ui() -> int:
	if _stage_editor_reward_amount_edit == null:
		return 0
	if _stage_editor_reward_item_option != null and _stage_editor_get_option_value(_stage_editor_reward_item_option).is_empty():
		return 0
	return maxi(0, int(_stage_editor_reward_amount_edit.text.to_int()))


func _stage_editor_get_reward_character_from_ui() -> CharacterData:
	if _stage_editor_reward_character_option == null:
		return null
	var path: String = _stage_editor_get_option_value(_stage_editor_reward_character_option)
	if path.is_empty():
		return null
	var resource: Resource = load(path)
	return resource as CharacterData


func _on_stage_editor_distribution_changed(_value: float, _type_value: int) -> void:
	if current_stage == null:
		return
	var distribution_types: Array[Block.Type] = _stage_editor_get_distribution_allowed_types_snapshot()
	current_stage.allowed_types = distribution_types
	current_stage.element_weights = _stage_editor_get_element_weights_snapshot(distribution_types)
	_set_stage_editor_status("Distribution updated")


func _on_stage_editor_drop_start_changed(_value: float, _column_index: int) -> void:
	if current_stage != null:
		current_stage.drop_start_rows = _stage_editor_get_drop_start_rows_snapshot()
	if board != null:
		board.queue_redraw()
	_set_stage_editor_status("Drop start updated")


func _on_stage_editor_drop_start_step(column_index: int, delta: int) -> void:
	_stage_editor_set_drop_start_value(column_index, _stage_editor_get_drop_start_value_from_ui(column_index) + delta)


func _on_stage_editor_drop_start_text_submitted(_text: String, column_index: int) -> void:
	_stage_editor_set_drop_start_value(column_index, _stage_editor_get_drop_start_value_from_ui(column_index))


func _on_stage_editor_drop_start_focus_exited(column_index: int) -> void:
	_stage_editor_set_drop_start_value(column_index, _stage_editor_get_drop_start_value_from_ui(column_index))


func _stage_editor_set_drop_start_value(column_index: int, value: int) -> void:
	if current_stage == null:
		return
	var clamped_value: int = clampi(value, 0, maxi(0, current_stage.rows - 1))
	if _stage_editor_drop_start_spins.has(column_index):
		var drop_edit: LineEdit = _stage_editor_drop_start_spins[column_index]
		drop_edit.text = str(clamped_value)
	current_stage.drop_start_rows = _stage_editor_get_drop_start_rows_snapshot()
	if board != null:
		board.queue_redraw()
	_set_stage_editor_status("Drop start updated")


func _on_stage_editor_reset_drop_pressed() -> void:
	for key in _stage_editor_drop_start_spins.keys():
		var drop_edit: LineEdit = _stage_editor_drop_start_spins[key]
		drop_edit.text = "0"
	if current_stage != null:
		current_stage.drop_start_rows = _stage_editor_get_drop_start_rows_snapshot()
	if board != null:
		board.queue_redraw()
	_set_stage_editor_status("Drop starts reset")


func _on_stage_editor_area_selected(item_index: int) -> void:
	if _stage_editor_area_option == null:
		return
	var item_area: String = String(_stage_editor_area_option.get_item_metadata(item_index))
	_stage_editor_selected_area = StageData.normalize_area(item_area)
	if current_stage != null:
		current_stage.area = _stage_editor_selected_area
	_refresh_stage_editor_area_panel()
	_apply_stage_background()
	_layout_board()
	_layout_stage_editor_enemy_area()
	_layout_stage_editor_ui()
	_set_stage_editor_status("Area: %s" % _stage_editor_selected_area)


func _on_stage_editor_bg_override_selected(_item_index: int) -> void:
	if _stage_editor_bg_override_option == null:
		return
	var selected_path: String = _stage_editor_get_option_value(_stage_editor_bg_override_option)
	if current_stage != null:
		current_stage.battle_background_override_path = selected_path
	_apply_stage_background()
	_layout_board()
	_set_stage_editor_status("BG Override: %s" % ("NULL" if selected_path.is_empty() else selected_path.get_file()))


func _on_stage_editor_music_override_selected(_item_index: int) -> void:
	if _stage_editor_music_override_option == null:
		return
	var selected_path: String = _stage_editor_get_option_value(_stage_editor_music_override_option)
	if current_stage != null:
		current_stage.battle_music_override_path = selected_path
	GameState.fade_out_bgm(0.15)
	_play_bgm()
	_set_stage_editor_status("Music Override: %s" % ("NULL" if selected_path.is_empty() else selected_path.get_file()))


func _on_stage_editor_boss_bgm_selected(_item_index: int) -> void:
	if _stage_editor_boss_bgm_option == null:
		return
	var selected_path: String = _stage_editor_get_option_value(_stage_editor_boss_bgm_option)
	if current_stage != null:
		if selected_path.is_empty():
			current_stage.boss_bgm = null
		else:
			current_stage.boss_bgm = load(selected_path) as AudioStream
	_set_stage_editor_status("Boss BGM: %s" % ("NULL" if selected_path.is_empty() else selected_path.get_file()))


func _on_stage_editor_stretch_bg_toggled(button_pressed: bool) -> void:
	if current_stage != null:
		current_stage.stretch_battle_background = button_pressed
	_layout_board()
	_layout_stage_editor_enemy_area()
	_layout_stage_editor_ui()
	_set_stage_editor_status("Full BG: %s" % ("On" if button_pressed else "Off"))


func _on_stage_editor_mode_button_pressed(mode_value: int) -> void:
	if current_stage == null:
		return
	if mode_value != StageData.Mode.NORMAL and mode_value != StageData.Mode.ESCAPE and mode_value != StageData.Mode.PUZZLE:
		return
	current_stage.mode = mode_value
	if current_stage.mode == StageData.Mode.PUZZLE:
		current_stage.puzzle_goal_kind = StageData.PuzzleGoalKind.BREAK_COUNT
		if not _stage_editor_is_valid_goal_target(int(current_stage.puzzle_goal_target_type)):
			current_stage.puzzle_goal_target_type = Block.Type.RED
		if current_stage.puzzle_goal_required_count < 0:
			current_stage.puzzle_goal_required_count = 0
		if current_stage.puzzle_turn_limit <= 0:
			current_stage.puzzle_turn_limit = 30
	_refresh_stage_editor_mode_buttons()
	_refresh_stage_editor_rounds_panel()
	_refresh_stage_editor_enemy_area()
	_layout_stage_editor_ui()
	var mode_name := "Normal"
	if current_stage.mode == StageData.Mode.ESCAPE:
		mode_name = "Escape"
	elif current_stage.mode == StageData.Mode.PUZZLE:
		mode_name = "Puzzle"
	_set_stage_editor_status("Mode: %s" % mode_name)


func _on_stage_editor_goal_target_selected(item_index: int) -> void:
	if current_stage == null or _stage_editor_goal_target_option == null:
		return
	var type_value: int = int(_stage_editor_goal_target_option.get_item_metadata(item_index))
	if not _stage_editor_is_valid_goal_target(type_value):
		return
	current_stage.puzzle_goal_target_type = type_value
	_refresh_stage_editor_enemy_area()
	_set_stage_editor_status("Goal target: %s" % _stage_editor_goal_target_label(type_value))


func _on_stage_editor_goal_count_changed(value: float) -> void:
	if current_stage == null:
		return
	current_stage.puzzle_goal_required_count = maxi(0, int(round(value)))
	_set_stage_editor_status("Goal count: %d" % current_stage.puzzle_goal_required_count)


func _on_stage_editor_goal_turn_changed(value: float) -> void:
	if current_stage == null:
		return
	current_stage.puzzle_turn_limit = maxi(1, int(round(value)))
	_set_stage_editor_status("Puzzle turns: %d" % current_stage.puzzle_turn_limit)


func _on_stage_editor_clear_pressed() -> void:
	board.clear_fixed_layout()
	_set_stage_editor_status("Cleared")


func _stage_editor_get_goal_target_from_ui() -> int:
	if _stage_editor_goal_target_option != null:
		var selected_index: int = _stage_editor_goal_target_option.selected
		if selected_index >= 0:
			return int(_stage_editor_goal_target_option.get_item_metadata(selected_index))
	return int(current_stage.puzzle_goal_target_type) if current_stage != null else int(Block.Type.RED)


func _stage_editor_get_goal_count_from_ui() -> int:
	if _stage_editor_goal_count_spin != null:
		return maxi(0, int(round(_stage_editor_goal_count_spin.value)))
	return int(current_stage.puzzle_goal_required_count) if current_stage != null else 0


func _stage_editor_get_goal_turn_limit_from_ui() -> int:
	if _stage_editor_goal_turn_spin != null:
		return maxi(1, int(round(_stage_editor_goal_turn_spin.value)))
	return int(current_stage.puzzle_turn_limit) if current_stage != null else 30


func _stage_editor_apply_puzzle_goal_from_ui() -> void:
	if current_stage == null:
		return
	if current_stage.mode != StageData.Mode.PUZZLE:
		return
	current_stage.puzzle_goal_kind = StageData.PuzzleGoalKind.BREAK_COUNT
	current_stage.puzzle_goal_target_type = _stage_editor_get_goal_target_from_ui()
	current_stage.puzzle_goal_required_count = _stage_editor_get_goal_count_from_ui()
	current_stage.puzzle_turn_limit = _stage_editor_get_goal_turn_limit_from_ui()


func _on_stage_editor_save_pressed() -> void:
	if current_stage == null or current_stage.resource_path.is_empty():
		_set_stage_editor_status("Save failed: no stage resource", false)
		return
	_stage_editor_apply_puzzle_goal_from_ui()
	var validation_error: String = _stage_editor_validate_rounds_for_save()
	if not validation_error.is_empty():
		_set_stage_editor_status(validation_error, false)
		return
	var distribution_types: Array[Block.Type] = _stage_editor_get_distribution_allowed_types_snapshot()
	current_stage.area = StageData.normalize_area(_stage_editor_selected_area)
	if _stage_editor_bg_override_option != null:
		current_stage.battle_background_override_path = _stage_editor_get_option_value(_stage_editor_bg_override_option)
	if _stage_editor_music_override_option != null:
		current_stage.battle_music_override_path = _stage_editor_get_option_value(_stage_editor_music_override_option)
	if _stage_editor_boss_bgm_option != null:
		var boss_bgm_path: String = _stage_editor_get_option_value(_stage_editor_boss_bgm_option)
		if boss_bgm_path.is_empty():
			current_stage.boss_bgm = null
		else:
			current_stage.boss_bgm = load(boss_bgm_path) as AudioStream
	if _stage_editor_stretch_bg_check != null:
		current_stage.stretch_battle_background = _stage_editor_stretch_bg_check.button_pressed
	current_stage.one_time_reward_item_type = _stage_editor_get_reward_item_type_from_ui()
	current_stage.one_time_reward_item_amount = _stage_editor_get_reward_amount_from_ui()
	current_stage.one_time_reward_character = _stage_editor_get_reward_character_from_ui()
	current_stage.allowed_types = distribution_types
	current_stage.element_weights = _stage_editor_get_element_weights_snapshot(distribution_types)
	current_stage.fixed_layout = board.get_fixed_layout_snapshot()
	current_stage.drop_start_rows = _stage_editor_get_drop_start_rows_snapshot()
	current_stage.rounds = _stage_editor_get_rounds_snapshot()
	current_stage.rounds_init_cd = _stage_editor_get_round_cds_snapshot()
	current_stage.rounds_enemy_levels = _stage_editor_get_round_levels_snapshot()
	current_stage.rounds_main_bosses = _stage_editor_get_round_bosses_snapshot()
	var err: int = ResourceSaver.save(current_stage, current_stage.resource_path)
	if err == OK:
		var file_name: String = current_stage.resource_path.get_file()
		_set_stage_editor_status("Saved %s" % file_name)
	else:
		_set_stage_editor_status("Save failed (%d)" % err, false)


func _stage_editor_validate_rounds_for_save() -> String:
	if current_stage == null:
		return "Save failed: no stage"
	var layout_snapshot: Array = board.get_fixed_layout_snapshot()
	for column_index in current_stage.columns:
		var drop_row: int = _stage_editor_get_drop_start_value_from_ui(column_index)
		if column_index < layout_snapshot.size() and layout_snapshot[column_index] is Array:
			var col: Array = layout_snapshot[column_index]
			if drop_row < col.size() and int(col[drop_row]) == StageData.CELL_HOLE:
				return "Save failed: C%d drop start is a hole" % (column_index + 1)
	if current_stage.mode == StageData.Mode.ESCAPE:
		return ""
	if current_stage.mode == StageData.Mode.PUZZLE:
		_stage_editor_apply_puzzle_goal_from_ui()
		if current_stage.puzzle_goal_kind != StageData.PuzzleGoalKind.BREAK_COUNT:
			return "Save failed: unsupported puzzle goal"
		if not _stage_editor_is_valid_goal_target(int(current_stage.puzzle_goal_target_type)):
			return "Save failed: invalid puzzle goal target"
		if current_stage.puzzle_goal_required_count <= 0:
			return "Save failed: puzzle goal count must be > 0"
		if current_stage.puzzle_turn_limit <= 0:
			return "Save failed: puzzle turns must be > 0"
		return ""
	if _stage_editor_rounds.is_empty():
		return "Save failed: add at least one round"
	for round_index in _stage_editor_rounds.size():
		var round_list: Array = _stage_editor_rounds[round_index]
		if round_list.is_empty():
			return "Save failed: round %d is empty" % (round_index + 1)
		for enemy_variant in round_list:
			if not (enemy_variant is EnemyData):
				return "Save failed: round %d has invalid enemy" % (round_index + 1)
	return ""


func _stage_editor_get_rounds_snapshot() -> Array[Array]:
	var snapshot: Array[Array] = []
	for round_variant in _stage_editor_rounds:
		var round_list: Array = round_variant
		var round_copy: Array = []
		for enemy_variant in round_list:
			if enemy_variant is EnemyData:
				round_copy.append(_stage_editor_make_stage_enemy_snapshot(enemy_variant as EnemyData))
		snapshot.append(round_copy)
	return snapshot


func _stage_editor_make_stage_enemy_snapshot(enemy_data: EnemyData) -> EnemyData:
	var snapshot: EnemyData = enemy_data.duplicate(true) as EnemyData
	if snapshot == null:
		return enemy_data
	var source_path: String = String(enemy_data.get_meta("stage_editor_source_path", enemy_data.resource_path)).strip_edges()
	snapshot.resource_path = ""
	if not source_path.is_empty():
		snapshot.set_meta("stage_editor_source_path", source_path)
	snapshot.loot_table = []
	for loot: LootItem in snapshot.stage_extra_loot_table:
		if loot != null:
			loot.resource_path = ""
	return snapshot


func _stage_editor_get_distribution_allowed_types_snapshot() -> Array[Block.Type]:
	var types: Array[Block.Type] = []
	for type_value: int in STAGE_EDITOR_DISTRIBUTION_TYPES:
		var weight: int = 0
		if _stage_editor_distribution_spins.has(type_value):
			var spin: SpinBox = _stage_editor_distribution_spins[type_value]
			weight = maxi(0, int(round(spin.value)))
		elif current_stage != null:
			weight = current_stage.get_element_weight_for_type(type_value)
		if weight > 0:
			types.append(type_value as Block.Type)
	if types.is_empty():
		types.append(Block.Type.RED)
		if _stage_editor_distribution_spins.has(Block.Type.RED):
			var red_spin: SpinBox = _stage_editor_distribution_spins[Block.Type.RED]
			red_spin.set_value_no_signal(1)
	return types


func _stage_editor_get_element_weights_snapshot(distribution_types: Array[Block.Type] = []) -> Array[int]:
	var weights: Array[int] = []
	if current_stage == null:
		return weights
	var source_types: Array[Block.Type] = distribution_types
	if source_types.is_empty():
		source_types = current_stage.allowed_types
	for type_value in source_types:
		var normalized: int = int(type_value)
		var weight: int = 0
		if _stage_editor_distribution_spins.has(normalized):
			var spin: SpinBox = _stage_editor_distribution_spins[normalized]
			weight = maxi(0, int(round(spin.value)))
		elif current_stage.element_weights.size() > weights.size():
			weight = maxi(0, int(current_stage.element_weights[weights.size()]))
		else:
			weight = current_stage.get_element_weight_for_type(normalized)
		weights.append(weight)
	return weights


func _stage_editor_get_drop_start_value_from_ui(column_index: int) -> int:
	if current_stage == null:
		return 0
	var max_row: int = maxi(0, current_stage.rows - 1)
	if _stage_editor_drop_start_spins.has(column_index):
		var drop_edit: LineEdit = _stage_editor_drop_start_spins[column_index]
		return clampi(int(drop_edit.text.to_int()), 0, max_row)
	return _stage_editor_get_drop_start_value(column_index)


func _stage_editor_get_drop_start_rows_snapshot() -> Array[int]:
	var snapshot: Array[int] = []
	if current_stage == null:
		return snapshot
	for column_index in current_stage.columns:
		snapshot.append(_stage_editor_get_drop_start_value_from_ui(column_index))
	return snapshot


func _stage_editor_get_round_cds_snapshot() -> Array[Array]:
	_stage_editor_normalize_cd_lists()
	var snapshot: Array[Array] = []
	for round_index in _stage_editor_rounds_init_cd.size():
		var source_cd: Array = _stage_editor_rounds_init_cd[round_index]
		var cd_copy: Array = []
		for cd_variant in source_cd:
			cd_copy.append(maxi(0, int(cd_variant)))
		snapshot.append(cd_copy)
	return snapshot


func _stage_editor_get_round_levels_snapshot() -> Array[Array]:
	_stage_editor_normalize_cd_lists()
	var snapshot: Array[Array] = []
	for round_index in _stage_editor_rounds_enemy_levels.size():
		var source_levels: Array = _stage_editor_rounds_enemy_levels[round_index]
		var level_copy: Array = []
		for level_variant in source_levels:
			level_copy.append(clampi(int(level_variant), 1, 99))
		snapshot.append(level_copy)
	return snapshot


func _stage_editor_get_round_bosses_snapshot() -> Array[Array]:
	_stage_editor_normalize_cd_lists()
	var snapshot: Array[Array] = []
	for round_index in _stage_editor_rounds_main_bosses.size():
		var source_bosses: Array = _stage_editor_rounds_main_bosses[round_index]
		var boss_copy: Array = []
		for boss_variant in source_bosses:
			boss_copy.append(bool(boss_variant))
		snapshot.append(boss_copy)
	return snapshot


func _on_stage_editor_back_pressed() -> void:
	GameState.stage_edit_mode = false
	board.set_edit_mode(false)
	GameState.fade_to_scene("res://scenes/map.tscn", 0.25)


func _set_stage_editor_status(message: String, ok: bool = true) -> void:
	pass


func _layout_stage_editor_ui() -> void:
	var viewport_size: Vector2 = ViewportUtils.get_size()
	var insets: Vector4 = ViewportUtils.get_safe_insets()
	var top_margin: float = 8.0 + insets.x
	var left_margin: float = 12.0 + insets.w
	var right_margin: float = 12.0 + insets.y
	var vertical_gap: float = 6.0
	var area_height: float = 0.0
	var bottom_margin: float = 8.0 + insets.z
	var tab_height: float = 58.0
	var tab_width: float = minf(maxf(340.0, viewport_size.x * 0.54), maxf(260.0, viewport_size.x - insets.w - insets.y - 24.0))
	var tab_left: float = insets.w + (viewport_size.x - insets.w - insets.y - tab_width) * 0.5
	var tab_top: float = viewport_size.y - bottom_margin - tab_height

	if _stage_editor_tab_panel != null:
		_stage_editor_set_control_rect(_stage_editor_tab_panel, Rect2(tab_left, tab_top, tab_width, tab_height))

	if _stage_editor_area_panel != null:
		var available_area_width: float = viewport_size.x - left_margin - right_margin
		var area_min_size: Vector2 = _stage_editor_area_panel.get_combined_minimum_size()
		var area_width: float = minf(maxf(area_min_size.x, 260.0), maxf(160.0, available_area_width))
		area_height = maxf(area_min_size.y, 54.0)
		_stage_editor_set_control_rect(_stage_editor_area_panel, Rect2(left_margin, top_margin, area_width, area_height))

	if _stage_editor_dialog_panel != null:
		var dialog_top: float = top_margin + area_height + vertical_gap
		var dialog_bottom: float = tab_top - 8.0
		var dialog_height: float = maxf(160.0, dialog_bottom - dialog_top)
		var dialog_width: float = maxf(260.0, viewport_size.x - left_margin - right_margin)
		_stage_editor_set_control_rect(_stage_editor_dialog_panel, Rect2(left_margin, dialog_top, dialog_width, dialog_height))

	if _stage_editor_panel == null:
		return
	var board_columns: int = current_stage.columns if current_stage != null else 8
	var board_rows: int = current_stage.rows if current_stage != null else 8
	var board_width: float = float(board_columns) * 64.0 * board.scale.x
	var board_height: float = float(board_rows) * 64.0 * board.scale.y
	var panel_width: float = minf(maxf(240.0, board_width + 24.0), viewport_size.x - insets.w - insets.y - 16.0)
	var gap: float = 4.0
	var inner_width: float = maxf(64.0, panel_width - 16.0)
	var target_button_size := 56.0
	var palette_columns: int = clampi(
		int(floor((inner_width + gap) / (target_button_size + gap))),
		1,
		STAGE_EDITOR_GEM_TYPES.size()
	)
	var button_size: float = floor((inner_width - gap * float(palette_columns - 1)) / float(palette_columns))
	button_size = clampf(button_size, 42.0, 64.0)
	for button_variant in _stage_editor_value_buttons.values():
		var button: Button = button_variant as Button
		if button != null:
			button.custom_minimum_size = Vector2(button_size, button_size)
	if _stage_editor_palette_grid != null:
		_stage_editor_palette_grid.columns = palette_columns
		_stage_editor_palette_grid.custom_minimum_size = Vector2(inner_width, 0.0)
	var palette_rows: int = ceili(float(STAGE_EDITOR_GEM_TYPES.size()) / float(palette_columns))
	var visible_palette_rows: int = mini(2, palette_rows)
	var palette_height: float = (float(visible_palette_rows) * button_size + float(maxi(0, visible_palette_rows - 1)) * 6.0 + 8.0) * 2.2
	if _stage_editor_palette_scroll != null:
		_stage_editor_palette_scroll.custom_minimum_size = Vector2(inner_width, palette_height)
	var panel_height: float = palette_height + 78.0
	var preferred_top: float = board.position.y + board_height + 12.0
	var max_top: float = minf(viewport_size.y - panel_height - insets.z - 8.0, tab_top - panel_height - 8.0)
	var min_top: float = 8.0 + insets.x
	if max_top < min_top:
		max_top = min_top
	var panel_top: float = clampf(preferred_top, min_top, max_top)
	var panel_left: float = clampf(board.position.x - maxf(0.0, panel_width - board_width) * 0.5, insets.w + 8.0, viewport_size.x - insets.y - panel_width - 8.0)
	_stage_editor_set_control_rect(_stage_editor_panel, Rect2(panel_left, panel_top, panel_width, panel_height))


## 設定融合提示：從隊伍角色中收集融合技能並傳遞給棋盤
func _setup_fuse_hints() -> void:
	var fuse_skills: Array[Dictionary] = []
	for char_index in party.size():
		var c: CharacterData = party[char_index]
		for skill_index in c.responding_skills.size():
			var skill: Dictionary = c.responding_skills[skill_index]
			var fuse_label: String = SkillUpgradeUtils.responding_fuse_label(c, skill_index, skill)
			if fuse_label.is_empty():
				continue
			var fuse_gem_type: Block.Type = SkillUpgradeUtils.responding_gem_type(c, skill)
			fuse_skills.append({
				"gem_type": fuse_gem_type,
				"threshold": SkillUpgradeUtils.responding_threshold(c, skill_index, skill),
				"label": fuse_label,
				"trigger_type": skill.get("trigger_type", "count"),
				"priority": skill.get("priority", 99),
				"team_index": char_index,
				"skill_order": skill_index,
			})
	board.set_fuse_skills(fuse_skills)


# ── 進場動畫 ──────────────────────────────────────────────────

## 進場動畫：黑幕淡出 → 角色卡從底部滑入 → 寶石隨機浮現
func _play_stage_intro() -> void:
	board.set_input_queue_locked(true)
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

	_stage_intro_gems_ready = false
	_play_stage_intro_gems()  # fire-and-forget，立即開始

	# 等 0.5 秒後啟動卡片滑入
	await get_tree().create_timer(0.5).timeout

	# ── 教學模式：等所有卡片動畫完成後再延遲 1 秒才啟動 ──
	if current_stage.is_tutorial:
		await character_panel.play_intro_slide()  # 等全部卡片滑入完畢
		while not _stage_intro_gems_ready:
			await get_tree().process_frame
		if _should_show_initial_boss_intro():
			await _show_boss_intro()
		else:
			await _fade_in_spawned_enemies()
		board.set_input_queue_locked(false)
		await get_tree().create_timer(1.0).timeout
		_start_battle_tutorial()
		return

	character_panel.play_intro_slide()  # fire-and-forget

	# 等寶石進場完成後才解鎖棋盤
	await get_tree().create_timer(0.1).timeout
	while not _stage_intro_gems_ready:
		await get_tree().process_frame
	if _should_show_initial_boss_intro():
		await _show_boss_intro()
	else:
		await _fade_in_spawned_enemies()
	if _is_stage13_story_battle():
		await _run_stage13_turn1_dialog()
	if _should_run_stage14_escape_intro():
		await _run_stage14_escape_intro()
	board.set_input_queue_locked(false)
	board.is_busy = false


func _play_stage_intro_gems() -> void:
	await board.play_gems_intro()
	_stage_intro_gems_ready = true


func _should_show_initial_boss_intro() -> bool:
	if _initial_boss_intro_shown or battle_manager == null:
		return false
	if battle_manager.current_round != 0:
		return false
	var boss: Enemy = battle_manager.get_main_boss_for_round(0)
	if boss == null or not is_instance_valid(boss):
		return false
	_initial_boss_intro_shown = true
	return true


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

	if _should_run_stage1_guest_intro():
		_battle_dialog.show_lines(_Stage1Tutorial.make_guest_intro_dialog())
		await _battle_dialog.all_lines_finished
		await add_temporary_guest_character(CHAR_HUSKY, {
			"slot_index": 3,
			"visual_scale": 1.5,
			"reveal_duration_scale": 2.0,
			"include_in_result": true,
		})

	var steps: Array = _Stage1Tutorial.make_steps(party)
	_tutorial_manager.start(steps)


func _should_run_stage1_guest_intro() -> bool:
	return current_stage != null and current_stage.stage_id == "1-1" and not party.has(CHAR_HUSKY)


func add_temporary_guest_character(guest: CharacterData, options: Dictionary = {}) -> int:
	if guest == null:
		return -1
	if party.has(guest):
		return party.find(guest)
	var was_busy: bool = board.is_busy
	board.is_busy = true
	var card_index: int = character_panel.append_temporary_card(guest, true)
	if card_index < 0:
		board.is_busy = was_busy
		return -1
	var expected_index: int = int(options.get("slot_index", party.size()))
	if expected_index != card_index:
		push_warning("Guest slot mismatch: expected %d, got %d" % [expected_index, card_index])
	await get_tree().process_frame
	var target_pos: Vector2 = character_panel.get_card_screen_center(card_index)
	var board_center: Vector2i = Vector2i(int(floor(float(board.columns) * 0.5)), int(floor(float(board.rows) * 0.5)))
	var from_pos: Vector2 = board.to_global(board.grid_to_world(board_center))
	var color: Color = Block.COLORS.get(guest.gem_type, Color.WHITE)
	var visual_scale: float = float(options.get("visual_scale", 1.0))
	await _play_guest_join_projectile(from_pos, target_pos, color, visual_scale)
	var reveal_duration_scale: float = float(options.get("reveal_duration_scale", 1.0)) * 2.0
	reveal_duration_scale = maxf(reveal_duration_scale - (0.5 / 0.34), 0.1)
	var battle_index: int = battle_manager.add_temporary_character(guest, bool(options.get("add_current_hp", true)))
	if battle_index != card_index:
		push_warning("Guest battle index mismatch: card=%d battle=%d" % [card_index, battle_index])
	_play_sfx(_se_join_team)
	await character_panel.reveal_temporary_card(card_index, reveal_duration_scale)
	party.append(guest)
	if not bool(options.get("include_in_result", true)):
		_guest_result_exclusions[guest] = true
	_setup_fuse_hints()
	_update_skill_ui()
	_refresh_gem_meter()
	var post_join_pause: float = maxf(0.0, float(options.get("post_join_pause", 0.2)))
	if post_join_pause > 0.0:
		await get_tree().create_timer(post_join_pause).timeout
	board.is_busy = was_busy
	return card_index


func add_temporary_guest_characters_staggered(entries: Array, interval: float = 0.5) -> Array[int]:
	var results: Array[int] = []
	results.resize(entries.size())
	for i in results.size():
		results[i] = -1
	if entries.is_empty():
		return results

	var completed := [0]
	for i in entries.size():
		var entry: Dictionary = entries[i] as Dictionary
		var guest: CharacterData = entry.get("guest", null) as CharacterData
		var options: Dictionary = entry.get("options", {}) as Dictionary
		_run_temporary_guest_join_task(guest, options, results, i, completed)
		if i < entries.size() - 1 and interval > 0.0:
			await get_tree().create_timer(interval).timeout

	while int(completed[0]) < entries.size():
		await get_tree().process_frame
	return results


func _run_temporary_guest_join_task(guest: CharacterData, options: Dictionary, results: Array, index: int, completed: Array) -> void:
	results[index] = await add_temporary_guest_character(guest, options)
	completed[0] = int(completed[0]) + 1


func _play_guest_join_projectile(from_pos: Vector2, target_pos: Vector2, color: Color, visual_scale: float) -> void:
	var trail := Node2D.new()
	trail.set_script(TrailProjectileScript)
	trail.z_index = 200
	fx_layer.add_child(trail)
	if trail.has_method("set_visual_size_multiplier"):
		trail.set_visual_size_multiplier(visual_scale)
	if trail.has_method("setup"):
		trail.setup()
	var has_release_signal: bool = trail.has_signal("released")
	if has_release_signal:
		trail.released.connect(trail.queue_free, CONNECT_ONE_SHOT)
	var duration: float = 2.0
	if trail.has_method("launch_guest_join"):
		trail.launch_guest_join(from_pos, target_pos, color, duration, 0.35)
	else:
		trail.launch(from_pos, target_pos, color, duration)
	if has_release_signal:
		await trail.released
	else:
		await get_tree().create_timer(duration / TrailProjectileScript.speed_divisor + 0.05).timeout
	if is_instance_valid(trail):
		trail.queue_free()


func _get_battle_result_party() -> Array[CharacterData]:
	if _is_stage13_story_battle() and not _stage13_result_party.is_empty():
		return _stage13_result_party.duplicate()
	var result: Array[CharacterData] = []
	for c: CharacterData in party:
		if c == null:
			continue
		if _guest_result_exclusions.has(c):
			continue
		result.append(c)
	return result


## 教學完成回呼
func _on_tutorial_finished() -> void:
	board.is_busy = false
	# 隱藏教學對話面板
	if _battle_dialog != null:
		_battle_dialog.visible = false


# ── BGM ───────────────────────────────────────────────────────

func _load_audio_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var stream: AudioStream = load(path)
		if stream != null:
			return stream
	if path.get_extension().to_lower() == "mp3" and FileAccess.file_exists(path):
		var mp3 := AudioStreamMP3.new()
		mp3.data = FileAccess.get_file_as_bytes(path)
		return mp3
	return null


## 播放一次性音效（volume_scale 為線性倍率，1.0 = 原音量）
func _play_sfx(stream: AudioStream, volume_scale: float = 1.0) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	if volume_scale > 0.0 and not is_equal_approx(volume_scale, 1.0):
		player.volume_db = linear_to_db(volume_scale)
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()


func _play_random_stone_impact_sfx() -> void:
	var choices: Array[AudioStream] = []
	for stream in _se_stone_impacts:
		if stream != null:
			choices.append(stream)
	if choices.is_empty():
		return
	_play_sfx(choices[randi() % choices.size()])


## 依連鎖數播放對應音階：chain 2 → match_xylophone_2，... chain 10+ → match_xylophone_10_MAX
func _play_chain_sfx(chain_count: int) -> void:
	var idx: int = clampi(chain_count, 2, 10)
	var path: String = "res://assets/se/match_xylophone_%d_MAX.wav" % idx if idx == 10 else "res://assets/se/match_xylophone_%d.wav" % idx
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path)
	_play_sfx(stream, 1.8)


## 播放關卡背景音樂
func _play_bgm() -> void:
	if _should_skip_default_battle_bgm_for_initial_boss():
		return
	var override_path: String = current_stage.battle_music_override_path.strip_edges() if current_stage != null else ""
	var stage_bgm: AudioStream = null
	var stage_id: String = ""
	if not override_path.is_empty() and ResourceLoader.exists(override_path):
		stage_bgm = load(override_path) as AudioStream
		stage_id = "stage_override:" + override_path
	elif current_stage.bgm != null:
		stage_bgm = current_stage.bgm
		stage_id = "stage:" + current_stage.stage_name
	if stage_bgm != null:
		# 進場後延遲 1 秒再啟動，且戰鬥 BGM 循環之間插入 1 秒延遲
		# 戰鬥 BGM 直接以全音量播放（不淡入），循環之間維持 1 秒間隔
		get_tree().create_timer(1.0).timeout.connect(func() -> void:
			GameState.crossfade_bgm(stage_bgm, true, 0.0, stage_id, 1.0)
			_bgm_player = GameState.bgm_player
		)


func _should_skip_default_battle_bgm_for_initial_boss() -> bool:
	if current_stage == null or battle_manager == null:
		return false
	if current_stage.boss_bgm == null:
		return false
	if current_stage.rounds.size() != 1:
		return false
	if current_stage.rounds.is_empty() or not (current_stage.rounds[0] is Array):
		return false
	var first_round: Array = current_stage.rounds[0]
	if first_round.is_empty():
		return false
	var boss: Enemy = battle_manager.get_main_boss_for_round(0)
	return boss != null and is_instance_valid(boss)


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


func _on_enemy_break_pulse() -> void:
	_play_sfx(_se_blast, 0.8)


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


func _is_upper_gem_skill(skill_name: String) -> bool:
	return _upper_type_for_response_skill(skill_name) != Block.UpperType.NONE


func _upper_type_for_response_skill(skill_name: String) -> Block.UpperType:
	return SkillUpgradeUtils.responding_upper_type_from_name(skill_name)


func _upper_type_for_response(resp: Dictionary) -> Block.UpperType:
	if resp.has("upper_type"):
		var raw_upper: int = int(resp.get("upper_type", Block.UpperType.NONE))
		return raw_upper
	var skill: Dictionary = resp.get("skill_dict", {}) as Dictionary
	if not skill.is_empty():
		return SkillUpgradeUtils.responding_upper_type(skill)
	return _upper_type_for_response_skill(str(resp.get("skill_name", "")))


func _is_upper_gem_response(resp: Dictionary) -> bool:
	return _upper_type_for_response(resp) != Block.UpperType.NONE


func _is_instant_response(resp: Dictionary) -> bool:
	return Block.upper_type_has_instant(_upper_type_for_response(resp))


func _has_living_battle_enemy() -> bool:
	return _living_battle_enemy_count() > 0


func _living_battle_enemy_count() -> int:
	var count := 0
	for enemy in battle_manager.active_enemies:
		if is_instance_valid(enemy) and enemy.current_hp > 0:
			count += 1
	return count


func _response_list_has_instant_spell(responses: Array) -> bool:
	for resp in responses:
		if _is_instant_response(resp):
			return true
	return false


func _is_battle_stage_mode() -> bool:
	return current_stage == null or int(current_stage.mode) == int(StageData.Mode.NORMAL)


func _should_abort_pending_instant_flow() -> bool:
	if battle_manager.is_round_transitioning:
		return true
	return _is_battle_stage_mode() and not _has_living_battle_enemy()


func _lock_input_for_instant_spell() -> void:
	board.clear_deferred_clicks()
	board.set_board_input_paused(true)


func _clear_pending_instant_spell_work() -> void:
	_concurrent_fuses.clear()
	_instant_fuse_pipeline_active = false
	_clear_instant_upper_task_visuals(_active_instant_upper_tasks)
	_clear_instant_upper_task_visuals(_pending_instant_upper_tasks)
	_release_trail_projectile(_next_instant_upper_follow_trail)
	_next_instant_upper_follow_trail = null
	_active_instant_upper_tasks.clear()
	_pending_instant_upper_tasks.clear()
	_reserved_instant_upper_tasks.clear()
	_attack_queue.clear()
	board.clear_deferred_clicks()


func _get_instant_upper_pop_full_duration() -> float:
	var pop_duration := 0.4
	if board != null and board.has_method("get_fuse_pop_full_duration"):
		pop_duration = float(board.get_fuse_pop_full_duration())
	return pop_duration


func _register_instant_upper_resolvers() -> void:
	_instant_upper_resolvers.clear()
	_instant_upper_predictors.clear()
	_instant_upper_resolvers[Block.UpperType.ICEBALL] = Callable(self, "_resolve_iceball_instant")
	_instant_upper_resolvers[Block.UpperType.LEAF_RAY] = Callable(self, "_resolve_leaf_ray_instant")
	_instant_upper_predictors[Block.UpperType.ICEBALL] = Callable(self, "_predict_iceball_instant")
	_instant_upper_predictors[Block.UpperType.LEAF_RAY] = Callable(self, "_predict_leaf_ray_instant")


func _has_instant_upper_resolver(upper_type: Block.UpperType) -> bool:
	var resolver: Callable = _instant_upper_resolvers.get(upper_type, Callable()) as Callable
	return resolver.is_valid()


func _has_instant_upper_predictor(upper_type: Block.UpperType) -> bool:
	var predictor: Callable = _instant_upper_predictors.get(upper_type, Callable()) as Callable
	return predictor.is_valid()


func _pending_instant_spell_mult(index: int) -> float:
	return 1.0 + float(_spell_chain_count + index) * 0.10


func _predict_targeted_instant_damage(gem_type: Block.Type, base_damage: int, spell_mult: float, sim_hp: Dictionary) -> Dictionary:
	var target: Enemy = battle_manager.targeted_enemy
	if target != null and (not is_instance_valid(target) or int(sim_hp.get(target, 0)) <= 0):
		target = null
	if target == null:
		target = _get_best_target_for_damage(gem_type, base_damage, spell_mult, sim_hp)
	if target == null:
		return {}
	var element_mult: float = battle_manager.get_element_multiplier(gem_type, target.data.element) if target.data != null else 1.0
	var final_damage: int = maxi(1, int(float(base_damage) * element_mult * spell_mult))
	var predicted_damage: int = battle_manager.get_enemy_damage_after_passives(target, final_damage)
	return {
		"target": target,
		"damage": predicted_damage,
	}


func _predict_iceball_instant(resp: Dictionary, spell_mult: float, sim_hp: Dictionary) -> Dictionary:
	var caster_index: int = int(resp.get("char_index", -1))
	var caster: CharacterData = party[caster_index] if caster_index >= 0 and caster_index < party.size() else null
	var magic_value: int = caster.get_magic() if caster != null else 1
	return _predict_targeted_instant_damage(Block.Type.BLUE, magic_value * ICEBALL_MAGIC_MULT, spell_mult, sim_hp)


func _predict_leaf_ray_instant(resp: Dictionary, spell_mult: float, sim_hp: Dictionary) -> Dictionary:
	var caster_index: int = int(resp.get("char_index", -1))
	var caster: CharacterData = party[caster_index] if caster_index >= 0 and caster_index < party.size() else null
	var magic_value: int = caster.get_magic() if caster != null else 1
	var base_damage: int = maxi(1, int(round(float(magic_value) * LEAF_RAY_MAGIC_MULT)))
	return _predict_targeted_instant_damage(Block.Type.GREEN, base_damage, spell_mult, sim_hp)


func _apply_instant_prediction_to_sim(prediction: Dictionary, sim_hp: Dictionary) -> void:
	var target_ref: Variant = prediction.get("target", null)
	if not is_instance_valid(target_ref):
		return
	var target: Enemy = target_ref as Enemy
	if target == null:
		return
	var predicted_damage: int = maxi(0, int(prediction.get("damage", 0)))
	sim_hp[target] = int(sim_hp.get(target, target.current_hp)) - predicted_damage


func _instant_task_matches_response(task: Dictionary, resp: Dictionary, upper_type: Block.UpperType) -> bool:
	if (task.get("upper_type", Block.UpperType.NONE) as Block.UpperType) != upper_type:
		return false
	var task_resp: Dictionary = task.get("resp", {}) as Dictionary
	return int(task_resp.get("char_index", -1)) == int(resp.get("char_index", -1)) \
		and int(task_resp.get("gem_type", -999)) == int(resp.get("gem_type", -999)) \
		and int(task_resp.get("skill_order", -1)) == int(resp.get("skill_order", -1))


func _make_instant_task(resp: Dictionary, upper_type: Block.UpperType) -> Dictionary:
	return {
		"resp": resp.duplicate(true),
		"upper_type": upper_type,
	}


func _reserve_instant_upper_responses(responses: Array) -> void:
	for resp in responses:
		var response: Dictionary = resp as Dictionary
		var upper_type: Block.UpperType = _upper_type_for_response(response)
		if upper_type == Block.UpperType.NONE or not Block.upper_type_has_instant(upper_type):
			continue
		if not _has_instant_upper_resolver(upper_type) or not _has_instant_upper_predictor(upper_type):
			continue
		_reserved_instant_upper_tasks.append(_make_instant_task(response, upper_type))


func _consume_instant_upper_reservation(resp: Dictionary, upper_type: Block.UpperType) -> void:
	for index in _reserved_instant_upper_tasks.size():
		if _instant_task_matches_response(_reserved_instant_upper_tasks[index], resp, upper_type):
			_reserved_instant_upper_tasks.remove_at(index)
			return


func _predict_instant_upper_task(task: Dictionary, sim_hp: Dictionary, pending_index: int) -> Dictionary:
	var upper_type: Block.UpperType = task.get("upper_type", Block.UpperType.NONE) as Block.UpperType
	var predictor: Callable = _instant_upper_predictors.get(upper_type, Callable()) as Callable
	if not predictor.is_valid():
		return {}
	var resp: Dictionary = task.get("resp", {}) as Dictionary
	var spell_mult: float = float(task.get("spell_mult", _pending_instant_spell_mult(pending_index)))
	return predictor.call(resp, spell_mult, sim_hp) as Dictionary


func _can_queue_instant_upper_response(resp: Dictionary, upper_type: Block.UpperType, include_reservations: bool = true) -> bool:
	if not _has_instant_upper_predictor(upper_type):
		push_warning("Instant upper gem has no predictor: %s" % str(upper_type))
		return false
	var sim_hp: Dictionary = _get_current_enemy_hp_sim()
	var simulated_tasks: Array[Dictionary] = []
	simulated_tasks.append_array(_active_instant_upper_tasks)
	simulated_tasks.append_array(_pending_instant_upper_tasks)
	if include_reservations:
		simulated_tasks.append_array(_reserved_instant_upper_tasks)
	for index in simulated_tasks.size():
		var queued_prediction: Dictionary = _predict_instant_upper_task(simulated_tasks[index], sim_hp, index)
		if queued_prediction.is_empty():
			return false
		_apply_instant_prediction_to_sim(queued_prediction, sim_hp)
	return not _predict_instant_upper_task(_make_instant_task(resp, upper_type), sim_hp, simulated_tasks.size()).is_empty()


func _queue_pending_instant_upper_task(pos: Vector2i, resp: Dictionary, upper_type: Block.UpperType) -> void:
	var block: Block = null
	if board != null and board._is_valid(pos):
		block = board.grid[pos.x][pos.y]
		if block != null:
			board.grid[pos.x][pos.y] = null
			block.grid_pos = pos
			block.set_board_columns(board.columns)
			_move_block_to_fx_layer_preserving_transform(block, _instant_upper_fx_z_index(upper_type))
			block.modulate = Color.WHITE
			block.refresh_upper_particle_system()
	var orbit_slot := _instant_upper_orbit_slot(resp)
	var task := {
		"pos": pos,
		"block": block,
		"resp": resp.duplicate(true),
		"upper_type": upper_type,
		"orbit_center": _instant_upper_owner_orbit_center(resp),
		"orbit_radius": INSTANT_UPPER_ORBIT_RADIUS + float(orbit_slot % 2) * 5.0,
		"orbit_angle": -PI * 0.5 + float(orbit_slot) * 0.72,
		"orbiting": false,
		"ready_msec": Time.get_ticks_msec() + int(_get_instant_upper_pop_full_duration() * 1000.0),
	}
	_pending_instant_upper_tasks.append(task)
	_refresh_instant_upper_orbits_for_char(int(resp.get("char_index", -1)))
	match INSTANT_UPPER_TRANSFER_METHOD:
		INSTANT_UPPER_TRANSFER_METHOD_VOID:
			_transfer_instant_upper_to_owner_orbit_by_void(task)
		_:
			_attach_instant_upper_follow_trail(task)
			_send_instant_upper_to_owner_orbit(task)


func _instant_upper_orbit_slot(resp: Dictionary) -> int:
	var char_index: int = int(resp.get("char_index", -1))
	var slot := 0
	for task in _active_instant_upper_tasks:
		var task_resp: Dictionary = task.get("resp", {}) as Dictionary
		if int(task_resp.get("char_index", -2)) == char_index:
			slot += 1
	for task in _pending_instant_upper_tasks:
		var task_resp: Dictionary = task.get("resp", {}) as Dictionary
		if int(task_resp.get("char_index", -2)) == char_index:
			slot += 1
	return slot


func _instant_upper_task_char_index(task: Dictionary) -> int:
	var task_resp: Dictionary = task.get("resp", {}) as Dictionary
	return int(task_resp.get("char_index", -1))


func _instant_upper_orbit_count_for_char(char_index: int) -> int:
	var count := 0
	for task in _active_instant_upper_tasks:
		if _instant_upper_task_char_index(task) == char_index and not bool(task.get("orbit_cancelled", false)) and is_instance_valid(task.get("block", null)):
			count += 1
	for task in _pending_instant_upper_tasks:
		if _instant_upper_task_char_index(task) == char_index and not bool(task.get("orbit_cancelled", false)) and is_instance_valid(task.get("block", null)):
			count += 1
	return maxi(1, count)


func _instant_upper_orbit_period(task: Dictionary) -> float:
	var char_index := _instant_upper_task_char_index(task)
	var orbit_count := _instant_upper_orbit_count_for_char(char_index)
	var speed_mult := 1.0 + float(maxi(orbit_count - 1, 0)) * INSTANT_UPPER_ORBIT_SPEED_STEP
	return maxf(INSTANT_UPPER_ORBIT_MIN_PERIOD, INSTANT_UPPER_ORBIT_PERIOD / speed_mult)


func _instant_upper_orbit_offset(angle: float, radius: float) -> Vector2:
	var local := Vector2(cos(angle) * radius, sin(angle) * radius * INSTANT_UPPER_ORBIT_Y_SCALE)
	var c := cos(INSTANT_UPPER_ORBIT_TILT)
	var s := sin(INSTANT_UPPER_ORBIT_TILT)
	return Vector2(local.x * c - local.y * s, local.x * s + local.y * c)


func _refresh_instant_upper_orbits_for_char(char_index: int) -> void:
	for task in _active_instant_upper_tasks:
		if _instant_upper_task_char_index(task) == char_index and bool(task.get("orbiting", false)):
			_start_instant_upper_orbit(task)
	for task in _pending_instant_upper_tasks:
		if _instant_upper_task_char_index(task) == char_index and bool(task.get("orbiting", false)):
			_start_instant_upper_orbit(task)


func _instant_upper_owner_orbit_center(resp: Dictionary) -> Vector2:
	var char_index: int = int(resp.get("char_index", -1))
	if character_panel != null and char_index >= 0:
		if character_panel.has_method("get_card"):
			var card: Control = character_panel.get_card(char_index)
			if card != null:
				var rect: Rect2 = card.get_global_rect()
				if rect.size != Vector2.ZERO:
					return Vector2(rect.get_center().x, rect.position.y + rect.size.y * 0.34)
		if character_panel.has_method("get_card_screen_center"):
			var center: Vector2 = character_panel.get_card_screen_center(char_index)
			if center != Vector2.ZERO:
				return center + Vector2(0.0, -16.0)
	return get_viewport_rect().size * Vector2(0.5, 0.88)


func _stop_board_fuse_animation_for_block(block: Block, target_scale: Vector2 = Vector2.ONE) -> void:
	if block == null or not is_instance_valid(block):
		return
	if board != null and board.has_method("hold_fuse_animation_at_peak"):
		board.hold_fuse_animation_at_peak(block)
	block.scale = target_scale


func _kill_instant_upper_task_tween(task: Dictionary, key: String) -> void:
	var raw_tween: Variant = task.get(key, null)
	if raw_tween is Tween:
		var tween := raw_tween as Tween
		if tween.is_valid():
			tween.kill()
	task[key] = null


func _release_instant_upper_follow_trail(task: Dictionary) -> void:
	var raw_trail: Variant = task.get("follow_trail", null)
	if is_instance_valid(raw_trail):
		var trail := raw_trail as Node2D
		if trail != null and trail.has_method("force_release"):
			trail.force_release()
	task["follow_trail"] = null


func _release_trail_projectile(trail: Variant) -> void:
	if is_instance_valid(trail):
		var node := trail as Node2D
		if node != null and node.has_method("force_release"):
			node.force_release()


func _take_next_instant_upper_follow_trail() -> Node2D:
	if not is_instance_valid(_next_instant_upper_follow_trail):
		_next_instant_upper_follow_trail = null
		return null
	var trail := _next_instant_upper_follow_trail
	_next_instant_upper_follow_trail = null
	return trail


func _prime_next_instant_upper_follow_trail(trail: Variant) -> void:
	if not is_instance_valid(trail):
		return
	_release_trail_projectile(_next_instant_upper_follow_trail)
	_next_instant_upper_follow_trail = trail as Node2D


func _release_unconsumed_next_instant_upper_follow_trail() -> void:
	_release_trail_projectile(_next_instant_upper_follow_trail)
	_next_instant_upper_follow_trail = null


func _clear_instant_upper_task_visuals(tasks: Array[Dictionary]) -> void:
	for task in tasks:
		task["orbit_cancelled"] = true
		task["orbiting"] = false
		_kill_instant_upper_task_tween(task, "travel_tween")
		_kill_instant_upper_task_tween(task, "orbit_tween")
		_release_instant_upper_follow_trail(task)
		var raw_block: Variant = task.get("block", null)
		if is_instance_valid(raw_block):
			var block: Block = raw_block as Block
			if block != null:
				block.queue_free()


func _instant_upper_follow_trail_color(resp: Dictionary, upper_type: Block.UpperType) -> Color:
	var fallback_type: Block.Type = int(resp.get("gem_type", Block.Type.RED)) as Block.Type
	var element_type: Block.Type = Block.UPPER_ELEMENT.get(upper_type, fallback_type) as Block.Type
	return Block.COLORS.get(element_type, Color.WHITE)


func _attach_instant_upper_follow_trail(task: Dictionary) -> void:
	var raw_block: Variant = task.get("block", null)
	if not is_instance_valid(raw_block):
		return
	var block := raw_block as Block
	if block == null:
		return
	var preserve_trail := false
	var trail: Node2D = _take_next_instant_upper_follow_trail()
	if trail != null:
		preserve_trail = true
	else:
		trail = _acquire_particle(TRANSMUTE_TRAIL_POOL_SIZE)
	if trail == null:
		return
	trail.z_index = block.z_index - 1
	var resp: Dictionary = task.get("resp", {}) as Dictionary
	var upper_type: Block.UpperType = task.get("upper_type", Block.UpperType.NONE) as Block.UpperType
	var color: Color = _instant_upper_follow_trail_color(resp, upper_type)
	if trail.has_method("follow_node"):
		trail.follow_node(block, color, INSTANT_UPPER_TRAIL_OFFSET, 0.48, preserve_trail)
	task["follow_trail"] = trail


func _send_instant_upper_to_owner_orbit(task: Dictionary) -> void:
	var raw_block: Variant = task.get("block", null)
	if not is_instance_valid(raw_block):
		return
	var block: Block = raw_block as Block
	if block == null:
		return
	var center: Vector2 = task.get("orbit_center", block.global_position) as Vector2
	var radius: float = float(task.get("orbit_radius", INSTANT_UPPER_ORBIT_RADIUS))
	var angle: float = float(task.get("orbit_angle", -PI * 0.5))
	_stop_board_fuse_animation_for_block(block, INSTANT_UPPER_ORBIT_SCALE)
	var target_pos: Vector2 = center + _instant_upper_orbit_offset(angle, radius)
	var start_pos: Vector2 = block.global_position
	var travel_distance: float = start_pos.distance_to(target_pos)
	var travel_arc_height: float = maxf(travel_distance * 0.56, 160.0)
	_kill_instant_upper_task_tween(task, "travel_tween")
	var tw := create_tween().set_parallel(true)
	task["travel_tween"] = tw
	tw.tween_method(
		func(u: float) -> void:
			if not is_instance_valid(block):
				return
			var t := clampf(u + 0.085 * sin(TAU * u), 0.0, 1.0)
			var path_pos := start_pos.lerp(target_pos, t)
			path_pos.y -= travel_arc_height * 4.0 * t * (1.0 - t)
			block.global_position = path_pos,
		0.0,
		1.0,
		INSTANT_UPPER_ORBIT_FLY_DURATION
	).set_trans(Tween.TRANS_LINEAR)
	tw.tween_property(block, "scale", INSTANT_UPPER_ORBIT_SCALE, INSTANT_UPPER_ORBIT_FLY_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	await tw.finished
	task["travel_tween"] = null
	if bool(task.get("orbit_cancelled", false)) or not is_instance_valid(block):
		return
	_start_instant_upper_orbit(task)


func _transfer_instant_upper_to_owner_orbit_by_void(task: Dictionary) -> void:
	var raw_block: Variant = task.get("block", null)
	if not is_instance_valid(raw_block):
		return
	var block: Block = raw_block as Block
	if block == null:
		return
	_release_unconsumed_next_instant_upper_follow_trail()
	var center: Vector2 = task.get("orbit_center", block.global_position) as Vector2
	var radius: float = float(task.get("orbit_radius", INSTANT_UPPER_ORBIT_RADIUS))
	var angle: float = float(task.get("orbit_angle", -PI * 0.5))
	var target_pos: Vector2 = center + _instant_upper_orbit_offset(angle, radius)
	var target_scale: Vector2 = INSTANT_UPPER_ORBIT_SCALE
	_stop_board_fuse_animation_for_block(block, target_scale)
	task["void_original_scale"] = target_scale
	_kill_instant_upper_task_tween(task, "travel_tween")
	block.modulate = Color.WHITE
	var shrink_tw := create_tween().set_parallel(true)
	task["travel_tween"] = shrink_tw
	shrink_tw.tween_property(block, "scale", Vector2.ZERO, INSTANT_UPPER_VOID_SHRINK_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)
	shrink_tw.tween_property(block, "modulate:a", 0.0, INSTANT_UPPER_VOID_SHRINK_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	await shrink_tw.finished
	if bool(task.get("orbit_cancelled", false)) or not is_instance_valid(block):
		return
	block.global_position = target_pos
	block.scale = Vector2.ZERO
	block.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_attach_instant_upper_follow_trail(task)
	var appear_tw := create_tween().set_parallel(true)
	task["travel_tween"] = appear_tw
	appear_tw.tween_property(block, "scale", target_scale, INSTANT_UPPER_VOID_APPEAR_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	appear_tw.tween_property(block, "modulate:a", 1.0, INSTANT_UPPER_VOID_APPEAR_DURATION * 0.72).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	await appear_tw.finished
	task["travel_tween"] = null
	if bool(task.get("orbit_cancelled", false)) or not is_instance_valid(block):
		return
	block.scale = target_scale
	block.modulate = Color.WHITE
	_start_instant_upper_orbit(task)


func _start_instant_upper_orbit(task: Dictionary) -> void:
	if bool(task.get("orbit_cancelled", false)):
		return
	var raw_block: Variant = task.get("block", null)
	if not is_instance_valid(raw_block):
		return
	var block: Block = raw_block as Block
	if block == null:
		return
	_kill_instant_upper_task_tween(task, "orbit_tween")
	var center: Vector2 = task.get("orbit_center", block.global_position) as Vector2
	var radius: float = float(task.get("orbit_radius", INSTANT_UPPER_ORBIT_RADIUS))
	var start_angle: float = float(task.get("orbit_angle", 0.0))
	var orbit_period := _instant_upper_orbit_period(task)
	var orbit_tw := create_tween().set_loops()
	task["orbiting"] = true
	task["orbit_tween"] = orbit_tw
	orbit_tw.tween_method(
		func(angle: float) -> void:
			if not is_instance_valid(block) or bool(task.get("orbit_cancelled", false)):
				return
			task["orbit_angle"] = fmod(angle, TAU)
			block.global_position = center + _instant_upper_orbit_offset(angle, radius),
		start_angle,
		start_angle + TAU,
		orbit_period
	).set_trans(Tween.TRANS_LINEAR)


func _prepare_instant_upper_task_for_effect(task: Dictionary) -> void:
	task["orbit_cancelled"] = true
	task["orbiting"] = false
	var char_index := _instant_upper_task_char_index(task)
	_kill_instant_upper_task_tween(task, "travel_tween")
	_kill_instant_upper_task_tween(task, "orbit_tween")
	_release_instant_upper_follow_trail(task)
	var raw_block: Variant = task.get("block", null)
	if not is_instance_valid(raw_block):
		return
	var block: Block = raw_block as Block
	if block == null:
		return
	block.modulate = Color.WHITE
	block.refresh_upper_particle_system()
	_refresh_instant_upper_orbits_for_char(char_index)
	await get_tree().process_frame


func _find_pending_instant_task_pos(task: Dictionary) -> Vector2i:
	var fallback: Vector2i = task.get("pos", Vector2i(-1, -1)) as Vector2i
	var raw_block: Variant = task.get("block", null)
	if not is_instance_valid(raw_block):
		return fallback
	var block: Block = raw_block as Block
	if block == null:
		return fallback
	if board == null:
		return fallback
	if board != null and board._is_valid(fallback) and board.grid[fallback.x][fallback.y] == block:
		return fallback
	for x in board.columns:
		for y in board.rows:
			if board.grid[x][y] == block:
				return Vector2i(x, y)
	return fallback


func _instant_upper_fx_z_index(upper_type: Block.UpperType) -> int:
	match upper_type:
		Block.UpperType.LEAF_RAY:
			return 95
		Block.UpperType.ICEBALL:
			return 42
		_:
			return 80


func _prepare_pending_instant_upper_tasks_for_effect() -> void:
	var latest_ready_msec := Time.get_ticks_msec()
	for task in _pending_instant_upper_tasks:
		latest_ready_msec = maxi(latest_ready_msec, int(task.get("ready_msec", latest_ready_msec)))
	var now := Time.get_ticks_msec()
	if now < latest_ready_msec:
		await get_tree().create_timer(float(latest_ready_msec - now) / 1000.0).timeout
	await get_tree().process_frame


func _wait_for_instant_upper_task_ready(task: Dictionary) -> void:
	var ready_msec: int = int(task.get("ready_msec", Time.get_ticks_msec()))
	var now := Time.get_ticks_msec()
	if now < ready_msec:
		await get_tree().create_timer(float(ready_msec - now) / 1000.0).timeout
	await get_tree().process_frame


func _play_pending_instant_upper_task(task: Dictionary) -> void:
	if battle_manager.is_round_transitioning:
		return
	var pos: Vector2i = _find_pending_instant_task_pos(task)
	var raw_block: Variant = task.get("block", null)
	if board == null or not board._is_valid(pos) or (not is_instance_valid(raw_block) and board.grid[pos.x][pos.y] == null):
		return
	var resp: Dictionary = task.get("resp", {}) as Dictionary
	var upper_type: Block.UpperType = task.get("upper_type", Block.UpperType.NONE) as Block.UpperType
	var resolver: Callable = _instant_upper_resolvers.get(upper_type, Callable()) as Callable
	if not resolver.is_valid():
		push_warning("Instant upper gem has no resolver: %s" % str(upper_type))
		return
	await _prepare_instant_upper_task_for_effect(task)
	raw_block = task.get("block", null)
	var spell_mult: float = float(task.get("spell_mult", 0.0))
	if spell_mult <= 0.0:
		spell_mult = _register_spell_chain()
		task["spell_mult"] = spell_mult
	await resolver.call(pos, resp, spell_mult, raw_block)


func _play_pending_instant_upper_tasks() -> void:
	if _pending_instant_upper_tasks.is_empty():
		return
	_lock_input_for_instant_spell()
	await _prepare_pending_instant_upper_tasks_for_effect()
	while not _pending_instant_upper_tasks.is_empty():
		var task: Dictionary = _pending_instant_upper_tasks.pop_front()
		await _play_pending_instant_upper_task(task)


func _kick_instant_upper_effect_worker() -> void:
	if _instant_upper_effect_worker_running:
		return
	_run_instant_upper_effect_worker()


func _run_instant_upper_effect_worker() -> void:
	_instant_upper_effect_worker_running = true
	while not _pending_instant_upper_tasks.is_empty():
		var task: Dictionary = _pending_instant_upper_tasks.pop_front()
		_active_instant_upper_tasks.append(task)
		await _wait_for_instant_upper_task_ready(task)
		await _play_pending_instant_upper_task(task)
		_active_instant_upper_tasks.erase(task)
		if _should_abort_pending_instant_flow():
			_pending_instant_upper_tasks.clear()
			break
	_active_instant_upper_tasks.clear()
	_instant_upper_effect_worker_running = false


func _place_instant_upper_response(resp: Dictionary, upper_type: Block.UpperType, fuse_gem_type: Block.Type) -> bool:
	if not _has_instant_upper_resolver(upper_type):
		push_warning("Instant upper gem is marked instant but has no resolver: %s" % str(upper_type))
		return false
	_consume_instant_upper_reservation(resp, upper_type)
	if not _can_queue_instant_upper_response(resp, upper_type, false):
		return false
	var pos: Vector2i = board.last_tapped_pos
	var upper_gem_type: Block.Type = Block.UPPER_ELEMENT.get(upper_type, fuse_gem_type) as Block.Type
	if not board.place_upper_gem(pos, upper_type, upper_gem_type, Block.UpperOwnerTeam.PLAYER, 0):
		return false
	_play_sfx(_se_freeze)
	var char_index: int = int(resp.get("char_index", -1))
	var character: CharacterData = party[char_index] if char_index >= 0 and char_index < party.size() else null
	var fuse_count: int = int(battle_manager.turn_gem_blasts.get(fuse_gem_type, 0))
	_add_log_entry(_format_fuse_bbcode(fuse_gem_type, fuse_count, upper_type), fuse_gem_type, character)
	_queue_pending_instant_upper_task(pos, resp, upper_type)
	return true


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
	_play_sfx(_se_blast, 0.8)
	# 將全局座標轉換為網格座標（用於直線檢測）
	var grid_positions: Array[Vector2i] = []
	for gp in global_positions:
		var local_pos: Vector2 = board.to_local(gp)
		grid_positions.append(board.world_to_grid(local_pos))

	# 高階寶石連鏈爆炸期間跳過攻擊序列（統一在結束時計算傷害）
	if _is_upper_gem_turn:
		board.is_busy = true  # 高階寶石路徑保留鎖定
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

	# 記錄消除資料以觸發回應技能（隔離本筆 blast：暫存/還原 turn_gem_blasts，避免並行 blast 累加導致誤判 fuse）
	var saved_blasts: Dictionary = battle_manager.turn_gem_blasts.duplicate()
	var saved_positions: Array[Vector2i] = battle_manager.last_blast_positions.duplicate()
	battle_manager.turn_gem_blasts = {}
	battle_manager.last_blast_positions = []
	battle_manager.record_blast(gem_type, count, grid_positions)

	# 先檢查回應技能以決定流程
	var responses := battle_manager.check_responding_skills(board)
	var is_fuse: bool = false
	var first_response: Dictionary = {}
	if responses.size() > 0:
		first_response = responses[0] as Dictionary
		is_fuse = _is_upper_gem_response(first_response)

	if is_fuse:
		# ── 融合管線（不消耗回合，整段保留鎖定）──
		# 融合不計入寶石計量器：還原 saved_blasts（這筆 record_blast 不計）
		battle_manager.turn_gem_blasts = saved_blasts
		battle_manager.last_blast_positions = saved_positions
		battle_manager.turn_gem_blasts_changed.emit()
		board.is_busy = true
		if _is_instant_response(first_response):
			await _execute_instant_fuse_pipeline(gem_type, count, global_positions, grid_positions, responses)
			return
		_reset_spell_chain()
		await _execute_fuse_pipeline(gem_type, count, global_positions, grid_positions, responses)
		return

	_reset_spell_chain()

	# 還原 turn_gem_blasts，等到 worker 處理此筆時再 set
	battle_manager.turn_gem_blasts = saved_blasts
	battle_manager.last_blast_positions = saved_positions

	# ── 普通攻擊流程：推入攻擊佇列、啟動 worker（不阻塞下一次 blast）──
	_attack_queue.append({
		"gem_type": gem_type,
		"count": count,
		"global_positions": global_positions,
		"grid_positions": grid_positions,
		"responses": responses,
	})
	if not _attack_worker_running:
		_run_attack_worker()  # fire-and-forget 協程


## 攻擊管線 worker：依序處理 _attack_queue 的每筆 blast。
## 每筆：VFX 飛卡 → 角色攻擊動畫 → 回應技能 → 結束回合（含敵人攻擊）。
func _run_attack_worker() -> void:
	_attack_worker_running = true
	board.notify_external_attack_busy(true)
	while _attack_queue.size() > 0:
		var item: Dictionary = _attack_queue.pop_front()
		# 還原 battle_manager 的 turn-blast 狀態（worker 取出時對應該 blast 的回合）
		battle_manager.turn_gem_blasts = { item.gem_type: item.count }
		battle_manager.last_blast_positions = item.grid_positions as Array[Vector2i]

		var blasted_dict: Dictionary = { item.gem_type: item.count }
		var blast_pos_dict: Dictionary = { item.gem_type: item.global_positions }
		await _process_blast_results(blasted_dict, blast_pos_dict)
		if _stage13_victory_triggered:
			break

		# 執行非融合的回應技能（如葉風暴）
		for resp in item.responses:
			await _execute_responding_skill(resp)

		# 結束此筆 blast 對應的回合（含敵人攻擊）
		await _end_player_turn()
	_attack_worker_running = false
	board.notify_external_attack_busy(false)


func _on_score_changed(new_score: int) -> void:
	score_label.text = "Score: %d" % new_score


func _create_trail_projectile() -> Node2D:
	var p := Node2D.new()
	p.set_script(TrailProjectileScript)
	fx_layer.add_child(p)
	p.setup()
	p.visible = false
	_vfx_pool.append(p)
	return p


func _prewarm_trail_projectile_pool(target_size: int) -> void:
	if fx_layer == null:
		return
	while _vfx_pool.size() < target_size:
		_create_trail_projectile()


## 從池中取得一個可用的 VFX 粒子節點（池滿且全忙時回傳 null）
func _acquire_particle(pool_limit: int = MAX_VFX_PARTICLES) -> Node2D:
	for p in _vfx_pool:
		if p.is_available:
			return p
	if _vfx_pool.size() < pool_limit:
		return _create_trail_projectile()
	return null


## ── 主動技 Animation Phase ──────────────────────────────────────────
## 各主動技的「動畫前置」參數查表。回傳 null = 該技能無動畫前置。
## 字典欄位：
##   anim_path: String          影片資源路徑（必須）
##   anim_offset: Vector2       相對於 board 左下角的位移（正值往右下）
##   anim_seek_sec: float       影片內起始秒數（seek 之後才 play）
##   anim_duration_sec: float   播放時長（0 = 等待影片自然結束；fallback 時用作等待秒數）
##   anim_size: Vector2         顯示尺寸（Vector2.ZERO = 用影片原寸）
func _get_active_skill_anim_params(c: CharacterData) -> Variant:
	if c == null:
		return null
	match c.active_skill_name:
		"Dragon Flame Domain":
			return {
				"anim_path": "res://assets/animation/anim_meteror.ogv",
				"anim_offset": Vector2.ZERO,
				"anim_seek_sec": 1.0,
				"anim_duration_sec": 0.0,
				"anim_size": Vector2.ZERO,
				"anim_scale": 0.5,
				"anim_playback_speed": 1.5,
			}
	return null


## 播放主動技動畫前置：建立 VideoStreamPlayer 於 board 左下角 + offset 處，
## 期間 board.is_busy = true。影片載入失敗時 fallback 為等待 anim_duration_sec（或 1.5 秒）。
func _play_skill_animation_phase(params: Variant) -> void:
	if params == null:
		return
	var p: Dictionary = params as Dictionary
	var anim_path: String = p.get("anim_path", "")
	if anim_path.is_empty():
		return
	var anim_offset: Vector2 = p.get("anim_offset", Vector2.ZERO)
	var anim_seek: float = float(p.get("anim_seek_sec", 0.0))
	var anim_duration: float = float(p.get("anim_duration_sec", 0.0))
	var anim_size: Vector2 = p.get("anim_size", Vector2.ZERO)
	var anim_scale: float = float(p.get("anim_scale", 1.0))

	var anim_playback_speed: float = float(p.get("anim_playback_speed", 1.0))

	# 鎖住棋盤
	var was_busy: bool = board.is_busy
	board.is_busy = true

	# 計算 board 左下角 global 座標
	var bl_local: Vector2 = Vector2(0.0, float(board.rows) * float(board.CELL_SIZE))
	var anchor_global: Vector2 = board.to_global(bl_local) + anim_offset

	var stream: VideoStream = null
	if ResourceLoader.exists(anim_path):
		var loaded: Resource = load(anim_path)
		if loaded is VideoStream:
			stream = loaded

	if stream != null:
		var player := VideoStreamPlayer.new()
		player.stream = stream
		player.expand = anim_size != Vector2.ZERO
		if anim_size != Vector2.ZERO:
			player.size = anim_size
		player.scale = Vector2(anim_scale, anim_scale)
		player.position = anchor_global
		# 以左下為錨點：將顯示框往上平移其高度
		player.pivot_offset = Vector2.ZERO
		player.z_index = 50
		fx_layer.add_child(player)
		# 等一幀讓 stream 取得長度
		await get_tree().process_frame
		# 左下對齊：依實際大小（含縮放）往上偏移
		var disp_h: float = anim_size.y if anim_size != Vector2.ZERO else float(player.size.y)
		disp_h *= anim_scale
		player.position = anchor_global - Vector2(0.0, disp_h)

		player.play()
		if anim_seek > 0.0:
			player.stream_position = anim_seek

		if anim_duration > 0.0:
			await get_tree().create_timer(anim_duration / anim_playback_speed).timeout
		elif anim_playback_speed != 1.0:
			# Engine.time_scale 放大每幀 delta，VideoStreamPlayer 據此加速解碼
			Engine.time_scale = anim_playback_speed
			await player.finished
			Engine.time_scale = 1.0
		else:
			await player.finished
		Engine.time_scale = 1.0  # 確保無論如何都還原
		if is_instance_valid(player):
			player.stop()
			player.queue_free()
	else:
		# Fallback：載入失敗 → 印警告並以 anim_duration 或 1.5s 等待
		push_warning("Animation phase: failed to load video '%s'; falling back to wait." % anim_path)
		var wait_sec: float = anim_duration if anim_duration > 0.0 else 1.5
		await get_tree().create_timer(wait_sec).timeout

	board.is_busy = was_busy


# ── 回合管線 ─────────────────────────────────────────────────────

func _consume_puzzle_turn_or_defeat() -> bool:
	if not _puzzle_mode or _puzzle_goal_completed or _puzzle_turn_limit_failed:
		return false
	if current_stage == null or current_stage.mode != StageData.Mode.PUZZLE:
		return false
	_puzzle_turns_left = maxi(_puzzle_turns_left - 1, 0)
	_update_puzzle_turn_panel(true)
	if _puzzle_turns_left <= 0:
		await _trigger_puzzle_turn_limit_defeat()
		return true
	return false


## Instant 融合管線：只負責生成 instant upper gem，施法效果交給獨立 queue。
## 合成粒子到位 → 放置上珠 → 立即掉落填充 → 背景逐顆播放 instant effect。
func _execute_instant_fuse_pipeline(gem_type: Block.Type, count: int, global_positions: Array, grid_positions: Array[Vector2i], responses: Array) -> void:
	board.skip_collapse = true
	board.is_fusing = true
	_fuse_pipeline_active = true
	_instant_fuse_pipeline_active = true
	_concurrent_fuses.clear()

	var first_tapped_pos: Vector2i = board.last_tapped_pos
	var first_tapped_local_pos: Vector2 = board.last_tapped_local_pos
	var fuse_target: Vector2 = board.to_global(board.grid_to_world(first_tapped_pos))
	var color: Color = Block.COLORS[gem_type]
	var particle_duration := 1.05
	var fuse_total: int = mini(global_positions.size(), MAX_VFX_PARTICLES)
	var retained_follow_trail: Node2D = null
	for idx in fuse_total:
		var particle: Node2D = _acquire_particle()
		if particle == null:
			break
		var gem_pos: Vector2 = global_positions[idx]
		var spread: float = (float(idx) / max(fuse_total - 1, 1)) * 2.0 - 1.0 if fuse_total > 1 else 0.0
		if idx == fuse_total - 1 and particle.has_method("launch_hold_at_end"):
			particle.launch_hold_at_end(gem_pos, fuse_target, color, particle_duration, spread)
			retained_follow_trail = particle
		else:
			particle.launch(gem_pos, fuse_target, color, particle_duration, spread)
	await get_tree().create_timer(particle_duration / TrailProjectileScript.speed_divisor + 0.05).timeout

	board.set_last_tapped_input(first_tapped_pos, first_tapped_local_pos)
	battle_manager.turn_gem_blasts = { gem_type: count }
	battle_manager.last_blast_positions = grid_positions
	var retained_follow_trail_used := false
	for resp in responses:
		if not retained_follow_trail_used and _is_instant_response(resp):
			_prime_next_instant_upper_follow_trail(retained_follow_trail)
			retained_follow_trail_used = true
		await _execute_responding_skill(resp)
	_release_unconsumed_next_instant_upper_follow_trail()
	if not retained_follow_trail_used:
		_release_trail_projectile(retained_follow_trail)

	while _concurrent_fuses.size() > 0:
		var cf: Dictionary = _concurrent_fuses.pop_front()
		var now := Time.get_ticks_msec()
		var arrival: int = cf.arrival_msec
		if now < arrival:
			var wait_sec: float = float(arrival - now) / 1000.0
			await get_tree().create_timer(wait_sec).timeout
		var cf_tapped_pos: Vector2i = cf.tapped_pos as Vector2i
		var cf_tapped_local_pos: Vector2 = cf.get("tapped_local_pos", board.grid_to_world(cf_tapped_pos)) as Vector2
		board.set_last_tapped_input(cf_tapped_pos, cf_tapped_local_pos)
		battle_manager.turn_gem_blasts = { cf.gem_type: cf.count }
		battle_manager.last_blast_positions = cf.grid_positions as Array[Vector2i]
		var cf_follow_trail: Node2D = cf.get("follow_trail", null) as Node2D
		var cf_follow_trail_used := false
		for resp in cf.responses:
			if not cf_follow_trail_used and _is_instant_response(resp):
				_prime_next_instant_upper_follow_trail(cf_follow_trail)
				cf_follow_trail_used = true
			await _execute_responding_skill(resp)
		_release_unconsumed_next_instant_upper_follow_trail()
		if not cf_follow_trail_used:
			_release_trail_projectile(cf_follow_trail)
	_reserved_instant_upper_tasks.clear()

	_instant_fuse_pipeline_active = false
	_fuse_pipeline_active = false
	board.is_fusing = false
	board.skip_collapse = false
	await board.do_collapse()

	battle_manager.reset_blast_data()
	_update_skill_ui()
	if not battle_manager.is_round_transitioning:
		battle_manager.clear_logic_pending_attack()
		battle_manager.resync_logic_state()
		board.resync_logic_from_visual()
		board.set_board_input_paused(false)
		board.is_busy = false
	_kick_instant_upper_effect_worker()


## 融合管線：放置高階寶石（不消耗回合）
## 粒子飛向點擊位置 → 放置高階寶石 → 處理並行融合 → 掉落填充 → 清除消除資料 → 解鎖棋盤
func _execute_fuse_pipeline(gem_type: Block.Type, count: int, global_positions: Array, grid_positions: Array[Vector2i], responses: Array) -> void:
	board.skip_collapse = true
	board.is_fusing = true
	_fuse_pipeline_active = true
	_concurrent_fuses.clear()
	_reserved_instant_upper_tasks.clear()

	var first_tapped_pos: Vector2i = board.last_tapped_pos
	var first_tapped_local_pos: Vector2 = board.last_tapped_local_pos
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
	board.set_last_tapped_input(first_tapped_pos, first_tapped_local_pos)
	battle_manager.turn_gem_blasts = { gem_type: count }
	battle_manager.last_blast_positions = grid_positions
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
		var cf_tapped_pos: Vector2i = cf.tapped_pos as Vector2i
		var cf_tapped_local_pos: Vector2 = cf.get("tapped_local_pos", board.grid_to_world(cf_tapped_pos)) as Vector2
		board.set_last_tapped_input(cf_tapped_pos, cf_tapped_local_pos)
		battle_manager.turn_gem_blasts = { cf.gem_type: cf.count }
		battle_manager.last_blast_positions = cf.grid_positions as Array[Vector2i]
		var cf_follow_trail: Node2D = cf.get("follow_trail", null) as Node2D
		var cf_follow_trail_used := false
		for resp in cf.responses:
			if not cf_follow_trail_used and _is_instant_response(resp):
				_prime_next_instant_upper_follow_trail(cf_follow_trail)
				cf_follow_trail_used = true
			await _execute_responding_skill(resp)
		_release_unconsumed_next_instant_upper_follow_trail()
		if not cf_follow_trail_used:
			_release_trail_projectile(cf_follow_trail)

	_reserved_instant_upper_tasks.clear()

	_fuse_pipeline_active = false
	board.is_fusing = false

	await board.do_collapse()

	# 不消耗回合，僅清除消除資料
	battle_manager.reset_blast_data()
	_update_skill_ui()
	if not battle_manager.is_round_transitioning:
		# State/UI 分離：融合不消耗回合，但 _handle_click 已預先 logic_apply_blast，
		# 必須以視覺現況重置邏輯狀態，否則後續普通爆破會被誤封鎖
		board.clear_deferred_clicks()
		battle_manager.clear_logic_pending_attack()
		battle_manager.resync_logic_state()
		board.resync_logic_from_visual()
		board.set_board_input_paused(false)
		board.is_busy = false
	_kick_instant_upper_effect_worker()


func _can_accept_concurrent_fuse(gem_type: Block.Type, count: int, grid_positions: Array, _tap_pos: Vector2i) -> bool:
	if battle_manager == null or board == null or battle_manager.is_round_transitioning:
		return false

	var typed_positions: Array[Vector2i] = []
	for value in grid_positions:
		typed_positions.append(value as Vector2i)

	var saved_blasts: Dictionary = battle_manager.turn_gem_blasts.duplicate()
	var saved_positions: Array[Vector2i] = battle_manager.last_blast_positions.duplicate()
	battle_manager.turn_gem_blasts = {}
	battle_manager.last_blast_positions = []
	battle_manager.record_blast(gem_type, count, typed_positions)
	var responses := battle_manager.check_responding_skills(board)
	battle_manager.turn_gem_blasts = saved_blasts
	battle_manager.last_blast_positions = saved_positions

	if responses.is_empty():
		return false

	var has_instant_response := false
	for resp in responses:
		var response: Dictionary = resp as Dictionary
		var upper_type: Block.UpperType = _upper_type_for_response(response)
		if upper_type == Block.UpperType.NONE or not Block.upper_type_has_instant(upper_type):
			continue
		has_instant_response = true
		if not _can_queue_instant_upper_response(response, upper_type):
			return false
	if _instant_fuse_pipeline_active and not has_instant_response:
		return false
	if has_instant_response:
		_reserve_instant_upper_responses(responses)
	return true


## 處理並行融合的 gems_blasted 信號：立即發射粒子並記錄待處理資料
func _handle_concurrent_fuse_blast(gem_type: Block.Type, count: int, grid_positions: Array[Vector2i], global_positions: Array) -> void:
	if battle_manager.is_round_transitioning:
		return
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

	var is_fuse: bool = false
	if responses.size() > 0:
		var first_response: Dictionary = responses[0] as Dictionary
		is_fuse = _is_upper_gem_response(first_response)
	if not is_fuse:
		board.clear_concurrent_fuse_tap()
		return
	var has_instant_response := _response_list_has_instant_spell(responses)
	if _instant_fuse_pipeline_active and not has_instant_response:
		board.clear_concurrent_fuse_tap()
		return

	# 立即發射粒子（與第一次融合動畫並行）
	var tapped_pos: Vector2i = board._concurrent_fuse_tapped_pos
	var tapped_local_pos: Vector2 = board.get_concurrent_fuse_tapped_local_pos()
	board.clear_concurrent_fuse_tap()
	var fuse_target: Vector2 = board.to_global(board.grid_to_world(tapped_pos))
	var color: Color = Block.COLORS[gem_type]
	var particle_duration := 1.05
	var fuse_total: int = mini(global_positions.size(), MAX_VFX_PARTICLES)
	var retained_follow_trail: Node2D = null
	for idx in fuse_total:
		var particle: Node2D = _acquire_particle()
		if particle == null:
			break
		var gem_pos: Vector2 = global_positions[idx]
		var spread: float = (float(idx) / max(fuse_total - 1, 1)) * 2.0 - 1.0 if fuse_total > 1 else 0.0
		if has_instant_response and idx == fuse_total - 1 and particle.has_method("launch_hold_at_end"):
			particle.launch_hold_at_end(gem_pos, fuse_target, color, particle_duration, spread)
			retained_follow_trail = particle
		else:
			particle.launch(gem_pos, fuse_target, color, particle_duration, spread)
	var arrival_msec: int = Time.get_ticks_msec() + int((particle_duration / TrailProjectileScript.speed_divisor + 0.05) * 1000)
	_concurrent_fuses.append({
		"tapped_pos": tapped_pos,
		"tapped_local_pos": tapped_local_pos,
		"responses": responses,
		"arrival_msec": arrival_msec,
		"gem_type": gem_type,
		"count": count,
		"grid_positions": grid_positions,
		"follow_trail": retained_follow_trail,
	})


## 結束玩家回合管線：turn++ → 1 秒延遲 → 敵人行動 → 被動技能 → 解鎖棋盤
func _end_player_turn() -> void:
	board.clear_deferred_clicks()
	_reset_spell_chain()
	var puzzle_turn_ended_with_defeat: bool = await _consume_puzzle_turn_or_defeat()
	if puzzle_turn_ended_with_defeat:
		return
	board.set_board_input_paused(true)
	battle_manager.finish_turn()

	# 召喚物每回合行動：豪豬攻擊 / 烏龜回血
	await _resolve_persistent_upper_gems()

	# 敵人行動前延遲（同時鎖定棋盤直到敵人攻擊完成）
	var will_attack: bool = battle_manager.has_enemies_to_attack()
	if will_attack:
		board.is_busy = true
		# 暫時停用：敵人攻擊期間不暗化棋盤。
		# board.darken_all_gems(0.3)
		await get_tree().create_timer(0.35).timeout

	var did_attack: bool = await battle_manager.do_enemy_phase()
	if did_attack:
		# 等待最後一個敵人投射物落地
		await get_tree().create_timer(0.5 / TrailProjectileScript.speed_divisor + 0.15).timeout
		while _enemy_board_effects_pending > 0:
			await get_tree().create_timer(0.05).timeout
	battle_manager.settle_player_shield_after_enemy_phase()
	if _stage13_event_running:
		await _wait_for_stage13_event()

	await _process_turn_start_passives()
	_update_skill_ui()
	if not battle_manager.is_round_transitioning:
		# State/UI 分離：解除邏輯阻擋
		battle_manager.clear_logic_pending_attack()
		# 僅當 attack worker 完成且 queue 全空時才安全 resync
		if board.deferred_clicks.is_empty() and _attack_queue.is_empty():
			battle_manager.resync_logic_state()
			board.resync_logic_from_visual()
		# 暫時停用：敵人攻擊結束時不需要恢復亮度。
		# if will_attack:
		# 	board.brighten_all_gems(0.3)
		# 一律解鎖棋盤（upper-gem 路徑全程 is_busy=true，必須在此釋放）
		board.set_board_input_paused(false)
		board.is_busy = false
		# Stage 1-5 急難事件：在玩家下一個回合開始前該發
		if _plank_event_pending and not _plank_event_done:
			_plank_event_pending = false
			_plank_event_done = true
			await _run_plank_emergency_event()
		if _should_run_stage13_light_hint():
			await _run_stage13_light_hint_event()


# ── 持久化召喚物：每回合行動 ───────────────────────────────────

const PORCUPINE_POWER: float = 0.5  # 豪豬攻擊：全隊魔力 × 0.5
const TURTLE_POWER: float = 0.8     # 烏龜回血：全隊魔力 × 0.8
const BAMBOO_SUPPLY_HEAL_MULT: float = 4.8  # 竹葉補給回血：Pan 魔力 × 4.8


## 在玩家回合結束、敵人行動之前：讓所有場上的召喚物（豪豬/烏龜）行動一次。
## 計算階段：board.is_busy=true（已由呼叫端保證）；棋盤其他寶石變暗，僅豪豬/烏龜保持亮度。
## 然後依序對每隻召喚物播放 bounce 動畫並執行其攻擊/回血。
func _resolve_persistent_upper_gems() -> void:
	var porcupines: Array[Vector2i] = board.find_upper_gems(Block.UpperType.PORCUPINE)
	var turtles: Array[Vector2i] = board.find_upper_gems(Block.UpperType.TURTLE)
	if porcupines.is_empty() and turtles.is_empty():
		return

	# 計算全隊魔力總和
	var party_magic_sum: int = 0
	for c: CharacterData in party:
		if c != null:
			party_magic_sum += c.get_magic()
	if party_magic_sum <= 0:
		return

	# 找出綠屬性角色（僅用於記錄；豪豬/烏龜的 VFX 直接從寶石位置出發，不經過角色卡）
	var green_idx: int = -1
	for i in party.size():
		var cd: CharacterData = party[i]
		if cd != null and cd.gem_type == Block.Type.GREEN:
			green_idx = i
			break
	var green_color: Color = Block.COLORS[Block.Type.GREEN]

	# ── 計算階段：將其他寶石變暗，凸顯豪豬/烏龜 ──
	var summon_set: Dictionary = {}
	for p: Vector2i in porcupines:
		summon_set[p] = true
	for p: Vector2i in turtles:
		summon_set[p] = true
	_dim_board_except(summon_set)

	# ── 豪豬：每隻 bounce 後直接從寶石位置 → 敵人 ──
	if not porcupines.is_empty():
		var dmg: int = int(party_magic_sum * PORCUPINE_POWER)
		if dmg > 0:
			# 啟用延遲死亡（過殺機制）
			for enemy in battle_manager.active_enemies:
				if is_instance_valid(enemy):
					enemy.defer_death = true

			for i in porcupines.size():
				var pos: Vector2i = porcupines[i]
				var target: Enemy = null
				for e: Enemy in battle_manager.active_enemies:
					if is_instance_valid(e) and e.current_hp > 0:
						target = e
						break
				if target == null:
					break
				# Bounce 動畫
				_bounce_block_at(pos)
				await get_tree().create_timer(0.18).timeout

				var from_pos: Vector2 = board.to_global(board.grid_to_world(pos))
				var target_pos: Vector2 = _get_enemy_image_center(target)
				var trail := Node2D.new()
				trail.set_script(TrailProjectileScript)
				fx_layer.add_child(trail)
				var captured_target: Enemy = target
				var captured_dmg: int = dmg
				trail.deduct_hp.connect(func():
					if is_instance_valid(captured_target) and (captured_target.current_hp > 0 or captured_target.defer_death):
						var applied_dmg: int = captured_target.take_damage(captured_dmg)
						_spawn_damage_number(_get_enemy_image_center(captured_target), applied_dmg, green_color, true, false)
					_play_sfx(_se_impact)
				, CONNECT_ONE_SHOT)
				trail.launch(from_pos, target_pos, green_color, 0.5)
				_add_log_entry("[b]%s[/b] %s ⚔ %d" % [Locale.tr_ui("Porcupine"), _gem_bbcode(Block.Type.GREEN), dmg], Block.Type.GREEN, null)
				if i < porcupines.size() - 1:
					await get_tree().create_timer(ATTACK_STAGGER_SEC).timeout

			# 等待最後一發投射物落地
			await get_tree().create_timer(0.5 / TrailProjectileScript.speed_divisor + 0.15).timeout

			# 結算延遲死亡
			for enemy in battle_manager.active_enemies.duplicate():
				if is_instance_valid(enemy):
					enemy.defer_death = false
					if enemy.current_hp <= 0:
						enemy.finalize_death()

	# ── 烏龜：bounce + 從烏龜寶石彈出 +HP 數字 + 直接回血 ──
	if not turtles.is_empty():
		var heal: int = int(party_magic_sum * TURTLE_POWER)
		if heal > 0:
			for i in turtles.size():
				var pos: Vector2i = turtles[i]
				_bounce_block_at(pos)
				await get_tree().create_timer(0.18).timeout

				battle_manager.apply_heal(heal)
				# 從烏龜寶石位置彈出 +HP 數字
				var from_pos: Vector2 = board.to_global(board.grid_to_world(pos))
				_spawn_damage_number(from_pos, heal, Color(0.5, 1.0, 0.5), true, false)
				_add_log_entry("[b]%s[/b] %s +%d HP" % [Locale.tr_ui("Turtle"), _gem_bbcode(Block.Type.GREEN), heal], Block.Type.GREEN, null)
				if i < turtles.size() - 1:
					await get_tree().create_timer(ATTACK_STAGGER_SEC).timeout

	# ── 計算階段結束：恢復棋盤亮度 ──
	_undim_board()


## 將棋盤上不在 keep_set（Vector2i → bool）內的寶石變暗。
func _dim_board_except(keep_set: Dictionary) -> void:
	for x in board.columns:
		for y in board.rows:
			var b: Block = board.grid[x][y]
			if b == null:
				continue
			if keep_set.has(Vector2i(x, y)):
				var tw_keep := create_tween()
				tw_keep.tween_property(b, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.15)
				continue
			var tw := create_tween()
			tw.tween_property(b, "modulate", Color(0.35, 0.35, 0.40, 1.0), 0.15)


func _undim_board() -> void:
	for x in board.columns:
		for y in board.rows:
			var b: Block = board.grid[x][y]
			if b == null:
				continue
			var tw := create_tween()
			tw.tween_property(b, "modulate", Color.WHITE, 0.15)


## 對指定位置的 Block 播放 bounce（放大→回原大小）動畫。
func _bounce_block_at(pos: Vector2i) -> void:
	if pos.x < 0 or pos.y < 0 or pos.x >= board.columns or pos.y >= board.rows:
		return
	var b: Block = board.grid[pos.x][pos.y]
	if b == null:
		return
	var orig_scale: Vector2 = Vector2.ONE
	var tw := create_tween()
	tw.tween_property(b, "scale", orig_scale * 1.35, 0.10) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(b, "scale", orig_scale, 0.12) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)


# ── 通用消除處理管線 ─────────────────────────────────────────────

## 處理一批消除結果：VFX 飛向角色卡 → 角色攻擊動畫
## blasted_by_type: { Block.Type -> count }
## blast_positions: { Block.Type -> Array[Vector2] } 全域座標（用於 VFX 起始點）
## chain_bonus: 連鏈 ATK 加成倍率（例如 0.10 = 加 10%）
func _process_blast_results(blasted_by_type: Dictionary, blast_positions: Dictionary, chain_bonus: float = 0.0) -> void:
	var particle_duration := 1.05
	var all_attacks: Array = []
	var max_attack_duration: float = 0.5

	# 計算各類型的粒子預算（按比例分配 MAX_VFX_PARTICLES）
	var total_raw := 0
	for k in blasted_by_type:
		total_raw += mini(blasted_by_type[k] as int, 8)

	for gem_type_key in blasted_by_type:
		var gem_type: Block.Type = gem_type_key as Block.Type
		var count: int = blasted_by_type[gem_type_key]
		var attacks := battle_manager.get_attack_data(gem_type, count)
		var color: Color = Block.COLORS[gem_type]
		var vfx_profile: Dictionary = _attack_vfx_profile_for_count(count)
		var raw: int = mini(count, 8)
		var budget: int = maxi(1, roundi(float(MAX_VFX_PARTICLES) * raw / total_raw)) if total_raw > 0 else 1
		var chain_total: int = mini(raw, budget)
		var blast_pos_list: Array = blast_positions.get(gem_type, [])

		# 無對應角色時跳過 VFX
		if attacks.is_empty():
			continue
		var profile_attack_duration: float = 0.5 * float(vfx_profile.get("duration_scale", 1.0))

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
				if particle.has_method("set_visual_size_multiplier"):
					particle.set_visual_size_multiplier(1.0)
				particle.launch(from_pos, card_center, color, particle_duration, spread)

		# 套用連鏈加成並排入攻擊佇列
		for attack in attacks:
			var chain_mult: float = 1.0 + chain_bonus
			var attack_vfx_duration: float = profile_attack_duration
			var attack_char_index: int = int(attack.get("char_index", -1))
			var attack_char: CharacterData = party[attack_char_index] if attack_char_index >= 0 and attack_char_index < party.size() else null
			if attack_char != null and attack_char.character_name == "Boar":
				attack_vfx_duration = 0.5
			max_attack_duration = maxf(max_attack_duration, attack_vfx_duration)
			attack.damage = int(attack.damage * chain_mult)
			attack["chain_mult"] = chain_mult
			attack["vfx_profile"] = vfx_profile
			attack["attack_vfx_duration"] = attack_vfx_duration
			all_attacks.append(attack)

	_retarget_attack_queue_by_simulated_hp(all_attacks)

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
	await get_tree().create_timer(max_attack_duration / TrailProjectileScript.speed_divisor + 0.15).timeout

	var stage13_final_hit: bool = _stage13_owen_light_hit_pending
	if stage13_final_hit:
		_stage13_owen_light_hit_pending = false

	# 攻擊序列結束：結算所有延遲死亡的敵人
	for enemy in battle_manager.active_enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.defer_death = false
			if enemy.current_hp <= 0:
				enemy.finalize_death()
	if stage13_final_hit:
		await _run_stage13_finale_and_win()


func _retarget_attack_queue_by_simulated_hp(attacks: Array) -> void:
	var sim_hp: Dictionary = {}
	for enemy in battle_manager.active_enemies:
		if is_instance_valid(enemy):
			sim_hp[enemy] = enemy.current_hp
	var manual_target: Enemy = battle_manager.targeted_enemy
	if manual_target != null and (not is_instance_valid(manual_target) or int(sim_hp.get(manual_target, 0)) <= 0):
		manual_target = null

	for attack in attacks:
		var target_ref: Variant = attack.get("target")
		var target: Enemy = target_ref as Enemy if is_instance_valid(target_ref) else null

		var char_index: int = int(attack.get("char_index", -1))
		if char_index < 0 or char_index >= party.size():
			continue
		var char_data: CharacterData = party[char_index]
		if char_data == null:
			continue

		var gem_type: Block.Type = attack.gem_type as Block.Type
		var gem_count: int = int(attack.get("count", 0))
		var chain_mult: float = float(attack.get("chain_mult", 1.0))
		if manual_target != null and int(sim_hp.get(manual_target, 0)) > 0:
			target = manual_target
		else:
			target = _get_best_sim_target_for_attack(char_data, gem_type, gem_count, chain_mult, sim_hp)
		if target == null:
			continue
		var element_mult: float = battle_manager.get_element_multiplier(gem_type, target.data.element) if target.data != null else 1.0
		var damage: int = int(float(char_data.get_atk() * gem_count) * element_mult * chain_mult)
		var predicted_damage: int = battle_manager.get_enemy_damage_after_passives(target, damage)
		attack["target"] = target
		attack["damage"] = damage
		attack["is_super"] = element_mult > 1.0
		sim_hp[target] = int(sim_hp.get(target, target.current_hp)) - predicted_damage
		if manual_target == target and int(sim_hp.get(target, 0)) <= 0:
			manual_target = null


func _get_best_sim_target_for_attack(character: CharacterData, gem_type: Block.Type, gem_count: int, chain_mult: float, sim_hp: Dictionary) -> Enemy:
	var base_damage: int = character.get_atk() * gem_count
	return _get_best_target_for_damage(gem_type, base_damage, chain_mult, sim_hp)


func _get_best_target_for_damage(gem_type: Block.Type, base_damage: int, damage_mult: float, sim_hp: Dictionary) -> Enemy:
	var kill_enemy: Enemy = null
	var kill_remaining_hp: int = -1
	var kill_raw_damage: int = -1
	var best_enemy: Enemy = null
	var best_effective_damage: int = -1
	var best_raw_damage: int = -1
	for enemy in battle_manager.active_enemies:
		if not is_instance_valid(enemy):
			continue
		var remaining_hp: int = int(sim_hp.get(enemy, 0))
		if remaining_hp <= 0:
			continue
		var element_mult: float = battle_manager.get_element_multiplier(gem_type, enemy.data.element) if enemy.data != null else 1.0
		var raw_damage: int = int(float(base_damage) * element_mult * damage_mult)
		var predicted_damage: int = battle_manager.get_enemy_damage_after_passives(enemy, raw_damage)
		var effective_damage: int = mini(predicted_damage, remaining_hp)
		if predicted_damage >= remaining_hp and (remaining_hp > kill_remaining_hp or (remaining_hp == kill_remaining_hp and raw_damage > kill_raw_damage)):
			kill_enemy = enemy
			kill_remaining_hp = remaining_hp
			kill_raw_damage = raw_damage
		if effective_damage > best_effective_damage or (effective_damage == best_effective_damage and raw_damage > best_raw_damage):
			best_enemy = enemy
			best_effective_damage = effective_damage
			best_raw_damage = raw_damage
	if kill_enemy != null:
		return kill_enemy
	return best_enemy


# ── 攻擊特效 ───────────────────────────────────────────────────


func _attack_vfx_profile_for_count(gem_count: int) -> Dictionary:
	if gem_count > 45:
		return {
			"power_level": 2,
			"duration_scale": 3.0 / (0.49 * 0.70),
			"visual_scale": 3.0,
			"shake": true,
		}
	if gem_count >= 25:
		return {
			"power_level": 1,
			"duration_scale": 3.0 / (0.70 * 0.78),
			"visual_scale": 2.0,
			"shake": true,
		}
	return {
		"power_level": 0,
		"duration_scale": 1.0,
		"visual_scale": 1.0,
		"shake": false,
	}


func _play_attack_hit_screen_shake(power_level: int = 2) -> void:
	if _battle_shake_tween != null and _battle_shake_tween.is_valid():
		_battle_shake_tween.kill()
		_apply_battle_shake_offset(_battle_shake_original_positions, Vector2.ZERO)
	var targets: Array = [board, enemy_container, character_panel, gem_meter, _battle_bg_rect]
	var originals: Dictionary = {}
	for node in targets:
		if is_instance_valid(node) and node.get("position") is Vector2:
			originals[node] = node.position
	if originals.is_empty():
		return
	_battle_shake_original_positions = originals
	var strength: float = 18.0 if power_level >= 2 else 8.0
	var duration: float = 0.32 if power_level >= 2 else 0.18
	var steps: int = 8 if power_level >= 2 else 6
	_battle_shake_tween = create_tween()
	for i in steps:
		var t: float = float(i) / float(maxi(steps - 1, 1))
		var amp: float = strength * (1.0 - t)
		var offset := Vector2(randf_range(-amp, amp), randf_range(-amp, amp))
		_battle_shake_tween.tween_callback(_apply_battle_shake_offset.bind(originals, offset))
		_battle_shake_tween.tween_interval(duration / float(steps))
	_battle_shake_tween.tween_callback(_apply_battle_shake_offset.bind(originals, Vector2.ZERO))
	_battle_shake_tween.tween_callback(func() -> void:
		_battle_shake_original_positions.clear()
	)


func _apply_battle_shake_offset(originals: Dictionary, offset: Vector2) -> void:
	for node in originals:
		if is_instance_valid(node):
			node.position = originals[node] + offset


func _get_enemy_image_center(enemy: Enemy) -> Vector2:
	if is_instance_valid(enemy) and enemy.portrait != null:
		return enemy.portrait.get_global_rect().get_center()
	return enemy.get_global_rect().get_center() if is_instance_valid(enemy) else Vector2.ZERO


## 播放單次攻擊序列：角色卡上彈 → 攻擊特效 → 角色卡回位（全部非阻塞，fire-and-forget）
func _play_attack_sequence(attack: Dictionary) -> void:
	var char_index: int = attack.char_index
	var gem_type: Block.Type = attack.gem_type as Block.Type
	var damage: int = attack.damage
	var gem_count: int = attack.count
	var target_ref: Variant = attack.get("target")
	var target: Enemy = target_ref as Enemy if is_instance_valid(target_ref) else null
	var is_super: bool = attack.get("is_super", false)
	var char_data := party[char_index]
	var chain_mult: float = attack.get("chain_mult", 1.0)
	var vfx_profile: Dictionary = attack.get("vfx_profile", _attack_vfx_profile_for_count(gem_count))

	# 若原目標已失效，嘗試重新選擇一個存活敵人；若無存活敵人則過殺原目標
	if not is_instance_valid(target) or target.current_hp <= 0:
		var new_target: Enemy = _get_best_sim_target_for_attack(char_data, gem_type, gem_count, chain_mult, _get_current_enemy_hp_sim())
		if new_target != null:
			target = new_target
		elif is_instance_valid(target) and target.defer_death:
			pass  # 過殺：繼續攻擊延遲死亡的最後一隻怪
		else:
			target = null

	if target == null:
		return
	var element_mult: float = battle_manager.get_element_multiplier(gem_type, target.data.element) if target.data != null else 1.0
	damage = int(float(char_data.get_atk() * gem_count) * element_mult * chain_mult)
	is_super = element_mult > 1.0
	var mult: float = element_mult

	# 角色卡片向上彈起
	await character_panel.play_card_attack_up(char_index)

	# 根據角色類型播放不同的攻擊特效
	match char_data.character_name:
		"Boar":  # 水屬性 — 斬擊特效 + 治療
			var applied_damage: int = damage
			if is_instance_valid(target):
				var slash := Node2D.new()
				slash.set_script(SlashEffectScript)
				fx_layer.add_child(slash)
				var target_pos := _get_enemy_image_center(target)
				slash.deduct_hp.connect(func():
					if is_instance_valid(target):
						applied_damage = _apply_enemy_damage_with_stage13_floor(target, damage, gem_type)
						_spawn_damage_number(_get_enemy_image_center(target), applied_damage, Block.COLORS[gem_type], true, is_super)
						if bool(vfx_profile.get("shake", false)):
							_play_attack_hit_screen_shake(int(vfx_profile.get("power_level", 2)))
					_play_sfx(_se_impact)
				, CONNECT_ONE_SHOT)
				await slash.play(target_pos)
			_add_log_entry(_format_atk_bbcode(gem_type, gem_count, char_data.get_atk(), applied_damage, 1, mult, chain_mult), gem_type, char_data)
			# 「飲水」被動：治療傷害的 50%
			var heal := battle_manager.get_heal_amount(char_index, applied_damage)
			if heal > 0:
				battle_manager.apply_heal(heal)
				character_panel.show_heal_text(char_index, heal)
			_add_log_entry("%s [b]%s[/b] [color=#44ff88]+%d[/color]" % [_gem_bbcode(gem_type), Locale.tr_ui("Drinking"), heal], gem_type, char_data)
		## ── 浣熊弓箭攻擊（暫時停用，改走預設攻擊，保留備用）──
		# "Raccoon":  # 葉屬性 — 每 3 個寶石發射 1 枝箭，每枝隨機攻擊一個存活敵人
		# 	var arrow_count := ceili(float(gem_count) / 3.0)
		# 	var arrow_damage := char_data.get_atk() * 3
		# 	var card_center: Vector2 = character_panel.get_card_screen_center(char_index)
		# 	var total_arrow_dmg := 0
		# 	var any_super := false
		# 	for arrow_idx in arrow_count:
		# 		var living: Array = []
		# 		for e in enemy_container.get_children():
		# 			if is_instance_valid(e) and (e as Enemy).current_hp > 0:
		# 				living.append(e)
		# 		if living.is_empty():
		# 			for e in enemy_container.get_children():
		# 				if is_instance_valid(e) and (e as Enemy).defer_death:
		# 					living.append(e)
		# 		if living.is_empty():
		# 			break
		# 		var arrow_target: Enemy = living[randi() % living.size()]
		# 		var arrow_mult := battle_manager.get_element_multiplier(char_data.gem_type, arrow_target.data.element)
		# 		var arrow_final := int(arrow_damage * arrow_mult)
		# 		var arrow_super := arrow_mult > 1.0
		# 		if arrow_super:
		# 			any_super = true
		# 		total_arrow_dmg += arrow_final
		# 		var target_pos := arrow_target.get_global_rect().get_center()
		# 		var bullet := Node2D.new()
		# 		bullet.set_script(BulletProjectileScript)
		# 		fx_layer.add_child(bullet)
		# 		var captured_target := arrow_target
		# 		var captured_dmg := arrow_final
		# 		bullet.deduct_hp.connect(func():
		# 			if is_instance_valid(captured_target) and (captured_target.current_hp > 0 or captured_target.defer_death):
		# 				captured_target.take_damage(captured_dmg)
		# 				_spawn_damage_number(captured_target.get_global_rect().get_center(), captured_dmg, Block.COLORS[gem_type], true, arrow_super)
		# 				_play_sfx(_se_impact)
		# 		, CONNECT_ONE_SHOT)
		# 		bullet.play(card_center, target_pos)
		# 		if arrow_idx < arrow_count - 1:
		# 			await get_tree().create_timer(0.2).timeout
		# 	var raccoon_mult: float = 1.5 if any_super else 1.0
		# 	_add_log_entry(_format_atk_bbcode(gem_type, gem_count, char_data.get_atk(), total_arrow_dmg, arrow_count, raccoon_mult, chain_mult), gem_type, char_data)
		# 	await get_tree().create_timer(0.45).timeout
		_:  # 預設攻擊：拖尾弧光從角色卡飛向敵人
			var applied_damage: int = damage
			if is_instance_valid(target):
				var card_center: Vector2 = character_panel.get_card_screen_center(char_index)
				var target_pos := _get_enemy_image_center(target)
				var color: Color = Block.COLORS[gem_type]
				var trail := Node2D.new()
				trail.set_script(TrailProjectileScript)
				fx_layer.add_child(trail)
				var captured_target := target
				var captured_dmg := damage
				trail.deduct_hp.connect(func():
					if is_instance_valid(captured_target) and (captured_target.current_hp > 0 or captured_target.defer_death):
						applied_damage = _apply_enemy_damage_with_stage13_floor(captured_target, captured_dmg, gem_type)
						_spawn_damage_number(_get_enemy_image_center(captured_target), applied_damage, color, true, is_super)
						if bool(vfx_profile.get("shake", false)):
							_play_attack_hit_screen_shake(int(vfx_profile.get("power_level", 2)))
					_play_sfx(_se_impact)
				, CONNECT_ONE_SHOT)
				var attack_duration: float = float(attack.get("attack_vfx_duration", 0.5 * float(vfx_profile.get("duration_scale", 1.0))))
				var power_level: int = int(vfx_profile.get("power_level", 0))
				if trail.has_method("set_visual_size_multiplier"):
					trail.set_visual_size_multiplier(float(vfx_profile.get("visual_scale", 1.0)))
				if power_level > 0 and trail.has_method("launch_power_attack"):
					trail.launch_power_attack(card_center, target_pos, color, attack_duration, 0.0, power_level)
				else:
					trail.launch(card_center, target_pos, color, attack_duration)
				await get_tree().create_timer(attack_duration / TrailProjectileScript.speed_divisor + 0.05).timeout
			_add_log_entry(_format_atk_bbcode(gem_type, gem_count, char_data.get_atk(), applied_damage, 1, mult, chain_mult), gem_type, char_data)

	# Card moves back (non-blocking)
	character_panel.play_card_return(char_index)


func _get_current_enemy_hp_sim() -> Dictionary:
	var sim_hp: Dictionary = {}
	for enemy in battle_manager.active_enemies:
		if is_instance_valid(enemy):
			sim_hp[enemy] = enemy.current_hp
	return sim_hp


# ── responding skills ─────────────────────────────────────────────────

func _execute_responding_skill(resp: Dictionary) -> void:
	var skill_name: String = resp.skill_name
	var upper_type: Block.UpperType = _upper_type_for_response(resp)
	var fuse_gem_type: Block.Type = int(resp.get("gem_type", party[int(resp.char_index)].gem_type))
	if upper_type != Block.UpperType.NONE and Block.upper_type_has_instant(upper_type):
		_place_instant_upper_response(resp, upper_type, fuse_gem_type)
		return
	if upper_type != Block.UpperType.NONE and not _is_instant_response(resp):
		_reset_spell_chain()
	var response_key: Variant = skill_name if upper_type == Block.UpperType.NONE else upper_type
	match response_key:
		"Leaf Storm":
			# Convert 3 gems → leaf, priority RED > BLUE
			var priority: Array[Block.Type] = [Block.Type.RED, Block.Type.BLUE]
			board.convert_gems(Block.Type.GREEN, 3, priority)
			var _rc: CharacterData = party[resp.char_index]
			_add_log_entry("[b]%s[/b] %s ×3" % [Locale.tr_ui("LOG_LEAF_STORM"), _gem_bbcode(Block.Type.GREEN)], Block.Type.GREEN, _rc)
			await get_tree().create_timer(0.4).timeout
		Block.UpperType.FIREBALL:
			# Place a Fireball upper gem at the tapped position
			var pos: Vector2i = board.last_tapped_pos
			board.place_upper_gem(pos, Block.UpperType.FIREBALL)
			_play_sfx(_se_freeze)
			var _fc: CharacterData = party[resp.char_index]
			var _fc_count: int = int(battle_manager.turn_gem_blasts.get(fuse_gem_type, 0))
			_add_log_entry(_format_fuse_bbcode(fuse_gem_type, _fc_count, Block.UpperType.FIREBALL), fuse_gem_type, _fc)
			await get_tree().create_timer(0.15).timeout
		Block.UpperType.FIRE_PILLAR_X, Block.UpperType.FIRE_PILLAR_Y:
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
			var _pc_count: int = int(battle_manager.turn_gem_blasts.get(fuse_gem_type, 0))
			_add_log_entry(_format_fuse_bbcode(fuse_gem_type, _pc_count, pillar_type), fuse_gem_type, _pc)
			await get_tree().create_timer(0.15).timeout
		Block.UpperType.SAINT_CROSS:
			# Place a Saint Cross upper gem at the tapped position
			var pos: Vector2i = board.last_tapped_pos
			board.place_upper_gem(pos, Block.UpperType.SAINT_CROSS)
			_play_sfx(_se_freeze)
			var _hc: CharacterData = party[resp.char_index]
			var _hc_count: int = int(battle_manager.turn_gem_blasts.get(fuse_gem_type, 0))
			_add_log_entry(_format_fuse_bbcode(fuse_gem_type, _hc_count, Block.UpperType.SAINT_CROSS), fuse_gem_type, _hc)
			await get_tree().create_timer(0.15).timeout
		Block.UpperType.LEAF_SHIELD:
			# Place a Leaf Shield upper gem at the tapped position
			var pos: Vector2i = board.last_tapped_pos
			board.place_upper_gem(pos, Block.UpperType.LEAF_SHIELD, Block.Type.GREEN)
			_play_sfx(_se_freeze)
			var _lc: CharacterData = party[resp.char_index]
			var _lc_count: int = int(battle_manager.turn_gem_blasts.get(fuse_gem_type, 0))
			_add_log_entry(_format_fuse_bbcode(fuse_gem_type, _lc_count, Block.UpperType.LEAF_SHIELD), fuse_gem_type, _lc)
			await get_tree().create_timer(0.15).timeout
		Block.UpperType.SNOWBALL:
			# Place a Snowball upper gem at the tapped position
			var pos: Vector2i = board.last_tapped_pos
			board.place_upper_gem(pos, Block.UpperType.SNOWBALL, Block.Type.BLUE)
			_play_sfx(_se_freeze)
			var _sc: CharacterData = party[resp.char_index]
			var _sc_count: int = int(battle_manager.turn_gem_blasts.get(fuse_gem_type, 0))
			_add_log_entry(_format_fuse_bbcode(fuse_gem_type, _sc_count, Block.UpperType.SNOWBALL), fuse_gem_type, _sc)
			await get_tree().create_timer(0.15).timeout
		Block.UpperType.LIGHT_SHIELD:
			var pos: Vector2i = board.last_tapped_pos
			if not board.place_upper_gem(pos, Block.UpperType.LIGHT_SHIELD, Block.Type.LIGHT):
				return
			_play_sfx(_se_freeze)
			var _dc: CharacterData = party[resp.char_index]
			var _dc_count: int = int(battle_manager.turn_gem_blasts.get(fuse_gem_type, 0))
			_add_log_entry(_format_fuse_bbcode(fuse_gem_type, _dc_count, Block.UpperType.LIGHT_SHIELD), fuse_gem_type, _dc)
			await get_tree().create_timer(0.15).timeout
		Block.UpperType.WATER_SLASH:
			# Place a Water Slash upper gem (always vertical type — chain logic ignores X/Y orientation)
			var pos: Vector2i = board.last_tapped_pos
			var slash_type: Block.UpperType = Block.UpperType.WATER_SLASH
			board.place_upper_gem(pos, slash_type)
			_play_sfx(_se_freeze)
			var _wc: CharacterData = party[resp.char_index]
			var _wc_count: int = int(battle_manager.turn_gem_blasts.get(fuse_gem_type, 0))
			_add_log_entry(_format_fuse_bbcode(fuse_gem_type, _wc_count, slash_type), fuse_gem_type, _wc)
			await get_tree().create_timer(0.15).timeout
		Block.UpperType.PORCUPINE:
			# 召喚豪豬：每回合攻擊敵人
			var pos: Vector2i = board.last_tapped_pos
			board.place_upper_gem(pos, Block.UpperType.PORCUPINE, Block.Type.GREEN)
			_play_sfx(_se_freeze)
			var _pc2: CharacterData = party[resp.char_index]
			var _pc2_count: int = int(battle_manager.turn_gem_blasts.get(fuse_gem_type, 0))
			_add_log_entry(_format_fuse_bbcode(fuse_gem_type, _pc2_count, Block.UpperType.PORCUPINE), fuse_gem_type, _pc2)
			await get_tree().create_timer(0.15).timeout
		Block.UpperType.TURTLE:
			# 召喚烏龜：每回合回復玩家 HP
			var pos: Vector2i = board.last_tapped_pos
			board.place_upper_gem(pos, Block.UpperType.TURTLE, Block.Type.GREEN)
			_play_sfx(_se_freeze)
			var _tc: CharacterData = party[resp.char_index]
			var _tc_count: int = int(battle_manager.turn_gem_blasts.get(fuse_gem_type, 0))
			_add_log_entry(_format_fuse_bbcode(fuse_gem_type, _tc_count, Block.UpperType.TURTLE), fuse_gem_type, _tc)
			await get_tree().create_timer(0.15).timeout
		Block.UpperType.BAMBOO_SUPPLY:
			# 竹葉補給：在點擊處生成竹葉補給寶石；爆破時消除周圍 8 格並回復觸發者 HP
			var pos: Vector2i = board.last_tapped_pos
			board.place_upper_gem(pos, Block.UpperType.BAMBOO_SUPPLY, Block.Type.GREEN)
			_play_sfx(_se_freeze)
			var _bc: CharacterData = party[resp.char_index]
			var _bc_count: int = int(battle_manager.turn_gem_blasts.get(fuse_gem_type, 0))
			_add_log_entry(_format_fuse_bbcode(fuse_gem_type, _bc_count, Block.UpperType.BAMBOO_SUPPLY), fuse_gem_type, _bc)
			await get_tree().create_timer(0.15).timeout
		Block.UpperType.WOOD_SPEAR_UP, Block.UpperType.WOOD_SPEAR_DOWN:
			var pos: Vector2i = board.last_tapped_pos
			var spear_type: Block.UpperType = board.get_wood_spear_type_for_last_tap()
			board.place_upper_gem(pos, spear_type, Block.Type.GREEN)
			var _gc: CharacterData = party[resp.char_index]
			var skill_order: int = int(resp.get("skill_order", 0))
			var spear_block: Block = board.grid[pos.x][pos.y]
			if spear_block != null:
				spear_block.intrinsic_bonus = SkillUpgradeUtils.wood_spear_intrinsic_bonus(_gc, skill_order)
				spear_block.wood_spear_pierce_breakable = SkillUpgradeUtils.wood_spear_pierces_breakable(_gc, skill_order)
			_play_sfx(_se_freeze)
			var _gc_count: int = int(battle_manager.turn_gem_blasts.get(fuse_gem_type, 0))
			_add_log_entry(_format_fuse_bbcode(fuse_gem_type, _gc_count, spear_type), fuse_gem_type, _gc)
			await get_tree().create_timer(0.15).timeout


func _register_spell_chain() -> float:
	_spell_chain_count += 1
	if _spell_chain_count >= 2:
		_update_spell_chain_label(_spell_chain_count)
		_play_chain_sfx(_spell_chain_count)
	return 1.0 + float(_spell_chain_count - 1) * 0.10


func _reset_spell_chain(fade: bool = true) -> void:
	if _spell_chain_count == 0 and not is_instance_valid(_spell_chain_label) and not is_instance_valid(_spell_chain_header):
		return
	_spell_chain_count = 0
	_fade_spell_chain_label(_spell_chain_label, fade)
	_spell_chain_label = null
	_fade_spell_chain_label(_spell_chain_header, fade)
	_spell_chain_header = null
	_position_combo_ui()


func _fade_spell_chain_label(label: Control, fade: bool) -> void:
	if not is_instance_valid(label):
		return
	if fade:
		var fade_tw := create_tween()
		fade_tw.tween_property(label, "modulate:a", 0.0, 0.25)
		fade_tw.tween_callback(label.queue_free)
	else:
		label.queue_free()


func _update_spell_chain_label(count: int) -> void:
	var base_font_size: int = 44
	var font_bonus: int = mini((count - 1) * 5, 50)
	var font_size: int = base_font_size + font_bonus

	if not is_instance_valid(_spell_chain_header):
		_spell_chain_header = Label.new()
		_spell_chain_header.text = Locale.tr_ui("SPELL_CHAIN")
		_spell_chain_header.add_theme_font_size_override("font_size", 22)
		_spell_chain_header.add_theme_color_override("font_color", Color(0.65, 0.90, 1.0))
		_spell_chain_header.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_spell_chain_header.add_theme_constant_override("outline_size", 4)
		_spell_chain_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_spell_chain_header.z_index = 100
		fx_layer.add_child(_spell_chain_header)

	if not is_instance_valid(_spell_chain_label):
		_spell_chain_label = Control.new()
		_spell_chain_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_spell_chain_label.z_index = 100
		fx_layer.add_child(_spell_chain_label)

	_build_spell_chain_wavy_value(_spell_chain_label, "×%d!" % count, font_size)
	_spell_chain_label.modulate.a = 1.0
	_spell_chain_label.scale = Vector2(0.5, 0.5)
	_position_combo_ui()

	var tw := create_tween()
	tw.tween_property(_spell_chain_label, "scale", Vector2(1.4, 1.4), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tw.tween_property(_spell_chain_label, "scale", Vector2(1.0, 1.0), 0.1).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)


func _build_spell_chain_wavy_value(container: Control, text: String, font_size: int) -> void:
	if container == null:
		return
	for child in container.get_children():
		child.visible = false
		child.queue_free()
	var x_offset := 0.0
	var char_width: float = maxf(float(font_size) * 0.56, 18.0)
	for i in text.length():
		var char_label := Label.new()
		char_label.text = text.substr(i, 1)
		char_label.add_theme_font_size_override("font_size", font_size)
		char_label.add_theme_color_override("font_color", Color(0.78, 0.94, 1.0))
		char_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		char_label.add_theme_constant_override("outline_size", 8)
		char_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		char_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		char_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		char_label.position = Vector2(x_offset, 0.0)
		char_label.size = Vector2(char_width, float(font_size) + SPELL_CHAIN_WAVE_AMPLITUDE * 2.0)
		container.add_child(char_label)
		_start_spell_chain_char_wave(char_label, i)
		x_offset += char_width
	container.size = Vector2(x_offset, float(font_size) + SPELL_CHAIN_WAVE_AMPLITUDE * 2.0)
	container.pivot_offset = Vector2(0.0, float(font_size))


func _start_spell_chain_char_wave(char_label: Label, index: int) -> void:
	var delay: float = float(index) * 0.08
	var rise_time := 0.16
	var fall_time := 0.20
	var rest_time: float = maxf(SPELL_CHAIN_WAVE_PERIOD - delay - rise_time - fall_time, 0.04)
	var tw := char_label.create_tween().set_loops()
	tw.tween_interval(delay)
	tw.tween_property(char_label, "position:y", -SPELL_CHAIN_WAVE_AMPLITUDE, rise_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tw.tween_property(char_label, "position:y", 0.0, fall_time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(rest_time)


func _get_current_living_target(gem_type: Block.Type = Block.Type.BLUE, base_damage: int = 1, damage_mult: float = 1.0) -> Enemy:
	var target: Enemy = battle_manager.targeted_enemy
	if is_instance_valid(target) and target.current_hp > 0:
		return target
	return _get_best_target_for_damage(gem_type, base_damage, damage_mult, _get_current_enemy_hp_sim())


func _move_block_to_fx_layer_preserving_transform(block: Block, z_index: int) -> void:
	if block == null or not is_instance_valid(block) or fx_layer == null:
		return
	var preserved_transform: Transform2D = block.global_transform
	var block_parent: Node = block.get_parent()
	if block_parent != null:
		block_parent.remove_child(block)
	fx_layer.add_child(block)
	block.global_transform = preserved_transform
	block.z_index = z_index


func _resolve_iceball_instant(pos: Vector2i, resp: Dictionary, spell_mult: float, source_block: Variant = null) -> void:
	if pos.x < 0 or pos.y < 0 or pos.x >= board.columns or pos.y >= board.rows:
		return
	var block: Block = null
	if is_instance_valid(source_block):
		block = source_block as Block
	if block == null:
		block = board.grid[pos.x][pos.y]
		if block != null:
			board.grid[pos.x][pos.y] = null
			_move_block_to_fx_layer_preserving_transform(block, 42)
	if block == null:
		return

	var start_global: Vector2 = block.global_position
	block.modulate = Color.WHITE
	block.refresh_upper_particle_system()

	var caster_index: int = int(resp.get("char_index", -1))
	var caster: CharacterData = party[caster_index] if caster_index >= 0 and caster_index < party.size() else null
	var magic_value: int = caster.get_magic() if caster != null else 1
	var base_damage: int = magic_value * ICEBALL_MAGIC_MULT
	var target: Enemy = _get_current_living_target(Block.Type.BLUE, base_damage, spell_mult)
	if target == null:
		var fallback_texture: Texture2D = Block.UPPER_GEM_TEXTURES.get(Block.UpperType.ICEBALL, null) as Texture2D
		DebrisVfx.play(fx_layer, fallback_texture, start_global, ICEBALL_DEBRIS_SHARDS, Vector2(0.78, 1.18), Vector2(0.65, 0.95), 110, Color(0.72, 0.90, 1.0, 1.0))
		block.queue_free()
		return

	var element_mult: float = battle_manager.get_element_multiplier(Block.Type.BLUE, target.data.element) if target.data != null else 1.0
	var final_damage: int = maxi(1, int(float(base_damage) * element_mult * spell_mult))
	var is_super: bool = element_mult > 1.0

	for enemy in battle_manager.active_enemies:
		if is_instance_valid(enemy):
			enemy.defer_death = true

	var float_tw := create_tween()
	float_tw.tween_property(block, "global_position:y", start_global.y - 32.0, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	await float_tw.finished

	var target_pos: Vector2 = _get_enemy_image_center(target) if is_instance_valid(target) else start_global
	var fly_tw := create_tween().set_parallel(true)
	fly_tw.tween_property(block, "global_position", target_pos, 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	fly_tw.tween_property(block, "scale", Vector2(1.62, 1.62), 0.4)
	fly_tw.tween_property(block, "rotation", block.rotation + TAU, 0.4)
	fly_tw.tween_property(block, "modulate:a", 0.55, 0.28).set_delay(0.12)
	await fly_tw.finished

	if is_instance_valid(target) and (target.current_hp > 0 or target.defer_death):
		var applied_damage: int = target.take_damage(final_damage)
		_spawn_damage_number(_get_enemy_image_center(target), applied_damage, Block.COLORS[Block.Type.BLUE], true, is_super)
	_play_sfx(_se_impact)
	var ice_texture: Texture2D = Block.UPPER_GEM_TEXTURES.get(Block.UpperType.ICEBALL, null) as Texture2D
	DebrisVfx.play(fx_layer, ice_texture, target_pos, ICEBALL_DEBRIS_SHARDS, Vector2(0.78, 1.18), Vector2(0.65, 0.95), 110, Color(0.72, 0.90, 1.0, 1.0))
	if is_instance_valid(block):
		block.queue_free()

	var mult_text := ""
	if element_mult > 1.0:
		mult_text += " ×%.1f" % element_mult
	if spell_mult > 1.0:
		mult_text += " ×%.1f%s" % [spell_mult, Locale.tr_ui("SPELL_CHAIN_SHORT")]
	_add_log_entry("[b]%s[/b] %s MAG%d%s = %d" % [Locale.tr_ui("Iceball"), _gem_bbcode(Block.Type.BLUE), base_damage, mult_text, final_damage], Block.Type.BLUE, caster)

	for enemy in battle_manager.active_enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.defer_death = false
			if enemy.current_hp <= 0:
				enemy.finalize_death()


func _resolve_leaf_ray_instant(pos: Vector2i, resp: Dictionary, spell_mult: float, source_block: Variant = null) -> void:
	if pos.x < 0 or pos.y < 0 or pos.x >= board.columns or pos.y >= board.rows:
		return
	var block: Block = null
	if is_instance_valid(source_block):
		block = source_block as Block
	if block == null:
		block = board.grid[pos.x][pos.y]
		if block != null:
			board.grid[pos.x][pos.y] = null
			_move_block_to_fx_layer_preserving_transform(block, 95)
	if block == null:
		return

	var start_global: Vector2 = block.global_position
	block.modulate = Color.WHITE
	block.refresh_upper_particle_system()

	var caster_index: int = int(resp.get("char_index", -1))
	var caster: CharacterData = party[caster_index] if caster_index >= 0 and caster_index < party.size() else null
	var magic_value: int = caster.get_magic() if caster != null else 1
	var base_damage: int = maxi(1, int(round(float(magic_value) * LEAF_RAY_MAGIC_MULT)))
	var target: Enemy = _get_current_living_target(Block.Type.GREEN, base_damage, spell_mult)
	var leaf_color: Color = Block.COLORS.get(Block.Type.GREEN, Color(0.30, 0.69, 0.31))
	if target == null:
		var fallback_texture: Texture2D = Block.UPPER_GEM_TEXTURES.get(Block.UpperType.LEAF_RAY, null) as Texture2D
		DebrisVfx.play(fx_layer, fallback_texture, start_global, LEAF_RAY_DEBRIS_SHARDS, Vector2(0.80, 1.18), Vector2(0.70, 1.0), 120, leaf_color)
		block.queue_free()
		return

	var element_mult: float = battle_manager.get_element_multiplier(Block.Type.GREEN, target.data.element) if target.data != null else 1.0
	var final_damage: int = maxi(1, int(float(base_damage) * element_mult * spell_mult))
	var is_super: bool = element_mult > 1.0

	for enemy in battle_manager.active_enemies:
		if is_instance_valid(enemy):
			enemy.defer_death = true

	var leaf_texture: Texture2D = Block.UPPER_GEM_TEXTURES.get(Block.UpperType.LEAF_RAY, null) as Texture2D
	var beam_start: Vector2 = block.global_position
	var target_pos: Vector2 = _get_enemy_image_center(target) if is_instance_valid(target) else beam_start
	var laser := Node2D.new()
	laser.set_script(LeafRayLaserVfxScript)
	if laser.has_method("set_shared_vfx_layer"):
		laser.call("set_shared_vfx_layer", _get_battle_vfx_3d_layer())
	fx_layer.add_child(laser)
	laser.start_following(block, target_pos, LEAF_RAY_LASER_DURATION)

	var recoil_dir: Vector2 = (beam_start - target_pos).normalized()
	if recoil_dir.length_squared() < 0.001:
		recoil_dir = Vector2(0.0, -1.0)
	var recoil_tw := create_tween().set_parallel(true)
	recoil_tw.tween_property(block, "global_position", beam_start + recoil_dir * 46.0, LEAF_RAY_LASER_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	recoil_tw.tween_property(block, "rotation", block.rotation + recoil_dir.x * 0.45, LEAF_RAY_LASER_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_play_sfx(_se_solar_beam_shining)

	var applied_damage := 0
	if is_instance_valid(target) and (target.current_hp > 0 or target.defer_death):
		var applied_total: int = target.get_damage_after_passives(final_damage)
		var tick_count: int = maxi(1, ceili(LEAF_RAY_LASER_DURATION / LEAF_RAY_DAMAGE_TICK_INTERVAL))
		var tick_base: int = floori(float(applied_total) / float(tick_count))
		var tick_remainder: int = applied_total % tick_count
		for tick_index in range(tick_count):
			await get_tree().create_timer(LEAF_RAY_DAMAGE_TICK_INTERVAL).timeout
			if not is_instance_valid(target) or not (target.current_hp > 0 or target.defer_death):
				continue
			var tick_damage: int = tick_base + (1 if tick_index < tick_remainder else 0)
			if tick_damage <= 0:
				continue
			var actual_tick_damage: int = target.take_applied_damage_tick(tick_damage)
			if actual_tick_damage <= 0:
				continue
			applied_damage += actual_tick_damage
			var tick_pos: Vector2 = _get_enemy_image_center(target)
			_spawn_damage_number(tick_pos, actual_tick_damage, leaf_color, true, is_super)
			DebrisVfx.play(fx_layer, leaf_texture, tick_pos, 4, Vector2(0.42, 0.78), Vector2(0.32, 0.52), 118, leaf_color)
	elif is_instance_valid(laser):
		await laser.finished

	if is_instance_valid(block):
		await _play_leaf_ray_gem_falloff(block)

	var mult_text := ""
	if element_mult > 1.0:
		mult_text += " ×%.1f" % element_mult
	if spell_mult > 1.0:
		mult_text += " ×%.1f%s" % [spell_mult, Locale.tr_ui("SPELL_CHAIN_SHORT")]
	_add_log_entry("[b]%s[/b] %s MAG%d%s = %d" % [Locale.tr_ui("Leaf Ray"), _gem_bbcode(Block.Type.GREEN), base_damage, mult_text, applied_damage], Block.Type.GREEN, caster)

	for enemy in battle_manager.active_enemies.duplicate():
		if is_instance_valid(enemy):
			enemy.defer_death = false
			if enemy.current_hp <= 0:
				enemy.finalize_death()


func _play_leaf_ray_gem_falloff(block: Node2D) -> void:
	if not is_instance_valid(block):
		return
	var start_pos: Vector2 = block.global_position
	var start_scale: Vector2 = block.scale
	var side: float = 1.0 if randf() >= 0.5 else -1.0
	var push_x: float = side * randf_range(42.0, 78.0)
	var jump_height: float = randf_range(56.0, 84.0)
	var fall_distance: float = randf_range(220.0, 300.0)
	var duration: float = 0.86

	var motion_tw := create_tween().set_parallel(true)
	motion_tw.tween_property(block, "global_position:x", start_pos.x + push_x, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	motion_tw.tween_property(block, "rotation", block.rotation + side * randf_range(1.1, 1.8) * PI, duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	motion_tw.tween_property(block, "scale", start_scale * 0.58, duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	motion_tw.tween_property(block, "modulate:a", 0.0, duration * 0.45).set_delay(duration * 0.55)

	var y_tw := create_tween()
	y_tw.tween_property(block, "global_position:y", start_pos.y - jump_height, duration * 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	y_tw.tween_property(block, "global_position:y", start_pos.y + fall_distance, duration * 0.72).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await y_tw.finished
	if is_instance_valid(block):
		block.queue_free()


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
	_position_combo_ui()


## 連鎖爆炸中波及特殊高階寶石時：即時觸發其獨有效果
func _on_upper_gem_chain_triggered(upper_type: Block.UpperType) -> void:
	_live_chain_count += 1
	if _live_chain_count >= 2:
		_update_chain_label(_live_chain_count)
		_play_chain_sfx(_live_chain_count)
	match upper_type:
		Block.UpperType.LEAF_SHIELD:
			# 葉盾：治療 Pan ATK × 5
			var panda_data: CharacterData = null
			var panda_index := -1
			for i in party.size():
				if party[i].character_name == "Pan":
					panda_data = party[i]
					panda_index = i
					break
			var heal_atk: int = panda_data.get_atk() if panda_data != null else 5
			var heal_amount: int = heal_atk * 5
			battle_manager.apply_heal(heal_amount)
			if panda_index >= 0:
				character_panel.show_heal_text(panda_index, heal_amount)
			_add_log_entry("[b]%s[/b] %s %s %d HP" % [Locale.tr_ui("Leaf Shield"), _gem_bbcode(Block.Type.GREEN), Locale.tr_ui("LOG_HEAL"), heal_amount], Block.Type.GREEN, panda_data)
		Block.UpperType.SAINT_CROSS:
			# 聖十字：標記需要在結算時執行聖十字效果
			_pending_saint_cross_count += 1
		Block.UpperType.BAMBOO_SUPPLY:
			# 竹葉補給：治療 Pan magic × BAMBOO_SUPPLY_HEAL_MULT
			var panda_data2: CharacterData = null
			var panda_index2 := -1
			for i in party.size():
				if party[i].character_name == "Pan":
					panda_data2 = party[i]
					panda_index2 = i
					break
			var magic_val: int = panda_data2.get_magic() if panda_data2 != null else 5
			var heal_amount2: int = int(round(float(magic_val) * BAMBOO_SUPPLY_HEAL_MULT))
			battle_manager.apply_heal(heal_amount2)
			if panda_index2 >= 0:
				character_panel.show_heal_text(panda_index2, heal_amount2)
			_add_log_entry("[b]%s[/b] %s %s %d HP" % [Locale.tr_ui("Bamboo Supply"), _gem_bbcode(Block.Type.GREEN), Locale.tr_ui("LOG_HEAL"), heal_amount2], Block.Type.GREEN, panda_data2)
		Block.UpperType.LIGHT_SHIELD:
			var duan_data: CharacterData = null
			for c: CharacterData in party:
				if c != null and (c.character_name == "敦" or c.active_skill_name == "希望之光"):
					duan_data = c
					break
			var shield_source_hp: int = duan_data.get_max_hp() if duan_data != null else 60
			var shield_amount: int = maxi(1, int(round(float(shield_source_hp) * 0.65)))
			battle_manager.add_player_shield(shield_amount)
			_spawn_damage_number(player_hp_fill.get_global_rect().get_center(), shield_amount, Color(0.55, 0.85, 1.0), true, false)
			_add_log_entry("[b]%s[/b] %s +%d Shield" % [Locale.tr_ui("光之盾"), _upper_gem_bbcode(Block.UpperType.LIGHT_SHIELD), shield_amount], Block.Type.LIGHT, duan_data)

## 高階寶石爆炸完成後：統一結算所有累積的獨有效果 + VFX 攻擊
func _on_upper_blast_completed(chain_count: int, blasted_by_type: Dictionary, _triggered_upper: Block.UpperType) -> void:
	var chain_mult: float = 1.0 + (chain_count - 1) * 0.10
	var had_saint_cross := _pending_saint_cross_count > 0

	# ── 結算所有累積的聖十字效果（單一目標）──
	if had_saint_cross:
		var total_enemy_gems := 0
		for bt in blasted_by_type:
			total_enemy_gems += blasted_by_type[bt] as int
		# 找到索爾角色計算 ATK
		var husky_data: CharacterData = null
		var husky_index := -1
		for i in party.size():
			if party[i].gem_type == Block.Type.LIGHT:
				husky_data = party[i]
				husky_index = i
				break
		var base_atk := husky_data.get_atk() if husky_data != null else 5
		# 聖十字傷害：原 ×0.08 版本再降低 10 倍。
		var holy_damage := int(total_enemy_gems * 50 * base_atk * chain_mult * _pending_saint_cross_count * 0.008)
		# 選定單一目標：有手動瞄準時優先，否則挑有效傷害最高的敵人
		var saint_target: Enemy = battle_manager.targeted_enemy
		if saint_target == null or not is_instance_valid(saint_target) or saint_target.current_hp <= 0:
			saint_target = _get_best_target_for_damage(Block.Type.LIGHT, holy_damage, 1.0, _get_current_enemy_hp_sim())
		# 開啟延遲死亡：即使聖十字打死敵人，後續本波 VFX 攻擊仍可找到目標（過殺）
		for enemy in battle_manager.active_enemies:
			if is_instance_valid(enemy):
				enemy.defer_death = true
		var light_color: Color = Block.COLORS[Block.Type.LIGHT]
		if saint_target != null:
			var target_pos: Vector2 = _get_enemy_image_center(saint_target)
			# ── 敵人受擊動畫：SwordOfJustice_spritesheet.png 1 row × 13 cols ──
			const SWORD_OF_JUSTICE_FRAMES := 13
			const SWORD_OF_JUSTICE_DURATION := 0.6
			var sword_node := Node2D.new()
			sword_node.position = target_pos
			sword_node.z_index = 30
			fx_layer.add_child(sword_node)
			var sword_sprite := Sprite2D.new()
			var sword_tex: Texture2D = load("res://assets/animation/SwordOfJustice_spritesheet.png") as Texture2D
			if sword_tex != null:
				sword_sprite.texture = sword_tex
			sword_sprite.hframes = SWORD_OF_JUSTICE_FRAMES
			sword_sprite.vframes = 1
			sword_sprite.frame = 0
			sword_sprite.scale = Vector2(1.4, 1.4)
			sword_node.add_child(sword_sprite)
			var frame_dur: float = SWORD_OF_JUSTICE_DURATION / SWORD_OF_JUSTICE_FRAMES
			var captured_enemy: Enemy = saint_target
			var captured_dmg: int = holy_damage
			# 在中途幀觸發扣血
			get_tree().create_timer(SWORD_OF_JUSTICE_DURATION * 0.45).timeout.connect(func() -> void:
				if is_instance_valid(captured_enemy):
					var applied_dmg: int = _apply_enemy_damage_with_stage13_floor(captured_enemy, captured_dmg, Block.Type.LIGHT)
					_spawn_damage_number(_get_enemy_image_center(captured_enemy), applied_dmg, light_color, true)
				_play_sfx(_se_impact)
			, CONNECT_ONE_SHOT)
			var sword_tw := create_tween()
			for fi: int in SWORD_OF_JUSTICE_FRAMES:
				var frame_index := fi
				sword_tw.tween_callback(func() -> void:
					if is_instance_valid(sword_sprite):
						sword_sprite.frame = frame_index
				)
				sword_tw.tween_interval(frame_dur)
			sword_tw.tween_callback(sword_node.queue_free)
			await get_tree().create_timer(0.4).timeout
		# 回復 20% 最大血量（每個聖十字各回復一次）
		var heal_amount := int(floor(battle_manager.player_max_hp * 0.2)) * _pending_saint_cross_count
		battle_manager.apply_heal(heal_amount)
		if husky_index >= 0:
			character_panel.show_heal_text(husky_index, heal_amount)
		var cross_str := "×%d " % _pending_saint_cross_count if _pending_saint_cross_count > 1 else ""
		var chain_str := (" ×%.1f鎖" % chain_mult) if chain_count >= 2 else ""
		_add_log_entry("[b]%s[/b] %s%s %d × ⚔%d%s = %d %s%d" % [Locale.tr_ui("LOG_SAINT_CROSS"), cross_str, _gem_bbcode(Block.Type.LIGHT), total_enemy_gems, base_atk, chain_str, holy_damage, Locale.tr_ui("LOG_HEAL"), heal_amount], Block.Type.LIGHT, husky_data)
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
	_position_combo_ui()

	# 重置狀態
	_is_upper_gem_turn = false
	_chain_atk_bonus = 0.0
	if _stage13_owen_light_hit_pending:
		_stage13_owen_light_hit_pending = false
		await _run_stage13_finale_and_win()
		return
	if _stage13_victory_triggered:
		return

	await _end_player_turn()


## 建立或更新連鏈數字標籤，並播放 pop 彈跳動畫
func _update_chain_label(count: int) -> void:
	# 每多一連鎖 +5 fontsize，加成上限 +50
	var base_font_size: int = 44
	var font_bonus: int = mini((count - 1) * 5, 50)
	var font_size: int = base_font_size + font_bonus
	var pop_scale: float = 1.4

	# "Chain" 靜態標籤 — 只建立一次
	if not is_instance_valid(_live_chain_header):
		_live_chain_header = Label.new()
		_live_chain_header.text = "Chain"
		_live_chain_header.add_theme_font_size_override("font_size", 22)
		_live_chain_header.add_theme_color_override("font_color", Color.WHITE)
		_live_chain_header.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_live_chain_header.add_theme_constant_override("outline_size", 4)
		_live_chain_header.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_live_chain_header.z_index = 100
		fx_layer.add_child(_live_chain_header)

	# "×N!" 動態標籤 — 只建立一次，之後只更新內容
	if not is_instance_valid(_live_chain_label):
		_live_chain_label = Label.new()
		_live_chain_label.add_theme_color_override("font_color", Color.WHITE)
		_live_chain_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		_live_chain_label.add_theme_constant_override("outline_size", 8)
		_live_chain_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_live_chain_label.z_index = 100
		fx_layer.add_child(_live_chain_label)

	_live_chain_label.text = "×%d!" % count
	_live_chain_label.add_theme_font_size_override("font_size", font_size)
	_live_chain_label.modulate.a = 1.0
	# 從左下角 pivot 放大（避免向螢幕中央偏移）
	_live_chain_label.pivot_offset = Vector2(0.0, font_size)
	_live_chain_label.scale = Vector2(0.5, 0.5)
	_position_combo_ui()

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
			_add_log_entry("%s：3→%s" % [Locale.tr_ui("Photosynthesis"), _gem_bbcode(Block.Type.GREEN)], Block.Type.GREEN, c)
			await get_tree().create_timer(0.4).timeout


# ── 主動技能 ─────────────────────────────────────────────────

## 角色主動技能觸發（玩家點擊角色卡片）
func _on_active_skill_activated(char_index: int) -> void:
	await _handle_active_skill(char_index)
	active_skill_finished.emit(char_index)


func _on_active_skill_selection_cancelled(char_index: int) -> void:
	if not _active_board_selection_running:
		return
	if char_index != _active_board_selection_char_index:
		return
	board.cancel_selection_mode()


func _on_board_selection_preview_changed(positions: Array) -> void:
	_active_selection_preview_positions.clear()
	for value in positions:
		_active_selection_preview_positions.append(value as Vector2i)
	_refresh_active_selection_dim_holes()


func _show_active_selection_dim(char_index: int) -> void:
	_clear_active_selection_dim_immediate()
	_active_selection_dim_layer = CanvasLayer.new()
	_active_selection_dim_layer.layer = ACTIVE_SELECTION_DIM_LAYER
	add_child(_active_selection_dim_layer)

	var overlay: Control = SelectionDimOverlayScript.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.modulate.a = 0.0
	overlay.set("dim_color", Color(0, 0, 0, ACTIVE_SELECTION_DIM_ALPHA))
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_active_selection_dim_layer.add_child(overlay)
	_active_selection_dim_overlay = overlay
	_refresh_active_selection_dim_holes(char_index)

	_active_selection_dim_tween = create_tween()
	_active_selection_dim_tween.tween_property(overlay, "modulate:a", 1.0, ACTIVE_SELECTION_DIM_FADE).set_ease(Tween.EASE_OUT)


func _hide_active_selection_dim() -> void:
	if _active_selection_dim_overlay == null and _active_selection_dim_layer == null:
		return
	if _active_selection_dim_tween != null and _active_selection_dim_tween.is_valid():
		_active_selection_dim_tween.kill()
	var overlay: Control = _active_selection_dim_overlay
	var layer: CanvasLayer = _active_selection_dim_layer
	_active_selection_dim_overlay = null
	_active_selection_dim_layer = null
	_active_selection_dim_tween = null
	if overlay == null or not is_instance_valid(overlay):
		if is_instance_valid(layer):
			layer.queue_free()
		return
	var tween := create_tween()
	tween.tween_property(overlay, "modulate:a", 0.0, ACTIVE_SELECTION_DIM_FADE).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		if is_instance_valid(layer):
			layer.queue_free()
	)
	await tween.finished


func _clear_active_selection_dim_immediate() -> void:
	if _active_selection_dim_tween != null and _active_selection_dim_tween.is_valid():
		_active_selection_dim_tween.kill()
	_active_selection_dim_tween = null
	if is_instance_valid(_active_selection_dim_layer):
		_active_selection_dim_layer.queue_free()
	_active_selection_dim_layer = null
	_active_selection_dim_overlay = null


func _refresh_active_selection_dim_holes(char_index: int = -999) -> void:
	if _active_selection_dim_overlay == null or not is_instance_valid(_active_selection_dim_overlay):
		return
	var active_index: int = char_index if char_index != -999 else _active_board_selection_char_index
	var clear_rects: Array[Rect2] = _get_board_selection_clear_rects()
	var card_rect: Rect2 = _get_active_selection_card_rect(active_index)
	if card_rect.size.x > 0.0 and card_rect.size.y > 0.0:
		clear_rects.append(card_rect.grow(4.0))
	_active_selection_dim_overlay.call("set_clear_rects", clear_rects)


func _get_board_selection_clear_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if not board.has_method("get_selection_valid_centers"):
		return rects
	var centers: Array = board.get_selection_valid_centers()
	for value in centers:
		var pos: Vector2i = value as Vector2i
		rects.append(_board_cell_rect(pos))
	for preview_pos in _active_selection_preview_positions:
		rects.append(_board_cell_rect(preview_pos))
	return rects


func _board_cell_rect(pos: Vector2i) -> Rect2:
	var top_left: Vector2 = board.to_global(Vector2(pos.x * board.CELL_SIZE, pos.y * board.CELL_SIZE))
	var bottom_right: Vector2 = board.to_global(Vector2((pos.x + 1) * board.CELL_SIZE, (pos.y + 1) * board.CELL_SIZE))
	var rect_pos: Vector2 = Vector2(minf(top_left.x, bottom_right.x), minf(top_left.y, bottom_right.y))
	var rect_size: Vector2 = Vector2(absf(bottom_right.x - top_left.x), absf(bottom_right.y - top_left.y))
	return Rect2(rect_pos, rect_size).grow(1.0)


func _get_active_selection_card_rect(char_index: int) -> Rect2:
	var card: Control = character_panel.get_card(char_index)
	if card == null:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	return card.get_global_rect()


func _run_board_selection_active_skill(char_index: int, convert_type: Block.Type, pattern: String = "cross", max_count: int = 1) -> Dictionary:
	if _active_board_selection_running:
		return {"positions": [], "cancelled": true}
	_active_board_selection_running = true
	_active_board_selection_char_index = char_index
	_active_selection_preview_positions.clear()
	board.enter_selection_mode(convert_type, pattern, max_count)
	character_panel.enter_active_selection_cancel_mode(char_index)
	_show_active_selection_dim(char_index)
	var result: Dictionary = await board.selection_finished
	await _hide_active_selection_dim()
	character_panel.exit_active_selection_cancel_mode()
	_active_selection_preview_positions.clear()
	_active_board_selection_char_index = -1
	_active_board_selection_running = false
	if not result.has("positions"):
		result["positions"] = []
	if not result.has("cancelled"):
		result["cancelled"] = false
	return result


func _get_random_convertible_cells(to_type: Block.Type, max_count: int) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	for x in board.columns:
		for y in board.rows:
			var b: Block = board.grid[x][y]
			if b == null or b.is_obstacle() or b.is_upper_gem():
				continue
			if b.block_type == to_type:
				continue
			candidates.append(Vector2i(x, y))
	candidates.shuffle()
	var result: Array[Vector2i] = []
	var n: int = mini(max_count, candidates.size())
	for i in n:
		result.append(candidates[i])
	return result


func _handle_active_skill(char_index: int) -> void:
	if board.is_busy or _active_board_selection_running:
		return
	if not _is_active_unlocked_for_battle(char_index):
		return
	if not battle_manager.is_active_ready(char_index):
		return

	var c: CharacterData = party[char_index]
	match c.active_skill_name:
		"Attack Form":
			# 攻擊形態：將所有火寶石轉為水寶石
			battle_manager.use_active_skill(char_index)
			board.convert_all_of_type(Block.Type.RED, Block.Type.BLUE)
			_add_log_entry("%s：%s→%s" % [Locale.tr_ui("Attack Form"), _gem_bbcode(Block.Type.RED), _gem_bbcode(Block.Type.BLUE)], Block.Type.BLUE, c)
			await get_tree().create_timer(0.4).timeout
			_update_skill_ui()
		"Tranquil Mirror":
			# 止水明鏡：將棋盤上所有火寶石轉換為水寶石
			battle_manager.use_active_skill(char_index)
			board.convert_all_of_type(Block.Type.RED, Block.Type.BLUE)
			_add_log_entry("%s：%s→%s" % [Locale.tr_ui("Tranquil Mirror"), _gem_bbcode(Block.Type.RED), _gem_bbcode(Block.Type.BLUE)], Block.Type.BLUE, c)
			await get_tree().create_timer(0.4).timeout
			_update_skill_ui()
		"冰球法印":
			battle_manager.use_active_skill(char_index)
			_play_sfx(_se_water_bubble)
			_update_skill_ui()
			board.is_busy = true
			var centers: Array[Vector2i] = [Vector2i(board.columns - 2, 1), Vector2i(1, board.rows - 2)]
			var converted := 0
			var affected := 0
			var seen: Dictionary = {}
			for center: Vector2i in centers:
				for dx in range(-1, 2):
					for dy in range(-1, 2):
						if dx == 0 and dy == 0:
							continue
						var pos: Vector2i = center + Vector2i(dx, dy)
						if pos.x < 0 or pos.y < 0 or pos.x >= board.columns or pos.y >= board.rows:
							continue
						if seen.has(pos):
							continue
						seen[pos] = true
						var target_block: Block = board.grid[pos.x][pos.y]
						if target_block == null or target_block.is_obstacle() or target_block.is_upper_gem():
							continue
						affected += 1
						if target_block.block_type != Block.Type.BLUE:
							board._animate_gem_morph(target_block, Block.Type.BLUE)
							converted += 1
			_add_log_entry("%s：%d/%d→%s" % [Locale.tr_ui("冰球法印"), converted, affected, _gem_bbcode(Block.Type.BLUE)], Block.Type.BLUE, c)
			await get_tree().create_timer(0.4).timeout
			board.is_busy = false
		"居合。水":
			# 居合.水魂：消除棋盤上所有水寶石並儲存於 pending，下次水屬性攻擊時併入
			battle_manager.use_active_skill(char_index)
			_update_skill_ui()
			# ── 水元素 VFX：從每顆水寶石飛向技能使用者卡片──
			var water_positions: Array[Vector2] = []
			for x in board.columns:
				for y in board.rows:
					var bb: Block = board.grid[x][y]
					if bb != null and bb.block_type == Block.Type.BLUE and not bb.is_upper_gem():
						water_positions.append(bb.global_position)
			if water_positions.size() > 0:
				var card_center: Vector2 = character_panel.get_card_screen_center(char_index)
				var water_color: Color = Block.COLORS.get(Block.Type.BLUE, Color(0.2, 0.55, 1.0))
				var particle_duration := 0.7
				var n_total: int = mini(water_positions.size(), MAX_VFX_PARTICLES)
				for i in n_total:
					var particle: Node2D = _acquire_particle()
					if particle == null:
						break
					var spread: float = (float(i) / max(n_total - 1, 1)) * 2.0 - 1.0 if n_total > 1 else 0.0
					particle.launch(water_positions[i], card_center, water_color, particle_duration, spread)
			var blasted: int = await board.blast_all_of_type(Block.Type.BLUE)
			if blasted > 0:
				battle_manager.pending_skill_blasts[Block.Type.BLUE] = int(battle_manager.pending_skill_blasts.get(Block.Type.BLUE, 0)) + blasted
				battle_manager.turn_gem_blasts_changed.emit()
			_add_log_entry("%s：%s %d %s" % [Locale.tr_ui("居合。水"), Locale.tr_ui("LOG_STORE"), blasted, _gem_bbcode(Block.Type.BLUE)], Block.Type.BLUE, c)
			await get_tree().create_timer(0.2).timeout
			_update_skill_ui()
		"Dragon Flame Domain":
			# 龍焰領域：先播放動畫前置，再進入火焰範圍選擇模式
			var selection: Dictionary = await _run_board_selection_active_skill(char_index, Block.Type.RED, "fireball")
			if bool(selection.get("cancelled", false)):
				return
			var positions: Array = selection.get("positions", [])
			if positions.is_empty():
				return
			battle_manager.use_active_skill(char_index)
			_update_skill_ui()
			board.is_busy = true
			# 範圍選擇完成後播放動畫前置（隕石/領域動畫）
			await _play_skill_animation_phase(_get_active_skill_anim_params(c))
			# 以範圍中心（positions[0]）作為隕石落下點
			if positions.size() > 0:
				var center_p: Vector2i = positions[0] as Vector2i
				var landing_global: Vector2 = board.to_global(board.grid_to_world(center_p)) + Vector2(board.CELL_SIZE * 0.5, board.CELL_SIZE * 0.5)
				var meteor := MeteorVFX.new()
				fx_layer.add_child(meteor)
				await meteor.play(landing_global)
				# 落地打擊音效
				_play_sfx(load("res://assets/se/skef_atk6.mp3"), 1.2)
			var converted := 0
			var planks_broken := 0
			for pos in positions:
				var p: Vector2i = pos as Vector2i
				var tb: Block = board.grid[p.x][p.y]
				if tb == null:
					continue
				if tb.is_breakable_structure():
					# BREAK 屬性：龍焰領域可連同可破壞障礙一併側除
					if c.has_break_essence and board.silently_destroy_breakable_structure(p):
						planks_broken += 1
					continue
				if tb.is_obstacle():
					continue
				if tb.block_type != Block.Type.RED:
					board._animate_gem_morph(tb, Block.Type.RED)
					converted += 1
			_add_log_entry("%s：%d→%s" % [Locale.tr_ui("Dragon Flame Domain"), converted, _gem_bbcode(Block.Type.RED)], Block.Type.RED, c)
			await get_tree().create_timer(0.4).timeout
			# 若打破了木板，必須讓上方寶石墜落填補空位
			if planks_broken > 0:
				await board._collapse_and_fill()
				board.is_busy = true
			await get_tree().create_timer(0.4).timeout
			board.is_busy = false
		"There shall be light":
			# 光輝降臨：進入選擇模式，懸停預覽十字範圍，點擊確認轉換為光寶石
			var selection: Dictionary = await _run_board_selection_active_skill(char_index, Block.Type.LIGHT)
			if bool(selection.get("cancelled", false)):
				return
			var positions: Array = selection.get("positions", [])
			if positions.is_empty():
				return
			battle_manager.use_active_skill(char_index)
			_update_skill_ui()
			_play_sfx(_se_thor_active)
			# 轉換十字範圍內的寶石
			var converted := 0
			for pos in positions:
				var p: Vector2i = pos as Vector2i
				var tb: Block = board.grid[p.x][p.y]
				if tb == null or tb.is_obstacle():
					continue
				if tb.block_type != Block.Type.LIGHT:
					board._animate_gem_morph(tb, Block.Type.LIGHT)
					converted += 1
			_add_log_entry("%s：%d→%s" % [Locale.tr_ui("There shall be light"), converted, _gem_bbcode(Block.Type.LIGHT)], Block.Type.LIGHT, c)
			await get_tree().create_timer(0.4).timeout
		"希望之光":
			var targets: Array[Vector2i] = _get_random_convertible_cells(Block.Type.LIGHT, 5)
			if targets.is_empty():
				return
			battle_manager.use_active_skill(char_index)
			_update_skill_ui()
			board.is_busy = true
			var light_color: Color = Block.COLORS.get(Block.Type.LIGHT, Color(1.0, 0.92, 0.23))
			var from_pos: Vector2 = character_panel.get_card_screen_center(char_index)
			var converted := 0
			for i in targets.size():
				var target_pos: Vector2i = targets[i]
				var target_block: Block = board.grid[target_pos.x][target_pos.y]
				if target_block == null or target_block.is_obstacle() or target_block.is_upper_gem() or target_block.block_type == Block.Type.LIGHT:
					continue
				var to_pos: Vector2 = target_block.global_position
				var trail := Node2D.new()
				trail.set_script(TrailProjectileScript)
				trail.z_index = 100
				fx_layer.add_child(trail)
				var captured_pos: Vector2i = target_pos
				trail.deduct_hp.connect(func() -> void:
					if board._is_valid(captured_pos):
						var b: Block = board.grid[captured_pos.x][captured_pos.y]
						if b != null and not b.is_obstacle() and not b.is_upper_gem() and b.block_type != Block.Type.LIGHT:
							board._animate_gem_morph(b, Block.Type.LIGHT)
					_play_sfx(_se_impact, 0.7)
				, CONNECT_ONE_SHOT)
				var spread: float = (float(i) / maxf(float(targets.size() - 1), 1.0)) * 1.4 - 0.7 if targets.size() > 1 else 0.0
				trail.launch(from_pos, to_pos, light_color, 0.5, spread)
				converted += 1
				if i < targets.size() - 1:
					await get_tree().create_timer(0.06).timeout
			await get_tree().create_timer(0.5 / TrailProjectileScript.speed_divisor + 0.18).timeout
			board.resync_logic_from_visual()
			board.is_busy = false
			_add_log_entry("%s：%d→%s" % [Locale.tr_ui("希望之光"), converted, _gem_bbcode(Block.Type.LIGHT)], Block.Type.LIGHT, c)
		"Leaf Spear Call":
			var selection_count: int = 1 + SkillUpgradeUtils.leaf_spear_extra_cells(c)
			var selection: Dictionary = await _run_board_selection_active_skill(char_index, Block.Type.GREEN, "single_top_bottom", selection_count)
			if bool(selection.get("cancelled", false)):
				return
			var sel_positions: Array = selection.get("positions", [])
			if sel_positions.is_empty():
				return
			var spear_targets: Array[Dictionary] = []
			var last_spear_type: Block.UpperType = Block.UpperType.WOOD_SPEAR_DOWN
			for pos in sel_positions:
				var spear_pos: Vector2i = pos as Vector2i
				var spear_block: Block = board.grid[spear_pos.x][spear_pos.y]
				if spear_block != null and spear_block.is_obstacle():
					continue
				if spear_block != null and spear_block.is_upper_gem():
					continue
				var spear_type: Block.UpperType = Block.UpperType.WOOD_SPEAR_DOWN
				if spear_pos.y == board.rows - 1:
					spear_type = Block.UpperType.WOOD_SPEAR_UP
				spear_targets.append({"pos": spear_pos, "ut": spear_type})
				last_spear_type = spear_type
			if spear_targets.is_empty():
				return
			battle_manager.use_active_skill(char_index)
			_update_skill_ui()
			board.is_busy = true
			var leaf_spiral_color: Color = Block.COLORS.get(Block.Type.GREEN, Color(0.3, 0.85, 0.35))
			var spear_positions: Array[Vector2i] = []
			for entry: Dictionary in spear_targets:
				spear_positions.append(entry["pos"] as Vector2i)
			await _play_transmute_spiral_vfx_for_cells(spear_positions, leaf_spiral_color)
			var placed_count := 0
			for entry: Dictionary in spear_targets:
				var spear_pos: Vector2i = entry["pos"] as Vector2i
				var spear_type: Block.UpperType = entry["ut"] as Block.UpperType
				if board.place_upper_gem(spear_pos, spear_type, Block.Type.GREEN):
					var placed_spear: Block = board.grid[spear_pos.x][spear_pos.y]
					if placed_spear != null:
						var spear_skill_index: int = SkillUpgradeUtils.find_responding_upper_type_index(c, Block.UpperType.WOOD_SPEAR_UP)
						placed_spear.wood_spear_pierce_breakable = SkillUpgradeUtils.wood_spear_pierces_breakable(c, spear_skill_index)
					placed_count += 1
					last_spear_type = spear_type
			if placed_count <= 0:
				board.is_busy = false
				return
			board.resync_logic_from_visual()
			_play_sfx(_se_freeze)
			_add_log_entry("%s：%s ×%d" % [Locale.tr_ui("Leaf Spear Call"), _upper_gem_bbcode(last_spear_type), placed_count], Block.Type.GREEN, c)
			await get_tree().create_timer(0.25).timeout
			board.is_busy = false
		"咒術印記: 陽光射線":
			var targets: Array[Vector2i] = []
			var seen: Dictionary = {}
			var areas: Array[Dictionary] = [
				{"x": 0, "y": 0},
				{"x": maxi(0, board.columns - 2), "y": maxi(0, board.rows - 3)},
			]
			for area in areas:
				var start_x: int = int(area.get("x", 0))
				var start_y: int = int(area.get("y", 0))
				for y in range(start_y, mini(start_y + 3, board.rows)):
					for x in range(start_x, mini(start_x + 2, board.columns)):
						var p := Vector2i(x, y)
						if seen.has(p):
							continue
						seen[p] = true
						if not board._is_valid(p):
							continue
						var tb: Block = board.grid[p.x][p.y]
						if tb == null or tb.is_obstacle() or tb.is_upper_gem():
							continue
						targets.append(p)
			if targets.is_empty():
				return
			battle_manager.use_active_skill(char_index)
			_update_skill_ui()
			board.is_busy = true
			var converted := 0
			for p: Vector2i in targets:
				var tb: Block = board.grid[p.x][p.y]
				if tb == null or tb.is_obstacle() or tb.is_upper_gem():
					continue
				if tb.block_type != Block.Type.GREEN:
					board._animate_gem_morph(tb, Block.Type.GREEN)
					converted += 1
			_add_log_entry("%s：%d/%d→%s" % [Locale.tr_ui("咒術印記: 陽光射線"), converted, targets.size(), _gem_bbcode(Block.Type.GREEN)], Block.Type.GREEN, c)
			await get_tree().create_timer(0.4).timeout
			board.resync_logic_from_visual()
			board.is_busy = false
		"Resurgence", "Resurgence+":
			# 生息：選一顆寶石，將其上下左右四鄰轉換為相同元素
			# 生息.強：再額外將被點擊的寶石加上 X5 額外效果
			var selection: Dictionary = await _run_board_selection_active_skill(char_index, Block.Type.RED, "single")  # convert_type 在 single 模式下未使用
			if bool(selection.get("cancelled", false)):
				return
			var sel_positions: Array = selection.get("positions", [])
			if sel_positions.is_empty():
				return
			var center_p: Vector2i = sel_positions[0] as Vector2i
			var center_block: Block = board.grid[center_p.x][center_p.y]
			if center_block == null:
				return
			battle_manager.use_active_skill(char_index)
			_update_skill_ui()

			# ── 狸貓手掌點擊動畫 ────────────────────────────────
			# 取得元素顏色（波紋用）
			var elem_color: Color = Block.COLORS.get(center_block.block_type, Color.WHITE)

			# 1) 直接顯示手掌圖示（Sprite2D 加到 fx_layer）
			var paw_tex: Texture2D = load("res://assets/panda_paw_2.png")
			var paw := Sprite2D.new()
			paw.texture = paw_tex
			paw.centered = true           # 以紋理中心為旋轉錨點
			paw.scale = Vector2(0.1, 0.1) # 縮小 10 倍
			paw.z_index = 30
			var gem_global: Vector2 = center_block.global_position
			# 中心點對應原先左上角錨點的等效位置（偏移加上半張圖尺寸）
			var paw_half: Vector2 = Vector2(paw_tex.get_width(), paw_tex.get_height()) * 0.5 * paw.scale
			paw.position = gem_global + Vector2(-80, -30) + paw_half
			fx_layer.add_child(paw)

			# 2) 按壓：縮小 + 順時針旋轉 約 25°；同步寶石縮小
			var tap_tw := create_tween().set_parallel(true)
			tap_tw.tween_property(paw, "scale", Vector2(0.07, 0.07), 0.2) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tap_tw.tween_property(paw, "rotation", deg_to_rad(25.0), 0.2) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			tap_tw.tween_property(center_block, "scale", Vector2(0.7, 0.7), 0.2) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			await tap_tw.finished

			# ── 波紋（甜甜圈）特效 — 在按壓最深時從寶石中心向外擴散 ──
			var ring_script := GDScript.new()
			ring_script.source_code = (
				"extends Node2D\n"
				+ "var radius: float = 0.0\n"
				+ "var ring_alpha: float = 1.0\n"
				+ "var ring_color: Color = Color.WHITE\n"
				+ "func _draw() -> void:\n"
				+ "\tdraw_arc(Vector2.ZERO, radius, 0.0, TAU, 64,"
				+ " Color(ring_color.r, ring_color.g, ring_color.b, ring_alpha), 8.0, true)\n"
				+ "func _process(_dt: float) -> void:\n"
				+ "\tqueue_redraw()\n"
			)
			ring_script.reload()
			var ring := Node2D.new()
			ring.set_script(ring_script)
			ring.set("ring_color", elem_color)
			ring.position = gem_global
			ring.z_index = 25
			fx_layer.add_child(ring)
			var ring_tw := create_tween().set_parallel(true)
			ring_tw.tween_property(ring, "radius", 60.0, 0.9) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			ring_tw.tween_property(ring, "ring_alpha", 0.0, 0.9) \
				.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			ring_tw.finished.connect(ring.queue_free)

			# 彈回：scale、rotation 復原；寶石也彈回
			var revert_tw := create_tween().set_parallel(true)
			revert_tw.tween_property(paw, "scale", Vector2(0.1, 0.1), 0.28) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			revert_tw.tween_property(paw, "rotation", 0.0, 0.28) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			revert_tw.tween_property(center_block, "scale", Vector2(1.0, 1.0), 0.28) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			await revert_tw.finished

			# 3) 手掌淡出（非阻塞）
			var paw_out := create_tween()
			paw_out.tween_property(paw, "modulate:a", 0.0, 0.3)
			paw_out.tween_callback(paw.queue_free)

			# ── 技能效果 ────────────────────────────────────────
			var target_element: Block.Type = center_block.block_type as Block.Type
			var converted := 0
			for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var np: Vector2i = center_p + dir
				if not board._is_valid(np):
					continue
				var nb: Block = board.grid[np.x][np.y]
				if nb == null or nb.is_upper_gem() or nb.is_obstacle():
					continue
				if nb.block_type == target_element:
					continue
				board._animate_gem_morph(nb, target_element)
				converted += 1
			# 生息.強 加 X3 標記到中心寶石（高階寶石跳過）
			if c.active_skill_name == "Resurgence+" and not center_block.is_upper_gem():
				center_block.add_extra(Block.ExtraEffect.X3)
			var skill_label: String = Locale.tr_ui(c.active_skill_name)
			_add_log_entry("%s：%d→%s" % [skill_label, converted, _gem_bbcode(target_element)], target_element, c)
			await get_tree().create_timer(0.4).timeout
		"Blast":
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
			_add_log_entry("%s：%s 消除 %d 顆寶石" % [Locale.tr_ui("Blast"), _gem_bbcode(Block.Type.RED), total_gems], Block.Type.RED, c)
			# 透過通用管線播放 VFX → 攻擊
			await _process_blast_results(blasted, _upper_blast_positions)
			await _end_player_turn()
		"Snowball Fight":
			# 打雪仗：動員棋盤上所有雪球飛向目標敵人，每顆造成 ATK×10 傷害
			var snowballs: Array[Vector2i] = board.find_upper_gems(Block.UpperType.SNOWBALL)
			if snowballs.is_empty():
				return
			battle_manager.use_active_skill(char_index)
			board.is_busy = true
			var polar_atk := c.get_atk()
			var snowball_dmg := polar_atk * 10
			var snowball_count := snowballs.size()
			var target: Enemy = battle_manager.targeted_enemy
			if target == null or not is_instance_valid(target) or target.current_hp <= 0:
				target = _get_best_target_for_damage(c.gem_type, snowball_dmg, 1.0, _get_current_enemy_hp_sim())
			if target == null:
				board.is_busy = false
				_update_skill_ui()
				return

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
				if not is_instance_valid(target) or int(sim_hp.get(target, 0)) <= 0:
					var new_target: Enemy = _get_best_target_for_damage(c.gem_type, snowball_dmg, 1.0, sim_hp)
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
				var target_pos: Vector2 = _get_enemy_image_center(hit_target) if is_instance_valid(hit_target) else board.global_position
				# 飛行動畫（fire-and-forget）
				var fly_tw := create_tween()
				fly_tw.set_parallel(true)
				fly_tw.tween_property(block, "global_position", target_pos, fly_duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
				fly_tw.tween_property(block, "scale", Vector2(0.6, 0.6), fly_duration)
				fly_tw.tween_property(block, "modulate:a", 0.5, fly_duration * 0.8).set_delay(fly_duration * 0.2)
				# 抵達時造成傷害並銷毀
				fly_tw.finished.connect(func() -> void:
					if is_instance_valid(hit_target) and (hit_target.current_hp > 0 or hit_target.defer_death):
						var applied_dmg: int = hit_target.take_damage(hit_dmg)
						_spawn_damage_number(_get_enemy_image_center(hit_target), applied_dmg, Block.COLORS[Block.Type.BLUE], true, hit_super)
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
		if not _is_active_unlocked_for_battle(i):
			character_panel.update_cooldown(i, -2)
			continue
		character_panel.update_cooldown(i, cd)
		if cd <= 0:
			character_panel.start_glow(i)


func _is_active_unlocked_for_battle(char_index: int) -> bool:
	if char_index < 0 or char_index >= party.size():
		return false
	var c: CharacterData = party[char_index]
	if c == null:
		return false
	if _temporary_active_unlocks.has(c):
		return true
	if _is_stage13_story_battle() and _is_thor_character(c):
		return false
	return SkillUpgradeUtils.is_active_stage_unlocked(c)


func _handle_auto_enemy_action(enemy: Enemy) -> void:
	if not _auto_enemy_can_continue(enemy):
		return
	var data: EnemyData = enemy.data
	var auto_character: CharacterData = data.auto_character
	if auto_character == null:
		return
	var enemy_name: String = data.get_display_name()
	var owner_id: int = enemy.get_instance_id()
	board.clear_deferred_clicks()
	board.is_busy = true

	if _auto_enemy_can_use_active(enemy, auto_character):
		var used_active: bool = await _run_auto_enemy_active_skill(enemy, auto_character)
		if not _auto_enemy_can_continue(enemy):
			board.is_busy = false
			return
		if used_active:
			_auto_enemy_active_cds[owner_id] = _auto_effective_active_cd(data, auto_character)
			_add_log_entry("[b]%s[/b] AUTO：%s" % [enemy_name, Locale.tr_ui(auto_character.active_skill_name)], auto_character.gem_type)
			await get_tree().create_timer(0.15).timeout
			if not _auto_enemy_can_continue(enemy):
				board.is_busy = false
				return

	if not _auto_enemy_can_continue(enemy):
		board.is_busy = false
		return

	await _try_auto_enemy_fuse(enemy, auto_character)
	if not _auto_enemy_can_continue(enemy):
		board.is_busy = false
		return

	var upper_result: Dictionary = await _try_auto_enemy_upper(enemy, auto_character)
	if not _auto_enemy_can_continue(enemy):
		board.is_busy = false
		return
	if int(upper_result.get("count", 0)) > 0:
		board.is_busy = false
		var upper_damage_count: int = _auto_enemy_damage_count_for_type(upper_result, auto_character.gem_type)
		var upper_damage_positions: Array = _auto_enemy_damage_positions_for_type(upper_result, auto_character.gem_type)
		if upper_damage_count > 0:
			await _apply_auto_enemy_gem_damage(enemy, upper_damage_count, auto_character.gem_type, "Upper", upper_damage_positions)
		return
	elif bool(upper_result.get("acted", false)):
		board.is_busy = false
		return

	var group: Array[Vector2i] = _choose_auto_enemy_blast_group(auto_character)
	if group.is_empty():
		board.is_busy = false
		return
	await _play_auto_enemy_cursor_tap(group[0], auto_character.gem_type)
	if not _auto_enemy_can_continue(enemy):
		board.is_busy = false
		return
	var pre_damage_count: int = _auto_enemy_group_count_for_type(group, auto_character.gem_type)
	var pre_damage_positions: Array = _auto_enemy_group_positions_for_type(group, auto_character.gem_type)
	var vfx_wait: float = 0.0
	var vfx_start_msec: int = 0
	if pre_damage_count > 0:
		vfx_start_msec = Time.get_ticks_msec()
		vfx_wait = _launch_auto_enemy_element_vfx_to_enemy(enemy, pre_damage_positions, auto_character.gem_type, pre_damage_count)
	var blast_result: Dictionary = await board.enemy_blast_group(group)
	if not _auto_enemy_can_continue(enemy):
		board.is_busy = false
		return
	board.is_busy = false
	var destroyed_count: int = int(blast_result.get("count", 0))
	if destroyed_count > 0:
		var damage_count: int = _auto_enemy_damage_count_for_type(blast_result, auto_character.gem_type)
		var damage_positions: Array = _auto_enemy_damage_positions_for_type(blast_result, auto_character.gem_type)
		if damage_count > 0:
			if vfx_wait > 0.0:
				var elapsed: float = float(Time.get_ticks_msec() - vfx_start_msec) / 1000.0
				var remaining: float = vfx_wait - elapsed
				if remaining > 0.0:
					await get_tree().create_timer(remaining).timeout
					if not _auto_enemy_can_continue(enemy):
						return
			await _apply_auto_enemy_gem_damage(enemy, damage_count, auto_character.gem_type, "Blast", damage_positions, pre_damage_count > 0)


func _auto_enemy_can_continue(enemy: Enemy) -> bool:
	return is_instance_valid(enemy) \
			and enemy.data != null \
			and enemy.current_hp > 0 \
			and battle_manager != null \
			and battle_manager.player_current_hp > 0 \
			and battle_manager.active_enemies.has(enemy) \
			and not battle_manager.is_round_transitioning


func _auto_enemy_can_use_active(enemy: Enemy, auto_character: CharacterData) -> bool:
	var owner_id: int = enemy.get_instance_id()
	var remaining: int = int(_auto_enemy_active_cds.get(owner_id, 0))
	if remaining > 0:
		remaining -= 1
		_auto_enemy_active_cds[owner_id] = remaining
	return remaining <= 0 and auto_character.active_skill_name.strip_edges() != ""


func _run_auto_enemy_active_skill(enemy: Enemy, auto_character: CharacterData) -> bool:
	if not _auto_enemy_can_continue(enemy):
		return false
	if auto_character.active_skill_name == "Leaf Spear Call":
		return await _run_auto_gory_leaf_spear_call(enemy, auto_character)
	return false


func _run_auto_gory_leaf_spear_call(enemy: Enemy, auto_character: CharacterData) -> bool:
	if not _auto_enemy_can_continue(enemy):
		return false
	var owner_id: int = enemy.get_instance_id()
	var place_count: int = 1 + _auto_effect_max(enemy.data, auto_character, SkillUpgradeUtils.KIND_ACTIVE, 0, "leaf_spear_extra_cells")
	var candidates: Array[Dictionary] = []
	for x in board.columns:
		var edge_options: Array[Dictionary] = [
			{"pos": Vector2i(x, 0), "ut": Block.UpperType.WOOD_SPEAR_DOWN},
			{"pos": Vector2i(x, board.rows - 1), "ut": Block.UpperType.WOOD_SPEAR_UP},
		]
		for option in edge_options:
			var pos: Vector2i = option["pos"] as Vector2i
			if not _auto_enemy_can_place_spear_at(pos):
				continue
			var ut: Block.UpperType = option["ut"] as Block.UpperType
			var score: Dictionary = _auto_score_wood_spear_cell(pos, ut)
			score["pos"] = pos
			score["ut"] = ut
			score["tie"] = randf()
			candidates.append(score)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var upper_a: int = int(a.get("player_upper_hits", 0))
		var upper_b: int = int(b.get("player_upper_hits", 0))
		if upper_a != upper_b:
			return upper_a > upper_b
		var leaf_a: int = int(a.get("leaf_hits", 0))
		var leaf_b: int = int(b.get("leaf_hits", 0))
		if leaf_a != leaf_b:
			return leaf_a > leaf_b
		return float(a.get("tie", 0.0)) > float(b.get("tie", 0.0))
	)
	var selected_entries: Array[Dictionary] = []
	var used_columns: Dictionary = {}
	var responding_index: int = SkillUpgradeUtils.find_responding_upper_type_index(auto_character, Block.UpperType.WOOD_SPEAR_UP)
	var pierces_breakable: bool = _auto_effect_max(enemy.data, auto_character, SkillUpgradeUtils.KIND_RESPONDING, responding_index, "wood_spear_pierce_breakable") > 0
	for entry in candidates:
		if selected_entries.size() >= place_count:
			break
		var pos: Vector2i = entry["pos"] as Vector2i
		if used_columns.has(pos.x):
			continue
		selected_entries.append(entry)
		used_columns[pos.x] = true
	var placed_count: int = 0
	for entry_index in selected_entries.size():
		if not _auto_enemy_can_continue(enemy):
			break
		var entry: Dictionary = selected_entries[entry_index]
		var pos: Vector2i = entry["pos"] as Vector2i
		var ut: Block.UpperType = entry["ut"] as Block.UpperType
		var spiral_color: Color = Block.COLORS.get(auto_character.gem_type, Block.COLORS.get(Block.Type.GREEN, Color(0.3, 0.85, 0.35)))
		await _play_transmute_spiral_vfx_for_cells([pos], spiral_color)
		if not _auto_enemy_can_continue(enemy):
			break
		if board.place_upper_gem(pos, ut, auto_character.gem_type, Block.UpperOwnerTeam.ENEMY, owner_id):
			var placed_block: Block = board.grid[pos.x][pos.y]
			if placed_block != null:
				placed_block.wood_spear_pierce_breakable = pierces_breakable
			placed_count += 1
			_play_sfx(_se_freeze)
			if entry_index < selected_entries.size() - 1:
				await get_tree().create_timer(0.5).timeout
				if not _auto_enemy_can_continue(enemy):
					break
	if placed_count > 0:
		board.resync_logic_from_visual()
	return placed_count > 0


func _auto_enemy_can_place_spear_at(pos: Vector2i) -> bool:
	if not board._cell_accepts_block(pos) or board.is_escape_marker_pos(pos):
		return false
	var block: Block = board.grid[pos.x][pos.y]
	if block == null:
		return true
	return not block.is_obstacle() and not block.is_upper_gem()


func _auto_score_wood_spear_cell(pos: Vector2i, ut: Block.UpperType) -> Dictionary:
	var direction_y: int = -1 if ut == Block.UpperType.WOOD_SPEAR_UP else 1
	var player_upper_hits: int = 0
	var leaf_hits: int = 0
	var current: Vector2i = pos + Vector2i(0, direction_y)
	while board._is_valid(current):
		if board.is_escape_marker_pos(current):
			current += Vector2i(0, direction_y)
			continue
		var block: Block = board.grid[current.x][current.y]
		if block == null:
			current += Vector2i(0, direction_y)
			continue
		if block.is_rock():
			break
		if block.is_upper_gem():
			if block.upper_owner_team == Block.UpperOwnerTeam.PLAYER:
				player_upper_hits += 1
		elif block.block_type == Block.Type.GREEN and not block.is_obstacle():
			leaf_hits += 1
		if block.is_obstacle() and not block.is_breakable_structure():
			break
		current += Vector2i(0, direction_y)
	return {
		"player_upper_hits": player_upper_hits,
		"leaf_hits": leaf_hits,
	}


func _try_auto_enemy_fuse(enemy: Enemy, auto_character: CharacterData) -> bool:
	if not _auto_enemy_can_continue(enemy):
		return false
	var responding_index: int = SkillUpgradeUtils.find_responding_upper_type_index(auto_character, Block.UpperType.WOOD_SPEAR_UP)
	var upper_type: Block.UpperType = Block.UpperType.WOOD_SPEAR_UP if responding_index >= 0 else Block.UpperType.NONE
	if responding_index < 0:
		for i in auto_character.responding_skills.size():
			var candidate: Dictionary = auto_character.responding_skills[i] as Dictionary
			var candidate_upper: Block.UpperType = SkillUpgradeUtils.responding_upper_type(candidate)
			if candidate_upper == Block.UpperType.NONE or Block.upper_type_has_instant(candidate_upper):
				continue
			responding_index = i
			upper_type = candidate_upper
			break
	if responding_index < 0:
		return false
	var skill: Dictionary = auto_character.responding_skills[responding_index] as Dictionary
	var fuse_gem_type: Block.Type = SkillUpgradeUtils.responding_gem_type(auto_character, skill)
	var threshold: int = maxi(1, int(skill.get("threshold", 1)) + _auto_effect_sum(enemy.data, auto_character, SkillUpgradeUtils.KIND_RESPONDING, responding_index, "threshold_delta"))
	var group: Array[Vector2i] = board.find_auto_fuse_group(fuse_gem_type, threshold)
	if group.is_empty():
		return false
	if upper_type != Block.UpperType.WOOD_SPEAR_UP and upper_type != Block.UpperType.WOOD_SPEAR_DOWN:
		var target_pos: Vector2i = group[0]
		var target_score: int = -1
		for p in group:
			var score: int = _auto_score_upper_fuse_cell(p, upper_type, fuse_gem_type)
			if score > target_score:
				target_score = score
				target_pos = p
		await _play_auto_enemy_cursor_tap(target_pos, fuse_gem_type)
		if not _auto_enemy_can_continue(enemy):
			return false
		_play_sfx(_se_freeze)
		await _play_auto_enemy_fuse_projectiles(group, target_pos, fuse_gem_type)
		if not _auto_enemy_can_continue(enemy):
			return false
		var generic_ok: bool = await board.enemy_fuse_upper_from_group(group, target_pos, upper_type, fuse_gem_type, enemy.get_instance_id())
		if not _auto_enemy_can_continue(enemy):
			return false
		if generic_ok:
			_add_log_entry("[b]%s[/b] AUTO：%s%d → %s" % [
				enemy.data.get_display_name(),
				_gem_bbcode(fuse_gem_type),
				group.size(),
				_upper_gem_bbcode(upper_type)
			], fuse_gem_type)
		return generic_ok
	var best_pos: Vector2i = group[0]
	var best_score: int = -1
	var best_ut: Block.UpperType = Block.UpperType.WOOD_SPEAR_DOWN
	var pierces_breakable: bool = _auto_effect_max(enemy.data, auto_character, SkillUpgradeUtils.KIND_RESPONDING, responding_index, "wood_spear_pierce_breakable") > 0
	for p in group:
		var ut: Block.UpperType = board.get_best_wood_spear_type_for_pos(p)
		var score_data: Dictionary = _auto_score_wood_spear_cell(p, ut)
		var score: int = int(score_data.get("player_upper_hits", 0)) * 1000 + int(score_data.get("leaf_hits", 0))
		if score > best_score:
			best_score = score
			best_pos = p
			best_ut = ut
	await _play_auto_enemy_cursor_tap(best_pos, fuse_gem_type)
	if not _auto_enemy_can_continue(enemy):
		return false
	_play_sfx(_se_freeze)
	await _play_auto_enemy_fuse_projectiles(group, best_pos, fuse_gem_type)
	if not _auto_enemy_can_continue(enemy):
		return false
	var ok: bool = await board.enemy_fuse_upper_from_group(group, best_pos, best_ut, fuse_gem_type, enemy.get_instance_id(), pierces_breakable)
	if not _auto_enemy_can_continue(enemy):
		return false
	if ok:
		_add_log_entry("[b]%s[/b] AUTO：%s%d → %s" % [
			enemy.data.get_display_name(),
			_gem_bbcode(fuse_gem_type),
			group.size(),
			_upper_gem_bbcode(best_ut)
		], fuse_gem_type)
	return ok


func _auto_score_upper_fuse_cell(pos: Vector2i, upper_type: Block.UpperType, gem_type: Block.Type) -> int:
	var score: int = 0
	for target_pos in board._get_blast_positions_for_upper(pos, upper_type):
		if not board._cell_accepts_block(target_pos) or board.is_escape_marker_pos(target_pos):
			continue
		var block: Block = board.grid[target_pos.x][target_pos.y]
		if block == null or block.is_rock():
			continue
		if block.is_upper_gem():
			score += 6 if block.upper_owner_team == Block.UpperOwnerTeam.PLAYER else 2
		elif not block.is_obstacle():
			score += 3 if block.block_type == gem_type else 1
		elif block.is_breakable_structure():
			score += 1
	return score


func _try_auto_enemy_upper(enemy: Enemy, auto_character: CharacterData) -> Dictionary:
	if not _auto_enemy_can_continue(enemy):
		return {"acted": false, "count": 0}
	var owner_id: int = enemy.get_instance_id()
	var uppers: Array[Vector2i] = board.find_owned_upper_gems(owner_id)
	if uppers.is_empty():
		return {"acted": false, "count": 0}
	var best_pos: Vector2i = uppers[0]
	var best_score: int = -1
	for pos in uppers:
		var score: int = board.get_enemy_upper_preview_count(pos, owner_id)
		if score > best_score:
			best_score = score
			best_pos = pos
	var best_upper_type: Block.UpperType = Block.UpperType.NONE
	if board._is_valid(best_pos):
		var best_block: Block = board.grid[best_pos.x][best_pos.y]
		if best_block != null:
			best_upper_type = best_block.upper_type
	await _play_auto_enemy_cursor_tap(best_pos, auto_character.gem_type)
	if not _auto_enemy_can_continue(enemy):
		return {"acted": false, "count": 0}
	var result: Dictionary = await board.enemy_trigger_owned_upper(best_pos, owner_id)
	if not _auto_enemy_can_continue(enemy):
		return {"acted": false, "count": 0}
	result["acted"] = true
	if int(result.get("count", 0)) > 0:
		_add_log_entry("[b]%s[/b] AUTO：%s ×%d" % [
			enemy.data.get_display_name(),
			_upper_gem_bbcode(best_upper_type) if best_upper_type != Block.UpperType.NONE else "Upper",
			int(result.get("count", 0))
		], auto_character.gem_type)
	return result


func _choose_auto_enemy_blast_group(auto_character: CharacterData) -> Array[Vector2i]:
	var own_group: Array[Vector2i] = board.find_best_auto_group(int(auto_character.gem_type))
	var any_group: Array[Vector2i] = board.find_best_auto_group(-1)
	if own_group.is_empty():
		return any_group
	if any_group.is_empty():
		return own_group
	if randf() < 0.5:
		return own_group
	return any_group


func _auto_enemy_damage_count_for_type(result: Dictionary, gem_type: Block.Type) -> int:
	var counts_by_type: Dictionary = result.get("counts_by_type", {})
	return int(counts_by_type.get(gem_type, 0))


func _auto_enemy_damage_positions_for_type(result: Dictionary, gem_type: Block.Type) -> Array:
	var positions_by_type: Dictionary = result.get("positions_by_type", {})
	var positions: Array = positions_by_type.get(gem_type, [])
	return positions


func _auto_enemy_group_count_for_type(group: Array[Vector2i], gem_type: Block.Type) -> int:
	var count: int = 0
	for pos in group:
		if not board._cell_accepts_block(pos):
			continue
		var block: Block = board.grid[pos.x][pos.y]
		if block != null and not block.is_obstacle() and not block.is_upper_gem() and block.block_type == gem_type:
			count += 1
	return count


func _auto_enemy_group_positions_for_type(group: Array[Vector2i], gem_type: Block.Type) -> Array:
	var positions: Array = []
	for pos in group:
		if not board._cell_accepts_block(pos):
			continue
		var block: Block = board.grid[pos.x][pos.y]
		if block != null and not block.is_obstacle() and not block.is_upper_gem() and block.block_type == gem_type:
			positions.append(block.global_position)
	return positions


func _play_auto_enemy_cursor_tap(target_pos: Vector2i, gem_type: Block.Type) -> void:
	if not board._cell_accepts_block(target_pos):
		return
	var target_global: Vector2 = board.to_global(board.grid_to_world(target_pos))
	target_global += Vector2(15.0, 15.0)
	var cursor_texture: Texture2D = load("res://assets/Hand3.png")
	if cursor_texture == null:
		return

	var cursor := Sprite2D.new()
	cursor.texture = cursor_texture
	cursor.centered = true
	cursor.z_index = 220
	var max_side: float = maxf(float(cursor_texture.get_width()), float(cursor_texture.get_height()))
	var base_scale: float = 54.0 / maxf(max_side, 1.0)
	cursor.scale = Vector2(base_scale, base_scale)
	cursor.modulate = Color(1.0, 1.0, 1.0, 0.0)
	var cursor_cell_top_center_offset := Vector2(32.0, 0.0)
	var hover_pos: Vector2 = target_global + Vector2(-74.0, -56.0) + cursor_cell_top_center_offset
	var board_center_global: Vector2 = board.to_global(Vector2(
		float(board.columns) * float(board.CELL_SIZE) * 0.5,
		float(board.rows) * float(board.CELL_SIZE) * 0.5
	))
	cursor.position = board_center_global + Vector2(-20.0, -18.0)
	fx_layer.add_child(cursor)

	var intro_tw := create_tween()
	intro_tw.set_parallel(true)
	intro_tw.tween_property(cursor, "modulate:a", 1.0, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	intro_tw.tween_property(cursor, "position", hover_pos, 0.42).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
	await intro_tw.finished

	var press_pos: Vector2 = target_global + Vector2(-20.0, -18.0) + cursor_cell_top_center_offset
	var color: Color = Block.COLORS.get(gem_type, Color.WHITE)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(cursor, "modulate:a", 1.0, 0.16)
	tw.tween_property(cursor, "position", press_pos, 0.36).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(cursor, "scale", Vector2(base_scale * 0.86, base_scale * 0.86), 0.36).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await tw.finished

	_spawn_auto_enemy_tap_ring(target_global, color)
	var release_tw := create_tween()
	release_tw.set_parallel(true)
	release_tw.tween_property(cursor, "position", press_pos + Vector2(8.0, -10.0), 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	release_tw.tween_property(cursor, "scale", Vector2(base_scale, base_scale), 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	release_tw.tween_property(cursor, "modulate:a", 0.0, 0.32).set_delay(0.12)
	await release_tw.finished
	if is_instance_valid(cursor):
		cursor.queue_free()


func _spawn_auto_enemy_tap_ring(center_global: Vector2, color: Color) -> void:
	var ring_script := GDScript.new()
	ring_script.source_code = (
		"extends Node2D\n"
		+ "var radius: float = 8.0\n"
		+ "var ring_alpha: float = 0.9\n"
		+ "var ring_color: Color = Color.WHITE\n"
		+ "func _draw() -> void:\n"
		+ "\tdraw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, Color(ring_color.r, ring_color.g, ring_color.b, ring_alpha), 5.0, true)\n"
		+ "func _process(_dt: float) -> void:\n"
		+ "\tqueue_redraw()\n"
	)
	ring_script.reload()
	var ring := Node2D.new()
	ring.set_script(ring_script)
	ring.set("ring_color", color)
	ring.position = center_global
	ring.z_index = 210
	fx_layer.add_child(ring)
	var ring_tw := create_tween().set_parallel(true)
	ring_tw.tween_property(ring, "radius", 42.0, 0.34).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	ring_tw.tween_property(ring, "ring_alpha", 0.0, 0.34).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	ring_tw.finished.connect(ring.queue_free, CONNECT_ONE_SHOT)


func _play_auto_enemy_fuse_projectiles(group: Array[Vector2i], target_pos: Vector2i, gem_type: Block.Type) -> void:
	if group.is_empty() or not board._cell_accepts_block(target_pos):
		return
	var target_global: Vector2 = board.to_global(board.grid_to_world(target_pos))
	var color: Color = Block.COLORS.get(gem_type, Color.WHITE)
	var starts: Array[Vector2] = []
	for p in group:
		if not board._cell_accepts_block(p):
			continue
		var block: Block = board.grid[p.x][p.y]
		if block == null or block.is_obstacle() or block.is_upper_gem():
			continue
		starts.append(block.global_position)
	if starts.is_empty():
		return

	var particle_duration: float = 1.05
	var fuse_total: int = mini(starts.size(), MAX_VFX_PARTICLES)
	for idx in fuse_total:
		var particle: Node2D = _acquire_particle()
		if particle == null:
			break
		var spread: float = (float(idx) / max(fuse_total - 1, 1)) * 2.0 - 1.0 if fuse_total > 1 else 0.0
		particle.launch(starts[idx], target_global, color, particle_duration, spread)
	await get_tree().create_timer(particle_duration / TrailProjectileScript.speed_divisor + 0.05).timeout


func _play_auto_enemy_element_vfx_to_enemy(enemy: Enemy, source_positions: Array, gem_type: Block.Type, destroyed_count: int) -> void:
	var wait_time: float = _launch_auto_enemy_element_vfx_to_enemy(enemy, source_positions, gem_type, destroyed_count)
	if wait_time > 0.0:
		await get_tree().create_timer(wait_time).timeout


func _launch_auto_enemy_element_vfx_to_enemy(enemy: Enemy, source_positions: Array, gem_type: Block.Type, destroyed_count: int) -> float:
	if not is_instance_valid(enemy):
		return 0.0
	var target_pos: Vector2 = _get_enemy_image_center(enemy)
	var color: Color = Block.COLORS.get(gem_type, Color.WHITE)
	var starts: Array[Vector2] = []
	for value in source_positions:
		if value is Vector2:
			starts.append(value as Vector2)
	if starts.is_empty():
		starts.append(board.to_global(Vector2(board.columns * 32.0, board.rows * 32.0)))

	var particle_duration: float = 1.05
	var raw: int = mini(maxi(destroyed_count, starts.size()), 8)
	var total: int = mini(raw, MAX_VFX_PARTICLES)
	for idx in total:
		var particle: Node2D = _acquire_particle()
		if particle == null:
			break
		var from_pos: Vector2 = starts[idx % starts.size()]
		var spread: float = (float(idx) / max(total - 1, 1)) * 2.0 - 1.0 if total > 1 else 0.0
		particle.launch(from_pos, target_pos, color, particle_duration, spread)
	if total > 0:
		return particle_duration / TrailProjectileScript.speed_divisor + 0.05
	return 0.0


func _apply_auto_enemy_gem_damage(enemy: Enemy, destroyed_count: int, gem_type: Block.Type, source_label: String, source_positions: Array = [], element_vfx_already_played: bool = false) -> void:
	if not _auto_enemy_can_continue(enemy) or destroyed_count <= 0:
		return
	var percent: float = float(destroyed_count) * maxf(enemy.data.auto_gem_atk_power, 0.0)
	if percent <= 0.0:
		return
	var estimated_hp: int = battle_manager.estimate_team_max_hp_for_level(enemy.spawn_level)
	var damage: int = maxi(1, int(round(float(estimated_hp) * percent / 100.0)))
	_add_log_entry("[b]%s[/b] AUTO %s：%s ×%d = %.1f%% / %d" % [
		enemy.data.get_display_name(),
		source_label,
		_gem_bbcode(gem_type),
		destroyed_count,
		percent,
		damage
	], gem_type)
	if not element_vfx_already_played:
		await _play_auto_enemy_element_vfx_to_enemy(enemy, source_positions, gem_type, destroyed_count)
		if not _auto_enemy_can_continue(enemy):
			return
	_on_enemy_attacked(enemy, damage)
	await get_tree().create_timer(0.5 / TrailProjectileScript.speed_divisor + 0.08).timeout


func _auto_effective_active_cd(data: EnemyData, auto_character: CharacterData) -> int:
	return maxi(0, auto_character.active_skill_cd + _auto_effect_sum(data, auto_character, SkillUpgradeUtils.KIND_ACTIVE, 0, "active_cd_delta"))


func _auto_effect_sum(data: EnemyData, auto_character: CharacterData, kind: String, skill_index: int, effect_key: String) -> int:
	var total: int = 0
	var defs: Array[Dictionary] = SkillUpgradeUtils.get_upgrade_defs(auto_character, kind, skill_index)
	var level_count: int = defs.size() if data != null and data.auto_use_max_skill_upgrades else mini(SkillUpgradeUtils.get_unlocked_level(auto_character, kind, skill_index), defs.size())
	for i in range(level_count):
		var effects: Dictionary = SkillUpgradeUtils._get_effects(defs[i])
		total += int(effects.get(effect_key, 0))
	return total


func _auto_effect_max(data: EnemyData, auto_character: CharacterData, kind: String, skill_index: int, effect_key: String) -> int:
	var best: int = 0
	var defs: Array[Dictionary] = SkillUpgradeUtils.get_upgrade_defs(auto_character, kind, skill_index)
	var level_count: int = defs.size() if data != null and data.auto_use_max_skill_upgrades else mini(SkillUpgradeUtils.get_unlocked_level(auto_character, kind, skill_index), defs.size())
	for i in range(level_count):
		var effects: Dictionary = SkillUpgradeUtils._get_effects(defs[i])
		best = maxi(best, int(effects.get(effect_key, 0)))
	return best


# ── 敎人攻擊特效 ─────────────────────────────────────────────

## 敎人攻擊時：拖尾弧光從敎人飛向玩家血條
## 若棋盤上有葉盾，消耗一個葉盾並減少 50% 傷害
func _on_enemy_attacked(enemy: Enemy, damage: int) -> void:
	if not is_instance_valid(enemy):
		_apply_player_damage_with_stage13_guard(damage)
		return
	var from_pos: Vector2 = _get_enemy_image_center(enemy)
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
			_apply_player_damage_with_stage13_guard(reduced_damage)
			_spawn_damage_number(shield_global, reduced_damage, Color(1.0, 0.3, 0.3))
			_play_sfx(_se_impact)
			# 找到 Pan 角色用於日誌
			var panda_data: CharacterData = null
			for i in party.size():
				if party[i].character_name == "Pan":
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
		_apply_player_damage_with_stage13_guard(damage)
		_spawn_damage_number(to_pos, damage, Color(1.0, 0.3, 0.3))
		_play_sfx(_se_impact)
	, CONNECT_ONE_SHOT)
	trail.launch(from_pos, to_pos, color, 0.5)


func _on_enemy_lightbreak_attacked(enemy: Enemy, damage: int, light_count: int) -> void:
	_enemy_board_effects_pending += 1
	var enemy_name: String = enemy.data.get_display_name() if is_instance_valid(enemy) and enemy.data != null else "Enemy"
	var requested_count: int = EnemyData.clamp_action_count(light_count)
	_on_enemy_attacked(enemy, damage)
	await get_tree().create_timer(0.5 / TrailProjectileScript.speed_divisor + 0.05).timeout

	var removed: int = await board.drop_random_gems_of_type(Block.Type.LIGHT, requested_count)
	if removed > 0:
		_add_log_entry("[b]%s[/b] %s：%s ×%d" % [enemy_name, Locale.tr_ui("Lightbreak Attack"), _gem_bbcode(Block.Type.LIGHT), removed], Block.Type.LIGHT)
	else:
		_add_log_entry("[b]%s[/b] %s：沒有%s目標" % [enemy_name, Locale.tr_ui("Lightbreak Attack"), _gem_bbcode(Block.Type.LIGHT)], Block.Type.LIGHT)
	_enemy_board_effects_pending = maxi(0, _enemy_board_effects_pending - 1)


## 敎人石化魔法：隨機將一個普通格轉為 ROCK
func _on_enemy_stone_magic_cast(enemy: Enemy) -> void:
	if not is_instance_valid(enemy):
		return
	var target_pos: Vector2i = board.get_random_rock_transmutation_target()
	var enemy_name: String = enemy.data.get_display_name() if enemy.data != null else "Enemy"
	if target_pos == Vector2i(-1, -1):
		_add_log_entry("[b]%s[/b] 石化魔法沒有目標" % [enemy_name], Block.Type.DARK)
		return

	var target_global: Vector2 = board.to_global(board.grid_to_world(target_pos))
	var color: Color = Color(0.55, 0.58, 0.64, 1.0)
	var gather_duration := 0.36
	_play_transmute_spiral_vfx(target_global, color, gather_duration)
	get_tree().create_timer(gather_duration).timeout.connect(func() -> void:
		if board.transmute_cell_to_rock(target_pos):
			_play_sfx(_se_impact)
	, CONNECT_ONE_SHOT)
	_add_log_entry("[b]%s[/b] 石化魔法：1 格 → %s" % [enemy_name, _gem_bbcode(Block.Type.ROCK)], Block.Type.DARK)


func _play_transmute_spiral_vfx_for_cells(positions: Array, color: Color, duration: float = 0.36) -> void:
	if positions.is_empty():
		return
	var targets: Array[Vector2] = []
	for value in positions:
		var pos: Vector2i = value as Vector2i
		if not board._is_valid(pos):
			continue
		var target_global: Vector2 = board.to_global(board.grid_to_world(pos))
		targets.append(target_global)
	if targets.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var total_trails: int = maxi(1, targets.size() * TRANSMUTE_TRAILS_PER_CELL)
	for i in total_trails:
		var target_global: Vector2 = targets[i % targets.size()]
		_launch_transmute_spiral_trail(target_global, color, duration, rng, i, total_trails)
		if i % 16 == 15:
			await get_tree().process_frame
	await get_tree().create_timer(duration).timeout


## 轉換前置特效：重用現有攻擊 trail，弧光在目標格周圍出現並旋入中心。
func _play_transmute_spiral_vfx(target_global: Vector2, color: Color, duration: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var trail_count: int = TRANSMUTE_TRAILS_PER_CELL
	for i in trail_count:
		_launch_transmute_spiral_trail(target_global, color, duration, rng, i, trail_count)


func _launch_transmute_spiral_trail(target_global: Vector2, color: Color, duration: float, rng: RandomNumberGenerator, index: int, total: int) -> void:
	var trail_color: Color = color
	trail_color.a = 1.0
	# TrailProjectile 內部會再除以 speed_divisor，這裡先乘回去，讓最後一條軌跡能在 duration 結束時貼齊轉石動畫。
	var launch_duration: float = duration * 0.72 * TrailProjectileScript.speed_divisor
	var angle: float = TAU * float(index) / float(maxi(total, 1)) + rng.randf_range(-0.28, 0.28)
	var radius: float = rng.randf_range(96.0, 148.0)
	var from_pos: Vector2 = target_global + Vector2(cos(angle), sin(angle)) * radius
	var swirl_spread: float = rng.randf_range(0.9, 1.65) * (-1.0 if rng.randf() < 0.5 else 1.0)
	var trail: Node2D = _acquire_particle(TRANSMUTE_TRAIL_POOL_SIZE)
	if trail == null:
		return
	trail.z_index = 100
	trail.launch(from_pos, target_global, trail_color, launch_duration, swirl_spread)


# ── 戰鬥回呼 ──────────────────────────────────────────────────

func _setup_player_shield_ui() -> void:
	if _player_shield_overlay != null:
		return
	var hp_bar: Control = $UILayer/PlayerHPBar
	_player_shield_overlay = ColorRect.new()
	_player_shield_overlay.name = "ShieldOverlay"
	_player_shield_overlay.color = Color(0.28, 0.68, 1.0, 0.48)
	_player_shield_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_shield_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player_shield_overlay.offset_top = -4.0
	_player_shield_overlay.offset_bottom = 4.0
	_player_shield_overlay.scale.x = 0.0
	_player_shield_overlay.visible = false
	_player_shield_overlay.z_index = 3
	hp_bar.add_child(_player_shield_overlay)

	_player_shield_badge = Control.new()
	_player_shield_badge.name = "ShieldBadge"
	_player_shield_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_shield_badge.size = Vector2(84.0, 28.0)
	_player_shield_badge.visible = false
	_player_shield_badge.z_index = 7
	hp_bar.add_child(_player_shield_badge)

	_player_shield_icon = TextureRect.new()
	_player_shield_icon.texture = SHIELD_ICON_TEXTURE
	_player_shield_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player_shield_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_player_shield_icon.size = Vector2(24.0, 24.0)
	_player_shield_icon.position = Vector2.ZERO
	_player_shield_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_shield_badge.add_child(_player_shield_icon)

	_player_shield_label = Label.new()
	_player_shield_label.position = Vector2(24.0, -1.0)
	_player_shield_label.size = Vector2(60.0, 28.0)
	_player_shield_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_player_shield_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_player_shield_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player_shield_badge.add_child(_player_shield_label)
	var font: Font = load("res://assets/fonts/game_ui_font.tres")
	_player_shield_label.add_theme_font_override("font", font)
	_player_shield_label.add_theme_font_size_override("font_size", 16)
	_player_shield_label.add_theme_color_override("font_color", Color(0.80, 0.93, 1.0))
	_player_shield_label.add_theme_color_override("font_outline_color", Color(0.02, 0.08, 0.16))
	_player_shield_label.add_theme_constant_override("outline_size", 5)
	player_hp_label.z_index = 6
	_update_player_shield_layout()


## 玩家血量變化時更新 UI（血條動畫 + 受傷/治療閃光）
func _on_player_hp_changed(current: int, maximum: int) -> void:
	player_hp_label.text = "%d" % current
	var ratio: float = float(current) / float(maximum) if maximum > 0 else 0.0
	var current_ratio: float = player_hp_fill.scale.x
	var hp_tween := create_tween()
	hp_tween.tween_property(player_hp_fill, "scale:x", ratio, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# 受傷時顯示白色預覽傷害條
	if ratio < current_ratio:
		_play_hp_damage_preview(player_hp_fill, current_ratio, ratio)
	# 治療時閃綠，受傷時閃紅
	if ratio > current_ratio:
		var heal_tween := create_tween()
		heal_tween.tween_property(player_hp_fill, "modulate", Color(1.25, 1.35, 1.15, 1.0), 0.1)
		heal_tween.tween_property(player_hp_fill, "modulate", Color.WHITE, 0.2)
	else:
		var dmg_tween := create_tween()
		dmg_tween.tween_property(player_hp_fill, "modulate", Color(1.45, 0.78, 0.78, 1.0), 0.1)
		dmg_tween.tween_property(player_hp_fill, "modulate", Color.WHITE, 0.2)


func _on_player_shield_changed(current: int, maximum: int, reason: String) -> void:
	if _player_shield_overlay == null:
		_setup_player_shield_ui()
	var ratio: float = 0.0
	if maximum > 0:
		ratio = clampf(float(mini(current, maximum)) / float(maximum), 0.0, 1.0)

	if _player_shield_tween != null and _player_shield_tween.is_valid():
		_player_shield_tween.kill()
	if _player_shield_badge_tween != null and _player_shield_badge_tween.is_valid():
		_player_shield_badge_tween.kill()

	if current > 0:
		_update_player_shield_layout()
		_player_shield_overlay.visible = true
		_player_shield_badge.visible = true
		_player_shield_overlay.modulate.a = 1.0
		_player_shield_badge.modulate.a = 1.0
		_player_shield_label.text = "%d" % current
		_player_shield_tween = create_tween()
		_player_shield_tween.tween_property(_player_shield_overlay, "scale:x", ratio, 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		return

	if reason == "break" or reason == "falloff":
		_play_player_shield_loss_vfx()
		_player_shield_tween = create_tween()
		_player_shield_tween.tween_property(_player_shield_overlay, "scale:x", 0.0, 0.22).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		_player_shield_tween.tween_callback(func() -> void:
			if is_instance_valid(_player_shield_overlay):
				_player_shield_overlay.visible = false
		)
		_player_shield_badge_tween = create_tween()
		_player_shield_badge_tween.tween_property(_player_shield_badge, "modulate:a", 0.0, 0.35)
		_player_shield_badge_tween.tween_callback(func() -> void:
			if is_instance_valid(_player_shield_badge):
				_player_shield_badge.visible = false
				_player_shield_badge.modulate.a = 1.0
		)
		return

	_player_shield_overlay.scale.x = 0.0
	_player_shield_overlay.visible = false
	_player_shield_badge.visible = false
	_player_shield_badge.modulate.a = 1.0
	_player_shield_label.text = "0"


func _update_player_shield_layout() -> void:
	if _player_shield_overlay != null:
		_player_shield_overlay.pivot_offset = Vector2(_player_shield_overlay.size.x, _player_shield_overlay.size.y * 0.5)
	_position_player_shield_badge(1.0)


func _position_player_shield_badge(_ratio: float) -> void:
	if _player_shield_badge == null:
		return
	var bar_size: Vector2 = player_hp_fill.size
	if bar_size.x <= 0.0:
		bar_size = player_hp_fill.get_rect().size
	var badge_size: Vector2 = _player_shield_badge.size
	var badge_x: float = maxf(0.0, bar_size.x - badge_size.x + 8.0)
	_player_shield_badge.position = Vector2(badge_x, -24.0)


func _play_player_shield_loss_vfx() -> void:
	if _player_shield_icon == null or not is_instance_valid(_player_shield_icon):
		return
	var origin: Vector2 = _player_shield_icon.get_global_rect().get_center()
	DebrisVfx.play(get_tree().current_scene, SHIELD_ICON_TEXTURE, origin, 7, Vector2(0.35, 0.70), Vector2(0.55, 0.95), 120, Color(0.65, 0.90, 1.0, 0.95))


## 回合數變更時更新 UI
func _on_turn_changed(t: int) -> void:
	turn_label.text = "Turn: %d" % t
	round_label.text = "Round: %d" % (battle_manager.current_round + 1)


## 重新整理寶石計量器：合併本回合消除數 + 技能儲存（pending）數
func _refresh_gem_meter() -> void:
	if gem_meter == null:
		return
	var combined: Dictionary = {}
	for k in battle_manager.turn_gem_blasts.keys():
		combined[k] = int(battle_manager.turn_gem_blasts[k])
	for k in battle_manager.pending_skill_blasts.keys():
		var v: int = int(battle_manager.pending_skill_blasts[k])
		if v <= 0:
			continue
		combined[k] = int(combined.get(k, 0)) + v
	gem_meter.refresh(combined)


## 為玩家血量標籤套用 Russo One 字型＋黑色描邊
func _style_player_hp_label() -> void:
	var font: Font = load("res://assets/fonts/game_ui_font.tres")
	player_hp_label.add_theme_font_override("font", font)
	player_hp_label.add_theme_font_size_override("font_size", 16)
	player_hp_label.add_theme_color_override("font_color", Color.WHITE)
	player_hp_label.add_theme_color_override("font_outline_color", Color.BLACK)
	player_hp_label.add_theme_constant_override("outline_size", 6)
	player_hp_label.add_theme_constant_override("margin_left", 8)


func _style_player_hp_bar() -> void:
	player_hp_fill.color = Color(1, 1, 1, 0)
	player_hp_fill.modulate = Color.WHITE
	if is_instance_valid(_player_hp_gradient_fill):
		return

	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.48, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.08, 0.68, 0.96, 1.0),
		Color(0.05, 0.78, 0.78, 1.0),
		Color(0.16, 0.96, 0.55, 1.0),
	])

	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 512
	texture.height = 24
	texture.fill_from = Vector2(0.0, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)

	_player_hp_gradient_fill = TextureRect.new()
	_player_hp_gradient_fill.name = "BlueGreenFill"
	_player_hp_gradient_fill.texture = texture
	_player_hp_gradient_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player_hp_gradient_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_player_hp_gradient_fill.stretch_mode = TextureRect.STRETCH_SCALE
	_player_hp_gradient_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player_hp_fill.add_child(_player_hp_gradient_fill)


## 玩家戰敗
func _on_player_defeated() -> void:
	_escape_failed = true
	_puzzle_turn_limit_failed = true
	_plank_event_pending = false
	_plank_event_deferred_check_running = false
	board.is_busy = true
	# 交叉淡入 One More Run（存於 GameState）
	GameState.crossfade_bgm(load("res://assets/music/One More Run.mp3"), false, 0.6, "defeat")
	_bgm_player = GameState.bgm_player
	await _wait_for_board_motion_idle()
	if _escape_mode and board.has_method("play_escape_marker_scatter"):
		call_deferred("_play_escape_marker_scatter_after_delay", 1.0)
	# 寶石散落動畫
	if board.has_method("play_lose_animation"):
		await board.play_lose_animation()
	_show_defeat_overlay()


func _trigger_puzzle_turn_limit_defeat() -> void:
	if _puzzle_turn_limit_failed or _victory_overlay != null or _defeat_overlay != null:
		return
	_puzzle_turn_limit_failed = true
	board.clear_deferred_clicks()
	board.set_input_queue_locked(true)
	board.is_busy = true
	await _wait_for_board_motion_idle()
	if board.has_method("play_lose_animation"):
		await board.play_lose_animation()
	_show_defeat_overlay("PUZZLE_WRONG_DEFEAT")


func _play_escape_marker_scatter_after_delay(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if _escape_mode and board != null and board.has_method("play_escape_marker_scatter"):
		await board.play_escape_marker_scatter()


## 顯示敗戰覆蓋層
func _show_defeat_overlay(title_key: String = "DEFEATED") -> void:
	if _defeat_overlay != null:
		return
	var font: Font = load("res://assets/fonts/game_ui_font.tres")
	var ui_layer: CanvasLayer = $UILayer

	_defeat_overlay = Control.new()
	_defeat_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_defeat_overlay.modulate = Color(1, 1, 1, 0)
	_defeat_overlay.z_index = 120
	ui_layer.add_child(_defeat_overlay)

	# 暗色背景（fade-in，慢速）
	var dark_bg := ColorRect.new()
	dark_bg.color = Color(0.0, 0.0, 0.0, 0.0)
	dark_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_defeat_overlay.add_child(dark_bg)
	var fade_tw := create_tween().set_parallel(true)
	fade_tw.tween_property(dark_bg, "color:a", 0.85, 1.2) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	fade_tw.tween_property(_defeat_overlay, "modulate:a", 1.0, 1.2)

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
	title.text = Locale.tr_ui(title_key)
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


## 敗戰後重新開始（透過淡黑→重載場景→淡入，徹底切回關卡 BGM 與對話狀態）
func _on_defeat_restart() -> void:
	GameState.fade_out_bgm(0.3)
	GameState.fade_to_scene("res://scenes/main.tscn", 0.4)


func _fade_in_spawned_enemies(duration: float = 0.45, exclude_boss: bool = false) -> void:
	if battle_manager == null:
		return
	var tw := create_tween().set_parallel(true)
	var has_tween: bool = false
	for enemy: Enemy in battle_manager.active_enemies:
		if not is_instance_valid(enemy):
			continue
		if exclude_boss and enemy == _boss_bar_enemy:
			continue
		if enemy.modulate.a >= 0.99:
			continue
		tw.tween_property(enemy, "modulate:a", 1.0, duration) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		has_tween = true
	if has_tween:
		await tw.finished
	else:
		tw.kill()


func _play_round_switch_transition(round_idx: int, total_rounds: int) -> void:
	if total_rounds <= 0:
		return
	var ui_layer: CanvasLayer = $UILayer
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = 52
	ui_layer.add_child(overlay)

	var font: Font = load("res://assets/fonts/game_ui_font.tres")
	var title := Label.new()
	title.text = Locale.tr_ui("ROUND_SWITCH_TITLE") % [round_idx + 1, total_rounds]
	title.set_anchors_preset(Control.PRESET_FULL_RECT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", font)
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_color_override("font_outline_color", Color(0.03, 0.03, 0.04, 1.0))
	title.add_theme_constant_override("outline_size", 8)
	title.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.65))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.modulate.a = 0.0
	overlay.add_child(title)

	var label_tw := create_tween()
	label_tw.tween_property(title, "modulate:a", 1.0, 0.24).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	label_tw.tween_interval(1.62)
	label_tw.tween_property(title, "modulate:a", 0.0, 0.32).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	_play_round_walk_background_motion()
	await label_tw.finished
	if is_instance_valid(overlay):
		overlay.queue_free()


func _play_round_walk_background_motion() -> void:
	if not is_instance_valid(_battle_bg_rect):
		return
	if _round_walk_tween != null and _round_walk_tween.is_valid():
		_round_walk_tween.kill()
	var base_pos: Vector2 = _battle_bg_rect.position
	_round_walk_tween = create_tween()
	for _step in 3:
		_round_walk_tween.tween_property(_battle_bg_rect, "position:y", base_pos.y + 5.0, 0.28) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		_round_walk_tween.tween_property(_battle_bg_rect, "position:y", base_pos.y - 5.0, 0.28) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_round_walk_tween.tween_property(_battle_bg_rect, "position:y", base_pos.y, 0.22) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_round_walk_tween.tween_callback(func() -> void:
		if is_instance_valid(_battle_bg_rect):
			_battle_bg_rect.position = base_pos
	)


## 波次轉換中：鎖定棋盤避免玩家在過場期間操作
func _on_round_transitioning() -> void:
	_clear_pending_instant_spell_work()
	board.set_board_input_paused(true)
	board.is_busy = true
	# 波次轉場：將棋盤暗化（同長按預覽色）
	board.darken_all_gems(0.4)


## 波次清除
func _on_round_cleared() -> void:
	round_label.text = "Round: %d" % (battle_manager.current_round + 1)
	await _play_round_switch_transition(battle_manager.current_round, battle_manager.stage_rounds.size())
	# Round 3（0-indexed = 2）教學：敵人意圖 + 切換目標
	if current_stage.is_tutorial and battle_manager.current_round == 2 and _battle_dialog != null:
		_battle_dialog.show_lines(_Stage1Tutorial.make_round3_dialog())
		await _battle_dialog.all_lines_finished
	# 最後一波（Boss 波）：切換 BGM + 顯示 Boss 出場演出
	if battle_manager.current_round == battle_manager.stage_rounds.size() - 1:
		await _show_boss_intro()
	else:
		await _fade_in_spawned_enemies()
	# State/UI 分離：新一波重置邏輯狀態 + 清空殘留 queue
	board.clear_deferred_clicks()
	board.set_board_input_paused(false)
	battle_manager.clear_logic_pending_attack()
	battle_manager.resync_logic_state()
	board.resync_logic_from_visual()
	# 棋盤淡回（融合提示在淡回完成後自動刷新）
	board.brighten_all_gems(0.5)
	board.is_busy = false


## Boss 出場演出：依關卡設定切換 Boss BGM、顯示 Boss 名稱全螢幕遮罩、淡出後返回
func _show_boss_intro() -> void:
	if current_stage != null and current_stage.boss_bgm != null:
		var boss_bgm_id: String = current_stage.boss_bgm.resource_path
		if boss_bgm_id.is_empty():
			boss_bgm_id = current_stage.stage_id
		GameState.crossfade_bgm(current_stage.boss_bgm, true, 0.8, "boss:" + boss_bgm_id)
		_bgm_player = GameState.bgm_player

	# Boss incoming banner temporarily disabled because the round transition
	# already shows "Round x/y".
	# var boss_name := "BOSS INCOMING"
	#
	# var font: Font = load("res://assets/fonts/game_ui_font.tres")
	# var ui_layer: CanvasLayer = $UILayer
	#
	# var overlay := Control.new()
	# overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	# overlay.z_index = 50
	# ui_layer.add_child(overlay)
	#
	# var bg := ColorRect.new()
	# bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	# bg.color = Color(0.0, 0.0, 0.0, 0.0)
	# overlay.add_child(bg)
	#
	# var title_lbl := Label.new()
	# title_lbl.text = boss_name
	# title_lbl.add_theme_font_override("font", font)
	# title_lbl.add_theme_font_size_override("font_size", 64)
	# title_lbl.add_theme_color_override("font_color", Color(0.91, 0.26, 0.21))
	# title_lbl.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.8))
	# title_lbl.add_theme_constant_override("shadow_offset_x", 3)
	# title_lbl.add_theme_constant_override("shadow_offset_y", 3)
	# title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# title_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	# title_lbl.modulate.a = 0.0
	# overlay.add_child(title_lbl)
	#
	# var tw_in := create_tween().set_parallel(true)
	# tw_in.tween_property(bg, "color", Color(0.0, 0.0, 0.0, 0.65), 0.4)
	# tw_in.tween_property(title_lbl, "modulate:a", 1.0, 0.4)
	# await tw_in.finished
	#
	# await get_tree().create_timer(1.8).timeout
	#
	# var tw_out := create_tween().set_parallel(true)
	# tw_out.tween_property(bg, "color", Color(0.0, 0.0, 0.0, 0.0), 0.4)
	# tw_out.tween_property(title_lbl, "modulate:a", 0.0, 0.4)
	# await tw_out.finished
	# overlay.queue_free()

	# Boss 橫幅結束後才讓頂部 Boss 條淡入
	_reveal_boss_bar()
	await _fade_in_spawned_enemies(0.45, true)


func _get_loot_toast_rect(stack_index: int = 0) -> Rect2:
	var viewport_size: Vector2 = ViewportUtils.get_size()
	var top_inset: float = ViewportUtils.get_safe_insets().x
	var pos := Vector2(
		viewport_size.x - LOOT_TOAST_RIGHT_MARGIN - LOOT_TOAST_SIZE.x,
		top_inset + LOOT_TOAST_TOP_OFFSET + float(stack_index) * (LOOT_TOAST_SIZE.y + LOOT_TOAST_GAP)
	)
	return Rect2(pos, LOOT_TOAST_SIZE)


func _get_loot_toast_target_center() -> Vector2:
	return _get_loot_toast_rect().get_center()


func _get_battle_vfx_3d_layer() -> BattleVfx3DLayer:
	if is_instance_valid(_battle_vfx_3d_layer):
		return _battle_vfx_3d_layer
	if fx_layer == null:
		return null
	_battle_vfx_3d_layer = BattleVfx3DLayerScript.new() as BattleVfx3DLayer
	_battle_vfx_3d_layer.name = "BattleVfx3DLayer"
	fx_layer.add_child(_battle_vfx_3d_layer)
	return _battle_vfx_3d_layer


func _make_gold_coin_3d_proxy(pixel_size: int, animate_spin: bool = true) -> Control:
	var layer := _get_battle_vfx_3d_layer()
	var proxy := GoldCoin3DProxyScript.new() as GoldCoin3DProxy
	if layer != null:
		proxy.configure(layer, pixel_size, animate_spin)
	else:
		proxy.custom_minimum_size = Vector2(pixel_size, pixel_size)
		proxy.size = Vector2(pixel_size, pixel_size)
		proxy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return proxy


func _release_gold_3d_proxies(root: Node) -> void:
	if root == null:
		return
	if root is GoldCoin3DProxy:
		(root as GoldCoin3DProxy).release_3d_coin()
	for child in root.get_children():
		if child is Node:
			_release_gold_3d_proxies(child as Node)


func _make_loot_toast_icon(item_type: ItemDefs.Type, icon_factory: Callable) -> Control:
	if item_type == ItemDefs.Type.GOLD:
		return _make_gold_coin_3d_proxy(LOOT_TOAST_ICON_SIZE, true)
	var icon: Control = null
	if icon_factory.is_valid():
		var node: Variant = icon_factory.call()
		if node is Control:
			icon = node as Control
	if icon == null:
		icon = _make_loot_visual_control(item_type, LOOT_TOAST_ICON_SIZE, true)
	return _wrap_loot_icon_with_shining(item_type, icon, LOOT_TOAST_ICON_SIZE, minf(ItemDefs.get_size_multiplier(item_type), 1.35))


func _make_loot_visual_control(item_type: ItemDefs.Type, pixel_size: int, animate: bool = false) -> Control:
	if item_type == ItemDefs.Type.GOLD:
		return _make_gold_coin_3d_proxy(pixel_size, animate)
	var image: Texture2D = ItemDefs.get_image(item_type)
	if image != null:
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(pixel_size, pixel_size)
		icon.size = Vector2(pixel_size, pixel_size)
		icon.texture = image
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return icon
	var label := Label.new()
	label.text = ItemDefs.get_display_name(item_type).substr(0, 1)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", ItemDefs.get_color(item_type))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(pixel_size, pixel_size)
	label.size = Vector2(pixel_size, pixel_size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _wrap_loot_icon_with_shining(item_type: ItemDefs.Type, icon: Control, pixel_size: int, effect_size_multiplier: float = 1.0) -> Control:
	var shining_color: Variant = ItemDefs.get_shining_color(item_type)
	if not (shining_color is Color):
		return icon
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(pixel_size, pixel_size)
	wrapper.size = Vector2(pixel_size, pixel_size)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var effect_scale: float = maxf(0.1, effect_size_multiplier)

	var ray := Node2D.new()
	ray.name = "LootToastShiningRayBurst"
	ray.position = Vector2(pixel_size, pixel_size) * 0.5
	ray.z_index = -1
	ray.scale = Vector2(0.62, 0.62) * effect_scale
	ray.set_script(PuzzleGoalRayBurstScript)
	ray.set("ray_color", shining_color)
	ray.set("outer_radius", float(pixel_size) * 0.42)
	wrapper.add_child(ray)

	var pulse_ring := Node2D.new()
	pulse_ring.name = "LootToastShiningPulseRing"
	pulse_ring.position = Vector2(pixel_size, pixel_size) * 0.5
	pulse_ring.z_index = 0
	pulse_ring.scale = Vector2(0.54, 0.54) * effect_scale
	pulse_ring.set_script(PuzzleGoalPulseParticlesScript)
	pulse_ring.set("draw_particles", false)
	wrapper.add_child(pulse_ring)
	pulse_ring.call("configure", shining_color)

	icon.position = (Vector2(pixel_size, pixel_size) - icon.size) * 0.5
	wrapper.add_child(icon)

	var dust := Node2D.new()
	dust.name = "LootToastShiningDust"
	dust.position = Vector2(pixel_size, pixel_size) * 0.5
	dust.z_index = 2
	dust.scale = Vector2(0.58, 0.58) * effect_scale
	dust.set_script(PuzzleGoalPulseParticlesScript)
	dust.set("draw_rings", false)
	wrapper.add_child(dust)
	dust.call("configure", shining_color)
	return wrapper


func _make_loot_drop_control(item_type: ItemDefs.Type, pixel_size: int, effect_size_multiplier: float = 1.0) -> Control:
	var wrapper := Control.new()
	wrapper.custom_minimum_size = Vector2(pixel_size, pixel_size)
	wrapper.size = Vector2(pixel_size, pixel_size)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var shadow := PanelContainer.new()
	shadow.name = "LootContactShadow"
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.z_index = -2
	shadow.size = Vector2(float(pixel_size) * 0.48, maxf(5.0, float(pixel_size) * 0.11))
	shadow.custom_minimum_size = shadow.size
	shadow.position = Vector2((float(pixel_size) - shadow.size.x) * 0.5, float(pixel_size) * 0.76)
	shadow.modulate.a = 0.46
	var shadow_style := StyleBoxFlat.new()
	shadow_style.bg_color = Color(0.0, 0.0, 0.0, 0.34)
	shadow_style.set_border_width_all(0)
	shadow_style.set_corner_radius_all(int(shadow.size.y * 0.5))
	shadow.add_theme_stylebox_override("panel", shadow_style)
	wrapper.add_child(shadow)

	var shining_color: Variant = ItemDefs.get_shining_color(item_type)
	var loot_effect_scale: float = maxf(0.1, effect_size_multiplier)
	if shining_color is Color:
		var ray := Node2D.new()
		ray.name = "LootShiningRayBurst"
		ray.position = Vector2(pixel_size, pixel_size) * 0.5
		ray.z_index = -1
		ray.scale = Vector2(0.92, 0.92) * loot_effect_scale
		ray.set_script(PuzzleGoalRayBurstScript)
		ray.set("ray_color", shining_color)
		ray.set("outer_radius", float(pixel_size) * 0.42)
		wrapper.add_child(ray)

		var pulse_ring := Node2D.new()
		pulse_ring.name = "LootShiningPulseRing"
		pulse_ring.position = Vector2(pixel_size, pixel_size) * 0.5
		pulse_ring.z_index = 0
		pulse_ring.scale = Vector2(0.78, 0.78) * loot_effect_scale
		pulse_ring.set_script(PuzzleGoalPulseParticlesScript)
		pulse_ring.set("draw_particles", false)
		wrapper.add_child(pulse_ring)
		pulse_ring.call("configure", shining_color)
	var visual := _make_loot_visual_control(item_type, pixel_size, true)
	visual.position = Vector2.ZERO
	wrapper.add_child(visual)
	if shining_color is Color:
		var dust := Node2D.new()
		dust.name = "LootShiningDust"
		dust.position = Vector2(pixel_size, pixel_size) * 0.5
		dust.z_index = 2
		dust.scale = Vector2(0.95, 0.95) * loot_effect_scale
		dust.set_script(PuzzleGoalPulseParticlesScript)
		dust.set("draw_rings", false)
		wrapper.add_child(dust)
		dust.call("configure", shining_color)
	return wrapper


func _begin_loot_animation() -> void:
	_active_loot_animation_count += 1


func _begin_loot_flight() -> void:
	_active_loot_flight_count += 1


func _finish_loot_flight() -> void:
	_active_loot_flight_count = maxi(0, _active_loot_flight_count - 1)
	if _active_loot_flight_count == 0:
		loot_flights_finished.emit()


func _finish_loot_animation() -> void:
	_active_loot_animation_count = maxi(0, _active_loot_animation_count - 1)
	if _active_loot_animation_count == 0:
		loot_animations_finished.emit()


func _wait_for_loot_animations_finished() -> void:
	while _active_loot_animation_count > 0:
		await loot_animations_finished


func _wait_for_loot_flights_finished() -> void:
	while _active_loot_flight_count > 0:
		await loot_flights_finished


func _animate_loot_toast_label(label: Label, from_total: int, to_total: int) -> void:
	if not is_instance_valid(label):
		return
	label.set_meta("loot_toast_value", to_total)
	var count_tw := create_tween()
	count_tw.tween_method(func(value: float) -> void:
		if is_instance_valid(label):
			label.text = "%d" % int(round(value))
	, float(maxi(0, from_total)), float(maxi(0, to_total)), 0.45).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _enqueue_loot_toast(item_type: ItemDefs.Type, from_total: int, to_total: int, icon_factory: Callable = Callable(), finished_callback: Callable = Callable()) -> void:
	for active_index in _active_loot_toasts.size():
		var active: Dictionary = _active_loot_toasts[active_index]
		if int(active.get("type", -1)) != int(item_type) or bool(active.get("closing", false)):
			continue
		var label: Label = active.get("label", null) as Label
		var current_total: int = int(active.get("to_total", from_total))
		active["to_total"] = maxi(current_total, to_total)
		var callbacks: Array = active.get("callbacks", [])
		if finished_callback.is_valid():
			callbacks.append(finished_callback)
		active["callbacks"] = callbacks
		_active_loot_toasts[active_index] = active
		_animate_loot_toast_label(label, current_total, int(active["to_total"]))
		return
	for entry_index in _loot_toast_queue.size():
		var queued: Dictionary = _loot_toast_queue[entry_index]
		if int(queued.get("type", -1)) != int(item_type):
			continue
		queued["to_total"] = maxi(int(queued.get("to_total", from_total)), to_total)
		var callbacks: Array = queued.get("callbacks", [])
		if finished_callback.is_valid():
			callbacks.append(finished_callback)
		queued["callbacks"] = callbacks
		_loot_toast_queue[entry_index] = queued
		return
	var callbacks: Array = []
	if finished_callback.is_valid():
		callbacks.append(finished_callback)
	_loot_toast_queue.append({
		"type": item_type,
		"from_total": from_total,
		"to_total": to_total,
		"icon_factory": icon_factory,
		"callbacks": callbacks,
	})
	_start_next_loot_toast()


func _layout_active_loot_toasts(animated: bool = true) -> void:
	var visible_index := 0
	for entry_index in _active_loot_toasts.size():
		var entry: Dictionary = _active_loot_toasts[entry_index]
		if bool(entry.get("closing", false)):
			continue
		var panel: Control = entry.get("panel", null) as Control
		if not is_instance_valid(panel):
			continue
		var target_rect := _get_loot_toast_rect(visible_index)
		entry["stack_index"] = visible_index
		_active_loot_toasts[entry_index] = entry
		if animated:
			var tw := create_tween()
			tw.tween_property(panel, "position", target_rect.position, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		else:
			panel.position = target_rect.position
		visible_index += 1


func _start_next_loot_toast() -> void:
	if _loot_toast_starting or _loot_toast_queue.is_empty():
		return
	_loot_toast_starting = true
	var entry: Dictionary = _loot_toast_queue.pop_front()
	var item_type: ItemDefs.Type = int(entry.get("type", ItemDefs.Type.GOLD)) as ItemDefs.Type
	var from_total: int = int(entry.get("from_total", 0))
	var to_total: int = int(entry.get("to_total", from_total))
	var icon_factory: Callable = entry.get("icon_factory", Callable()) as Callable
	var stack_index: int = 0
	for active: Dictionary in _active_loot_toasts:
		if not bool(active.get("closing", false)):
			stack_index += 1
	var toast_rect := _get_loot_toast_rect(stack_index)
	var viewport_size: Vector2 = ViewportUtils.get_size()
	var panel := PanelContainer.new()
	panel.name = "LootToast"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 0.0
	panel.position = Vector2(viewport_size.x + 6.0, toast_rect.position.y)
	panel.size = toast_rect.size
	panel.custom_minimum_size = toast_rect.size
	panel.modulate.a = 0.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.5)
	style.border_color = Color(0.0, 0.0, 0.0, 0.0)
	style.set_border_width_all(0)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(4)
	panel.add_theme_stylebox_override("panel", style)
	$UILayer.add_child(panel)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	panel.add_child(row)

	var icon_slot := CenterContainer.new()
	icon_slot.custom_minimum_size = Vector2(64, 56)
	icon_slot.clip_contents = true
	row.add_child(icon_slot)

	var icon := _make_loot_toast_icon(item_type, icon_factory)
	icon_slot.add_child(icon)

	var label := Label.new()
	label.text = "%d" % maxi(0, from_total)
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", ItemDefs.get_color(item_type).lerp(Color.WHITE, 0.12))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(86, 54)
	row.add_child(label)
	entry["panel"] = panel
	entry["label"] = label
	entry["closing"] = false
	entry["stack_index"] = stack_index
	_active_loot_toasts.append(entry)
	_animate_loot_toast_label(label, from_total, to_total)

	var tw := create_tween()
	tw.tween_property(panel, "position", toast_rect.position, LOOT_TOAST_SLIDE_IN_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(panel, "modulate:a", 1.0, LOOT_TOAST_SLIDE_IN_DURATION)
	tw.tween_callback(func() -> void:
		_loot_toast_starting = false
		_start_next_loot_toast()
	)
	tw.tween_interval(LOOT_TOAST_HOLD_DURATION)
	tw.tween_callback(func() -> void:
		for active_index in _active_loot_toasts.size():
			var active: Dictionary = _active_loot_toasts[active_index]
			if active.get("panel", null) == panel:
				active["closing"] = true
				_active_loot_toasts[active_index] = active
				break
	)
	tw.tween_property(panel, "position:y", toast_rect.position.y - 28.0, LOOT_TOAST_SLIDE_OUT_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(panel, "modulate:a", 0.0, LOOT_TOAST_SLIDE_OUT_DURATION)
	tw.tween_callback(func() -> void:
		var callbacks: Array = []
		for active_index in range(_active_loot_toasts.size() - 1, -1, -1):
			var active: Dictionary = _active_loot_toasts[active_index]
			if active.get("panel", null) == panel:
				callbacks = active.get("callbacks", [])
				_active_loot_toasts.remove_at(active_index)
				break
		for callback: Callable in callbacks:
			if callback.is_valid():
				callback.call()
		if is_instance_valid(panel):
			_release_gold_3d_proxies(panel)
			panel.queue_free()
		_layout_active_loot_toasts(true)
		_start_next_loot_toast()
	)


func _play_loot_drop(start_position: Vector2, item_type: ItemDefs.Type, _amount: int, target_total: int) -> void:
	_begin_loot_animation()
	_begin_loot_flight()
	var previous_total: int = int(_loot_toast_totals.get(item_type, 0))
	_loot_toast_totals[item_type] = target_total
	var icon_factory := func():
		return _make_loot_visual_control(item_type, LOOT_TOAST_ICON_SIZE, true)
	var finished_callback := func() -> void:
		_finish_loot_animation()
	if fx_layer == null:
		_finish_loot_flight()
		_enqueue_loot_toast(item_type, previous_total, target_total, icon_factory, finished_callback)
		return
	var base_fly_size: int = GOLD_COIN_VIEWPORT_SIZE if item_type == ItemDefs.Type.GOLD else LOOT_FLY_ICON_SIZE
	var item_size_multiplier: float = ItemDefs.get_size_multiplier(item_type)
	var fly_size: int = maxi(1, int(round(float(base_fly_size) * item_size_multiplier)))
	var loot_view := _make_loot_drop_control(item_type, fly_size, item_size_multiplier)
	loot_view.position = start_position - Vector2(fly_size, fly_size) * 0.5
	loot_view.scale = Vector2(0.8, 0.8)
	fx_layer.add_child(loot_view)

	var floor_position: Vector2 = start_position + GOLD_COIN_FLOOR_DROP
	var target_position: Vector2 = _get_loot_toast_target_center()
	var target_control_position: Vector2 = target_position - Vector2(fly_size, fly_size) * 0.5
	var floor_control_position: Vector2 = floor_position - Vector2(fly_size, fly_size) * 0.5
	var fly_distance: float = floor_control_position.distance_to(target_control_position)
	var fly_arc_height: float = maxf(92.0, fly_distance * 0.28)
	var fly_arc_control_position: Vector2 = (floor_control_position + target_control_position) * 0.5 + Vector2(0.0, -fly_arc_height)

	var tw := create_tween()
	tw.tween_property(loot_view, "position", floor_control_position, GOLD_COIN_DROP_DURATION).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BOUNCE)
	tw.tween_interval(GOLD_COIN_SPIN_HOLD_DURATION)
	tw.tween_method(func(t: float) -> void:
		if not is_instance_valid(loot_view):
			return
		var inv_t: float = 1.0 - t
		loot_view.position = inv_t * inv_t * floor_control_position \
			+ 2.0 * inv_t * t * fly_arc_control_position \
			+ t * t * target_control_position
	, 0.0, 1.0, GOLD_COIN_FLY_DURATION).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_property(loot_view, "scale", Vector2(0.42, 0.42), GOLD_COIN_FLY_DURATION).set_ease(Tween.EASE_IN)
	tw.tween_callback(func() -> void:
		_finish_loot_flight()
		if is_instance_valid(loot_view):
			_release_gold_3d_proxies(loot_view)
			loot_view.queue_free()
		_enqueue_loot_toast(item_type, previous_total, target_total, icon_factory, finished_callback)
	)

	var fade_tw := create_tween()
	fade_tw.tween_interval(GOLD_COIN_DROP_DURATION + GOLD_COIN_SPIN_HOLD_DURATION + GOLD_COIN_FLY_DURATION - GOLD_COIN_FADE_DURATION)
	fade_tw.tween_property(loot_view, "modulate:a", 0.35, GOLD_COIN_FADE_DURATION).set_ease(Tween.EASE_IN)


func _play_gold_coin_drop(start_position: Vector2, amount: int, target_total: int) -> void:
	_play_loot_drop(start_position, ItemDefs.Type.GOLD, amount, target_total)


## 敵人死亡掉落戰利品：存入本場積累，播放通用 loot drop/fly/toast 流程。
func _on_loot_dropped(enemy_data: EnemyData, results: Array, enemy_level: int, drop_position: Vector2) -> void:
	# 累計本場經驗值
	_battle_exp += enemy_data.get_exp_drop_for_level(enemy_level)

	# 找出死亡的敵人節點以取得掉落起點（若找不到就用螢幕中央）
	var popup_pos: Vector2 = drop_position
	if popup_pos == Vector2.ZERO:
		popup_pos = Vector2(get_viewport().get_visible_rect().size / 2)

	for result: Dictionary in results:
		var type: ItemDefs.Type = result.type
		var amount: int = result.amount
		# 積累到本場計數
		var current: int = _battle_loot.get(type, 0)
		_battle_loot[type] = current + amount
		_play_loot_drop(popup_pos, type, amount, int(_battle_loot[type]))


## 設定逃脫模式 HUD：依關卡 mode 顯示/隱藏剩餘距離
func _setup_escape_hud() -> void:
	_escape_mode = current_stage != null and current_stage.mode == StageData.Mode.ESCAPE
	_escape_won = false
	_escape_failed = false
	_escape_goal_wood_row = -1
	if _escape_mode:
		_escape_distance_target = maxi(current_stage.escape_refill_target, 0)
		_escape_distance_traveled = 0
		_escape_distance_remaining = _escape_distance_target
		_escape_distance_displayed = _escape_distance_remaining
		_escape_refill_label.visible = true
		_setup_escape_distance_label_style()
		_update_escape_distance_label(false, true)
		var start_pos := Vector2i(board.columns / 2, ESCAPE_SCROLL_RESET_ROW)
		board.set_escape_marker_colors(_get_party_escape_marker_colors())
		board.enable_escape_marker(start_pos)
		_update_escape_goal_wood_row()
	else:
		_escape_distance_target = 0
		_escape_distance_traveled = 0
		_escape_distance_remaining = 0
		_escape_distance_displayed = 0
		_escape_failed = false
		_escape_goal_wood_row = -1
		_escape_refill_label.visible = false
		if is_instance_valid(_escape_distance_number_label):
			_escape_distance_number_label.visible = false
		if is_instance_valid(_escape_distance_unit_label):
			_escape_distance_unit_label.visible = false


func _get_party_escape_marker_colors() -> Array[Color]:
	var colors: Array[Color] = []
	for c: CharacterData in party:
		if c == null:
			continue
		var color: Color = Block.COLORS.get(c.gem_type, Color.WHITE)
		color.a = 0.95
		colors.append(color)
	if colors.is_empty():
		colors.append(Color.WHITE)
	var source: Array[Color] = colors.duplicate()
	var idx: int = 0
	while colors.size() < 3 and not source.is_empty():
		colors.append(source[idx % source.size()])
		idx += 1
	return colors


func _update_escape_goal_wood_row() -> void:
	if not _escape_mode or _escape_won or _escape_failed or board == null:
		return
	if _escape_goal_wood_row >= 0:
		return
	if not board.has_method("place_escape_goal_wood_row"):
		return
	var wood_row: int = _get_escape_goal_wood_row_for_marker_y(board.get_escape_marker_grid_pos().y)
	if wood_row < 0:
		return
	var placed_row: int = int(board.place_escape_goal_wood_row(wood_row))
	if placed_row >= 0:
		_escape_goal_wood_row = placed_row


func _get_escape_goal_wood_row_for_marker_y(marker_y: int) -> int:
	if not _escape_mode or board == null:
		return -1
	var remaining_rows: int = int(ceil(float(maxi(_escape_distance_remaining, 0)) / float(ESCAPE_METERS_PER_ROW)))
	if remaining_rows <= 0:
		return -1
	var wood_row: int = marker_y + remaining_rows
	if wood_row < 0 or wood_row >= board.rows:
		return -1
	return wood_row


func _setup_escape_distance_label_style() -> void:
	if _escape_refill_label == null:
		return
	_escape_refill_label.label_settings = null
	_escape_refill_label.add_theme_font_size_override("font_size", 28)
	_escape_refill_label.add_theme_color_override("font_color", Color.WHITE)
	_escape_refill_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_escape_refill_label.add_theme_constant_override("outline_size", 8)
	_escape_refill_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_escape_refill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_escape_refill_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_escape_refill_label.z_index = 6
	_escape_refill_label.text = "剩餘"
	if not is_instance_valid(_escape_distance_number_label):
		_escape_distance_number_label = _make_escape_distance_part_label()
		_escape_distance_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		$UILayer.add_child(_escape_distance_number_label)
	if not is_instance_valid(_escape_distance_unit_label):
		_escape_distance_unit_label = _make_escape_distance_part_label()
		_escape_distance_unit_label.text = "米"
		_escape_distance_unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		$UILayer.add_child(_escape_distance_unit_label)
	_escape_distance_number_label.visible = true
	_escape_distance_unit_label.visible = true
	_position_escape_distance_label()


func _make_escape_distance_part_label() -> Label:
	var label := Label.new()
	label.label_settings = null
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 9)
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	label.z_index = 6
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _position_escape_distance_label() -> void:
	if _escape_refill_label == null:
		return
	var right: float = board.position.x + float(board.columns * board.CELL_SIZE)
	var top: float = board.position.y
	var y: float = maxf(top - 46.0, 4.0)
	_escape_refill_label.position = Vector2(right , y)
	_escape_refill_label.size = Vector2(72.0, 42.0)
	if is_instance_valid(_escape_distance_number_label):
		_escape_distance_number_label.position = Vector2(right + 70.0, y+3)
		_escape_distance_number_label.size = Vector2(64.0, 42.0)
	if is_instance_valid(_escape_distance_unit_label):
		_escape_distance_unit_label.position = Vector2(right + 138.0, y)
		_escape_distance_unit_label.size = Vector2(28.0, 42.0)


func _update_escape_distance_label(animate_digits: bool = false, immediate: bool = false) -> void:
	if _escape_refill_label == null:
		return
	_escape_refill_label.label_settings = null
	_escape_refill_label.text = "剩餘"
	_escape_refill_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_escape_refill_label.add_theme_constant_override("outline_size", 9)
	_position_escape_distance_label()
	if not is_instance_valid(_escape_distance_number_label):
		return
	var target: int = maxi(_escape_distance_remaining, 0)
	if immediate or not animate_digits:
		_escape_distance_displayed = target
		_escape_distance_number_label.text = "%d" % target
		_position_escape_distance_label()
		return
	_animate_escape_distance_digits(_escape_distance_displayed, target)


func _animate_escape_distance_digits(from_value: int, to_value: int) -> void:
	if not is_instance_valid(_escape_distance_number_label):
		return
	if _escape_distance_tween != null and _escape_distance_tween.is_valid():
		_escape_distance_tween.kill()
	_escape_distance_number_label.scale = Vector2.ONE
	var direction: int = -1 if to_value < from_value else 1
	var step_size: int = 5
	var values: Array[int] = []
	var current: int = from_value
	while current != to_value and values.size() < 80:
		var next_value: int = current + direction * step_size
		if direction < 0 and next_value < to_value:
			next_value = to_value
		elif direction > 0 and next_value > to_value:
			next_value = to_value
		values.append(next_value)
		current = next_value
	if values.is_empty():
		return
	var base_pos: Vector2 = _escape_distance_number_label.position
	_escape_distance_tween = create_tween()
	for next_value in values:
		_escape_distance_tween.tween_property(_escape_distance_number_label, "position:y", base_pos.y + 16.0, 0.035) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		_escape_distance_tween.tween_callback(_set_escape_distance_digit_frame.bind(next_value, base_pos.y))
		_escape_distance_tween.tween_property(_escape_distance_number_label, "position:y", base_pos.y, 0.035) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _set_escape_distance_digit_frame(value: int, base_y: float) -> void:
	if not is_instance_valid(_escape_distance_number_label):
		return
	_escape_distance_number_label.text = "%d" % value
	_escape_distance_number_label.position.y = base_y - 14.0
	_escape_distance_displayed = value


func _setup_puzzle_goal_hud() -> void:
	_puzzle_mode = current_stage != null and current_stage.mode == StageData.Mode.PUZZLE
	_puzzle_goal_completed = false
	_puzzle_turn_limit_failed = false
	if _puzzle_goal_tween != null and _puzzle_goal_tween.is_valid():
		_puzzle_goal_tween.kill()
	if _puzzle_turn_tween != null and _puzzle_turn_tween.is_valid():
		_puzzle_turn_tween.kill()
	_stop_puzzle_turn_warning_pulse()
	if not _puzzle_mode:
		_puzzle_goal_required = 0
		_puzzle_goal_progress = 0
		_puzzle_goal_remaining = 0
		_puzzle_goal_displayed = 0
		_puzzle_turn_limit = 0
		_puzzle_turns_left = 0
		_puzzle_turns_displayed = 0
		if is_instance_valid(_puzzle_goal_panel):
			_puzzle_goal_panel.queue_free()
		_puzzle_goal_panel = null
		_puzzle_turn_prefix_label = null
		_puzzle_turn_number_label = null
		_puzzle_turn_suffix_label = null
		return

	_puzzle_goal_required = maxi(current_stage.puzzle_goal_required_count, 0)
	_puzzle_goal_progress = 0
	_puzzle_goal_remaining = _puzzle_goal_required
	_puzzle_goal_displayed = _puzzle_goal_remaining
	_puzzle_turn_limit = maxi(current_stage.puzzle_turn_limit, 1)
	_puzzle_turns_left = _puzzle_turn_limit
	_puzzle_turns_displayed = _puzzle_turns_left
	for child in enemy_container.get_children():
		enemy_container.remove_child(child)
		child.queue_free()
	enemy_container.visible = true
	_build_puzzle_goal_panel()
	_update_puzzle_goal_panel(false, true)
	_update_puzzle_turn_panel(false, true)


func _build_puzzle_goal_panel() -> void:
	if is_instance_valid(_puzzle_goal_panel):
		return
	_puzzle_goal_panel = PanelContainer.new()
	_puzzle_goal_panel.name = "PuzzleGoalPanel"
	_puzzle_goal_panel.custom_minimum_size = Vector2(270, 124)
	_puzzle_goal_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.09, 0.86)
	style.border_color = Color(0.95, 0.78, 0.32, 0.92)
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	_puzzle_goal_panel.add_theme_stylebox_override("panel", style)
	enemy_container.add_child(_puzzle_goal_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 6)
	_puzzle_goal_panel.add_child(margin)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	margin.add_child(grid)

	_puzzle_goal_prefix_label = _make_puzzle_goal_part_label(24)
	_puzzle_goal_prefix_label.text = "剩餘"
	_puzzle_goal_prefix_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_puzzle_goal_prefix_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_puzzle_goal_prefix_label.custom_minimum_size = Vector2(62, 36)
	grid.add_child(_puzzle_goal_prefix_label)

	_puzzle_goal_number_label = _make_puzzle_goal_part_label(24)
	_puzzle_goal_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_puzzle_goal_number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_puzzle_goal_number_label.custom_minimum_size = Vector2(36, 34)
	grid.add_child(_puzzle_goal_number_label)

	_puzzle_goal_icon_slot = _make_puzzle_goal_icon_slot()
	grid.add_child(_puzzle_goal_icon_slot)
	_puzzle_goal_target_label = null

	_puzzle_turn_prefix_label = _make_puzzle_goal_part_label(24)
	_puzzle_turn_prefix_label.text = "剩餘"
	_puzzle_turn_prefix_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_puzzle_turn_prefix_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_puzzle_turn_prefix_label.custom_minimum_size = Vector2(62, 36)
	grid.add_child(_puzzle_turn_prefix_label)

	_puzzle_turn_number_label = _make_puzzle_goal_part_label(24)
	_puzzle_turn_number_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_puzzle_turn_number_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_puzzle_turn_number_label.custom_minimum_size = Vector2(36, 34)
	grid.add_child(_puzzle_turn_number_label)

	_puzzle_turn_suffix_label = _make_puzzle_goal_part_label(24)
	_puzzle_turn_suffix_label.text = "步數"
	_puzzle_turn_suffix_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_puzzle_turn_suffix_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_puzzle_turn_suffix_label.custom_minimum_size = Vector2(70, 36)
	grid.add_child(_puzzle_turn_suffix_label)


func _make_puzzle_goal_icon_slot() -> Control:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(70, 58)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_puzzle_goal_icon = TextureRect.new()
	_puzzle_goal_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_puzzle_goal_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_puzzle_goal_icon.custom_minimum_size = Vector2(58, 58)
	_puzzle_goal_icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	_puzzle_goal_icon.offset_left = 6.0
	_puzzle_goal_icon.offset_top = 0.0
	_puzzle_goal_icon.offset_right = -6.0
	_puzzle_goal_icon.offset_bottom = 0.0
	_puzzle_goal_icon.z_index = 0
	slot.add_child(_puzzle_goal_icon)

	_puzzle_goal_icon_ray = Node2D.new()
	_puzzle_goal_icon_ray.name = "PuzzleGoalIconRayBurst"
	_puzzle_goal_icon_ray.position = Vector2(35, 29)
	_puzzle_goal_icon_ray.scale = Vector2(0.72, 0.72)
	_puzzle_goal_icon_ray.z_index = 1
	_puzzle_goal_icon_ray.set_script(PuzzleGoalRayBurstScript)
	_puzzle_goal_icon_ray.set("ray_color", PUZZLE_KEY_HUD_AURA_COLOR)
	slot.add_child(_puzzle_goal_icon_ray)

	_puzzle_goal_icon_fx = Node2D.new()
	_puzzle_goal_icon_fx.name = "PuzzleGoalIconParticles"
	_puzzle_goal_icon_fx.position = Vector2(35, 29)
	_puzzle_goal_icon_fx.scale = Vector2(0.58, 0.58)
	_puzzle_goal_icon_fx.z_index = 2
	_puzzle_goal_icon_fx.set_script(PuzzleGoalPulseParticlesScript)
	slot.add_child(_puzzle_goal_icon_fx)
	_puzzle_goal_icon_fx.call_deferred("configure", PUZZLE_KEY_HUD_AURA_COLOR)

	_puzzle_goal_icon_gem = TextureRect.new()
	_puzzle_goal_icon_gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_puzzle_goal_icon_gem.texture = PUZZLE_KEY_HUD_GEM_TEXTURE
	_puzzle_goal_icon_gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_puzzle_goal_icon_gem.custom_minimum_size = Vector2(58, 58)
	_puzzle_goal_icon_gem.set_anchors_preset(Control.PRESET_FULL_RECT)
	_puzzle_goal_icon_gem.offset_left = 6.0
	_puzzle_goal_icon_gem.offset_top = 0.0
	_puzzle_goal_icon_gem.offset_right = -6.0
	_puzzle_goal_icon_gem.offset_bottom = 0.0
	_puzzle_goal_icon_gem.z_index = 3
	slot.add_child(_puzzle_goal_icon_gem)
	return slot


func _make_puzzle_goal_part_label(font_size: int) -> Label:
	var label := Label.new()
	label.label_settings = null
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 7)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _puzzle_goal_target_name(type_value: int) -> String:
	match type_value:
		Block.Type.RED:
			return "紅寶石"
		Block.Type.BLUE:
			return "藍寶石"
		Block.Type.GREEN:
			return "綠寶石"
		Block.Type.LIGHT:
			return "光寶石"
		Block.Type.DARK:
			return "暗寶石"
		Block.Type.PLANK:
			return "木板"
		Block.Type.PUZZLE_KEY:
			return "解謎鑰匙"
		_:
			return "目標"


func _update_puzzle_goal_panel(animate_digits: bool = false, immediate: bool = false) -> void:
	if not _puzzle_mode or not is_instance_valid(_puzzle_goal_panel):
		return
	var target_type: int = int(current_stage.puzzle_goal_target_type) if current_stage != null else int(Block.Type.RED)
	if is_instance_valid(_puzzle_goal_icon):
		_puzzle_goal_icon.texture = PUZZLE_KEY_HUD_BASE_TEXTURE if target_type == int(Block.Type.PUZZLE_KEY) else Block.GEM_TEXTURES.get(target_type, null)
	if is_instance_valid(_puzzle_goal_icon_ray):
		_puzzle_goal_icon_ray.visible = target_type == int(Block.Type.PUZZLE_KEY)
		if _puzzle_goal_icon_ray.visible:
			_puzzle_goal_icon_ray.set("ray_color", PUZZLE_KEY_HUD_AURA_COLOR)
	if is_instance_valid(_puzzle_goal_icon_fx):
		_puzzle_goal_icon_fx.visible = target_type == int(Block.Type.PUZZLE_KEY)
		if _puzzle_goal_icon_fx.visible:
			_puzzle_goal_icon_fx.call("configure", PUZZLE_KEY_HUD_AURA_COLOR)
	if is_instance_valid(_puzzle_goal_icon_gem):
		_puzzle_goal_icon_gem.visible = target_type == int(Block.Type.PUZZLE_KEY)
	if is_instance_valid(_puzzle_goal_prefix_label):
		_puzzle_goal_prefix_label.text = "達成" if _puzzle_goal_completed else "剩餘"
	if is_instance_valid(_puzzle_goal_target_label):
		_puzzle_goal_target_label.text = _puzzle_goal_target_name(target_type)
	if not is_instance_valid(_puzzle_goal_number_label):
		return
	var target: int = maxi(_puzzle_goal_remaining, 0)
	if immediate or not animate_digits:
		_puzzle_goal_displayed = target
		_puzzle_goal_number_label.text = "%d" % target
		return
	_animate_puzzle_goal_digits(_puzzle_goal_displayed, target)


func _update_puzzle_turn_panel(animate_digits: bool = false, immediate: bool = false) -> void:
	if not _puzzle_mode or not is_instance_valid(_puzzle_turn_number_label):
		return
	if is_instance_valid(_puzzle_turn_prefix_label):
		_puzzle_turn_prefix_label.text = "剩餘"
	if is_instance_valid(_puzzle_turn_suffix_label):
		_puzzle_turn_suffix_label.text = "步數"
	var target: int = maxi(_puzzle_turns_left, 0)
	if immediate or not animate_digits:
		_puzzle_turns_displayed = target
		_puzzle_turn_number_label.text = "%d" % target
		_refresh_puzzle_turn_warning_pulse()
		return
	_animate_puzzle_turn_digits(_puzzle_turns_displayed, target)
	_refresh_puzzle_turn_warning_pulse()


func _refresh_puzzle_turn_warning_pulse() -> void:
	if not is_instance_valid(_puzzle_turn_number_label):
		return
	if _puzzle_turns_left == 1 and not _puzzle_goal_completed and not _puzzle_turn_limit_failed:
		_start_puzzle_turn_warning_pulse()
	else:
		_stop_puzzle_turn_warning_pulse()


func _start_puzzle_turn_warning_pulse() -> void:
	if not is_instance_valid(_puzzle_turn_number_label):
		return
	if _puzzle_turn_warning_tween != null and _puzzle_turn_warning_tween.is_valid():
		return
	_puzzle_turn_warning_tween = create_tween().set_loops()
	_puzzle_turn_warning_tween.tween_method(_set_puzzle_turn_warning_color, Color(1.0, 0.18, 0.16), Color.WHITE, 0.32) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_puzzle_turn_warning_tween.tween_method(_set_puzzle_turn_warning_color, Color.WHITE, Color(1.0, 0.18, 0.16), 0.32) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


func _stop_puzzle_turn_warning_pulse() -> void:
	if _puzzle_turn_warning_tween != null and _puzzle_turn_warning_tween.is_valid():
		_puzzle_turn_warning_tween.kill()
	_puzzle_turn_warning_tween = null
	_set_puzzle_turn_warning_color(Color.WHITE)


func _set_puzzle_turn_warning_color(color: Color) -> void:
	if not is_instance_valid(_puzzle_turn_number_label):
		return
	_puzzle_turn_number_label.add_theme_color_override("font_color", color)


func _animate_puzzle_turn_digits(from_value: int, to_value: int) -> void:
	if not is_instance_valid(_puzzle_turn_number_label):
		return
	if _puzzle_turn_tween != null and _puzzle_turn_tween.is_valid():
		_puzzle_turn_tween.kill()
	_puzzle_turn_number_label.scale = Vector2.ONE
	var direction: int = -1 if to_value < from_value else 1
	var values: Array[int] = []
	var current: int = from_value
	while current != to_value and values.size() < 80:
		var next_value: int = current + direction
		if direction < 0 and next_value < to_value:
			next_value = to_value
		elif direction > 0 and next_value > to_value:
			next_value = to_value
		values.append(next_value)
		current = next_value
	if values.is_empty():
		return
	var base_pos: Vector2 = _puzzle_turn_number_label.position
	_puzzle_turn_tween = create_tween()
	for next_value in values:
		_puzzle_turn_tween.tween_property(_puzzle_turn_number_label, "position:y", base_pos.y + 10.0, 0.04) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		_puzzle_turn_tween.tween_callback(_set_puzzle_turn_digit_frame.bind(next_value, base_pos.y))
		_puzzle_turn_tween.tween_property(_puzzle_turn_number_label, "position:y", base_pos.y, 0.04) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _set_puzzle_turn_digit_frame(value: int, base_y: float) -> void:
	if not is_instance_valid(_puzzle_turn_number_label):
		return
	_puzzle_turn_number_label.text = "%d" % value
	_puzzle_turn_number_label.position.y = base_y - 8.0
	_puzzle_turns_displayed = value


func _animate_puzzle_goal_digits(from_value: int, to_value: int) -> void:
	if not is_instance_valid(_puzzle_goal_number_label):
		return
	if _puzzle_goal_tween != null and _puzzle_goal_tween.is_valid():
		_puzzle_goal_tween.kill()
	_puzzle_goal_number_label.scale = Vector2.ONE
	var direction: int = -1 if to_value < from_value else 1
	var delta: int = abs(to_value - from_value)
	var step_size: int = maxi(1, int(ceil(float(delta) / 30.0)))
	var values: Array[int] = []
	var current: int = from_value
	while current != to_value and values.size() < 80:
		var next_value: int = current + direction * step_size
		if direction < 0 and next_value < to_value:
			next_value = to_value
		elif direction > 0 and next_value > to_value:
			next_value = to_value
		values.append(next_value)
		current = next_value
	if values.is_empty():
		return
	var base_pos: Vector2 = _puzzle_goal_number_label.position
	_puzzle_goal_tween = create_tween()
	for next_value in values:
		_puzzle_goal_tween.tween_property(_puzzle_goal_number_label, "position:y", base_pos.y + 14.0, 0.035) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		_puzzle_goal_tween.tween_callback(_set_puzzle_goal_digit_frame.bind(next_value, base_pos.y))
		_puzzle_goal_tween.tween_property(_puzzle_goal_number_label, "position:y", base_pos.y, 0.035) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _set_puzzle_goal_digit_frame(value: int, base_y: float) -> void:
	if not is_instance_valid(_puzzle_goal_number_label):
		return
	_puzzle_goal_number_label.text = "%d" % value
	_puzzle_goal_number_label.position.y = base_y - 12.0
	_puzzle_goal_displayed = value


func _on_goal_cells_broken(block_type: int, count: int, _global_positions: Array) -> void:
	if not _puzzle_mode or _puzzle_goal_completed:
		return
	if current_stage == null or current_stage.mode != StageData.Mode.PUZZLE:
		return
	if current_stage.puzzle_goal_kind != StageData.PuzzleGoalKind.BREAK_COUNT:
		return
	if int(block_type) != int(current_stage.puzzle_goal_target_type):
		return
	var gained: int = maxi(count, 0)
	if gained <= 0:
		return
	_play_sfx(_se_goal_achieve)
	_puzzle_goal_progress = mini(_puzzle_goal_progress + gained, _puzzle_goal_required)
	_puzzle_goal_remaining = maxi(_puzzle_goal_required - _puzzle_goal_progress, 0)
	if _puzzle_goal_remaining <= 0:
		_puzzle_goal_completed = true
	_update_puzzle_goal_panel(true)
	if _puzzle_goal_completed:
		call_deferred("_finish_puzzle_goal_after_feedback")


func _finish_puzzle_goal_after_feedback() -> void:
	await get_tree().create_timer(0.35).timeout
	if not _puzzle_mode or not _puzzle_goal_completed:
		return
	if _victory_overlay != null:
		return
	while _puzzle_mode and _puzzle_goal_completed \
			and not _puzzle_turn_limit_failed \
			and _victory_overlay == null \
			and _defeat_overlay == null \
			and (_is_upper_gem_turn \
				or _fuse_pipeline_active \
				or board.is_busy \
				or board.is_board_motion_running() \
				or _attack_worker_running \
				or not _attack_queue.is_empty() \
				or _enemy_board_effects_pending > 0):
		await get_tree().create_timer(0.05).timeout
	if not _puzzle_mode or not _puzzle_goal_completed:
		return
	if _puzzle_turn_limit_failed or _victory_overlay != null or _defeat_overlay != null:
		return
	await get_tree().create_timer(1.0).timeout
	if not _puzzle_mode or not _puzzle_goal_completed:
		return
	if _puzzle_turn_limit_failed or _victory_overlay != null or _defeat_overlay != null:
		return
	battle_manager.battle_won.emit()


## board.gems_refilled 保留給既有系統；Escape 進度改由位置石實際下降計算
func _on_gems_refilled(_count: int) -> void:
	pass


func _on_escape_marker_moved(rows_dropped: int) -> void:
	if not _escape_mode or _escape_won or _escape_failed:
		return
	if battle_manager != null and battle_manager.player_current_hp <= 0:
		_escape_failed = true
		return
	var gained: int = maxi(rows_dropped, 0) * ESCAPE_METERS_PER_ROW
	if gained <= 0:
		return
	_escape_distance_traveled = mini(_escape_distance_traveled + gained, _escape_distance_target)
	_escape_distance_remaining = maxi(_escape_distance_target - _escape_distance_traveled, 0)
	_update_escape_goal_wood_row()
	_update_escape_distance_label(true)
	# Stage 1-5 急難事件：走到 200m 後只觸發一次
	var triggered_plank_event: bool = false
	if current_stage != null and current_stage.stage_id == ESCAPE_PLANK_STAGE_ID \
			and not _plank_event_done and not _plank_event_pending \
			and _escape_distance_traveled >= _PLANK_EVENT_DISTANCE \
			and _escape_distance_remaining > 0:
		_plank_event_pending = true
		triggered_plank_event = true
	if _plank_event_pending and not _plank_event_done:
		_schedule_pending_plank_event_after_upper_flow()
	if _escape_distance_remaining <= 0:
		_escape_won = true
		battle_manager.battle_won.emit()
		return
	if not _plank_event_pending and not triggered_plank_event:
		_check_escape_scroll_after_marker_move()


func _schedule_pending_plank_event_after_upper_flow() -> void:
	if _escape_failed:
		return
	if _plank_event_deferred_check_running:
		return
	_plank_event_deferred_check_running = true
	call_deferred("_run_pending_plank_event_after_upper_flow")


func _run_pending_plank_event_after_upper_flow() -> void:
	await get_tree().process_frame
	while _plank_event_pending and not _plank_event_done \
			and not _escape_failed \
			and (_is_upper_gem_turn or board.is_busy or _attack_worker_running or board.is_board_motion_running()):
		await get_tree().create_timer(0.05).timeout
	if _plank_event_pending and not _plank_event_done and not _escape_failed:
		_plank_event_pending = false
		_plank_event_done = true
		await _run_plank_emergency_event()
	_plank_event_deferred_check_running = false


func _wait_for_board_motion_idle() -> void:
	while board != null and board.is_board_motion_running():
		await get_tree().create_timer(0.05).timeout
	await get_tree().process_frame


func _check_escape_scroll_after_marker_move() -> void:
	if not _escape_mode or _escape_won or _escape_failed:
		return
	if board == null:
		return
	if _escape_goal_wood_row >= 0:
		return
	var marker_pos: Vector2i = board.get_escape_marker_grid_pos()
	var trigger_row: int = maxi(board.rows - 3, 0)
	if marker_pos.y >= trigger_row:
		var pending_goal_wood_row: int = _get_escape_goal_wood_row_for_marker_y(ESCAPE_SCROLL_RESET_ROW)
		await board.force_escape_scroll_to_row(ESCAPE_SCROLL_RESET_ROW, false, pending_goal_wood_row)
		if pending_goal_wood_row >= 0:
			_escape_goal_wood_row = pending_goal_wood_row
		else:
			_update_escape_goal_wood_row()
		board.is_busy = false


# ── Stage 1-5 急難奇蹟事件：龍焰登場 ─────────────────────────

## 找出隊伍中第一位指定名稱的角色 index（找不到回傳 -1）
func _find_party_index_by_name(name: String) -> int:
	for i in party.size():
		if party[i] != null and party[i].character_name == name:
			return i
		if name == "Thor" and _is_thor_character(party[i]):
			return i
		if name == "Dragon" and _is_dragon_character(party[i]):
			return i
	return -1


func _is_thor_character(character: CharacterData) -> bool:
	if character == null:
		return false
	if character.character_name == "Thor" or character.character_name == "Husky":
		return true
	return character.resource_path.get_file().get_basename().to_lower() == "char_husky"


func _is_dragon_character(character: CharacterData) -> bool:
	if character == null:
		return false
	if character == CHAR_DRAGON:
		return true
	if character.active_skill_name == "Dragon Flame Domain":
		return true
	var base_name: String = character.resource_path.get_file().get_basename().to_lower()
	return base_name == "char_dragon"


## 木板從天而降：落成龍焰領域的 fireball shape（3x3 + 上下左右延伸）
func _drop_plank_pile_animation() -> void:
	var target_positions: Array[Vector2i] = _get_plank_accident_target_positions()
	var drop_dur: float = 0.45
	var stagger: float = 0.05
	var idx: int = 0
	for target_grid_pos: Vector2i in target_positions:
		var x: int = target_grid_pos.x
		var y: int = target_grid_pos.y
		# 先靜默釋放原本位置的 block（不論 plank/gem/upper），不發信號
		var existing: Block = board.grid[x][y]
		if existing != null and is_instance_valid(existing):
			board.grid[x][y] = null
		# 在天空位置生成新 PLANK，並以墜落動畫落到目標格
		var sky_pos: Vector2 = board.grid_to_world(Vector2i(x, -2 - idx % 4))
		var target_pos: Vector2 = board.grid_to_world(target_grid_pos)
		var pb: Block = preload("res://scenes/block.tscn").instantiate() as Block
		pb.position = sky_pos
		board.add_child(pb)
		pb.set_block_type(Block.Type.PLANK)
		pb.grid_pos = target_grid_pos
		pb.add_extra(Block.ExtraEffect.BURNING)
		pb.z_index = 4
		board.grid[x][y] = pb
		board.logic_grid[x][y] = -2  # LOGIC_PLANK
		# 以掉落動畫滑落到位
		var tw: Tween = pb.create_tween()
		tw.tween_property(pb, "position", target_pos, drop_dur) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(Callable(self, "_play_plank_impact_crush").bind(existing, board.to_global(target_pos)))
		idx += 1
		await get_tree().create_timer(stagger).timeout
	await get_tree().create_timer(drop_dur + 0.1).timeout
	# 同步邏輯網格（plank 狀態），並刷新融合提示
	board.resync_logic_from_visual()


func _get_plank_accident_target_positions() -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	if board == null:
		return positions
	var center := Vector2i(
		clampi(int(floor(float(board.columns) * 0.5)), 0, maxi(board.columns - 1, 0)),
		clampi(int(floor(float(board.rows) * 0.5)), 0, maxi(board.rows - 1, 0))
	)
	var offsets: Array[Vector2i] = [
		Vector2i(0, -2),
		Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
		Vector2i(-2, 0), Vector2i(-1, 0), Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0),
		Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
		Vector2i(0, 2),
	]
	for offset: Vector2i in offsets:
		var pos: Vector2i = center + offset
		if board._cell_accepts_block(pos):
			positions.append(pos)
	return positions


func _play_plank_impact_crush(crushed_block: Block, impact_pos: Vector2) -> void:
	_play_random_stone_impact_sfx()
	if board != null:
		board._spawn_plank_debris(impact_pos)
	if crushed_block == null or not is_instance_valid(crushed_block):
		return
	if crushed_block.is_breakable_structure():
		crushed_block.play_destroy_animation()
		if board != null:
			board._spawn_plank_debris(crushed_block.global_position)
	else:
		if board != null:
			board._play_gem_break_debris(crushed_block, crushed_block.is_upper_gem())
		else:
			crushed_block.play_destroy_animation()
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		if is_instance_valid(crushed_block):
			crushed_block.queue_free()
	, CONNECT_ONE_SHOT)

## 在指定卡片周圍建立「四條」全螢幕黯化條（保留卡片區域為亮）+ STOP 滑鼠
func _setup_dim_overlay(card_rect: Rect2) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var dim_color := Color(0, 0, 0, 0.6)
	# 上條
	var top := ColorRect.new()
	top.color = dim_color
	top.position = Vector2.ZERO
	top.size = Vector2(vp.x, max(card_rect.position.y, 0))
	top.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(top)
	# 下條
	var bot := ColorRect.new()
	bot.color = dim_color
	bot.position = Vector2(0, card_rect.position.y + card_rect.size.y)
	bot.size = Vector2(vp.x, max(vp.y - (card_rect.position.y + card_rect.size.y), 0))
	bot.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(bot)
	# 左條
	var lft := ColorRect.new()
	lft.color = dim_color
	lft.position = Vector2(0, card_rect.position.y)
	lft.size = Vector2(max(card_rect.position.x, 0), card_rect.size.y)
	lft.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(lft)
	# 右條
	var rgt := ColorRect.new()
	rgt.color = dim_color
	rgt.position = Vector2(card_rect.position.x + card_rect.size.x, card_rect.position.y)
	rgt.size = Vector2(max(vp.x - (card_rect.position.x + card_rect.size.x), 0), card_rect.size.y)
	rgt.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(rgt)

	# ── 卡片上方：循環擴散的脈衝圓圈（淡出）+ 上下浮動的手指 + 提示文字 ──
	var center: Vector2 = card_rect.position + card_rect.size * 0.5
	var radius: float = card_rect.size.length() * 0.55

	# 脈衝圓圈：以 Node2D + 自訂 _draw 實作，三層錯開時間
	var pulse_root := Node2D.new()
	pulse_root.position = center
	pulse_root.z_index = 5
	layer.add_child(pulse_root)
	for i in 3:
		var ring := _PulseRing.new()
		ring.base_radius = radius
		ring.delay = float(i) * 0.5
		pulse_root.add_child(ring)

	# 手指/游標圖示：在卡片正上方，上下浮動
	var hand_tex: Texture2D = load("res://assets/Hand3.png")
	if hand_tex != null:
		var hand := Sprite2D.new()
		hand.texture = hand_tex
		hand.scale = Vector2(1, 1)
		var hand_base_pos := Vector2(center.x, card_rect.position.y + card_rect.size.y * 0.52)
		hand.position = hand_base_pos
		hand.z_index = 6
		layer.add_child(hand)
		var ht: Tween = hand.create_tween().set_loops()
		ht.tween_property(hand, "position:y", hand_base_pos.y - 12, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		ht.tween_property(hand, "position:y", hand_base_pos.y + 8, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	# 提示文字（畫面正中央）
	var prompt := Label.new()
	prompt.text = Locale.tr_ui("TAP_HERO_TO_USE_SKILL")
	prompt.add_theme_font_size_override("font_size", 36)
	prompt.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	prompt.add_theme_constant_override("outline_size", 4)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.size = Vector2(vp.x, 32)
	prompt.position = Vector2(0, (vp.y - 32) * 0.5)
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.z_index = 6
	layer.add_child(prompt)
	var pt: Tween = prompt.create_tween().set_loops()
	pt.tween_property(prompt, "modulate:a", 0.5, 0.7).set_trans(Tween.TRANS_SINE)
	pt.tween_property(prompt, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE)

	return layer


## 卡片提示用的脈衝圓圈：基底半徑 + 啟動延遲，循環從 1.0× 擴散到 1.8× 並淡出
class _PulseRing extends Node2D:
	var base_radius: float = 60.0
	var delay: float = 0.0
	var _t: float = 0.0
	const _DURATION: float = 1.5

	func _ready() -> void:
		_t = -delay
		set_process(true)

	func _process(dt: float) -> void:
		_t += dt
		if _t >= _DURATION:
			_t = 0.0
		queue_redraw()

	func _draw() -> void:
		if _t < 0.0:
			return
		var k: float = _t / _DURATION
		var r: float = base_radius * (1.0 + k * 0.8)
		var a: float = clampf(1.0 - k, 0.0, 1.0) * 0.7
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, Color(1.0, 0.85, 0.2, a), 4.0, true)


## 在卡片上播放「邊界脈動」動畫（金色脈衝邊框）；回傳建立的 Panel 節點，事件結束時 free
func _start_card_pulse(card: Control) -> Panel:
	var pulse := Panel.new()
	pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pulse.position = Vector2(-6, -6)
	pulse.size = card.size + Vector2(12, 12)
	# 自製脈衝邊框（透明背景 + 金色邊）
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0)
	sb.border_color = Color(1.0, 0.85, 0.2, 1.0)
	sb.border_width_left = 4
	sb.border_width_right = 4
	sb.border_width_top = 4
	sb.border_width_bottom = 4
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	pulse.add_theme_stylebox_override("panel", sb)
	card.add_child(pulse)
	# 循環縮放與透明度脈動
	var tw: Tween = pulse.create_tween().set_loops()
	tw.tween_property(pulse, "modulate:a", 0.3, 0.5).set_trans(Tween.TRANS_SINE)
	tw.tween_property(pulse, "modulate:a", 1.0, 0.5).set_trans(Tween.TRANS_SINE)
	pulse.set_meta("_pulse_tween", tw)
	return pulse


## 等待指定 char_index 的主動技能完整執行完成
func _wait_for_active_skill_finish(char_index: int) -> void:
	while true:
		var idx: int = await active_skill_finished
		if idx == char_index:
			return


func _wait_for_stage13_event() -> void:
	while _stage13_event_running:
		await get_tree().process_frame


func _run_stage13_turn1_dialog() -> void:
	if _stage13_turn1_done:
		return
	_stage13_turn1_done = true
	_stage13_event_running = true
	var dialog: _BattleDialog = _ensure_battle_dialog()
	dialog.visible = true
	dialog.show_lines(_Stage1_3Owen.make_turn1_dialog())
	await dialog.all_lines_finished
	dialog.visible = false
	_stage13_event_running = false


func _apply_player_damage_with_stage13_guard(amount: int) -> void:
	var shield_absorb: int = mini(maxi(amount, 0), maxi(battle_manager.player_shield, 0))
	var hp_overflow_damage: int = maxi(0, amount - shield_absorb)
	if _is_stage13_story_battle() and not _stage13_rescue_done \
			and hp_overflow_damage > 0 \
			and battle_manager.player_current_hp - hp_overflow_damage <= 0:
		if shield_absorb > 0:
			battle_manager.player_shield -= shield_absorb
			battle_manager.player_shield_damaged_this_turn = true
			battle_manager.player_shield_changed.emit(battle_manager.player_shield, battle_manager.player_max_hp, "break" if battle_manager.player_shield <= 0 else "damage")
		battle_manager.player_current_hp = 1
		battle_manager.player_hp_changed.emit(battle_manager.player_current_hp, battle_manager.player_max_hp)
		if not _stage13_event_running:
			_run_stage13_rescue_event()
		return
	battle_manager.apply_player_damage(amount)


func _run_stage13_rescue_event() -> void:
	if _stage13_rescue_done:
		return
	_stage13_rescue_done = true
	_stage13_event_running = true
	board.is_busy = true
	board.set_input_queue_locked(true)

	var dialog: _BattleDialog = _ensure_battle_dialog()
	dialog.visible = true
	dialog.show_lines(_Stage1_3Owen.make_husky_near_death_dialog())
	await dialog.all_lines_finished
	dialog.visible = false

	await add_temporary_guest_characters_staggered([
		{
			"guest": CHAR_DRAGON,
			"options": {
				"slot_index": 1,
				"visual_scale": 1.35,
				"reveal_duration_scale": 1.35,
				"post_join_pause": 0.0,
				"include_in_result": true,
			},
		},
		{
			"guest": CHAR_PANDA,
			"options": {
				"slot_index": 2,
				"visual_scale": 1.35,
				"reveal_duration_scale": 1.35,
				"post_join_pause": 0.0,
				"include_in_result": true,
			},
		},
		{
			"guest": CHAR_SHARK,
			"options": {
				"slot_index": 3,
				"visual_scale": 1.35,
				"reveal_duration_scale": 1.35,
				"post_join_pause": 0.0,
				"include_in_result": true,
			},
		},
	], 0.22)

	dialog.visible = true
	dialog.show_lines(_Stage1_3Owen.make_rescue_dialog())
	await dialog.all_lines_finished
	dialog.visible = false

	_stage13_join_turn = battle_manager.turn
	board.set_input_queue_locked(false)
	board.is_busy = false
	_stage13_event_running = false


func _should_run_stage13_light_hint() -> bool:
	return _is_stage13_story_battle() \
		and _stage13_rescue_done \
		and not _stage13_light_hint_done \
		and _stage13_join_turn >= 0 \
		and battle_manager.turn - _stage13_join_turn >= 2


func _run_stage13_light_hint_event() -> void:
	if _stage13_light_hint_done:
		return
	_stage13_light_hint_done = true
	_stage13_event_running = true
	board.is_busy = true
	board.set_input_queue_locked(true)

	var dialog: _BattleDialog = _ensure_battle_dialog()
	dialog.visible = true
	dialog.show_lines(_Stage1_3Owen.make_light_hint_dialog())
	await dialog.all_lines_finished
	dialog.visible = false

	var husky_idx: int = _find_party_index_by_name("Thor")
	if husky_idx < 0:
		board.set_input_queue_locked(false)
		board.is_busy = false
		_stage13_event_running = false
		return
	_temporary_active_unlocks[party[husky_idx]] = true
	battle_manager.skill_cooldowns[husky_idx] = 0
	_update_skill_ui()

	var husky_card: Control = character_panel.get_card(husky_idx)
	if husky_card == null:
		board.set_input_queue_locked(false)
		board.is_busy = false
		_stage13_event_running = false
		return
	var dim_layer: CanvasLayer = _setup_dim_overlay(husky_card.get_global_rect())
	var pulse: Panel = _start_card_pulse(husky_card)

	board.set_input_queue_locked(false)
	board.is_busy = false
	while true:
		var activated_idx: int = await character_panel.active_skill_activated
		if activated_idx == husky_idx:
			break

	if is_instance_valid(pulse):
		pulse.queue_free()
	if is_instance_valid(dim_layer):
		dim_layer.queue_free()

	await _wait_for_active_skill_finish(husky_idx)
	_stage13_husky_active_used = true
	_enable_stage13_owen_hp_floor()
	_stage13_event_running = false


func _is_stage13_owen(enemy: Enemy) -> bool:
	return enemy != null and is_instance_valid(enemy) and enemy.data != null and enemy.data.enemy_name == "First Owen"


func _should_run_stage14_escape_intro() -> bool:
	return not _stage14_escape_intro_done \
		and current_stage != null \
		and current_stage.stage_id == ESCAPE_PLANK_STAGE_ID \
		and current_stage.mode == StageData.Mode.ESCAPE


func _run_stage14_escape_intro() -> void:
	if not _should_run_stage14_escape_intro():
		return
	_stage14_escape_intro_done = true
	board.is_busy = true
	board.set_input_queue_locked(true)

	var dialog: _BattleDialog = _ensure_battle_dialog()
	dialog.visible = true
	dialog.show_lines([
		_make_stage14_escape_line("panda", "normal",
			"我們被困住了！\n聖所... 一片火海！",
			"We're trapped! A sea of fire!"),
		_make_stage14_escape_line("shark", "normal",
			"不要慌！一邊消除寶石一邊前進！",
			"Don't panic! Keep moving while clearing the gems."),
	])
	await dialog.all_lines_finished
	dialog.visible = false
	await _show_stage14_escape_rules_canvas()


func _make_stage14_escape_line(char_id: String, emotion: String, zh: String, en: String) -> _DialogLine:
	var line := _DialogLine.new()
	line.character_id = char_id
	line.emotion = emotion
	line.position = "left"
	line.action = "none"
	line.text_zh = zh
	line.text_en = en
	line.shake = false
	return line


func _show_stage14_escape_rules_canvas() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 70
	$UILayer.add_child(layer)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0, 0, 0.66)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(dim)

	var viewport_size: Vector2 = ViewportUtils.get_size()
	var panel_w: float = minf(680.0, viewport_size.x - 28.0)
	var panel_h: float = minf(430.0, viewport_size.y - 42.0)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -panel_w * 0.5
	panel.offset_right = panel_w * 0.5
	panel.offset_top = -panel_h * 0.5
	panel.offset_bottom = panel_h * 0.5
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.16, 0.97)
	style.border_color = Color(0.85, 0.72, 0.30, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	root.add_child(panel)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 18)
	panel.add_child(content)

	var top_row := HBoxContainer.new()
	top_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_row.add_theme_constant_override("separation", 18)
	content.add_child(top_row)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 1.05
	left.add_theme_constant_override("separation", 12)
	top_row.add_child(left)

	var title := _stage14_canvas_label("", 36, Color(1.0, 0.92, 0.30))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	left.add_child(title)

	var info := _stage14_canvas_label("", 24, Color(0.90, 0.94, 1.0))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(info)

	var image_side: float = maxf(160.0, minf(panel_h - 112.0, panel_w * 0.44))
	var image_panel := PanelContainer.new()
	image_panel.custom_minimum_size = Vector2(image_side, image_side)
	image_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	image_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var image_style := StyleBoxFlat.new()
	image_style.bg_color = Color(0.03, 0.04, 0.07, 0.92)
	image_style.border_color = Color(0.25, 0.42, 0.62, 0.82)
	image_style.set_border_width_all(1)
	image_style.set_corner_radius_all(8)
	image_style.set_content_margin_all(8)
	image_panel.add_theme_stylebox_override("panel", image_style)
	top_row.add_child(image_panel)

	var image := TextureRect.new()
	image.texture = CHAR_DRAGON.portrait_texture
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_panel.add_child(image)

	var button_row := Control.new()
	button_row.custom_minimum_size = Vector2(0, 54)
	button_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(button_row)

	var bottom_w: float = panel_w - 36.0
	var button_y := 14.0
	var button_w := 118.0
	var button_h := 38.0
	var prev_btn := Button.new()
	prev_btn.text = "Back"
	prev_btn.custom_minimum_size = Vector2(button_w, button_h)
	prev_btn.position = Vector2(bottom_w * 0.5 - button_w - 10.0, button_y)
	prev_btn.size = Vector2(button_w, button_h)
	button_row.add_child(prev_btn)
	var next_btn := Button.new()
	next_btn.text = "Next"
	next_btn.custom_minimum_size = Vector2(button_w, button_h)
	next_btn.position = Vector2(bottom_w * 0.5 + 10.0, button_y)
	next_btn.size = Vector2(button_w, button_h)
	button_row.add_child(next_btn)
	var skip_btn := Button.new()
	skip_btn.text = "Skip"
	skip_btn.custom_minimum_size = Vector2(86, button_h)
	skip_btn.position = Vector2(bottom_w - 86.0, button_y)
	skip_btn.size = Vector2(86, button_h)
	button_row.add_child(skip_btn)

	var dot_row := HBoxContainer.new()
	dot_row.add_theme_constant_override("separation", 8)
	dot_row.position = Vector2(bottom_w * 0.5 - 28.0, 1.0)
	dot_row.custom_minimum_size = Vector2(56, 10)
	button_row.add_child(dot_row)

	var pages: Array[Dictionary] = [
		{
			"title": "逃脫模式",
			"info": "消除或合成角色下方的寶石, \n向下逃跑吧!!",
			"image": "res://assets/escape_tutor_1.png",
		},
		{
			"title": "燒著啦!",
			"info": "燃燒寶石每回合結束時會消耗你的生命，\n消除或融合它們！",
			"image": "res://assets/escape_tutor_2.png",
		},
		{
			"title": "障礙方塊",
			"info": "障礙方塊不能透過普通的點撃消除！\n爆破相鄰的寶石，合成寶石爆風甚至技能也對它有效。",
			"image": "res://assets/escape_tutor_3.png",
		},
	]
	var dots: Array[Panel] = []
	for i in pages.size():
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(10, 10)
		dot.size = Vector2(10, 10)
		dot_row.add_child(dot)
		dots.append(dot)
	var page_state := {"index": 0}
	var closed := {"done": false}
	var update_dots := func(active_index: int) -> void:
		for i in dots.size():
			var dot_style := StyleBoxFlat.new()
			dot_style.bg_color = Color(1.0, 0.86, 0.20, 1.0) if i == active_index else Color(0.05, 0.055, 0.075, 1.0)
			dot_style.border_color = Color(0.0, 0.0, 0.0, 0.78)
			dot_style.set_border_width_all(1)
			dot_style.set_corner_radius_all(5)
			dots[i].add_theme_stylebox_override("panel", dot_style)
	var render_page := func() -> void:
		var page_index: int = int(page_state.index)
		var page: Dictionary = pages[page_index]
		title.text = str(page.get("title", ""))
		info.text = str(page.get("info", ""))
		var image_path: String = str(page.get("image", ""))
		image.texture = load(image_path) as Texture2D if ResourceLoader.exists(image_path) else CHAR_DRAGON.portrait_texture
		prev_btn.visible = page_index > 0
		next_btn.text = "OK" if page_index >= pages.size() - 1 else "Next"
		update_dots.call(page_index)
	render_page.call()

	prev_btn.pressed.connect(func() -> void:
		page_state.index = maxi(int(page_state.index) - 1, 0)
		render_page.call()
	)
	next_btn.pressed.connect(func() -> void:
		if int(page_state.index) < pages.size() - 1:
			page_state.index = int(page_state.index) + 1
			render_page.call()
		else:
			closed.done = true
	)
	skip_btn.pressed.connect(func() -> void:
		closed.done = true
	)
	while not bool(closed.done):
		await get_tree().process_frame
	layer.queue_free()


func _stage14_canvas_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _enable_stage13_owen_hp_floor() -> void:
	if not _is_stage13_story_battle() or _stage13_victory_triggered:
		return
	for enemy: Enemy in battle_manager.active_enemies:
		if not _is_stage13_owen(enemy):
			continue
		enemy.set_damage_hp_floor(1)
		var floor_callable: Callable = _on_stage13_owen_hp_floor_triggered
		if not enemy.hp_floor_triggered.is_connected(floor_callable):
			enemy.hp_floor_triggered.connect(floor_callable, CONNECT_ONE_SHOT)


func _on_stage13_owen_hp_floor_triggered(enemy: Enemy) -> void:
	if not _is_stage13_owen(enemy) or _stage13_victory_triggered:
		return
	_stage13_owen_light_hit_pending = true
	_schedule_stage13_floor_finale()


func _schedule_stage13_floor_finale() -> void:
	if _stage13_floor_finale_scheduled or _stage13_victory_triggered:
		return
	_stage13_floor_finale_scheduled = true
	_run_stage13_floor_finale_deferred()


func _run_stage13_floor_finale_deferred() -> void:
	await get_tree().create_timer(0.75).timeout
	_stage13_floor_finale_scheduled = false
	if _stage13_victory_triggered or not _stage13_owen_light_hit_pending:
		return
	_stage13_owen_light_hit_pending = false
	await _run_stage13_finale_and_win()


func _should_stage13_floor_owen_light_hit(enemy: Enemy, gem_type: Block.Type) -> bool:
	if not _is_stage13_story_battle() or not _stage13_husky_active_used or _stage13_victory_triggered:
		return false
	if int(gem_type) != int(Block.Type.LIGHT):
		return false
	return _is_stage13_owen(enemy)


func _apply_enemy_damage_with_stage13_floor(enemy: Enemy, amount: int, gem_type: Block.Type) -> int:
	if _should_stage13_floor_owen_light_hit(enemy, gem_type):
		_stage13_owen_light_hit_pending = true
		return enemy.take_damage_with_hp_floor(amount, 1)
	if enemy == null or not is_instance_valid(enemy):
		return 0
	return enemy.take_damage(amount)


func _run_stage13_finale_and_win(emit_win_signal: bool = true) -> void:
	if _stage13_victory_triggered:
		return
	_stage13_victory_triggered = true
	_stage13_event_running = true
	board.is_busy = true
	board.set_input_queue_locked(true)

	var dialog: _BattleDialog = _ensure_battle_dialog()
	dialog.visible = true
	dialog.show_lines(_Stage1_3Owen.make_finale_dialog())
	await dialog.all_lines_finished
	dialog.visible = false

	_stage13_event_running = false
	if emit_win_signal:
		battle_manager.battle_won.emit()
	else:
		await _complete_battle_won()


## 主事件：木板大量降臨 → 對話 → 黯化 → 龍焰使用 → 收尾對話
func _run_plank_emergency_event() -> void:
	if _escape_failed:
		return
	board.is_busy = true
	board.set_input_queue_locked(true)
	await _wait_for_board_motion_idle()
	board.snap_visual_blocks_to_grid()

	# 1) Escape 事件先把位置石拉回上方，再讓木板從天而降
	if _escape_mode:
		if _escape_failed:
			board.set_input_queue_locked(false)
			board.is_busy = false
			return
		await board.force_escape_scroll_to_row(ESCAPE_SCROLL_RESET_ROW, true)
		await _wait_for_board_motion_idle()
		board.snap_visual_blocks_to_grid()
		_update_escape_goal_wood_row()

	await _drop_plank_pile_animation()

	# 必要時懶建戰鬥對話面板（非教學關卡預設為 null）
	if _battle_dialog == null:
		_battle_dialog = _BattleDialog.new()
		_battle_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
		$UILayer.add_child(_battle_dialog)

	# 2) 恐慌對話
	if _battle_dialog != null:
		_battle_dialog.visible = true
		_battle_dialog.show_lines(_Stage1_4Emergency.make_pre_dialog())
		await _battle_dialog.all_lines_finished
		_battle_dialog.visible = false

	# 3) 找到 Dragon
	var dragon_idx: int = _find_party_index_by_name("Dragon")
	if dragon_idx < 0:
		# 隊伍中無龍 → 無法執行此事件（仍標記為已完成）
		board.set_input_queue_locked(false)
		board.is_busy = false
		return

	# 4) 重置 Dragon 主動技能 CD，讓他可立即發動
	_temporary_active_unlocks[party[dragon_idx]] = true
	battle_manager.skill_cooldowns[dragon_idx] = 0
	_update_skill_ui()

	# 5) 黯化全螢幕（保留 Dragon 卡片區域）+ 卡片邊界脈動
	var dragon_card: Control = character_panel.get_card(dragon_idx)
	if dragon_card == null:
		board.set_input_queue_locked(false)
		board.is_busy = false
		return
	var card_rect: Rect2 = dragon_card.get_global_rect()
	var dim_layer: CanvasLayer = _setup_dim_overlay(card_rect)
	var pulse: Panel = _start_card_pulse(dragon_card)

	# 6) 解除 board.is_busy 讓 Dragon 主動技能可被觸發（黯化覆蓋層阻擋了棋盤輸入）
	board.set_input_queue_locked(false)
	board.is_busy = false

	# 7) 等待 Dragon 卡片被點擊（active_skill_activated 信號），但不等整個技能流程
	while true:
		var activated_idx: int = await character_panel.active_skill_activated
		if activated_idx == dragon_idx:
			break

	# 8) 立刻移除黯化與脈動，讓玩家可在棋盤上進行範圍選擇
	if is_instance_valid(pulse):
		pulse.queue_free()
	if is_instance_valid(dim_layer):
		dim_layer.queue_free()

	# 9) 等待主動技能完整執行完成
	await _wait_for_active_skill_finish(dragon_idx)

	# 10) 收尾對話
	if _battle_dialog != null:
		_battle_dialog.visible = true
		_battle_dialog.show_lines(_Stage1_4Emergency.make_post_dialog())
		await _battle_dialog.all_lines_finished
		_battle_dialog.visible = false


## 燃燒額外效果結算：每顆 BURNING 寶石扣玩家最大 HP 的 1%
func _apply_burning_tick() -> void:
	if board == null:
		return
	var burn_positions: Array[Vector2i] = board.get_burning_gem_positions()
	var n: int = burn_positions.size()
	if n <= 0:
		return
	var per_gem: int = maxi(int(floor(battle_manager.player_max_hp * 0.01)), 1)
	var total: int = per_gem * n

	# ── 視覺演出階段 ──────────────────────────────────────────
	# 1) 暗化棋盤，只留燃燒寶石
	board.darken_except(burn_positions, 0.2)
	await get_tree().create_timer(0.18).timeout

	# 2) 播放打擊音效
	var strike_stream: AudioStream = load("res://assets/se/skef_atk6.mp3")
	_play_sfx(strike_stream, 1.2)

	# 3) 每顆燃燒寶石播放彈跳 pop 動畫
	for p in burn_positions:
		var b: Block = board.grid[p.x][p.y]
		if b == null or not is_instance_valid(b):
			continue
		var tw: Tween = b.create_tween()
		tw.tween_property(b, "scale", Vector2(1.35, 1.35), 0.08).set_ease(Tween.EASE_OUT)
		tw.tween_property(b, "scale", Vector2(1.0, 1.0), 0.12).set_ease(Tween.EASE_IN)

	await get_tree().create_timer(0.18).timeout

	# 4) 扣血
	battle_manager.apply_player_damage(total)
	_add_log_entry("燃燒：%d 顆 %s 寶石，扣 %d HP" % [n, _gem_bbcode(Block.Type.RED), total], Block.Type.RED, null)

	# 5) 還原棋盤亮度
	await get_tree().create_timer(0.08).timeout
	board.brighten_all_gems(0.2)


func _ensure_battle_dialog() -> _BattleDialog:
	if _battle_dialog == null:
		_battle_dialog = _BattleDialog.new()
		_battle_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
		$UILayer.add_child(_battle_dialog)
	return _battle_dialog


## 戰鬥勝利
func _on_battle_won() -> void:
	if _is_stage13_story_battle() and _stage13_event_running and _stage13_victory_triggered:
		return
	if _is_stage13_story_battle() and _stage13_husky_active_used and not _stage13_victory_triggered:
		await _run_stage13_finale_and_win(false)
		return
	await _complete_battle_won()


func _complete_battle_won() -> void:
	board.is_busy = true
	await _wait_for_loot_animations_finished()
	# ── 戰利品 UI 播完後 → 交叉淡入勝利音樂 ──
	if current_stage == null or current_stage.mode != StageData.Mode.PUZZLE:
		GameState.crossfade_bgm(load("res://assets/music/fez_winfare.mp3"), false, 0.5, "winfare")
	_bgm_player = GameState.bgm_player
	# ── 教學：Boss 擊敗後收尾對話（勝利橫幅前）──
	if current_stage.is_tutorial and _battle_dialog != null:
		_battle_dialog.show_lines(_Stage1Tutorial.make_victory_dialog())
		await _battle_dialog.all_lines_finished
		_battle_dialog.visible = false

	GameState.last_battle_reward_characters.clear()
	_apply_stage_one_time_rewards()

	# 將本場戰利品存入 GameState
	for type: ItemDefs.Type in _battle_loot:
		GameState.add_loot(type, _battle_loot[type])

	# 標記關卡通關（用於世界地圖解鎖）
	if current_stage != null:
		GameState.mark_stage_cleared(current_stage.stage_id)
		# 關卡未設定 fixed party 時，記錄本場出戰隊伍為「下次預設隊伍」
		if current_stage.set_party.is_empty():
			GameState.set_last_used_party(_get_battle_result_party())

	# 將結算資料寫入 GameState（結算場景讀取）
	GameState.last_battle_loot = _battle_loot.duplicate()
	GameState.last_battle_party = _get_battle_result_party()
	GameState.last_battle_exp = _battle_exp

	_show_victory_overlay()


func _apply_stage_one_time_rewards() -> void:
	if current_stage == null:
		return
	var stage_id: String = current_stage.stage_id.strip_edges()
	if stage_id.is_empty() or GameState.is_stage_reward_claimed(stage_id):
		return
	var has_item_reward: bool = current_stage.one_time_reward_item_amount > 0
	var has_character_reward: bool = current_stage.one_time_reward_character != null
	if not has_item_reward and not has_character_reward:
		return

	if has_item_reward:
		var reward_type: ItemDefs.Type = current_stage.one_time_reward_item_type
		var current_amount: int = int(_battle_loot.get(reward_type, 0))
		_battle_loot[reward_type] = current_amount + current_stage.one_time_reward_item_amount

	if has_character_reward:
		var reward_character: CharacterData = current_stage.one_time_reward_character
		if GameState.grant_character(reward_character, true):
			GameState.last_battle_reward_characters.append(reward_character)

	GameState.mark_stage_reward_claimed(stage_id, false)


## 顯示勝利覆蓋層（5 秒後或點擊後跳轉結算場景）
func _show_victory_overlay() -> void:
	if _victory_overlay != null:
		return
	var font: Font = load("res://assets/fonts/game_ui_font.tres")
	var ui_layer: CanvasLayer = $UILayer

	_victory_overlay = Control.new()
	_victory_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_victory_overlay.z_index = 200
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
	var victory_text_key: String = "COMPLETE" if current_stage != null and current_stage.mode == StageData.Mode.PUZZLE else "VICTORY"
	title.text = Locale.tr_ui(victory_text_key)
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


## 重新開始戰鬥（透過淡黑→重載場景→淡入，徹底切回關卡 BGM）
func _on_restart_pressed() -> void:
	GameState.fade_out_bgm(0.3)
	GameState.fade_to_scene("res://scenes/main.tscn", 0.4)


## 返回地圖
func _on_return_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/map.tscn")


# ── Boss HP 條 + Kill-All 偵錯按鈕 ─────────────────────────────────

const BOSS_BAR_HEIGHT: float = 56.0

var _boss_bar: Control = null
var _boss_bar_fill: TextureRect = null
var _boss_bar_bg: ColorRect = null
var _boss_bar_label: Label = null
var _boss_bar_enemy: Enemy = null
var _boss_bar_reveal_tween: Tween = null
var _kill_all_btn: Button = null


## 建立位於螢幕頂端的 Boss HP 條（預設隱藏）
func _setup_boss_bar() -> void:
	var ui_layer: CanvasLayer = $UILayer
	_boss_bar = Control.new()
	_boss_bar.name = "BossBar"
	_boss_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_boss_bar.offset_left = 16.0
	_boss_bar.offset_right = -16.0
	_boss_bar.offset_top = 4.0
	_boss_bar.offset_bottom = 4.0 + BOSS_BAR_HEIGHT
	_boss_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.visible = false
	ui_layer.add_child(_boss_bar)

	# 血條容器（占滿整條，不再預留元素圖示位置）
	var bar := Control.new()
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar.add_child(bar)

	_boss_bar_bg = ColorRect.new()
	_boss_bar_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_boss_bar_bg.color = Color(0, 0, 0, 1)
	_boss_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_boss_bar_bg)

	_boss_bar_fill = TextureRect.new()
	_boss_bar_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_boss_bar_fill.offset_left = 3.0
	_boss_bar_fill.offset_top = 3.0
	_boss_bar_fill.offset_right = -3.0
	_boss_bar_fill.offset_bottom = -3.0
	_boss_bar_fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_boss_bar_fill.stretch_mode = TextureRect.STRETCH_SCALE
	_boss_bar_fill.pivot_offset = Vector2.ZERO
	_boss_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_boss_bar_fill)

	var font: Font = load("res://assets/fonts/game_ui_font.tres")

	_boss_bar_label = Label.new()
	_boss_bar_label.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_boss_bar_label.offset_left = -160.0
	_boss_bar_label.offset_right = -8.0
	_boss_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_boss_bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_boss_bar_label.add_theme_font_override("font", font)
	_boss_bar_label.add_theme_font_size_override("font_size", 18)
	_boss_bar_label.add_theme_color_override("font_color", Color.WHITE)
	_boss_bar_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_boss_bar_label.add_theme_constant_override("outline_size", 4)
	_boss_bar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_boss_bar_label)


## 建立「Exit / Restart / Kill All / Combo Test / Skill Reset」按鈕列。
func _setup_kill_all_button() -> void:
	var ui_layer: CanvasLayer = $UILayer
	var exit_btn: Node = ui_layer.get_node_or_null("ReturnButton")
	var restart_btn: Node = ui_layer.get_node_or_null("RestartButton")

	# 偵錯按鈕同寬，間距 6px，整組以 anchor 0.5 置中。
	var top_off: float = -96.0
	var bot_off: float = -56.0
	if restart_btn is Button:
		var rb: Button = restart_btn as Button
		top_off = rb.offset_top
		bot_off = rb.offset_bottom
		rb.offset_left = -217.0
		rb.offset_right = -113.0
	if exit_btn is Button:
		var eb: Button = exit_btn as Button
		eb.text = Locale.tr_ui("EXIT")
		eb.visible = true
		eb.anchor_left = 0.5
		eb.anchor_top = 1.0
		eb.anchor_right = 0.5
		eb.anchor_bottom = 1.0
		eb.offset_left = -327.0
		eb.offset_right = -223.0
		eb.offset_top = top_off
		eb.offset_bottom = bot_off

	_kill_all_btn = Button.new()
	_kill_all_btn.name = "KillAllButton"
	_kill_all_btn.text = "Kill All"
	_kill_all_btn.modulate = Color(1.0, 0.6, 0.6)
	_kill_all_btn.anchor_left = 0.5
	_kill_all_btn.anchor_top = 1.0
	_kill_all_btn.anchor_right = 0.5
	_kill_all_btn.anchor_bottom = 1.0
	_kill_all_btn.offset_left = -107.0
	_kill_all_btn.offset_right = -3.0
	_kill_all_btn.offset_top = top_off
	_kill_all_btn.offset_bottom = bot_off
	_kill_all_btn.pressed.connect(_on_kill_all_pressed)
	ui_layer.add_child(_kill_all_btn)

	var combo_btn := Button.new()
	combo_btn.name = "ComboTestButton"
	combo_btn.text = "Combo Test"
	combo_btn.modulate = Color(1.0, 0.85, 0.4)
	combo_btn.anchor_left = 0.5
	combo_btn.anchor_top = 1.0
	combo_btn.anchor_right = 0.5
	combo_btn.anchor_bottom = 1.0
	combo_btn.offset_left = 3.0
	combo_btn.offset_right = 107.0
	combo_btn.offset_top = top_off
	combo_btn.offset_bottom = bot_off
	combo_btn.pressed.connect(_on_combo_test_pressed.bind(combo_btn))
	ui_layer.add_child(combo_btn)

	var test_board_btn := Button.new()
	test_board_btn.name = "TestBoardButton"
	test_board_btn.text = "Test Board"
	test_board_btn.modulate = Color(0.65, 0.9, 1.0)
	test_board_btn.anchor_left = 0.5
	test_board_btn.anchor_top = 1.0
	test_board_btn.anchor_right = 0.5
	test_board_btn.anchor_bottom = 1.0
	test_board_btn.offset_left = 113.0
	test_board_btn.offset_right = 217.0
	test_board_btn.offset_top = top_off
	test_board_btn.offset_bottom = bot_off
	test_board_btn.pressed.connect(_on_test_board_pressed)
	ui_layer.add_child(test_board_btn)

	var skill_reset_btn := Button.new()
	skill_reset_btn.name = "SkillResetButton"
	skill_reset_btn.text = "Skill Reset"
	skill_reset_btn.modulate = Color(0.5, 1.0, 0.8)
	skill_reset_btn.anchor_left = 0.5
	skill_reset_btn.anchor_top = 1.0
	skill_reset_btn.anchor_right = 0.5
	skill_reset_btn.anchor_bottom = 1.0
	skill_reset_btn.offset_left = 223.0
	skill_reset_btn.offset_right = 327.0
	skill_reset_btn.offset_top = top_off
	skill_reset_btn.offset_bottom = bot_off
	skill_reset_btn.pressed.connect(_on_skill_reset_pressed)
	ui_layer.add_child(skill_reset_btn)

	# 連鎖間隔調整滑桿（偵錯）— 0.0 ~ 0.6 秒，置於按鈕列正下方
	var chain_box := VBoxContainer.new()
	chain_box.name = "ChainIntervalDebug"
	chain_box.anchor_left = 0.5
	chain_box.anchor_top = 1.0
	chain_box.anchor_right = 0.5
	chain_box.anchor_bottom = 1.0
	chain_box.offset_left = -200.0
	chain_box.offset_right = 200.0
	chain_box.offset_top = bot_off + 4.0   # 緊接按鈕列下方
	chain_box.offset_bottom = bot_off + 44.0
	chain_box.add_theme_constant_override("separation", 2)
	ui_layer.add_child(chain_box)

	var chain_lbl := Label.new()
	chain_lbl.name = "ChainIntervalLabel"
	chain_lbl.text = "Chain Interval: %.2fs" % board.chain_blast_interval
	chain_lbl.add_theme_font_size_override("font_size", 12)
	chain_lbl.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	chain_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chain_box.add_child(chain_lbl)

	var chain_slider := HSlider.new()
	chain_slider.min_value = 0.0
	chain_slider.max_value = 0.6
	chain_slider.step = 0.01
	chain_slider.value = board.chain_blast_interval
	chain_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chain_slider.custom_minimum_size = Vector2(0, 22)
	chain_slider.value_changed.connect(func(v: float) -> void:
		board.chain_blast_interval = v
		chain_lbl.text = "Chain Interval: %.2fs" % v
	)
	chain_box.add_child(chain_slider)


## 一波敵人生成完畢 — 評估是否顯示 Boss 條
func _on_round_spawned(round_idx: int) -> void:
	for enemy: Enemy in battle_manager.active_enemies:
		if is_instance_valid(enemy) and not enemy.died.is_connected(_on_auto_enemy_died):
			enemy.died.connect(_on_auto_enemy_died)
	var boss: Enemy = battle_manager.get_main_boss_for_round(round_idx)
	_bind_boss_bar(boss)


func _on_auto_enemy_died(enemy: Enemy) -> void:
	if not is_instance_valid(enemy):
		return
	var owner_id: int = enemy.get_instance_id()
	_auto_enemy_active_cds.erase(owner_id)
	if board != null:
		board.destroy_enemy_upper_gems_for_owner(owner_id)


## 將 Boss 條綁定到指定敵人；傳 null 則隱藏
func _bind_boss_bar(boss: Enemy) -> void:
	if _boss_bar == null:
		return
	# 解除舊綁定
	if _boss_bar_enemy != null and is_instance_valid(_boss_bar_enemy):
		if _boss_bar_enemy.hp_changed.is_connected(_on_boss_hp_changed):
			_boss_bar_enemy.hp_changed.disconnect(_on_boss_hp_changed)
		if _boss_bar_enemy.died.is_connected(_on_boss_died):
			_boss_bar_enemy.died.disconnect(_on_boss_died)
		if _boss_bar_enemy.current_hp > 0:
			_boss_bar_enemy.set_main_boss_mode(false)
	_boss_bar_enemy = boss
	if boss == null or not is_instance_valid(boss) or boss.data == null:
		_boss_bar.visible = false
		return

	# 套用元素色垂直漸層（上：元素色，下：較暗），背景依舊為黑
	var elem: int = boss.data.element
	var elem_color: Color = Block.COLORS.get(elem, Color(0.9, 0.15, 0.15))
	_boss_bar_fill.texture = Enemy.make_hp_gradient(elem_color)
	_boss_bar_bg.color = Color(0, 0, 0, 1)
	_boss_bar_fill.scale.x = 1.0
	_boss_bar_label.text = "%d / %d" % [boss.current_hp, boss.max_hp]
	# 預設隗入狀態：隱藏並安置在頂部之上，由 _reveal_boss_bar() 負責漸入
	_boss_bar.modulate.a = 0.0
	_boss_bar.offset_top = 4.0 - BOSS_BAR_HEIGHT - 16.0
	_boss_bar.offset_bottom = _boss_bar.offset_top + BOSS_BAR_HEIGHT
	_boss_bar.visible = true
	boss.set_main_boss_mode(true)
	var delay_boss_visual: bool = battle_manager != null and (battle_manager.is_round_transitioning or (battle_manager.current_round == 0 and not _initial_boss_intro_shown))
	boss.modulate.a = 0.0 if delay_boss_visual else 1.0

	boss.hp_changed.connect(_on_boss_hp_changed)
	boss.died.connect(_on_boss_died)


## 將 Boss 條從頂部漸入到定位（需在 _bind_boss_bar() 後呼叫）
func _reveal_boss_bar() -> void:
	if _boss_bar == null or not _boss_bar.visible or _boss_bar_enemy == null:
		return
	if _boss_bar_reveal_tween != null and _boss_bar_reveal_tween.is_valid():
		_boss_bar_reveal_tween.kill()
	_boss_bar_reveal_tween = create_tween().set_parallel(true)
	_boss_bar_reveal_tween.tween_property(_boss_bar, "modulate:a", 1.0, 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_boss_bar_reveal_tween.tween_property(_boss_bar, "offset_top", 4.0, 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_boss_bar_reveal_tween.tween_property(_boss_bar, "offset_bottom", 4.0 + BOSS_BAR_HEIGHT, 0.4) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	if is_instance_valid(_boss_bar_enemy):
		_boss_bar_reveal_tween.tween_property(_boss_bar_enemy, "modulate:a", 1.0, 0.4) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


func _on_boss_hp_changed(current: int, maximum: int) -> void:
	if _boss_bar == null or _boss_bar_fill == null:
		return
	var ratio: float = float(current) / float(maximum) if maximum > 0 else 0.0
	var prev_ratio: float = _boss_bar_fill.scale.x
	var tw := create_tween()
	tw.tween_property(_boss_bar_fill, "scale:x", ratio, 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	if ratio < prev_ratio:
		# 預覽條與 boss bar fill 對齊
		_play_hp_damage_preview(_boss_bar_fill, prev_ratio, ratio)
	if _boss_bar_label:
		_boss_bar_label.text = "%d / %d" % [current, maximum]


func _on_boss_died(_e: Enemy) -> void:
	_bind_boss_bar(null)


func _on_enemy_long_pressed(enemy: Enemy) -> void:
	_show_enemy_status_popup(enemy)


func _show_enemy_status_popup(enemy: Enemy) -> void:
	if _enemy_popup_layer != null or enemy == null or not is_instance_valid(enemy) or enemy.data == null:
		return
	var data: EnemyData = enemy.data
	_enemy_popup_layer = CanvasLayer.new()
	_enemy_popup_layer.layer = 83
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	host.add_child(_enemy_popup_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			_close_enemy_status_popup()
	)
	_enemy_popup_layer.add_child(dim)

	const PANEL_W: float = 480.0
	const HEADER_H: float = 150.0
	var panel := PanelContainer.new()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.offset_left = -PANEL_W * 0.5
	panel.offset_right = PANEL_W * 0.5
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.clip_contents = true
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.12, 0.18, 0.97)
	bg.border_color = Color(0.85, 0.72, 0.30)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(14)
	bg.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", bg)
	_enemy_popup_layer.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)

	var header := Control.new()
	header.custom_minimum_size = Vector2(PANEL_W, HEADER_H)
	header.clip_contents = true
	vbox.add_child(header)

	if data.portrait_texture != null:
		var portrait_tex := TextureRect.new()
		portrait_tex.texture = data.portrait_texture
		portrait_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		portrait_tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		portrait_tex.anchor_left = 0.0
		portrait_tex.anchor_top = 1.0
		portrait_tex.anchor_right = 0.0
		portrait_tex.anchor_bottom = 1.0
		portrait_tex.offset_left = 4.0
		portrait_tex.offset_top = -260.0
		portrait_tex.offset_right = 264.0
		portrait_tex.offset_bottom = 0.0
		header.add_child(portrait_tex)

	var info_vbox := VBoxContainer.new()
	info_vbox.anchor_left = 0.0
	info_vbox.anchor_top = 0.0
	info_vbox.anchor_right = 1.0
	info_vbox.anchor_bottom = 1.0
	info_vbox.offset_left = 16.0
	info_vbox.offset_right = -16.0
	info_vbox.add_theme_constant_override("separation", 6)
	info_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	info_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(info_vbox)

	var name_lbl := Label.new()
	name_lbl.text = data.get_display_name()
	name_lbl.add_theme_font_size_override("font_size", 27)
	name_lbl.add_theme_color_override("font_color", Color.WHITE)
	name_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	name_lbl.add_theme_constant_override("outline_size", 4)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(name_lbl)

	var meta_row := HBoxContainer.new()
	meta_row.add_theme_constant_override("separation", 5)
	meta_row.alignment = BoxContainer.ALIGNMENT_END
	meta_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(meta_row)

	var elem_icon := TextureRect.new()
	elem_icon.texture = Block.GEM_TEXTURES.get(data.element, null)
	elem_icon.custom_minimum_size = Vector2(18, 18)
	elem_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	elem_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta_row.add_child(elem_icon)

	var lv_lbl := Label.new()
	lv_lbl.text = "Lv. %d" % enemy.spawn_level
	lv_lbl.add_theme_font_size_override("font_size", 23)
	lv_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	lv_lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lv_lbl.add_theme_constant_override("outline_size", 3)
	lv_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta_row.add_child(lv_lbl)

	var skills_scroll := ScrollContainer.new()
	skills_scroll.custom_minimum_size = Vector2(PANEL_W, 220)
	skills_scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(skills_scroll)

	var skills_margin := MarginContainer.new()
	skills_margin.add_theme_constant_override("margin_left", 16)
	skills_margin.add_theme_constant_override("margin_right", 16)
	skills_margin.add_theme_constant_override("margin_top", 12)
	skills_margin.add_theme_constant_override("margin_bottom", 12)
	skills_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills_scroll.add_child(skills_margin)

	var skills_vbox := VBoxContainer.new()
	skills_vbox.add_theme_constant_override("separation", 8)
	skills_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	skills_margin.add_child(skills_vbox)

	if int(data.passive_type) != EnemyData.PassiveType.NONE:
		_add_enemy_popup_passive(skills_vbox, data)
	else:
		var empty_lbl := Label.new()
		empty_lbl.text = Locale.tr_ui("NO_PASSIVE")
		empty_lbl.add_theme_font_size_override("font_size", 17)
		empty_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
		skills_vbox.add_child(empty_lbl)

	dim.modulate.a = 0.0
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.88, 0.88)
	panel.resized.connect(func() -> void:
		panel.pivot_offset = panel.size * 0.5
	, CONNECT_ONE_SHOT)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(dim, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, 0.18).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.20).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _add_enemy_popup_passive(parent: VBoxContainer, data: EnemyData) -> void:
	var entry := VBoxContainer.new()
	entry.add_theme_constant_override("separation", 8)
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(entry)

	var row_wrap := MarginContainer.new()
	entry.add_child(row_wrap)
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0.58))
	grad.set_color(1, Color(0, 0, 0, 0))
	var grad_tex := GradientTexture2D.new()
	grad_tex.gradient = grad
	grad_tex.fill_from = Vector2(0, 0.5)
	grad_tex.fill_to = Vector2(1, 0.5)
	var row_bg := TextureRect.new()
	row_bg.texture = grad_tex
	row_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	row_bg.stretch_mode = TextureRect.STRETCH_SCALE
	row_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row_wrap.add_child(row_bg)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 7)
	title_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row_wrap.add_child(title_row)

	title_row.add_child(_make_enemy_passive_requirement_box(data, Vector2(30, 30), 14, true))

	var nm := Label.new()
	nm.text = _enemy_passive_name(data)
	nm.add_theme_font_size_override("font_size", 19)
	nm.add_theme_color_override("font_color", Color.WHITE)
	nm.add_theme_color_override("font_outline_color", Color.BLACK)
	nm.add_theme_constant_override("outline_size", 4)
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_row.add_child(nm)

	var detail_row := HBoxContainer.new()
	detail_row.add_theme_constant_override("separation", 10)
	detail_row.alignment = BoxContainer.ALIGNMENT_CENTER
	detail_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.add_child(detail_row)

	var dl := Label.new()
	dl.text = _enemy_passive_desc(data)
	dl.add_theme_font_size_override("font_size", 16)
	dl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.9))
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_row.add_child(dl)


func _make_enemy_passive_requirement_box(data: EnemyData, icon_size: Vector2 = Vector2(68, 68), font_size: int = 26, prefix_plus: bool = false) -> Control:
	var wrap := Control.new()
	wrap.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	wrap.custom_minimum_size = icon_size
	var gem := TextureRect.new()
	gem.texture = Block.GEM_TEXTURES.get(data.passive_required_gem_type, null)
	gem.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gem.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gem.set_anchors_preset(Control.PRESET_FULL_RECT)
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(gem)
	var num := Label.new()
	var count: int = EnemyData.clamp_passive_required_gem_count(data.passive_required_gem_count)
	if prefix_plus:
		num.text = "+%d" % count
	else:
		num.text = "%d+" % count
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.set_anchors_preset(Control.PRESET_FULL_RECT)
	var font: Font = load("res://assets/fonts/game_ui_font.tres")
	if font != null:
		num.add_theme_font_override("font", font)
	num.add_theme_font_size_override("font_size", font_size)
	num.add_theme_color_override("font_color", Color.WHITE)
	num.add_theme_color_override("font_outline_color", Color.BLACK)
	num.add_theme_constant_override("outline_size", 5)
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(num)
	return wrap


func _enemy_passive_name(data: EnemyData) -> String:
	match int(data.passive_type):
		EnemyData.PassiveType.REQUIRE_GEM_COUNT_DAMAGE_GATE:
			return Locale.tr_or(data.passive_name, Locale.tr_ui("Gem Gate"))
	return Locale.tr_ui("PASSIVE")


func _enemy_passive_desc(data: EnemyData) -> String:
	match int(data.passive_type):
		EnemyData.PassiveType.REQUIRE_GEM_COUNT_DAMAGE_GATE:
			var template: String = Locale.tr_or("Gem Gate DESC", "Requires %d+ %s gems this turn to deal normal damage. Otherwise incoming damage becomes 1.")
			return template % [EnemyData.clamp_passive_required_gem_count(data.passive_required_gem_count), _localized_element_name(data.passive_required_gem_type)]
	return Locale.tr_or(data.passive_desc, data.passive_desc)


func _localized_element_name(element_type: int) -> String:
	match element_type:
		Block.Type.RED:
			return Locale.tr_ui("ELEMENT_FIRE")
		Block.Type.BLUE:
			return Locale.tr_ui("ELEMENT_WATER")
		Block.Type.GREEN:
			return Locale.tr_ui("ELEMENT_LEAF")
		Block.Type.LIGHT:
			return Locale.tr_ui("ELEMENT_LIGHT")
		Block.Type.DARK:
			return Locale.tr_ui("ELEMENT_DARK")
	return str(element_type)


func _close_enemy_status_popup() -> void:
	if _enemy_popup_layer == null:
		return
	var layer := _enemy_popup_layer
	_enemy_popup_layer = null
	var tw := create_tween().set_parallel(true)
	for child in layer.get_children():
		tw.tween_property(child, "modulate:a", 0.0, 0.14).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(layer.queue_free)


## 偵錯：將本回合所有存活敵人 HP 扣為 0，沿用既有死亡 → 下一波 / 勝利流程
func _on_kill_all_pressed() -> void:
	if battle_manager == null:
		return
	var snapshot: Array = battle_manager.active_enemies.duplicate()
	for e: Enemy in snapshot:
		if is_instance_valid(e) and e.current_hp > 0:
			e.take_damage(e.current_hp)


## 偵錯：將棋盤改成 3x3 九宮格元素堆，方便測試 fusion。
func _on_test_board_pressed() -> void:
	if board == null or battle_manager == null:
		return
	if battle_manager.is_round_transitioning:
		return

	var pattern: Array[Block.Type] = [
		Block.Type.RED,
		Block.Type.BLUE,
		Block.Type.GREEN,
		Block.Type.LIGHT,
	]
	var tile_size := 3
	var tile_columns: int = maxi(1, ceili(float(board.columns) / float(tile_size)))
	board.clear_deferred_clicks()
	for y in board.rows:
		for x in board.columns:
			var block: Block = board.grid[x][y]
			if block == null or block.is_obstacle():
				continue
			var tile_x: int = int(floor(float(x) / float(tile_size)))
			var tile_y: int = int(floor(float(y) / float(tile_size)))
			var tile_index: int = tile_y * tile_columns + tile_x
			var gem_type: Block.Type = pattern[tile_index % pattern.size()]
			block.visible = true
			block.modulate = Color.WHITE
			block.rotation = 0.0
			block.scale = Vector2.ONE
			block.set_upper_type(Block.UpperType.NONE)
			block.clear_extras()
			block.set_block_type(gem_type)
	board.resync_logic_from_visual()
	battle_manager.clear_logic_pending_attack()
	battle_manager.resync_logic_state()
	_setup_fuse_hints()


## 偵錯：Combo Test 按鈕 — 在按鈕上方彈出當前隊伍可用的高階寶石選單
func _on_combo_test_pressed(source_btn: Button) -> void:
	if board == null:
		return

	# 若已有選單開著則關閉（toggle）
	var ui_layer: CanvasLayer = $UILayer
	var existing: Node = ui_layer.get_node_or_null("ComboPopup")
	if existing != null:
		existing.queue_free()
		return

	# 收集當前隊伍所有高階寶石技能（去重）
	var upper_entries: Array = []
	var seen_upper_types: Dictionary = {}
	for c: CharacterData in party:
		for skill: Dictionary in c.responding_skills:
			var sname: String = skill.get("name", "")
			var upper_type: Block.UpperType = SkillUpgradeUtils.responding_upper_type(skill)
			if upper_type == Block.UpperType.NONE or seen_upper_types.has(upper_type):
				continue
			var fuse_gem_type: Block.Type = SkillUpgradeUtils.responding_gem_type(c, skill)
			seen_upper_types[upper_type] = true
			upper_entries.append({"name": sname, "gem_type": fuse_gem_type, "upper_type": upper_type})

	if upper_entries.is_empty():
		return

	# 建立彈出面板
	var popup := PanelContainer.new()
	popup.name = "ComboPopup"
	var popup_style := StyleBoxFlat.new()
	popup_style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	popup_style.set_corner_radius_all(6)
	popup_style.set_content_margin_all(4)
	popup.add_theme_stylebox_override("panel", popup_style)
	popup.mouse_filter = Control.MOUSE_FILTER_STOP

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	popup.add_child(vbox)

	for entry in upper_entries:
		var ename: String = entry["name"]
		var egem: int = entry["gem_type"]
		var upper_type: Block.UpperType = int(entry["upper_type"])
		var row_btn := Button.new()
		row_btn.text = ename
		row_btn.flat = false
		var gem_color: Color = Block.COLORS.get(egem, Color.WHITE)
		row_btn.modulate = gem_color.lightened(0.25)
		row_btn.custom_minimum_size = Vector2(130, 28)
		row_btn.pressed.connect(func() -> void:
			popup.queue_free()
			_debug_spawn_upper_type(upper_type)
		)
		vbox.add_child(row_btn)

	ui_layer.add_child(popup)
	await get_tree().process_frame

	# 將面板對齊在按鈕正上方
	var btn_rect: Rect2 = source_btn.get_global_rect()
	var popup_size: Vector2 = popup.size
	popup.set_anchors_preset(Control.PRESET_TOP_LEFT)
	popup.offset_left = btn_rect.position.x
	popup.offset_top = btn_rect.position.y - popup_size.y - 4.0
	popup.offset_right = popup.offset_left + popup_size.x
	popup.offset_bottom = popup.offset_top + popup_size.y


## 偵錯：根據技能名稱在棋盤隨機生成 15 個對應高階寶石
func _debug_spawn_upper(skill_name: String) -> void:
	_debug_spawn_upper_type(_upper_type_for_response_skill(skill_name))


func _debug_spawn_upper_type(ut: Block.UpperType) -> void:
	if board == null:
		return
	if ut == Block.UpperType.NONE:
		# 倒回旧行為
		if board.has_method("debug_spawn_firebombs"):
			board.debug_spawn_firebombs(15)
		return
	var candidates: Array = []
	for x in board.columns:
		for y in board.rows:
			var b: Block = board.grid[x][y]
			if b != null and not b.is_upper_gem():
				candidates.append(Vector2i(x, y))
	candidates.shuffle()
	var n: int = mini(15, candidates.size())
	for i in n:
		board.place_upper_gem(candidates[i], ut)


func _on_skill_reset_pressed() -> void:
	battle_manager.reset_all_skill_cooldowns()
	_update_skill_ui()


## HP 條傷害預覽白條：與 Fill 對齊（同 padding），停留 0.45s 後右邊崩興至新 HP 邊界
func _play_hp_damage_preview(fill: Control, prev_ratio: float, new_ratio: float) -> void:
	HpDamagePreview.show(fill, prev_ratio, new_ratio)
