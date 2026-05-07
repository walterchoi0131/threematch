## PortraitDebugScreen — 頭像偏移/縮放全局調試介面。
## 4 欄各自模擬真實遊戲場景（寬度跟随 viewport）：
##   0 = Battle Panel  (portrait_scale / portrait_offset)   → 4 張卡片底部列
##   1 = Square Card   (square_scale   / square_offset)     → 7 欄角色格（VP_W/7 每格）
##   2 = Result Row    (rectangular_scale / rectangular_offset) → 戰鬥結算列
##   3 = Dialog Box    (dialog_square_scale / dialog_square_offset) → 對話框底部
## 拖拽 = 調整 Offset，滚輪 = 調整 Scale。Save 按鈕寫回 .tres。
extends Control

const _SCALE_STEP: float    = 0.05
const _RECT_IMG_SIZE: float = 1200.0  # battle_result 使用 300×4
## 遊戲 viewport 實際寬度（由 ViewportUtils.get_size().x 動態設定，預設等於專案基準 720px）
var _VP_W: float = 720.0

## [scale_prop, offset_prop, column_label]
const _SYS: Array = [
	["portrait_scale",      "portrait_offset",      "Battle Panel"],
	["square_scale",        "square_offset",        "Square Card"],
	["rectangular_scale",   "rectangular_offset",   "Result Row"],
	["dialog_square_scale", "dialog_square_offset", "Dialog Box"],
]

var _char_data: CharacterData = null

## 每欄的「576px 寬場景容器」節點 — rebuild 時清空並填入
var _scene_nodes: Array[Control] = []
## 每欄場景容器的父級 wrapper（用於接收 resized 後更新 scale）
var _wrappers: Array[Control]    = []
## TextureRect（或 null）for each preview card
var _portraits: Array            = []   # untyped: TextureRect or null
## 是否用 anchor offset 定位（rectangular），否則用 .position
var _is_rect: Array[bool]        = [false, false, true, false]

var _scale_lbls: Array[Label]         = []
var _offset_lbls: Array[Label]        = []
var _drag_active: Array[bool]         = [false, false, false, false]
var _drag_start_mouse: Array[Vector2] = []
var _drag_start_offset: Array[Vector2] = []
var _char_btns: Array[Button]         = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	for _i: int in 4:
		_drag_start_mouse.append(Vector2.ZERO)
		_drag_start_offset.append(Vector2.ZERO)
		_portraits.append(null)
	_build()


func _build() -> void:
	_VP_W = ViewportUtils.get_size().x
	# ── 背景 ──
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.09, 0.97)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# ── 頂部工具列 ──
	var top_bar := HBoxContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_bottom = 52.0
	top_bar.add_theme_constant_override("separation", 8)
	add_child(top_bar)

	var pad_l := Control.new()
	pad_l.custom_minimum_size = Vector2(12, 1)
	pad_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(pad_l)

	var title_lbl := Label.new()
	title_lbl.text = "Portrait Debug"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(title_lbl)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.add_theme_font_size_override("font_size", 16)
	save_btn.custom_minimum_size = Vector2(74, 40)
	save_btn.pressed.connect(_save)
	top_bar.add_child(save_btn)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.custom_minimum_size = Vector2(44, 40)
	close_btn.pressed.connect(queue_free)
	top_bar.add_child(close_btn)

	var pad_r := Control.new()
	pad_r.custom_minimum_size = Vector2(12, 1)
	pad_r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(pad_r)

	# ── 主體 VBox（top_bar 之下） ──
	var main_vbox := VBoxContainer.new()
	main_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_vbox.offset_top = 52.0
	main_vbox.add_theme_constant_override("separation", 0)
	add_child(main_vbox)

	# 4 列預覽區（垂直排列，可滾動）
	var preview_scroll := ScrollContainer.new()
	preview_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	preview_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	preview_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_AUTO
	main_vbox.add_child(preview_scroll)

	var preview_vbox := VBoxContainer.new()
	preview_vbox.add_theme_constant_override("separation", 4)
	preview_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preview_scroll.add_child(preview_vbox)

	for i: int in 4:
		_build_preview_col(preview_vbox, i)

	# 分割線
	var divider := ColorRect.new()
	divider.color = Color(0.28, 0.28, 0.35, 1.0)
	divider.custom_minimum_size = Vector2(0, 2)
	main_vbox.add_child(divider)

	# ── 底部角色列表 ──
	var char_scroll := ScrollContainer.new()
	char_scroll.custom_minimum_size = Vector2(0, 140)
	char_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	char_scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_DISABLED
	main_vbox.add_child(char_scroll)

	var char_row := HBoxContainer.new()
	char_row.add_theme_constant_override("separation", 6)
	char_scroll.add_child(char_row)

	var cl_pad := Control.new()
	cl_pad.custom_minimum_size = Vector2(8, 1)
	cl_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	char_row.add_child(cl_pad)

	var chars: Array[CharacterData] = GameState.owned_characters
	for i: int in chars.size():
		_build_char_btn(char_row, chars[i], i)

	if chars.size() > 0:
		_select_char(0)


