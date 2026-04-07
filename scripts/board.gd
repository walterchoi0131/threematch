## Board（棋盤）— 管理寶石網格、點擊消除、掉落填充、融合提示及高階寶石邏輯。
extends Node2D

const CELL_SIZE := 64          # 每格寶石的像素尺寸
const FALL_SPEED := 800.0      # 掉落速度（像素/秒）— 掉落與填充共用

const BlockScene := preload("res://scenes/block.tscn")  # 寶石場景預載

@export var stage: StageData  # 當前關卡資料

var columns: int = 8          # 棋盤欄位數
var rows: int = 8             # 棋盤行數
var allowed_types: Array[Block.Type] = []  # 允許出現的寶石類型
var min_match: int = 2        # 最少連接數才可消除

var grid: Array = []          # 二維網格陣列 grid[x][y] = Block 或 null
var is_busy: bool = false     # 是否正在處理動畫/消除中（防止重複點擊）
var score: int = 0            # 當前得分
var last_tapped_pos: Vector2i = Vector2i(-1, -1)  # 最後一次點擊的網格位置
var skip_collapse: bool = false   # 融合流程中由 main.gd 設定，跳過自動掉落
var _fuse_skills: Array[Dictionary] = []  # 融合技能清單 { gem_type, threshold, label, trigger_type }

# ── 選擇模式（主動技能用：懸停預覽十字範圍，點擊確認轉換）──
var _selection_mode: bool = false           # 是否處於選擇模式
var _selection_convert_type: Block.Type = Block.Type.RED  # 選擇模式要轉換的目標類型
var _preview_overlays: Array[ColorRect] = []  # 預覽覆蓋層節點
var _preview_center: Vector2i = Vector2i(-1, -1)  # 目前預覽的中心格

signal score_changed(new_score: int)      # 分數變更時發出
signal gems_blasted(gem_type: Block.Type, count: int, global_positions: Array)  # 寶石消除時發出
signal upper_gem_clicked()                # 高階寶石被點擊時發出
signal upper_blast_completed(chain_count: int, blasted_by_type: Dictionary, triggered_upper: Block.UpperType)  # 高階爆炸完成時發出
signal selection_confirmed(positions: Array)  # 選擇模式確認時發出


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
	for x in columns:
		for y in rows:
			var rect := Rect2(x * CELL_SIZE, y * CELL_SIZE, CELL_SIZE, CELL_SIZE)
			var c := Color(1, 1, 1, 0.04) if (x + y) % 2 == 0 else Color(0, 0, 0, 0.04)
			draw_rect(rect, c)


## 初始化棋盤：清除舊網格並為每一格建立新寶石
func initialize_board() -> void:
	grid.clear()
	grid.resize(columns)
	for x in columns:
		grid[x] = []
		grid[x].resize(rows)
		for y in rows:
			_create_block(x, y)
	_update_fuse_hints()


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


## 處理滑鼠輸入：左鍵點擊棋盤上的寶石；選擇模式下懸停預覽 + 點擊確認
func _unhandled_input(event: InputEvent) -> void:
	if _selection_mode:
		if event is InputEventMouseMotion:
			var local_pos := get_local_mouse_position()
			var gp := world_to_grid(local_pos)
			if _is_valid(gp) and gp != _preview_center:
				_update_cross_preview(gp)
			elif not _is_valid(gp):
				_clear_preview_overlays()
				_preview_center = Vector2i(-1, -1)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var local_pos := get_local_mouse_position()
			var gp := world_to_grid(local_pos)
			if _is_valid(gp):
				var positions := _get_cross_positions(gp)
				_clear_preview_overlays()
				_selection_mode = false
				_preview_center = Vector2i(-1, -1)
				selection_confirmed.emit(positions)
		return
	if is_busy:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local_pos := get_local_mouse_position()
		var gp := world_to_grid(local_pos)
		if _is_valid(gp) and grid[gp.x][gp.y] != null:
			_handle_click(gp)


## 處理寶石點擊事件
## 如果是高階寶石 → 觸發特殊爆炸
## 如果連接數 >= min_match → 消除並掉落填充
## 否則 → 抖動提示無效
func _handle_click(pos: Vector2i) -> void:
	var block: Block = grid[pos.x][pos.y]
	last_tapped_pos = pos

	# 高階寶石 — 特殊點擊（消耗一回合，觸發範圍/橫列爆炸並可連鏈）
	if block.is_upper_gem():
		is_busy = true
		await _handle_upper_click(pos)
		await _collapse_and_fill()
		# is_busy 由 main.gd _on_upper_blast_completed 在攻擊動畫結束後解除
		return

	var matches := _find_connected(pos)
	if matches.is_empty():
		# 寶石抖動提示無效操作
		if block:
			var tween := create_tween()
			tween.tween_property(block, "position:x", block.position.x + 4, 0.05)
			tween.tween_property(block, "position:x", block.position.x - 4, 0.05)
			tween.tween_property(block, "position:x", block.position.x, 0.05)
		return

	is_busy = true
	_destroy_blocks(matches)          # 非阻塞 — 啟動動畫並延遲釋放
	if skip_collapse:
		# 融合流程 — main.gd 會在放置高階寶石後呼叫 do_collapse()
		return
	await _collapse_and_fill()        # 掉落立即開始
	# is_busy 由 main.gd _on_gems_blasted 在攻擊動畫結束後解除


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
		_update_fuse_hints()
		return
	await get_tree().create_timer(longest_dur + Block.BOUNCE_DUR + 0.05).timeout
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
	is_busy = false


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


