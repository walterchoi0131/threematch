## TutorialManager — 教學步驟控制器。
## 管理：對話 → 高亮+手指 → 等待玩家操作 → 後續對話 → 下一步驟 的循環。
extends Node

const _DialogLine := preload("res://scripts/dialog_line.gd")
const _BattleDialog := preload("res://scripts/battle_dialog.gd")

signal step_completed(step_index: int)
signal tutorial_finished

## 步驟資料格式：
## {
##   "pre_dialog": Array[DialogLine],    — 步驟開始前的對話
##   "highlight": Array[Vector2i],       — 要高亮的格子
##   "hand_pos": Vector2i,               — 手指圖示位置（(-1,-1) = 不顯示）
##   "filter": Array[Vector2i],          — 可點擊的格子（空 = 全部可點）
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
