## Board（棋盤）— 管理寶石網格、點擊消除、掉落填充、融合提示及高階寶石邏輯。
extends Node2D

const CELL_SIZE := 64          # 每格寶石的像素尺寸
const FALL_SPEED := 800.0      # 掉落速度（像素/秒）— 掉落與填充共用
var chain_blast_interval := 0.2  # 連鎖爆炸之間的間隔（秒）

const BlockScene := preload("res://scenes/block.tscn")  # 寶石場景預載

@export var stage: StageData  # 當前關卡資料

var columns: int = 8          # 棋盤欄位數
var rows: int = 8             # 棋盤行數
var allowed_types: Array[Block.Type] = []  # 允許出現的寶石類型
var min_match: int = 2        # 最少連接數才可消除

var grid: Array = []          # 二維網格陣列 grid[x][y] = Block 或 null
# is_busy 屬性後備欄位（property 用，setter 觸發 drain）
var _is_busy_back: bool = false
# is_busy：是否正在處理動畫/消除中（防止重複點擊）
# 改為 property — falling edge 自動觸發 deferred clicks drain
var is_busy: bool:
	get:
		return _is_busy_back
	set(v):
		var was: bool = _is_busy_back
		_is_busy_back = v
		if was and not v:
			call_deferred("_drain_deferred_clicks")
var score: int = 0            # 當前得分
var last_tapped_pos: Vector2i = Vector2i(-1, -1)  # 最後一次點擊的網格位置
var skip_collapse: bool = false   # 融合流程中由 main.gd 設定，跳過自動掉落
var _fuse_skills: Array[Dictionary] = []  # 融合技能清單 { gem_type, threshold, label, trigger_type }
var is_fusing: bool = false       # 融合動畫進行中（允許並行點擊下一次融合）
var _concurrent_fuse_tapped_pos: Vector2i = Vector2i(-1, -1)  # 並行融合點擊的位置（由 _on_gems_blasted 讀取）

# ── 邏輯狀態（State/UI 分離：用於連續爆破預測驗證）──────────
# logic_grid[x][y] 儲存 Block.Type（int）或：
#   LOGIC_UNKNOWN：等待視覺填充隨機顏色（BFS 不會匹配）
#   LOGIC_UPPER：高階寶石（BFS 不會匹配普通爆破）
const LOGIC_UNKNOWN := 999
const LOGIC_UPPER := -1
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

# ── 選擇模式（主動技能用：懸停預覽十字範圍，點擊確認轉換）──
var _selection_mode: bool = false           # 是否處於選擇模式
var _selection_convert_type: Block.Type = Block.Type.RED  # 選擇模式要轉換的目標類型
var _selection_pattern: String = "cross"    # 選擇模式的預覽形狀："cross" | "fireball"
var _preview_overlays: Array[ColorRect] = []  # 預覽覆蓋層節點
var _preview_center: Vector2i = Vector2i(-1, -1)  # 目前預覽的中心格

# ── 長按預覽系統（長按高階寶石顯示爆炸範圍）──
const LONGPRESS_THRESHOLD := 0.35         # 長按觸發閾值（秒）
const PREVIEW_FADE_DUR := 0.18            # 預覽進出漸變時間（秒）
var _longpress_pos: Vector2i = Vector2i(-1, -1)  # 長按追蹤的網格位置
var _longpress_timer: float = 0.0          # 已按住時間
var _longpress_active: bool = false        # 長按預覽是否已顯示
var _longpress_overlays: Array[Node] = []  # 爆炸範圍高亮覆蓋層
var _longpress_dim_tween: Tween = null     # 暗化/還原動畫 tween
var _longpress_raised_blocks: Array[Block] = []  # 預覽時被抬高 z_index 的方塊

# ── 教學系統 ──
var _tutorial_filter: Array[Vector2i] = []   # 非空時，只允許點擊這些位置
var _hand_sprite: Sprite2D = null            # 教學手指圖示
var _hand_tween: Tween = null                # 手指浮動動畫

signal score_changed(new_score: int)      # 分數變更時發出
signal gems_blasted(gem_type: Block.Type, count: int, global_positions: Array)  # 寶石消除時發出
signal upper_gem_clicked()                # 高階寶石被點擊時發出
signal upper_blast_completed(chain_count: int, blasted_by_type: Dictionary, triggered_upper: Block.UpperType)  # 高階爆炸完成時發出
signal upper_gem_chain_triggered(upper_type: Block.UpperType)  # 連鎖中特殊高階寶石被觸發時發出
signal selection_confirmed(positions: Array)  # 選擇模式確認時發出
signal blast_preview_entered()               # 長按預覽開始時發出
signal blast_preview_exited()                # 長按預覽結束時發出


