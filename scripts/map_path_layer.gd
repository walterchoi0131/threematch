## MapPathLayer — 在世界地圖 StageButton 之間繪製道路連線。
## 由 map.gd 建立，stage_buttons 由 map.gd 注入。
extends Control

const PATH_WIDTH: float = 8.0
const COLOR_LOCKED: Color = Color(0.45, 0.45, 0.5, 0.55)
const COLOR_AVAILABLE: Color = Color(0.85, 0.7, 0.4, 0.9)
const COLOR_CLEARED: Color = Color(0.55, 0.85, 0.55, 0.95)

var stage_buttons: Array = []


func _draw() -> void:
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
		var connects: Array = sb.stage.connects_to
		if connects == null or connects.is_empty():
			connects = derived.get(sb.stage.stage_id, [])
		if connects.is_empty():
			continue
		var from_center: Vector2 = sb.position + sb.size * 0.5
		for next_id: String in connects:
			var nb: Node = by_id.get(next_id, null)
			if nb == null or not nb.visible:
				continue
			var to_center: Vector2 = nb.position + nb.size * 0.5
			var color: Color = Color(1, 1, 1, 0.95)
			# 黑色描邊讓線條在底圖上更清楚
			draw_line(from_center, to_center, Color(0, 0, 0, 0.6), PATH_WIDTH + 4.0, true)
			draw_line(from_center, to_center, color, PATH_WIDTH, true)
