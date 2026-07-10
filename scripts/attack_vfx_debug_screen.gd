extends Control

const TrailProjectileScript := preload("res://scripts/trail_projectile.gd")
const ORIGINAL_LEVEL := 0
const MID_LEVEL := 1
const MAX_LEVEL := 2
const LEVELS := [ORIGINAL_LEVEL, MID_LEVEL, MAX_LEVEL]

const ORIGINAL_MOTION_ITEMS := [
	{"key": "duration", "label": "Duration 持續時間", "min": 0.05, "max": 3.0, "step": 0.01, "decimals": 2, "suffix": " s"},
	{"key": "arc_angle_deg", "label": "Arc angle 弧線角度", "min": -180.0, "max": 180.0, "step": 1.0, "decimals": 0, "suffix": " deg"},
	{"key": "arc_height_ratio", "label": "Arc height ratio 弧高比例", "min": 0.0, "max": 1.5, "step": 0.01, "decimals": 2},
	{"key": "arc_height_min", "label": "Arc height min 最小弧高", "min": 0.0, "max": 360.0, "step": 1.0, "decimals": 0, "suffix": " px"},
	{"key": "normal_arc_factor", "label": "Arc influence 弧線影響", "min": 0.0, "max": 1.5, "step": 0.01, "decimals": 2},
	{"key": "spread", "label": "Side spread 側向偏移", "min": -2.0, "max": 2.0, "step": 0.01, "decimals": 2},
	{"key": "side_factor", "label": "Side strength 側向強度", "min": 0.0, "max": 2.0, "step": 0.01, "decimals": 2},
	{"key": "time_power", "label": "Time curve 時間曲線", "min": 0.2, "max": 5.0, "step": 0.01, "decimals": 2},
]

const POWER_MOTION_ITEMS := [
	{"key": "duration", "label": "Duration 持續時間", "min": 0.15, "max": 3.0, "step": 0.01, "decimals": 2, "suffix": " s"},
	{"key": "arc_angle_deg", "label": "Arc angle 弧線角度", "min": -180.0, "max": 180.0, "step": 1.0, "decimals": 0, "suffix": " deg"},
	{"key": "arc_height_ratio", "label": "Arc height ratio 弧高比例", "min": 0.0, "max": 1.5, "step": 0.01, "decimals": 2},
	{"key": "arc_height_min", "label": "Arc height min 最小弧高", "min": 0.0, "max": 360.0, "step": 1.0, "decimals": 0, "suffix": " px"},
	{"key": "pull_arc_factor", "label": "Arc influence 弧線影響", "min": 0.0, "max": 1.5, "step": 0.01, "decimals": 2},
	{"key": "spread", "label": "Side spread 側向偏移", "min": -2.0, "max": 2.0, "step": 0.01, "decimals": 2},
	{"key": "side_factor", "label": "Side strength 側向強度", "min": 0.0, "max": 2.0, "step": 0.01, "decimals": 2},
	{"key": "time_power", "label": "Time curve 時間曲線", "min": 0.2, "max": 5.0, "step": 0.01, "decimals": 2},
]

const CONTROL_POINT_ITEMS := [
	{"key": "pullback_ratio", "label": "Pullback ratio 回拉比例", "min": 0.0, "max": 2.0, "step": 0.01, "decimals": 2},
	{"key": "pullback_min", "label": "Pullback min 最小回拉", "min": 0.0, "max": 800.0, "step": 1.0, "decimals": 0, "suffix": " px"},
	{"key": "pullback_max", "label": "Pullback max 最大回拉", "min": 20.0, "max": 900.0, "step": 1.0, "decimals": 0, "suffix": " px"},
	{"key": "approach_ratio", "label": "Approach ratio 接近比例", "min": 0.0, "max": 1.5, "step": 0.01, "decimals": 2},
	{"key": "approach_min", "label": "Approach min 最小接近距離", "min": 0.0, "max": 500.0, "step": 1.0, "decimals": 0, "suffix": " px"},
	{"key": "approach_max", "label": "Approach max 最大接近距離", "min": 20.0, "max": 600.0, "step": 1.0, "decimals": 0, "suffix": " px"},
]

