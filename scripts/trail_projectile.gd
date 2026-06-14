## TrailProjectile（拖尾弧光）— 發光球頭 + 漸隱拖尾線 + GPUParticles2D 火花。
## 支援池模式（寶石→角色卡）與一次性模式（角色卡→敵人）。
extends Node2D

const TRAIL_LENGTH := 28         # 拖尾記錄點數
const HEAD_RADIUS := 5.0         # 球頭核心半徑
const HEAD_GLOW_RADIUS := 28.0   # 球頭最外層光暈半徑
const TRAIL_WIDTH_HEAD := 18.0   # 拖尾頭端寬度（寬光帶）
const TRAIL_WIDTH_TAIL := 1.0    # 拖尾尾端寬度
const SPARKLE_AMOUNT := 16       # 火花粒子數量
const FLARE_COUNT := 4           # 十字光芒條數
const FLARE_LENGTH := 22.0       # 光芒長度
const FLARE_WIDTH := 2.0         # 光芒寬度
const PARTICLE_SCALE_MIN := 0.6
const PARTICLE_SCALE_MAX := 1.2

static var speed_divisor := 3.5  # 速度除數（外部可調）
static var _spark_particle_texture: Texture2D = null

signal released   ## 飛行結束、可被池回收
signal deduct_hp  ## 命中時扣血（攻擊模式用）

var is_available := true

var _color := Color.WHITE
var _trail: Array[Vector2] = []
var _tween: Tween
var _particles: GPUParticles2D
var _flying := false
var _bursting := false
var _head_pos := Vector2.ZERO  # 全域座標中的頭部位置
var _burst_pos := Vector2.ZERO
var _burst_scale := 1.0
var _burst_alpha := 0.0
var _visual_size_multiplier: float = 1.0
var _orbiting := false
var _orbit_center_global := Vector2.ZERO
var _orbit_radius := 28.0
var _orbit_angle := 0.0
var _orbit_speed := 2.6


## 初始化（池模式呼叫一次）
static func make_attack_spark_texture() -> Texture2D:
	if _spark_particle_texture != null:
		return _spark_particle_texture
	var tex_size := 16
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(tex_size - 1) / 2.0, float(tex_size - 1) / 2.0)
	var max_dist: float = float(tex_size) / 2.0
	for y in tex_size:
		for x in tex_size:
			var dist: float = Vector2(x, y).distance_to(center)
			var t: float = clampf(dist / max_dist, 0.0, 1.0)
			var a: float = pow(1.0 - t, 1.5)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_spark_particle_texture = ImageTexture.create_from_image(img)
	return _spark_particle_texture


func setup() -> void:
	if _particles == null:
		_build_particles()
	_apply_particle_size()


func set_visual_size_multiplier(value: float) -> void:
	_visual_size_multiplier = maxf(0.1, value)
	_apply_particle_size()
	queue_redraw()


