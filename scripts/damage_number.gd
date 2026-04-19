## DamageNumber（傷害數字）— 浮動傷害數字，帶彈跳動畫和黑色描邊。
## 用法：
##   var dn = DamageNumber.new()
##   parent.add_child(dn)
##   dn.show_number(全局座標, 數值, 顏色)
extends Node2D


## 顯示傷害數字（彈跳上升 + 淡出）
func show_number(pos: Vector2, amount: int, color: Color, random_x_offset: bool = false, is_super: bool = false) -> void:
	if random_x_offset:
		pos.x += randf_range(-40.0, 40.0)
	global_position = pos

	var label := Label.new()
	label.text = str(amount) + ("!!" if is_super else "")
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Russo One 字型（與血條 HP 標籤一致）
	var font: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
	label.add_theme_font_override("font", font)

	# 字體大小 — 克制效果時更大
	var font_size: int = 38 if is_super else 28
	label.add_theme_font_size_override("font_size", font_size)

	# 字體顏色
	label.add_theme_color_override("font_color", color)

	# 黑色描邊
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color.BLACK)

	# 陰影
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)

	# 將標籤置中於節點
	label.position = Vector2(-40, -20)
	label.size = Vector2(80, 40)

	add_child(label)

	# 彈跳動畫：往上彈起 → 回落 → 小彈跳 → 定位 → 上浮淡出
	var tween := create_tween()
	# 第1階：快速上彈
	tween.tween_property(label, "position:y", -60.0, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# 第2階：回落
	tween.tween_property(label, "position:y", -30.0, 0.12).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# 第3階：小彈跳
	tween.tween_property(label, "position:y", -45.0, 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# 第4階：定位
	tween.tween_property(label, "position:y", -35.0, 0.08).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# 第5階：上浮淡出
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", -70.0, 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)


## 顯示任意文字（與 show_number 相同動畫，供掉落文字等使用）
func show_text(pos: Vector2, text: String, color: Color) -> void:
	global_position = pos

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var font: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)

	label.position = Vector2(-60, -20)
	label.size = Vector2(120, 40)
	add_child(label)

	var tween := create_tween()
	tween.tween_property(label, "position:y", -55.0, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(label, "position:y", -30.0, 0.12).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(label, "position:y", -42.0, 0.08).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_interval(0.3)
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", -75.0, 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.set_parallel(false)
	tween.tween_callback(queue_free)