## 初始化：讀取關卡資料並建立棋盤
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
	for x in columns:
		for y in rows:
			var rect := Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE)
			var c := light_brown if (x + y) % 2 == 0 else dark_brown
			draw_rect(rect, c)


## 每幀更新：追蹤長按計時，超過閾值時顯示爆炸預覽
func _process(delta: float) -> void:
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
	# 若有固定佈局，覆寫寶石類型
	if stage != null and stage.fixed_layout.size() == columns:
		for x in columns:
			var col: Array = stage.fixed_layout[x]
			for y in rows:
				if y < col.size() and grid[x][y] != null:
					grid[x][y].set_block_type(col[y])
	_init_logic_grid_from_visual()
	_update_fuse_hints()


## 從視覺 grid 完整初始化 logic_grid（重建/重置時呼叫）
func _init_logic_grid_from_visual() -> void:
	logic_grid.clear()
	logic_grid.resize(columns)
	for x in columns:
		logic_grid[x] = []
		logic_grid[x].resize(rows)
		for y in rows:
			var b: Block = grid[x][y]
			if b == null:
				logic_grid[x][y] = LOGIC_UNKNOWN
			elif b.is_upper_gem():
				logic_grid[x][y] = LOGIC_UPPER
			else:
				logic_grid[x][y] = b.block_type


## 從視覺 grid 同步未知（LOGIC_UNKNOWN）的 logic_grid 格子。
## 在每次視覺 _collapse_and_fill 完成時呼叫，讓邏輯追上視覺隨機填色。
func _sync_logic_unknowns_from_visual() -> void:
	for x in columns:
		for y in rows:
			if logic_grid[x][y] == LOGIC_UNKNOWN:
				var b: Block = grid[x][y]
				if b != null:
					logic_grid[x][y] = LOGIC_UPPER if b.is_upper_gem() else int(b.block_type)


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
	var block: Block = BlockScene.instantiate()
	block.set_block_type(_random_type())
	block.grid_pos = Vector2i(x, y)
	# Set position BEFORE add_child so it never flashes at the wrong spot.
	block.position = start_pos if use_start_pos else grid_to_world(Vector2i(x, y))
	add_child(block)
	grid[x][y] = block
	return block


## 隨機選擇一個允許的寶石類型
func _random_type() -> int:
	return allowed_types[randi() % allowed_types.size()]


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


## 處理滑鼠輸入：左鍵點擊棋盤上的寶石；選擇模式下懸停預覽 + 點擊確認；長按高階寶石預覽爆炸範圍
func _unhandled_input(event: InputEvent) -> void:
	if _selection_mode:
		if event is InputEventMouseMotion:
			var local_pos := get_local_mouse_position()
			var gp := world_to_grid(local_pos)
			if _is_valid(gp) and gp != _preview_center:
				_update_selection_preview(gp)
			elif not _is_valid(gp):
				_clear_preview_overlays()
				_preview_center = Vector2i(-1, -1)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var local_pos := get_local_mouse_position()
			var gp := world_to_grid(local_pos)
			if _is_valid(gp):
				var positions := _get_selection_positions(gp)
				_clear_preview_overlays()
				_selection_mode = false
				_preview_center = Vector2i(-1, -1)
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
			if _is_valid(fuse_gp):
				_try_concurrent_fuse(fuse_gp)
			return
		# State/UI 分離：在動畫期間預先 queue 普通爆破點擊
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var queue_local_pos := get_local_mouse_position()
			var queue_gp := world_to_grid(queue_local_pos)
			if _is_valid(queue_gp):
				_try_queue_click(queue_gp)
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_pos := get_local_mouse_position()
		var gp := world_to_grid(local_pos)
		if _is_valid(gp) and grid[gp.x][gp.y] != null:
			var clicked_block: Block = grid[gp.x][gp.y]
			if clicked_block.is_upper_gem():
				# 高階寶石 → 開始長按追蹤（延遲點擊）
				_longpress_pos = gp
				_longpress_timer = 0.0
				_longpress_active = false
				return
			_handle_click(gp)


# ── 邏輯端 BFS / Queue / Drain（State/UI 分離）────────────────────

