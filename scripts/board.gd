## Board（棋盤）— 管理寶石網格、點擊消除、掉落填充、融合提示及高階寶石邏輯。
extends Node2D

const CELL_SIZE := 64          # 每格寶石的像素尺寸
const FALL_SPEED := 800.0      # 掉落速度（像素/秒）— 掉落與填充共用
var chain_blast_interval := 0.2  # 連鎖爆炸之間的間隔（秒）

const BlockScene := preload("res://scenes/block.tscn")  # 寶石場景預載
const TrailProjectileScript := preload("res://scripts/trail_projectile.gd")
const PLANK_DEBRIS_TEXTURE := preload("res://assets/blocks/wood.png")
const WOOD_SPEAR_THRUST_TEXTURE := preload("res://assets/leafspear.png")
const GEM_DEBRIS_Z_INDEX := 90
const OBSTACLE_DEBRIS_Z_INDEX := 100
const WOOD_SPEAR_THRUST_Z_INDEX := 110
const FLOATING_UPPER_Z_INDEX := 18
const FUSE_SOLUTION_1 := 1  # 舊版融合：高階寶石留在棋盤內，掉落時會跟著坍塌移動。
const FUSE_SOLUTION_2 := 2  # 上一版融合：高階寶石暫時浮起，原格用固定佔位保留。
const FUSE_SOLUTION_3 := 3  # 目前新版：高階寶石暫時浮起且不阻擋坍塌，坍塌後插回原本融合欄位。
const ACTIVE_FUSE_SOLUTION := FUSE_SOLUTION_1  # 若日後要切換方案，改成 FUSE_SOLUTION_1 / 2 / 3。
const NORMAL_GEM_DEBRIS_SHARDS := 5
const UPPER_GEM_DEBRIS_SHARDS := 7
const OBSTACLE_DEBRIS_SHARDS := 8
const WOOD_SPEAR_THRUST_SCALE := 0.18
const WOOD_SPEAR_THRUST_TIP_FROM_TOP := 48.0
const WOOD_SPEAR_ROW_HIT_INTERVAL := 0.075
const SELECTION_ORDER_FONT := preload("res://assets/fonts/game_ui_font.tres")

@export var stage: StageData  # 當前關卡資料

var columns: int = 8          # 棋盤欄位數
var rows: int = 8             # 棋盤行數
var allowed_types: Array[Block.Type] = []  # 允許出現的寶石類型
var min_match: int = 2        # 最少連接數才可消除

var grid: Array = []          # 二維網格陣列 grid[x][y] = Block 或 null
# is_busy 屬性後備欄位（property 用，setter 觸發 drain）
var _is_busy_back: bool = false
var _escape_refill_input_lock: bool = false
var _input_queue_locked: bool = false
var _board_input_paused: bool = false
# is_busy：是否正在處理動畫/消除中（防止重複點擊）
# 改為 property — falling edge 自動觸發 deferred clicks drain
var is_busy: bool:
	get:
		return _is_busy_back
	set(v):
		if not v and (_escape_refill_input_lock or _escape_scroll_running):
			return
		var was: bool = _is_busy_back
		_is_busy_back = v
		if was and not v:
			call_deferred("_drain_deferred_clicks")
var score: int = 0            # 當前得分
var last_tapped_pos: Vector2i = Vector2i(-1, -1)  # 最後一次點擊的網格位置
var last_tapped_local_pos: Vector2 = Vector2(-1.0, -1.0)  # 最後一次點擊在棋盤 local 座標的位置
var skip_collapse: bool = false   # 融合流程中由 main.gd 設定，跳過自動掉落
var _fuse_skills: Array[Dictionary] = []  # 融合技能清單 { gem_type, threshold, label, trigger_type, team_index }
var is_fusing: bool = false       # 融合動畫進行中（允許並行點擊下一次融合）
var _concurrent_fuse_tapped_pos: Vector2i = Vector2i(-1, -1)  # 並行融合點擊的位置（由 _on_gems_blasted 讀取）
var _concurrent_fuse_tapped_local_pos: Vector2 = Vector2(-1.0, -1.0)  # 並行融合點擊的 local 座標
var _floating_fused_upper_gems: Array[Dictionary] = []

# ── 邏輯狀態（State/UI 分離：用於連續爆破預測驗證）──────────
## logic_grid[x][y] 儲存 Block.Type（int）或：
#   LOGIC_UNKNOWN：等待視覺填充隨機顏色（BFS 不會匹配）
#   LOGIC_UPPER：高階寶石（BFS 不會匹配普通爆破）
#   LOGIC_PLANK：block（PLANK）— 不參與 BFS
#   LOGIC_ROCK：rock（ROCK）— 不參與 BFS、不移動、不被消除
#   LOGIC_WOOD_STRUCTURE：woodStructure — 不參與 BFS、不移動、可被爆破拆除
#   LOGIC_SPAWNED_UNKNOWN：只在掉落預測中暫用；落定後轉回 LOGIC_UNKNOWN
const LOGIC_UNKNOWN := 999
const LOGIC_SPAWNED_UNKNOWN := 998
const LOGIC_UPPER := -1
const LOGIC_PLANK := -2
const LOGIC_ROCK := -3
const LOGIC_WOOD_STRUCTURE := -4
const LOGIC_ESCAPE_MARKER := -5
const LOGIC_HOLE := -6
const EDIT_RANDOM := -1
const VISUAL_HOLE := &"hole"
const FUSE_SOLUTION1_UPPER_PLACEHOLDER := &"upper_placeholder"
const FLOATING_UPPER_PLACEHOLDER := &"floating_upper_placeholder"
var logic_grid: Array = []
# 待處理的 click queue（玩家在動畫期間預先輸入的爆破點擊）
var deferred_clicks: Array[Vector2i] = []
# battle_manager 引用（由 main.gd 透過 setter 注入；用於邏輯敵人狀態查詢）
var battle_manager_ref: Node = null
var _draining: bool = false       # 正在 drain queue（避免遞迴）
# 標記下一次 _handle_click 來自 drain（邏輯狀態已預先套用，跳過再扣血/destroy）
var _next_click_is_drained: bool = false
# 由 main.gd 設定：attack worker 仍在處理 queue（影響 upper-gem drain 時機）
var external_attack_busy: bool = false


func _player_is_defeated() -> bool:
	return battle_manager_ref != null and int(battle_manager_ref.get("player_current_hp")) <= 0


## 清除尚未執行的預輸入，並重置 deferred drain 狀態。
func clear_deferred_clicks() -> void:
	deferred_clicks.clear()
	_draining = false
	_next_click_is_drained = false


## 暫停棋盤點擊；敵方回合使用，避免 busy 空窗吃到玩家舊輸入。
func set_board_input_paused(paused: bool) -> void:
	_board_input_paused = paused
	if paused:
		clear_deferred_clicks()
		if _longpress_active:
			_hide_blast_preview()
		_longpress_active = false
		_longpress_pos = Vector2i(-1, -1)
		_longpress_timer = 0.0


func _block_input_after_defeat() -> bool:
	if not _player_is_defeated():
		return false
	clear_deferred_clicks()
	if _longpress_active:
		_hide_blast_preview()
	_longpress_active = false
	_longpress_pos = Vector2i(-1, -1)
	_longpress_timer = 0.0
	return true

# ── 選擇模式（主動技能用：懸停預覽十字範圍，點擊確認轉換）──
var _selection_mode: bool = false           # 是否處於選擇模式
var _selection_convert_type: Block.Type = Block.Type.RED  # 選擇模式要轉換的目標類型
var _selection_pattern: String = "cross"    # 選擇模式的預覽形狀："cross" | "fireball"
var _preview_overlays: Array[ColorRect] = []  # 預覽覆蓋層節點
var _selection_order_labels: Array[Label] = []
var _selection_valid_centers: Array[Vector2i] = []      # 當前模式可點擊的中心格
var _selection_preview_positions: Array[Vector2i] = []  # 目前 hover 顯示的影響範圍
var _selection_finished_emitted: bool = false           # 防止確認/取消重複發出
var _preview_center: Vector2i = Vector2i(-1, -1)  # 目前預覽的中心格
var _selection_max_count: int = 1
var _selection_selected_positions: Array[Vector2i] = []

# ── 長按預覽系統（長按高階寶石顯示爆炸範圍）──
const LONGPRESS_THRESHOLD := 0.35         # 長按觸發閾值（秒）
const PREVIEW_FADE_DUR := 0.18            # 預覽進出漸變時間（秒）
var _longpress_pos: Vector2i = Vector2i(-1, -1)  # 長按追蹤的網格位置
var _longpress_timer: float = 0.0          # 已按住時間
var _longpress_active: bool = false        # 長按預覽是否已顯示
var _longpress_overlays: Array[Node] = []  # 爆炸範圍高亮覆蓋層
var _longpress_dim_tween: Tween = null     # 暗化/還原動畫 tween
var _longpress_initial_tween: Tween = null # 初始爆炸色層循環動畫 tween
var _longpress_press_tween: Tween = null   # 長按預覽時 upper gem 的按壓/放開動畫
var _longpress_press_block: Block = null
var _longpress_press_original_scale: Vector2 = Vector2.ONE
var _longpress_press_original_position: Vector2 = Vector2.ZERO
var _longpress_raised_blocks: Array[Block] = []  # 預覽時被抬高 z_index 的方塊

# ── 教學系統 ──
var _tutorial_filter: Array[Vector2i] = []   # 非空時，只允許點擊這些位置
var _hand_sprite: Sprite2D = null            # 教學手指圖示
var _hand_tween: Tween = null                # 手指浮動動畫

# ── 關卡棋盤編輯模式 ───────────────────────────────────────
var _edit_mode: bool = false
var _edit_paint_value: int = Block.Type.RED
var _edit_drag_paint_value: int = Block.Type.RED
var _edit_input_enabled: bool = true
var _edit_dragging: bool = false
var _edit_last_painted: Vector2i = Vector2i(-1, -1)
var _edit_layout_values: Array = []

var _escape_marker_enabled: bool = false
var _escape_marker_pos: Vector2i = Vector2i(-1, -1)
var _escape_marker_node: Node2D = null
var _escape_marker_trails: Array[Node2D] = []
var _escape_marker_spin: float = 0.0
var _escape_scroll_running: bool = false
var _collapse_and_fill_running: bool = false
var _suppress_escape_marker_progress: bool = false
var _escape_marker_colors: Array[Color] = [
	Color(1.0, 0.22, 0.16, 0.95),
	Color(0.18, 0.55, 1.0, 0.95),
	Color(0.18, 1.0, 0.36, 0.95),
]

## collapse-and-fill 前置回呼：在現有寶石落定後、新寶石生成前由外部（main.gd）設定。
## 設定後每次有新寶石填入前會 await 此 Callable（可用於燃燒扣血等需要視覺節奏的效果）。
## 回呼以 async func() 形式提供（回傳值忽略），可在內部使用 await。
var pre_refill_hook: Callable = Callable()
## 欲觸發前置回呼標記：僅在玩家實際消除回合（正常點擊拆除 / 高階寶石被點擊）前置為 true。
## 技能等非拆除回合觸發的準苯類型不會設定此標記，從而跟燃燒正常點擊區隔。
var _blast_refill_armed: bool = false

signal score_changed(new_score: int)      # 分數變更時發出
signal gems_blasted(gem_type: Block.Type, count: int, global_positions: Array)  # 寶石消除時發出
signal goal_cells_broken(block_type: int, count: int, global_positions: Array)  # Puzzle goal 用：實際破壞格數
signal upper_gem_clicked()                # 高階寶石被點擊時發出
signal upper_blast_completed(chain_count: int, blasted_by_type: Dictionary, triggered_upper: Block.UpperType)  # 高階爆炸完成時發出
signal upper_gem_chain_triggered(upper_type: Block.UpperType)  # 連鎖中特殊高階寶石被觸發時發出
signal selection_confirmed(positions: Array)  # 選擇模式確認時發出
signal selection_finished(result: Dictionary) # 選擇模式完成或取消時發出 {positions, cancelled}
signal selection_preview_changed(positions: Array) # 選擇模式 hover 範圍變更時發出
signal blast_preview_entered()               # 長按預覽開始時發出
signal blast_preview_exited()                # 長按預覽結束時發出
signal enemy_break_pulse()                   # 敵方 AI 實際破壞棋盤格時發出，用於 SFX
signal gems_refilled(count: int)             # 從天空填充新寶石時發出（count = 本批新生成數量）
signal meteor_requested(global_pos: Vector2)  # FIREBALL 高階寶石引爆時發出（main 處理 3D 隕石 VFX）


## 初始化：讀取關卡資料並建立棋盤
signal escape_marker_moved(rows_dropped: int)

func _ready() -> void:
	if GameState.selected_stage != null:
		stage = GameState.selected_stage
	elif stage == null:
		stage = preload("res://stages/stage_dev.tres")
	_apply_stage(stage)
	initialize_board()


## 套用關卡資料到棋盤參數
func _apply_stage(s: StageData) -> void:
	columns = s.columns
	rows = s.rows
	min_match = s.min_match
	allowed_types = s.allowed_types.duplicate()


## 繪製棋盤背景格子（棋盤紋效果）
func _draw() -> void:
	var light_brown := Color(46.0/255, 32.0/255, 7.0/255)
	var dark_brown := Color(34.0/255, 22.0/255, 2.0/255)
	if _has_any_hole():
		_draw_cell_area_background()
	for x in columns:
		for y in rows:
			var rect := Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE)
			if _is_hole_pos(Vector2i(x, y)):
				if _edit_mode:
					draw_rect(rect.grow(-4.0), Color(0.0, 0.0, 0.0, 0.76))
					draw_rect(rect.grow(-5.0), Color(0.5, 0.62, 0.88, 0.82), false, 2.0)
				continue
			var c := light_brown if (x + y) % 2 == 0 else dark_brown
			draw_rect(rect, c)
	if _edit_mode:
		for x in columns:
			var marker_y: int = _get_drop_start_row(x)
			var top_left := Vector2(float(x * CELL_SIZE), float(marker_y * CELL_SIZE))
			var marker_color := Color(1.0, 0.22, 0.18, 0.95) if _is_hole_pos(Vector2i(x, marker_y)) else Color(0.35, 0.88, 1.0, 0.9)
			draw_line(top_left + Vector2(8.0, 8.0), top_left + Vector2(CELL_SIZE - 8.0, 8.0), marker_color, 3.0)
			draw_colored_polygon(
				PackedVector2Array([
					top_left + Vector2(CELL_SIZE * 0.5, 18.0),
					top_left + Vector2(CELL_SIZE * 0.5 - 7.0, 8.0),
					top_left + Vector2(CELL_SIZE * 0.5 + 7.0, 8.0),
				]),
				marker_color
			)


## 每幀更新：追蹤長按計時，超過閾值時顯示爆炸預覽
func _draw_cell_area_background() -> void:
	var bg_color := Color(0.13, 0.13, 0.2, 1.0)
	var pad := 6.0
	for x in columns:
		for y in rows:
			var pos := Vector2i(x, y)
			if _is_hole_pos(pos):
				continue
			var rect := Rect2(float(x * CELL_SIZE), float(y * CELL_SIZE), float(CELL_SIZE), float(CELL_SIZE))
			draw_rect(rect, bg_color)
			_draw_cell_area_background_edges(rect, pos, bg_color, pad)


func _draw_cell_area_background_edges(rect: Rect2, pos: Vector2i, bg_color: Color, pad: float) -> void:
	if _is_hole_or_outside(pos + Vector2i.LEFT):
		draw_rect(Rect2(rect.position.x - pad, rect.position.y, pad, rect.size.y), bg_color)
	if _is_hole_or_outside(pos + Vector2i.RIGHT):
		draw_rect(Rect2(rect.end.x, rect.position.y, pad, rect.size.y), bg_color)
	if _is_hole_or_outside(pos + Vector2i.UP):
		draw_rect(Rect2(rect.position.x, rect.position.y - pad, rect.size.x, pad), bg_color)
	if _is_hole_or_outside(pos + Vector2i.DOWN):
		draw_rect(Rect2(rect.position.x, rect.end.y, rect.size.x, pad), bg_color)

	if _is_hole_or_outside(pos + Vector2i.LEFT) and _is_hole_or_outside(pos + Vector2i.UP):
		draw_rect(Rect2(rect.position.x - pad, rect.position.y - pad, pad, pad), bg_color)
	if _is_hole_or_outside(pos + Vector2i.RIGHT) and _is_hole_or_outside(pos + Vector2i.UP):
		draw_rect(Rect2(rect.end.x, rect.position.y - pad, pad, pad), bg_color)
	if _is_hole_or_outside(pos + Vector2i.LEFT) and _is_hole_or_outside(pos + Vector2i.DOWN):
		draw_rect(Rect2(rect.position.x - pad, rect.end.y, pad, pad), bg_color)
	if _is_hole_or_outside(pos + Vector2i.RIGHT) and _is_hole_or_outside(pos + Vector2i.DOWN):
		draw_rect(Rect2(rect.end.x, rect.end.y, pad, pad), bg_color)


func _is_hole_or_outside(pos: Vector2i) -> bool:
	return not _is_valid(pos) or _is_hole_pos(pos)


func _process(delta: float) -> void:
	_update_escape_marker_vfx(delta)
	if _longpress_pos == Vector2i(-1, -1) or _longpress_active:
		return
	_longpress_timer += delta
	if _longpress_timer >= LONGPRESS_THRESHOLD:
		_show_blast_preview(_longpress_pos)


## 初始化棋盤：清除舊網格並為每一格建立新寶石
func initialize_board() -> void:
	grid.clear()
	grid.resize(columns)
	for x in columns:
		grid[x] = []
		grid[x].resize(rows)
		for y in rows:
			_create_block(x, y)
	# 若有固定佈局，覆寫寶石類型（負值代表「保留隨機」，跳過該格）
	if stage != null and stage.fixed_layout.size() == columns:
		for x in columns:
			var col: Array = stage.fixed_layout[x]
			for y in rows:
				if y < col.size() and grid[x][y] != null:
					var t: int = int(col[y])
					if t == StageData.CELL_HOLE:
						grid[x][y].queue_free()
						grid[x][y] = null
						continue
					if t == StageData.CELL_WATER_SWORD:
						grid[x][y].set_block_type(Block.Type.BLUE)
						grid[x][y].set_upper_type(Block.UpperType.WATER_SLASH)
						continue
					if t < 0 or not Block.is_valid_type_value(t):
						continue
					grid[x][y].set_block_type(t)
	# 關卡 1-6：所有 PLANK 自動掛載 BURNING 效果
	if stage != null and stage.stage_id == "1-6":
		for x in columns:
			for y in rows:
				var b: Block = grid[x][y]
				if b != null and b.is_block():
					b.add_extra(Block.ExtraEffect.BURNING)
	_init_logic_grid_from_visual()
	_refresh_background_visibility()
	_update_fuse_hints()


## 從視覺 grid 完整初始化 logic_grid（重建/重置時呼叫）
func _init_logic_grid_from_visual() -> void:
	logic_grid.clear()
	logic_grid.resize(columns)
	for x in columns:
		logic_grid[x] = []
		logic_grid[x].resize(rows)
		for y in rows:
			var pos := Vector2i(x, y)
			if _is_hole_pos(pos):
				logic_grid[x][y] = LOGIC_HOLE
				continue
			if is_escape_marker_pos(pos):
				logic_grid[x][y] = LOGIC_ESCAPE_MARKER
				continue
			var b: Block = grid[x][y]
			if b == null:
				logic_grid[x][y] = LOGIC_UNKNOWN
			elif b.is_upper_gem():
				logic_grid[x][y] = LOGIC_UPPER
			elif b.is_block():
				logic_grid[x][y] = LOGIC_PLANK
			elif b.is_rock():
				logic_grid[x][y] = LOGIC_ROCK
			elif b.is_wood_structure():
				logic_grid[x][y] = LOGIC_WOOD_STRUCTURE
			else:
				logic_grid[x][y] = b.block_type


## 從視覺 grid 同步未知（LOGIC_UNKNOWN）的 logic_grid 格子。
## 在每次視覺 _collapse_and_fill 完成時呼叫，讓邏輯追上視覺隨機填色。
func _sync_logic_unknowns_from_visual() -> void:
	for x in columns:
		for y in rows:
			var pos := Vector2i(x, y)
			if _is_hole_pos(pos):
				logic_grid[x][y] = LOGIC_HOLE
				continue
			if is_escape_marker_pos(pos):
				logic_grid[x][y] = LOGIC_ESCAPE_MARKER
				continue
			if logic_grid[x][y] == LOGIC_ESCAPE_MARKER:
				logic_grid[x][y] = LOGIC_UNKNOWN
			if logic_grid[x][y] == LOGIC_UNKNOWN:
				var b: Block = grid[x][y]
				if b != null:
					if b.is_upper_gem():
						logic_grid[x][y] = LOGIC_UPPER
					elif b.is_block():
						logic_grid[x][y] = LOGIC_PLANK
					elif b.is_rock():
						logic_grid[x][y] = LOGIC_ROCK
					elif b.is_wood_structure():
						logic_grid[x][y] = LOGIC_WOOD_STRUCTURE
					else:
						logic_grid[x][y] = int(b.block_type)


func _refresh_background_visibility() -> void:
	var bg: CanvasItem = get_node_or_null("Background") as CanvasItem
	if bg != null:
		bg.visible = not _has_any_hole()


func _has_any_hole() -> bool:
	for x in columns:
		for y in rows:
			if _is_hole_pos(Vector2i(x, y)):
				return true
	return false


## 完整將 logic_grid 重置為視覺狀態（無 queued click 時的安全點呼叫，例如波次轉換後）
func resync_logic_from_visual() -> void:
	if not deferred_clicks.is_empty():
		return
	_init_logic_grid_from_visual()


## 隱藏所有寶石（進場動畫用：設為完全透明 + 略微縮小）
func hide_all_gems() -> void:
	for x in columns:
		for y in rows:
			var block: Block = grid[x][y]
			if block != null:
				block.modulate.a = 0.0
				block.scale = Vector2(0.5, 0.5)


## 進場動畫：寶石以隨機順序逐個浮現（淡入 + 彈性放大）
func play_gems_intro() -> void:
	# 收集所有寶石座標並打亂順序
	var positions: Array[Vector2i] = []
	for x in columns:
		for y in rows:
			if grid[x][y] != null:
				positions.append(Vector2i(x, y))
	# Fisher-Yates 洗牌
	for i in range(positions.size() - 1, 0, -1):
		var j: int = randi() % (i + 1)
		var tmp: Vector2i = positions[i]
		positions[i] = positions[j]
		positions[j] = tmp

	# 每顆寶石間隔一小段時間浮現（總時長約 0.35 秒）
	var total_gems: int = positions.size()
	var interval: float = 0.35 / maxf(total_gems, 1)
	for idx in total_gems:
		var pos: Vector2i = positions[idx]
		var block: Block = grid[pos.x][pos.y]
		if block == null:
			continue
		var tw := create_tween().set_parallel(true)
		tw.tween_property(block, "modulate:a", 1.0, 0.61) \
			.set_ease(Tween.EASE_OUT)
		tw.tween_property(block, "scale", Vector2.ONE, 0.63) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		# 不等每顆完成，用計時器交錯
		if idx < total_gems - 1:
			await get_tree().create_timer(interval).timeout
	# 等最後一顆完成動畫
	await get_tree().create_timer(0.63).timeout


## 將整個棋盤暗化（同長按預覽用色），用於波次轉場
## duration: 漸變時間（秒）
func darken_all_gems(duration: float = 0.4) -> void:
	if _longpress_dim_tween != null and _longpress_dim_tween.is_valid():
		_longpress_dim_tween.kill()
	var dim_color := Color(0.3, 0.3, 0.35, 1.0)
	_longpress_dim_tween = create_tween().set_parallel(true)
	for x in columns:
		for y in rows:
			var b: Block = grid[x][y]
			if b != null:
				_longpress_dim_tween.tween_property(b, "modulate", dim_color, duration) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)


## 將整個棋盤淡回正常顏色，並重新顯示融合提示
## duration: 漸變時間（秒）
func brighten_all_gems(duration: float = 0.4) -> void:
	if _longpress_dim_tween != null and _longpress_dim_tween.is_valid():
		_longpress_dim_tween.kill()
	var normal_color := Color(1, 1, 1, 1)
	_longpress_dim_tween = create_tween().set_parallel(true)
	for x in columns:
		for y in rows:
			var b: Block = grid[x][y]
			if b != null:
				_longpress_dim_tween.tween_property(b, "modulate", normal_color, duration) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# 漸變完成後重新刷新融合提示（防止波次轉場期間被覆蓋）
	_longpress_dim_tween.chain().tween_callback(_update_fuse_hints)


## 在指定格子建立一個新寶石
func _create_block(x: int, y: int, start_pos: Vector2 = Vector2.ZERO, use_start_pos: bool = false) -> Block:
	if not _cell_accepts_block(Vector2i(x, y)):
		return null
	var block: Block = BlockScene.instantiate()
	block.grid_pos = Vector2i(x, y)
	block.set_board_columns(columns)
	block.set_block_type(_random_type())
	# Set position BEFORE add_child so it never flashes at the wrong spot.
	block.position = start_pos if use_start_pos else grid_to_world(Vector2i(x, y))
	add_child(block)
	grid[x][y] = block
	# 關卡 1-6：火屬性寶石自動掛載 BURNING 額外效果（含初始填充與天空補充）
	if stage != null and stage.stage_id == "1-6" and block.block_type == Block.Type.RED:
		block.add_extra(Block.ExtraEffect.BURNING)
	return block


