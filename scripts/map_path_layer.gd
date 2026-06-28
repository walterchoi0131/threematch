## MapPathLayer — 在世界地圖 StageButton 之間繪製道路連線。
## 由 map.gd 建立，stage_buttons 由 map.gd 注入。
extends Control

const PATH_WIDTH: float = 8.0
const COLOR_LOCKED: Color = Color(0.45, 0.45, 0.5, 0.55)
const COLOR_AVAILABLE: Color = Color(0.85, 0.7, 0.4, 0.9)
const COLOR_CLEARED: Color = Color(0.55, 0.85, 0.55, 0.95)
const HIT_PADDING: float = 14.0
const DRAFT_COLOR: Color = Color(0.35, 0.85, 1.0, 0.95)

var stage_buttons: Array = []
var draft_from_stage_id: String = ""
var draft_to_position: Vector2 = Vector2.ZERO
var _path_segments: Array[Dictionary] = []


func _draw() -> void:
	_path_segments.clear()
	if stage_buttons.is_empty():
		return
	# 建立 stage_id → StageButton 對照
	var by_id: Dictionary = {}
	for sb in stage_buttons:
		if sb == null or sb.stage == null:
			continue
		by_id[sb.stage.stage_id] = sb
	# 從 prerequisite_stage_id 反推出 prereq → [後續 stage_id] 對照
	var derived: Dictionary = {}
	for sb in stage_buttons:
		if sb == null or sb.stage == null:
			continue
		var prereq: String = sb.stage.prerequisite_stage_id
		if prereq == "":
			continue
		if not derived.has(prereq):
			derived[prereq] = []
		(derived[prereq] as Array).append(sb.stage.stage_id)
	for sb in stage_buttons:
		if sb == null or sb.stage == null or not sb.visible:
			continue
		# 優先使用顯式 connects_to；若為空則使用反推結果
		var connects: Array = []
		for next_id in sb.stage.connects_to:
			if not connects.has(String(next_id)):
				connects.append(String(next_id))
		for next_id in derived.get(sb.stage.stage_id, []):
			if not connects.has(String(next_id)):
				connects.append(String(next_id))
		if connects.is_empty():
			continue
		var from_center: Vector2 = sb.position + _anchor_offset(sb)
		for next_id: String in connects:
			var nb: Node = by_id.get(next_id, null)
			if nb == null or not nb.visible:
				continue
			var to_center: Vector2 = nb.position + _anchor_offset(nb)
			var color: Color = Color(1, 1, 1, 0.95)
			_path_segments.append({
				"from_id": sb.stage.stage_id,
				"to_id": next_id,
				"from": from_center,
				"to": to_center,
			})
			# 黑色描邊讓線條在底圖上更清楚
			draw_line(from_center, to_center, Color(0, 0, 0, 0.6), PATH_WIDTH + 4.0, true)
			draw_line(from_center, to_center, color, PATH_WIDTH, true)
	_draw_draft_path(by_id)


## 取得 StageButton 的橢圓中心（本地座標）；若按鈕有提供 get_anchor_center 則優先採用，
## 否則退回 size * 0.5。
func set_draft_path(from_stage_id: String, to_position: Vector2) -> void:
	draft_from_stage_id = from_stage_id
	draft_to_position = to_position
	queue_redraw()


func clear_draft_path() -> void:
	if draft_from_stage_id == "":
		return
	draft_from_stage_id = ""
	queue_redraw()


func find_relation_at_point(point: Vector2) -> Dictionary:
	for segment in _path_segments:
		var from_pos: Vector2 = segment.get("from", Vector2.ZERO) as Vector2
		var to_pos: Vector2 = segment.get("to", Vector2.ZERO) as Vector2
		if _distance_to_segment(point, from_pos, to_pos) <= PATH_WIDTH * 0.5 + HIT_PADDING:
			return {
				"from_id": String(segment.get("from_id", "")),
				"to_id": String(segment.get("to_id", "")),
			}
	return {}


func _draw_draft_path(by_id: Dictionary) -> void:
	if draft_from_stage_id == "" or not by_id.has(draft_from_stage_id):
		return
	var sb: Node = by_id[draft_from_stage_id] as Node
	if sb == null:
		return
	var from_center: Vector2 = (sb as Control).position + _anchor_offset(sb)
	draw_line(from_center, draft_to_position, Color(0, 0, 0, 0.55), PATH_WIDTH + 6.0, true)
	draw_line(from_center, draft_to_position, DRAFT_COLOR, PATH_WIDTH, true)
	draw_circle(draft_to_position, 8.0, DRAFT_COLOR)


func _distance_to_segment(point: Vector2, from_pos: Vector2, to_pos: Vector2) -> float:
	var segment: Vector2 = to_pos - from_pos
	var len_sq: float = segment.length_squared()
	if len_sq <= 0.001:
		return point.distance_to(from_pos)
	var t: float = clampf((point - from_pos).dot(segment) / len_sq, 0.0, 1.0)
	return point.distance_to(from_pos + segment * t)


func _anchor_offset(sb: Node) -> Vector2:
	if sb.has_method("get_anchor_center"):
		return sb.call("get_anchor_center")
	return (sb as Control).size * 0.5