## 從起始位置在 logic_grid 上找連通同色普通寶石（與 _find_connected 同 BFS 邏輯，但讀邏輯狀態）
func _find_connected_logic(start: Vector2i) -> Array[Vector2i]:
	if not _is_valid(start):
		return []
	var target: int = logic_grid[start.x][start.y]
	if target == LOGIC_UNKNOWN or target == LOGIC_UPPER:
		return []
	var visited := {}
	var connected: Array[Vector2i] = []
	var queue: Array[Vector2i] = [start]
	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()
		if visited.has(current):
			continue
		if not _is_valid(current):
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
func _logic_destroy_and_collapse(positions: Array[Vector2i]) -> void:
	for p in positions:
		logic_grid[p.x][p.y] = LOGIC_UNKNOWN
	for x in columns:
		var stack: Array = []
		for y in rows:
			if logic_grid[x][y] != LOGIC_UNKNOWN:
				stack.append(logic_grid[x][y])
		var stack_idx: int = stack.size() - 1
		for y in range(rows - 1, -1, -1):
			if stack_idx >= 0:
				logic_grid[x][y] = stack[stack_idx]
				stack_idx -= 1
			else:
				logic_grid[x][y] = LOGIC_UNKNOWN


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
	if not _is_valid(pos):
		return
	if _tutorial_filter.size() > 0 and not _tutorial_filter.has(pos):
		return
	# 允許在動畫期間 queue 高階寶石點擊（normal blast → upper blast 路線）
	var b: Block = grid[pos.x][pos.y]
	if b != null and b.is_upper_gem():
		deferred_clicks.append(pos)
		return
	var t: int = logic_grid[pos.x][pos.y]
	if t == LOGIC_UNKNOWN or t == LOGIC_UPPER:
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
	if not busy and not is_busy:
		call_deferred("_drain_deferred_clicks")


## 處理寶石點擊事件
## 如果是高階寶石 → 觸發特殊爆炸
## 如果連接數 >= min_match → 消除並掉落填充
## 否則 → 抖動提示無效
func _handle_click(pos: Vector2i) -> void:	# 教學過濾：只允許指定位置
	if _tutorial_filter.size() > 0 and not _tutorial_filter.has(pos):
		return

	var block: Block = grid[pos.x][pos.y]
	last_tapped_pos = pos

	# 高階寶石 — 特殊點擊（消耗一回合，觸發範圍/橫列爆炸並可連鏈）
	if block.is_upper_gem():
		_next_click_is_drained = false
		is_busy = true
		await _handle_upper_click(pos)
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
			var tween := create_tween()
			tween.tween_property(block, "position:x", block.position.x + 4, 0.05)
			tween.tween_property(block, "position:x", block.position.x - 4, 0.05)
			tween.tween_property(block, "position:x", block.position.x, 0.05)
		_next_click_is_drained = false
		return

	# 邏輯狀態同步：若此次點擊不是來自 drain queue，需即時更新邏輯狀態
	# （drain 來的點擊在 _try_queue_click 已預先套用過邏輯狀態）
	if not _next_click_is_drained:
		_logic_destroy_and_collapse(matches)
		if battle_manager_ref != null and not block.is_upper_gem():
			battle_manager_ref.logic_apply_blast(int(block.block_type), matches.size())
	_next_click_is_drained = false

	is_busy = true
	_destroy_blocks(matches)          # 非阻塞 — 啟動動畫並延遲釋放
	if skip_collapse:
		# 融合流程 — main.gd 會在放置高階寶石後呼叫 do_collapse()
		return
	await _collapse_and_fill()        # 掉落立即開始
	# State/UI 分離：destroy + collapse 完成後立即解鎖，讓下一個 queued click 可開始
	# （角色攻擊與 VFX 由 main.gd 在 attack queue 中以 fire-and-forget 並行播放）
	is_busy = false


## 從起始位置開始，找出所有相連的同類型寶石（BFS 洪水填充）
func _find_connected(start: Vector2i) -> Array[Vector2i]:
	var block: Block = grid[start.x][start.y]
	if block == null:
		return []

	var target_type = block.block_type
	var visited := {}
	var connected: Array[Vector2i] = []
	var queue: Array[Vector2i] = [start]

	while queue.size() > 0:
		var current: Vector2i = queue.pop_front()

		if visited.has(current):
			continue
		if not _is_valid(current):
			continue
		if grid[current.x][current.y] == null:
			continue
		var cur_block: Block = grid[current.x][current.y]
		if cur_block.block_type != target_type:
			continue
		# 高階寶石不參與普通配對 — 跳過
		if cur_block.is_upper_gem():
			continue

		visited[current] = true
		connected.append(current)

		queue.append(Vector2i(current.x + 1, current.y))
		queue.append(Vector2i(current.x - 1, current.y))
		queue.append(Vector2i(current.x, current.y + 1))
		queue.append(Vector2i(current.x, current.y - 1))

	return connected


