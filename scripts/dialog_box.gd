## DialogBox — AVG 風格對話場景（獨立場景，非覆蓋層）。
## 支援：背景圖、角色立繪滑入/滑出、說話者高亮、擠壓彈跳動畫、
## 情緒差分貼圖、打字機效果、繁中/英文雙語、背景音樂切換。
extends Control

const _DialogLine := preload("res://scripts/dialog_line.gd")
const _DialogSequence := preload("res://scripts/dialog_sequence.gd")

signal dialog_finished

# ── 設計常數 ──────────────────────────────────────────────────
# 立繪比例與位置（相對於 viewport 尺寸）
const PORTRAIT_SCALE := 7.2            # 原始小圖放大倍率（4.0 × 1.8）
const PORTRAIT_Y_RATIO := 0.527        # 立繪頂端 Y / viewport_h
const LEFT_X_RATIO := 0.064            # 左側立繪 X / viewport_w
const RIGHT_X_RATIO := 0.625           # 右側立繪 X / viewport_w
const SLIDE_OFFSET_RATIO := 0.41       # 滑入/滑出偏移量 / viewport_w
const ACTIVE_PORTRAIT_Z := 100         # 目前說話者永遠畫在最前方
const DIALOG_PANEL_Z := 150
const FULLSCREEN_FADE_Z := 220
const ROTARY_X_RADIUS := 92.0          # 多角色同側旋轉展示的水平半徑
const ROTARY_Y_RADIUS := 48.0          # 多角色同側旋轉展示的垂直半徑
const BACK_PORTRAIT_SCALE := 0.86      # 非說話角色稍微縮小，讓後排更不擁擠

# 動畫時間
const SLIDE_IN_DUR := 0.35
const SLIDE_OUT_DUR := 0.28
const DIM_DUR := 0.2
const TYPEWRITER_CPS := 35.0           # 打字機速度（字/秒）
const SQUEEZE_DUR := 0.22              # 擠壓彈跳總時長

# 說話者 / 非說話者 modulate
const ACTIVE_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const INACTIVE_COLOR := Color(0.3, 0.3, 0.35, 1.0)

# 對話框樣式
const PANEL_HEIGHT := 300.0
const PANEL_MARGIN := 24.0
const NAME_FONT_SIZE := 28
const TEXT_FONT_SIZE := 26
const SKIP_FONT_SIZE := 20

# 音樂淡入淡出
const BGM_FADE_DUR := 0.8
const BG_SWITCH_FADE_DUR := 0.18

# Skip 自動推進
const SKIP_INTERVAL := 0.1
const FONT_PATH := "res://assets/fonts/game_ui_font.tres"

# 角色名稱顏色
const CHAR_NAME_COLORS := {
	"husky":   Color(1.0, 0.92, 0.5),
	"fox":     Color(1.0, 0.55, 0.35),
	"polar":   Color(0.6, 0.82, 1.0),
	"raccoon": Color(0.55, 0.9, 0.5),
	"boar":    Color(0.45, 0.7, 1.0),
	"panda":   Color(0.55, 0.9, 0.5),
	"dragon":  Color(1.0, 0.45, 0.3),
	"shark":   Color(0.4, 0.85, 1.0),
}

# 角色 ID → 實際貼圖檔名的別名（保留 char_id 不變的情況下換圖）
const _CHAR_ID_ALIAS := {
	"raccoon": "raccoon_baby",
}

# ── 節點引用 ──────────────────────────────────────────────────
var _bg_rect: TextureRect
var _bg_color: ColorRect
var _portrait_left: TextureRect
var _portrait_right: TextureRect
var _portrait_layer: Control
var _name_label: Label
var _text_label: RichTextLabel
var _tap_zone: Button
var _dialog_panel: PanelContainer
var _bgm_player: AudioStreamPlayer
var _skip_btn: Button

# ── 狀態 ─────────────────────────────────────────────────────
var _sequence: _DialogSequence
var _line_index: int = -1
var _left_char_id: String = ""
var _right_char_id: String = ""
var _side_characters: Dictionary = {"left": [], "right": []}
var _portrait_nodes: Dictionary = {}
var _last_speaker_id: String = ""
var _side_speaker_ids: Dictionary = {"left": "", "right": ""}
var auto_start: bool = true
var _preview_mode: bool = false
var _finish_with_fade: bool = false
var _start_with_fade: bool = false
var _typing: bool = false
var _event_transitioning: bool = false
var _type_tween: Tween = null
var _bg_switch_tween: Tween = null
var _texture_cache: Dictionary = {}  # path -> Texture2D
var _auto_skipping: bool = false
var _skip_timer: Timer = null


