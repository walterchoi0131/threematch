class_name CircleProgressRing
extends Control

var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()

var ring_color: Color = Color(0.55, 1.0, 0.45, 0.95):
	set(value):
		ring_color = value
		queue_redraw()

var background_color: Color = Color(0.02, 0.03, 0.02, 0.62):
	set(value):
		background_color = value
		queue_redraw()

var line_width: float = 7.0:
	set(value):
		line_width = maxf(value, 1.0)
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius: float = maxf(minf(size.x, size.y) * 0.5 - line_width * 0.5, 1.0)
	draw_circle(center, radius + line_width * 0.2, background_color)
	draw_arc(center, radius, -PI * 0.5, PI * 1.5, 64, Color(0.85, 0.95, 0.82, 0.26), line_width, true)
	if progress <= 0.0:
		return
	draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * progress, 64, ring_color, line_width, true)