## 消除指定位置的寶石：計算得分、發出信號、播放動畫、延遲釋放節點
func _destroy_blocks(positions: Array[Vector2i]) -> void:
	var gem_type: Block.Type = grid[positions[0].x][positions[0].y].block_type
	var blocks: Array = []
	var blast_positions: Array = []
	for pos in positions:
		var block: Block = grid[pos.x][pos.y]
		if block:
			blast_positions.append(block.global_position)
			grid[pos.x][pos.y] = null
			blocks.append(block)

	score += positions.size() * 10
	score_changed.emit(score)
	gems_blasted.emit(gem_type, positions.size(), blast_positions)

	for block in blocks:
		block.play_destroy_animation()

	# 動畫結束後釋放寶石節點 — 非阻塞，讓掉落立即開始
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		for b in blocks:
			if is_instance_valid(b):
				b.queue_free()
	, CONNECT_ONE_SHOT)


## 掉落與填充：現有寶石向下壓縮，空位從頂部生成新寶石掉落
func _collapse_and_fill() -> void:
	# 每一欄的資料：{ block, to_pos, is_new, gx, gy }
	var columns_data: Array = []  # Array of Arrays
	columns_data.resize(columns)

	for x in columns:
		var col_falls: Array = []

		# 將現有寶石向下壓縮
		var write_y := rows - 1
		for read_y in range(rows - 1, -1, -1):
			if grid[x][read_y] != null:
				if read_y != write_y:
					grid[x][write_y] = grid[x][read_y]
					grid[x][read_y] = null
					grid[x][write_y].grid_pos = Vector2i(x, write_y)
					col_falls.append({
						block = grid[x][write_y],
						to_pos = grid_to_world(Vector2i(x, write_y)),
						is_new = false
					})
				write_y -= 1

		# 記錄需要新寶石的空位
		for y in rows:
			if grid[x][y] == null:
				col_falls.append({
					to_pos = grid_to_world(Vector2i(x, y)),
					is_new = true,
					gx = x, gy = y
				})

		columns_data[x] = col_falls

	# ── 第二階段：建立新寶石並以 FALL_SPEED 速度動畫掉落 ───
	var longest_dur := 0.0

	for x in columns:
		var col_falls: Array = columns_data[x]
		if col_falls.is_empty():
			continue

		# 計算本欄新寶石數量，用來堆疊生成位置
		var spawn_count := 0
		for f in col_falls:
			if f.is_new:
				spawn_count += 1

		var spawn_idx := 0
		for f in col_falls:
			var from_pos: Vector2
			if f.is_new:
				# 新寶石堆疊在棋盤上方：第 -1, -2, … 行
				from_pos = grid_to_world(Vector2i(f.gx, -1 - (spawn_count - 1 - spawn_idx)))
				spawn_idx += 1
			else:
				# 現有寶石從目前位置開始掉落
				from_pos = f.block.position

			var dist := absf(f.to_pos.y - from_pos.y)
			if dist < 0.5:
				continue
			var dur := dist / FALL_SPEED
			longest_dur = maxf(longest_dur, dur)

			if f.is_new:
				var block := _create_block(f.gx, f.gy, from_pos, true)
				block.modulate.a = 0.0
				block.fall_to(f.to_pos, dur, 0.0, true)
			else:
				f.block.fall_to(f.to_pos, dur, 0.0, false)

	if longest_dur == 0.0:
		_sync_logic_unknowns_from_visual()
		_update_fuse_hints()
		return
	await get_tree().create_timer(longest_dur + Block.BOUNCE_DUR + 0.05).timeout
	_sync_logic_unknowns_from_visual()
	_update_fuse_hints()


## 重新開始：清除棋盤並重新初始化
func restart() -> void:
	is_busy = true
	score = 0
	score_changed.emit(score)
	for x in columns:
		for y in rows:
			if grid[x][y] != null:
				grid[x][y].queue_free()
				grid[x][y] = null
	initialize_board()
	is_busy = false