func _ready() -> void:
	_build_ui()
	_tap_zone.pressed.connect(_advance)
	# 從準備畫面淡入
	var gs: Node = get_node_or_null("/root/GameState")
	if auto_start and gs != null:
		gs.fade_in_if_pending(0.4)
	# 漸隱前一場景的 BGM（例如地圖音樂）
	if auto_start and gs != null:
		gs.fade_out_bgm(0.4)
	# 獨立場景模式：自動讀取 GameState 的對話資料並播放
	if auto_start and gs != null and gs.selected_stage != null and gs.selected_stage.pre_dialog != null:
		start(gs.selected_stage.pre_dialog)


# ── 公開 API ─────────────────────────────────────────────────

## 開始播放對話序列
func start(sequence: _DialogSequence, preview_mode: bool = false, finish_with_fade: bool = false, start_with_fade: bool = false) -> void:
	_sequence = sequence
	_preview_mode = preview_mode
	_finish_with_fade = finish_with_fade
	_start_with_fade = start_with_fade
	_event_transitioning = false
	_line_index = -1
	_left_char_id = ""
	_right_char_id = ""
	_side_characters = {"left": [], "right": []}
	_last_speaker_id = ""
	_side_speaker_ids = {"left": "", "right": ""}
	for node_variant in _portrait_nodes.values():
		var portrait_node: TextureRect = node_variant as TextureRect
		if portrait_node != null:
			portrait_node.queue_free()
	_portrait_nodes.clear()
	_set_auto_skip(false)
	_portrait_left.visible = false
	_portrait_right.visible = false

	# 設定背景圖
	_set_background_texture(sequence.background)
	if sequence.initial_music != null:
		_change_bgm(sequence.initial_music)

	if _start_with_fade:
		_play_start_fade_in()

	_advance()


func switch_background(texture: Texture2D, animated: bool = true) -> void:
	if _bg_rect == null or _bg_color == null:
		return
	if _bg_switch_tween != null and _bg_switch_tween.is_valid():
		_bg_switch_tween.kill()
	if not animated:
		_set_background_texture(texture)
		return
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.z_index = FULLSCREEN_FADE_Z
	add_child(overlay)
	_bg_switch_tween = create_tween()
	_bg_switch_tween.tween_property(overlay, "color:a", 1.0, BG_SWITCH_FADE_DUR)
	_bg_switch_tween.tween_callback(Callable(self, "_set_background_texture").bind(texture))
	_bg_switch_tween.tween_property(overlay, "color:a", 0.0, BG_SWITCH_FADE_DUR)
	_bg_switch_tween.tween_callback(overlay.queue_free)


func _set_background_texture(texture: Texture2D) -> void:
	if texture != null:
		_bg_rect.texture = texture
		_bg_rect.visible = true
		_bg_color.visible = false
	else:
		_bg_rect.visible = false
		_bg_color.visible = true


func _play_start_fade_in() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 1)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = FULLSCREEN_FADE_Z
	add_child(overlay)
	var tw := create_tween()
	tw.tween_property(overlay, "color:a", 0.0, 0.35)
	tw.tween_callback(overlay.queue_free)


# ── UI 建構 ──────────────────────────────────────────────────

