## BulletProjectile（子彈彈道）— 浣熊攻擊用的動畫子彈。
## 使用 bullet.png 精靈圖表：24 列 × 15 行。
## 浣熊的子彈：第 8 行（0-indexed 第 7 行），第 1–8 欄（幀 168..175）。
## 從角色卡片飛向敎人，使用貝茲爲弧形軌跡，到達時發出 deduct_hp 信號。
extends Node2D

const BULLET_TEXTURE := preload("res://assets/bullet.png")  # 子彈精靈圖表
const HFRAMES := 24           # 水平幀數
const VFRAMES := 15           # 垂直幀數
const ROW := 7                # 使用的行（0-indexed）
const FRAME_START := ROW * HFRAMES  # 起始幀 168
const FRAME_END := FRAME_START + 7  # 結束幀 175（8 幀）
const FLIGHT_DURATION := 0.4  # 飛行時長（秒）

signal deduct_hp  # 命中時發出扣血信號

var _sprite: Sprite2D  # 子彈精靈圖


## 發射子彈：從 from 到 to，沿貝茲爲曲線飛行並播放幀動畫
func play(from: Vector2, to: Vector2) -> void:
	position = from

	_sprite = Sprite2D.new()
	_sprite.texture = BULLET_TEXTURE
	_sprite.hframes = HFRAMES
	_sprite.vframes = VFRAMES
	_sprite.frame = FRAME_START
	_sprite.scale = Vector2(3, 3)
	add_child(_sprite)

	# 旋轉精靈圖面向飛行方向
	var angle := from.angle_to_point(to)
	_sprite.rotation = angle

	# 貝茲爲弧形：控制點在中點上方
	var mid := (from + to) * 0.5
	var control := Vector2(mid.x, min(from.y, to.y) - 80.0)

	var tween := create_tween()
	tween.set_parallel(true)

	# 沿貝茲爲曲線移動
	tween.tween_method(func(t: float) -> void:
		var inv := 1.0 - t
		position = inv * inv * from + 2.0 * inv * t * control + t * t * to
		# 更新旋轉以跟隨曲線
		var next_t := minf(t + 0.01, 1.0)
		var inv2 := 1.0 - next_t
		var next_pos := inv2 * inv2 * from + 2.0 * inv2 * next_t * control + next_t * next_t * to
		_sprite.rotation = position.angle_to_point(next_pos)
	, 0.0, 1.0, FLIGHT_DURATION)

	# 播放幀動畫
	tween.tween_method(func(f: float) -> void:
		_sprite.frame = FRAME_START + int(f)
	, 0.0, float(FRAME_END - FRAME_START), FLIGHT_DURATION)

	tween.set_parallel(false)

	await tween.finished
	deduct_hp.emit()
	queue_free()