## 隨機選擇一個允許的寶石類型
func _random_type() -> int:
	var distribution: Dictionary = stage.get_element_distribution() if stage != null else {}
	var total_weight: int = 0
	for key in distribution.keys():
		var type_value: int = int(key)
		if Block.is_random_gem_type_value(type_value):
			total_weight += maxi(0, int(distribution[key]))
	if total_weight <= 0:
		return Block.Type.RED
	var roll: int = randi() % total_weight
	var cursor: int = 0
	for key in distribution.keys():
		var type_value: int = int(key)
		if not Block.is_random_gem_type_value(type_value):
			continue
		cursor += maxi(0, int(distribution[key]))
		if roll < cursor:
			return type_value
	return Block.Type.RED


## 將網格座標轉換為世界像素座標（格子中心點）
func grid_to_world(gp: Vector2i) -> Vector2:
	return Vector2(gp.x * CELL_SIZE + CELL_SIZE * 0.5, gp.y * CELL_SIZE + CELL_SIZE * 0.5)


## 將世界像素座標轉換為網格座標
func world_to_grid(wp: Vector2) -> Vector2i:
	var gx := int(wp.x) / CELL_SIZE
	var gy := int(wp.y) / CELL_SIZE
	return Vector2i(gx, gy)


## 檢查網格座標是否在棋盤範圍內
func _is_valid(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < columns and pos.y >= 0 and pos.y < rows


func _is_hole_pos(pos: Vector2i) -> bool:
	if not _is_valid(pos):
		return false
	if _edit_mode:
		_ensure_edit_layout_values()
		if pos.x < _edit_layout_values.size() and _edit_layout_values[pos.x] is Array:
			var edit_col: Array = _edit_layout_values[pos.x]
			if pos.y < edit_col.size():
				return int(edit_col[pos.y]) == StageData.CELL_HOLE
	if stage == null or stage.fixed_layout.size() != columns:
		return false
	if not (stage.fixed_layout[pos.x] is Array):
		return false
	var col: Array = stage.fixed_layout[pos.x]
	return pos.y < col.size() and int(col[pos.y]) == StageData.CELL_HOLE


func _cell_accepts_block(pos: Vector2i) -> bool:
	return _is_valid(pos) and not _is_hole_pos(pos)


func _get_drop_start_row(column_index: int) -> int:
	if stage == null or column_index < 0 or column_index >= columns:
		return 0
	if column_index >= stage.drop_start_rows.size():
		return 0
	return clampi(int(stage.drop_start_rows[column_index]), 0, rows - 1)


func _get_drop_spawn_capacity(column_index: int) -> int:
	if column_index < 0 or column_index >= columns:
		return 0
	var spawn_row: int = _get_drop_start_row(column_index)
	var capacity: int = 0
	for row_index in range(spawn_row, rows):
		if not _is_hole_pos(Vector2i(column_index, row_index)):
			capacity += 1
	return capacity


func _is_no_enemy_mode() -> bool:
	return stage != null and (stage.mode == StageData.Mode.ESCAPE or stage.mode == StageData.Mode.PUZZLE)


func _emit_goal_cells_for_blocks(blocks: Array) -> void:
	var count_by_type: Dictionary = {}
	var positions_by_type: Dictionary = {}
	for value in blocks:
		var block: Block = value as Block
		if block == null or not is_instance_valid(block) or block.is_upper_gem():
			continue
		var type_value: int = int(block.block_type)
		if type_value != int(Block.Type.PLANK) and not Block.is_random_gem_type_value(type_value):
			continue
		if type_value == int(Block.Type.PLANK) or not block.is_obstacle():
			count_by_type[type_value] = int(count_by_type.get(type_value, 0)) + 1
			if not positions_by_type.has(type_value):
				positions_by_type[type_value] = []
			(positions_by_type[type_value] as Array).append(block.global_position)
	for type_key in count_by_type.keys():
		var positions: Array = positions_by_type[type_key] as Array
		goal_cells_broken.emit(int(type_key), int(count_by_type[type_key]), positions)


func is_escape_marker_pos(pos: Vector2i) -> bool:
	return _escape_marker_enabled and pos == _escape_marker_pos


func enable_escape_marker(start_pos: Vector2i) -> void:
	if not _cell_accepts_block(start_pos):
		for y in rows:
			for x in columns:
				var candidate := Vector2i(x, y)
				if _cell_accepts_block(candidate):
					start_pos = candidate
					break
			if _cell_accepts_block(start_pos):
				break
	if not _cell_accepts_block(start_pos):
		return
	_escape_marker_enabled = true
	_escape_marker_pos = start_pos
	var existing: Block = grid[start_pos.x][start_pos.y]
	if existing != null and is_instance_valid(existing):
		grid[start_pos.x][start_pos.y] = null
		existing.queue_free()
	_create_escape_marker_node()
	_position_escape_marker_node(false)
	_init_logic_grid_from_visual()


func set_escape_marker_colors(colors: Array[Color]) -> void:
	if colors.is_empty():
		return
	_escape_marker_colors = colors.duplicate()
	for trail in _escape_marker_trails:
		if is_instance_valid(trail):
			trail.queue_free()
	_escape_marker_trails.clear()
	if is_instance_valid(_escape_marker_node):
		_create_escape_marker_trails()


func get_escape_marker_grid_pos() -> Vector2i:
	return _escape_marker_pos


func place_escape_goal_wood_row(row_index: int) -> int:
	if stage == null or stage.mode != StageData.Mode.ESCAPE or not _escape_marker_enabled:
		return -1
	if row_index < 0 or row_index >= rows:
		return -1
	var placed_row: int = row_index
	var placed_count: int = 0
	for x in columns:
		var pos := Vector2i(x, placed_row)
		if not _cell_accepts_block(pos) or is_escape_marker_pos(pos):
			continue
		var block: Block = grid[x][placed_row]
		if block == null or not is_instance_valid(block):
			block = _create_block(x, placed_row)
		if block == null:
			continue
		_make_block_escape_goal_wood(block, pos)
		block.position = grid_to_world(pos)
		grid[x][placed_row] = block
		if logic_grid.size() == columns and x < logic_grid.size() and logic_grid[x] is Array and placed_row < (logic_grid[x] as Array).size():
			logic_grid[x][placed_row] = LOGIC_WOOD_STRUCTURE
		placed_count += 1
	if placed_count <= 0:
		return -1
	_init_logic_grid_from_visual()
	_update_fuse_hints()
	queue_redraw()
	return placed_row


func _make_block_escape_goal_wood(block: Block, pos: Vector2i) -> void:
	if block == null or not is_instance_valid(block):
		return
	block.grid_pos = pos
	block.set_board_columns(columns)
	block.set_block_type(Block.Type.WOOD_STRUCTURE)
	block.set_upper_type(Block.UpperType.NONE)
	block.clear_extras()
	block.modulate = Color.WHITE
	block.visible = true


func is_board_motion_running() -> bool:
	return _collapse_and_fill_running or _escape_scroll_running


func snap_visual_blocks_to_grid() -> void:
	var live_blocks: Dictionary = {}
	for x in columns:
		for y in rows:
			var block: Block = grid[x][y]
			if block == null or not is_instance_valid(block):
				continue
			live_blocks[block] = true
			var pos := Vector2i(x, y)
			block.grid_pos = pos
			block.set_board_columns(columns)
			block.position = grid_to_world(pos)
	for child in get_children():
		if child is Block and not live_blocks.has(child):
			child.queue_free()
	if _escape_marker_enabled:
		_position_escape_marker_node(false)


func force_escape_scroll_to_row(target_y: int, dramatic: bool = false, goal_wood_row: int = -1) -> void:
	if not _escape_marker_enabled or _escape_scroll_running:
		return
	var clamped_target: int = clampi(target_y, 0, rows - 1)
	var clamped_goal_wood_row: int = goal_wood_row if goal_wood_row >= 0 and goal_wood_row < rows else -1
	var shift: int = maxi(_escape_marker_pos.y - clamped_target, 0)
	var was_busy: bool = is_busy
	_escape_scroll_running = true
	is_busy = true
	if shift <= 0:
		await _play_escape_marker_scroll_shake(dramatic)
		_escape_scroll_running = false
		is_busy = was_busy
		return

	var old_grid: Array = _copy_grid_state()
	var new_grid: Array = []
	new_grid.resize(columns)
	for x in columns:
		new_grid[x] = []
		new_grid[x].resize(rows)
		for y in rows:
			new_grid[x][y] = null

	var removed_blocks: Array[Block] = []
	var tween := create_tween().set_parallel(true)
	var duration: float = 0.58 if dramatic else 0.34
	var row_delay: float = 0.075 if dramatic else 0.045
	var max_scroll_delay: float = 0.0
	var new_row_start_y: int = maxi(rows - shift, 0)
	var marker_target_pos := Vector2i(_escape_marker_pos.x, clamped_target)

	for x in columns:
		for old_y in rows:
			var cell: Variant = old_grid[x][old_y]
			if not (cell is Block):
				continue
			var block: Block = cell as Block
			var new_y: int = old_y - shift
			var delay: float = float(old_y) * row_delay
			max_scroll_delay = maxf(max_scroll_delay, delay)
			if new_y < 0 or Vector2i(x, new_y) == marker_target_pos or _is_hole_pos(Vector2i(x, new_y)):
				removed_blocks.append(block)
				var exit_y: int = new_y if new_y < 0 else new_y - shift
				tween.tween_property(block, "position", grid_to_world(Vector2i(x, exit_y)), duration) \
					.set_delay(delay) \
					.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
				tween.tween_property(block, "modulate:a", 0.0, duration * 0.75) \
					.set_delay(delay)
				continue
			if new_y == clamped_goal_wood_row:
				_make_block_escape_goal_wood(block, Vector2i(x, new_y))
			new_grid[x][new_y] = block
			block.grid_pos = Vector2i(x, new_y)
			tween.tween_property(block, "position", grid_to_world(block.grid_pos), duration) \
				.set_delay(delay) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)

	for x in columns:
		for y in range(new_row_start_y, rows):
			if Vector2i(x, y) == marker_target_pos:
				continue
			if _is_hole_pos(Vector2i(x, y)):
				continue
			if new_grid[x][y] != null:
				continue
			var start_pos: Vector2 = grid_to_world(Vector2i(x, y + shift))
			var block: Block = _create_block(x, y, start_pos, true)
			if y == clamped_goal_wood_row:
				_make_block_escape_goal_wood(block, Vector2i(x, y))
			block.modulate.a = 0.0
			new_grid[x][y] = block
			var delay: float = float(y - new_row_start_y) * row_delay + duration * 0.35
			max_scroll_delay = maxf(max_scroll_delay, delay)
			tween.tween_property(block, "position", grid_to_world(Vector2i(x, y)), duration) \
				.set_delay(delay) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
			tween.tween_property(block, "modulate:a", 1.0, duration * 0.65) \
				.set_delay(delay)

	for x in columns:
		for y in rows:
			grid[x][y] = new_grid[x][y]

	_escape_marker_pos.y = clamped_target
	if is_instance_valid(_escape_marker_node):
		tween.tween_property(_escape_marker_node, "position", grid_to_world(_escape_marker_pos), duration) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)

	await get_tree().create_timer(duration + max_scroll_delay + 0.05).timeout
	for block in removed_blocks:
		if is_instance_valid(block):
			block.queue_free()
	_init_logic_grid_from_visual()
	_update_fuse_hints()
	_escape_scroll_running = false
	is_busy = was_busy


func _create_escape_marker_node() -> void:
	if is_instance_valid(_escape_marker_node):
		return
	_escape_marker_node = Node2D.new()
	_escape_marker_node.name = "EscapeMarker"
	_escape_marker_node.z_index = 125
	_escape_marker_node.process_mode = Node.PROCESS_MODE_INHERIT
	add_child(_escape_marker_node)
	_create_escape_marker_trails()


func _create_escape_marker_trails() -> void:
	_escape_marker_trails.clear()
	var colors: Array[Color] = _escape_marker_colors.duplicate()
	if colors.is_empty():
		colors = [Color.WHITE]
	for i in colors.size():
		var trail := Node2D.new()
		trail.name = "OrbitAttackTrail%d" % i
		trail.set_script(TrailProjectileScript)
		add_child(trail)
		trail.call("setup")
		trail.z_index = 126
		trail.call("start_orbit", to_global(grid_to_world(_escape_marker_pos)), 40.5, colors[i], TAU * float(i) / float(colors.size()), 2.8, 0.93)
		_escape_marker_trails.append(trail)


func play_escape_marker_scatter() -> void:
	if _escape_marker_trails.is_empty():
		return
	var count: int = _escape_marker_trails.size()
	for i in count:
		var trail: Node2D = _escape_marker_trails[i]
		if not is_instance_valid(trail):
			continue
		var angle: float = -PI * 0.5 + TAU * float(i) / float(count)
		var dir := Vector2(cos(angle), sin(angle))
		trail.call("scatter_from_orbit", dir, 300.0, 0.62)
	if is_instance_valid(_escape_marker_node):
		var fade := create_tween()
		fade.tween_property(_escape_marker_node, "modulate:a", 0.0, 0.3)
		fade.tween_callback(func() -> void:
			if is_instance_valid(_escape_marker_node):
				_escape_marker_node.modulate.a = 1.0
				_escape_marker_node.visible = false
		)
	await get_tree().create_timer(0.68).timeout


func _position_escape_marker_node(animated: bool = true) -> void:
	if not is_instance_valid(_escape_marker_node):
		return
	var target_pos: Vector2 = grid_to_world(_escape_marker_pos)
	if animated:
		var tw := create_tween()
		tw.tween_property(_escape_marker_node, "position", target_pos, 0.18) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	else:
		_escape_marker_node.position = target_pos
	_update_escape_marker_orbit_center()


func _update_escape_marker_vfx(delta: float) -> void:
	if not is_instance_valid(_escape_marker_node):
		return
	_escape_marker_spin = fmod(_escape_marker_spin + delta * 2.2, TAU)
	_update_escape_marker_orbit_center()


func _update_escape_marker_orbit_center() -> void:
	if not is_instance_valid(_escape_marker_node):
		return
	var center_global: Vector2 = to_global(_escape_marker_node.position)
	for trail in _escape_marker_trails:
		if is_instance_valid(trail):
			trail.call("set_orbit_center", center_global)


func _play_escape_marker_scroll_shake(dramatic: bool) -> void:
	if not is_instance_valid(_escape_marker_node):
		return
	var base_pos: Vector2 = _escape_marker_node.position
	var offset: float = 18.0 if dramatic else 8.0
	var tw := create_tween()
	tw.tween_property(_escape_marker_node, "position:y", base_pos.y + offset, 0.08)
	tw.tween_property(_escape_marker_node, "position:y", base_pos.y - offset * 0.45, 0.08)
	tw.tween_property(_escape_marker_node, "position:y", base_pos.y, 0.10)
	await tw.finished


func _is_static_obstacle(block: Block) -> bool:
	return block != null and block.is_obstacle()


func set_last_tapped_input(pos: Vector2i, local_pos: Vector2) -> void:
	last_tapped_pos = pos
	last_tapped_local_pos = local_pos


func set_input_queue_locked(locked: bool) -> void:
	_input_queue_locked = locked
	if locked:
		clear_deferred_clicks()


func get_concurrent_fuse_tapped_local_pos() -> Vector2:
	return _concurrent_fuse_tapped_local_pos


func clear_concurrent_fuse_tap() -> void:
	_concurrent_fuse_tapped_pos = Vector2i(-1, -1)
	_concurrent_fuse_tapped_local_pos = Vector2(-1.0, -1.0)


func _shake_block(block: Block) -> void:
	if block == null:
		return
	var base_x: float = block.position.x
	var sh_tw: Tween = create_tween()
	sh_tw.tween_property(block, "position:x", base_x + 4.0, 0.05)
	sh_tw.tween_property(block, "position:x", base_x - 4.0, 0.05)
	sh_tw.tween_property(block, "position:x", base_x, 0.05)


func play_rejected_cell_animation(pos: Vector2i) -> void:
	if not _is_valid(pos):
		return
	_shake_block(grid[pos.x][pos.y])


func set_edit_mode(enabled: bool) -> void:
	_edit_mode = enabled
	_edit_input_enabled = enabled
	_edit_dragging = false
	_edit_last_painted = Vector2i(-1, -1)
	if enabled:
		clear_deferred_clicks()
		is_busy = false
		_selection_mode = false
		_clear_preview_overlays()
		if _longpress_active:
			_hide_blast_preview()
		_longpress_pos = Vector2i(-1, -1)
		_longpress_timer = 0.0
		_longpress_active = false
		_build_edit_layout_from_stage()
		_apply_edit_layout_to_visuals()
	else:
		_edit_layout_values.clear()
	_refresh_background_visibility()
	queue_redraw()


func set_edit_input_enabled(enabled: bool) -> void:
	_edit_input_enabled = enabled
	if not enabled:
		_edit_dragging = false
		_edit_last_painted = Vector2i(-1, -1)


func set_edit_paint_value(value: int) -> void:
	_edit_paint_value = _normalize_edit_value(value)


func paint_cell(pos: Vector2i, value: int) -> void:
	if not _is_valid(pos):
		return
	_ensure_edit_layout_values()
	var normalized: int = _normalize_edit_value(value)
	var col: Array = _edit_layout_values[pos.x]
	col[pos.y] = normalized
	_set_edit_cell_visual(pos, normalized)
	_refresh_background_visibility()
	queue_redraw()
	_edit_last_painted = pos


func clear_fixed_layout() -> void:
	_ensure_edit_layout_values()
	for x in columns:
		var col: Array = _edit_layout_values[x]
		for y in rows:
			col[y] = EDIT_RANDOM
			_set_edit_cell_visual(Vector2i(x, y), EDIT_RANDOM)
	_refresh_background_visibility()
	queue_redraw()


func get_fixed_layout_snapshot() -> Array:
	_ensure_edit_layout_values()
	var layout: Array = []
	layout.resize(columns)
	for x in columns:
		var source_col: Array = _edit_layout_values[x]
		var col: Array = []
		col.resize(rows)
		for y in rows:
			col[y] = _normalize_edit_value(int(source_col[y]))
		layout[x] = col
	return layout


func save_fixed_layout_to_stage() -> int:
	if stage == null or stage.resource_path == "":
		push_warning("Board editor: cannot save fixed_layout without a stage resource path.")
		return ERR_INVALID_PARAMETER
	stage.fixed_layout = get_fixed_layout_snapshot()
	return ResourceSaver.save(stage, stage.resource_path)


func _handle_edit_input(event: InputEvent) -> void:
	if not _edit_input_enabled:
		return
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event as InputEventMouseButton
		if mouse_button.button_index != MOUSE_BUTTON_LEFT and mouse_button.button_index != MOUSE_BUTTON_RIGHT:
			return
		if mouse_button.pressed:
			var press_pos: Vector2i = world_to_grid(get_local_mouse_position())
			_edit_dragging = _is_valid(press_pos)
			_edit_last_painted = Vector2i(-1, -1)
			_edit_drag_paint_value = EDIT_RANDOM if mouse_button.button_index == MOUSE_BUTTON_RIGHT else _edit_paint_value
			if _edit_dragging:
				paint_cell(press_pos, _edit_drag_paint_value)
		else:
			_edit_dragging = false
			_edit_last_painted = Vector2i(-1, -1)
		return
	if event is InputEventMouseMotion and _edit_dragging:
		var drag_pos: Vector2i = world_to_grid(get_local_mouse_position())
		if _is_valid(drag_pos) and drag_pos != _edit_last_painted:
			paint_cell(drag_pos, _edit_drag_paint_value)


func _build_edit_layout_from_stage() -> void:
	_edit_layout_values.clear()
	_edit_layout_values.resize(columns)
	for x in columns:
		var col: Array = []
		col.resize(rows)
		for y in rows:
			col[y] = EDIT_RANDOM
		_edit_layout_values[x] = col

	if stage == null or stage.fixed_layout.size() != columns:
		return
	for x in columns:
		if not (stage.fixed_layout[x] is Array):
			continue
		var source_col: Array = stage.fixed_layout[x]
		var target_col: Array = _edit_layout_values[x]
		for y in rows:
			if y >= source_col.size():
				continue
			target_col[y] = _normalize_edit_value(int(source_col[y]))


func _ensure_edit_layout_values() -> void:
	if _edit_layout_values.size() != columns:
		_build_edit_layout_from_stage()
		return
	for x in columns:
		if not (_edit_layout_values[x] is Array):
			_build_edit_layout_from_stage()
			return
		var col: Array = _edit_layout_values[x]
		if col.size() != rows:
			_build_edit_layout_from_stage()
			return


func _apply_edit_layout_to_visuals() -> void:
	_ensure_edit_layout_values()
	for x in columns:
		var col: Array = _edit_layout_values[x]
		for y in rows:
			_set_edit_cell_visual(Vector2i(x, y), int(col[y]))
	_init_logic_grid_from_visual()
	_refresh_background_visibility()
	queue_redraw()


func _set_edit_cell_visual(pos: Vector2i, value: int) -> void:
	var normalized: int = _normalize_edit_value(value)
	if normalized == EDIT_RANDOM or normalized == StageData.CELL_HOLE:
		var old_block: Block = grid[pos.x][pos.y]
		if old_block != null:
			old_block.visible = false
			old_block.queue_free()
			grid[pos.x][pos.y] = null
		_sync_edit_logic_cell(pos, normalized)
		return

	var block: Block = grid[pos.x][pos.y]
	if block == null:
		block = _create_block(pos.x, pos.y)
	block.grid_pos = pos
	block.set_board_columns(columns)
	block.position = grid_to_world(pos)
	block.scale = Vector2.ONE
	block.modulate = Color(1, 1, 1, 1)
	block.z_index = 0
	block.clear_extras()
	block.set_upper_type(Block.UpperType.NONE)
	if normalized == StageData.CELL_WATER_SWORD:
		block.set_block_type(Block.Type.BLUE)
		block.set_upper_type(Block.UpperType.WATER_SLASH)
	else:
		block.set_block_type(normalized)
	grid[pos.x][pos.y] = block
	_sync_edit_logic_cell(pos, normalized)


func _sync_edit_logic_cell(pos: Vector2i, value: int) -> void:
	if logic_grid.size() != columns or not (logic_grid[pos.x] is Array):
		_init_logic_grid_from_visual()
		return
	var logic_col: Array = logic_grid[pos.x]
	if logic_col.size() != rows:
		_init_logic_grid_from_visual()
		return
	var normalized: int = _normalize_edit_value(value)
	if normalized == EDIT_RANDOM:
		logic_grid[pos.x][pos.y] = LOGIC_UNKNOWN
	elif normalized == StageData.CELL_HOLE:
		logic_grid[pos.x][pos.y] = LOGIC_HOLE
	elif normalized == StageData.CELL_WATER_SWORD:
		logic_grid[pos.x][pos.y] = LOGIC_UPPER
	elif normalized == Block.Type.PLANK:
		logic_grid[pos.x][pos.y] = LOGIC_PLANK
	elif normalized == Block.Type.ROCK:
		logic_grid[pos.x][pos.y] = LOGIC_ROCK
	elif normalized == Block.Type.WOOD_STRUCTURE:
		logic_grid[pos.x][pos.y] = LOGIC_WOOD_STRUCTURE
	else:
		logic_grid[pos.x][pos.y] = normalized


func _normalize_edit_value(value: int) -> int:
	if value == EDIT_RANDOM:
		return EDIT_RANDOM
	if value == StageData.CELL_HOLE:
		return StageData.CELL_HOLE
	if value == StageData.CELL_WATER_SWORD:
		return StageData.CELL_WATER_SWORD
	if Block.is_valid_type_value(value):
		return value
	return EDIT_RANDOM


## 處理滑鼠輸入：左鍵點擊棋盤上的寶石；選擇模式下懸停預覽 + 點擊確認；長按高階寶石預覽爆炸範圍
func _unhandled_input(event: InputEvent) -> void:
	if _edit_mode:
		_handle_edit_input(event)
		return
	if _block_input_after_defeat():
		return
	if _board_input_paused:
		return

	if _selection_mode:
		if event is InputEventMouseMotion:
			var local_pos := get_local_mouse_position()
			var gp := world_to_grid(local_pos)
			if _is_valid(gp) and gp != _preview_center:
				_update_selection_preview(gp)
			elif not _is_valid(gp):
				_clear_selection_hover_preview()
				_preview_center = Vector2i(-1, -1)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var local_pos := get_local_mouse_position()
			var gp := world_to_grid(local_pos)
			if _cell_accepts_block(gp):
				var clicked_block: Block = grid[gp.x][gp.y]
				var positions := _get_selection_positions(gp)
				if positions.is_empty():
					_clear_selection_hover_preview()
					_preview_center = Vector2i(-1, -1)
					return
				if positions.size() <= 1 and _is_static_obstacle(clicked_block):
					_shake_block(clicked_block)
					return
				if _selection_max_count > 1:
					for p in positions:
						if not _selection_selected_positions.has(p):
							_selection_selected_positions.append(p)
					_update_selection_preview(gp)
					if _selection_selected_positions.size() >= _selection_max_count:
						var selected: Array = _selection_selected_positions.slice(0, _selection_max_count)
						_finish_selection(selected, false)
						selection_confirmed.emit(selected)
					return
				_finish_selection(positions, false)
				selection_confirmed.emit(positions)
		return

	# ── 長按追蹤中：處理放開、移動 ──
	if _longpress_pos != Vector2i(-1, -1):
		if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if _longpress_active:
				# 長按預覽中放開 → 隱藏預覽，不觸發點擊
				_hide_blast_preview()
			else:
				# 未達長按閾值就放開 → 觸發原本的點擊
				var saved_pos: Vector2i = _longpress_pos
				_longpress_pos = Vector2i(-1, -1)
				_longpress_timer = 0.0
				if not is_busy:
					_handle_click(saved_pos)
				return
			_longpress_pos = Vector2i(-1, -1)
			_longpress_timer = 0.0
			return
		if event is InputEventMouseMotion:
			var local_pos := get_local_mouse_position()
			var gp := world_to_grid(local_pos)
			if gp != _longpress_pos:
				# 移出格子 → 取消長按追蹤
				if _longpress_active:
					_hide_blast_preview()
				_longpress_pos = Vector2i(-1, -1)
				_longpress_timer = 0.0
			return
		return

	if is_busy:
		# 融合動畫期間允許立即觸發並行融合
		if is_fusing and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var fuse_local_pos := get_local_mouse_position()
			var fuse_gp := world_to_grid(fuse_local_pos)
			if _cell_accepts_block(fuse_gp):
				_try_concurrent_fuse(fuse_gp, fuse_local_pos)
			return
		if _input_queue_locked:
			return
		# 逃脫/無敵人關卡沒有敵人攻擊節奏可吸收預輸入；busy 期間直接忽略點擊。
		if _is_no_enemy_mode():
			return
		# State/UI 分離：在動畫期間預先 queue 普通爆破點擊
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var queue_local_pos := get_local_mouse_position()
			var queue_gp := world_to_grid(queue_local_pos)
			if _cell_accepts_block(queue_gp):
				_try_queue_click(queue_gp)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_pos := get_local_mouse_position()
		var gp := world_to_grid(local_pos)
		if _cell_accepts_block(gp) and grid[gp.x][gp.y] != null:
			var clicked_block: Block = grid[gp.x][gp.y]
			set_last_tapped_input(gp, local_pos)
			if _is_player_upper_gem(clicked_block):
				# 高階寶石 → 開始長按追蹤（延遲點擊）
				_longpress_pos = gp
				_longpress_timer = 0.0
				_longpress_active = false
				return
			_handle_click(gp)