func _build_ui() -> void:
	var dialog_font := load(FONT_PATH) as Font

	# 純色背景（fallback）
	_bg_color = ColorRect.new()
	_bg_color.color = Color(0.05, 0.05, 0.1, 1.0)
	_bg_color.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_color.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_color)

	# 圖片背景
	_bg_rect = TextureRect.new()
	_bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_rect.visible = false
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_rect)

	# 半透明暗化層（讓立繪和文字更清晰）
	var dim_overlay := ColorRect.new()
	dim_overlay.color = Color(0, 0, 0, 0.3)
	dim_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim_overlay)

	_portrait_layer = Control.new()
	_portrait_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait_layer)

	# 立繪尺寸（以放大倍率擴張 rect，避免 squeeze bounce 重設 transform.scale 影響大小）
	var p_w: float = 300.0 * (PORTRAIT_SCALE / 4.0)
	var p_h: float = 400.0 * (PORTRAIT_SCALE / 4.0)
	var vp: Vector2 = ViewportUtils.get_size()
	var left_x: float = vp.x * LEFT_X_RATIO
	var right_x: float = vp.x * RIGHT_X_RATIO
	var portrait_y: float = vp.y * PORTRAIT_Y_RATIO

	# 左側立繪
	_portrait_left = TextureRect.new()
	_portrait_left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_left.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_left.custom_minimum_size = Vector2(p_w, p_h)
	_portrait_left.size = Vector2(p_w, p_h)
	_portrait_left.position = Vector2(left_x - (p_w - 300.0) * 0.5 - 50.0, portrait_y - (p_h - 400.0))
	_portrait_left.set_meta("home_x", _portrait_left.position.x)
	_portrait_left.visible = false
	_portrait_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait_left)

	# 右側立繪
	_portrait_right = TextureRect.new()
	_portrait_right.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_right.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_right.custom_minimum_size = Vector2(p_w, p_h)
	_portrait_right.size = Vector2(p_w, p_h)
	_portrait_right.position = Vector2(right_x - (p_w - 300.0) * 0.5 - 30.0, portrait_y - (p_h - 400.0))
	_portrait_right.set_meta("home_x", _portrait_right.position.x)
	_portrait_right.visible = false
	_portrait_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait_right)

	# 對話框面板（底部全寬，靠 anchor 自動延展）
	_dialog_panel = PanelContainer.new()
	_dialog_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_dialog_panel.offset_top = -PANEL_HEIGHT
	_dialog_panel.offset_bottom = 0.0
	_dialog_panel.offset_left = 0.0
	_dialog_panel.offset_right = 0.0
	_dialog_panel.z_index = DIALOG_PANEL_Z
	_dialog_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.08, 0.14, 0.92)
	panel_style.border_color = Color(0.35, 0.35, 0.5, 0.6)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(0)
	panel_style.content_margin_left = PANEL_MARGIN
	panel_style.content_margin_right = PANEL_MARGIN
	panel_style.content_margin_top = PANEL_MARGIN * 0.6
	panel_style.content_margin_bottom = PANEL_MARGIN * 0.5
	_dialog_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_dialog_panel)

	var vbox := VBoxContainer.new()
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dialog_panel.add_child(vbox)

	# 角色名稱列：左為名稱，右為 Skip 按鈕
	var name_row := HBoxContainer.new()
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(name_row)

	# 角色名稱
	_name_label = Label.new()
	if dialog_font != null:
		_name_label.add_theme_font_override("font", dialog_font)
	_name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_name_label.add_theme_constant_override("outline_size", 3)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_label)

	# Skip 按鈕（與名稱同一列、靠右）— 文字風格與對話內文一致
	_skip_btn = Button.new()
	_skip_btn.text = Locale.tr_ui("SKIP")
	_skip_btn.focus_mode = Control.FOCUS_NONE
	_skip_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	if dialog_font != null:
		_skip_btn.add_theme_font_override("font", dialog_font)
	_skip_btn.add_theme_font_size_override("font_size", SKIP_FONT_SIZE)
	_skip_btn.add_theme_color_override("font_color", Color.WHITE)
	_skip_btn.add_theme_color_override("font_color_hover", Color(1.0, 1.0, 1.0, 0.7))
	_skip_btn.add_theme_color_override("font_color_pressed", Color(1.0, 1.0, 1.0, 0.5))
	var skip_empty := StyleBoxEmpty.new()
	_skip_btn.add_theme_stylebox_override("normal", skip_empty)
	_skip_btn.add_theme_stylebox_override("hover", skip_empty)
	_skip_btn.add_theme_stylebox_override("pressed", skip_empty)
	_skip_btn.add_theme_stylebox_override("focus", skip_empty)
	_skip_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	_skip_btn.pressed.connect(_on_skip_pressed)
	name_row.add_child(_skip_btn)

	# 間隔
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(spacer)

	# 對話文字
	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.scroll_active = false
	_text_label.custom_minimum_size = Vector2(vp.x - PANEL_MARGIN * 2, 0)
	if dialog_font != null:
		_text_label.add_theme_font_override("normal_font", dialog_font)
		_text_label.add_theme_font_override("bold_font", dialog_font)
	_text_label.add_theme_font_size_override("normal_font_size", TEXT_FONT_SIZE)
	_text_label.add_theme_color_override("default_color", Color.WHITE)
	_text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_text_label)

	# 全螢幕點擊區域
	_tap_zone = Button.new()
	_tap_zone.flat = true
	_tap_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tap_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	# 完全透明的按鈕
	var empty_style := StyleBoxEmpty.new()
	_tap_zone.add_theme_stylebox_override("normal", empty_style)
	_tap_zone.add_theme_stylebox_override("hover", empty_style)
	_tap_zone.add_theme_stylebox_override("pressed", empty_style)
	_tap_zone.add_theme_stylebox_override("focus", empty_style)
	add_child(_tap_zone)

	# 確保對話面板（含 Skip 按鈕）在 tap_zone 之上接收點擊
	_dialog_panel.move_to_front()

	# Skip 定時器
	_skip_timer = Timer.new()
	_skip_timer.wait_time = SKIP_INTERVAL
	_skip_timer.one_shot = false
	_skip_timer.timeout.connect(_advance)
	add_child(_skip_timer)

	# BGM 播放器
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.bus = "Master"
	add_child(_bgm_player)