const TRAIL_ITEMS := [
	{"key": "visual_scale", "label": "Visual size 視覺尺寸", "min": 0.25, "max": 5.0, "step": 0.05, "decimals": 2},
	{"key": "trail_length", "label": "Trail points 拖尾點數", "min": 2.0, "max": 80.0, "step": 1.0, "decimals": 0},
	{"key": "trail_width_head", "label": "Trail head width 拖尾前端寬度", "min": 1.0, "max": 45.0, "step": 0.5, "decimals": 1, "suffix": " px"},
	{"key": "trail_width_tail", "label": "Trail tail width 拖尾末端寬度", "min": 0.2, "max": 12.0, "step": 0.1, "decimals": 1, "suffix": " px"},
	{"key": "head_radius", "label": "Head radius 彈頭半徑", "min": 1.0, "max": 18.0, "step": 0.5, "decimals": 1, "suffix": " px"},
	{"key": "head_glow_radius", "label": "Glow radius 光暈半徑", "min": 2.0, "max": 80.0, "step": 1.0, "decimals": 0, "suffix": " px"},
	{"key": "flare_count", "label": "Flare count 光芒數量", "min": 0.0, "max": 12.0, "step": 1.0, "decimals": 0},
	{"key": "flare_length", "label": "Flare length 光芒長度", "min": 0.0, "max": 70.0, "step": 1.0, "decimals": 0, "suffix": " px"},
	{"key": "flare_width", "label": "Flare width 光芒寬度", "min": 0.0, "max": 10.0, "step": 0.25, "decimals": 2, "suffix": " px"},
	{"key": "fade_duration", "label": "Hit fade 命中淡出", "min": 0.01, "max": 1.5, "step": 0.01, "decimals": 2, "suffix": " s"},
]

const PARTICLE_ITEMS := [
	{"key": "sparkle_amount", "label": "Spark amount 火花數量", "min": 1.0, "max": 96.0, "step": 1.0, "decimals": 0},
	{"key": "particle_lifetime", "label": "Particle life 粒子壽命", "min": 0.05, "max": 2.0, "step": 0.01, "decimals": 2, "suffix": " s"},
	{"key": "particle_velocity_min", "label": "Velocity min 最小速度", "min": 0.0, "max": 180.0, "step": 1.0, "decimals": 0},
	{"key": "particle_velocity_max", "label": "Velocity max 最大速度", "min": 0.0, "max": 260.0, "step": 1.0, "decimals": 0},
	{"key": "particle_gravity", "label": "Gravity 粒子重力", "min": -180.0, "max": 240.0, "step": 1.0, "decimals": 0},
	{"key": "particle_scale_min", "label": "Particle scale min 最小粒子尺寸", "min": 0.05, "max": 3.0, "step": 0.05, "decimals": 2},
	{"key": "particle_scale_max", "label": "Particle scale max 最大粒子尺寸", "min": 0.05, "max": 5.0, "step": 0.05, "decimals": 2},
]

const COLOR_ITEMS := [
	{"key": "color_hue", "label": "Hue 色相", "min": 0.0, "max": 360.0, "step": 1.0, "decimals": 0, "suffix": " deg"},
	{"key": "color_saturation", "label": "Saturation 飽和度", "min": 0.0, "max": 1.0, "step": 0.01, "decimals": 2},
	{"key": "color_value", "label": "Brightness 亮度", "min": 0.1, "max": 1.0, "step": 0.01, "decimals": 2},
]

var _profiles: Dictionary = {}
var _preview_roots: Dictionary = {}
var _preview_viewports: Dictionary = {}
var _preview_guides: Dictionary = {}
var _preview_markers: Dictionary = {}
var _trails: Dictionary = {}
var _sliders: Dictionary = {}
var _level_panels: Dictionary = {}
var _tab_buttons: Dictionary = {}
var _diff_outputs: Dictionary = {}
var _auto_replay: CheckButton = null
var _loop_timer: Timer = null
var _pending_replays: Dictionary = {}
var _replay_dispatch_queued := false
var _updating_controls := false
var _selected_level := ORIGINAL_LEVEL


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	for level in LEVELS:
		_profiles[level] = _make_default_profile(level)
		_sliders[level] = {}
	_build_ui()
	_loop_timer = Timer.new()
	_loop_timer.one_shot = true
	_loop_timer.timeout.connect(_on_loop_timer_timeout)
	add_child(_loop_timer)
	call_deferred("_replay_all")