## 將 [count] 個寶石轉換為 [to_type] 類型。
## 優先從 [priority_types] 中選取，不足時從其他類型補充。
## 播放縮小→替換→放大 的變身動畫。返回被轉換的位置。
func convert_gems(to_type: Block.Type, count: int, priority_types: Array[Block.Type]) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var fallback: Array[Vector2i] = []

	for x in columns:
		for y in rows:
			var block: Block = grid[x][y]
			if block == null or block.block_type == to_type:
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


## 將棋盤上所有 [from_type] 類型的寶石轉換為 [to_type]。返回轉換數量。
func convert_all_of_type(from_type: Block.Type, to_type: Block.Type) -> int:
	var count := 0
	for x in columns:
		for y in rows:
			var block: Block = grid[x][y]
			if block != null and block.block_type == from_type:
				_animate_gem_morph(block, to_type)
				count += 1
	return count


## 寶石變身動畫：縮小 → 替換類型 → 放大 → 更新融合提示
func _animate_gem_morph(block: Block, new_type: Block.Type) -> void:
	var tween := create_tween()
	# 縮小
	tween.tween_property(block, "scale", Vector2(0.3, 0.3), 0.15) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# 在最小點替換類型
	tween.tween_callback(func() -> void:
		block.set_block_type(new_type)
	)
	# 放大回原始尺寸
	tween.tween_property(block, "scale", Vector2(1.0, 1.0), 0.15) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# 動畫完成後更新融合提示
	tween.tween_callback(_update_fuse_hints)


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
			if grid[p.x][p.y] != null:
				valid.append(p)
		if valid.is_empty():
			continue

		# 按類型分組，發出信號
		var by_type: Dictionary = {}
		for p in valid:
			var b: Block = grid[p.x][p.y]
			var bt: Block.Type = b.block_type as Block.Type
			if not by_type.has(bt):
				by_type[bt] = []
			by_type[bt].append(b.global_position)
			blasted_by_type[bt] = blasted_by_type.get(bt, 0) + 1

		# 消除此行寶石
		var blocks_to_free: Array = []
		for p in valid:
			var b: Block = grid[p.x][p.y]
			if b:
				grid[p.x][p.y] = null
				blocks_to_free.append(b)
				b.play_destroy_animation()

		score += valid.size() * 10
		score_changed.emit(score)

		for bt in by_type:
			var gpos: Array = by_type[bt]
			gems_blasted.emit(bt as Block.Type, gpos.size(), gpos)

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
func place_upper_gem(pos: Vector2i, ut: Block.UpperType, gem_type: Block.Type = Block.Type.RED) -> void:
	if not _is_valid(pos):
		return
	var block: Block = grid[pos.x][pos.y]
	if block == null:
		block = _create_block(pos.x, pos.y)
		block.set_block_type(gem_type)

	# 設定高階類型（替換普通寶石外觀為火焰貼圖 + 紅色底色）
	block.set_upper_type(ut)
	# 放大彈跳效果表示融合完成 + 白色閃光覆蓋層
	var tween := create_tween()
	tween.tween_property(block, "scale", Vector2(1.4, 1.4), 0.2).set_ease(Tween.EASE_OUT)
	tween.tween_property(block, "scale", Vector2(1.0, 1.0), 0.2).set_trans(Tween.TRANS_BACK)

	# 白色閃光覆蓋層：從白色淡出至透明
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.85)
	flash.size = Vector2(CELL_SIZE, CELL_SIZE)
	flash.position = Vector2(-CELL_SIZE * 0.5, -CELL_SIZE * 0.5)
	flash.z_index = 10
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(flash)
	var flash_tween := create_tween()
	flash_tween.tween_property(flash, "color:a", 0.0, 0.2).set_ease(Tween.EASE_IN)
	flash_tween.tween_callback(flash.queue_free)