# ── 對話推進 ─────────────────────────────────────────────────

func _advance() -> void:
	if _event_transitioning:
		return
	# 若正在打字 → 立即全顯
	if _typing:
		_finish_typing()
		return

	_line_index += 1
	if _line_index >= _sequence.lines.size():
		_set_auto_skip(false)
		_finish_dialog()
		return

	var line: _DialogLine = _sequence.lines[_line_index]
	_show_line(line)


## Skip 按鈕：切換自動推進
func _on_skip_pressed() -> void:
	_set_auto_skip(not _auto_skipping)
	if _auto_skipping:
		_advance()


func _set_auto_skip(enabled: bool) -> void:
	_auto_skipping = enabled
	if _skip_btn != null:
		_skip_btn.add_theme_color_override(
			"font_color",
			Color(1.0, 0.85, 0.3) if enabled else Color.WHITE)
	if _skip_timer == null:
		return
	if enabled:
		_skip_timer.start(SKIP_INTERVAL)
	else:
		_skip_timer.stop()


func _show_line(line: _DialogLine) -> void:
	var char_id: String = line.character_id
	var side: String = _normalize_dialog_side(line.position)
	if line.stop_music:
		_fade_out_dialog_bgm()
	elif line.music != null:
		_change_bgm(line.music)

	# ── 音樂切換 ──
	if line.action == "switch_bg":
		_name_label.text = ""
		_text_label.text = ""
		_text_label.visible_ratio = 1.0
		_typing = false
		_event_transitioning = true
		switch_background(line.background, true)
		var event_duration: float = BG_SWITCH_FADE_DUR * 2.0
		if line.stop_music or line.music != null:
			event_duration = maxf(event_duration, BGM_FADE_DUR)
		get_tree().create_timer(event_duration).timeout.connect(func() -> void:
			if is_inside_tree():
				_event_transitioning = false
				_advance()
		, CONNECT_ONE_SHOT)
		return

	if line.action == "switch_bgm":
		_name_label.text = ""
		_text_label.text = ""
		_text_label.visible_ratio = 1.0
		_typing = false
		get_tree().create_timer(BGM_FADE_DUR).timeout.connect(func() -> void:
			if is_inside_tree():
				_advance()
		, CONNECT_ONE_SHOT)
		return

	# ── 旁白行（無角色）──
	if char_id.is_empty():
		_set_all_portraits_dim("")
		_name_label.text = ""
	else:
		# ── 處理動作：enter / exit ──
		if line.action == "exit":
			_last_speaker_id = char_id
			var exit_side: String = _get_character_side(char_id)
			_do_exit_character(char_id)
			if exit_side.is_empty():
				exit_side = side
			_set_side_portraits_dim(exit_side, "")
			_name_label.text = ""
			_text_label.text = ""
			_text_label.visible_ratio = 1.0
			_typing = false
			get_tree().create_timer(SLIDE_OUT_DUR).timeout.connect(func() -> void:
				if is_inside_tree():
					_advance()
			, CONNECT_ONE_SHOT)
			return
		else:
			_last_speaker_id = char_id
			_side_speaker_ids[side] = char_id
			_ensure_character_entered(char_id, side, line.emotion)
			_set_side_portraits_dim(side, char_id)

		# ── 擠壓彈跳說話動畫 ──
		var portrait: TextureRect = _portrait_nodes.get(char_id, null) as TextureRect
		if line.shake and line.action != "exit" and portrait != null and portrait.visible:
			_play_squeeze_bounce(portrait, _portrait_target_scale(char_id, side))

		# ── 名稱 ──
		_name_label.text = Locale.tr_or("DIALOG_" + char_id, char_id.capitalize())
		_name_label.add_theme_color_override("font_color", _dialog_name_color(char_id))

	# ── 打字機效果 ──
	var locale_node2: Node = get_node_or_null("/root/Locale")
	var dialog_text: String
	if locale_node2 != null:
		dialog_text = locale_node2.get_dialog_text(line)
	else:
		dialog_text = line.text_zh if not line.text_zh.is_empty() else line.text_en
	_text_label.text = dialog_text
	_text_label.visible_ratio = 0.0
	_typing = true

	var char_count: int = dialog_text.length()
	var duration: float = char_count / TYPEWRITER_CPS if char_count > 0 else 0.01
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	_type_tween = create_tween()
	_type_tween.tween_property(_text_label, "visible_ratio", 1.0, duration)
	_type_tween.tween_callback(_on_typing_done)