# ─────────────────────────────────────────────────────────────
# 建立單列（垂直堆疊）：左側資訊欄 + 右側場景預覽
# ─────────────────────────────────────────────────────────────
func _build_preview_col(parent: VBoxContainer, sys_idx: int) -> void:
	# 分隔線（第一個之外都加，在 row 之前插入）
	if sys_idx > 0:
		var div := ColorRect.new()
		div.color = Color(0.25, 0.26, 0.33, 1.0)
		div.custom_minimum_size = Vector2(0, 1)
		div.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		parent.add_child(div)

	# 每個場景項目是一個 HBoxContainer：左邊資訊 + 右邊預覽
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.custom_minimum_size   = Vector2(0.0, 180.0)
	parent.add_child(row)

	# ── 左側資訊欄 ──
	var info_vbox := VBoxContainer.new()
	info_vbox.custom_minimum_size   = Vector2(90.0, 0.0)
	info_vbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	info_vbox.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	info_vbox.add_theme_constant_override("separation", 6)
	info_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(info_vbox)

	var sys_lbl := Label.new()
	sys_lbl.text = _SYS[sys_idx][2] as String
	sys_lbl.add_theme_font_size_override("font_size", 13)
	sys_lbl.add_theme_color_override("font_color", Color(0.72, 0.88, 1.0))
	sys_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sys_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(sys_lbl)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(spacer)

	var scale_lbl := Label.new()
	scale_lbl.text = "Scale: 1.00"
	scale_lbl.add_theme_font_size_override("font_size", 12)
	scale_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	scale_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(scale_lbl)
	_scale_lbls.append(scale_lbl)

	var offset_lbl := Label.new()
	offset_lbl.text = "(0, 0)"
	offset_lbl.add_theme_font_size_override("font_size", 11)
	offset_lbl.add_theme_color_override("font_color", Color(0.75, 0.78, 0.88))
	offset_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info_vbox.add_child(offset_lbl)
	_offset_lbls.append(offset_lbl)

	# ── 右側場景預覽 clip wrapper ──
	var wrapper := Control.new()
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN  # 高度由 custom_minimum_size 決定
	wrapper.clip_contents = true
	row.add_child(wrapper)
	_wrappers.append(wrapper)

	var clip_bg := ColorRect.new()
	clip_bg.color = Color(0.08, 0.09, 0.14, 1.0)
	clip_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_child(clip_bg)

	var scene := Control.new()
	scene.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.size = Vector2(_VP_W, 200.0)  # rebuild 時重設
	wrapper.add_child(scene)
	_scene_nodes.append(scene)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var captured: int = sys_idx
	overlay.gui_input.connect(func(ev: InputEvent) -> void:
		_on_preview_input(ev, captured)
	)
	wrapper.add_child(overlay)


# ─────────────────────────────────────────────────────────────
# 場景不縮放 — 1:1 遊戲像素，讓 wrapper 高度跟隨場景高度
# ─────────────────────────────────────────────────────────────
func _fit_scene_to_wrapper(idx: int) -> void:
	var wrapper: Control = _wrappers[idx]
	var scene: Control   = _scene_nodes[idx]
	scene.scale    = Vector2.ONE
	scene.position = Vector2.ZERO
	# wrapper 高度 = 場景高度，讓外層 HBox row 正確撐開
	wrapper.custom_minimum_size = Vector2(0.0, scene.size.y)


