class_name StatChart
extends Control

signal hover_level(level_value: int)

const CURRENT_COLOR: Color = Color(1.0, 0.85, 0.24, 0.95)
const GRID_COLOR: Color = Color(0.35, 0.38, 0.48, 0.22)
const AXIS_COLOR: Color = Color(0.75, 0.78, 0.88, 0.55)
const PAD_LEFT: float = 24.0
const PAD_TOP: float = 12.0
const PAD_RIGHT: float = 10.0
const PAD_BOTTOM: float = 20.0
const GRID_LINES: int = 4

var _levels: Array[int] = []
var _values: Array[int] = []
var _stat_label: String = ""
var _line_color: Color = Color.WHITE
var _min_level: int = 1
var _max_level: int = 99
var _current_level: int = 1
var _max_value: float = 1.0
var _hover_idx: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(stat_label: String, line_color: Color) -> void:
	_stat_label = stat_label
	_line_color = line_color
	queue_redraw()


func clear() -> void:
	_levels.clear()
	_values.clear()
	_hover_idx = -1
	tooltip_text = ""
	queue_redraw()


func set_series(values: Array[int], min_level: int, max_level: int, current_level: int) -> void:
	_levels.clear()
	_values.clear()
	_hover_idx = -1
	tooltip_text = ""
	_min_level = maxi(min_level, 1)
	_max_level = maxi(max_level, _min_level)
	_current_level = clampi(current_level, _min_level, _max_level)
	var raw_max_value: float = 1.0

	for value_index: int in values.size():
		var level_value: int = _min_level + value_index
		if level_value > _max_level:
			break
		var stat_value: int = values[value_index]
		_levels.append(level_value)
		_values.append(stat_value)
		raw_max_value = maxf(raw_max_value, float(stat_value))

	_max_value = _nice_ceiling(raw_max_value)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_set_hover_from_position(motion.position)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_clear_hover()


func _draw() -> void:
	var bg_rect: Rect2 = Rect2(Vector2.ZERO, size)
	draw_rect(bg_rect, Color(0.055, 0.065, 0.095, 1.0), true)
	if _levels.is_empty():
		return

	var plot_rect: Rect2 = _get_plot_rect()
	draw_rect(plot_rect, Color(0.075, 0.085, 0.125, 1.0), true)
	_draw_grid(plot_rect)
	_draw_series(plot_rect, _values, _line_color, 2.8)
	_draw_current_marker(plot_rect)
	_draw_hover_marker(plot_rect)


func _get_plot_rect() -> Rect2:
	var plot_w: float = maxf(1.0, size.x - PAD_LEFT - PAD_RIGHT)
	var plot_h: float = maxf(1.0, size.y - PAD_TOP - PAD_BOTTOM)
	return Rect2(Vector2(PAD_LEFT, PAD_TOP), Vector2(plot_w, plot_h))


func _draw_grid(plot_rect: Rect2) -> void:
	for i: int in GRID_LINES + 1:
		var ratio: float = float(i) / float(GRID_LINES)
		var y: float = plot_rect.position.y + plot_rect.size.y * ratio
		draw_line(Vector2(plot_rect.position.x, y), Vector2(plot_rect.end.x, y), GRID_COLOR, 1.0)

	for i: int in GRID_LINES + 1:
		var ratio: float = float(i) / float(GRID_LINES)
		var x: float = plot_rect.position.x + plot_rect.size.x * ratio
		draw_line(Vector2(x, plot_rect.position.y), Vector2(x, plot_rect.end.y), GRID_COLOR, 1.0)

	draw_line(plot_rect.position, Vector2(plot_rect.position.x, plot_rect.end.y), AXIS_COLOR, 1.5)
	draw_line(Vector2(plot_rect.position.x, plot_rect.end.y), plot_rect.end, AXIS_COLOR, 1.5)


func _draw_series(plot_rect: Rect2, values: Array[int], color: Color, width: float) -> void:
	if values.size() < 2:
		return
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in values.size():
		points.append(_point_for(plot_rect, i, float(values[i])))
	draw_polyline(points, Color(0, 0, 0, 0.35), width + 2.0, true)
	draw_polyline(points, color, width, true)


func _draw_current_marker(plot_rect: Rect2) -> void:
	var idx: int = clampi(_current_level - _min_level, 0, _levels.size() - 1)
	var x: float = _x_for_index(plot_rect, idx)
	draw_line(Vector2(x, plot_rect.position.y), Vector2(x, plot_rect.end.y), CURRENT_COLOR, 1.4)
	draw_circle(_point_for(plot_rect, idx, float(_values[idx])), 4.0, _line_color)


func _draw_hover_marker(plot_rect: Rect2) -> void:
	if _hover_idx < 0 or _hover_idx >= _levels.size():
		return
	var x: float = _x_for_index(plot_rect, _hover_idx)
	draw_line(Vector2(x, plot_rect.position.y), Vector2(x, plot_rect.end.y), Color(1, 1, 1, 0.55), 1.2)
	draw_circle(_point_for(plot_rect, _hover_idx, float(_values[_hover_idx])), 5.0, _line_color)


func _point_for(plot_rect: Rect2, idx: int, value: float) -> Vector2:
	var x: float = _x_for_index(plot_rect, idx)
	var y_ratio: float = clampf(value / maxf(_max_value, 1.0), 0.0, 1.0)
	var y: float = plot_rect.end.y - plot_rect.size.y * y_ratio
	return Vector2(x, y)


func _x_for_index(plot_rect: Rect2, idx: int) -> float:
	if _levels.size() <= 1:
		return plot_rect.position.x
	var ratio: float = float(idx) / float(_levels.size() - 1)
	return plot_rect.position.x + plot_rect.size.x * ratio


func _set_hover_from_position(pos: Vector2) -> void:
	if _levels.is_empty():
		_clear_hover()
		return
	var plot_rect: Rect2 = _get_plot_rect()
	if not plot_rect.has_point(pos):
		_clear_hover()
		return
	var ratio: float = clampf((pos.x - plot_rect.position.x) / maxf(plot_rect.size.x, 1.0), 0.0, 1.0)
	var idx: int = clampi(int(round(ratio * float(_levels.size() - 1))), 0, _levels.size() - 1)
	if idx == _hover_idx:
		return
	_hover_idx = idx
	tooltip_text = "%s Lv.%d: %d" % [_stat_label, _levels[idx], _values[idx]]
	hover_level.emit(_levels[idx])
	queue_redraw()


func _clear_hover() -> void:
	if _hover_idx == -1:
		return
	_hover_idx = -1
	tooltip_text = ""
	queue_redraw()


func _nice_ceiling(value: float) -> float:
	if value <= 10.0:
		return 10.0
	var magnitude: float = pow(10.0, floor(log(value) / log(10.0)))
	var normalized: float = value / magnitude
	var nice: float = 10.0
	if normalized <= 1.0:
		nice = 1.0
	elif normalized <= 2.0:
		nice = 2.0
	elif normalized <= 5.0:
		nice = 5.0
	return nice * magnitude