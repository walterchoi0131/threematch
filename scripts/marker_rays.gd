## MarkerRays — "!" 標記後方的黃色放射光錐動畫。
## 6 條從中心向外擴張的窄三角形 cone，alpha 隨擴張遞減；循環 + 緩慢自轉。
@tool
class_name MarkerRays
extends Node2D

const RAY_COUNT: int = 6
const RAY_HALF_ANGLE: float = 0.18  # 每條 cone 的一半張角（弧度）
const PERIOD: float = 0.95          # 一次脈動週期（秒）
const ROTATION_SPEED: float = 0.55  # rad/s
const COLOR: Color = Color(1.0, 0.93, 0.20, 1.0)

## 光錐的最大半徑（外緣）
@export var radius: float = 28.0:
	set(value):
		radius = value
		queue_redraw()

## 光錐的最小半徑（內緣，從 marker 中心外推一段，避免重疊文字）
@export var inner_radius: float = 6.0:
	set(value):
		inner_radius = value
		queue_redraw()

var _t: float = 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	rotation += delta * ROTATION_SPEED
	queue_redraw()


func _draw() -> void:
	# 取脈動相位（0..1 線性增長後重置），讓光錐外緣由內向外掃並淡出
	var phase: float = fmod(_t, PERIOD) / PERIOD
	var current_outer: float = lerp(inner_radius, radius, phase)
	var current_inner: float = inner_radius
	var alpha: float = clamp(1.0 - phase, 0.0, 1.0) * 0.85

	for i in RAY_COUNT:
		var ang: float = TAU * float(i) / float(RAY_COUNT)
		var a0: float = ang - RAY_HALF_ANGLE
		var a1: float = ang + RAY_HALF_ANGLE
		var p0 := Vector2(cos(a0), sin(a0)) * current_inner
		var p1 := Vector2(cos(a1), sin(a1)) * current_inner
		var p2 := Vector2(cos(a1), sin(a1)) * current_outer
		var p3 := Vector2(cos(a0), sin(a0)) * current_outer
		var pts := PackedVector2Array([p0, p1, p2, p3])
		var col: Color = COLOR
		col.a = alpha
		var cols := PackedColorArray([col, col, col, col])
		draw_polygon(pts, cols)