# ── 邏輯端 BFS / Queue / Drain（State/UI 分離）────────────────────

## 從起始位置在 logic_grid 上找連通同色普通寶石（與 _find_connected 同 BFS 邏輯，但讀邏輯狀態）
func _find_connected_logic(start: Vector2i) -> Array[Vector2i]:
	if not _cell_accepts_block(start):
		return []
	var target: int = logic_grid[start.x][start.y]
	if _logic_value_blocks_matching(target):
		return []
	var visited := {}
	var connected: Array[Vector2i] = []
	var queue: Array[Vector2i] = [start]
	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		if visited.has(current):
			continue
		if not _cell_accepts_block(current):
			continue
		var cur: int = logic_grid[current.x][current.y]
		if cur != target:
			continue
		visited[current] = true
		connected.append(current)
		queue.append(Vector2i(current.x + 1, current.y))
		queue.append(Vector2i(current.x - 1, current.y))
		queue.append(Vector2i(current.x, current.y + 1))
		queue.append(Vector2i(current.x, current.y - 1))
	return connected


## 邏輯端 destroy + collapse：消除指定位置，現有寶石下移，頂部標記為 UNKNOWN
## 同時將鄰格的 PLANK 也標記為 UNKNOWN（與 _destroy_blocks 行為一致，避免 queue 預測錯位）
func _logic_destroy_and_collapse(positions: Array[Vector2i]) -> void:
	for p in positions:
		logic_grid[p.x][p.y] = LOGIC_UNKNOWN
	# 鄰格可破壞障礙也視為被消除
	const NEIGHBOR_DIRS: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for p in positions:
		for d in NEIGHBOR_DIRS:
			var np: Vector2i = p + d
			if not _is_valid(np):
				continue
			if _logic_value_is_breakable_structure(int(logic_grid[np.x][np.y])):
				logic_grid[np.x][np.y] = LOGIC_UNKNOWN
	_settle_logic_grid_with_rocks()


func _settle_logic_grid_with_rocks() -> void:
	var max_iterations: int = maxi(1, columns * rows * (columns + rows + 4))
	var spawn_counts: Array = []
	spawn_counts.resize(columns)
	for column_index in columns:
		spawn_counts[column_index] = 0
	var iteration: int = 0
	while iteration < max_iterations:
		var changed: bool = false
		if _logic_apply_vertical_fall_step():
			changed = true
		if _logic_apply_rock_slide_step(iteration):
			changed = true
		if _logic_spawn_top_unknowns(spawn_counts):
			changed = true
		if not changed:
			break
		iteration += 1
	if iteration >= max_iterations:
		push_warning("Logic collapse reached iteration limit; leaving current settled state.")

	for column_index in columns:
		for row_index in rows:
			if int(logic_grid[column_index][row_index]) == LOGIC_SPAWNED_UNKNOWN:
				logic_grid[column_index][row_index] = LOGIC_UNKNOWN


func _logic_apply_vertical_fall_step() -> bool:
	var moved: bool = false
	for row_index in range(rows - 2, -1, -1):
		for column_index in columns:
			var value: int = int(logic_grid[column_index][row_index])
			if not _logic_cell_can_move(value):
				continue
			if int(logic_grid[column_index][row_index + 1]) != LOGIC_UNKNOWN:
				continue
			logic_grid[column_index][row_index + 1] = value
			logic_grid[column_index][row_index] = LOGIC_UNKNOWN
			moved = true
	return moved


func _logic_apply_rock_slide_step(iteration: int) -> bool:
	var moved: bool = false
	for row_index in range(rows - 2, -1, -1):
		for column_index in columns:
			var value: int = int(logic_grid[column_index][row_index])
			if not _logic_cell_can_move(value):
				continue
			if int(logic_grid[column_index][row_index + 1]) == LOGIC_UNKNOWN:
				continue
			var first_direction: int = -1 if (column_index + row_index + iteration) % 2 == 0 else 1
			var slide_directions: Array[int] = [first_direction, -first_direction]
			for direction in slide_directions:
				if not _logic_can_slide_under_rock(column_index, row_index, direction):
					continue
				var target_x: int = column_index + direction
				var target_y: int = row_index + 1
				logic_grid[target_x][target_y] = value
				logic_grid[column_index][row_index] = LOGIC_UNKNOWN
				moved = true
				break
	return moved


func _logic_can_slide_under_rock(source_x: int, source_y: int, direction: int) -> bool:
	var target_x: int = source_x + direction
	var target_y: int = source_y + 1
	if target_x < 0 or target_x >= columns or target_y < 0 or target_y >= rows:
		return false
	if int(logic_grid[target_x][target_y]) != LOGIC_UNKNOWN:
		return false
	return _logic_target_has_stationary_roof(target_x, target_y)


func _logic_target_has_stationary_roof(target_x: int, target_y: int) -> bool:
	var row_index: int = target_y - 1
	while row_index >= 0:
		var value: int = int(logic_grid[target_x][row_index])
		if value == LOGIC_UNKNOWN or value == LOGIC_HOLE:
			row_index -= 1
			continue
		return _logic_value_is_stationary_obstacle(value)
	return false


func _logic_spawn_top_unknowns(spawn_counts: Array) -> bool:
	var spawned: bool = false
	for column_index in columns:
		if int(spawn_counts[column_index]) >= _get_drop_spawn_capacity(column_index):
			continue
		var spawn_row: int = _get_drop_start_row(column_index)
		if int(logic_grid[column_index][spawn_row]) != LOGIC_UNKNOWN:
			continue
		logic_grid[column_index][spawn_row] = LOGIC_SPAWNED_UNKNOWN
		spawn_counts[column_index] = int(spawn_counts[column_index]) + 1
		spawned = true
	return spawned


func _logic_cell_can_move(value: int) -> bool:
	return value != LOGIC_UNKNOWN and value != LOGIC_HOLE and not _logic_value_is_stationary_obstacle(value)


func _logic_value_is_stationary_obstacle(value: int) -> bool:
	return value == LOGIC_ROCK or value == LOGIC_WOOD_STRUCTURE


func _logic_value_is_breakable_structure(value: int) -> bool:
	return value == LOGIC_PLANK or value == LOGIC_WOOD_STRUCTURE


func _logic_value_blocks_matching(value: int) -> bool:
	return value == LOGIC_UNKNOWN \
		or value == LOGIC_UPPER \
		or value == LOGIC_PLANK \
		or value == LOGIC_ROCK \
		or value == LOGIC_WOOD_STRUCTURE \
		or value == LOGIC_ESCAPE_MARKER \
		or value == LOGIC_HOLE


## 預測：此次爆破是否會觸發任何融合（回應）技能
func _logic_would_trigger_fuse(gem_type: int, count: int) -> bool:
	for skill: Dictionary in _fuse_skills:
		if int(skill.gem_type) == gem_type and count >= int(skill.threshold):
			return true
	return false


## 嘗試將點擊放入 deferred queue（is_busy 期間呼叫）。
func _try_queue_click(pos: Vector2i) -> void:
	if _selection_mode:
		return
	if is_fusing:
		return
	if battle_manager_ref == null:
		return
	if not battle_manager_ref.logic_can_blast():
		return
	if not _cell_accepts_block(pos):
		return
	if _tutorial_filter.size() > 0 and not _tutorial_filter.has(pos):
		return
	# 允許在動畫期間 queue 高階寶石點擊（normal blast → upper blast 路線）
	var b: Block = grid[pos.x][pos.y]
	if _is_static_obstacle(b):
		return
	if b != null and b.is_upper_gem():
		deferred_clicks.append(pos)
		return
	var t: int = logic_grid[pos.x][pos.y]
	if _logic_value_blocks_matching(t):
		return
	var matches := _find_connected_logic(pos)
	if matches.size() < min_match:
		return
	# 不 queue 會觸發融合的爆破（讓融合管線在 is_busy 結束後正常處理）
	if _logic_would_trigger_fuse(t, matches.size()):
		return
	# 通過驗證 — 即時更新邏輯狀態並 enqueue
	_logic_destroy_and_collapse(matches)
	battle_manager_ref.logic_apply_blast(t, matches.size())
	deferred_clicks.append(pos)


## 從 deferred queue 取出下一個點擊並執行（is_busy 變為 false 時自動觸發）
func _drain_deferred_clicks() -> void:
	if _draining or is_busy:
		return
	if _block_input_after_defeat():
		return
	if deferred_clicks.is_empty():
		return
	if is_fusing or _selection_mode:
		return
	# 若下一筆是高階寶石，需等 attack worker 也空閒才 drain（避免敵人攻擊與 upper chain 重疊）
	var next_pos: Vector2i = deferred_clicks[0]
	if _is_valid(next_pos):
		var nb: Block = grid[next_pos.x][next_pos.y]
		if nb != null and nb.is_upper_gem() and external_attack_busy:
			return
	_draining = true
	var pos: Vector2i = deferred_clicks.pop_front()
	_draining = false
	if not _is_valid(pos):
		return
	var b: Block = grid[pos.x][pos.y]
	if b == null:
		return
	# 高階寶石仍允許從 queue 觸發（normal → upper 路線）
	_next_click_is_drained = true
	_handle_click(pos)


## 由 main.gd 在 attack worker 結束時呼叫，嘗試 drain 高階寶石點擊
func notify_external_attack_busy(busy: bool) -> void:
	external_attack_busy = busy
	if _player_is_defeated():
		clear_deferred_clicks()
		return
	if not busy and not is_busy:
		call_deferred("_drain_deferred_clicks")


## 處理寶石點擊事件
## 如果是高階寶石 → 觸發特殊爆炸
## 如果連接數 >= min_match → 消除並掉落填充
## 否則 → 抖動提示無效
func _handle_click(pos: Vector2i) -> void:	# 教學過濾：只允許指定位置
	if _block_input_after_defeat():
		return
	if not _cell_accepts_block(pos):
		return
	if _tutorial_filter.size() > 0 and not _tutorial_filter.has(pos):
		return

	var block: Block = grid[pos.x][pos.y]
	if last_tapped_pos != pos or last_tapped_local_pos.x < 0.0:
		set_last_tapped_input(pos, grid_to_world(pos))
	else:
		last_tapped_pos = pos

	# PLANK / ROCK — 不响應點擊，不消耗回合；播放抖動表示無效
	if _is_static_obstacle(block):
		play_rejected_cell_animation(pos)
		_next_click_is_drained = false
		return

	if block != null and block.is_enemy_upper_gem():
		play_rejected_cell_animation(pos)
		_next_click_is_drained = false
		is_busy = false
		return

	# 高階寶石 — 特殊點擊（消耗一回合，觸發範圍/橫列爆炸並可連鏈）
	if block.is_upper_gem():
		_next_click_is_drained = false
		is_busy = true
		await _handle_upper_click(pos)
		_blast_refill_armed = true
		await _collapse_and_fill()
		# is_busy 由 main.gd _on_upper_blast_completed 在攻擊動畫結束後解除
		return

	# State/UI 分離：直接點擊也檢查邏輯阻擋（敵人全死 / 即將敵人攻擊）
	if not _next_click_is_drained and battle_manager_ref != null and not battle_manager_ref.logic_can_blast():
		_next_click_is_drained = false
		return

	var matches := _find_connected(pos)
	if matches.is_empty():
		# 寶石抖動提示無效操作
		if block:
			play_rejected_cell_animation(pos)
		_next_click_is_drained = false
		return

	# 通過 match 檢查後立即鎖住輸入；逃脫/無敵人模式尤其需要等掉落補滿後才還控制權。
	if _is_no_enemy_mode():
		_escape_refill_input_lock = true
	is_busy = true

	# 邏輯狀態同步：若此次點擊不是來自 drain queue，需即時更新邏輯狀態
	# （drain 來的點擊在 _try_queue_click 已預先套用過邏輯狀態）
	if not _next_click_is_drained:
		_logic_destroy_and_collapse(matches)
		if battle_manager_ref != null and not block.is_upper_gem():
			battle_manager_ref.logic_apply_blast(int(block.block_type), matches.size())
	_next_click_is_drained = false

	_destroy_blocks(matches)          # 非阻塞 — 啟動動畫並延遲釋放
	if skip_collapse:
		# 融合流程 — main.gd 會在放置高階寶石後呼叫 do_collapse()
		_escape_refill_input_lock = false
		return
	_blast_refill_armed = true
	await _collapse_and_fill()        # 掉落立即開始
	# State/UI 分離：destroy + collapse 完成後立即解鎖，讓下一個 queued click 可開始
	# （角色攻擊與 VFX 由 main.gd 在 attack queue 中以 fire-and-forget 並行播放）
	_escape_refill_input_lock = false
	is_busy = false


## 從起始位置開始，找出所有相連的同類型寶石（BFS 洪水填充）
func _find_connected(start: Vector2i) -> Array[Vector2i]:
	if not _cell_accepts_block(start):
		return []
	var block: Block = grid[start.x][start.y]
	if block == null:
		return []
	# 障礙物不參與任何配對
	if block.is_obstacle():
		return []

	var target_type = block.block_type
	var visited := {}
	var connected: Array[Vector2i] = []
	var queue: Array[Vector2i] = [start]

	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()

		if visited.has(current):
			continue
		if not _cell_accepts_block(current):
			continue
		if grid[current.x][current.y] == null:
			continue
		var cur_block: Block = grid[current.x][current.y]
		if cur_block.block_type != target_type:
			continue
		# 高階寶石不參與普通配對 — 跳過
		if cur_block.is_upper_gem():
			continue
		# 障礙物不參與 — 跳過
		if cur_block.is_obstacle():
			continue

		visited[current] = true
		connected.append(current)

		queue.append(Vector2i(current.x + 1, current.y))
		queue.append(Vector2i(current.x - 1, current.y))
		queue.append(Vector2i(current.x, current.y + 1))
		queue.append(Vector2i(current.x, current.y - 1))

	return connected


## 消除指定位置的寶石：計算得分、發出信號、播放動畫、延遲釋放節點
## 同時掃描鄰格，若有可破壞障礙則靜默移除（無得分、無信號、無攻擊）
func _destroy_blocks(positions: Array[Vector2i]) -> void:
	var gem_type: Block.Type = grid[positions[0].x][positions[0].y].block_type
	var blocks: Array = []
	var blast_positions: Array = []
	var effective_count: int = 0  # X5 等額外效果加成後的數量
	for pos in positions:
		var block: Block = grid[pos.x][pos.y]
		if block:
			blast_positions.append(block.global_position)
			effective_count += block.get_blast_value()
			grid[pos.x][pos.y] = null
			blocks.append(block)

	# 鄰格可破壞障礙靜默移除（不計分、不發信號）
	var planks_to_remove: Array = []
	var plank_seen: Dictionary = {}
	const NEIGHBOR_DIRS: Array = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for pos in positions:
		for d in NEIGHBOR_DIRS:
			var np: Vector2i = pos + d
			if not _is_valid(np):
				continue
			var key: int = np.x * 1000 + np.y
			if plank_seen.has(key):
				continue
			var nb: Block = grid[np.x][np.y]
			if nb != null and nb.is_breakable_structure():
				plank_seen[key] = true
				grid[np.x][np.y] = null
				planks_to_remove.append(nb)
				# 邏輯端同步：標記為 UNKNOWN 讓崩落補位
				logic_grid[np.x][np.y] = LOGIC_UNKNOWN
				nb.play_destroy_animation()
				_spawn_plank_debris(nb.global_position)

	score += positions.size() * 10
	score_changed.emit(score)
	gems_blasted.emit(gem_type, effective_count, blast_positions)
	var goal_blocks: Array = blocks.duplicate()
	goal_blocks.append_array(planks_to_remove)
	_emit_goal_cells_for_blocks(goal_blocks)

	for block in blocks:
		_play_gem_break_debris(block)

	# 動畫結束後釋放寶石節點 — 非阻塞，讓掉落立即開始
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		for b in blocks:
			if is_instance_valid(b):
				b.queue_free()
		for p in planks_to_remove:
			if is_instance_valid(p):
				p.queue_free()
	, CONNECT_ONE_SHOT)


## 掉落與填充：新寶石只從棋盤頂部進入；ROCK 下方空洞只能靠鄰欄斜向滑入
func _queue_floating_fused_upper_gem(block: Block, pos: Vector2i) -> void:
	if not is_instance_valid(block) or not _is_valid(pos):
		return
	for i in range(_floating_fused_upper_gems.size() - 1, -1, -1):
		var entry: Dictionary = _floating_fused_upper_gems[i]
		var raw_queued_block: Variant = entry.get("block", null)
		if not is_instance_valid(raw_queued_block):
			_floating_fused_upper_gems.remove_at(i)
			continue
		var queued_block: Block = raw_queued_block as Block
		if queued_block == null:
			_floating_fused_upper_gems.remove_at(i)
			continue
		if queued_block == block:
			entry["pos"] = pos
			_floating_fused_upper_gems[i] = entry
			return
	_floating_fused_upper_gems.append({
		"block": block,
		"pos": pos,
	})


func _prepare_fuse_collapse_solution() -> Array[Dictionary]:
	match ACTIVE_FUSE_SOLUTION:
		FUSE_SOLUTION_1:
			return _fuse_solution1_prepare_collapse()
		FUSE_SOLUTION_2:
			return _fuse_solution2_prepare_collapse()
		FUSE_SOLUTION_3:
			return _fuse_solution3_prepare_collapse()
		_:
			push_warning("未知的融合坍塌方案，改用 fuseSolution3。")
			return _fuse_solution3_prepare_collapse()


func _finish_fuse_collapse_solution(solution_state: Array[Dictionary]) -> void:
	match ACTIVE_FUSE_SOLUTION:
		FUSE_SOLUTION_1:
			_fuse_solution1_finish_collapse(solution_state)
		FUSE_SOLUTION_2:
			_fuse_solution2_finish_collapse(solution_state)
		FUSE_SOLUTION_3:
			_fuse_solution3_finish_collapse(solution_state)
		_:
			_fuse_solution3_finish_collapse(solution_state)


# fuseSolution1：保留舊版融合方式。
# 高階寶石放在 grid 裡直接參與坍塌，因此下方有空格時會跟著掉落。
# 目前不呼叫這個方案；若想切回舊版，把 ACTIVE_FUSE_SOLUTION 改成 FUSE_SOLUTION_1。
func _fuse_solution1_prepare_collapse() -> Array[Dictionary]:
	_floating_fused_upper_gems.clear()
	var empty_state: Array[Dictionary] = []
	return empty_state


func _fuse_solution1_finish_collapse(_solution_state: Array[Dictionary]) -> void:
	pass


# fuseSolution2：上一版融合方式。
# 坍塌前先把融合出的高階寶石從 grid 暫時抽離，原融合格放固定佔位；
# 這能保證高階寶石回到原格，但固定佔位會像屋頂一樣影響斜向滑落。
func _fuse_solution2_prepare_collapse() -> Array[Dictionary]:
	var lifted: Array[Dictionary] = []
	if _floating_fused_upper_gems.is_empty():
		return lifted
	var pending := _floating_fused_upper_gems.duplicate()
	_floating_fused_upper_gems.clear()
	for entry in pending:
		var raw_block: Variant = entry.get("block", null)
		var pos: Vector2i = entry.get("pos", Vector2i(-1, -1)) as Vector2i
		if not is_instance_valid(raw_block) or not _is_valid(pos):
			continue
		var block: Block = raw_block as Block
		if block == null:
			continue
		if grid[pos.x][pos.y] != block:
			continue
		grid[pos.x][pos.y] = FLOATING_UPPER_PLACEHOLDER
		block.grid_pos = pos
		block.set_board_columns(columns)
		block.position = grid_to_world(pos)
		lifted.append({
			"block": block,
			"pos": pos,
			"z_index": block.z_index,
		})
		block.z_index = maxi(block.z_index, FLOATING_UPPER_Z_INDEX)
	return lifted


func _fuse_solution2_finish_collapse(solution_state: Array[Dictionary]) -> void:
	for entry in solution_state:
		var raw_block: Variant = entry.get("block", null)
		var pos: Vector2i = entry.get("pos", Vector2i(-1, -1)) as Vector2i
		if not is_instance_valid(raw_block) or not _is_valid(pos):
			if _is_valid(pos) and grid[pos.x][pos.y] == FLOATING_UPPER_PLACEHOLDER:
				grid[pos.x][pos.y] = null
			continue
		var block: Block = raw_block as Block
		if block == null:
			if grid[pos.x][pos.y] == FLOATING_UPPER_PLACEHOLDER:
				grid[pos.x][pos.y] = null
			continue
		grid[pos.x][pos.y] = block
		block.grid_pos = pos
		block.set_board_columns(columns)
		block.position = grid_to_world(pos)
		block.z_index = int(entry.get("z_index", block.z_index))


# fuseSolution3：目前新版融合方式。
# 坍塌前先把融合出的高階寶石從 grid 暫時抽離，不放任何佔位，所以它不會形成「屋頂」
# 來觸發斜向滑落；坍塌與補寶石結束後，再於同欄把上方連續格往上推一格，將高階寶石插回原本融合格。
func _fuse_solution3_prepare_collapse() -> Array[Dictionary]:
	var lifted: Array[Dictionary] = []
	if _floating_fused_upper_gems.is_empty():
		return lifted
	var pending := _floating_fused_upper_gems.duplicate()
	_floating_fused_upper_gems.clear()
	for entry in pending:
		var raw_block: Variant = entry.get("block", null)
		var pos: Vector2i = entry.get("pos", Vector2i(-1, -1)) as Vector2i
		if not is_instance_valid(raw_block) or not _is_valid(pos):
			continue
		var block: Block = raw_block as Block
		if block == null:
			continue
		if grid[pos.x][pos.y] != block:
			continue
		grid[pos.x][pos.y] = null
		block.grid_pos = pos
		block.set_board_columns(columns)
		block.position = grid_to_world(pos)
		lifted.append({
			"block": block,
			"pos": pos,
			"z_index": block.z_index,
		})
		block.z_index = maxi(block.z_index, FLOATING_UPPER_Z_INDEX)
	return lifted


func _fuse_solution3_finish_collapse(solution_state: Array[Dictionary]) -> void:
	for entry in solution_state:
		var raw_block: Variant = entry.get("block", null)
		var pos: Vector2i = entry.get("pos", Vector2i(-1, -1)) as Vector2i
		if not is_instance_valid(raw_block) or not _is_valid(pos):
			continue
		var block: Block = raw_block as Block
		if block == null:
			continue
		_insert_floating_upper_gem_after_collapse(block, pos, int(entry.get("z_index", block.z_index)))


func _insert_floating_upper_gem_after_collapse(block: Block, pos: Vector2i, restore_z_index: int) -> void:
	if not is_instance_valid(block) or not _cell_accepts_block(pos) or is_escape_marker_pos(pos):
		return
	var current_raw: Variant = grid[pos.x][pos.y]
	if current_raw != null and not is_instance_valid(current_raw):
		grid[pos.x][pos.y] = null
	elif is_instance_valid(current_raw):
		var current: Block = current_raw as Block
		if current != null and current.is_stationary_obstacle():
			return
	var top_y: int = pos.y
	while top_y > 0:
		var above := Vector2i(pos.x, top_y - 1)
		if not _cell_accepts_block(above) or is_escape_marker_pos(above):
			break
		var above_raw: Variant = grid[above.x][above.y]
		if above_raw != null and not is_instance_valid(above_raw):
			grid[above.x][above.y] = null
		elif is_instance_valid(above_raw):
			var above_block: Block = above_raw as Block
			if above_block != null and above_block.is_stationary_obstacle():
				break
		top_y -= 1
	var removed_raw: Variant = grid[pos.x][top_y]
	if is_instance_valid(removed_raw):
		var removed_block: Block = removed_raw as Block
		if removed_block != null and removed_block != block:
			removed_block.queue_free()
	for y in range(top_y, pos.y):
		var moved_raw: Variant = grid[pos.x][y + 1]
		if moved_raw != null and not is_instance_valid(moved_raw):
			moved_raw = null
		grid[pos.x][y] = moved_raw
		if is_instance_valid(moved_raw):
			var moved_block: Block = moved_raw as Block
			if moved_block == null:
				continue
			var moved_pos := Vector2i(pos.x, y)
			moved_block.grid_pos = moved_pos
			moved_block.set_board_columns(columns)
			moved_block.position = grid_to_world(moved_pos)
	grid[pos.x][pos.y] = block
	block.grid_pos = pos
	block.set_board_columns(columns)
	block.position = grid_to_world(pos)
	block.z_index = restore_z_index


