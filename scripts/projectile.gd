## Projectile（拋物線彈道）— 程式化建立並加入 FXLayer。
## 從敎人射向玩家血條，使用貝茲爲曲線弧形軌跡。
## 到達後執行 on_hit 回呼。
extends Node2D

var _p0: Vector2        # 起點
var _p1: Vector2        # 貝茲爲控制點（弧形頂點）
var _p2: Vector2        # 終點
var _color: Color       # 彈道顏色
var _on_hit: Callable   # 命中回呼


## 發射彈道：從 from 到 to，到達後呼叫 on_hit
func launch(from: Vector2, to: Vector2, color: Color, on_hit: Callable) -> void:
	_p0 = from
	_p2 = to
	_p1 = Vector2((from.x + to.x) * 0.5, min(from.y, to.y) - 120.0)  # 中點上方 120px
	_color = color
	_on_hit = on_hit
	position = from
	queue_redraw()

	var tween := create_tween()
	tween.tween_method(_step, 0.0, 1.0, 0.42)
	await tween.finished
	_on_hit.call()
	queue_free()


## 貝茲爲插值移動
func _step(t: float) -> void:
	# 二次貝茲爲：B(t) = (1-t)²P0 + 2(1-t)t·P1 + t²P2
	var inv: float = 1.0 - t
	position = inv * inv * _p0 + 2.0 * inv * t * _p1 + t * t * _p2
	queue_redraw()


## 繪製彈道外觀（光暈 + 核心球體 + 高光點）
func _draw() -> void:
	# 柔和光暈
	draw_circle(Vector2.ZERO, 14.0, Color(_color.r, _color.g, _color.b, 0.28))
	# 核心球體
	draw_circle(Vector2.ZERO, 9.0, _color)
	# 高光點
	draw_circle(Vector2(-3.0, -3.0), 3.5, Color(1, 1, 1, 0.6))