func _make_default_profile(level: int) -> Dictionary:
	var profile: Dictionary
	if level == ORIGINAL_LEVEL:
		profile = TrailProjectileScript.get_normal_attack_defaults().duplicate(true)
	else:
		profile = TrailProjectileScript.get_power_attack_defaults(level).duplicate(true)
	profile["duration_divisor"] = 1.0
	profile["duration"] = 0.14 if level == ORIGINAL_LEVEL else (0.79 if level == MID_LEVEL else 1.25)
	profile["spread"] = 0.0
	profile["color_hue"] = 26.0
	profile["color_saturation"] = 0.88
	profile["color_value"] = 1.0
	return profile


func _parameter_groups_for_level(level: int) -> Array:
	var groups: Array = [{
		"title": "MOTION 動態",
		"items": ORIGINAL_MOTION_ITEMS if level == ORIGINAL_LEVEL else POWER_MOTION_ITEMS,
	}]
	if level != ORIGINAL_LEVEL:
		groups.append({"title": "CONTROL POINTS 控制點", "items": CONTROL_POINT_ITEMS})
	groups.append({"title": "TRAIL AND HEAD 拖尾與彈頭", "items": TRAIL_ITEMS})
	groups.append({"title": "PARTICLES 粒子", "items": PARTICLE_ITEMS})
	groups.append({"title": "COLOR 顏色", "items": COLOR_ITEMS})
	return groups


func _build_ui() -> void:
	var backdrop := ColorRect.new()
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.025, 0.03, 0.055, 0.985)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 7)
	margin.add_child(page)
	page.add_child(_build_header())
	page.add_child(_build_level_tabs())

	for level in LEVELS:
		var panel: Control = _build_level_panel(level)
		panel.visible = level == _selected_level
		_level_panels[level] = panel
		page.add_child(panel)


func _build_header() -> Control:
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 3)
	var title_row := HBoxContainer.new()
	title_row.custom_minimum_size.y = 34.0
	title_row.add_theme_constant_override("separation", 8)
	header.add_child(title_row)

	var back := Button.new()
	back.text = "Back 返回"
	back.custom_minimum_size = Vector2(76, 32)
	back.pressed.connect(queue_free)
	title_row.add_child(back)

	var title := Label.new()
	title.text = "ATTACK VFX DEBUG 攻擊特效除錯"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color.WHITE)
	title_row.add_child(title)

	var action_row := HBoxContainer.new()
	action_row.custom_minimum_size.y = 32.0
	action_row.add_theme_constant_override("separation", 6)
	header.add_child(action_row)

	_auto_replay = CheckButton.new()
	_auto_replay.text = "Auto replay 自動重播"
	_auto_replay.button_pressed = true
	_auto_replay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_auto_replay.toggled.connect(_on_auto_replay_toggled)
	action_row.add_child(_auto_replay)

	var replay := Button.new()
	replay.text = "Replay 重播"
	replay.custom_minimum_size = Vector2(84, 30)
	replay.pressed.connect(_replay_all)
	action_row.add_child(replay)

	var reset := Button.new()
	reset.text = "Reset all 全部重設"
	reset.custom_minimum_size = Vector2(108, 30)
	reset.pressed.connect(_reset_all)
	action_row.add_child(reset)
	return header


func _build_level_tabs() -> Control:
	var tabs := HBoxContainer.new()
	tabs.custom_minimum_size.y = 34.0
	tabs.add_theme_constant_override("separation", 4)
	var group := ButtonGroup.new()
	for level in LEVELS:
		var tab := Button.new()
		tab.text = _level_tab_text(level)
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = level == _selected_level
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.add_theme_font_size_override("font_size", 12)
		tab.pressed.connect(_select_level.bind(level))
		tabs.add_child(tab)
		_tab_buttons[level] = tab
	return tabs