func _collapse_and_fill() -> void:
	_collapse_and_fill_running = true
	var fuse_solution_state := _prepare_fuse_collapse_solution()
	var collapse_plan: Dictionary = _build_collapse_plan()
	var fall_moves: Array = collapse_plan.get("falls", [])
	var total_new_count: int = int(collapse_plan.get("new_count", 0))
	var longest_dur: float = 0.0
	var marker_rows_dropped: int = 0

	# 在填入新寶石前觸發前置回呼，例如燃燒扣血。
	var any_new: bool = total_new_count > 0
	if any_new and pre_refill_hook.is_valid():
		await pre_refill_hook.call()
		if battle_manager_ref != null and int(battle_manager_ref.get("player_current_hp")) <= 0:
			_finish_fuse_collapse_solution(fuse_solution_state)
			_collapse_and_fill_running = false
			_sync_logic_unknowns_from_visual()
			_update_fuse_hints()
			return

	for fall_data in fall_moves:
		var from_pos: Vector2
		var target_pos: Vector2 = fall_data.to_pos
		if bool(fall_data.get("is_escape_marker", false)):
			if not is_instance_valid(_escape_marker_node):
				continue
			from_pos = _escape_marker_node.position
			var marker_dist: float = from_pos.distance_to(target_pos)
			var marker_dur: float = marker_dist / FALL_SPEED
			longest_dur = maxf(longest_dur, marker_dur)
			marker_rows_dropped += int(fall_data.get("rows_dropped", 0))
			if marker_dist >= 0.5:
				var marker_tw := create_tween()
				marker_tw.tween_property(_escape_marker_node, "position", target_pos, marker_dur) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			continue
		if bool(fall_data.is_new):
			var spawn_x: int = int(fall_data.spawn_x)
			var spawn_idx: int = int(fall_data.spawn_idx)
			var spawn_y: int = int(fall_data.get("spawn_y", -1 - spawn_idx))
			from_pos = grid_to_world(Vector2i(spawn_x, spawn_y))
		else:
			if not is_instance_valid(fall_data.block):
				continue
			from_pos = fall_data.block.position

		var dist: float = from_pos.distance_to(target_pos)
		if dist < 0.5:
			continue
		var dur: float = dist / FALL_SPEED
		longest_dur = maxf(longest_dur, dur)

		if bool(fall_data.is_new):
			var block: Block = _create_block(int(fall_data.gx), int(fall_data.gy), from_pos, true)
			block.modulate.a = 0.0
			block.fall_to(target_pos, dur, 0.0, true)
		else:
			fall_data.block.fall_to(target_pos, dur, 0.0, false)

	if longest_dur == 0.0:
		_finish_fuse_collapse_solution(fuse_solution_state)
		_sync_logic_unknowns_from_visual()
		_update_fuse_hints()
		_collapse_and_fill_running = false
		if marker_rows_dropped > 0 and not _suppress_escape_marker_progress:
			escape_marker_moved.emit(marker_rows_dropped)
		return
	if total_new_count > 0:
		gems_refilled.emit(total_new_count)
	await get_tree().create_timer(longest_dur + Block.BOUNCE_DUR + 0.05).timeout
	_finish_fuse_collapse_solution(fuse_solution_state)
	_sync_logic_unknowns_from_visual()
	_update_fuse_hints()
	_collapse_and_fill_running = false
	if marker_rows_dropped > 0 and not _suppress_escape_marker_progress:
		escape_marker_moved.emit(marker_rows_dropped)


func _build_collapse_plan() -> Dictionary:
	var state: Array = _copy_grid_state()
	var spawn_counts: Array = []
	spawn_counts.resize(columns)
	for column_index in columns:
		spawn_counts[column_index] = 0

	_settle_visual_state_with_rocks(state, spawn_counts, true)

	var fall_moves: Array = []
	var new_count: int = 0
	for column_index in columns:
		for row_index in rows:
			var cell: Variant = state[column_index][row_index]
			var target_grid_pos: Vector2i = Vector2i(column_index, row_index)
			if cell is Block:
				var block: Block = cell as Block
				grid[column_index][row_index] = block
				if block.is_stationary_obstacle():
					block.grid_pos = target_grid_pos
					block.set_board_columns(columns)
					block.position = grid_to_world(target_grid_pos)
					continue
				var original_grid_pos: Vector2i = block.grid_pos
				block.grid_pos = target_grid_pos
				block.set_board_columns(columns)
				if original_grid_pos != target_grid_pos:
					fall_moves.append({
						block = block,
						to_pos = grid_to_world(target_grid_pos),
						is_new = false
					})
			elif cell is Dictionary:
				var cell_data: Dictionary = cell
				if bool(cell_data.get("escape_marker", false)):
					var old_y: int = int(cell_data.get("original_y", row_index))
					var new_pos := Vector2i(column_index, row_index)
					var dropped_rows: int = maxi(row_index - old_y, 0)
					_escape_marker_pos = new_pos
					if dropped_rows > 0:
						fall_moves.append({
							to_pos = grid_to_world(new_pos),
							is_escape_marker = true,
							rows_dropped = dropped_rows,
							is_new = false
						})
					else:
						_position_escape_marker_node(false)
					grid[column_index][row_index] = null
					continue
				var spawn_x: int = int(cell_data["spawn_x"])
				grid[column_index][row_index] = null
				new_count += 1
				fall_moves.append({
					to_pos = grid_to_world(target_grid_pos),
					is_new = true,
					gx = column_index,
					gy = row_index,
					spawn_x = spawn_x,
					spawn_y = int(cell_data.get("spawn_y", -1 - int(cell_data["spawn_idx"]))),
					spawn_idx = int(cell_data["spawn_idx"]),
					spawn_count = int(spawn_counts[spawn_x])
				})
			else:
				grid[column_index][row_index] = null
	return {"falls": fall_moves, "new_count": new_count}


func _copy_grid_state() -> Array:
	var state: Array = []
	state.resize(columns)
	for column_index in columns:
		state[column_index] = []
		state[column_index].resize(rows)
		for row_index in rows:
			var pos := Vector2i(column_index, row_index)
			if _is_hole_pos(pos):
				state[column_index][row_index] = VISUAL_HOLE
			elif is_escape_marker_pos(pos):
				state[column_index][row_index] = {"escape_marker": true, "original_y": row_index}
			else:
				state[column_index][row_index] = grid[column_index][row_index]
	return state


func _settle_visual_state_with_rocks(state: Array, spawn_counts: Array, spawn_from_top: bool) -> void:
	var max_iterations: int = maxi(1, columns * rows * (columns + rows + 4))
	var iteration: int = 0
	while iteration < max_iterations:
		var changed: bool = false
		if _visual_apply_vertical_fall_step(state):
			changed = true
		if _visual_apply_rock_slide_step(state, iteration):
			changed = true
		if spawn_from_top and _visual_spawn_top_blocks(state, spawn_counts):
			changed = true
		if not changed:
			break
		iteration += 1
	if iteration >= max_iterations:
		push_warning("Visual collapse reached iteration limit; leaving current settled state.")


func _visual_apply_vertical_fall_step(state: Array) -> bool:
	var moved: bool = false
	for row_index in range(rows - 2, -1, -1):
		for column_index in columns:
			var cell: Variant = state[column_index][row_index]
			if not _variant_cell_can_move(cell):
				continue
			if state[column_index][row_index + 1] != null:
				continue
			state[column_index][row_index + 1] = cell
			state[column_index][row_index] = null
			moved = true
	return moved


func _visual_apply_rock_slide_step(state: Array, iteration: int) -> bool:
	var moved: bool = false
	for row_index in range(rows - 2, -1, -1):
		for column_index in columns:
			var cell: Variant = state[column_index][row_index]
			if not _variant_cell_can_move(cell):
				continue
			if state[column_index][row_index + 1] == null:
				continue
			var first_direction: int = -1 if (column_index + row_index + iteration) % 2 == 0 else 1
			var slide_directions: Array[int] = [first_direction, -first_direction]
			for direction in slide_directions:
				if not _visual_can_slide_under_rock(state, column_index, row_index, direction):
					continue
				var target_x: int = column_index + direction
				var target_y: int = row_index + 1
				state[target_x][target_y] = cell
				state[column_index][row_index] = null
				moved = true
				break
	return moved


func _visual_can_slide_under_rock(state: Array, source_x: int, source_y: int, direction: int) -> bool:
	var target_x: int = source_x + direction
	var target_y: int = source_y + 1
	if target_x < 0 or target_x >= columns or target_y < 0 or target_y >= rows:
		return false
	if state[target_x][target_y] != null:
		return false
	return _visual_target_has_stationary_roof(state, target_x, target_y)


func _visual_target_has_stationary_roof(state: Array, target_x: int, target_y: int) -> bool:
	var row_index: int = target_y - 1
	while row_index >= 0:
		var cell: Variant = state[target_x][row_index]
		if cell == null or _variant_cell_is_hole(cell):
			row_index -= 1
			continue
		return _variant_cell_is_stationary_obstacle(cell)
	return false


func _visual_spawn_top_blocks(state: Array, spawn_counts: Array) -> bool:
	var spawned: bool = false
	for column_index in columns:
		if int(spawn_counts[column_index]) >= _get_drop_spawn_capacity(column_index):
			continue
		var spawn_row: int = _get_drop_start_row(column_index)
		if state[column_index][spawn_row] != null:
			continue
		state[column_index][spawn_row] = {
			"is_new": true,
			"spawn_x": column_index,
			"spawn_y": spawn_row - 1 - int(spawn_counts[column_index]),
			"spawn_idx": int(spawn_counts[column_index])
		}
		spawn_counts[column_index] = int(spawn_counts[column_index]) + 1
		spawned = true
	return spawned


func _variant_cell_can_move(cell: Variant) -> bool:
	return cell != null and not _variant_cell_is_hole(cell) and not _variant_cell_is_stationary_obstacle(cell)


func _variant_cell_is_stationary_obstacle(cell: Variant) -> bool:
	if cell is StringName and cell == FLOATING_UPPER_PLACEHOLDER:
		return true
	return cell is Block and (cell as Block).is_stationary_obstacle()


func _variant_cell_is_hole(cell: Variant) -> bool:
	return cell is StringName and cell == VISUAL_HOLE


## 重新開始：清除棋盤並重新初始化
func restart() -> void:
	is_busy = true
	_board_input_paused = false
	clear_deferred_clicks()
	score = 0
	score_changed.emit(score)
	for x in columns:
		for y in rows:
			if grid[x][y] != null:
				grid[x][y].queue_free()
				grid[x][y] = null
	initialize_board()
	is_busy = false


## 失敗動畫：寶石全部以拋物線（小幅上拋→落下）散開並旋轉淡出。
## 旋轉與位置同時開始（並行）。鎖定 is_busy 並 await 動畫完成。
func play_lose_animation() -> void:
	is_busy = true
	clear_deferred_clicks()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var max_total: float = 0.0
	var blocks_to_animate: Array[Block] = []
	var seen: Dictionary = {}
	for x in columns:
		for y in rows:
			var block: Block = grid[x][y]
			if block == null or not is_instance_valid(block) or seen.has(block):
				continue
			seen[block] = true
			blocks_to_animate.append(block)
	for child in get_children():
		if child is Block and is_instance_valid(child) and not seen.has(child):
			seen[child] = true
			blocks_to_animate.append(child as Block)
	for block in blocks_to_animate:
		var delay: float = rng.randf_range(0.0, 0.25)
		var jump_h: float = rng.randf_range(40.0, 110.0)
		var dx: float = rng.randf_range(-220.0, 220.0)
		var fall_dy: float = rng.randf_range(700.0, 1000.0)
		var spin: float = rng.randf_range(-PI * 1.6, PI * 1.6)
		var up_dur: float = 0.22
		var down_dur: float = 0.85
		var total_dur: float = up_dur + down_dur
		var start_pos: Vector2 = block.position
		block.z_index = 50
		# 旋轉：與位置動畫同時開始（並行，貫穿整段）
		var spin_tw := create_tween()
		spin_tw.tween_interval(delay)
		spin_tw.tween_property(block, "rotation", spin, total_dur)
		# X 方向：與位置同時開始，整段時間內線性飄移
		var x_tw := create_tween()
		x_tw.tween_interval(delay)
		x_tw.tween_property(block, "position:x", start_pos.x + dx, total_dur) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		# Y 方向：拋物線 — 先上拋（短）再落下（長）
		var y_tw := create_tween()
		y_tw.tween_interval(delay)
		y_tw.tween_property(block, "position:y", start_pos.y - jump_h, up_dur) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		y_tw.tween_property(block, "position:y", start_pos.y + fall_dy, down_dur) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		# 淡出：在落下後段才開始
		var fade_tw := create_tween()
		fade_tw.tween_interval(delay + total_dur - 0.45)
		fade_tw.tween_property(block, "modulate:a", 0.0, 0.45)
		var total: float = delay + total_dur
		if total > max_total:
			max_total = total
	if max_total <= 0.0:
		max_total = 0.4
	await get_tree().create_timer(max_total + 0.05).timeout


## 將 [count] 個寶石轉換為 [to_type] 類型。
## 優先從 [priority_types] 中選取，不足時從其他類型補充。
## 播放縮小→替換→放大 的變身動畫。返回被轉換的位置。
func convert_gems(to_type: Block.Type, count: int, priority_types: Array[Block.Type]) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var fallback: Array[Vector2i] = []

	for x in columns:
		for y in rows:
			var block: Block = grid[x][y]
			if block == null or block.block_type == to_type or block.is_obstacle():
				continue
			if block.block_type in priority_types:
				candidates.append(Vector2i(x, y))
			else:
				fallback.append(Vector2i(x, y))

	# 洗牌並選取最多 count 個
	candidates.shuffle()
	fallback.shuffle()
	var picked: Array[Vector2i] = []
	for pos in candidates:
		if picked.size() >= count:
			break
		picked.append(pos)
	for pos in fallback:
		if picked.size() >= count:
			break
		picked.append(pos)

	# 播放變身動畫
	for pos in picked:
		var block: Block = grid[pos.x][pos.y]
		if block == null:
			continue
		_animate_gem_morph(block, to_type)

	return picked


## 隨機取得可被轉化為 ROCK 的普通寶石格；沒有合法目標時回傳 (-1, -1)
func get_random_rock_transmutation_target() -> Vector2i:
	var candidates: Array[Vector2i] = []
	for x in columns:
		for y in rows:
			var block: Block = grid[x][y]
			if block == null:
				continue
			if block.is_upper_gem() or block.is_obstacle():
				continue
			candidates.append(Vector2i(x, y))

	if candidates.is_empty():
		return Vector2i(-1, -1)

	candidates.shuffle()
	return candidates[0]


## 將指定普通寶石格轉化為 ROCK，並播放 fuse animation
func transmute_cell_to_rock(pos: Vector2i) -> bool:
	if not _is_valid(pos):
		return false
	var block: Block = grid[pos.x][pos.y]
	if block == null:
		return false
	if block.is_upper_gem() or block.is_obstacle():
		return false

	block.clear_extras()
	block.set_upper_type(Block.UpperType.NONE)
	block.set_block_type(Block.Type.ROCK)
	if not deferred_clicks.is_empty():
		clear_deferred_clicks()
		_init_logic_grid_from_visual()
	else:
		_sync_edit_logic_cell(pos, Block.Type.ROCK)
	play_fuse_animation(block)
	_update_fuse_hints()
	return true


## 隨機將一個普通寶石格轉化為 ROCK；沒有合法目標時回傳 (-1, -1)
func transmute_random_cell_to_rock() -> Vector2i:
	var pos: Vector2i = get_random_rock_transmutation_target()
	if pos == Vector2i(-1, -1):
		return pos
	if not transmute_cell_to_rock(pos):
		return Vector2i(-1, -1)
	return pos


## 將棋盤上所有 [from_type] 類型的寶石轉換為 [to_type]。返回轉換數量。
func convert_all_of_type(from_type: Block.Type, to_type: Block.Type) -> int:
	var count := 0
	for x in columns:
		for y in rows:
			var block: Block = grid[x][y]
			if block != null and block.block_type == from_type and not block.is_obstacle():
				_animate_gem_morph(block, to_type)
				count += 1
	return count


## 沉默地消除棋盤上所有指定類型的寶石並填充新寶石。
## 不發出 gems_blasted（不觸發攻擊），不調用 record_blast。
## 回傳被消除的有效爆炸值總和（X5 寶石計為 5）。
func blast_all_of_type(type: Block.Type) -> int:
	is_busy = true
	var positions: Array[Vector2i] = []
	var blocks: Array = []
	var effective_count: int = 0
	for x in columns:
		for y in rows:
			var b: Block = grid[x][y]
			if b != null and b.block_type == type and not b.is_upper_gem() and not b.is_obstacle():
				positions.append(Vector2i(x, y))
				blocks.append(b)
				effective_count += b.get_blast_value()
				grid[x][y] = null
	if blocks.is_empty():
		is_busy = false
		return 0

	for b in blocks:
		_play_gem_break_debris(b)
	_emit_goal_cells_for_blocks(blocks)
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		for b in blocks:
			if is_instance_valid(b):
				b.queue_free()
	, CONNECT_ONE_SHOT)

	await get_tree().create_timer(0.25).timeout
	await _collapse_and_fill()
	is_busy = false
	return effective_count


func drop_random_gems_of_type(type: Block.Type, count: int) -> int:
	var clamped_count: int = maxi(0, count)
	if clamped_count <= 0:
		return 0
	var candidates: Array[Vector2i] = []
	for x in columns:
		for y in rows:
			var block: Block = grid[x][y]
			if block != null and block.block_type == type and not block.is_upper_gem() and not block.is_obstacle():
				candidates.append(Vector2i(x, y))
	if candidates.is_empty():
		return 0

	candidates.shuffle()
	var removed_blocks: Array[Block] = []
	var removed_count: int = mini(clamped_count, candidates.size())
	is_busy = true
	for i in removed_count:
		var pos: Vector2i = candidates[i]
		var block: Block = grid[pos.x][pos.y]
		if block == null or block.is_upper_gem() or block.is_obstacle() or block.block_type != type:
			continue
		grid[pos.x][pos.y] = null
		logic_grid[pos.x][pos.y] = LOGIC_UNKNOWN
		removed_blocks.append(block)
		_play_gem_break_debris(block)

	if removed_blocks.is_empty():
		is_busy = false
		return 0

	_emit_goal_cells_for_blocks(removed_blocks)
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		for block in removed_blocks:
			if is_instance_valid(block):
				block.queue_free()
	, CONNECT_ONE_SHOT)

	await get_tree().create_timer(0.25).timeout
	await _collapse_and_fill()
	is_busy = false
	return removed_blocks.size()


## 公開的「融合/變身」闃光+彈跳動畫—可被任何「變成其它寶石」的流程調用
func play_fuse_animation(block: Block) -> void:
	if block == null or not is_instance_valid(block):
		return
	block.scale = Vector2(1.0, 1.0)
	var tween := create_tween()
	tween.tween_property(block, "scale", Vector2(1.4, 1.4), 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(block, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_BACK)
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.85)
	flash.size = Vector2(CELL_SIZE, CELL_SIZE)
	flash.position = Vector2(-CELL_SIZE * 0.5, -CELL_SIZE * 0.5)
	flash.z_index = 10
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(flash)
	var flash_tw := create_tween()
	flash_tw.tween_property(flash, "color:a", 0.0, 0.2).set_ease(Tween.EASE_IN)
	flash_tw.tween_callback(flash.queue_free)


## 寶石變身動畫：縮小 → 替換類型 → 放大 + 融合闃光/彈跳 → 更新融合提示
func _animate_gem_morph(block: Block, new_type: Block.Type) -> void:
	if block == null or block.is_obstacle():
		return
	var tween := create_tween()
	# 縮小
	tween.tween_property(block, "scale", Vector2(0.3, 0.3), 0.15) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# 在最小點替換類型
	tween.tween_callback(func() -> void:
		block.set_block_type(new_type)
	)
	# 套用統一的「融合」闃光與彈跳動畫（play_fuse_animation 已在同一 scope 內定義）
	tween.tween_callback(func() -> void:
		if is_instance_valid(block):
			play_fuse_animation(block)
	)
	# 動畫完成後更新融合提示（等 fuse 動畫大致結束）
	tween.tween_interval(0.42)
	tween.tween_callback(_update_fuse_hints)


## 靜默移除指定位置的可破壞障礙（無得分、無信號）— 供具有 BREAK 屬性的技能使用
func silently_destroy_breakable_structure(pos: Vector2i) -> bool:
	if pos.x < 0 or pos.x >= columns or pos.y < 0 or pos.y >= rows:
		return false
	var b: Block = grid[pos.x][pos.y]
	if b == null or not b.is_breakable_structure():
		return false
	var origin: Vector2 = b.global_position
	grid[pos.x][pos.y] = null
	logic_grid[pos.x][pos.y] = LOGIC_UNKNOWN
	b.play_destroy_animation()
	_spawn_plank_debris(origin)
	_emit_goal_cells_for_blocks([b])
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		if is_instance_valid(b):
			b.queue_free()
	, CONNECT_ONE_SHOT)
	return true


## 靜默移除指定位置的 PLANK / woodStructure（舊 API 名稱保留給既有技能呼叫）
func silently_destroy_plank(pos: Vector2i) -> bool:
	return silently_destroy_breakable_structure(pos)


func _get_debris_host() -> Node:
	var host: Node = get_tree().current_scene
	if host == null:
		host = self
	return host


func _play_gem_break_debris(block: Block, is_upper_break: bool = false) -> void:
	if block == null:
		return
	var break_texture: Texture2D = null
	var shard_count: int = NORMAL_GEM_DEBRIS_SHARDS
	var scale_range: Vector2 = Vector2(0.70, 1.10)
	var lifetime_range: Vector2 = Vector2(0.55, 0.85)
	if is_upper_break or block.is_upper_gem():
		break_texture = Block.UPPER_GEM_TEXTURES.get(block.upper_type, null)
		if break_texture == null:
			break_texture = block.get_base_texture()
		shard_count = UPPER_GEM_DEBRIS_SHARDS
		scale_range = Vector2(0.78, 1.18)
		lifetime_range = Vector2(0.65, 0.95)
	else:
		break_texture = block.get_base_texture()

	if break_texture == null:
		block.play_destroy_animation()
		return

	DebrisVfx.play(_get_debris_host(), break_texture, block.global_position, shard_count, scale_range, lifetime_range, GEM_DEBRIS_Z_INDEX)
	block.visible = false


## 在指定全域座標生成木屑飛散動畫；由 pooled DebrisVfx 控制總量。
func _spawn_plank_debris(world_pos: Vector2) -> void:
	DebrisVfx.play(_get_debris_host(), PLANK_DEBRIS_TEXTURE, world_pos, OBSTACLE_DEBRIS_SHARDS, Vector2(0.68, 1.10), Vector2(0.90, 1.30), OBSTACLE_DEBRIS_Z_INDEX)


func _is_wood_spear_type(ut: Block.UpperType) -> bool:
	return ut == Block.UpperType.WOOD_SPEAR_UP or ut == Block.UpperType.WOOD_SPEAR_DOWN


func _wood_spear_direction(ut: Block.UpperType) -> int:
	return -1 if ut == Block.UpperType.WOOD_SPEAR_UP else 1


func _handle_wood_spear_sequence(start_pos: Vector2i, chain_data: Array = [], total_blasted_by_type: Dictionary = {}, is_initial: bool = true) -> void:
	if not _is_valid(start_pos):
		return
	var start_block: Block = grid[start_pos.x][start_pos.y]
	if start_block == null:
		return
	var ut: Block.UpperType = start_block.upper_type
	if not _is_wood_spear_type(ut):
		return

	if is_initial:
		chain_data.clear()
		chain_data.append(1)
		total_blasted_by_type.clear()
		upper_gem_clicked.emit()
	elif chain_data.size() > 0:
		chain_data[0] += 1

	upper_gem_chain_triggered.emit(ut)
	var direction_y: int = _wood_spear_direction(ut)
	var positions: Array[Vector2i] = _get_blast_positions_for_upper(start_pos, ut)
	var row_groups: Array[Array] = _build_wood_spear_row_groups(start_pos, positions, direction_y)
	var destination: Vector2i = _wood_spear_destination(start_pos, positions, direction_y)
	var thrust_duration: float = maxf(float(maxi(row_groups.size(), 1)) * WOOD_SPEAR_ROW_HIT_INTERVAL, 0.18)
	_play_wood_spear_thrust(grid_to_world(start_pos), grid_to_world(destination), direction_y, thrust_duration)

	var start_type: Block.Type = start_block.block_type as Block.Type
	var start_value: int = start_block.get_blast_value()
	total_blasted_by_type[start_type] = total_blasted_by_type.get(start_type, 0) + start_value
	gems_blasted.emit(start_type, start_value, [start_block.global_position])
	grid[start_pos.x][start_pos.y] = null
	_play_gem_break_debris(start_block, true)
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		if is_instance_valid(start_block):
			start_block.queue_free()
	, CONNECT_ONE_SHOT)

	var chained_positions: Array[Vector2i] = []
	for group_index in row_groups.size():
		await get_tree().create_timer(WOOD_SPEAR_ROW_HIT_INTERVAL).timeout
		var group: Array = row_groups[group_index]
		_destroy_wood_spear_row_group(group, total_blasted_by_type, chained_positions)

	if row_groups.is_empty():
		await get_tree().create_timer(thrust_duration).timeout

	if not chained_positions.is_empty():
		await _execute_upper_blast_chain(chained_positions, chain_data, total_blasted_by_type)

	if is_initial:
		upper_blast_completed.emit(chain_data[0], total_blasted_by_type, ut)


