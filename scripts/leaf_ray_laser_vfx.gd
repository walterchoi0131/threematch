extends Node2D

signal finished

var from_pos: Vector2 = Vector2.ZERO
var to_pos: Vector2 = Vector2.ZERO
var duration: float = 1.0
var elapsed: float = 0.0
var source_node: Node2D = null


func _init() -> void:
	set_process(false)


func start(p_from: Vector2, p_to: Vector2, p_duration: float = 1.0) -> void:
	source_node = null
	from_pos = p_from
	to_pos = p_to
	duration = maxf(p_duration, 0.05)
	elapsed = 0.0
	z_index = 96
	set_process(true)
	queue_redraw()


func start_following(p_source: Node2D, p_to: Vector2, p_duration: float = 1.0) -> void:
	source_node = p_source
	from_pos = p_source.global_position if is_instance_valid(p_source) else from_pos
	to_pos = p_to
	duration = maxf(p_duration, 0.05)
	elapsed = 0.0
	z_index = 96
	set_process(true)
	queue_redraw()


func play(p_from: Vector2, p_to: Vector2, p_duration: float = 1.0) -> void:
	start(p_from, p_to, p_duration)
	await finished


func _process(delta: float) -> void:
	if is_instance_valid(source_node):
		from_pos = source_node.global_position
	elapsed += delta
	queue_redraw()
	if elapsed >= duration:
		set_process(false)
		finished.emit()
		queue_free()


func _draw() -> void:
	var beam_vec := to_pos - from_pos
	var beam_len := beam_vec.length()
	if beam_len <= 0.1:
		return

	var dir := beam_vec / beam_len
	var perp := Vector2(-dir.y, dir.x)
	var extend := clampf(elapsed / 0.18, 0.0, 1.0)
	var fade := 1.0
	if elapsed > duration - 0.35:
		fade = clampf((duration - elapsed) / 0.35, 0.0, 1.0)
	var pulse := 0.5 + 0.5 * sin(elapsed * 18.0)
	var end_pos := from_pos + beam_vec * extend

	draw_line(from_pos, end_pos, Color(0.10, 0.95, 0.20, 0.34 * fade), 34.0 + 6.0 * pulse, true)
	draw_line(from_pos, end_pos, Color(0.42, 1.00, 0.05, 0.44 * fade), 24.0 + 4.0 * pulse, true)
	draw_line(from_pos, end_pos, Color(1.00, 0.90, 0.08, 0.78 * fade), 13.0 + 3.0 * pulse, true)
	draw_line(from_pos, end_pos, Color(1.00, 1.00, 0.88, 0.98 * fade), 6.0 + 1.5 * pulse, true)

	for i in range(9):
		var t0 := float(i) / 9.0
		var t1 := minf(1.0, t0 + 0.38 + 0.08 * sin(float(i)))
		var phase := elapsed * (3.2 + float(i) * 0.13) + float(i) * 1.7
		var offset := perp * (sin(phase) * 18.0 + cos(phase * 0.7) * 8.0)
		var start := from_pos.lerp(end_pos, t0) + offset * 0.55
		var stop := from_pos.lerp(end_pos, t1) + offset
		var line_color := Color(0.64, 1.0, 0.10, (0.34 + 0.16 * pulse) * fade)
		if i % 3 == 0:
			line_color = Color(1.0, 0.75, 0.08, 0.50 * fade)
		draw_line(start, stop, line_color, 2.0 + float(i % 3), true)