func _build_level_panel(level: int) -> Control:
	var accent: Color = _level_accent(level)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _make_panel_style(accent))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	margin.add_child(column)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	column.add_child(title_row)
	var title := Label.new()
	title.text = _level_title(level)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", accent)
	title_row.add_child(title)
	var replay := Button.new()
	replay.text = "Play 播放"
	replay.custom_minimum_size = Vector2(72, 28)
	replay.add_theme_font_size_override("font_size", 11)
	replay.pressed.connect(_replay_level.bind(level))
	title_row.add_child(replay)

	column.add_child(_build_preview(level, accent))
	column.add_child(_build_diff_panel(level, accent))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 4)
	scroll.add_child(controls)
	for group_value in _parameter_groups_for_level(level):
		_add_parameter_group(controls, level, group_value as Dictionary, accent)
	return panel


func _build_preview(level: int, accent: Color) -> Control:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(0, 260)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.02, 0.04, 1.0)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.34)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", style)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(2, 2)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	_preview_viewports[level] = viewport

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.015, 0.02, 0.04, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport.add_child(bg)

	var guide := Line2D.new()
	guide.points = PackedVector2Array([Vector2.ZERO, Vector2.ZERO])
	guide.width = 2.0
	guide.default_color = Color(accent.r, accent.g, accent.b, 0.16)
	viewport.add_child(guide)
	_preview_guides[level] = guide
	var source_marker: Control = _make_preview_marker(Vector2.ZERO, "S", accent)
	var target_marker: Control = _make_preview_marker(Vector2.ZERO, "T", Color.WHITE)
	viewport.add_child(source_marker)
	viewport.add_child(target_marker)
	_preview_markers[level] = {"source": source_marker, "target": target_marker}

	var trail_root := Node2D.new()
	trail_root.z_index = 5
	viewport.add_child(trail_root)
	_preview_roots[level] = trail_root
	viewport.size_changed.connect(_update_preview_geometry.bind(level))
	call_deferred("_update_preview_geometry", level)
	return frame


func _build_diff_panel(level: int, accent: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var header := HBoxContainer.new()
	box.add_child(header)
	var label := Label.new()
	label.text = "Diff against current 與目前設定差異"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", accent)
	header.add_child(label)
	var copy := Button.new()
	copy.text = "Copy diff 複製差異"
	copy.custom_minimum_size = Vector2(112, 26)
	copy.add_theme_font_size_override("font_size", 10)
	copy.pressed.connect(_copy_diff.bind(level))
	header.add_child(copy)

	var output := TextEdit.new()
	output.custom_minimum_size.y = 76.0
	output.editable = false
	output.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	output.add_theme_font_size_override("font_size", 10)
	output.add_theme_color_override("font_color", Color(0.82, 0.86, 0.92))
	box.add_child(output)
	_diff_outputs[level] = output
	_update_diff(level)
	return box


func _make_preview_marker(center: Vector2, marker_text: String, color: Color) -> Control:
	var marker := PanelContainer.new()
	marker.position = center - Vector2(14, 14)
	marker.size = Vector2(28, 28)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r * 0.18, color.g * 0.18, color.b * 0.18, 0.9)
	style.border_color = color
	style.set_border_width_all(2)
	style.set_corner_radius_all(14)
	marker.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = marker_text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color.WHITE)
	marker.add_child(label)
	return marker


func _add_parameter_group(parent: VBoxContainer, level: int, group: Dictionary, accent: Color) -> void:
	var heading := Label.new()
	heading.text = str(group.get("title", ""))
	heading.add_theme_font_size_override("font_size", 10)
	heading.add_theme_color_override("font_color", Color(accent.r, accent.g, accent.b, 0.82))
	heading.add_theme_constant_override("outline_size", 2)
	parent.add_child(heading)
	for spec_value in group.get("items", []):
		_add_parameter_slider(parent, level, spec_value as Dictionary)


func _add_parameter_slider(parent: VBoxContainer, level: int, spec: Dictionary) -> void:
	var key: String = str(spec.get("key", ""))
	var decimals: int = int(spec.get("decimals", 2))
	var suffix: String = str(spec.get("suffix", ""))
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 0)
	parent.add_child(block)

	var label_row := HBoxContainer.new()
	block.add_child(label_row)
	var name_label := Label.new()
	name_label.text = str(spec.get("label", key))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.tooltip_text = name_label.text
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	label_row.add_child(name_label)
	var value_label := Label.new()
	value_label.custom_minimum_size.x = 72.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_font_size_override("font_size", 11)
	value_label.add_theme_color_override("font_color", Color.WHITE)
	label_row.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = float(spec.get("min", 0.0))
	slider.max_value = float(spec.get("max", 1.0))
	slider.step = float(spec.get("step", 0.01))
	slider.value = float((_profiles[level] as Dictionary).get(key, slider.min_value))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_parameter_changed.bind(level, key, value_label, decimals, suffix))
	block.add_child(slider)
	value_label.text = _format_value(slider.value, decimals, suffix)
	var level_sliders: Dictionary = _sliders[level]
	level_sliders[key] = slider
	_sliders[level] = level_sliders