func _build_wood_spear_row_groups(origin: Vector2i, positions: Array[Vector2i], direction_y: int) -> Array[Array]:
	var by_y: Dictionary = {}
	for p: Vector2i in positions:
		if p == origin or not _is_valid(p):
			continue
		if not by_y.has(p.y):
			by_y[p.y] = []
		(by_y[p.y] as Array).append(p)

	var rows_list: Array[int] = []
	for row_key in by_y.keys():
		rows_list.append(int(row_key))
	rows_list.sort()
	if direction_y < 0:
		rows_list.reverse()

	var groups: Array[Array] = []
	for row_y in rows_list:
		var raw_positions: Array = by_y[row_y] as Array
		var ordered_positions: Array[Vector2i] = []
		var center := Vector2i(origin.x, row_y)
		if raw_positions.has(center):
			ordered_positions.append(center)
		for value in raw_positions:
			var p: Vector2i = value as Vector2i
			if p != center:
				ordered_positions.append(p)
		groups.append(ordered_positions)
	return groups


func _wood_spear_destination(origin: Vector2i, positions: Array[Vector2i], direction_y: int) -> Vector2i:
	var destination_y: int = origin.y
	for p: Vector2i in positions:
		if not _is_valid(p):
			continue
		if direction_y < 0:
			destination_y = mini(destination_y, p.y)
		else:
			destination_y = maxi(destination_y, p.y)
	return Vector2i(origin.x, destination_y)


func _play_wood_spear_thrust(start_local: Vector2, end_local: Vector2, direction_y: int, duration: float) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = WOOD_SPEAR_THRUST_TEXTURE
	sprite.centered = true
	sprite.z_index = WOOD_SPEAR_THRUST_Z_INDEX
	sprite.scale = Vector2(WOOD_SPEAR_THRUST_SCALE, WOOD_SPEAR_THRUST_SCALE)
	sprite.rotation = 0.0 if direction_y < 0 else PI
	sprite.position = start_local - Vector2(0.0, float(direction_y) * float(CELL_SIZE) * 0.75)
	sprite.modulate.a = 0.95
	add_child(sprite)

	var tip_to_center: float = (float(WOOD_SPEAR_THRUST_TEXTURE.get_height()) * 0.5 - WOOD_SPEAR_THRUST_TIP_FROM_TOP) * WOOD_SPEAR_THRUST_SCALE
	var end_position: Vector2 = end_local - Vector2(0.0, float(direction_y) * tip_to_center)
	var tween := sprite.create_tween().set_parallel(true)
	tween.tween_property(sprite, "position", end_position, duration).set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "modulate:a", 0.0, duration * 0.28).set_delay(duration * 0.72)
	tween.finished.connect(func() -> void:
		if is_instance_valid(sprite):
			sprite.queue_free()
	, CONNECT_ONE_SHOT)


func _destroy_wood_spear_row_group(group: Array, total_blasted_by_type: Dictionary, chained_positions: Array[Vector2i]) -> void:
	var blast_positions_by_type: Dictionary = {}
	var blast_count_by_type: Dictionary = {}
	var blocks_to_free: Array = []
	var normal_destroyed: int = 0

	for value in group:
		var p: Vector2i = value as Vector2i
		if not _is_valid(p):
			continue
		var b: Block = grid[p.x][p.y]
		if b == null or b.is_rock():
			continue
		if b.is_upper_gem():
			if b.upper_owner_team == Block.UpperOwnerTeam.ENEMY:
				_destroy_upper_without_effect(p)
				continue
			if not chained_positions.has(p):
				chained_positions.append(p)
			continue
		if b.is_breakable_structure():
			grid[p.x][p.y] = null
			logic_grid[p.x][p.y] = LOGIC_UNKNOWN
			blocks_to_free.append(b)
			b.play_destroy_animation()
			_spawn_plank_debris(b.global_position)
			continue

		var bt: Block.Type = b.block_type as Block.Type
		var bv: int = b.get_blast_value()
		if not blast_positions_by_type.has(bt):
			blast_positions_by_type[bt] = []
		(blast_positions_by_type[bt] as Array).append(b.global_position)
		blast_count_by_type[bt] = blast_count_by_type.get(bt, 0) + bv
		total_blasted_by_type[bt] = total_blasted_by_type.get(bt, 0) + bv
		grid[p.x][p.y] = null
		blocks_to_free.append(b)
		normal_destroyed += 1
		_play_gem_break_debris(b)

	if normal_destroyed > 0:
		score += normal_destroyed * 10
		score_changed.emit(score)

	for bt in blast_positions_by_type:
		gems_blasted.emit(bt as Block.Type, blast_count_by_type[bt] as int, blast_positions_by_type[bt])
	_emit_goal_cells_for_blocks(blocks_to_free)

	if not blocks_to_free.is_empty():
		var captured_blocks := blocks_to_free.duplicate()
		get_tree().create_timer(0.2).timeout.connect(func() -> void:
			for b in captured_blocks:
				if is_instance_valid(b):
					b.queue_free()
		, CONNECT_ONE_SHOT)


# ── 高階寶石系統 ─────────────────────────────────────────────────────

## 在指定網格位置放置高階寶石。
## 公開方法：觸發掉落與填充。由 main.gd 在融合流程後呼叫。
func do_collapse() -> void:
	skip_collapse = false
	await _collapse_and_fill()


## 爆炸：由上到下逐行消除所有寶石，每行之間有短暫延遲
## 傳回 { gem_type -> count } 統計
func blast_all_rows_sequential(delay: float = 0.12) -> Dictionary:
	var blasted_by_type: Dictionary = {}
	for row_y in rows:
		var row_positions := _get_row_positions(row_y)
		var valid: Array[Vector2i] = []
		for p in row_positions:
			var pb: Block = grid[p.x][p.y]
			# 非 BREAK 屬性技能不可影響障礙物；ROCK 永遠不可影響
			if pb != null and not pb.is_obstacle():
				valid.append(p)
		if valid.is_empty():
			continue

		# 按類型分組，發出信號
		var by_type: Dictionary = {}
		var count_by_type: Dictionary = {}
		for p in valid:
			var b: Block = grid[p.x][p.y]
			var bt: Block.Type = b.block_type as Block.Type
			if not by_type.has(bt):
				by_type[bt] = []
			by_type[bt].append(b.global_position)
			var bv: int = b.get_blast_value()
			count_by_type[bt] = count_by_type.get(bt, 0) + bv
			blasted_by_type[bt] = blasted_by_type.get(bt, 0) + bv

		# 消除此行寶石
		var blocks_to_free: Array = []
		for p in valid:
			var b: Block = grid[p.x][p.y]
			if b:
				grid[p.x][p.y] = null
				blocks_to_free.append(b)
				_play_gem_break_debris(b)

		score += valid.size() * 10
		score_changed.emit(score)

		for bt in by_type:
			var gpos: Array = by_type[bt]
			gems_blasted.emit(bt as Block.Type, count_by_type[bt] as int, gpos)
		_emit_goal_cells_for_blocks(blocks_to_free)

		# 延遲釋放節點
		var captured_blocks := blocks_to_free.duplicate()
		get_tree().create_timer(0.2).timeout.connect(func() -> void:
			for b in captured_blocks:
				if is_instance_valid(b):
					b.queue_free()
		, CONNECT_ONE_SHOT)

		if row_y < rows - 1:
			await get_tree().create_timer(delay).timeout

	return blasted_by_type


## 在指定位置放置高階寶石（若該格為空則先建立寶石，顏色由 gem_type 決定）
func place_upper_gem(
	pos: Vector2i,
	ut: Block.UpperType,
	gem_type: Block.Type = Block.Type.RED,
	owner_team: Block.UpperOwnerTeam = Block.UpperOwnerTeam.PLAYER,
	owner_id: int = 0
) -> bool:
	if not _is_valid(pos):
		return false
	if _is_hole_pos(pos):
		return false
	if is_escape_marker_pos(pos):
		return false
	var block: Block = grid[pos.x][pos.y]
	if block != null and block.is_obstacle():
		return false
	if block != null and block.is_upper_gem():
		return false
	if block == null:
		block = _create_block(pos.x, pos.y)
		block.set_block_type(gem_type)

	# 設定高階類型（替換普通寶石外觀為火焰貼圖 + 紅色底色）
	block.set_upper_type(ut)
	block.set_upper_owner(owner_team, owner_id)
	if is_fusing or skip_collapse:
		_queue_floating_fused_upper_gem(block, pos)
	# 統一「融合閃光 + 彈跳」動畫
	play_fuse_animation(block)
	return true


## 偵錯：將棋盤上隨機 N 顆普通寶石轉為火炸彈（FIREBALL）
func debug_spawn_firebombs(count: int) -> void:
	var candidates: Array = []
	for x in columns:
		for y in rows:
			var b: Block = grid[x][y]
			if b != null and not b.is_upper_gem() and not b.is_obstacle():
				candidates.append(b)
	candidates.shuffle()
	var n: int = mini(count, candidates.size())
	for i in n:
		var b: Block = candidates[i]
		b.set_block_type(Block.Type.RED)
		b.set_upper_type(Block.UpperType.FIREBALL)


## 處理高階寶石被點擊：根據類型決定爆炸範圍，執行連鏈爆炸
func _handle_upper_click(pos: Vector2i) -> void:
	var block: Block = grid[pos.x][pos.y]
	if block == null or block.is_enemy_upper_gem():
		return
	var ut: Block.UpperType = block.upper_type

	# 水劍專用連鎖序列：不走一般 upper-gem chain 路徑
	if ut == Block.UpperType.WATER_SLASH:
		await _handle_water_sword_sequence(pos)
		return
	if _is_wood_spear_type(ut):
		await _handle_wood_spear_sequence(pos)
		return

	# 根據高階類型決定爆炸位置（使用共用函式）
	var positions: Array[Vector2i] = _get_blast_positions_for_upper(pos, ut)

	# 執行帶連鏈遞迴的爆炸
	var chain_data := [1]  # 初始點擊即為 chain 1
	var total_blasted_by_type: Dictionary = {}  # Block.Type -> int，各類型被爆破數量

	upper_gem_clicked.emit()

	# 觸發被點擊高階寶石的獨有效果（與連鏈統一處理）
	upper_gem_chain_triggered.emit(ut)

	# 播放爆炸 VFX（fire-and-forget）
	_play_blast_vfx_for(pos, ut, block.global_position)

	# 先消除被點擊的高階寶石本身（立即播放動畫）
	var bt: Block.Type = block.block_type as Block.Type
	var bv: int = block.get_blast_value()
	total_blasted_by_type[bt] = bv
	gems_blasted.emit(bt, bv, [block.global_position])
	grid[pos.x][pos.y] = null
	_play_gem_break_debris(block, true)
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		if is_instance_valid(block):
			block.queue_free()
	, CONNECT_ONE_SHOT)

	# 從爆炸範圍中移除自身（已處理），再交給連鏈函式
	positions.erase(pos)
	if positions.size() > 0:
		await _execute_upper_blast_chain(positions, chain_data, total_blasted_by_type)

	upper_blast_completed.emit(chain_data[0], total_blasted_by_type, ut)


## 執行高階寶石爆炸連鏈（遞迴）
## 若爆炸範圍內有其他高階寶石，會繼續觸發其爆炸
func _execute_upper_blast_chain(positions: Array[Vector2i], chain_data: Array, total_blasted_by_type: Dictionary) -> void:
	# 收集要消除的寶石和被波及的其他高階寶石
	var to_destroy: Array[Vector2i] = []
	var planks_in_blast: Array[Vector2i] = []  # 範圍內的可破壞障礙（靜默移除）
	var chained_uppers: Array[Dictionary] = []  # { pos, upper_type }

	for p in positions:
		if not _is_valid(p):
			continue
		var b: Block = grid[p.x][p.y]
		if b == null:
			continue
		if b.is_rock():
			continue
		# 如果這個寶石是高階寶石，加入連鏈爆炸佇列（暫不消除）
		if b.is_upper_gem():
			if b.upper_owner_team == Block.UpperOwnerTeam.ENEMY:
				_destroy_upper_without_effect(p)
				continue
			chained_uppers.append({"pos": p, "upper_type": b.upper_type})
			continue
		# 可破壞障礙 — 靜默移除（不計分、不發信號、不貢獻攻擊）
		if b.is_breakable_structure():
			planks_in_blast.append(p)
			continue
		to_destroy.append(p)

	# 統計各類型被爆破的寶石數量
	var blast_positions_by_type: Dictionary = {}  # type -> Array of global positions
	var blast_count_by_type: Dictionary = {}  # type -> 加成後的數量
	for p in to_destroy:
		var b: Block = grid[p.x][p.y]
		if b == null:
			continue
		var bt: Block.Type = b.block_type as Block.Type
		if not blast_positions_by_type.has(bt):
			blast_positions_by_type[bt] = []
		blast_positions_by_type[bt].append(b.global_position)

		# 累加到總計（X5 額外效果加成）
		var bv: int = b.get_blast_value()
		blast_count_by_type[bt] = blast_count_by_type.get(bt, 0) + bv
		total_blasted_by_type[bt] = total_blasted_by_type.get(bt, 0) + bv

	# 消除普通寶石（高階寶石保留在棋盤上）
	var blocks_to_free: Array = []
	for p in to_destroy:
		var b: Block = grid[p.x][p.y]
		if b == null:
			continue
		grid[p.x][p.y] = null
		blocks_to_free.append(b)
		_play_gem_break_debris(b)

	# 靜默消除可破壞障礙（無得分、無信號）
	var planks_to_free: Array = []
	for p in planks_in_blast:
		var pb: Block = grid[p.x][p.y]
		if pb == null:
			continue
		grid[p.x][p.y] = null
		logic_grid[p.x][p.y] = LOGIC_UNKNOWN
		planks_to_free.append(pb)
		pb.play_destroy_animation()
		_spawn_plank_debris(pb.global_position)

	score += to_destroy.size() * 10
	score_changed.emit(score)

	# 為每種類型發出 gems_blasted 信號（用於攻擊計算）
	for bt in blast_positions_by_type:
		var gpos: Array = blast_positions_by_type[bt]
		gems_blasted.emit(bt as Block.Type, blast_count_by_type[bt] as int, gpos)
	var upper_goal_blocks: Array = blocks_to_free.duplicate()
	upper_goal_blocks.append_array(planks_to_free)
	_emit_goal_cells_for_blocks(upper_goal_blocks)

	# 動畫結束後釋放節點
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		for b in blocks_to_free:
			if is_instance_valid(b):
				b.queue_free()
		for p in planks_to_free:
			if is_instance_valid(p):
				p.queue_free()
	, CONNECT_ONE_SHOT)

	# 本批有真正消除才需要等待視覺節奏；空批（被前面的連鎖清光了）直接 0 等待
	if to_destroy.size() > 0 or planks_in_blast.size() > 0:
		await get_tree().create_timer(0.15).timeout

	# 處理連鏈的高階寶石：輪到時消除，執行與點擊相同的爆炸行為
	for chained in chained_uppers:
		var cp: Vector2i = chained.pos
		var cut: Block.UpperType = chained.upper_type as Block.UpperType

		# 先檢查目標是否還活著 — 若已被同批其他 upper 的遞迴爆炸清掉，直接跳過（不計連鎖、不等待）
		var ub: Block = grid[cp.x][cp.y]
		if ub == null:
			continue

		# 等待連鏈間隔（固定節奏，僅在還有實際爆炸時花費）
		await get_tree().create_timer(chain_blast_interval).timeout

		# 二次檢查（等待期間可能被其他遞迴清掉）
		ub = grid[cp.x][cp.y]
		if ub == null:
			continue

		# 水劍：交由專用連鎖序列處理（與點擊同樣規則，且不允許其他 upper 插入）
		if cut == Block.UpperType.WATER_SLASH:
			await _handle_water_sword_sequence(cp, chain_data, total_blasted_by_type, false)
			continue
		if _is_wood_spear_type(cut):
			await _handle_wood_spear_sequence(cp, chain_data, total_blasted_by_type, false)
			continue

		# 播放連鏈爆炸 VFX
		_play_blast_vfx_for(cp, cut, ub.global_position)
		var ub_type: Block.Type = ub.block_type as Block.Type
		var ub_bv: int = ub.get_blast_value()
		total_blasted_by_type[ub_type] = total_blasted_by_type.get(ub_type, 0) + ub_bv
		gems_blasted.emit(ub_type, ub_bv, [ub.global_position])
		grid[cp.x][cp.y] = null
		_play_gem_break_debris(ub, true)
		get_tree().create_timer(0.2).timeout.connect(func() -> void:
			if is_instance_valid(ub):
				ub.queue_free()
		, CONNECT_ONE_SHOT)

		# 發出信號讓 main.gd 處理此類型的獨有效果
		upper_gem_chain_triggered.emit(cut)

		# 取得爆炸範圍（與點擊行為一致，使用共用函式）
		var chain_positions: Array[Vector2i] = _get_blast_positions_for_upper(cp, cut)
		chain_positions.erase(cp)  # 排除自身（已被消除）

		# 過濾已被消除的位置
		var valid_positions: Array[Vector2i] = []
		for pp in chain_positions:
			if _is_valid(pp) and grid[pp.x][pp.y] != null:
				valid_positions.append(pp)

		# 連鎖計數：每個被觸發的 upper 都計 1 次（與 upper_gem_chain_triggered 訊號次數同步）
		chain_data[0] += 1
		if valid_positions.size() > 0:
			await _execute_upper_blast_chain(valid_positions, chain_data, total_blasted_by_type)


## ── 水劍專用連鎖序列 ───────────────────────────────────────────
## 點擊任意水劍時呼叫；自動連鎖棋盤上「所有」水劍，期間不允許其它高階寶石的 chain 插入。
## 規則：
##   - 1 把水劍：直接縱向 column 爆破。
##   - N 把水劍：以「貪心找最遠」順序排序；每相鄰兩把間以直線連起並爆破線上所有寶石；
##              最後一把水劍另做一次縱向 column 爆破。
## 可重複呼叫於：
##   - 初始點擊（_handle_upper_click）：chain_data=null時自動創建，并發出 upper_gem_clicked / upper_blast_completed
##   - 連鎖觸發（_execute_upper_blast_chain）：傳入 chain_data 與 total_blasted_by_type，不重複發出外部訊號
func _handle_water_sword_sequence(start_pos: Vector2i, chain_data: Array = [], total_blasted_by_type: Dictionary = {}, is_initial: bool = true) -> void:
	var start_block: Block = grid[start_pos.x][start_pos.y]
	if start_block == null:
		return
	var ut: Block.UpperType = start_block.upper_type

	# 狂鯊連鎖期間放慢節奏至 0.3s，結束後還原
	var _saved_interval: float = chain_blast_interval
	if is_initial:
		chain_blast_interval = 0.3

	if is_initial:
		chain_data.clear()
		chain_data.append(0)
		total_blasted_by_type.clear()
		upper_gem_clicked.emit()

	# 收集所有水劍位置（含起始）
	var swords: Array[Vector2i] = [start_pos]
	for p in find_upper_gems(Block.UpperType.WATER_SLASH):
		if p != start_pos:
			swords.append(p)

	# 貪心建構連鎖順序：每次選距上一把最遠的水劍
	var order: Array[Vector2i] = [start_pos]
	var remaining: Array[Vector2i] = []
	for s in swords:
		if s != start_pos:
			remaining.append(s)
	while not remaining.is_empty():
		var cur: Vector2i = order[order.size() - 1]
		var best_idx: int = 0
		var best_d: float = -1.0
		for i in remaining.size():
			var diff: Vector2 = Vector2(remaining[i] - cur)
			var d: float = diff.length_squared()
			if d > best_d:
				best_d = d
				best_idx = i
		order.append(remaining[best_idx])
		remaining.remove_at(best_idx)

	# 被跳過的其它 upper 寶石 — 收集到佇列，水劍連鎖全部跱完後逐一觸發
	var deferred_uppers: Array = []  # Array of {"pos": Vector2i, "upper_type": UpperType}
	var deferred_seen: Dictionary = {}

	for i in order.size():
		var sword_pos: Vector2i = order[i]
		chain_data[0] += 1
		upper_gem_chain_triggered.emit(ut)

		# 決定本段要爆破的格子
		var cells: Array[Vector2i]
		var beam_start: Vector2
		var beam_end: Vector2
		if i < order.size() - 1:
			cells = _line_cells_between(sword_pos, order[i + 1])
			beam_start = to_global(grid_to_world(sword_pos))
			beam_end = to_global(grid_to_world(order[i + 1]))
		else:
			cells = _get_col_positions(sword_pos.x)
			# 縱向欄位：由欄底到欄頂（修改方向：原本是從 0 到 rows-1）
			beam_start = to_global(grid_to_world(Vector2i(sword_pos.x, rows - 1)))
			beam_end = to_global(grid_to_world(Vector2i(sword_pos.x, 0)))

		# 播放連接起點與終點的射線 VFX（取代原本每格一次的爆破精靈）
		_play_water_chain_beam(beam_start, beam_end)

		# 銷毀格子上的寶石（其他高階寶石不觸發其爆破，避免 chain 插入；
		#  唯一例外：水劍本身仍被消耗）
		var blast_pos_by_type: Dictionary = {}
		var blast_count_by_type: Dictionary = {}
		var blocks_to_free: Array = []
		for c in cells:
			if not _is_valid(c):
				continue
			var b: Block = grid[c.x][c.y]
			if b == null:
				continue
			if b.is_rock():
				continue
			var is_other_upper: bool = b.is_upper_gem() \
				and b.upper_type != Block.UpperType.WATER_SLASH
			if is_other_upper:
				if b.upper_owner_team == Block.UpperOwnerTeam.ENEMY:
					_destroy_upper_without_effect(c)
					continue
				# 不立即觸發以避免 chain 插入；收集到佇列在水劍序列完成後逐一觸發
				var key: int = c.x * 1000 + c.y
				if not deferred_seen.has(key):
					deferred_seen[key] = true
					deferred_uppers.append({"pos": c, "upper_type": b.upper_type})
				continue
			# 可破壞障礙 — 靜默移除（不計分、不發信號、不貢獻攻擊）
			if b.is_breakable_structure():
				grid[c.x][c.y] = null
				logic_grid[c.x][c.y] = LOGIC_UNKNOWN
				blocks_to_free.append(b)
				b.play_destroy_animation()
				_spawn_plank_debris(b.global_position)
				continue
			var bt: Block.Type = b.block_type as Block.Type
			var bv: int = b.get_blast_value()
			if not blast_pos_by_type.has(bt):
				blast_pos_by_type[bt] = []
			(blast_pos_by_type[bt] as Array).append(b.global_position)
			blast_count_by_type[bt] = blast_count_by_type.get(bt, 0) + bv
			total_blasted_by_type[bt] = total_blasted_by_type.get(bt, 0) + bv
			grid[c.x][c.y] = null
			blocks_to_free.append(b)
			_play_gem_break_debris(b)

		score += blocks_to_free.size() * 10
		score_changed.emit(score)

		for bt in blast_pos_by_type:
			gems_blasted.emit(bt as Block.Type, blast_count_by_type[bt] as int, blast_pos_by_type[bt])
		_emit_goal_cells_for_blocks(blocks_to_free)

		get_tree().create_timer(0.2).timeout.connect(func() -> void:
			for b in blocks_to_free:
				if is_instance_valid(b):
					b.queue_free()
		, CONNECT_ONE_SHOT)

		if blocks_to_free.size() > 0:
			await get_tree().create_timer(maxf(chain_blast_interval, 0.02)).timeout

	# 水劍序列全部跱完 → 處理路線上被「跳過」的其他高階寶石（順序觸發，允許递迴連鎖）
	for entry in deferred_uppers:
		var dp: Vector2i = entry["pos"]
		var dut: Block.UpperType = entry["upper_type"] as Block.UpperType
		# 重新驗證目標仍在且仍是同類 upper
		if not _is_valid(dp):
			continue
		var dub: Block = grid[dp.x][dp.y]
		if dub == null or not dub.is_upper_gem() or dub.upper_type != dut:
			continue

		await get_tree().create_timer(maxf(chain_blast_interval, 0.02)).timeout
		# 再次驗證
		dub = grid[dp.x][dp.y]
		if dub == null:
			continue
		if _is_wood_spear_type(dut):
			await _handle_wood_spear_sequence(dp, chain_data, total_blasted_by_type, false)
			continue

		# 交由連鎖路徑處理（由「逘一觸發」路徑代勞）
		chain_data[0] += 1
		upper_gem_chain_triggered.emit(dut)
		_play_blast_vfx_for(dp, dut, dub.global_position)

		var dub_type: Block.Type = dub.block_type as Block.Type
		var dub_bv: int = dub.get_blast_value()
		total_blasted_by_type[dub_type] = total_blasted_by_type.get(dub_type, 0) + dub_bv
		gems_blasted.emit(dub_type, dub_bv, [dub.global_position])
		grid[dp.x][dp.y] = null
		_play_gem_break_debris(dub, true)
		get_tree().create_timer(0.2).timeout.connect(func() -> void:
			if is_instance_valid(dub):
				dub.queue_free()
		, CONNECT_ONE_SHOT)

		# 水劍：交給水劍序列（不應發生—所有水劍已在上輪被處理）
		if dut == Block.UpperType.WATER_SLASH:
			await _handle_water_sword_sequence(dp, chain_data, total_blasted_by_type, false)
			continue

		# 其他 upper：取其爆炸範圍並走常規連鎖递迴
		var d_positions: Array[Vector2i] = _get_blast_positions_for_upper(dp, dut)
		d_positions.erase(dp)
		var d_valid: Array[Vector2i] = []
		for pp in d_positions:
			if _is_valid(pp) and grid[pp.x][pp.y] != null:
				d_valid.append(pp)
		if d_valid.size() > 0:
			await _execute_upper_blast_chain(d_valid, chain_data, total_blasted_by_type)

	if is_initial:
		upper_blast_completed.emit(chain_data[0], total_blasted_by_type, ut)
		chain_blast_interval = _saved_interval