# ─────────────────────────────────────────────────────────────
# 重建單欄的場景內容（切角色後呼叫）
# ─────────────────────────────────────────────────────────────
func _rebuild_preview(idx: int) -> void:
	if _char_data == null:
		return
	var scene: Control = _scene_nodes[idx]
	# 清空舊內容
	for child: Node in scene.get_children():
		child.queue_free()

	var portrait_ref: TextureRect = null
	# 各場景高度 = 遊戲實際像素（不縮放）
	# Battle: CharacterRow offset_top=-200 → offset_bottom=-140 → 高度 60px
	# Square: VP_W / 7 ≈ 82px（同 characters_screen / prepare_screen 公式）
	var cell: float = _VP_W / 7.0
	var scene_heights: Array[float] = [60.0, cell, 240.0, 190.0]
	var scene_h: float = scene_heights[idx]

	match idx:
		0:
			portrait_ref = _build_scene_battle(scene, scene_h)
		1:
			portrait_ref = _build_scene_square(scene, scene_h)
		2:
			portrait_ref = _build_scene_result(scene, scene_h)
		3:
			portrait_ref = _build_scene_dialog(scene, scene_h)

	scene.size = Vector2(_VP_W, scene_h)
	_portraits[idx] = portrait_ref
	_fit_scene_to_wrapper(idx)
	_refresh_preview(idx)


# ─────────────────────────────────────────────────────────────
# 場景 0：Battle Panel — 4 張卡片水平列（與 CharacterPanel 完全同尺寸）
# CharacterRow: anchor_bottom=1, offset_top=-200, offset_bottom=-140 → 高度 60px
# card_w = VP_W / 4 ≈ 144px，card_h = 60px
# ─────────────────────────────────────────────────────────────
func _build_scene_battle(scene: Control, scene_h: float) -> TextureRect:
	const N_CARDS: int = 4
	var card_w: float = _VP_W / float(N_CARDS)   # 同遊戲：576 / 4 = 144px

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.12, 1.0)
	bg.size = Vector2(_VP_W, scene_h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(bg)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 0)
	hbox.position = Vector2(0.0, 0.0)
	hbox.size      = Vector2(_VP_W, scene_h)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(hbox)

	var chars: Array[CharacterData] = GameState.owned_characters
	var target_idx: int = GameState.owned_characters.find(_char_data)
	var portrait_ref: TextureRect = null

	for i: int in N_CARDS:
		# 目標角色放第 0 張，其餘依序填入其他角色作為背景
		var c: CharacterData
		var is_target: bool = (i == 0)
		if i == 0:
			c = _char_data
		else:
			var ci: int = (target_idx + i) % maxi(chars.size(), 1)
			c = chars[ci] if ci < chars.size() else _char_data

		var result: Dictionary = CharacterCard.make_battle(c)
		var card: PanelContainer = result.panel as PanelContainer
		card.custom_minimum_size = Vector2(card_w, scene_h)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(card)

		if is_target and result.portrait != null:
			portrait_ref = result.portrait as TextureRect

	return portrait_ref


# ─────────────────────────────────────────────────────────────
# 場景 1：Square Card — 單張顯示（1 格，cell = VP_W/7 ≈ 82px）
# 只顯示目標角色，方便觀察頭像裁切框
# ─────────────────────────────────────────────────────────────
func _build_scene_square(scene: Control, scene_h: float) -> TextureRect:
	var cell: float = scene_h  # scene_h 已由 _rebuild_preview 設為 _VP_W / 7 ≈ 82px

	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.14, 0.22, 1.0)
	bg.size = Vector2(_VP_W, cell)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(bg)

	var result: Dictionary = CharacterCard.make_square(_char_data)
	var card: PanelContainer = result.panel as PanelContainer
	card.custom_minimum_size = Vector2(cell, cell)
	card.size = Vector2(cell, cell)
	card.position = Vector2.ZERO
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(card)

	var portrait_ref: TextureRect = null
	if result.portrait != null:
		portrait_ref = result.portrait as TextureRect
		# 高亮外框
		var hl := Panel.new()
		var hl_s := StyleBoxFlat.new()
		hl_s.draw_center = false
		hl_s.border_color = Color(1.0, 0.85, 0.2)
		hl_s.set_border_width_all(3)
		hl_s.set_corner_radius_all(10)
		hl.add_theme_stylebox_override("panel", hl_s)
		hl.set_anchors_preset(Control.PRESET_FULL_RECT)
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(hl)

	return portrait_ref