func _finish_typing() -> void:
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	_text_label.visible_ratio = 1.0
	_typing = false


func _on_typing_done() -> void:
	_typing = false


func _finish_dialog() -> void:
	if _preview_mode:
		if _finish_with_fade:
			_finish_preview_with_fade()
		else:
			dialog_finished.emit()
			queue_free()
		return

	# 淡出音樂
	if _bgm_player.playing:
		var fade := create_tween()
		fade.tween_property(_bgm_player, "volume_db", -40.0, 0.6)
		fade.tween_callback(_bgm_player.stop)

	# 淡出畫面 → 切換至戰鬥場景
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = FULLSCREEN_FADE_Z
	add_child(overlay)

	var tw := create_tween()
	tw.tween_property(overlay, "color:a", 1.0, 0.5)
	tw.tween_callback(func() -> void:
		dialog_finished.emit()
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	)


func _finish_preview_with_fade() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.z_index = FULLSCREEN_FADE_Z
	add_child(overlay)

	var tw := create_tween()
	tw.tween_property(overlay, "color:a", 1.0, 0.35)
	tw.tween_callback(func() -> void:
		dialog_finished.emit()
		queue_free()
	)


# ── 音樂系統 ─────────────────────────────────────────────────

func _change_bgm(stream: AudioStream) -> void:
	if _bgm_player.playing:
		var fade := create_tween()
		fade.tween_property(_bgm_player, "volume_db", -40.0, BGM_FADE_DUR)
		fade.tween_callback(func() -> void:
			_bgm_player.stream = stream
			_bgm_player.volume_db = -10.0
			_bgm_player.play()
			var fade_in := create_tween()
			fade_in.tween_property(_bgm_player, "volume_db", 0.0, BGM_FADE_DUR)
		)
	else:
		_bgm_player.stream = stream
		_bgm_player.volume_db = -10.0
		_bgm_player.play()
		var fade_in := create_tween()
		fade_in.tween_property(_bgm_player, "volume_db", 0.0, BGM_FADE_DUR)


# ── 立繪管理 ─────────────────────────────────────────────────

func _fade_out_dialog_bgm() -> void:
	if _bgm_player == null or not _bgm_player.playing:
		return
	var fade := create_tween()
	fade.tween_property(_bgm_player, "volume_db", -40.0, BGM_FADE_DUR)
	fade.tween_callback(func() -> void:
		if is_instance_valid(_bgm_player):
			_bgm_player.stop()
			_bgm_player.stream = null
			_bgm_player.volume_db = 0.0
	)


func _normalize_dialog_side(side: String) -> String:
	return "right" if side == "right" else "left"


func _get_portrait_size() -> Vector2:
	return Vector2(300.0 * (PORTRAIT_SCALE / 4.0), 400.0 * (PORTRAIT_SCALE / 4.0))


func _portrait_anchor_position(side: String) -> Vector2:
	var portrait_size: Vector2 = _get_portrait_size()
	var vp: Vector2 = ViewportUtils.get_size()
	var portrait_y: float = vp.y * PORTRAIT_Y_RATIO
	var anchor_x: float
	if side == "right":
		anchor_x = vp.x * RIGHT_X_RATIO - (portrait_size.x - 300.0) * 0.5 - 30.0
	else:
		anchor_x = vp.x * LEFT_X_RATIO - (portrait_size.x - 300.0) * 0.5 - 30.0
	return Vector2(anchor_x, portrait_y - (portrait_size.y - 400.0))


