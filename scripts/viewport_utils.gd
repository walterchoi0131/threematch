extends Node

## Centralized viewport / safe-area helpers for portrait mobile layout.
## Registered as autoload "ViewportUtils".

const BASE_SIZE: Vector2 = Vector2(720, 1280)

signal viewport_changed(size: Vector2)

var _last_size: Vector2 = BASE_SIZE


func _ready() -> void:
	# Single connection point for all subscribers; avoids each scene
	# attaching its own size_changed handler.
	get_tree().root.size_changed.connect(_on_root_size_changed)
	_last_size = get_size()


func _on_root_size_changed() -> void:
	var s: Vector2 = get_size()
	if s == _last_size:
		return
	_last_size = s
	viewport_changed.emit(s)


## Current visible viewport size (post-stretch, in base units).
func get_size() -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return BASE_SIZE
	return vp.get_visible_rect().size


## Returns the safe area in viewport-local pixels.
## Falls back to the full viewport rect on platforms without a real safe area.
func get_safe_area() -> Rect2:
	var size: Vector2 = get_size()
	var full := Rect2(Vector2.ZERO, size)
	if not DisplayServer.is_touchscreen_available():
		return full
	# DisplayServer.get_display_safe_area returns physical pixels in
	# screen coordinates; convert to viewport-local proportionally.
	var screen_size: Vector2i = DisplayServer.window_get_size()
	if screen_size.x <= 0 or screen_size.y <= 0:
		return full
	var sa: Rect2i = DisplayServer.get_display_safe_area()
	var sx: float = size.x / float(screen_size.x)
	var sy: float = size.y / float(screen_size.y)
	return Rect2(
		Vector2(sa.position.x * sx, sa.position.y * sy),
		Vector2(sa.size.x * sx, sa.size.y * sy)
	)


## Returns insets in (top, right, bottom, left) order, in viewport-local pixels.
## All zero on desktop / non-touch platforms.
func get_safe_insets() -> Vector4:
	var size: Vector2 = get_size()
	var sa: Rect2 = get_safe_area()
	var top: float = max(0.0, sa.position.y)
	var left: float = max(0.0, sa.position.x)
	var right: float = max(0.0, size.x - (sa.position.x + sa.size.x))
	var bottom: float = max(0.0, size.y - (sa.position.y + sa.size.y))
	return Vector4(top, right, bottom, left)