## 偵錯：將棋盤上隨機 N 顆普通寶石轉為火炸彈（FIREBALL）
func debug_spawn_firebombs(count: int) -> void:
	var candidates: Array = []
	for x in columns:
		for y in rows:
			var b: Block = grid[x][y]
			if b != null and not b.is_upper_gem():
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
	var ut: Block.UpperType = block.upper_type

	# 根據高階類型決定爆炸位置（使用共用函式）
	var positions: Array[Vector2i] = _get_blast_positions_for_upper(pos, ut)

	# 執行帶連鏈遞迴的爆炸
	var chain_data := [1]  # 初始點擊即為 chain 1
	var total_blasted_by_type: Dictionary = {}  # Block.Type -> int，各類型被爆破數量

	upper_gem_clicked.emit()

	# 觸發被點擊高階寶石的獨有效果（與連鏈統一處理）
	upper_gem_chain_triggered.emit(ut)

	# 播放爆炸 VFX（fire-and-forget）
	BlastVfx.play(self, block.global_position, ut)

	# 先消除被點擊的高階寶石本身（立即播放動畫）
	var bt: Block.Type = block.block_type as Block.Type
	total_blasted_by_type[bt] = 1
	gems_blasted.emit(bt, 1, [block.global_position])
	grid[pos.x][pos.y] = null
	block.play_destroy_animation()
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
	var chained_uppers: Array[Dictionary] = []  # { pos, upper_type }

	for p in positions:
		if not _is_valid(p):
			continue
		var b: Block = grid[p.x][p.y]
		if b == null:
			continue
		# 如果這個寶石是高階寶石，加入連鏈爆炸佇列（暫不消除）
		if b.is_upper_gem():
			chained_uppers.append({"pos": p, "upper_type": b.upper_type})
			continue
		to_destroy.append(p)

	# 統計各類型被爆破的寶石數量
	var blast_positions_by_type: Dictionary = {}  # type -> Array of global positions
	for p in to_destroy:
		var b: Block = grid[p.x][p.y]
		if b == null:
			continue
		var bt: Block.Type = b.block_type as Block.Type
		if not blast_positions_by_type.has(bt):
			blast_positions_by_type[bt] = []
		blast_positions_by_type[bt].append(b.global_position)

		# 累加到總計
		total_blasted_by_type[bt] = total_blasted_by_type.get(bt, 0) + 1

	# 消除普通寶石（高階寶石保留在棋盤上）
	var blocks_to_free: Array = []
	for p in to_destroy:
		var b: Block = grid[p.x][p.y]
		if b == null:
			continue
		grid[p.x][p.y] = null
		blocks_to_free.append(b)
		b.play_destroy_animation()

	score += to_destroy.size() * 10
	score_changed.emit(score)

	# 為每種類型發出 gems_blasted 信號（用於攻擊計算）
	for bt in blast_positions_by_type:
		var gpos: Array = blast_positions_by_type[bt]
		gems_blasted.emit(bt as Block.Type, gpos.size(), gpos)

	# 動畫結束後釋放節點
	get_tree().create_timer(0.2).timeout.connect(func() -> void:
		for b in blocks_to_free:
			if is_instance_valid(b):
				b.queue_free()
	, CONNECT_ONE_SHOT)

	await get_tree().create_timer(0.15).timeout

	# 處理連鏈的高階寶石：輪到時消除，執行與點擊相同的爆炸行為
	for chained in chained_uppers:
		var cp: Vector2i = chained.pos
		var cut: Block.UpperType = chained.upper_type as Block.UpperType

		# 等待連鏈間隔
		await get_tree().create_timer(chain_blast_interval).timeout

		# 輪到時消除高階寶石並統計
		var ub: Block = grid[cp.x][cp.y]
		if ub == null:
			# 已被同批其他 upper 的遞迴爆炸清掉 → 不計連鎖、不發訊號（避免聲音/計數不同步）
			continue
		# 播放連鏈爆炸 VFX
		BlastVfx.play(self, ub.global_position, cut)
		var ub_type: Block.Type = ub.block_type as Block.Type
		total_blasted_by_type[ub_type] = total_blasted_by_type.get(ub_type, 0) + 1
		gems_blasted.emit(ub_type, 1, [ub.global_position])
		grid[cp.x][cp.y] = null
		ub.play_destroy_animation()
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
		Block.UpperType.WATER_SLASH_X:
			return _get_row_positions(pos.y)
		Block.UpperType.WATER_SLASH_Y:
			return _get_col_positions(pos.x)
	return [pos]


## 取得火球爆炸位置：中心 3×3 + 四個方向各延伸1格
func _get_area_positions(center: Vector2i, _size: int = 0) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	# 3×3 核心範圍
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			var p := Vector2i(center.x + dx, center.y + dy)
			if _is_valid(p):
				result.append(p)
	# 上下左右各延伸1格
	var extensions: Array[Vector2i] = [Vector2i(0, -2), Vector2i(0, 2), Vector2i(-2, 0), Vector2i(2, 0)]
	for ext: Vector2i in extensions:
		var p: Vector2i = center + ext
		if _is_valid(p):
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
			if _is_valid(p):
				result.append(p)
	return result


