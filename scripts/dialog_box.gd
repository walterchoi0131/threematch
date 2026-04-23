## DialogBox — AVG 風格對話場景（獨立場景，非覆蓋層）。
## 支援：背景圖、角色立繪滑入/滑出、說話者高亮、擠壓彈跳動畫、
## 情緒差分貼圖、打字機效果、繁中/英文雙語、背景音樂切換。
extends Control

const _DialogLine := preload("res://scripts/dialog_line.gd")
const _DialogSequence := preload("res://scripts/dialog_sequence.gd")

signal dialog_finished

# ── 設計常數 ──────────────────────────────────────────────────
const VIEWPORT_W := 856.0
const VIEWPORT_H := 1024.0

# 立繪尺寸與位置
const PORTRAIT_SCALE := 7.2            # 原始小圖放大倍率（4.0 × 1.8）
const PORTRAIT_Y := 540.0              # 立繪頂端 Y（往下移：底部約 1/3 被對話框遮住）
const LEFT_X := 55.0                   # 左側立繪 X (40 + 15)
const RIGHT_X := 535.0                 # 右側立繪 X (520 + 15)
const SLIDE_OFFSET := 350.0            # 滑入/滑出偏移量

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
const PANEL_HEIGHT := 220.0
const PANEL_MARGIN := 24.0
const NAME_FONT_SIZE := 22
const TEXT_FONT_SIZE := 20

# 音樂淡入淡出
const BGM_FADE_DUR := 0.8

# Skip 自動推進
const SKIP_INTERVAL := 0.1
const FONT_PATH := "res://assets/fonts/RussoOne-Regular.ttf"

# 角色名稱對照表（雙語）
const CHAR_NAMES := {
	"husky":   { "zh": "哈士奇老師", "en": "Prof. Husky" },
	"fox":     { "zh": "小狐",       "en": "Fox" },
	"polar":   { "zh": "白熊",       "en": "Polar" },
	"raccoon": { "zh": "小浣",       "en": "Raccoon" },
	"boar":    { "zh": "山豬",       "en": "Boar" },
	"panda":   { "zh": "熊貓",       "en": "Panda" },
	"dragon":  { "zh": "小龍",       "en": "Dragon" },
	"shark":   { "zh": "鯊鯊",       "en": "Shark" },
}

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
var _typing: bool = false
var _type_tween: Tween = null
var _texture_cache: Dictionary = {}  # path -> Texture2D
var _auto_skipping: bool = false
var _skip_timer: Timer = null


func _ready() -> void:
	_build_ui()
	_tap_zone.pressed.connect(_advance)
	# 從準備畫面淡入
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null:
		gs.fade_in_if_pending(0.4)
	# 漸隱前一場景的 BGM（例如地圖音樂）
	if gs != null:
		gs.fade_out_bgm(0.4)
	# 獨立場景模式：自動讀取 GameState 的對話資料並播放
	if gs != null and gs.selected_stage != null and gs.selected_stage.pre_dialog != null:
		start(gs.selected_stage.pre_dialog)


# ── 公開 API ─────────────────────────────────────────────────

## 開始播放對話序列
func start(sequence: _DialogSequence) -> void:
	_sequence = sequence
	_line_index = -1
	_left_char_id = ""
	_right_char_id = ""
	_set_auto_skip(false)
	_portrait_left.visible = false
	_portrait_right.visible = false

	# 設定背景圖
	if sequence.background != null:
		_bg_rect.texture = sequence.background
		_bg_rect.visible = true
		_bg_color.visible = false
	else:
		_bg_rect.visible = false
		_bg_color.visible = true

	_advance()


# ── UI 建構 ──────────────────────────────────────────────────

