## BattleDialog — 戰鬥中緊湊型對話面板。
## 覆蓋角色列區域，顯示小頭像 + 名字 + 打字機文字。
## 點擊推進對話，播完發出 all_lines_finished 信號。
extends Control

const _DialogLine := preload("res://scripts/dialog_line.gd")

signal all_lines_finished

# ── 設計常數 ──────────────────────────────────────────────────
const TYPEWRITER_CPS := 30.0
const PORTRAIT_SIZE := 80.0
const PANEL_MARGIN := 16.0

# 角色名稱（雙語）
const CHAR_NAMES := {
	"husky":   { "zh": "哈士奇老師", "en": "Prof. Husky" },
	"fox":     { "zh": "小狐",       "en": "Fox" },
	"polar":   { "zh": "白熊",       "en": "Polar" },
	"raccoon": { "zh": "小浣",       "en": "Raccoon" },
	"boar":    { "zh": "山豬",       "en": "Boar" },
	"panda":   { "zh": "熊貓",       "en": "Panda" },
}

const CHAR_NAME_COLORS := {
	"husky":   Color(1.0, 0.92, 0.5),
	"fox":     Color(1.0, 0.55, 0.35),
	"polar":   Color(0.6, 0.82, 1.0),
	"raccoon": Color(0.55, 0.9, 0.5),
	"boar":    Color(0.45, 0.7, 1.0),
	"panda":   Color(0.55, 0.9, 0.5),
}

# ── 節點 ─────────────────────────────────────────────────────
var _overlay: ColorRect
var _panel: PanelContainer
var _portrait: TextureRect
var _name_label: Label
var _text_label: RichTextLabel
var _tap_zone: Button

# ── 狀態 ─────────────────────────────────────────────────────
var _lines: Array = []
var _line_index: int = -1
var _typing: bool = false
var _type_tween: Tween = null
var _texture_cache: Dictionary = {}


func _ready() -> void:
	_build_ui()
	_tap_zone.pressed.connect(_advance)
	visible = false


# ── 公開 API ─────────────────────────────────────────────────

## 顯示一組對話行（播完後自動隱藏並發出信號）
func show_lines(lines: Array) -> void:
	_lines = lines
	_line_index = -1
	visible = true
	_advance()


# ── UI 建構 ──────────────────────────────────────────────────

func _build_ui() -> void:
	# 全螢幕暗色覆蓋層（對話期間擋住所有互動）
	_overlay = ColorRect.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.color = Color(0, 0, 0, 0.65)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	# 對話面板（定位在畫面底部角色列區域）
	_panel = PanelContainer.new()
	_panel.offset_left = 16.0
	_panel.offset_top = 845.0
	_panel.offset_right = 840.0
	_panel.offset_bottom = 1010.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.12, 0.94)
	style.border_color = Color(0.35, 0.35, 0.5, 0.5)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = PANEL_MARGIN
	style.content_margin_right = PANEL_MARGIN
	style.content_margin_top = PANEL_MARGIN * 0.5
	style.content_margin_bottom = PANEL_MARGIN * 0.5
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	_panel.add_child(hbox)

	# 頭像
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	hbox.add_child(_portrait)

	# 右側文字區
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	hbox.add_child(vbox)

	# 名稱
	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 18)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_name_label.add_theme_constant_override("outline_size", 2)
	vbox.add_child(_name_label)

	# 對話文字
	_text_label = RichTextLabel.new()
	_text_label.bbcode_enabled = true
	_text_label.fit_content = true
	_text_label.scroll_active = false
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_font_size_override("normal_font_size", 17)
	_text_label.add_theme_color_override("default_color", Color.WHITE)
	vbox.add_child(_text_label)

	# 全區域點擊
	_tap_zone = Button.new()
	_tap_zone.flat = true
	_tap_zone.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tap_zone.mouse_filter = Control.MOUSE_FILTER_STOP
	var empty := StyleBoxEmpty.new()
	_tap_zone.add_theme_stylebox_override("normal", empty)
	_tap_zone.add_theme_stylebox_override("hover", empty)
	_tap_zone.add_theme_stylebox_override("pressed", empty)
	_tap_zone.add_theme_stylebox_override("focus", empty)
	add_child(_tap_zone)


# ── 對話推進 ─────────────────────────────────────────────────

func _advance() -> void:
	if _typing:
		_finish_typing()
		return

	_line_index += 1
	if _line_index >= _lines.size():
		visible = false
		all_lines_finished.emit()
		return

	var line: _DialogLine = _lines[_line_index]
	_show_line(line)


func _show_line(line: _DialogLine) -> void:
	var char_id: String = line.character_id

	# 頭像
	var tex: Texture2D = _load_portrait(char_id, line.emotion)
	if tex != null:
		_portrait.texture = tex
		_portrait.visible = true
	else:
		_portrait.visible = false

	# 名稱
	var locale_node: Node = get_node_or_null("/root/Locale")
	var cur_locale: String = locale_node.current_locale if locale_node != null else "zh"

	if char_id.is_empty():
		_name_label.text = ""
	else:
		var name_entry: Dictionary = CHAR_NAMES.get(char_id, {})
		_name_label.text = name_entry.get(cur_locale, char_id.capitalize())
		var name_color: Color = CHAR_NAME_COLORS.get(char_id, Color(1.0, 0.92, 0.5))
		_name_label.add_theme_color_override("font_color", name_color)

	# 打字機
	var dialog_text: String
	if locale_node != null:
		dialog_text = locale_node.get_dialog_text(line)
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
	_type_tween.tween_callback(func() -> void: _typing = false)


func _finish_typing() -> void:
	if _type_tween != null and _type_tween.is_valid():
		_type_tween.kill()
	_text_label.visible_ratio = 1.0
	_typing = false


func _load_portrait(char_id: String, emotion: String) -> Texture2D:
	if char_id.is_empty():
		return null
	if emotion != "normal" and not emotion.is_empty():
		var p := "res://assets/characters/%s_%s.png" % [char_id, emotion]
		if _texture_cache.has(p):
			return _texture_cache[p]
		if ResourceLoader.exists(p):
			var t: Texture2D = load(p)
			_texture_cache[p] = t
			return t
	var dp := "res://assets/%s.png" % char_id
	if _texture_cache.has(dp):
		return _texture_cache[dp]
	if ResourceLoader.exists(dp):
		var t: Texture2D = load(dp)
		_texture_cache[dp] = t
		return t
	return null