## 搜尋棋盤上所有符合指定高階類型的寶石位置
func find_upper_gems(ut: Block.UpperType) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for x in columns:
		for y in rows:
			var block: Block = grid[x][y]
			if block != null and block.upper_type == ut:
				result.append(Vector2i(x, y))
	return result


## 移除並摧毀指定位置的高階寶石（播放破壞動畫 + 掉落填充）
func destroy_upper_gem_at(pos: Vector2i) -> void:
	if not _is_valid(pos):
		return
	var block: Block = grid[pos.x][pos.y]
	if block == null:
		return
	var was_leaf_shield: bool = block.upper_type == Block.UpperType.LEAF_SHIELD
	grid[pos.x][pos.y] = null

	if was_leaf_shield:
		_play_shield_break_anim(block)
	else:
		block.play_destroy_animation()
		get_tree().create_timer(0.2).timeout.connect(func() -> void:
			if is_instance_valid(block):
				block.queue_free()
		, CONNECT_ONE_SHOT)


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
		result.append(Vector2i(x, row))
	return result


## 取得指定欄的所有位置
func _get_col_positions(col: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y in rows:
		result.append(Vector2i(col, y))
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
	if _is_valid(center):
		result.append(center)
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		for dist in range(1, 3):
			var p: Vector2i = center + dir * dist
			if _is_valid(p):
				result.append(p)
	return result


## 進入選擇模式（由 main.gd 呼叫，玩家懸停預覽，點擊確認轉換）
func enter_selection_mode(convert_type: Block.Type, pattern: String = "cross") -> void:
	_selection_mode = true
	_selection_convert_type = convert_type
	_selection_pattern = pattern
	_preview_center = Vector2i(-1, -1)


## 離開選擇模式（取消）
func exit_selection_mode() -> void:
	_selection_mode = false
	_clear_preview_overlays()
	_preview_center = Vector2i(-1, -1)


## 更新十字預覽覆蓋層（黃色半透明方塊顯示在預覽位置上方）
func _update_cross_preview(center: Vector2i) -> void:
	_update_selection_preview(center)


## 通用選擇預覽（依 _selection_pattern 決定形狀，依 _selection_convert_type 決定顏色）
func _update_selection_preview(center: Vector2i) -> void:
	_clear_preview_overlays()
	_preview_center = center
	var positions := _get_selection_positions(center)
	var color: Color = Block.COLORS.get(_selection_convert_type, Color(1.0, 0.92, 0.23))
	for p in positions:
		var overlay := ColorRect.new()
		overlay.color = Color(color.r, color.g, color.b, 0.35)
		overlay.size = Vector2(CELL_SIZE, CELL_SIZE)
		overlay.position = Vector2(p.x * CELL_SIZE, p.y * CELL_SIZE)
		overlay.z_index = 10
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(overlay)
		_preview_overlays.append(overlay)


## 依目前 _selection_pattern 取得選擇範圍位置
func _get_selection_positions(center: Vector2i) -> Array[Vector2i]:
	if _selection_pattern == "fireball":
		return _get_area_positions(center)
	return _get_cross_positions(center)


## 清除所有預覽覆蓋層
func _clear_preview_overlays() -> void:
	for overlay in _preview_overlays:
		if is_instance_valid(overlay):
			overlay.queue_free()
	_preview_overlays.clear()


# ── 融合提示系統 ─────────────────────────────────────────────────────

## 由 main.gd 呼叫，註冊隊伍的融合技能。
## 每個項目：{ gem_type: Block.Type, threshold: int, label: String, trigger_type: String }
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

	# 依優先級排序融合技能（數字越小 = 優先級越高）
	var sorted_skills := _fuse_skills.duplicate()
	sorted_skills.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.get("priority", 99) < b.get("priority", 99)
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

				# 檢查此群組是否符合融合條件
				var qualifies := false
				match trigger_type:
					"count":
						qualifies = group.size() >= threshold
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
			sim[x][y] = grid[x][y]

	# 融合流程中，上階寶石將被放置在 last_tapped_pos（尚未放置時模擬為佔位）
	if _is_valid(last_tapped_pos) and sim[last_tapped_pos.x][last_tapped_pos.y] == null:
		sim[last_tapped_pos.x][last_tapped_pos.y] = &"upper_placeholder"

	# 模擬掉落：將非空格向下壓縮
	for x in columns:
		var write_y := rows - 1
		for read_y in range(rows - 1, -1, -1):
			if sim[x][read_y] != null:
				if read_y != write_y:
					sim[x][write_y] = sim[x][read_y]
					sim[x][read_y] = null
				write_y -= 1

	return sim


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
	if block.is_upper_gem():
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
		if cur_block.is_upper_gem():
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
func _try_concurrent_fuse(click_pos: Vector2i) -> void:
	var block: Block = grid[click_pos.x][click_pos.y]
	if block == null or block.is_upper_gem():
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
	_destroy_blocks(real_matches)


# ── 長按爆炸預覽系統 ─────────────────────────────────────────────────

const PREVIEW_OVERLAY_Z := 5   # 爆炸範圍覆蓋層 z_index
const PREVIEW_BLOCK_Z := 8     # 受影響方塊在預覽時的 z_index（高於覆蓋層）
const PREVIEW_BORDER_Z := 9    # 邊框覆蓋層 z_index

## 計算高階寶石的完整爆炸範圍（含連鏈遞迴）
## 回傳 { direct: Array[Vector2i], chain_groups: Array[Dictionary], chain_uppers: Array[Vector2i] }
## chain_groups: [{ ut: UpperType, positions: Array[Vector2i] }, ...]
func _calc_blast_preview(start_pos: Vector2i, start_ut: Block.UpperType) -> Dictionary:
	var direct_blast: Dictionary = {}   # 直接爆炸範圍
	var chain_uppers: Array[Vector2i] = []
	var processed_uppers: Dictionary = {}
	processed_uppers[start_pos] = true

	# 第一層：直接爆炸
	var first_positions: Array[Vector2i] = _get_blast_positions_for_upper(start_pos, start_ut)
	var next_queue: Array[Dictionary] = []
	for p in first_positions:
		if p == start_pos:
			continue
		direct_blast[p] = true
		if _is_valid(p) and grid[p.x][p.y] != null:
			var b: Block = grid[p.x][p.y]
			if b.is_upper_gem() and not processed_uppers.has(p):
				chain_uppers.append(p)
				processed_uppers[p] = true
				next_queue.append({"pos": p, "ut": b.upper_type})

	# 後續層：連鏈爆炸（按觸發的高階寶石分組）
	var chain_groups: Array[Dictionary] = []   # [{ ut, positions }]
	var all_chain: Dictionary = {}             # 去重用
	while next_queue.size() > 0:
		var current: Dictionary = next_queue.pop_front()
		var cpos: Vector2i = current.pos
		var cut: Block.UpperType = current.ut
		var cpositions: Array[Vector2i] = _get_blast_positions_for_upper(cpos, cut)
		var group_positions: Array[Vector2i] = []
		for p in cpositions:
			if p == cpos or direct_blast.has(p) or all_chain.has(p):
				continue
			all_chain[p] = true
			group_positions.append(p)
			if _is_valid(p) and grid[p.x][p.y] != null:
				var b: Block = grid[p.x][p.y]
				if b.is_upper_gem() and not processed_uppers.has(p):
					chain_uppers.append(p)
					processed_uppers[p] = true
					next_queue.append({"pos": p, "ut": b.upper_type})
		if group_positions.size() > 0:
			chain_groups.append({"ut": cut, "positions": group_positions})

	return {
		"direct": direct_blast.keys(),
		"direct_ut": start_ut,
		"chain_groups": chain_groups,
		"chain_uppers": chain_uppers,
	}


## 顯示長按爆炸預覽：漸變暗化棋盤 + 高亮爆炸範圍
func _show_blast_preview(pos: Vector2i) -> void:
	_longpress_active = true
	var block: Block = grid[pos.x][pos.y]
	if block == null or not block.is_upper_gem():
		return

	var result: Dictionary = _calc_blast_preview(pos, block.upper_type)
	var direct: Array = result.direct
	var direct_ut: Block.UpperType = result.direct_ut
	var chain_groups: Array = result.chain_groups
	var chain_uppers: Array = result.chain_uppers

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

	# 還原被抬高的方塊 z_index
	for rb in _longpress_raised_blocks:
		if is_instance_valid(rb):
			rb.z_index = 0
	_longpress_raised_blocks.clear()

	# 終止先前的暗化/還原 tween
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