# ─────────────────────────────────────────────────────────────
# 場景 2：Result Row — 戰鬥結算列（矩形頭像底-左錨定）
# ROW_H = 96px + 8px padding，與 battle_result.gd 完全一致
# ─────────────────────────────────────────────────────────────
func _build_scene_result(scene: Control, scene_h: float) -> TextureRect:
	const ROW_H: float = 96.0
	const ROW_TOTAL: float = ROW_H + 8.0   # 104px per row（content margin 6*2 + ROW_H）
	const SIDE: float  = 12.0
	var ROW_W: float = _VP_W - SIDE * 2.0

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.14, 1.0)
	bg.size = Vector2(_VP_W, scene_h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(bg)

	var chars: Array[CharacterData] = GameState.owned_characters
	var target_idx: int = GameState.owned_characters.find(_char_data)
	# 顯示 2 列：目標角色在第 0 列，另一個角色作背景
	const N_ROWS: int = 2
	var portrait_ref: TextureRect = null

	for ri: int in N_ROWS:
		var is_target: bool = (ri == 0)
		var ci: int = (target_idx + ri) % maxi(chars.size(), 1)
		var c: CharacterData = _char_data if is_target else (chars[ci] if ci < chars.size() else _char_data)

		var row := PanelContainer.new()
		row.position = Vector2(SIDE, ri * (ROW_TOTAL + 4.0))
		row.size     = Vector2(ROW_W, ROW_TOTAL)
		var rs := StyleBoxFlat.new()
		rs.bg_color = Color(0.10, 0.12, 0.18, 1.0)
		if is_target:
			rs.bg_color = Color(0.14, 0.17, 0.28, 1.0)
		rs.set_corner_radius_all(8)
		rs.set_content_margin_all(6)
		row.add_theme_stylebox_override("panel", rs)
		row.clip_contents = true
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		scene.add_child(row)

		# HBox: placeholder + right info
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(hbox)

		var ph := Control.new()
		ph.custom_minimum_size = Vector2(ROW_TOTAL, ROW_TOTAL)
		ph.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		ph.size_flags_vertical   = Control.SIZE_SHRINK_BEGIN
		ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(ph)

		var rvb := VBoxContainer.new()
		rvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rvb.size_flags_vertical   = Control.SIZE_EXPAND_FILL
		rvb.add_theme_constant_override("separation", 4)
		rvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(rvb)

		var nl := Label.new()
		nl.text = c.character_name
		nl.add_theme_font_size_override("font_size", 18)
		nl.add_theme_color_override("font_color", Color.WHITE)
		nl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rvb.add_child(nl)

		var ll := Label.new()
		ll.text = "Lv.%d" % c.level
		ll.add_theme_font_size_override("font_size", 16)
		ll.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
		ll.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rvb.add_child(ll)

		# portrait overlay
		var po := Control.new()
		po.mouse_filter = Control.MOUSE_FILTER_IGNORE
		po.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.add_child(po)

		if c.portrait_texture != null:
			var portrait := TextureRect.new()
			portrait.texture     = c.portrait_texture
			portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
			portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
			portrait.anchor_left   = 0.0;  portrait.anchor_right  = 0.0
			portrait.anchor_top    = 1.0;  portrait.anchor_bottom = 1.0
			portrait.grow_horizontal = Control.GROW_DIRECTION_END
			portrait.grow_vertical   = Control.GROW_DIRECTION_BEGIN
			portrait.pivot_offset    = Vector2(0.0, _RECT_IMG_SIZE)
			po.add_child(portrait)
			if is_target:
				portrait_ref = portrait

		# 高亮指示
		if is_target:
			var hl_rect := ColorRect.new()
			hl_rect.color = Color(1.0, 0.85, 0.2, 0.08)
			hl_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
			hl_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(hl_rect)

	return portrait_ref


# ─────────────────────────────────────────────────────────────
# 場景 3：Dialog Box — 對話面板（PANEL_H=190px，與 battle_dialog.gd 完全一致）
# 142×142 頭像 clip，左邊接文字欄
# ─────────────────────────────────────────────────────────────
func _build_scene_dialog(scene: Control, scene_h: float) -> TextureRect:
	const PORTRAIT_SIZE: float = 142.0   # battle_dialog.gd PORTRAIT_SIZE
	const PANEL_H: float       = 190.0   # battle_dialog.gd PANEL_HEIGHT
	const MARGIN: float        = 16.0    # battle_dialog.gd PANEL_MARGIN

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.12, 1.0)
	bg.size  = Vector2(_VP_W, scene_h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(bg)

	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.06, 0.06, 0.12, 0.94)
	ps.set_corner_radius_all(6)
	ps.set_content_margin_all(MARGIN)
	panel.add_theme_stylebox_override("panel", ps)
	panel.size     = Vector2(_VP_W, PANEL_H)
	panel.position = Vector2(0.0, 0.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scene.add_child(panel)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(hbox)

	# 142×142 頭像 clip
	var clip := Control.new()
	clip.custom_minimum_size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(clip)

	var portrait_ref: TextureRect = null
	if _char_data.portrait_texture != null:
		var portrait := TextureRect.new()
		portrait.texture              = _char_data.portrait_texture
		portrait.expand_mode          = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode         = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		portrait.custom_minimum_size  = Vector2(300.0, 300.0)
		portrait.size                 = Vector2(300.0, 300.0)
		portrait.pivot_offset         = Vector2.ZERO
		portrait.mouse_filter         = Control.MOUSE_FILTER_IGNORE
		clip.add_child(portrait)
		portrait_ref = portrait

	var text_vbox := VBoxContainer.new()
	text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_vbox.add_theme_constant_override("separation", 8)
	text_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hbox.add_child(text_vbox)

	var name_lbl := Label.new()
	name_lbl.text = _char_data.character_name
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(name_lbl)

	var text_lbl := Label.new()
	text_lbl.text = "..."
	text_lbl.add_theme_font_size_override("font_size", 17)
	text_lbl.add_theme_color_override("font_color", Color.WHITE)
	text_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_lbl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	text_vbox.add_child(text_lbl)

	return portrait_ref


# ─────────────────────────────────────────────────────────────
# 工具：在 scene 上貼標籤文字
# ─────────────────────────────────────────────────────────────
func _add_label(parent: Control, text: String, x: float, y: float, font_size: int) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(x, y)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.9, 0.85))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)