## 在指定位置放置高階寶石（若該格為空則先建立紅色寶石）
func place_upper_gem(pos: Vector2i, ut: Block.UpperType) -> void:
	if not _is_valid(pos):
		return
	var block: Block = grid[pos.x][pos.y]
	if block == null:
		# Cell empty after blast — create a new RED block at grid position
		block = _create_block(pos.x, pos.y)
		block.set_block_type(Block.Type.RED)

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


## 處理高階寶石被點擊：根據類型決定爆炸範圍，執行連鏈爆炸
func _handle_upper_click(pos: Vector2i) -> void:
	var block: Block = grid[pos.x][pos.y]
	var ut: Block.UpperType = block.upper_type

	# 根據高階類型決定爆炸位置
	var positions: Array[Vector2i] = []
	match ut:
		Block.UpperType.FIREBALL:
			positions = _get_area_positions(pos, 4)   # 3×3 + 十字延伸
		Block.UpperType.FIRE_PILLAR_X:
			positions = _get_row_positions(pos.y)     # 整行
		Block.UpperType.FIRE_PILLAR_Y:
			positions = _get_col_positions(pos.x)     # 整欄
		Block.UpperType.SAINT_CROSS:
			positions = _get_cross_positions(pos)     # 完整十字形

	# 執行帶連鏈遞迴的爆炸
	var chain_data := [1]  # 初始點擊即為 chain 1
	var total_blasted_by_type: Dictionary = {}  # Block.Type -> int，各類型被爆破數量

	# 將高階寶石本身也納入爆炸範圍
	if not positions.has(pos):
		positions.append(pos)

	upper_gem_clicked.emit()
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
		# 如果這個寶石是高階寶石（且非最初被點擊的那個），
		# 加入連鏈爆炸佇列
		if b.is_upper_gem():
			chained_uppers.append({"pos": p, "upper_type": b.upper_type})
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

	# 消除寶石
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

	# 處理連鏈的高階寶石
	for chained in chained_uppers:
		var cp: Vector2i = chained.pos
		# 該寶石已被消除，直接計算爆炸範圍
		var cut: Block.UpperType = chained.upper_type as Block.UpperType
		var chain_positions: Array[Vector2i] = []
		match cut:
			Block.UpperType.FIREBALL:
				chain_positions = _get_area_positions(cp, 4)
			Block.UpperType.FIRE_PILLAR_X:
				chain_positions = _get_row_positions(cp.y)
			Block.UpperType.FIRE_PILLAR_Y:
				chain_positions = _get_col_positions(cp.x)
			Block.UpperType.SAINT_CROSS:
				chain_positions = _get_cross_positions(cp)

		# 過濾已被消除的位置
		var valid_positions: Array[Vector2i] = []
		for pp in chain_positions:
			if _is_valid(pp) and grid[pp.x][pp.y] != null:
				valid_positions.append(pp)

		if valid_positions.size() > 0:
			chain_data[0] += 1
			await _execute_upper_blast_chain(valid_positions, chain_data, total_blasted_by_type)


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


## 進入選擇模式（由 main.gd 呼叫，玩家懸停預覽十字，點擊確認轉換）
func enter_selection_mode(convert_type: Block.Type) -> void:
	_selection_mode = true
	_selection_convert_type = convert_type
	_preview_center = Vector2i(-1, -1)


## 離開選擇模式（取消）
func exit_selection_mode() -> void:
	_selection_mode = false
	_clear_preview_overlays()
	_preview_center = Vector2i(-1, -1)


## 更新十字預覽覆蓋層（黃色半透明方塊顯示在預覽位置上方）
func _update_cross_preview(center: Vector2i) -> void:
	_clear_preview_overlays()
	_preview_center = center
	var positions := _get_cross_positions(center)
	for p in positions:
		var overlay := ColorRect.new()
		overlay.color = Color(1.0, 0.92, 0.23, 0.35)
		overlay.size = Vector2(CELL_SIZE, CELL_SIZE)
		overlay.position = Vector2(p.x * CELL_SIZE, p.y * CELL_SIZE)
		overlay.z_index = 10
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(overlay)
		_preview_overlays.append(overlay)


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
	# 第一階段：清除所有現有提示
	for x in columns:
		for y in rows:
			var block: Block = grid[x][y]
			if block != null:
				block.hide_fuse_hint()

	if _fuse_skills.is_empty():
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
