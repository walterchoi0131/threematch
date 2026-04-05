## RayBurst — 高階寶石底下旋轉放射光芒效果（旭日旗風格錐形射線）。
## 使用 _draw() 從中心畫出錐形三角形，_process() 持續旋轉。
extends Node2D

var ray_count := 8      # 射線條數
var outer_radius := 30.0   # 射線最遠端半徑
## 每道射線半角：0.28 rad ≈ 16°，8 條 × 32° = 256°，約 71% 填充率（粗錐形）
var ray_half_angle := 0.18
var rotation_speed := 0.6  # 旋轉速度（弧度/秒）
var ray_color := Color(1.0, 0.90, 0.35, 0.82)


func _process(delta: float) -> void:
	rotation += rotation_speed * delta
	queue_redraw()


func _draw() -> void:
	const STEPS := 5  # 徑向分段數，越多曲線越平滑
	for i in ray_count:
		var base_angle: float = (TAU / float(ray_count)) * float(i)
		var left_a: float = base_angle - ray_half_angle
		var right_a: float = base_angle + ray_half_angle
		var left_dir := Vector2(cos(left_a), sin(left_a))
		var right_dir := Vector2(cos(right_a), sin(right_a))

		for s in STEPS:
			var t_inner: float = float(s) / float(STEPS)
			var t_outer: float = float(s + 1) / float(STEPS)
			var r_inner: float = t_inner * outer_radius
			var r_outer: float = t_outer * outer_radius

			# ease-out：靠近透明端時漸變趨緩（pow 曲線）
			var alpha_inner: float = pow(1.25 - t_inner, 2.0) * ray_color.a
			var alpha_outer: float = pow(1.25 - t_outer, 2.0) * ray_color.a

			var c_inner := Color(ray_color.r, ray_color.g, ray_color.b, alpha_inner)
			var c_outer := Color(ray_color.r, ray_color.g, ray_color.b, alpha_outer)

			var il: Vector2 = left_dir * r_inner
			var ir: Vector2 = right_dir * r_inner
			var ol: Vector2 = left_dir * r_outer
			var or_v: Vector2 = right_dir * r_outer

			# 梯形（最內層退化為三角形）
			draw_polygon([il, ir, or_v, ol], [c_inner, c_inner, c_outer, c_outer])