# ─────────────────────────────────────────────────────────────
# 建立底部角色按鈕
# ─────────────────────────────────────────────────────────────
func _build_char_btn(parent: HBoxContainer, c: CharacterData, idx: int) -> void:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(84, 116)
	btn.clip_contents = true

	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.10, 0.11, 0.16, 1.0)
	sbox.set_corner_radius_all(6)
	sbox.set_border_width_all(2)
	sbox.border_color = Color(0.28, 0.30, 0.40, 1.0)
	btn.add_theme_stylebox_override("normal",  sbox)
	btn.add_theme_stylebox_override("hover",   sbox)
	btn.add_theme_stylebox_override("pressed", sbox)
	btn.add_theme_stylebox_override("focus",   sbox)
	parent.add_child(btn)
	_char_btns.append(btn)

	if c.portrait_texture != null:
		var tex := TextureRect.new()
		tex.texture = c.portrait_texture
		tex.set_anchors_preset(Control.PRESET_FULL_RECT)
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(tex)

	var name_bg := ColorRect.new()
	name_bg.color = Color(0, 0, 0, 0.65)
	name_bg.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_bg.offset_top = -26.0
	name_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(name_bg)

	var name_lbl := Label.new()
	name_lbl.text = c.character_name
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	name_lbl.offset_top = -24.0
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(name_lbl)

	var sel := Panel.new()
	sel.name = "SelBorder"
	var sel_style := StyleBoxFlat.new()
	sel_style.draw_center = false
	sel_style.border_color = Color(1.0, 0.85, 0.2)
	sel_style.set_border_width_all(3)
	sel_style.set_corner_radius_all(6)
	sel.add_theme_stylebox_override("panel", sel_style)
	sel.set_anchors_preset(Control.PRESET_FULL_RECT)
	sel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sel.visible = false
	btn.add_child(sel)

	var ci: int = idx
	btn.pressed.connect(func() -> void: _select_char(ci))