func _portrait_target_position(side: String, side_index: int, side_count: int = 1, active_index: int = -1) -> Vector2:
	var anchor_position: Vector2 = _portrait_anchor_position(side)
	var char_id: String = ""
	if _side_characters.has(side):
		var side_list: Array = _side_characters[side]
		if side_index >= 0 and side_index < side_list.size():
			char_id = String(side_list[side_index])
	var character_offset: Vector2 = _dialog_phase_offset(char_id)
	if side_count <= 1:
		return anchor_position + character_offset
	var display_index: int = side_index
	if active_index >= 0:
		display_index = posmod(side_index - active_index, side_count)
	var angle: float = -PI * 0.5 + TAU * float(display_index) / float(side_count)
	var offset := Vector2(cos(angle) * ROTARY_X_RADIUS, -sin(angle) * ROTARY_Y_RADIUS)
	return anchor_position + offset + character_offset


func _side_active_speaker_id(side: String) -> String:
	return String(_side_speaker_ids.get(side, ""))


func _portrait_target_scale(char_id: String, side: String) -> Vector2:
	var character_scale: float = _dialog_phase_scale(char_id)
	if char_id == _side_active_speaker_id(side):
		return Vector2(character_scale, character_scale)
	return Vector2(BACK_PORTRAIT_SCALE * character_scale, BACK_PORTRAIT_SCALE * character_scale)


func _dialog_phase_scale(char_id: String) -> float:
	var character: CharacterData = _find_character_data(char_id)
	if character == null:
		return 1.0
	return maxf(0.05, character.dialog_phase_scale)


func _dialog_phase_offset(char_id: String) -> Vector2:
	var character: CharacterData = _find_character_data(char_id)
	if character == null:
		return Vector2.ZERO
	return character.dialog_phase_offset


func _dialog_name_color(char_id: String) -> Color:
	var character: CharacterData = _find_character_data(char_id)
	if character != null:
		var element_color: Color = Block.COLORS.get(character.gem_type, Color.WHITE)
		return element_color.lightened(0.35)
	return CHAR_NAME_COLORS.get(char_id, Color.WHITE)


func _find_character_data(char_id: String) -> CharacterData:
	if char_id.is_empty():
		return null
	var gs: Node = get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("get_character_catalog"):
		return null
	var lower := char_id.to_lower()
	var catalog: Array = gs.call("get_character_catalog")
	for entry in catalog:
		if entry is CharacterData:
			var c: CharacterData = entry as CharacterData
			var path_id := c.resource_path.get_file().get_basename().trim_prefix("char_").to_lower()
			if path_id == lower or c.character_name.to_lower() == lower:
				return c
	return null


func _make_dynamic_portrait(char_id: String) -> TextureRect:
	var portrait := TextureRect.new()
	portrait.name = "Portrait_" + char_id
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var portrait_size: Vector2 = _get_portrait_size()
	portrait.custom_minimum_size = portrait_size
	portrait.size = portrait_size
	portrait.pivot_offset = Vector2(portrait_size.x * 0.5, portrait_size.y)
	portrait.visible = false
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	portrait.modulate = ACTIVE_COLOR
	_portrait_layer.add_child(portrait)
	return portrait


func _get_dynamic_portrait(char_id: String) -> TextureRect:
	var existing: TextureRect = _portrait_nodes.get(char_id, null) as TextureRect
	if existing != null:
		return existing
	var portrait: TextureRect = _make_dynamic_portrait(char_id)
	_portrait_nodes[char_id] = portrait
	return portrait


func _get_character_side(char_id: String) -> String:
	for side_variant in _side_characters.keys():
		var side: String = String(side_variant)
		var side_list: Array = _side_characters[side]
		if side_list.has(char_id):
			return side
	return ""


func _remove_character_from_sides(char_id: String) -> void:
	for side_variant in _side_characters.keys():
		var side: String = String(side_variant)
		var side_list: Array = _side_characters[side]
		while side_list.has(char_id):
			side_list.erase(char_id)