## 水劍連鎖射線動畫：projetilNew.png 為 1×6 縱向精靈表（上到下 6 幀）
## 每幀中：左邊為起點、右邊為終點 → 以 Sprite2D 拉伸與旋轉連接兩點
func _play_water_chain_beam(start_global: Vector2, end_global: Vector2) -> void:
	var tex: Texture2D = load("res://assets/animation/projetilNew.png")
	if tex == null:
		return
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.hframes = 1
	sprite.vframes = 7
	sprite.frame = 0
	sprite.centered = false
	var frame_w: float = float(tex.get_width())
	var frame_h: float = float(tex.get_height()) / 7.0
	# 以「左邊中點」為錨點：offset 推到負半幀高讓垂直上下居中
	sprite.offset = Vector2(0.0, -frame_h * 0.5)
	var diff: Vector2 = end_global - start_global
	var dist: float = diff.length()
	var scale_x: float = (dist / frame_w) if frame_w > 0.0 else 1.0
	# Y 方向放大 2 倍 → 水劍斬痕加粗
	sprite.scale = Vector2(scale_x, 2.0)
	sprite.rotation = diff.angle()
	sprite.z_index = 25
	add_child(sprite)
	sprite.global_position = start_global

	# 播放 6 幀動畫— 總長 ≈ chain_blast_interval（最低 0.18s）
	var total: float = maxf(chain_blast_interval, 0.18)
	var frame_dur: float = total / 7.0
	var anim_tw := create_tween()
	for f in 7:
		anim_tw.tween_callback(func() -> void:
			if is_instance_valid(sprite):
				sprite.frame = f
		)
		anim_tw.tween_interval(frame_dur)
	anim_tw.tween_callback(func() -> void:
		if is_instance_valid(sprite):
			sprite.queue_free()
	)