# ─────────────────────────────────────────────────────────────
# 邏輯
# ─────────────────────────────────────────────────────────────
func _select_char(idx: int) -> void:
	if idx < 0 or idx >= GameState.owned_characters.size():
		return
	_char_data = GameState.owned_characters[idx]
	for j: int in _char_btns.size():
		var sel: Node = _char_btns[j].get_node_or_null("SelBorder")
		if sel != null:
			(sel as Control).visible = (j == idx)
	for i: int in 4:
		_rebuild_preview(i)


func _on_preview_input(ev: InputEvent, idx: int) -> void:
	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_active[idx]       = true
				_drag_start_mouse[idx]  = mb.global_position
				_drag_start_offset[idx] = _get_offset(idx)
			else:
				_drag_active[idx] = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_set_scale(idx, snappedf(_get_scale(idx) + _SCALE_STEP, 0.001))
			_refresh_preview(idx)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_set_scale(idx, maxf(snappedf(_get_scale(idx) - _SCALE_STEP, 0.001), 0.05))
			_refresh_preview(idx)
	elif ev is InputEventMouseMotion and _drag_active[idx]:
		var mm: InputEventMouseMotion = ev as InputEventMouseMotion
		# scene は 1:1 スケールなのでマウス delta = ゲーム pixel delta
		var delta: Vector2 = mm.global_position - _drag_start_mouse[idx]
		_set_offset(idx, _drag_start_offset[idx] + delta)
		_refresh_preview(idx)


func _refresh_preview(idx: int) -> void:
	if _char_data == null:
		return
	var portrait_node = _portraits[idx]
	if portrait_node == null:
		return
	var portrait: TextureRect = portrait_node as TextureRect
	var scale_v: float    = _get_scale(idx)
	var offset_v: Vector2 = _get_offset(idx)

	if _is_rect[idx]:
		portrait.scale         = Vector2(scale_v, scale_v)
		portrait.offset_left   = 0.0             + offset_v.x
		portrait.offset_top    = -_RECT_IMG_SIZE + offset_v.y
		portrait.offset_right  = _RECT_IMG_SIZE  + offset_v.x
		portrait.offset_bottom = 0.0             + offset_v.y
	else:
		portrait.scale    = Vector2(scale_v, scale_v)
		portrait.position = offset_v

	_scale_lbls[idx].text  = "Scale: %.2f" % scale_v
	_offset_lbls[idx].text = "(%.0f, %.0f)" % [offset_v.x, offset_v.y]


func _get_scale(idx: int) -> float:
	if _char_data == null:
		return 1.0
	return _char_data.get(_SYS[idx][0]) as float


func _set_scale(idx: int, v: float) -> void:
	if _char_data == null:
		return
	_char_data.set(_SYS[idx][0], v)


func _get_offset(idx: int) -> Vector2:
	if _char_data == null:
		return Vector2.ZERO
	return _char_data.get(_SYS[idx][1]) as Vector2


func _set_offset(idx: int, v: Vector2) -> void:
	if _char_data == null:
		return
	_char_data.set(_SYS[idx][1], v)


func _save() -> void:
	if _char_data == null or _char_data.resource_path == "":
		return
	var err: int = ResourceSaver.save(_char_data, _char_data.resource_path)
	if err != OK:
		push_warning("PortraitDebugScreen: save failed for %s (err=%d)" % [_char_data.resource_path, err])
