## TutorialManager — 教學步驟控制器。
## 管理：對話 → 高亮+手指 → 等待玩家操作 → 後續對話 → 下一步驟 的循環。
extends Node

const _DialogLine := preload("res://scripts/dialog_line.gd")
const _BattleDialog := preload("res://scripts/battle_dialog.gd")

const SPOTLIGHT_DIM_COLOR := Color(0, 0, 0, 0.68)
const SPOTLIGHT_FADE_IN := 0.18
const SPOTLIGHT_FADE_OUT := 0.28

signal step_completed(step_index: int)
signal tutorial_finished

## 步驟資料格式：
## {
##   "pre_dialog": Array[DialogLine],    — 步驟開始前的對話
##   "highlight": Array[Vector2i],       — 要高亮的格子
##   "hand_pos": Vector2i,               — 手指圖示位置（(-1,-1) = 不顯示）
##   "filter": Array[Vector2i],          — 可點擊的格子（空 = 全部可點）
##   "spotlight": Dictionary,            — 可選；{target, shape, hold} 的非互動聚焦遮罩
##   "wait_for_blast": bool,             — 可選；false 表示不等待玩家操作
##   "post_dialog": Array[DialogLine],   — 操作完成後的對話
## }

var _steps: Array = []
var _current_step: int = -1
var _board: Node2D = null
var _dialog: _BattleDialog = null
var _waiting_for_blast: bool = false


## 初始化：傳入棋盤和對話面板引用
func setup(board: Node2D, dialog: _BattleDialog) -> void:
	_board = board
	_dialog = dialog


## 設定步驟資料並開始教學
func start(steps: Array) -> void:
	_steps = steps
	_current_step = -1
	_board.gems_blasted.connect(_on_gems_blasted)
	_advance_step()


## 推進到下一步驟
func _advance_step() -> void:
	_current_step += 1
	if _current_step >= _steps.size():
		_finish_tutorial()
		return
	_run_step(_steps[_current_step])


## 執行單一步驟
func _run_step(step: Dictionary) -> void:
	_board.is_busy = true

	# ── 前置對話 ──
	var pre_dialog: Array = step.get("pre_dialog", [])
	if pre_dialog.size() > 0:
		_dialog.show_lines(pre_dialog)
		await _dialog.all_lines_finished

	# ── 非互動聚焦遮罩 ──
	var spotlight: Dictionary = step.get("spotlight", {})
	if not spotlight.is_empty():
		await _play_spotlight(spotlight)

	# ── 高亮 + 手指 + 過濾 ──
	var highlight: Array = step.get("highlight", [])
	if highlight.size() > 0:
		var typed_highlight: Array[Vector2i] = []
		for p in highlight:
			typed_highlight.append(p as Vector2i)
		_board.set_tutorial_highlight(typed_highlight)

	var hand_pos: Vector2i = step.get("hand_pos", Vector2i(-1, -1))
	if hand_pos != Vector2i(-1, -1):
		_board.show_hand_hint(hand_pos)

	var filter: Array = step.get("filter", [])
	if filter.size() > 0:
		var typed_filter: Array[Vector2i] = []
		for p in filter:
			typed_filter.append(p as Vector2i)
		_board.set_tutorial_filter(typed_filter)

	var requires_blast: bool = bool(step.get("wait_for_blast", highlight.size() > 0 or hand_pos != Vector2i(-1, -1) or filter.size() > 0))
	if requires_blast:
		# ── 等待玩家操作 ──
		_waiting_for_blast = true
		_board.is_busy = false  # 解鎖棋盤讓玩家點擊

		# 等 gems_blasted 信號
		await self.step_completed  # _on_gems_blasted 會發出這個

	# ── 清除高亮/手指/過濾 ──
	_board.is_busy = true
	_board.hide_hand_hint()
	_board.clear_tutorial_highlight()
	_board.clear_tutorial_filter()

	# ── 後續對話 ──
	var post_dialog: Array = step.get("post_dialog", [])
	if post_dialog.size() > 0:
		_dialog.show_lines(post_dialog)
		await _dialog.all_lines_finished

	# ── 後續覆蓋面板（例如融合提示卡）──
	var post_canvas_fn: Callable = step.get("post_canvas_fn", Callable())
	if post_canvas_fn.is_valid():
		var done := {"closed": false}
		var on_close := func() -> void:
			done.closed = true
		post_canvas_fn.call(self, on_close)
		while not done.closed:
			await get_tree().process_frame

	# 進入下一步
	_advance_step()


func _play_spotlight(config: Dictionary) -> void:
	var target_rect: Rect2 = _resolve_spotlight_rect(str(config.get("target", "")))
	if target_rect.size.x <= 0.0 or target_rect.size.y <= 0.0:
		return
	var layer := CanvasLayer.new()
	layer.layer = 84
	add_child(layer)

	var overlay := _TutorialSpotlightOverlay.new()
	overlay.dim_color = SPOTLIGHT_DIM_COLOR
	overlay.hole_shape = str(config.get("shape", "rect"))
	overlay.hole_rect = target_rect
	overlay.modulate.a = 0.0
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(overlay)

	var fade_in := create_tween()
	fade_in.tween_property(overlay, "modulate:a", 1.0, SPOTLIGHT_FADE_IN).set_ease(Tween.EASE_OUT)
	await fade_in.finished
	await get_tree().create_timer(float(config.get("hold", 3.0))).timeout
	var fade_out := create_tween()
	fade_out.tween_property(overlay, "modulate:a", 0.0, SPOTLIGHT_FADE_OUT).set_ease(Tween.EASE_IN)
	await fade_out.finished
	if is_instance_valid(layer):
		layer.queue_free()


