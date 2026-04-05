## SlashEffect（斬擊特效）— 在敎人位置播放的火焰斬擊動畫。
## 精靈圖表：6 列 × 3 行 = 18 幀，由左至右、由上至下播放。
extends Node2D

const SLASH_TEXTURE := preload("res://assets/slash.png")  # 斬擊精靈圖表
const DURATION    := 0.5   # 動畫總時長（秒）
const DEDUCT_RATIO := 0.5  # 在動畫這個比例處觸發扣血
const HFRAMES     := 6     # 水平幀數
const VFRAMES     := 3     # 垂直幀數
const TOTAL_FRAMES := HFRAMES * VFRAMES  # 總幀數 18

signal deduct_hp  # 扣血信號


## 在指定位置播放斬擊動畫
func play(at_position: Vector2) -> void:
	position = at_position

	var sprite := Sprite2D.new()
	sprite.texture = SLASH_TEXTURE
	sprite.hframes = HFRAMES
	sprite.vframes  = VFRAMES
	sprite.frame    = 0
	sprite.scale    = Vector2(0.25, 0.25)
	sprite.position = Vector2(5, 40)
	sprite.rotation_degrees = 190.0
	add_child(sprite)

	# 使用 tween_method 逐幀推進
	var tween := create_tween()
	tween.tween_method(
		func(f: float) -> void: sprite.frame = int(f),
		0.0, float(TOTAL_FRAMES - 1), DURATION
	)

	# 在動畫進行到 DEDUCT_RATIO 時發出扣血信號
	get_tree().create_timer(DURATION * DEDUCT_RATIO).timeout.connect(
		func() -> void: deduct_hp.emit()
	)

	await tween.finished
	queue_free()
