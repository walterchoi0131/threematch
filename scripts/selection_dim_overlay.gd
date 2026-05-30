extends Control

var dim_color: Color = Color(0, 0, 0, 0.62)
var clear_rects: Array[Rect2] = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_clear_rects(rects: Array[Rect2]) -> void:
	clear_rects = rects.duplicate()
	queue_redraw()


func _draw() -> void:
	var covered_rects: Array[Rect2] = [Rect2(Vector2.ZERO, size)]
	for clear_rect in clear_rects:
		var clipped: Rect2 = _intersect_rect(clear_rect, Rect2(Vector2.ZERO, size))
		if clipped.size.x <= 0.0 or clipped.size.y <= 0.0:
			continue
		var next_rects: Array[Rect2] = []
		for covered in covered_rects:
			for piece in _subtract_rect(covered, clipped):
				next_rects.append(piece)
		covered_rects = next_rects

	for rect in covered_rects:
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			draw_rect(rect, dim_color)


func _intersect_rect(a: Rect2, b: Rect2) -> Rect2:
	var left: float = maxf(a.position.x, b.position.x)
	var top: float = maxf(a.position.y, b.position.y)
	var right: float = minf(a.position.x + a.size.x, b.position.x + b.size.x)
	var bottom: float = minf(a.position.y + a.size.y, b.position.y + b.size.y)
	if right <= left or bottom <= top:
		return Rect2(Vector2.ZERO, Vector2.ZERO)
	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))


func _subtract_rect(source: Rect2, clear_rect: Rect2) -> Array[Rect2]:
	var cut: Rect2 = _intersect_rect(source, clear_rect)
	if cut.size.x <= 0.0 or cut.size.y <= 0.0:
		return [source]

	var pieces: Array[Rect2] = []
	var source_left: float = source.position.x
	var source_top: float = source.position.y
	var source_right: float = source.position.x + source.size.x
	var source_bottom: float = source.position.y + source.size.y
	var cut_left: float = cut.position.x
	var cut_top: float = cut.position.y
	var cut_right: float = cut.position.x + cut.size.x
	var cut_bottom: float = cut.position.y + cut.size.y

	_add_rect_if_visible(pieces, Rect2(Vector2(source_left, source_top), Vector2(source.size.x, cut_top - source_top)))
	_add_rect_if_visible(pieces, Rect2(Vector2(source_left, cut_bottom), Vector2(source.size.x, source_bottom - cut_bottom)))
	_add_rect_if_visible(pieces, Rect2(Vector2(source_left, cut_top), Vector2(cut_left - source_left, cut.size.y)))
	_add_rect_if_visible(pieces, Rect2(Vector2(cut_right, cut_top), Vector2(source_right - cut_right, cut.size.y)))
	return pieces


func _add_rect_if_visible(rects: Array[Rect2], rect: Rect2) -> void:
	if rect.size.x > 0.5 and rect.size.y > 0.5:
		rects.append(rect)