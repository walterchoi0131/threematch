## OvalShape — 自繪扁平橢圓（含填色 + 邊框）。
## 用於世界地圖關卡指示器；尺寸由 `size` 決定（rx=size.x/2, ry=size.y/2）。
@tool
class_name OvalShape
extends Control

const SEGMENTS: int = 64

@export var fill_color: Color = Color(0.94, 0.62, 0.18, 1.0):
	set(value):
		fill_color = value
		queue_redraw()

@export var border_color: Color = Color(0.24, 0.16, 0.08, 1.0):
	set(value):
		border_color = value
		queue_redraw()

@export var border_width: float = 3.0:
	set(value):
		border_width = value
		queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	var cx: float = size.x * 0.5
	var cy: float = size.y * 0.5
	var rx: float = max(0.0, cx - border_width * 0.5)
	var ry: float = max(0.0, cy - border_width * 0.5)

	var pts := PackedVector2Array()
	pts.resize(SEGMENTS)
	for i in SEGMENTS:
		var a: float = TAU * float(i) / float(SEGMENTS)
		pts[i] = Vector2(cx + cos(a) * rx, cy + sin(a) * ry)

	var fill_cols := PackedColorArray()
	fill_cols.resize(SEGMENTS)
	for i in SEGMENTS:
		fill_cols[i] = fill_color
	draw_polygon(pts, fill_cols)

	if border_width > 0.0:
		var loop := PackedVector2Array()
		loop.resize(SEGMENTS + 1)
		for i in SEGMENTS:
			loop[i] = pts[i]
		loop[SEGMENTS] = pts[0]
		draw_polyline(loop, border_color, border_width, true)