## 發射：從 from 到 to（全域座標），沿 Bezier 弧線飛行
func launch(from: Vector2, to: Vector2, color: Color, duration: float = 0.35, spread: float = 0.0) -> void:
	is_available = false
	_orbiting = false
	duration = duration / speed_divisor  # 速度加快
	_color = color
	_trail.clear()
	_head_pos = from
	_flying = true
	_bursting = false
	visible = true

	if _particles == null:
		_build_particles()
	_apply_particle_size()
	_apply_particle_color(color)
	_particles.emitting = true

	# 中止殘留 tween
	if _tween and _tween.is_valid():
		_tween.kill()

	# Bezier 弧線計算
	var dir: Vector2 = to - from
	var perp := Vector2(-dir.y, dir.x).normalized()
	var side: float = spread
	var arc_height: float = dir.length() * 0.35
	var control: Vector2 = (from + to) * 0.5 + perp * arc_height * side + Vector2(0, -arc_height * 0.5)

	_tween = create_tween()
	_tween.tween_method(func(t: float) -> void:
		var inv: float = 1.0 - t
		_head_pos = inv * inv * from + 2.0 * inv * t * control + t * t * to
		# 記錄拖尾點
		_trail.push_front(_head_pos)
		if _trail.size() > TRAIL_LENGTH:
			_trail.resize(TRAIL_LENGTH)
		# 更新粒子發射位置
		if _particles:
			_particles.global_position = _head_pos
		queue_redraw()
	, 0.0, 1.0, duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	_tween.tween_callback(_on_flight_done)


func launch_power_attack(from: Vector2, to: Vector2, color: Color, duration: float = 0.35, spread: float = 0.0, power_level: int = 1) -> void:
	is_available = false
	_orbiting = false
	duration = duration / speed_divisor
	_color = color
	_trail.clear()
	_head_pos = from
	_flying = true
	_bursting = false
	visible = true
	modulate.a = 1.0

	if _particles == null:
		_build_particles()
	_apply_particle_size()
	_apply_particle_color(color)
	_particles.emitting = true

	if _tween and _tween.is_valid():
		_tween.kill()

	var dir: Vector2 = to - from
	var dist: float = dir.length()
	var dir_n: Vector2 = dir.normalized() if dist > 0.001 else Vector2.RIGHT
	var perp := Vector2(-dir_n.y, dir_n.x)
	var level: int = clampi(power_level, 1, 2)
	var pullback_dist: float = minf(maxf(dist * (0.62 if level == 1 else 0.95), 140.0 if level == 1 else 210.0), 410.0 if level == 1 else 620.0)
	var arc_height: float = maxf(dist * (0.46 if level == 1 else 0.50), 105.0 if level == 1 else 120.0)
	var approach_dist: float = minf(maxf(dist * (0.36 if level == 1 else 0.46), 105.0 if level == 1 else 140.0), 260.0 if level == 1 else 340.0)
	var side: float = spread * (0.45 if level == 1 else 0.75)
	var pull_control: Vector2 = from - dir_n * pullback_dist + perp * pullback_dist * side + Vector2(0.0, -arc_height * (0.38 if level == 1 else 0.16))
	var approach_control: Vector2 = to - dir_n * approach_dist
	var time_power: float = 2.15 if level == 1 else 2.65

	_tween = create_tween()
	_tween.tween_method(func(t: float) -> void:
		var curve_t: float = pow(t, time_power)
		var inv: float = 1.0 - curve_t
		_set_head_position(
			inv * inv * inv * from
			+ 3.0 * inv * inv * curve_t * pull_control
			+ 3.0 * inv * curve_t * curve_t * approach_control
			+ curve_t * curve_t * curve_t * to
		)
	, 0.0, 1.0, duration).set_trans(Tween.TRANS_LINEAR)
	_tween.tween_callback(_on_flight_done)


func _set_head_position(pos: Vector2) -> void:
	_head_pos = pos
	_trail.push_front(_head_pos)
	if _trail.size() > TRAIL_LENGTH:
		_trail.resize(TRAIL_LENGTH)
	if _particles:
		_particles.global_position = _head_pos
	queue_redraw()


func start_orbit(center_global: Vector2, radius: float, color: Color, start_angle: float = 0.0, speed: float = 2.6, visual_size: float = 0.72) -> void:
	is_available = false
	_orbiting = true
	_flying = true
	_bursting = false
	_color = color
	_orbit_center_global = center_global
	_orbit_radius = radius
	_orbit_angle = start_angle
	_orbit_speed = speed
	_trail.clear()
	top_level = true
	global_position = Vector2.ZERO
	visible = true
	modulate.a = 1.0
	set_visual_size_multiplier(visual_size)
	if _particles == null:
		_build_particles()
	_apply_particle_size()
	_apply_particle_color(color)
	_particles.emitting = true
	set_process(true)
	for i in TRAIL_LENGTH:
		var tail_angle: float = start_angle - float(i) * 0.035
		_set_head_position(_orbit_center_global + Vector2(cos(tail_angle), sin(tail_angle)) * _orbit_radius)


func set_orbit_center(center_global: Vector2) -> void:
	_orbit_center_global = center_global


func scatter_from_orbit(direction: Vector2, distance: float = 280.0, duration: float = 0.55) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_orbiting = false
	_flying = true
	is_available = false
	visible = true
	var dir: Vector2 = direction.normalized() if direction.length_squared() > 0.001 else Vector2.RIGHT
	var start_pos: Vector2 = _head_pos
	var end_pos: Vector2 = start_pos + dir * distance
	if _particles:
		_particles.emitting = true
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(func(t: float) -> void:
		_set_head_position(start_pos.lerp(end_pos, t))
	, 0.0, 1.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(self, "modulate:a", 0.0, duration).set_ease(Tween.EASE_IN)
	_tween.chain().tween_callback(func() -> void:
		if _particles:
			_particles.emitting = false
		visible = false
		modulate.a = 1.0
		_trail.clear()
		_flying = false
		is_available = true
		released.emit()
	)


func _process(delta: float) -> void:
	if not _orbiting:
		return
	_orbit_angle = fmod(_orbit_angle + _orbit_speed * delta, TAU)
	_set_head_position(_orbit_center_global + Vector2(cos(_orbit_angle), sin(_orbit_angle)) * _orbit_radius)


func launch_guest_join(from: Vector2, to: Vector2, color: Color, duration: float = 1.0, spread: float = 0.35) -> void:
	is_available = false
	_orbiting = false
	duration = duration / speed_divisor
	_color = color
	_trail.clear()
	_head_pos = from
	_flying = true
	_bursting = false
	_burst_alpha = 0.0
	modulate.a = 1.0
	visible = true

	if _particles == null:
		_build_particles()
	_apply_particle_size()
	_apply_particle_color(color)
	_particles.emitting = true

	if _tween and _tween.is_valid():
		_tween.kill()

	var dir: Vector2 = to - from
	var dist: float = dir.length()
	var dir_n: Vector2 = dir.normalized() if dist > 0.001 else Vector2.RIGHT
	var perp := Vector2(-dir_n.y, dir_n.x)
	var side: float = spread
	var pullback_dist: float = minf(maxf(dist * 0.14, 28.0), 86.0)
	var backswing: Vector2 = from - dir_n * pullback_dist + perp * pullback_dist * 0.35 * side
	var arc_height: float = maxf(dist * 0.32, 72.0)
	var control: Vector2 = (backswing + to) * 0.5 + perp * arc_height * 0.28 * side + Vector2(0.0, -arc_height)

	_tween = create_tween()
	_tween.tween_method(func(t: float) -> void:
		_set_head_position(from.lerp(backswing, t))
	, 0.0, 1.0, duration * 0.22).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	_tween.tween_method(func(t: float) -> void:
		var inv: float = 1.0 - t
		_set_head_position(inv * inv * backswing + 2.0 * inv * t * control + t * t * to)
	, 0.0, 1.0, duration * 0.78).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	_tween.tween_callback(_on_guest_join_arrived)


## 飛行結束
func _on_flight_done() -> void:
	_flying = false
	if _particles:
		_particles.emitting = false
	deduct_hp.emit()
	# 拖尾淡出
	var fade_tw := create_tween()
	fade_tw.tween_method(func(t: float) -> void:
		modulate.a = 1.0 - t
		queue_redraw()
	, 0.0, 1.0, 0.2)
	fade_tw.tween_callback(func() -> void:
		visible = false
		modulate.a = 1.0
		_trail.clear()
		is_available = true
		released.emit()
	)


func _on_guest_join_arrived() -> void:
	_flying = false
	_bursting = true
	_burst_pos = _head_pos
	_burst_scale = 0.75
	_burst_alpha = 1.0
	if _particles:
		_particles.emitting = false
	deduct_hp.emit()

	var burst_tw := create_tween()
	burst_tw.set_parallel(true)
	burst_tw.tween_method(func(v: float) -> void:
		_burst_scale = v
		queue_redraw()
	, 0.75, 3.2, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	burst_tw.tween_method(func(v: float) -> void:
		_burst_alpha = v
		modulate.a = v
		queue_redraw()
	, 1.0, 0.0, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	burst_tw.chain().tween_callback(func() -> void:
		visible = false
		modulate.a = 1.0
		_bursting = false
		_burst_alpha = 0.0
		_trail.clear()
		is_available = true
		released.emit()
	)


## 強制回收
func force_release() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_orbiting = false
	_flying = false
	_bursting = false
	if _particles:
		_particles.emitting = false
	visible = false
	_trail.clear()
	is_available = true


func _is_valid_trail_point(point: Vector2) -> bool:
	return not is_nan(point.x) and not is_nan(point.y) and not is_inf(point.x) and not is_inf(point.y)


func _is_valid_trail_quad(verts: PackedVector2Array) -> bool:
	if verts.size() != 4:
		return false
	var area: float = 0.0
	for i in verts.size():
		var current: Vector2 = verts[i]
		var next: Vector2 = verts[(i + 1) % verts.size()]
		if not _is_valid_trail_point(current):
			return false
		if current.distance_squared_to(next) < 0.01:
			return false
		area += current.cross(next)
	if abs(area) < 0.5:
		return false
	return Geometry2D.triangulate_polygon(verts).size() >= 3


func _draw() -> void:
	if _trail.size() < 2:
		return
	var trail_points: Array[Vector2] = []
	for point in _trail:
		if not _is_valid_trail_point(point):
			continue
		if trail_points.is_empty() or trail_points[trail_points.size() - 1].distance_squared_to(point) > 0.25:
			trail_points.append(point)
	if trail_points.size() < 2:
		return

	# ── 寬光帶拖尾（多層漸變 polygon strip）──
	var count: int = trail_points.size()
	var visual_mult: float = _visual_size_multiplier

	# 計算每個點的法線方向（用於展開寬度）
	var normals: Array[Vector2] = []
	for i in count:
		var tangent: Vector2
		if i == 0 and count > 1:
			tangent = (trail_points[0] - trail_points[1]).normalized()
		elif i == count - 1 and count > 1:
			tangent = (trail_points[i - 1] - trail_points[i]).normalized()
		else:
			tangent = (trail_points[i - 1] - trail_points[i + 1]).normalized()
		normals.append(Vector2(-tangent.y, tangent.x))

	# 三層拖尾：外部柔光 → 中層元素色 → 內層白芯
	var layers: Array[Dictionary] = [
		{"width_mult": 1.0, "color_func": "_trail_outer_color", "alpha_mult": 0.18},
		{"width_mult": 0.55, "color_func": "_trail_mid_color", "alpha_mult": 0.7},
		{"width_mult": 0.22, "color_func": "_trail_core_color", "alpha_mult": 0.85},
	]

	for layer in layers:
		var w_mult: float = layer.width_mult
		var a_mult: float = layer.alpha_mult
		var is_core: bool = w_mult < 0.3
		# 每層用三角形條帶繪製
		for i in range(count - 1):
			var t0: float = float(i) / float(count - 1)
			var t1: float = float(i + 1) / float(count - 1)
			var alpha0: float = pow(1.0 - t0, 2.2) * a_mult
			var alpha1: float = pow(1.0 - t1, 2.2) * a_mult
			var w0: float = lerpf(TRAIL_WIDTH_HEAD, TRAIL_WIDTH_TAIL, pow(t0, 0.6)) * w_mult * visual_mult
			var w1: float = lerpf(TRAIL_WIDTH_HEAD, TRAIL_WIDTH_TAIL, pow(t1, 0.6)) * w_mult * visual_mult
			var p0: Vector2 = trail_points[i] - global_position
			var p1: Vector2 = trail_points[i + 1] - global_position
			if p0.distance_squared_to(p1) < 0.25:
				continue
			var n0: Vector2 = normals[i]
			var n1: Vector2 = normals[i + 1]

			var c0: Color
			var c1: Color
			if is_core:
				var wb0: float = pow(1.0 - t0, 1.5)
				var wb1: float = pow(1.0 - t1, 1.5)
				c0 = Color(1, 1, 1, alpha0 * wb0)
				c1 = Color(1, 1, 1, alpha1 * wb1)
			else:
				c0 = Color(_color.r, _color.g, _color.b, alpha0)
				c1 = Color(_color.r, _color.g, _color.b, alpha1)

			var verts: PackedVector2Array = [
				p0 + n0 * w0, p0 - n0 * w0,
				p1 - n1 * w1, p1 + n1 * w1,
			]
			if not _is_valid_trail_quad(verts):
				continue
			var colors: PackedColorArray = [c0, c0, c1, c1]
			draw_polygon(verts, colors)

	# ── 球頭（多層發光 + 十字光芒）──
	if _flying and trail_points.size() > 0:
		var head_local: Vector2 = trail_points[0] - global_position

		# 最外層柔暈
		draw_circle(head_local, HEAD_GLOW_RADIUS * visual_mult, Color(_color.r, _color.g, _color.b, 0.12))
		# 中層暈
		draw_circle(head_local, HEAD_GLOW_RADIUS * 0.6 * visual_mult, Color(_color.r, _color.g, _color.b, 0.25))
		# 元素色核心
		draw_circle(head_local, HEAD_RADIUS * 1.4 * visual_mult, _color)
		# 白色核心
		draw_circle(head_local, HEAD_RADIUS * visual_mult, Color(1, 1, 1, 0.92))
		# 最亮高光
		draw_circle(head_local, HEAD_RADIUS * 0.45 * visual_mult, Color(1, 1, 1, 1.0))

		# 十字光芒（lens flare spikes）
		for fi in FLARE_COUNT:
			var angle: float = (PI / float(FLARE_COUNT)) * float(fi)
			var dir_f := Vector2(cos(angle), sin(angle))
			var perp_f := Vector2(-dir_f.y, dir_f.x)
			var flare_length: float = FLARE_LENGTH * visual_mult
			var flare_width: float = FLARE_WIDTH * visual_mult
			var tip_a: Vector2 = head_local + dir_f * flare_length
			var tip_b: Vector2 = head_local - dir_f * flare_length
			var side_a: Vector2 = head_local + perp_f * flare_width
			var side_b: Vector2 = head_local - perp_f * flare_width
			var flare_color := Color(1, 1, 1, 0.55)
			var tip_color := Color(1, 1, 1, 0.0)
			# 兩個三角形組成一道光芒
			draw_polygon([head_local, side_a, tip_a], [flare_color, flare_color, tip_color])
			draw_polygon([head_local, side_b, tip_a], [flare_color, flare_color, tip_color])
			draw_polygon([head_local, side_a, tip_b], [flare_color, flare_color, tip_color])
			draw_polygon([head_local, side_b, tip_b], [flare_color, flare_color, tip_color])

	_draw_guest_join_burst(visual_mult)


func _draw_guest_join_burst(visual_mult: float) -> void:
	if not _bursting:
		return
	var burst_local: Vector2 = _burst_pos - global_position
	var a: float = _burst_alpha
	var s: float = _burst_scale * visual_mult
	draw_circle(burst_local, HEAD_GLOW_RADIUS * 0.95 * s, Color(_color.r, _color.g, _color.b, 0.18 * a))
	draw_circle(burst_local, HEAD_GLOW_RADIUS * 0.55 * s, Color(1, 1, 1, 0.28 * a))
	draw_arc(burst_local, HEAD_GLOW_RADIUS * 0.75 * s, 0.0, TAU, 40, Color(1, 1, 1, 0.65 * a), 3.0 * visual_mult, true)
	for fi in 8:
		var angle: float = TAU * float(fi) / 8.0
		var dir_f := Vector2(cos(angle), sin(angle))
		var inner: Vector2 = burst_local + dir_f * HEAD_RADIUS * 1.5 * s
		var outer: Vector2 = burst_local + dir_f * HEAD_GLOW_RADIUS * 1.15 * s
		draw_line(inner, outer, Color(1, 1, 1, 0.55 * a), 2.0 * visual_mult)


## 建立 GPUParticles2D 火花粒子
func _build_particles() -> void:
	_particles = GPUParticles2D.new()
	_particles.amount = SPARKLE_AMOUNT
	_particles.lifetime = 0.4
	_particles.explosiveness = 0.0
	_particles.emitting = false
	_particles.top_level = true  # 使用全域座標
	_particles.z_index = -1      # 繪製在球頭下方

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 0, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 20.0
	mat.initial_velocity_max = 60.0
	mat.gravity = Vector3(0, 40, 0)
	mat.scale_min = PARTICLE_SCALE_MIN
	mat.scale_max = PARTICLE_SCALE_MAX
	mat.damping_min = 20.0
	mat.damping_max = 40.0

	# alpha 漸隱曲線
	var alpha_curve := CurveTexture.new()
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(0.5, 0.6))
	curve.add_point(Vector2(1.0, 0.0))
	alpha_curve.curve = curve
	mat.alpha_curve = alpha_curve

	# 尺寸從小到更小
	var scale_curve := CurveTexture.new()
	var s_curve := Curve.new()
	s_curve.add_point(Vector2(0.0, 1.0))
	s_curve.add_point(Vector2(1.0, 0.2))
	scale_curve.curve = s_curve
	mat.scale_curve = scale_curve

	_particles.process_material = mat

	# 徑向漸層紋理：白色中心 → 透明外緣
	var tex_size := 16
	var img := Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	var center := Vector2(float(tex_size - 1) / 2.0, float(tex_size - 1) / 2.0)
	var max_dist: float = float(tex_size) / 2.0
	for y in tex_size:
		for x in tex_size:
			var dist: float = Vector2(x, y).distance_to(center)
			var t: float = clampf(dist / max_dist, 0.0, 1.0)
			var a: float = pow(1.0 - t, 1.5)
			# 中心白 → 外圈透明（顏色由 color_ramp 控制）
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_particles.texture = ImageTexture.create_from_image(img)

	add_child(_particles)
	_apply_particle_size()


func _apply_particle_size() -> void:
	if _particles == null or _particles.process_material == null:
		return
	var mat: ParticleProcessMaterial = _particles.process_material as ParticleProcessMaterial
	if mat == null:
		return
	mat.scale_min = PARTICLE_SCALE_MIN * _visual_size_multiplier
	mat.scale_max = PARTICLE_SCALE_MAX * _visual_size_multiplier


## 套用顏色到粒子材質
func _apply_particle_color(color: Color) -> void:
	if _particles == null or _particles.process_material == null:
		return
	var mat: ParticleProcessMaterial = _particles.process_material as ParticleProcessMaterial
	# 顏色漸層：白色中心 → 元素色外圍（隨壽命漸變）
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))           # 生成時白色
	grad.set_color(1, Color(color.r, color.g, color.b, 0.6))  # 消失時元素色
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex
	mat.color = Color(1, 1, 1, 1)  # 基礎色白色，讓 color_ramp 控制漸變