func _build_ui() -> void:
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
	_bg_rect.custom_minimum_size = Vector2(VIEWPORT_W, VIEWPORT_H)
	_bg_rect.size = Vector2(VIEWPORT_W, VIEWPORT_H)
	_bg_rect.visible = false
	_bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg_rect)

	# 半透明暗化層（讓立繪和文字更清晰）
	var dim_overlay := ColorRect.new()
	dim_overlay.color = Color(0, 0, 0, 0.3)
	dim_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim_overlay)

	# 立繪尺寸（以放大倍率擴張 rect，避免 squeeze bounce 重設 transform.scale 影響大小）
	var p_w: float = 300.0 * (PORTRAIT_SCALE / 4.0)
	var p_h: float = 400.0 * (PORTRAIT_SCALE / 4.0)

	# 左側立繪
	_portrait_left = TextureRect.new()
	_portrait_left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_left.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_left.custom_minimum_size = Vector2(p_w, p_h)
	_portrait_left.size = Vector2(p_w, p_h)
	_portrait_left.position = Vector2(LEFT_X - (p_w - 300.0) * 0.5 - 50.0, PORTRAIT_Y - (p_h - 400.0))
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
	_portrait_right.position = Vector2(RIGHT_X - (p_w - 300.0) * 0.5 - 30.0, PORTRAIT_Y - (p_h - 400.0))
	_portrait_right.set_meta("home_x", _portrait_right.position.x)
	_portrait_right.visible = false
	_portrait_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait_right)

	# 對話框面板
	_dialog_panel = PanelContainer.new()
	_dialog_panel.position = Vector2(0, VIEWPORT_H - PANEL_HEIGHT)
	_dialog_panel.size = Vector2(VIEWPORT_W, PANEL_HEIGHT)
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

	# 角色名稱
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", NAME_FONT_SIZE)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_name_label.add_theme_constant_override("outline_size", 3)
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_name_label)

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
	_text_label.custom_minimum_size = Vector2(VIEWPORT_W - PANEL_MARGIN * 2, 0)
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

	# Skip 按鈕（右上角）
	_skip_btn = Button.new()
	_skip_btn.text = Locale.tr_ui("SKIP")
	_skip_btn.focus_mode = Control.FOCUS_NONE
	_skip_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	var skip_font: Font = load(FONT_PATH)
	if skip_font != null:
		_skip_btn.add_theme_font_override("font", skip_font)
	_skip_btn.add_theme_font_size_override("font_size", 22)
	_skip_btn.add_theme_color_override("font_color", Color.WHITE)
	_skip_btn.add_theme_color_override("font_color_hover", Color(1.0, 0.95, 0.5))
	_skip_btn.add_theme_color_override("font_color_pressed", Color(1.0, 0.85, 0.3))
	_skip_btn.add_theme_color_override("font_outline_color", Color.BLACK)
	_skip_btn.add_theme_constant_override("outline_size", 4)
	_skip_btn.add_theme_constant_override("shadow_offset_x", 2)
	_skip_btn.add_theme_constant_override("shadow_offset_y", 2)
	_skip_btn.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	var skip_empty := StyleBoxEmpty.new()
	_skip_btn.add_theme_stylebox_override("normal", skip_empty)
	_skip_btn.add_theme_stylebox_override("hover", skip_empty)
	_skip_btn.add_theme_stylebox_override("pressed", skip_empty)
	_skip_btn.add_theme_stylebox_override("focus", skip_empty)
	_skip_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip_btn.offset_left = -110.0
	_skip_btn.offset_top = VIEWPORT_H - PANEL_HEIGHT + 10.0
	_skip_btn.offset_right = -16.0
	_skip_btn.offset_bottom = VIEWPORT_H - PANEL_HEIGHT + 50.0
	_skip_btn.pressed.connect(_on_skip_pressed)
	add_child(_skip_btn)

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
	var is_left: bool = line.position == "left"
	var portrait: TextureRect = _portrait_left if is_left else _portrait_right
	var other_portrait: TextureRect = _portrait_right if is_left else _portrait_left

	# ── 音樂切換 ──
	if line.music != null:
		_change_bgm(line.music)

	# ── 旁白行（無角色）──
	if char_id.is_empty():
		_set_portrait_dim(_portrait_left, true)
		_set_portrait_dim(_portrait_right, true)
		_name_label.text = ""
	else:
		# ── 處理動作：enter / exit ──
		if line.action == "enter":
			_do_enter(char_id, line.emotion, is_left, portrait)
		elif line.action == "exit":
			_do_exit(is_left, portrait)
		else:
			_update_portrait_texture(portrait, char_id, line.emotion, is_left)

		# 更新角色追蹤
		if is_left:
			if line.action != "exit":
				_left_char_id = char_id
			else:
				_left_char_id = ""
		else:
			if line.action != "exit":
				_right_char_id = char_id
			else:
				_right_char_id = ""

		# ── 說話者高亮 / 非說話者暗化 ──
		if line.action != "exit":
			_set_portrait_dim(portrait, false)
			_set_portrait_dim(other_portrait, true)
		else:
			_set_portrait_dim(portrait, true)

		# ── 擠壓彈跳說話動畫 ──
		if line.shake and line.action != "exit" and portrait.visible:
			_play_squeeze_bounce(portrait)

		# ── 名稱 ──
		var locale_node: Node = get_node_or_null("/root/Locale")
		var cur_locale: String = locale_node.current_locale if locale_node != null else "zh"
		var name_entry: Dictionary = CHAR_NAMES.get(char_id, {})
		_name_label.text = name_entry.get(cur_locale, char_id.capitalize())
		var name_color: Color = CHAR_NAME_COLORS.get(char_id, Color(1.0, 0.92, 0.5))
		_name_label.add_theme_color_override("font_color", name_color)

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
	overlay.z_index = 100
	add_child(overlay)

	var tw := create_tween()
	tw.tween_property(overlay, "color:a", 1.0, 0.5)
	tw.tween_callback(func() -> void:
		dialog_finished.emit()
		get_tree().change_scene_to_file("res://scenes/main.tscn")
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

func _do_enter(char_id: String, emotion: String, is_left: bool, portrait: TextureRect) -> void:
	# 如果同側已有不同角色，先快速滑出
	var current_id: String = _left_char_id if is_left else _right_char_id
	if not current_id.is_empty() and current_id != char_id:
		_do_instant_exit(is_left, portrait)

	_update_portrait_texture(portrait, char_id, emotion, is_left)
	portrait.visible = true
	portrait.modulate = ACTIVE_COLOR

	# 從螢幕外滑入
	var target_x: float = portrait.get_meta("home_x", LEFT_X if is_left else RIGHT_X)
	var start_x: float = target_x - SLIDE_OFFSET if is_left else target_x + SLIDE_OFFSET
	portrait.position.x = start_x
	var tw := create_tween()
	tw.tween_property(portrait, "position:x", target_x, SLIDE_IN_DUR) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)


func _do_exit(is_left: bool, portrait: TextureRect) -> void:
	if not portrait.visible:
		return
	var target_x: float = portrait.position.x - SLIDE_OFFSET if is_left else portrait.position.x + SLIDE_OFFSET
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
	portrait.position.x = portrait.get_meta("home_x", LEFT_X if is_left else RIGHT_X)


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


func _play_squeeze_bounce(portrait: TextureRect) -> void:
	# 設定 pivot 到底部中心（立繪從底部擠壓）
	portrait.pivot_offset = Vector2(portrait.size.x * 0.5, portrait.size.y)

	var t: float = SQUEEZE_DUR
	var tw := create_tween()
	# 擠壓（壓扁）
	tw.tween_property(portrait, "scale", Vector2(1.06, 0.92), t * 0.3) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	# 彈起（拉長）
	tw.tween_property(portrait, "scale", Vector2(0.95, 1.08), t * 0.35) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	# 回歸
	tw.tween_property(portrait, "scale", Vector2(1.0, 1.0), t * 0.35) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_QUAD)