func _layout_portraits(animated: bool, skip_char_id: String = "") -> void:
	for side_name in ["left", "right"]:
		var side_list: Array = _side_characters[side_name]
		var side_count: int = side_list.size()
		var side_speaker_id: String = _side_active_speaker_id(side_name)
		var active_index: int = side_list.find(side_speaker_id)
		for side_index in side_list.size():
			var char_id: String = String(side_list[side_index])
			if char_id == skip_char_id:
				continue
			var portrait: TextureRect = _portrait_nodes.get(char_id, null) as TextureRect
			if portrait == null or not portrait.visible:
				continue
			portrait.flip_h = side_name == "left"
			portrait.z_index = ACTIVE_PORTRAIT_Z if char_id == _last_speaker_id else 60 if char_id == side_speaker_id else side_index
			var target_position: Vector2 = _portrait_target_position(side_name, side_index, side_count, active_index)
			var target_scale: Vector2 = _portrait_target_scale(char_id, side_name)
			portrait.set_meta("home_x", target_position.x)
			if animated:
				var tw := create_tween()
				tw.tween_property(portrait, "position", target_position, 0.18) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
				tw.parallel().tween_property(portrait, "scale", target_scale, 0.18) \
					.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
			else:
				portrait.position = target_position
				portrait.scale = target_scale


func _ensure_character_entered(char_id: String, side: String, emotion: String) -> void:
	side = _normalize_dialog_side(side)
	var portrait: TextureRect = _get_dynamic_portrait(char_id)
	_update_portrait_texture(portrait, char_id, emotion, side == "left")
	var current_side: String = _get_character_side(char_id)
	if current_side == side and portrait.visible:
		_layout_portraits(true)
		return

	_remove_character_from_sides(char_id)
	var side_list: Array = _side_characters[side]
	side_list.append(char_id)
	portrait.visible = true
	portrait.modulate = ACTIVE_COLOR
	portrait.flip_h = side == "left"
	portrait.z_index = ACTIVE_PORTRAIT_Z
	var active_index: int = side_list.find(char_id)
	var target_position: Vector2 = _portrait_target_position(side, side_list.size() - 1, side_list.size(), active_index)
	portrait.scale = _portrait_target_scale(char_id, side)
	portrait.set_meta("home_x", target_position.x)
	var slide_offset: float = ViewportUtils.get_size().x * SLIDE_OFFSET_RATIO
	portrait.position = Vector2(target_position.x - slide_offset if side == "left" else target_position.x + slide_offset, target_position.y)
	_layout_portraits(true, char_id)
	var tw := create_tween()
	tw.tween_property(portrait, "position", target_position, SLIDE_IN_DUR) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _do_exit_character(char_id: String) -> void:
	var side: String = _get_character_side(char_id)
	var portrait: TextureRect = _portrait_nodes.get(char_id, null) as TextureRect
	if side.is_empty() or portrait == null or not portrait.visible:
		return
	portrait.z_index = ACTIVE_PORTRAIT_Z
	_remove_character_from_sides(char_id)
	if _last_speaker_id == char_id:
		_last_speaker_id = ""
	if _side_active_speaker_id(side) == char_id:
		_side_speaker_ids[side] = ""
	_layout_portraits(true, char_id)
	var slide_offset: float = ViewportUtils.get_size().x * SLIDE_OFFSET_RATIO
	var target_x: float = portrait.position.x - slide_offset if side == "left" else portrait.position.x + slide_offset
	var tw := create_tween()
	tw.tween_property(portrait, "position:x", target_x, SLIDE_OUT_DUR) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(portrait, "modulate:a", 0.0, SLIDE_OUT_DUR)
	tw.tween_callback(func() -> void:
		portrait.visible = false
		portrait.modulate = ACTIVE_COLOR
	)


func _set_all_portraits_dim(active_char_id: String) -> void:
	for char_variant in _portrait_nodes.keys():
		var char_id: String = String(char_variant)
		var portrait: TextureRect = _portrait_nodes[char_id]
		if portrait == null or not portrait.visible:
			continue
		_set_portrait_dim(portrait, char_id != active_char_id)


func _set_side_portraits_dim(side: String, active_char_id: String) -> void:
	if not _side_characters.has(side):
		return
	var side_list: Array = _side_characters[side]
	for char_variant in side_list:
		var char_id: String = String(char_variant)
		var portrait: TextureRect = _portrait_nodes.get(char_id, null) as TextureRect
		if portrait == null or not portrait.visible:
			continue
		_set_portrait_dim(portrait, char_id != active_char_id)