func _resolve_spotlight_rect(target: String) -> Rect2:
	var host: Node = get_parent()
	if host == null:
		host = get_tree().current_scene
	if host == null:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	match target:
		"first_enemy":
			var enemy_row: Node = host.get_node_or_null("UILayer/EnemyRow")
			if enemy_row == null:
				return Rect2(Vector2.ZERO, Vector2.ZERO)
			for child in enemy_row.get_children():
				if child is Control and (child as Control).visible and (child as Control).modulate.a > 0.01:
					return (child as Control).get_global_rect().grow(10.0)
		"player_hp":
			var hp_bar: Control = host.get_node_or_null("UILayer/PlayerHPBar") as Control
			if hp_bar != null:
				return hp_bar.get_global_rect().grow(6.0)
	return Rect2(Vector2.ZERO, Vector2.ZERO)


class _TutorialSpotlightOverlay extends Control:
	var dim_color: Color = Color(0, 0, 0, 0.68)
	var hole_shape: String = "rect"
	var hole_rect: Rect2 = Rect2(Vector2.ZERO, Vector2.ZERO)
	const OUTLINE_COLOR := Color(1.0, 0.86, 0.24, 0.95)
	const CIRCLE_SCAN_STEP := 4.0

	func _draw() -> void:
		var full_rect := Rect2(Vector2.ZERO, size)
		var clipped: Rect2 = hole_rect.intersection(full_rect).grow(0.0)
		if clipped.size.x <= 0.0 or clipped.size.y <= 0.0:
			draw_rect(full_rect, dim_color)
			return
		if hole_shape == "circle":
			_draw_circle_hole(clipped)
		else:
			_draw_rect_hole(clipped)

	func _draw_rect_hole(rect: Rect2) -> void:
		_draw_dim_rect(Rect2(Vector2.ZERO, Vector2(size.x, rect.position.y)))
		_draw_dim_rect(Rect2(Vector2(0.0, rect.position.y + rect.size.y), Vector2(size.x, size.y - rect.position.y - rect.size.y)))
		_draw_dim_rect(Rect2(Vector2(0.0, rect.position.y), Vector2(rect.position.x, rect.size.y)))
		_draw_dim_rect(Rect2(Vector2(rect.position.x + rect.size.x, rect.position.y), Vector2(size.x - rect.position.x - rect.size.x, rect.size.y)))
		draw_rect(rect, OUTLINE_COLOR, false, 3.0)

	func _draw_circle_hole(rect: Rect2) -> void:
		var center: Vector2 = rect.position + rect.size * 0.5
		var radius: float = maxf(rect.size.x, rect.size.y) * 0.5
		var top: float = center.y - radius
		var bottom: float = center.y + radius
		_draw_dim_rect(Rect2(Vector2.ZERO, Vector2(size.x, top)))
		_draw_dim_rect(Rect2(Vector2(0.0, bottom), Vector2(size.x, size.y - bottom)))
		var y: float = maxf(top, 0.0)
		while y < minf(bottom, size.y):
			var band_h: float = minf(CIRCLE_SCAN_STEP, minf(bottom, size.y) - y)
			var sample_y: float = y + band_h * 0.5
			var dy: float = sample_y - center.y
			var half_w: float = sqrt(maxf(radius * radius - dy * dy, 0.0))
			var left_edge: float = clampf(center.x - half_w, 0.0, size.x)
			var right_edge: float = clampf(center.x + half_w, 0.0, size.x)
			_draw_dim_rect(Rect2(Vector2(0.0, y), Vector2(left_edge, band_h)))
			_draw_dim_rect(Rect2(Vector2(right_edge, y), Vector2(size.x - right_edge, band_h)))
			y += CIRCLE_SCAN_STEP
		draw_arc(center, radius, 0.0, TAU, 96, OUTLINE_COLOR, 3.0, true)

	func _draw_dim_rect(rect: Rect2) -> void:
		if rect.size.x > 0.5 and rect.size.y > 0.5:
			draw_rect(rect, dim_color)


## 玩家消除寶石時的回呼
func _on_gems_blasted(_gem_type: Block.Type, _count: int, _global_positions: Array) -> void:
	if not _waiting_for_blast:
		return
	_waiting_for_blast = false
	# 等待攻擊/融合管線完成（is_busy 從 true 變回 false）
	while _board.is_busy:
		await get_tree().process_frame
	step_completed.emit(_current_step)


## 教學結束
func _finish_tutorial() -> void:
	_board.hide_hand_hint()
	_board.clear_tutorial_highlight()
	_board.clear_tutorial_filter()
	if _board.gems_blasted.is_connected(_on_gems_blasted):
		_board.gems_blasted.disconnect(_on_gems_blasted)
	tutorial_finished.emit()