func _on_parameter_changed(value: float, level: int, key: String, value_label: Label, decimals: int, suffix: String) -> void:
	value_label.text = _format_value(value, decimals, suffix)
	var profile: Dictionary = _profiles[level]
	profile[key] = value
	_profiles[level] = profile
	_update_diff(level)
	if not _updating_controls:
		_queue_replay(level)


func _format_value(value: float, decimals: int, suffix: String) -> String:
	return "%.*f%s" % [decimals, value, suffix]


func _select_level(level: int) -> void:
	_selected_level = level
	for candidate in LEVELS:
		var panel: Control = _level_panels.get(candidate, null) as Control
		if panel != null:
			panel.visible = candidate == level
	_replay_all()


func _queue_replay(level: int) -> void:
	_pending_replays[level] = true
	if _replay_dispatch_queued:
		return
	_replay_dispatch_queued = true
	await get_tree().create_timer(0.08).timeout
	_replay_dispatch_queued = false
	if not is_inside_tree():
		return
	var levels: Array = _pending_replays.keys()
	_pending_replays.clear()
	for pending_level in levels:
		if int(pending_level) == _selected_level:
			_replay_level(int(pending_level))


func _replay_all() -> void:
	_replay_level(_selected_level)
	_restart_loop_timer()


func _replay_level(level: int) -> void:
	if level != _selected_level:
		return
	var old_trail: Node = _trails.get(level, null)
	if old_trail != null and is_instance_valid(old_trail):
		if old_trail.has_method("force_release"):
			old_trail.call("force_release")
		old_trail.queue_free()
	var trail_root: Node2D = _preview_roots.get(level, null) as Node2D
	if trail_root == null:
		return
	var preview_points: Array[Vector2] = _update_preview_geometry(level)
	if preview_points.size() != 2:
		return
	var preview_from: Vector2 = preview_points[0]
	var preview_to: Vector2 = preview_points[1]
	var profile: Dictionary = (_profiles[level] as Dictionary).duplicate(true)
	var duration: float = float(profile.get("duration", 0.8))
	var spread: float = float(profile.get("spread", 0.0))
	var color := Color.from_hsv(
		fposmod(float(profile.get("color_hue", 26.0)), 360.0) / 360.0,
		clampf(float(profile.get("color_saturation", 0.88)), 0.0, 1.0),
		clampf(float(profile.get("color_value", 1.0)), 0.0, 1.0)
	)
	var trail := Node2D.new()
	trail.set_script(TrailProjectileScript)
	trail_root.add_child(trail)
	_trails[level] = trail
	if level == ORIGINAL_LEVEL:
		trail.call("launch", preview_from, preview_to, color, duration, spread, profile)
	else:
		trail.call("launch_power_attack", preview_from, preview_to, color, duration, spread, level, profile)
	_restart_loop_timer()


func _update_preview_geometry(level: int) -> Array[Vector2]:
	var viewport: SubViewport = _preview_viewports.get(level, null) as SubViewport
	if viewport == null:
		return []
	var preview_size := Vector2(viewport.size)
	if preview_size.x <= 4.0 or preview_size.y <= 4.0:
		return []
	var source_ratio: float
	var source_min_x: float
	match level:
		ORIGINAL_LEVEL:
			source_ratio = 0.04
			source_min_x = 32.0
		MID_LEVEL:
			source_ratio = 0.18
			source_min_x = 180.0
		_:
			source_ratio = 0.24
			source_min_x = 280.0
	var preview_from := Vector2(
		minf(maxf(preview_size.x * source_ratio, source_min_x), preview_size.x * 0.38),
		preview_size.y * 0.62
	)
	var preview_to := Vector2(preview_size.x * 0.84, preview_size.y * 0.45)
	var guide: Line2D = _preview_guides.get(level, null) as Line2D
	if guide != null:
		guide.points = PackedVector2Array([preview_from, preview_to])
	var markers: Dictionary = _preview_markers.get(level, {})
	var source_marker: Control = markers.get("source", null) as Control
	var target_marker: Control = markers.get("target", null) as Control
	if source_marker != null:
		source_marker.position = preview_from - source_marker.size * 0.5
	if target_marker != null:
		target_marker.position = preview_to - target_marker.size * 0.5
	return [preview_from, preview_to]