func _do_enter(char_id: String, emotion: String, is_left: bool, portrait: TextureRect) -> void:
	# 如果同側已有不同角色，先快速滑出
	var current_id: String = _left_char_id if is_left else _right_char_id
	if not current_id.is_empty() and current_id != char_id:
		_do_instant_exit(is_left, portrait)

	_update_portrait_texture(portrait, char_id, emotion, is_left)
	portrait.visible = true
	portrait.modulate = ACTIVE_COLOR

	# 從螢幕外滑入
	var vp: Vector2 = ViewportUtils.get_size()
	var fallback_x: float = vp.x * (LEFT_X_RATIO if is_left else RIGHT_X_RATIO)
	var slide_offset: float = vp.x * SLIDE_OFFSET_RATIO
	var target_x: float = portrait.get_meta("home_x", fallback_x)
	var start_x: float = target_x - slide_offset if is_left else target_x + slide_offset
	portrait.position.x = start_x
	var tw := create_tween()
	tw.tween_property(portrait, "position:x", target_x, SLIDE_IN_DUR) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _do_exit(is_left: bool, portrait: TextureRect) -> void:
	if not portrait.visible:
		return
	var slide_offset: float = ViewportUtils.get_size().x * SLIDE_OFFSET_RATIO
	var target_x: float = portrait.position.x - slide_offset if is_left else portrait.position.x + slide_offset
	var tw := create_tween()
	tw.tween_property(portrait, "position:x", target_x, SLIDE_OUT_DUR) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.parallel().tween_property(portrait, "modulate:a", 0.0, SLIDE_OUT_DUR)
	tw.tween_callback(func() -> void:
		portrait.visible = false
		portrait.modulate = ACTIVE_COLOR
	)


func _do_instant_exit(is_left: bool, portrait: TextureRect) -> void:
	portrait.visible = false
	portrait.modulate = ACTIVE_COLOR
	var fallback_x: float = ViewportUtils.get_size().x * (LEFT_X_RATIO if is_left else RIGHT_X_RATIO)
	portrait.position.x = portrait.get_meta("home_x", fallback_x)


func _update_portrait_texture(portrait: TextureRect, char_id: String, emotion: String, is_left: bool) -> void:
	var tex: Texture2D = _load_character_texture(char_id, emotion)
	if tex != null:
		portrait.texture = tex
		# 左側角色朝右（面向中心），右側角色朝左（面向中心）
		portrait.flip_h = is_left


func _load_character_texture(char_id: String, emotion: String) -> Texture2D:
	# 角色 ID 別名（例如 raccoon → raccoon_baby）
	var aliased: String = _CHAR_ID_ALIAS.get(char_id, char_id)
	# 嘗試情緒差分貼圖
	if emotion != "normal" and not emotion.is_empty():
		var emotion_path := "res://assets/characters/%s_%s.png" % [aliased, emotion]
		if _texture_cache.has(emotion_path):
			return _texture_cache[emotion_path]
		if ResourceLoader.exists(emotion_path):
			var tex: Texture2D = load(emotion_path)
			_texture_cache[emotion_path] = tex
			return tex

	# Fallback: 預設貼圖
	var default_path := "res://assets/%s.png" % aliased
	if _texture_cache.has(default_path):
		return _texture_cache[default_path]
	if ResourceLoader.exists(default_path):
		var tex: Texture2D = load(default_path)
		_texture_cache[default_path] = tex
		return tex

	return null


func _set_portrait_dim(portrait: TextureRect, dim: bool) -> void:
	if not portrait.visible:
		return
	var target: Color = INACTIVE_COLOR if dim else ACTIVE_COLOR
	var tw := create_tween()
	tw.tween_property(portrait, "modulate", target, DIM_DUR)


func _play_squeeze_bounce(portrait: TextureRect, base_scale: Vector2) -> void:
	# 設定 pivot 到底部中心（立繪從底部擠壓）
	portrait.pivot_offset = Vector2(portrait.size.x * 0.5, portrait.size.y)

	var t: float = SQUEEZE_DUR
	var tw := create_tween()
	# 擠壓（壓扁）
	tw.tween_property(portrait, "scale", base_scale * Vector2(1.06, 0.92), t * 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# 彈起（拉長）
	tw.tween_property(portrait, "scale", base_scale * Vector2(0.95, 1.08), t * 0.35) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# 回歸
	tw.tween_property(portrait, "scale", base_scale, t * 0.35) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