## Bresenham：回傳兩個格子之間（含端點）的所有經過格子
func _line_cells_between(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var dx: int = absi(b.x - a.x)
	var dy: int = absi(b.y - a.y)
	var sx: int = 1 if a.x < b.x else -1
	var sy: int = 1 if a.y < b.y else -1
	var err: int = dx - dy
	var x: int = a.x
	var y: int = a.y
	while true:
		cells.append(Vector2i(x, y))
		if x == b.x and y == b.y:
			break
		var e2: int = 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
	return cells


## 播放高階寶石爆炸 VFX：水劍會在每個受影響格子各播放一次（X 旋轉 90°）；
## 其他類型則維持單點播放於中心。
func _play_blast_vfx_for(center_pos: Vector2i, ut: Block.UpperType, center_global: Vector2) -> void:
	if ut == Block.UpperType.WATER_SLASH:
		var positions: Array[Vector2i] = _get_blast_positions_for_upper(center_pos, ut)
		for p in positions:
			var gp: Vector2 = center_global
			if p.x >= 0 and p.x < grid.size() and p.y >= 0 and p.y < grid[p.x].size():
				var b: Block = grid[p.x][p.y]
				if b != null:
					gp = b.global_position
				else:
					gp = center_global + Vector2(p - center_pos) * float(CELL_SIZE)
			BlastVfx.play(self, gp, ut, 0.0)
		return
	BlastVfx.play(self, center_global, ut)


## 根據高階寶石類型取得爆炸範圍（點擊與連鏈共用）
func _get_blast_positions_for_upper(pos: Vector2i, ut: Block.UpperType) -> Array[Vector2i]:
	match ut:
		Block.UpperType.FIREBALL:
			return _get_area_positions(pos, 4)
		Block.UpperType.FIRE_PILLAR_X:
			return _get_row_positions(pos.y)
		Block.UpperType.FIRE_PILLAR_Y:
			return _get_col_positions(pos.x)
		Block.UpperType.SAINT_CROSS:
			return _get_cross_positions(pos)
		Block.UpperType.LEAF_SHIELD:
			return [pos]
		Block.UpperType.SNOWBALL:
			return _get_surrounding_positions(pos)
		Block.UpperType.ICEBALL:
			return _get_surrounding_positions(pos)
		Block.UpperType.LIGHT_SHIELD:
			return [pos]
		Block.UpperType.BAMBOO_SUPPLY:
			return _get_surrounding_positions(pos)
		Block.UpperType.WATER_SLASH:
			return _get_col_positions(pos.x)
		Block.UpperType.WOOD_SPEAR_UP:
			return _get_wood_spear_positions(pos, -1)
		Block.UpperType.WOOD_SPEAR_DOWN:
			return _get_wood_spear_positions(pos, 1)
	return [pos]


func _append_unique_valid_position(result: Array[Vector2i], pos: Vector2i) -> void:
	if _is_valid(pos) and not result.has(pos):
		result.append(pos)


func _append_wood_spear_head(result: Array[Vector2i], center: Vector2i) -> void:
	_append_unique_valid_position(result, center)
	_append_unique_valid_position(result, Vector2i(center.x - 1, center.y))
	_append_unique_valid_position(result, Vector2i(center.x + 1, center.y))


func _get_wood_spear_positions(origin: Vector2i, direction_y: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	_append_unique_valid_position(result, origin)

	var origin_block: Block = grid[origin.x][origin.y]
	var pierce_breakable: bool = origin_block != null and origin_block.wood_spear_pierce_breakable
	var terminal: Vector2i = origin
	var current: Vector2i = origin + Vector2i(0, direction_y)
	while _is_valid(current):
		_append_unique_valid_position(result, current)
		terminal = current
		var block: Block = grid[current.x][current.y]
		if block != null and block.is_obstacle():
			if pierce_breakable and block.is_breakable_structure():
				current += Vector2i(0, direction_y)
				continue
			var beyond: Vector2i = current + Vector2i(0, direction_y)
			_append_unique_valid_position(result, beyond)
			_append_wood_spear_head(result, current)
			return result
		current += Vector2i(0, direction_y)

	_append_wood_spear_head(result, terminal)
	return result


## 取得火球爆炸位置：中心 3×3 + 四個方向各延伸1格
func _get_area_positions(center: Vector2i, _size: int = 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	# 3×3 核心範圍
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var p := Vector2i(center.x + dx, center.y + dy)
			if _cell_accepts_block(p):
				result.append(p)
	# 上下左右各延伸1格
	var extensions: Array[Vector2i] = [Vector2i(0, -2), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(2, 0)]
	for ext: Vector2i in extensions:
		var p: Vector2i = center + ext
		if _cell_accepts_block(p):
			result.append(p)
	return result


## 取得周圍 8 格位置（3×3 去掉中心）— 用於 Snowball 爆炸範圍
func _get_surrounding_positions(center: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var p := Vector2i(center.x + dx, center.y + dy)
			if _cell_accepts_block(p):
				result.append(p)
	return result


## 搜尋棋盤上所有符合指定高階類型的寶石位置
func find_upper_gems(ut: Block.UpperType) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in columns:
		for y in rows:
			var block: Block = grid[x][y]
			if block != null \
					and block.upper_type == ut \
					and block.upper_owner_team == Block.UpperOwnerTeam.PLAYER:
				result.append(Vector2i(x, y))
	return result


## 移除並摧毀指定位置的高階寶石（播放破壞動畫 + 掉落填充）
func destroy_upper_gem_at(pos: Vector2i) -> void:
	if not _is_valid(pos):
		return
	var block: Block = grid[pos.x][pos.y]
	if block == null:
		return
	grid[pos.x][pos.y] = null
	_play_gem_break_debris(block, true)
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		if is_instance_valid(block):
			block.queue_free()
	, CONNECT_ONE_SHOT)


func _destroy_upper_without_effect(pos: Vector2i) -> void:
	if not _is_valid(pos):
		return
	var block: Block = grid[pos.x][pos.y]
	if block == null or not block.is_upper_gem():
		return
	grid[pos.x][pos.y] = null
	_play_gem_break_debris(block, true)
	_queue_free_blocks_after_debris([block])


func find_owned_upper_gems(owner_id: int, ut: Block.UpperType = Block.UpperType.NONE) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in columns:
		for y in rows:
			var block: Block = grid[x][y]
			if block == null or not block.is_upper_gem():
				continue
			if block.upper_owner_team != Block.UpperOwnerTeam.ENEMY:
				continue
			if block.upper_owner_id != owner_id:
				continue
			if ut != Block.UpperType.NONE and block.upper_type != ut:
				continue
			result.append(Vector2i(x, y))
	return result


func _auto_is_normal_gem(block: Block) -> bool:
	return block != null and not block.is_obstacle() and not block.is_upper_gem()


func _auto_connected_group(start: Vector2i, type_filter: int = -1) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not _cell_accepts_block(start) or is_escape_marker_pos(start):
		return result
	var start_block: Block = grid[start.x][start.y]
	if not _auto_is_normal_gem(start_block):
		return result
	var target_type: int = int(start_block.block_type)
	if type_filter >= 0 and target_type != type_filter:
		return result
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var key: int = current.x * 1000 + current.y
		if visited.has(key):
			continue
		if not _cell_accepts_block(current) or is_escape_marker_pos(current):
			continue
		var block: Block = grid[current.x][current.y]
		if not _auto_is_normal_gem(block):
			continue
		if int(block.block_type) != target_type:
			continue
		visited[key] = true
		result.append(current)
		queue.append(Vector2i(current.x + 1, current.y))
		queue.append(Vector2i(current.x - 1, current.y))
		queue.append(Vector2i(current.x, current.y + 1))
		queue.append(Vector2i(current.x, current.y - 1))
	return result


func find_best_auto_group(type_filter: int = -1) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var visited: Dictionary = {}
	for x in columns:
		for y in rows:
			var pos := Vector2i(x, y)
			var key: int = x * 1000 + y
			if visited.has(key):
				continue
			var group: Array[Vector2i] = _auto_connected_group(pos, type_filter)
			for p in group:
				visited[p.x * 1000 + p.y] = true
			if group.size() > best.size():
				best = group
	return best


func find_auto_fuse_group(gem_type: Block.Type, threshold: int) -> Array[Vector2i]:
	var group: Array[Vector2i] = find_best_auto_group(int(gem_type))
	if group.size() >= threshold:
		return group
	var empty: Array[Vector2i] = []
	return empty


func get_best_wood_spear_type_for_pos(pos: Vector2i) -> Block.UpperType:
	var up_count: int = _auto_count_wood_spear_targets(pos, -1)
	var down_count: int = _auto_count_wood_spear_targets(pos, 1)
	if down_count > up_count:
		return Block.UpperType.WOOD_SPEAR_DOWN
	if up_count > down_count:
		return Block.UpperType.WOOD_SPEAR_UP
	if pos.y <= rows / 2:
		return Block.UpperType.WOOD_SPEAR_DOWN
	return Block.UpperType.WOOD_SPEAR_UP


func _auto_count_wood_spear_targets(pos: Vector2i, direction_y: int) -> int:
	var count: int = 0
	for p in _get_wood_spear_positions(pos, direction_y):
		if p == pos or not _cell_accepts_block(p) or is_escape_marker_pos(p):
			continue
		var block: Block = grid[p.x][p.y]
		if block == null or block.is_rock():
			continue
		count += 1
	return count


func get_enemy_upper_preview_count(pos: Vector2i, owner_id: int) -> int:
	if not _is_valid(pos):
		return 0
	var block: Block = grid[pos.x][pos.y]
	if block == null or not block.is_upper_gem():
		return 0
	if block.upper_owner_team != Block.UpperOwnerTeam.ENEMY or block.upper_owner_id != owner_id:
		return 0
	var count: int = 0
	for p in _get_blast_positions_for_upper(pos, block.upper_type):
		if p == pos or not _cell_accepts_block(p) or is_escape_marker_pos(p):
			continue
		var target: Block = grid[p.x][p.y]
		if _auto_is_normal_gem(target):
			count += 1
	return count


func enemy_fuse_upper_from_group(
	group: Array[Vector2i],
	target: Vector2i,
	ut: Block.UpperType,
	gem_type: Block.Type,
	owner_id: int,
	wood_spear_pierce_breakable: bool = false
) -> bool:
	if group.is_empty() or not group.has(target):
		return false
	var target_block: Block = grid[target.x][target.y]
	if target_block == null or target_block.is_obstacle() or target_block.is_upper_gem():
		return false
	var blocks_to_free: Array = []
	for p in group:
		if p == target or not _is_valid(p):
			continue
		var block: Block = grid[p.x][p.y]
		if not _auto_is_normal_gem(block):
			continue
		grid[p.x][p.y] = null
		blocks_to_free.append(block)
		_play_gem_break_debris(block)
	target_block.set_block_type(gem_type)
	target_block.set_upper_type(ut)
	target_block.set_upper_owner(Block.UpperOwnerTeam.ENEMY, owner_id)
	if _is_wood_spear_type(ut):
		target_block.wood_spear_pierce_breakable = wood_spear_pierce_breakable
	_queue_floating_fused_upper_gem(target_block, target)
	play_fuse_animation(target_block)
	_queue_free_blocks_after_debris(blocks_to_free)
	await get_tree().create_timer(0.25).timeout
	await _collapse_without_escape_progress()
	return true


func enemy_blast_group(group: Array[Vector2i]) -> Dictionary:
	var count: int = 0
	var world_positions: Array[Vector2] = []
	var counts_by_type: Dictionary = {}
	var positions_by_type: Dictionary = {}
	var blocks_to_free: Array = []
	for p in group:
		if not _cell_accepts_block(p) or is_escape_marker_pos(p):
			continue
		var block: Block = grid[p.x][p.y]
		if not _auto_is_normal_gem(block):
			continue
		var bt: Block.Type = block.block_type as Block.Type
		grid[p.x][p.y] = null
		count += 1
		world_positions.append(block.global_position)
		counts_by_type[bt] = int(counts_by_type.get(bt, 0)) + 1
		if not positions_by_type.has(bt):
			positions_by_type[bt] = []
		(positions_by_type[bt] as Array).append(block.global_position)
		blocks_to_free.append(block)
		_play_gem_break_debris(block)
	if count > 0:
		enemy_break_pulse.emit()
	_queue_free_blocks_after_debris(blocks_to_free)
	await _collapse_without_escape_progress()
	return {
		"count": count,
		"positions": world_positions,
		"counts_by_type": counts_by_type,
		"positions_by_type": positions_by_type,
	}


func enemy_trigger_owned_upper(pos: Vector2i, owner_id: int) -> Dictionary:
	var visited: Dictionary = {}
	return await _enemy_trigger_owned_upper_recursive(pos, owner_id, visited)


func _enemy_trigger_owned_upper_recursive(pos: Vector2i, owner_id: int, visited: Dictionary) -> Dictionary:
	var result := {"count": 0, "positions": [], "counts_by_type": {}, "positions_by_type": {}}
	if not _is_valid(pos):
		return result
	var key: int = pos.x * 1000 + pos.y
	if visited.has(key):
		return result
	visited[key] = true
	var block: Block = grid[pos.x][pos.y]
	if block == null or not block.is_upper_gem():
		return result
	if block.upper_owner_team != Block.UpperOwnerTeam.ENEMY or block.upper_owner_id != owner_id:
		return result
	var ut: Block.UpperType = block.upper_type
	var positions: Array[Vector2i] = _get_blast_positions_for_upper(pos, ut)
	var chain_positions: Array[Vector2i] = []
	var blocks_to_free: Array = []
	var normal_count: int = 0
	var normal_world_positions: Array[Vector2] = []
	var counts_by_type: Dictionary = {}
	var positions_by_type: Dictionary = {}

	_play_blast_vfx_for(pos, ut, block.global_position)
	var upper_element: Block.Type = block.block_type as Block.Type
	var upper_value: int = block.get_blast_value()
	normal_count += upper_value
	normal_world_positions.append(block.global_position)
	counts_by_type[upper_element] = int(counts_by_type.get(upper_element, 0)) + upper_value
	if not positions_by_type.has(upper_element):
		positions_by_type[upper_element] = []
	(positions_by_type[upper_element] as Array).append(block.global_position)
	if _is_wood_spear_type(ut):
		var direction_y: int = _wood_spear_direction(ut)
		var destination: Vector2i = _wood_spear_destination(pos, positions, direction_y)
		var row_groups: Array[Array] = _build_wood_spear_row_groups(pos, positions, direction_y)
		var thrust_duration: float = maxf(float(maxi(row_groups.size(), 1)) * WOOD_SPEAR_ROW_HIT_INTERVAL, 0.18)
		_play_wood_spear_thrust(grid_to_world(pos), grid_to_world(destination), direction_y, thrust_duration)

		grid[pos.x][pos.y] = null
		blocks_to_free.append(block)
		_play_gem_break_debris(block, true)
		_queue_free_blocks_after_debris(blocks_to_free)

		for group_index in row_groups.size():
			await get_tree().create_timer(WOOD_SPEAR_ROW_HIT_INTERVAL).timeout
			var group: Array = row_groups[group_index]
			normal_count += _destroy_enemy_wood_spear_row_group(group, owner_id, counts_by_type, positions_by_type, normal_world_positions, chain_positions)

		if row_groups.is_empty():
			await get_tree().create_timer(thrust_duration).timeout
	else:
		grid[pos.x][pos.y] = null
		blocks_to_free.append(block)
		_play_gem_break_debris(block, true)

		for p in positions:
			if p == pos or not _cell_accepts_block(p) or is_escape_marker_pos(p):
				continue
			var target: Block = grid[p.x][p.y]
			if target == null or target.is_rock():
				continue
			if target.is_upper_gem():
				if target.upper_owner_team == Block.UpperOwnerTeam.ENEMY and target.upper_owner_id == owner_id:
					if not chain_positions.has(p):
						chain_positions.append(p)
				else:
					grid[p.x][p.y] = null
					blocks_to_free.append(target)
					_play_gem_break_debris(target, true)
				continue
			if target.is_breakable_structure():
				grid[p.x][p.y] = null
				logic_grid[p.x][p.y] = LOGIC_UNKNOWN
				blocks_to_free.append(target)
				target.play_destroy_animation()
				_spawn_plank_debris(target.global_position)
				continue
			var target_type: Block.Type = target.block_type as Block.Type
			grid[p.x][p.y] = null
			normal_count += 1
			normal_world_positions.append(target.global_position)
			counts_by_type[target_type] = int(counts_by_type.get(target_type, 0)) + 1
			if not positions_by_type.has(target_type):
				positions_by_type[target_type] = []
			(positions_by_type[target_type] as Array).append(target.global_position)
			blocks_to_free.append(target)
			_play_gem_break_debris(target)

		if not blocks_to_free.is_empty():
			enemy_break_pulse.emit()
		_queue_free_blocks_after_debris(blocks_to_free)

	for chain_pos in chain_positions:
		await get_tree().create_timer(chain_blast_interval).timeout
		var chain_result: Dictionary = await _enemy_trigger_owned_upper_recursive(chain_pos, owner_id, visited)
		normal_count += int(chain_result.get("count", 0))
		normal_world_positions.append_array(chain_result.get("positions", []))
		var chain_counts: Dictionary = chain_result.get("counts_by_type", {})
		for bt in chain_counts:
			counts_by_type[bt] = int(counts_by_type.get(bt, 0)) + int(chain_counts[bt])
		var chain_positions_by_type: Dictionary = chain_result.get("positions_by_type", {})
		for bt in chain_positions_by_type:
			if not positions_by_type.has(bt):
				positions_by_type[bt] = []
			(positions_by_type[bt] as Array).append_array(chain_positions_by_type[bt])

	await _collapse_without_escape_progress()
	result["count"] = normal_count
	result["positions"] = normal_world_positions
	result["counts_by_type"] = counts_by_type
	result["positions_by_type"] = positions_by_type
	return result


func _destroy_enemy_wood_spear_row_group(
		group: Array,
		owner_id: int,
		counts_by_type: Dictionary,
		positions_by_type: Dictionary,
		normal_world_positions: Array[Vector2],
		chained_positions: Array[Vector2i]
) -> int:
	var blocks_to_free: Array = []
	var destroyed_count: int = 0
	for value in group:
		var p: Vector2i = value as Vector2i
		if not _is_valid(p) or is_escape_marker_pos(p):
			continue
		var target: Block = grid[p.x][p.y]
		if target == null or target.is_rock():
			continue
		if target.is_upper_gem():
			if target.upper_owner_team == Block.UpperOwnerTeam.ENEMY and target.upper_owner_id == owner_id:
				if not chained_positions.has(p):
					chained_positions.append(p)
			else:
				grid[p.x][p.y] = null
				blocks_to_free.append(target)
				_play_gem_break_debris(target, true)
			continue
		if target.is_breakable_structure():
			grid[p.x][p.y] = null
			logic_grid[p.x][p.y] = LOGIC_UNKNOWN
			blocks_to_free.append(target)
			target.play_destroy_animation()
			_spawn_plank_debris(target.global_position)
			continue
		var target_type: Block.Type = target.block_type as Block.Type
		grid[p.x][p.y] = null
		destroyed_count += 1
		normal_world_positions.append(target.global_position)
		counts_by_type[target_type] = int(counts_by_type.get(target_type, 0)) + 1
		if not positions_by_type.has(target_type):
			positions_by_type[target_type] = []
		(positions_by_type[target_type] as Array).append(target.global_position)
		blocks_to_free.append(target)
		_play_gem_break_debris(target)

	if not blocks_to_free.is_empty():
		enemy_break_pulse.emit()
	_queue_free_blocks_after_debris(blocks_to_free)
	return destroyed_count


func destroy_enemy_upper_gems_for_owner(owner_id: int) -> void:
	var blocks_to_free: Array = []
	for pos in find_owned_upper_gems(owner_id):
		var block: Block = grid[pos.x][pos.y]
		if block == null:
			continue
		grid[pos.x][pos.y] = null
		blocks_to_free.append(block)
		_play_gem_break_debris(block, true)
	_queue_free_blocks_after_debris(blocks_to_free)


func _queue_free_blocks_after_debris(blocks: Array) -> void:
	if blocks.is_empty():
		return
	var captured_blocks := blocks.duplicate()
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		for block in captured_blocks:
			if is_instance_valid(block):
				block.queue_free()
	, CONNECT_ONE_SHOT)


func _collapse_without_escape_progress() -> void:
	var was_suppressed: bool = _suppress_escape_marker_progress
	_suppress_escape_marker_progress = true
	await _collapse_and_fill()
	_suppress_escape_marker_progress = was_suppressed


## 葉盾破碎動畫：先放大閃爍 → 拋物線跳起再跌落 + 漸層淡出
func _play_shield_break_anim(block: Block) -> void:
	var start_pos: Vector2 = block.global_position
	var original_scale: Vector2 = block.scale

	# ── 第一段：放大強調 ──
	var enlarge_tw := create_tween()
	enlarge_tw.tween_property(block, "scale", original_scale * 1.5, 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	enlarge_tw.tween_property(block, "scale", original_scale * 1.3, 0.08).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	await enlarge_tw.finished

	# ── 第二段：拋物線跌落 ──
	# 隨機水平方向（左或右），偏移 40~80 px
	var dir_x: float = (randf() * 40.0 + 40.0) * (1.0 if randf() > 0.5 else -1.0)
	var jump_height: float = 60.0 + randf() * 30.0   # 跳起高度 60~90 px
	var fall_dist: float = 200.0 + randf() * 60.0     # 下落距離 200~260 px
	var duration := 0.9

	# 使用 Tween 分兩段：上拋 + 下墜
	var tw := create_tween()
	tw.set_parallel(true)

	# X 軸：勻速水平位移
	tw.tween_property(block, "global_position:x", start_pos.x + dir_x, duration)

	# Y 軸：先向上再向下（用兩段串接的 sequential tween）
	var tw_y := create_tween()
	var peak_y: float = start_pos.y - jump_height
	var end_y: float = start_pos.y + fall_dist
	tw_y.tween_property(block, "global_position:y", peak_y, duration * 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tw_y.tween_property(block, "global_position:y", end_y, duration * 0.7).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	# 縮小回正常尺寸
	tw.tween_property(block, "scale", original_scale * 0.6, duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	# 旋轉：隨機方向旋轉
	var spin: float = (randf() * 2.0 + 1.0) * (1.0 if dir_x > 0 else -1.0)
	tw.tween_property(block, "rotation", spin * TAU * 0.5, duration)

	# 淡出：後半段漸層透明
	tw.tween_property(block, "modulate:a", 0.0, duration * 0.6).set_delay(duration * 0.4)

	tw_y.tween_callback(func() -> void:
		if is_instance_valid(block):
			block.queue_free()
	)


## 取得指定行的所有位置
func _get_row_positions(row: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in columns:
		var pos := Vector2i(x, row)
		if _cell_accepts_block(pos):
			result.append(pos)
	return result


## 取得指定欄的所有位置
func _get_col_positions(col: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in rows:
		var pos := Vector2i(col, y)
		if _cell_accepts_block(pos):
			result.append(pos)
	return result


## 檢測被消除的位置是否形成一條線（用於 FirePillar 判定）。
## 若有 [threshold] 個以上的位置在同一行或同一欄連續排列則返回 true。
## 判斷消除位置的主要方向（水平或垂直）。
## 回傳 "horizontal"、"vertical" 或 "vertical"（預設）。
func get_line_direction(positions: Array[Vector2i]) -> String:
	if positions.size() < 2:
		return "vertical"
	var by_row: Dictionary = {}
	var by_col: Dictionary = {}
	for p in positions:
		if not by_row.has(p.y):
			by_row[p.y] = []
		by_row[p.y].append(p.x)
		if not by_col.has(p.x):
			by_col[p.x] = []
		by_col[p.x].append(p.y)
	var max_h_run := 0
	for _y in by_row:
		var xs: Array = by_row[_y]
		xs.sort()
		var run := 1
		for i in range(1, xs.size()):
			if xs[i] == xs[i - 1] + 1:
				run += 1
			else:
				run = 1
			max_h_run = max(max_h_run, run)
		max_h_run = max(max_h_run, run)
	var max_v_run := 0
	for _x in by_col:
		var ys: Array = by_col[_x]
		ys.sort()
		var run := 1
		for i in range(1, ys.size()):
			if ys[i] == ys[i - 1] + 1:
				run += 1
			else:
				run = 1
			max_v_run = max(max_v_run, run)
		max_v_run = max(max_v_run, run)
	if max_h_run >= max_v_run:
		return "horizontal"
	return "vertical"


func get_wood_spear_type_for_last_tap() -> Block.UpperType:
	if not _is_valid(last_tapped_pos):
		return Block.UpperType.WOOD_SPEAR_UP
	var cell_top_y: float = float(last_tapped_pos.y * CELL_SIZE)
	var cell_local_y: float = last_tapped_local_pos.y - cell_top_y
	if last_tapped_local_pos.x < 0.0 or cell_local_y < 0.0 or cell_local_y > float(CELL_SIZE):
		cell_local_y = float(CELL_SIZE) * 0.5
	if cell_local_y < float(CELL_SIZE) * 0.5:
		return Block.UpperType.WOOD_SPEAR_UP
	return Block.UpperType.WOOD_SPEAR_DOWN


func get_wood_spear_type_for_positions(_positions: Array[Vector2i]) -> Block.UpperType:
	return get_wood_spear_type_for_last_tap()


func has_line_match(positions: Array[Vector2i], threshold: int) -> bool:
	if positions.size() < threshold:
		return false

	# 檢查行：按 y 分組，按 x 排序，找連續子序列
	var by_row: Dictionary = {}  # y -> Array[int]（x 座標陣列）
	var by_col: Dictionary = {}  # x -> Array[int]（y 座標陣列）

	for p in positions:
		if not by_row.has(p.y):
			by_row[p.y] = []
		by_row[p.y].append(p.x)
		if not by_col.has(p.x):
			by_col[p.x] = []
		by_col[p.x].append(p.y)

	for _y in by_row:
		var xs: Array = by_row[_y]
		xs.sort()
		var run := 1
		for i in range(1, xs.size()):
			if xs[i] == xs[i - 1] + 1:
				run += 1
				if run >= threshold:
					return true
			else:
				run = 1

	for _x in by_col:
		var ys: Array = by_col[_x]
		ys.sort()
		var run := 1
		for i in range(1, ys.size()):
			if ys[i] == ys[i - 1] + 1:
				run += 1
				if run >= threshold:
					return true
			else:
				run = 1

	return false


# ── 十字形範圍 & 選擇模式 ────────────────────────────────────────────

## 取得十字形爆炸/預覽位置：中心 + 上下左右各延伸2格
func _get_cross_positions(center: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if _cell_accepts_block(center):
		result.append(center)
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		for dist in range(1, 3):
			var p: Vector2i = center + dir * dist
			if _cell_accepts_block(p):
				result.append(p)
	return result


## 進入選擇模式（由 main.gd 呼叫，玩家懸停預覽，點擊確認轉換）
func enter_selection_mode(convert_type: Block.Type, pattern: String = "cross", max_count: int = 1) -> void:
	if _selection_mode:
		cancel_selection_mode()
	_selection_mode = true
	_selection_convert_type = convert_type
	_selection_pattern = pattern
	_selection_max_count = maxi(1, max_count)
	_selection_selected_positions.clear()
	_selection_finished_emitted = false
	_preview_center = Vector2i(-1, -1)
	_refresh_selection_valid_centers()


## 離開選擇模式（取消）
func exit_selection_mode() -> void:
	cancel_selection_mode()


func cancel_selection_mode() -> void:
	if not _selection_mode:
		return
	_finish_selection([], true)


func _finish_selection(positions: Array, cancelled: bool) -> void:
	if _selection_finished_emitted:
		return
	var keep_order_labels: bool = not cancelled and _selection_max_count > 1 and not _selection_order_labels.is_empty()
	_selection_finished_emitted = true
	_selection_mode = false
	if keep_order_labels:
		_clear_preview_overlays(false)
		_selection_valid_centers.clear()
		var labels_to_free: Array = _selection_order_labels.duplicate()
		_selection_order_labels.clear()
		_free_selection_order_labels_later(labels_to_free)
	else:
		_clear_selection_visuals()
	_selection_selected_positions.clear()
	_selection_max_count = 1
	_preview_center = Vector2i(-1, -1)
	selection_finished.emit({
		"positions": positions,
		"cancelled": cancelled,
	})


## 更新十字預覽覆蓋層（黃色半透明方塊顯示在預覽位置上方）
func _update_cross_preview(center: Vector2i) -> void:
	_update_selection_preview(center)


## 通用選擇預覽（依 _selection_pattern 決定形狀，依 _selection_convert_type 決定顏色）
func _update_selection_preview(center: Vector2i) -> void:
	_clear_preview_overlays()
	_preview_center = center
	var positions := _get_selection_positions(center)
	var display_positions: Array[Vector2i] = _selection_selected_positions.duplicate()
	for p in positions:
		if not display_positions.has(p):
			display_positions.append(p)
	_set_selection_preview_positions(display_positions)
	if display_positions.is_empty():
		return
	var color: Color = _selection_color_for_center(center)
	for p in display_positions:
		var overlay: ColorRect = _create_selection_preview_overlay(p, color)
		_preview_overlays.append(overlay)
	_refresh_selection_order_labels()


## 依目前 _selection_pattern 取得選擇範圍位置
func _get_selection_positions(center: Vector2i) -> Array[Vector2i]:
	if not _is_selection_center_viable(center):
		return []
	if _selection_pattern == "fireball":
		return _get_area_positions(center)
	if _selection_pattern == "single":
		var result: Array[Vector2i] = []
		if _cell_accepts_block(center):
			result.append(center)
		return result
	if _selection_pattern == "single_top_bottom":
		var result: Array[Vector2i] = []
		if _cell_accepts_block(center) and (center.y == 0 or center.y == rows - 1):
			result.append(center)
		return result
	return _get_cross_positions(center)


func _is_selection_center_viable(center: Vector2i) -> bool:
	if not _cell_accepts_block(center):
		return false
	match _selection_pattern:
		"single":
			var block: Block = grid[center.x][center.y]
			return block != null and not _is_static_obstacle(block)
		"single_top_bottom":
			if center.y != 0 and center.y != rows - 1:
				return false
			var block: Block = grid[center.x][center.y]
			return block != null and not _is_static_obstacle(block)
		_:
			return true


func _selection_color_for_center(center: Vector2i) -> Color:
	if _selection_pattern == "single" and _is_valid(center):
		var block: Block = grid[center.x][center.y]
		if block != null:
			return Block.COLORS.get(block.block_type, Color(1.0, 0.92, 0.23))
	return Block.COLORS.get(_selection_convert_type, Color(1.0, 0.92, 0.23))


func _refresh_selection_valid_centers() -> void:
	_selection_valid_centers.clear()
	for x in columns:
		for y in rows:
			var center: Vector2i = Vector2i(x, y)
			if _is_selection_center_viable(center):
				_selection_valid_centers.append(center)


func get_selection_valid_centers() -> Array[Vector2i]:
	return _selection_valid_centers.duplicate()


func get_selection_preview_positions() -> Array[Vector2i]:
	return _selection_preview_positions.duplicate()


func _set_selection_preview_positions(positions: Array[Vector2i]) -> void:
	_selection_preview_positions = positions.duplicate()
	selection_preview_changed.emit(_selection_preview_positions)


func _create_selection_preview_overlay(pos: Vector2i, color: Color) -> ColorRect:
	var overlay := ColorRect.new()
	overlay.color = Color(color.r, color.g, color.b, 0.30)
	overlay.size = Vector2(CELL_SIZE, CELL_SIZE)
	overlay.position = Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
	overlay.z_index = 12
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	return overlay


func _clear_selection_visuals() -> void:
	_clear_selection_preview()
	_selection_valid_centers.clear()


## 清除所有預覽覆蓋層
func _clear_preview_overlays(clear_order_labels: bool = true) -> void:
	for overlay in _preview_overlays:
		if is_instance_valid(overlay):
			overlay.queue_free()
	_preview_overlays.clear()
	if clear_order_labels:
		_clear_selection_order_labels()


func _clear_selection_preview() -> void:
	_clear_preview_overlays()
	var empty_positions: Array[Vector2i] = []
	_set_selection_preview_positions(empty_positions)


func _clear_selection_hover_preview() -> void:
	_clear_preview_overlays(false)
	_refresh_selection_order_labels()
	_set_selection_preview_positions(_selection_selected_positions)


func _refresh_selection_order_labels() -> void:
	_clear_selection_order_labels()
	for i in range(_selection_selected_positions.size()):
		var selected_pos: Vector2i = _selection_selected_positions[i]
		var order_label: Label = _create_selection_order_label(selected_pos, i + 1)
		_selection_order_labels.append(order_label)


func _create_selection_order_label(pos: Vector2i, order: int) -> Label:
	var label := Label.new()
	label.text = str(order)
	label.size = Vector2(CELL_SIZE, CELL_SIZE)
	label.position = Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE)
	label.z_index = 14
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", SELECTION_ORDER_FONT)
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(label)
	return label


func _clear_selection_order_labels() -> void:
	for label in _selection_order_labels:
		if is_instance_valid(label):
			label.queue_free()
	_selection_order_labels.clear()


func _free_selection_order_labels_later(labels: Array) -> void:
	get_tree().create_timer(0.45).timeout.connect(func() -> void:
		for label in labels:
			if is_instance_valid(label):
				(label as Label).queue_free()
	, CONNECT_ONE_SHOT)


# ── 融合提示系統 ─────────────────────────────────────────────────────

## 由 main.gd 呼叫，註冊隊伍的融合技能。
## 每個項目：{ gem_type: Block.Type, threshold: int, label: String, trigger_type: String, team_index: int }
func set_fuse_skills(skills: Array[Dictionary]) -> void:
	_fuse_skills = skills
	_update_fuse_hints()


## 掃描連接群並顯示/隱藏融合提示
func _update_fuse_hints() -> void:
	# 第一階段：標記所有現有提示為待清理（不立即隱藏）
	for x in columns:
		for y in rows:
			var block: Block = grid[x][y]
			if block != null:
				block.mark_fuse_hint_stale()

	if _fuse_skills.is_empty():
		# 無技能時直接清理所有待清理提示
		for x in columns:
			for y in rows:
				var block: Block = grid[x][y]
				if block != null:
					block.hide_fuse_hint_if_stale()
		return

	# 與實際融合決策一致：需求寶石數高者優先；同需求時隊伍前排優先。
	var sorted_skills := _fuse_skills.duplicate()
	sorted_skills.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_threshold: int = int(a.get("threshold", 0))
		var b_threshold: int = int(b.get("threshold", 0))
		if a_threshold != b_threshold:
			return a_threshold > b_threshold
		var a_team_index: int = int(a.get("team_index", 999))
		var b_team_index: int = int(b.get("team_index", 999))
		if a_team_index != b_team_index:
			return a_team_index < b_team_index
		var a_priority: int = int(a.get("priority", 99))
		var b_priority: int = int(b.get("priority", 99))
		if a_priority != b_priority:
			return a_priority < b_priority
		return int(a.get("skill_order", 999)) < int(b.get("skill_order", 999))
	)

	# 追蹤已有提示的寶石（最高優先級優先）
	var hinted: Dictionary = {}  # Vector2i -> true

	# 第二階段：對每個融合技能（依優先級順序）掃描連接群
	for skill in sorted_skills:
		var gem_type: Block.Type = skill.gem_type as Block.Type
		var threshold: int = skill.threshold
		var label: String = skill.label
		var trigger_type: String = skill.get("trigger_type", "count")

		var visited := {}
		for x in columns:
			for y in rows:
				var pos := Vector2i(x, y)
				if visited.has(pos):
					continue
				var block: Block = grid[x][y]
				if block == null or block.block_type != gem_type or block.is_upper_gem():
					continue

				var group := _find_connected(pos)
				for gp in group:
					visited[gp] = true

				# 跳過已有更高優先級提示的群組
				var already_hinted := false
				for gp in group:
					if hinted.has(gp):
						already_hinted = true
						break
				if already_hinted:
					continue

				# 計算群組的有效爆炸值（X5 寶石計為 5）
				var effective_count := 0
				for gp2 in group:
					var gb: Block = grid[gp2.x][gp2.y]
					if gb != null:
						effective_count += gb.get_blast_value()

				# 檢查此群組是否符合融合條件
				var qualifies := false
				match trigger_type:
					"count":
						qualifies = effective_count >= threshold
					"line":
						qualifies = group.size() >= threshold and has_line_match(group, threshold)

				if qualifies:
					for gp in group:
						var b: Block = grid[gp.x][gp.y]
						if b != null:
							b.show_fuse_hint(label)
							hinted[gp] = true
	# 第三階段：清理仍為待清理狀態的提示（不再符合條件的方塊）
	for x in columns:
		for y in rows:
			var block: Block = grid[x][y]
			if block != null:
				block.hide_fuse_hint_if_stale()


# ── 教學系統 ──────────────────────────────────────────────────

## 設定教學點擊過濾：只允許 positions 中的格子被點擊
func set_tutorial_filter(positions: Array[Vector2i]) -> void:
	_tutorial_filter = positions


## 清除教學點擊過濾
func clear_tutorial_filter() -> void:
	_tutorial_filter.clear()


## 暗化全部寶石，只保持 positions 中的寶石明亮
func set_tutorial_highlight(positions: Array[Vector2i]) -> void:
	var highlight_set := {}
	for p in positions:
		highlight_set[p] = true
	for x in columns:
		for y in rows:
			var block: Block = grid[x][y]
			if block == null:
				continue
			var gp := Vector2i(x, y)
			var target: Color = Color(1, 1, 1, 1) if highlight_set.has(gp) else Color(0.25, 0.25, 0.3, 1.0)
			var tw := create_tween()
			tw.tween_property(block, "modulate", target, 0.3)


## 還原所有寶石亮度
func clear_tutorial_highlight() -> void:
	for x in columns:
		for y in rows:
			var block: Block = grid[x][y]
			if block == null:
				continue
			var tw := create_tween()
			tw.tween_property(block, "modulate", Color(1, 1, 1, 1), 0.3)


## 在指定格子上顯示手指圖示（浮動動畫）
func show_hand_hint(grid_pos: Vector2i) -> void:
	hide_hand_hint()
	var tex: Texture2D = load("res://assets/Hand3.png")
	if tex == null:
		return
	_hand_sprite = Sprite2D.new()
	_hand_sprite.texture = tex
	_hand_sprite.z_index = 50
	_hand_sprite.scale = Vector2(0.7, 0.7)
	var base_pos: Vector2 = grid_to_world(grid_pos) + Vector2(16, 20)
	_hand_sprite.position = base_pos
	add_child(_hand_sprite)
	# 浮動上下動畫（循環）
	_hand_tween = create_tween().set_loops()
	_hand_tween.tween_property(_hand_sprite, "position:y", base_pos.y - 8, 0.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_hand_tween.tween_property(_hand_sprite, "position:y", base_pos.y + 8, 0.5) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)


## 隱藏手指圖示
func hide_hand_hint() -> void:
	if _hand_tween != null and _hand_tween.is_valid():
		_hand_tween.kill()
		_hand_tween = null
	if _hand_sprite != null:
		_hand_sprite.queue_free()
		_hand_sprite = null


# ── 並行融合系統（允許玩家在融合動畫期間立即觸發另一次融合）────────────

## 模擬掉落後的棋盤狀態（用於驗證並行融合點擊）
func _simulate_post_collapse_grid() -> Array:
	var sim: Array = []
	sim.resize(columns)
	for x in columns:
		sim[x] = []
		sim[x].resize(rows)
		for y in rows:
			var pos := Vector2i(x, y)
			sim[x][y] = VISUAL_HOLE if _is_hole_pos(pos) else grid[x][y]

	# 融合流程中，上階寶石將被放置在 last_tapped_pos。
	# fuseSolution1：保留舊版模擬佔位，讓它像一般可移動內容一樣參與坍塌。
	# fuseSolution2：使用固定佔位保留原融合格，會像屋頂一樣影響斜向滑落。
	if (ACTIVE_FUSE_SOLUTION == FUSE_SOLUTION_1 or ACTIVE_FUSE_SOLUTION == FUSE_SOLUTION_2) \
			and _cell_accepts_block(last_tapped_pos) \
			and sim[last_tapped_pos.x][last_tapped_pos.y] == null:
		if ACTIVE_FUSE_SOLUTION == FUSE_SOLUTION_2:
			sim[last_tapped_pos.x][last_tapped_pos.y] = FLOATING_UPPER_PLACEHOLDER
		else:
			sim[last_tapped_pos.x][last_tapped_pos.y] = FUSE_SOLUTION1_UPPER_PLACEHOLDER

	# 模擬掉落：ROCK 固定，新寶石從頂部進入，ROCK 下方空洞可由鄰欄斜向滑入。
	var spawn_counts: Array = []
	spawn_counts.resize(columns)
	for column_index in columns:
		spawn_counts[column_index] = 0
	_settle_visual_state_with_rocks(sim, spawn_counts, true)
	if ACTIVE_FUSE_SOLUTION == FUSE_SOLUTION_3:
		# fuseSolution3：先讓棋盤完全坍塌，之後才模擬高階寶石插回原欄位，避免它在坍塌中形成斜滑屋頂。
		_simulate_insert_floating_upper_after_collapse(sim, last_tapped_pos)

	return sim


func _simulate_insert_floating_upper_after_collapse(sim_grid: Array, pos: Vector2i) -> void:
	if not _cell_accepts_block(pos) or is_escape_marker_pos(pos):
		return
	if _variant_cell_is_stationary_obstacle(sim_grid[pos.x][pos.y]):
		return
	var top_y: int = pos.y
	while top_y > 0:
		var above := Vector2i(pos.x, top_y - 1)
		if not _cell_accepts_block(above) or is_escape_marker_pos(above):
			break
		if _variant_cell_is_stationary_obstacle(sim_grid[above.x][above.y]):
			break
		top_y -= 1
	for y in range(top_y, pos.y):
		sim_grid[pos.x][y] = sim_grid[pos.x][y + 1]
	sim_grid[pos.x][pos.y] = FLOATING_UPPER_PLACEHOLDER


## 在模擬棋盤中尋找指定方塊的位置
func _find_block_in_sim(block: Block, sim_grid: Array) -> Vector2i:
	for x in columns:
		for y in rows:
			var cell: Variant = sim_grid[x][y]
			if cell is Block and cell == block:
				return Vector2i(x, y)
	return Vector2i(-1, -1)


## 在模擬棋盤上搜尋相連同類寶石（BFS）
func _find_connected_in_grid(start: Vector2i, sim_grid: Array) -> Array[Vector2i]:
	var cell: Variant = sim_grid[start.x][start.y]
	if cell == null or cell is not Block:
		return []
	var block: Block = cell as Block
	if block.is_upper_gem() or block.is_obstacle():
		return []

	var target_type: Block.Type = block.block_type as Block.Type
	var visited := {}
	var connected: Array[Vector2i] = []
	var queue: Array[Vector2i] = [start]

	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		if visited.has(current):
			continue
		if not _is_valid(current):
			continue
		var cur_cell: Variant = sim_grid[current.x][current.y]
		if cur_cell == null or cur_cell is not Block:
			continue
		var cur_block: Block = cur_cell as Block
		if cur_block.block_type != target_type:
			continue
		if cur_block.is_upper_gem() or cur_block.is_obstacle():
			continue

		visited[current] = true
		connected.append(current)

		queue.append(Vector2i(current.x + 1, current.y))
		queue.append(Vector2i(current.x - 1, current.y))
		queue.append(Vector2i(current.x, current.y + 1))
		queue.append(Vector2i(current.x, current.y - 1))

	return connected


## 檢查一組相連寶石是否會觸發任何融合技能
func _would_trigger_fuse(gem_type: Block.Type, group: Array[Vector2i]) -> bool:
	for skill in _fuse_skills:
		if skill.gem_type as Block.Type != gem_type:
			continue
		var threshold: int = skill.threshold
		var trigger_type: String = skill.get("trigger_type", "count")
		match trigger_type:
			"count":
				if group.size() >= threshold:
					return true
			"line":
				if group.size() >= threshold and has_line_match(group, threshold):
					return true
	return false


## 嘗試在融合動畫期間立即觸發並行融合。
## 驗證：1) 模擬掉落後棋盤仍可行 2) 真實棋盤也可行 → 立即消除並發出信號。
func _try_concurrent_fuse(click_pos: Vector2i, local_pos: Vector2) -> void:
	var block: Block = grid[click_pos.x][click_pos.y]
	if block == null or block.is_upper_gem() or block.is_obstacle():
		return

	# 1. 在模擬掉落後的棋盤中驗證可行性
	var sim_grid := _simulate_post_collapse_grid()
	var sim_pos := _find_block_in_sim(block, sim_grid)
	if sim_pos == Vector2i(-1, -1):
		return
	var sim_matches := _find_connected_in_grid(sim_pos, sim_grid)
	if sim_matches.is_empty():
		return
	var gem_type: Block.Type = block.block_type as Block.Type
	if not _would_trigger_fuse(gem_type, sim_matches):
		return

	# 2. 在真實棋盤再次驗證（確保實際可消除數量足夠）
	var real_matches := _find_connected(click_pos)
	if real_matches.is_empty():
		return
	if not _would_trigger_fuse(gem_type, real_matches):
		return

	# 3. 立即消除（skip_collapse 已為 true）並發出 gems_blasted 信號
	_concurrent_fuse_tapped_pos = click_pos
	_concurrent_fuse_tapped_local_pos = local_pos
	_destroy_blocks(real_matches)


# ── 長按爆炸預覽系統 ─────────────────────────────────────────────────

const PREVIEW_OVERLAY_Z := 5   # 爆炸範圍覆蓋層 z_index
const PREVIEW_BLOCK_Z := 8     # 受影響方塊在預覽時的 z_index（高於覆蓋層）
const PREVIEW_BORDER_Z := 9    # 邊框覆蓋層 z_index
const PREVIEW_INITIAL_OVERLAY_Z := 10  # 初始爆炸半透明色層（蓋在受影響寶石上方）
const PREVIEW_INITIAL_ALPHA_MAX := 0.50
const PREVIEW_INITIAL_ALPHA_MIN := 0.0
const PREVIEW_INITIAL_FADE_IN := 0.22
const PREVIEW_INITIAL_HOLD := 0.16
const PREVIEW_INITIAL_FADE_OUT := 0.18
const PREVIEW_CHAIN_STEP_GAP := 0.05
const PREVIEW_LOOP_BORDER_WIDTH := 4.0
const PREVIEW_LOOP_BORDER_ALPHA_MAX := 0.90
const PREVIEW_LOOP_BORDER_STEP_DUR := 0.018
const PREVIEW_LOOP_BORDER_HOLD := 0.24
const PREVIEW_LOOP_BORDER_FADE_OUT := 0.18
const PREVIEW_FAST_COMBO_BASE_STEPS := 5.0
const PREVIEW_FAST_COMBO_MIN_SCALE := 0.45
const PREVIEW_PRESS_SCALE := 0.86
const PREVIEW_PRESS_BOUNCE_SCALE := 1.08
const PREVIEW_PRESS_DOWN_OFFSET := 4.0
const PREVIEW_PRESS_DOWN_DUR := 0.08
const PREVIEW_PRESS_RELEASE_DUR := 0.13
const PREVIEW_PRESS_SETTLE_DUR := 0.09


func _is_player_upper_gem(block: Block) -> bool:
	return block != null \
			and block.is_upper_gem() \
			and block.upper_owner_team == Block.UpperOwnerTeam.PLAYER


func _preview_combo_time_scale(step_count: int) -> float:
	if step_count <= 0:
		return 1.0
	return clampf(PREVIEW_FAST_COMBO_BASE_STEPS / float(maxi(step_count, 1)), PREVIEW_FAST_COMBO_MIN_SCALE, 1.0)


## 計算高階寶石的完整爆炸範圍（含連鏈遞迴）
## 回傳 { direct: Array[Vector2i], initial: Array[Vector2i], chain_groups: Array[Dictionary], chain_uppers: Array[Vector2i] }
## chain_groups: [{ ut: UpperType, positions: Array[Vector2i] }, ...]
func _calc_blast_preview(start_pos: Vector2i, start_ut: Block.UpperType) -> Dictionary:
	var direct_blast: Dictionary = {}   # 直接爆炸範圍
	var initial_blast: Dictionary = {}  # 第一波爆炸範圍（給彩色脈衝層）
	initial_blast[start_pos] = true
	var chain_uppers: Array[Vector2i] = []
	var processed_uppers: Dictionary = {}
	processed_uppers[start_pos] = true

	# 連鏈爆炸：BFS 佇列（任何 upper 觸發，包含被連鎖到的水劍）
	var next_queue: Array[Dictionary] = []
	var chain_groups: Array[Dictionary] = []   # [{ ut, positions }]
	var all_chain: Dictionary = {}             # 去重用

	# ── 水劍特例：套用「貪心連線」連鎖預測（與 _handle_water_sword_sequence 相同邏輯）──
	if start_ut == Block.UpperType.WATER_SLASH:
		var sw_groups: Array[Dictionary] = _calc_water_slash_chain_preview(
			start_pos, processed_uppers, all_chain, chain_uppers, next_queue, initial_blast, true)
		for g in sw_groups:
			chain_groups.append(g)
	else:
		# 第一層：直接爆炸
		var first_positions: Array[Vector2i] = _get_blast_positions_for_upper(start_pos, start_ut)
		for p in first_positions:
			if p == start_pos:
				continue
			if _is_valid(p) and grid[p.x][p.y] != null and grid[p.x][p.y].is_rock():
				continue
			direct_blast[p] = true
			initial_blast[p] = true
			if _is_valid(p) and grid[p.x][p.y] != null:
				var b: Block = grid[p.x][p.y]
				if _is_player_upper_gem(b) and not processed_uppers.has(p):
					chain_uppers.append(p)
					processed_uppers[p] = true
					next_queue.append({"pos": p, "ut": b.upper_type})

	# 後續層：連鏈爆炸（按觸發的高階寶石分組）
	while next_queue.size() > 0:
		var current: Dictionary = next_queue.pop_front()
		var cpos: Vector2i = current.pos
		var cut: Block.UpperType = current.ut
		# 連鏈水劍：使用專用貪心連鎖，而非單純的 column 爆破
		if cut == Block.UpperType.WATER_SLASH:
			var sw_groups2: Array[Dictionary] = _calc_water_slash_chain_preview(
				cpos, processed_uppers, all_chain, chain_uppers, next_queue, initial_blast, false)
			for g in sw_groups2:
				chain_groups.append(g)
			continue
		var cpositions: Array[Vector2i] = _get_blast_positions_for_upper(cpos, cut)
		var group_positions: Array[Vector2i] = []
		var group_preview_positions: Array[Vector2i] = []
		for p in cpositions:
			if not _is_valid(p):
				continue
			if grid[p.x][p.y] != null and grid[p.x][p.y].is_rock():
				continue
			if not group_preview_positions.has(p):
				group_preview_positions.append(p)
			if p == cpos or direct_blast.has(p) or all_chain.has(p):
				continue
			all_chain[p] = true
			group_positions.append(p)
			if grid[p.x][p.y] != null:
				var b: Block = grid[p.x][p.y]
				if _is_player_upper_gem(b) and not processed_uppers.has(p):
					chain_uppers.append(p)
					processed_uppers[p] = true
					next_queue.append({"pos": p, "ut": b.upper_type})
		if group_preview_positions.size() > 0:
			chain_groups.append({
				"ut": cut,
				"positions": group_positions,
				"preview_positions": group_preview_positions,
				"trigger_pos": cpos,
			})

	return {
		"direct": direct_blast.keys(),
		"initial": initial_blast.keys(),
		"direct_ut": start_ut,
		"chain_groups": chain_groups,
		"chain_uppers": chain_uppers,
	}


## 計算「以 seed_pos 為起點」的水劍貪心連鎖預覽。
## 會將後續水劍與路徑上波及的非水劍 upper 加入 chain_uppers / processed_uppers，
## 並將非水劍 upper 推入 bfs_queue 等後續 BFS 處理；visited 是共享的格子去重集合。
## 回傳：每段水劍連線/最後一把欄位爆破組成的 Dictionary 陣列。
func _calc_water_slash_chain_preview(
		seed_pos: Vector2i,
		processed_uppers: Dictionary,
		visited: Dictionary,
		chain_uppers: Array[Vector2i],
		bfs_queue: Array[Dictionary],
		initial_blast: Dictionary,
		mark_initial: bool) -> Array[Dictionary]:
	# 收集所有「尚未處理過」的水劍位置（含 seed 自身）
	var swords: Array[Vector2i] = [seed_pos]
	for sp in find_upper_gems(Block.UpperType.WATER_SLASH):
		if sp == seed_pos:
			continue
		if processed_uppers.has(sp):
			continue
		swords.append(sp)

	# 貪心建構連鎖順序：每次選距上一把最遠的水劍
	var order: Array[Vector2i] = [seed_pos]
	var remaining: Array[Vector2i] = []
	for s in swords:
		if s != seed_pos:
			remaining.append(s)
	while not remaining.is_empty():
		var cur: Vector2i = order[order.size() - 1]
		var best_idx: int = 0
		var best_d: float = -1.0
		for i in remaining.size():
			var diff: Vector2 = Vector2(remaining[i] - cur)
			var d: float = diff.length_squared()
			if d > best_d:
				best_d = d
				best_idx = i
		order.append(remaining[best_idx])
		remaining.remove_at(best_idx)

	# 把後續的水劍標記為 chain_uppers（亮起為 upper border）
	for k in range(1, order.size()):
		var sp_next: Vector2i = order[k]
		if not processed_uppers.has(sp_next):
			chain_uppers.append(sp_next)
			processed_uppers[sp_next] = true

	# 計算每段連線格子；最後一把走整欄
	var groups: Array[Dictionary] = []
	for i in order.size():
		var sp_i: Vector2i = order[i]
		var seg_cells: Array[Vector2i]
		if i < order.size() - 1:
			seg_cells = _line_cells_between(sp_i, order[i + 1])
		else:
			seg_cells = _get_col_positions(sp_i.x)
		var group_pos: Array[Vector2i] = []
		var group_preview_pos: Array[Vector2i] = []
		for c in seg_cells:
			if not _is_valid(c):
				continue
			var b: Block = grid[c.x][c.y]
			if b != null and b.is_rock():
				continue
			if not group_preview_pos.has(c):
				group_preview_pos.append(c)
			if mark_initial and i == 0:
				initial_blast[c] = true
			if c == seed_pos or visited.has(c):
				continue
			visited[c] = true
			if processed_uppers.has(c):
				# 是水劍序列中的另一把水劍 — 跳過格子本身的「被爆」標記（亮 upper border 即可）
				continue
			group_pos.append(c)
			# 路徑上若有非水劍 upper，加入 BFS 佇列待後續連鎖
			if _is_player_upper_gem(b) and not processed_uppers.has(c):
				processed_uppers[c] = true
				chain_uppers.append(c)
				bfs_queue.append({"pos": c, "ut": b.upper_type})
		if group_preview_pos.size() > 0:
			groups.append({
				"ut": Block.UpperType.WATER_SLASH,
				"positions": group_pos,
				"preview_positions": group_preview_pos,
				"trigger_pos": sp_i,
			})
	return groups


## 顯示長按爆炸預覽：漸變暗化棋盤 + 高亮爆炸範圍
func _show_blast_preview(pos: Vector2i) -> void:
	var block: Block = grid[pos.x][pos.y]
	if not _is_player_upper_gem(block):
		return
	_longpress_active = true
	_play_longpress_press_down(block)

	var result: Dictionary = _calc_blast_preview(pos, block.upper_type)
	var direct: Array = result.direct
	var direct_ut: Block.UpperType = result.direct_ut
	var chain_groups: Array = result.chain_groups
	var chain_uppers: Array = result.chain_uppers

	var preview_steps: Array[Dictionary] = _build_blast_preview_steps(
		result,
		UpperGemDefs.get_preview_color(direct_ut, Block.COLORS.get(block.block_type, Color.WHITE))
	)
	_add_initial_blast_overlay(preview_steps)

	# 收集所有不暗化的位置
	var bright_set: Dictionary = {}
	bright_set[pos] = true
	for p in direct:
		bright_set[p] = true
	for group in chain_groups:
		for p in group.positions:
			bright_set[p] = true
	for p in chain_uppers:
		bright_set[p] = true

	# 終止先前的暗化/還原 tween
	if _longpress_dim_tween != null and _longpress_dim_tween.is_valid():
		_longpress_dim_tween.kill()
	_longpress_dim_tween = create_tween().set_parallel(true)

	# 暗化所有未受影響的方塊（漸變）
	var dim_color := Color(0.3, 0.3, 0.35, 1.0)
	for x in columns:
		for y in rows:
			var gp := Vector2i(x, y)
			var b: Block = grid[x][y]
			if b != null and not bright_set.has(gp):
				_longpress_dim_tween.tween_property(b, "modulate", dim_color, PREVIEW_FADE_DUR) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 抬高受影響方塊的 z_index（讓寶石顯示在覆蓋層之上）
	_longpress_raised_blocks.clear()
	for p_key in bright_set:
		var bp: Vector2i = p_key
		if _is_valid(bp) and grid[bp.x][bp.y] != null:
			var rb: Block = grid[bp.x][bp.y]
			rb.z_index = PREVIEW_BLOCK_Z
			_longpress_raised_blocks.append(rb)

	blast_preview_entered.emit()


func _play_longpress_press_down(block: Block) -> void:
	_reset_longpress_press_bounce()
	_longpress_press_block = block
	_longpress_press_original_scale = block.scale
	_longpress_press_original_position = block.position

	_longpress_press_tween = create_tween()
	_longpress_press_tween.tween_property(block, "scale", _longpress_press_original_scale * PREVIEW_PRESS_SCALE, PREVIEW_PRESS_DOWN_DUR) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_longpress_press_tween.parallel().tween_property(block, "position", _longpress_press_original_position + Vector2(0.0, PREVIEW_PRESS_DOWN_OFFSET), PREVIEW_PRESS_DOWN_DUR) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_longpress_press_tween.tween_callback(func() -> void:
		_longpress_press_tween = null
	)


func _play_longpress_release_bounce() -> void:
	if _longpress_press_tween != null and _longpress_press_tween.is_valid():
		_longpress_press_tween.kill()
	_longpress_press_tween = null
	if not is_instance_valid(_longpress_press_block):
		_longpress_press_block = null
		return

	var block := _longpress_press_block
	_longpress_press_tween = create_tween()
	_longpress_press_tween.tween_property(block, "scale", _longpress_press_original_scale * PREVIEW_PRESS_BOUNCE_SCALE, PREVIEW_PRESS_RELEASE_DUR) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_longpress_press_tween.parallel().tween_property(block, "position", _longpress_press_original_position, PREVIEW_PRESS_RELEASE_DUR) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	_longpress_press_tween.tween_property(block, "scale", _longpress_press_original_scale, PREVIEW_PRESS_SETTLE_DUR) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	_longpress_press_tween.tween_callback(func() -> void:
		if is_instance_valid(block):
			block.position = _longpress_press_original_position
			block.scale = _longpress_press_original_scale
		_longpress_press_tween = null
		_longpress_press_block = null
	)


func _reset_longpress_press_bounce(restore_transform: bool = true) -> void:
	if _longpress_press_tween != null and _longpress_press_tween.is_valid():
		_longpress_press_tween.kill()
	_longpress_press_tween = null
	if restore_transform and is_instance_valid(_longpress_press_block):
		_longpress_press_block.scale = _longpress_press_original_scale
		_longpress_press_block.position = _longpress_press_original_position
	_longpress_press_block = null


func _build_blast_preview_steps(result: Dictionary, initial_color: Color) -> Array[Dictionary]:
	var steps: Array[Dictionary] = []
	var initial_positions: Array[Vector2i] = _unique_preview_positions(result.initial as Array)
	if not initial_positions.is_empty():
		steps.append({"positions": initial_positions, "color": initial_color})

	var chain_groups: Array = result.get("chain_groups", []) as Array
	for group_value in chain_groups:
		var group: Dictionary = group_value as Dictionary
		var raw_positions: Array = group.get("preview_positions", group.get("positions", [])) as Array
		var group_positions: Array[Vector2i] = _unique_preview_positions(raw_positions)
		if group.has("trigger_pos"):
			var trigger_pos: Vector2i = group["trigger_pos"] as Vector2i
			if not group_positions.has(trigger_pos):
				group_positions.push_front(trigger_pos)
		if group_positions.is_empty():
			continue
		if not steps.is_empty():
			var previous_step: Dictionary = steps[steps.size() - 1]
			if _same_preview_positions(previous_step.get("positions", []) as Array, group_positions):
				continue
		var ut: Block.UpperType = group.get("ut", Block.UpperType.NONE) as Block.UpperType
		steps.append({
			"positions": group_positions,
			"color": UpperGemDefs.get_preview_color(ut, initial_color),
		})
	return steps


func _unique_preview_positions(values: Array) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for value in values:
		var p: Vector2i = value as Vector2i
		if _is_valid(p) and not result.has(p):
			result.append(p)
	return result


func _same_preview_positions(left_values: Array, right_values: Array[Vector2i]) -> bool:
	if left_values.size() != right_values.size():
		return false
	for value in left_values:
		var p: Vector2i = value as Vector2i
		if not right_values.has(p):
			return false
	return true


func _collect_preview_step_positions(steps: Array[Dictionary]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for step_value in steps:
		var step: Dictionary = step_value as Dictionary
		var positions: Array = step.get("positions", []) as Array
		for position_value in positions:
			var p: Vector2i = position_value as Vector2i
			if _is_valid(p) and not result.has(p):
				result.append(p)
	return result


func _preview_loop_border_color(steps: Array[Dictionary]) -> Color:
	if steps.is_empty():
		return Color(1.0, 1.0, 1.0, PREVIEW_LOOP_BORDER_ALPHA_MAX)
	var first_step: Dictionary = steps[0]
	var color: Color = first_step.get("color", Color.WHITE) as Color
	return Color(color.r, color.g, color.b, PREVIEW_LOOP_BORDER_ALPHA_MAX).lightened(0.35)


func _create_loop_preview_border_segments(positions: Array[Vector2i], color: Color) -> Array[Dictionary]:
	var position_set: Dictionary = {}
	for p in positions:
		if _is_valid(p):
			position_set[p] = true

	var area_center: Vector2 = _preview_positions_center(positions)
	var segments: Array[Dictionary] = []
	for p in positions:
		if not _is_valid(p):
			continue
		if not position_set.has(p + Vector2i(0, -1)):
			segments.append(_create_loop_preview_border_segment(
				Vector2(p.x * CELL_SIZE, p.y * CELL_SIZE),
				Vector2(CELL_SIZE, PREVIEW_LOOP_BORDER_WIDTH),
				"x",
				color,
				area_center
			))
		if not position_set.has(p + Vector2i(1, 0)):
			segments.append(_create_loop_preview_border_segment(
				Vector2((p.x + 1) * CELL_SIZE - PREVIEW_LOOP_BORDER_WIDTH, p.y * CELL_SIZE),
				Vector2(PREVIEW_LOOP_BORDER_WIDTH, CELL_SIZE),
				"y",
				color,
				area_center
			))
		if not position_set.has(p + Vector2i(0, 1)):
			segments.append(_create_loop_preview_border_segment(
				Vector2(p.x * CELL_SIZE, (p.y + 1) * CELL_SIZE - PREVIEW_LOOP_BORDER_WIDTH),
				Vector2(CELL_SIZE, PREVIEW_LOOP_BORDER_WIDTH),
				"x",
				color,
				area_center
			))
		if not position_set.has(p + Vector2i(-1, 0)):
			segments.append(_create_loop_preview_border_segment(
				Vector2(p.x * CELL_SIZE, p.y * CELL_SIZE),
				Vector2(PREVIEW_LOOP_BORDER_WIDTH, CELL_SIZE),
				"y",
				color,
				area_center
			))
	segments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("angle", 0.0)) < float(b.get("angle", 0.0))
	)
	return segments


func _preview_positions_center(positions: Array[Vector2i]) -> Vector2:
	if positions.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for p in positions:
		sum += Vector2(p.x * CELL_SIZE, p.y * CELL_SIZE) + Vector2(CELL_SIZE, CELL_SIZE) * 0.5
	return sum / float(positions.size())


func _create_loop_preview_border_segment(pos: Vector2, size: Vector2, axis: String, color: Color, area_center: Vector2) -> Dictionary:
	var rect := ColorRect.new()
	rect.color = color
	rect.size = size
	rect.position = pos
	rect.z_index = PREVIEW_INITIAL_OVERLAY_Z + 1
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.scale = Vector2(0.0, 1.0) if axis == "x" else Vector2(1.0, 0.0)
	add_child(rect)
	_longpress_overlays.append(rect)
	var segment_center: Vector2 = pos + size * 0.5
	var diff: Vector2 = segment_center - area_center
	return {"rect": rect, "axis": axis, "angle": atan2(diff.y, diff.x)}


func _reset_loop_preview_border_segments(segments: Array[Dictionary]) -> void:
	for segment_value in segments:
		var segment: Dictionary = segment_value as Dictionary
		var rect: ColorRect = segment["rect"] as ColorRect
		if not is_instance_valid(rect):
			continue
		var axis: String = segment["axis"] as String
		rect.color.a = PREVIEW_LOOP_BORDER_ALPHA_MAX
		rect.scale = Vector2(0.0, 1.0) if axis == "x" else Vector2(1.0, 0.0)


func _add_initial_blast_overlay(steps: Array[Dictionary]) -> void:
	if _longpress_initial_tween != null and _longpress_initial_tween.is_valid():
		_longpress_initial_tween.kill()
	_longpress_initial_tween = null

	var step_rects: Array[Array] = []
	var loop_border_segments: Array[Dictionary] = _create_loop_preview_border_segments(
		_collect_preview_step_positions(steps),
		_preview_loop_border_color(steps)
	)
	for step_value in steps:
		var step: Dictionary = step_value as Dictionary
		var element_color: Color = step.get("color", Color.WHITE) as Color
		var overlay_color := Color(element_color.r, element_color.g, element_color.b, 0.0)
		var pulse_rects: Array[ColorRect] = []
		var step_positions: Array = step.get("positions", []) as Array
		for position_value in step_positions:
			var p: Vector2i = position_value as Vector2i
			if not _is_valid(p):
				continue
			var rect := ColorRect.new()
			rect.color = overlay_color
			rect.size = Vector2(CELL_SIZE, CELL_SIZE)
			rect.position = Vector2(p.x * CELL_SIZE, p.y * CELL_SIZE)
			rect.z_index = PREVIEW_INITIAL_OVERLAY_Z
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(rect)
			_longpress_overlays.append(rect)
			pulse_rects.append(rect)
		if not pulse_rects.is_empty():
			step_rects.append(pulse_rects)

	if step_rects.is_empty():
		return
	var time_scale: float = _preview_combo_time_scale(step_rects.size())
	var fade_in_dur: float = maxf(PREVIEW_INITIAL_FADE_IN * time_scale, 0.06)
	var hold_dur: float = maxf(PREVIEW_INITIAL_HOLD * time_scale, 0.04)
	var fade_out_dur: float = maxf(PREVIEW_INITIAL_FADE_OUT * time_scale, 0.05)
	var step_gap: float = maxf(PREVIEW_CHAIN_STEP_GAP * time_scale, 0.01)
	var border_step_dur: float = maxf(PREVIEW_LOOP_BORDER_STEP_DUR * time_scale, 0.006)
	var border_hold_dur: float = maxf(PREVIEW_LOOP_BORDER_HOLD * time_scale, 0.06)
	var border_fade_out_dur: float = maxf(PREVIEW_LOOP_BORDER_FADE_OUT * time_scale, 0.05)
	_longpress_initial_tween = create_tween().set_loops()
	for pulse_rects_value in step_rects:
		var pulse_rects: Array = pulse_rects_value as Array
		_longpress_initial_tween.set_parallel(true)
		for rect_value in pulse_rects:
			var fade_in_rect: ColorRect = rect_value as ColorRect
			_longpress_initial_tween.tween_property(fade_in_rect, "color:a", PREVIEW_INITIAL_ALPHA_MAX, fade_in_dur) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		_longpress_initial_tween.chain().tween_interval(hold_dur)
		_longpress_initial_tween.chain()
		_longpress_initial_tween.set_parallel(true)
		for rect_value in pulse_rects:
			var fade_out_rect: ColorRect = rect_value as ColorRect
			_longpress_initial_tween.tween_property(fade_out_rect, "color:a", PREVIEW_INITIAL_ALPHA_MIN, fade_out_dur) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		_longpress_initial_tween.chain().tween_interval(step_gap)

	if not loop_border_segments.is_empty():
		_longpress_initial_tween.chain().tween_callback(_reset_loop_preview_border_segments.bind(loop_border_segments))
		_longpress_initial_tween.chain()
		_longpress_initial_tween.set_parallel(false)
		for segment_value in loop_border_segments:
			var draw_segment: Dictionary = segment_value as Dictionary
			var draw_rect: ColorRect = draw_segment["rect"] as ColorRect
			var draw_axis: String = draw_segment["axis"] as String
			var scale_property := "scale:x" if draw_axis == "x" else "scale:y"
			_longpress_initial_tween.tween_property(draw_rect, scale_property, 1.0, border_step_dur) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		_longpress_initial_tween.chain().tween_interval(border_hold_dur)
		_longpress_initial_tween.chain()
		_longpress_initial_tween.set_parallel(true)
		for fade_segment_value in loop_border_segments:
			var fade_segment: Dictionary = fade_segment_value as Dictionary
			var fade_rect: ColorRect = fade_segment["rect"] as ColorRect
			_longpress_initial_tween.tween_property(fade_rect, "color:a", 0.0, border_fade_out_dur) \
				.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		_longpress_initial_tween.chain().tween_interval(step_gap)


## 漸變邊框覆蓋層透明度（對其下所有 ColorRect 子節點）
func _tween_border_alpha(tw: Tween, container: Node, target_alpha: float) -> void:
	for child in container.get_children():
		if child is ColorRect:
			tw.tween_property(child, "color:a", target_alpha, PREVIEW_FADE_DUR)


## 建立格子邊框覆蓋層（用於高亮高階寶石，由4條邊組成）
func _create_border_overlay(gp: Vector2i, color: Color) -> Node:
	var border_width := 3.0
	var origin := Vector2(gp.x * CELL_SIZE, gp.y * CELL_SIZE)
	var container := Node2D.new()
	container.z_index = PREVIEW_BORDER_Z
	add_child(container)

	# 上
	var top := ColorRect.new()
	top.color = color
	top.size = Vector2(CELL_SIZE, border_width)
	top.position = origin
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(top)
	# 下
	var bottom := ColorRect.new()
	bottom.color = color
	bottom.size = Vector2(CELL_SIZE, border_width)
	bottom.position = origin + Vector2(0, CELL_SIZE - border_width)
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(bottom)
	# 左
	var left := ColorRect.new()
	left.color = color
	left.size = Vector2(border_width, CELL_SIZE - border_width * 2)
	left.position = origin + Vector2(0, border_width)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(left)
	# 右
	var right := ColorRect.new()
	right.color = color
	right.size = Vector2(border_width, CELL_SIZE - border_width * 2)
	right.position = origin + Vector2(CELL_SIZE - border_width, border_width)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.add_child(right)

	return container


## 隱藏長按爆炸預覽：漸變還原暗化 + 漸變移除覆蓋層
func _hide_blast_preview() -> void:
	_longpress_active = false
	_play_longpress_release_bounce()

	# 還原被抬高的方塊 z_index
	for rb in _longpress_raised_blocks:
		if is_instance_valid(rb):
			rb.z_index = 0
	_longpress_raised_blocks.clear()

	# 終止先前的暗化/還原 tween
	if _longpress_initial_tween != null and _longpress_initial_tween.is_valid():
		_longpress_initial_tween.kill()
	_longpress_initial_tween = null
	if _longpress_dim_tween != null and _longpress_dim_tween.is_valid():
		_longpress_dim_tween.kill()
	_longpress_dim_tween = create_tween().set_parallel(true)

	var normal_color := Color(1, 1, 1, 1)

	# 漸變還原所有棋盤方塊到正常 modulate（確保不遺漏）
	for x in columns:
		for y in rows:
			var b: Block = grid[x][y]
			if b != null and b.modulate != normal_color:
				_longpress_dim_tween.tween_property(b, "modulate", normal_color, PREVIEW_FADE_DUR) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 漸變淡出覆蓋層後釋放
	var overlays_to_free: Array[Node] = _longpress_overlays.duplicate()
	for overlay in overlays_to_free:
		if not is_instance_valid(overlay):
			continue
		if overlay is ColorRect:
			_longpress_dim_tween.tween_property(overlay, "color:a", 0.0, PREVIEW_FADE_DUR)
		else:
			# Node2D 邊框容器 — 對所有子節點淡出
			for child in overlay.get_children():
				if child is ColorRect:
					_longpress_dim_tween.tween_property(child, "color:a", 0.0, PREVIEW_FADE_DUR)
	_longpress_overlays.clear()

	# 動畫結束後釋放所有覆蓋層節點
	_longpress_dim_tween.chain().tween_callback(func() -> void:
		for o in overlays_to_free:
			if is_instance_valid(o):
				o.queue_free()
	)

	blast_preview_exited.emit()


## 統計棋盤上具有 BURNING 額外效果的寶石數量
func count_burning_gems() -> int:
	var n: int = 0
	for x in columns:
		for y in rows:
			var b: Block = grid[x][y]
			if b != null and b.has_extra(Block.ExtraEffect.BURNING):
				n += 1
	return n


## 回傳所有帶有 BURNING 效果的寶石位置列表
func get_burning_gem_positions() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in columns:
		for y in rows:
			var b: Block = grid[x][y]
			if b != null and b.has_extra(Block.ExtraEffect.BURNING):
				result.append(Vector2i(x, y))
	return result


## 暗化除指定位置外的所有寶石，高亮指定位置
func darken_except(positions: Array[Vector2i], duration: float = 0.25) -> void:
	var bright_set: Dictionary = {}
	for p in positions:
		bright_set[p] = true
	if _longpress_dim_tween != null and _longpress_dim_tween.is_valid():
		_longpress_dim_tween.kill()
	var dim_color := Color(0.3, 0.3, 0.35, 1.0)
	var bright_color := Color(1.0, 1.0, 1.0, 1.0)
	_longpress_dim_tween = create_tween().set_parallel(true)
	for x in columns:
		for y in rows:
			var b: Block = grid[x][y]
			if b == null:
				continue
			var target: Color = bright_color if bright_set.has(Vector2i(x, y)) else dim_color
			_longpress_dim_tween.tween_property(b, "modulate", target, duration) \
				.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