func _restart_loop_timer() -> void:
	if _loop_timer == null or _auto_replay == null or not _auto_replay.button_pressed:
		return
	var profile: Dictionary = _profiles[_selected_level]
	var wait_time: float = float(profile.get("duration", 0.8)) + float(profile.get("fade_duration", 0.2)) + 0.65
	_loop_timer.start(wait_time)


func _on_loop_timer_timeout() -> void:
	if _auto_replay != null and _auto_replay.button_pressed:
		_replay_all()


func _on_auto_replay_toggled(enabled: bool) -> void:
	if enabled:
		_replay_all()
	elif _loop_timer != null:
		_loop_timer.stop()


func _reset_all() -> void:
	_updating_controls = true
	for level in LEVELS:
		_profiles[level] = _make_default_profile(level)
		var level_sliders: Dictionary = _sliders[level]
		for key_value in level_sliders:
			var key: String = str(key_value)
			var slider: HSlider = level_sliders[key] as HSlider
			if slider != null:
				slider.value = float((_profiles[level] as Dictionary).get(key, slider.value))
		_update_diff(level)
	_updating_controls = false
	_replay_all()


func _update_diff(level: int) -> void:
	var output: TextEdit = _diff_outputs.get(level, null) as TextEdit
	if output == null:
		return
	output.text = _build_diff_text(level)


func _build_diff_text(level: int) -> String:
	var current: Dictionary = _profiles[level]
	var defaults: Dictionary = _make_default_profile(level)
	var lines: PackedStringArray = [
		"[%s] Preview only; game code unchanged / 僅預覽；未修改正式遊戲程式碼" % _level_tab_text(level),
	]
	for group_value in _parameter_groups_for_level(level):
		var group: Dictionary = group_value
		for spec_value in group.get("items", []):
			var spec: Dictionary = spec_value
			var key: String = str(spec.get("key", ""))
			var old_value: float = float(defaults.get(key, 0.0))
			var new_value: float = float(current.get(key, old_value))
			if is_equal_approx(old_value, new_value):
				continue
			var decimals: int = int(spec.get("decimals", 2))
			var suffix: String = str(spec.get("suffix", ""))
			var delta: float = new_value - old_value
			lines.append("%s [%s]: %s -> %s (delta %s)" % [
				key,
				str(spec.get("label", key)),
				_format_value(old_value, decimals, suffix),
				_format_value(new_value, decimals, suffix),
				_format_signed_value(delta, decimals, suffix),
			])
	if lines.size() == 1:
		lines.append("No changes / 沒有變更")
	return "\n".join(lines)


func _format_signed_value(value: float, decimals: int, suffix: String) -> String:
	var sign_text := "+" if value >= 0.0 else ""
	return "%s%.*f%s" % [sign_text, decimals, value, suffix]


func _copy_diff(level: int) -> void:
	DisplayServer.clipboard_set(_build_diff_text(level))


func _level_tab_text(level: int) -> String:
	match level:
		ORIGINAL_LEVEL:
			return "ORIGINAL 原始"
		MID_LEVEL:
			return "MID 中等"
		_:
			return "MAX 最大"


func _level_title(level: int) -> String:
	match level:
		ORIGINAL_LEVEL:
			return "ORIGINAL ATTACK 原始攻擊"
		MID_LEVEL:
			return "MID ATTACK POWER 中等攻擊威力"
		_:
			return "MAX ATTACK POWER 最大攻擊威力"


func _level_accent(level: int) -> Color:
	match level:
		ORIGINAL_LEVEL:
			return Color(0.50, 0.92, 0.48)
		MID_LEVEL:
			return Color(0.22, 0.82, 1.0)
		_:
			return Color(1.0, 0.72, 0.16)


func _make_panel_style(accent: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.055, 0.065, 0.105, 0.98)
	style.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	return style
