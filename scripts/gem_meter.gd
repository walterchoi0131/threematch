## GemMeter — 顯示本回合各類寶石的消除累積數量。
## 依 battle_manager.turn_gem_blasts + pending_skill_blasts 合併後重建子節點。
## 每個寶石類型以「一堆寶石圖示」呈現（最多 MAX_VISIBLE_ICONS 個重疊），
## 並在中央覆蓋一個白字 xN 標籤。
class_name GemMeter
extends HBoxContainer

const ICON_SIZE := Vector2(36, 36)
const PILE_OVERLAP := 0.55  # 相鄰圖示重疊比例（0~1，越大越擠）
const MAX_VISIBLE_ICONS := 6

# 顯示順序（其它類型若出現會附在後面）
const DISPLAY_ORDER: Array[int] = [
	Block.Type.RED, Block.Type.BLUE, Block.Type.GREEN, Block.Type.LIGHT,
	Block.Type.DARK,
]


func _ready() -> void:
	add_theme_constant_override("separation", 12)


## 重建顯示。counts: Block.Type -> int
func refresh(counts: Dictionary) -> void:
	for child in get_children():
		child.queue_free()

	var ordered: Array[int] = []
	for t in DISPLAY_ORDER:
		if int(counts.get(t, 0)) > 0:
			ordered.append(t)
	# 把不在預設順序裡的也加進來
	for k in counts.keys():
		var ti: int = int(k)
		if int(counts[k]) > 0 and not ordered.has(ti) and Block.is_valid_type_value(ti) and ti != Block.Type.PLANK and ti != Block.Type.ROCK:
			ordered.append(ti)

	for t in ordered:
		var n: int = int(counts[t])
		add_child(_make_entry(t as Block.Type, n))


## 為某一類型 gem_type、count 數量建立一個堆疊圖示 + 中央 xN 的 Control。
func _make_entry(gem_type: Block.Type, count: int) -> Control:
	var visible_n: int = clampi(count, 1, MAX_VISIBLE_ICONS)
	var step: float = ICON_SIZE.x * (1.0 - PILE_OVERLAP)
	var total_w: float = ICON_SIZE.x + step * float(visible_n - 1)

	var box := Control.new()
	box.custom_minimum_size = Vector2(total_w, ICON_SIZE.y)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var has_tex: bool = Block.GEM_TEXTURES.has(gem_type)
	for i in visible_n:
		if has_tex:
			var icon := TextureRect.new()
			icon.size = ICON_SIZE
			icon.position = Vector2(step * float(i), 0.0)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			icon.texture = Block.GEM_TEXTURES[gem_type]
			box.add_child(icon)
		else:
			var fallback := ColorRect.new()
			fallback.size = ICON_SIZE
			fallback.position = Vector2(step * float(i), 0.0)
			fallback.color = Block.COLORS.get(gem_type, Color.WHITE)
			fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
			box.add_child(fallback)

	# 中央覆蓋 數量標籤（只顯示數字，不加 x）
	var label := Label.new()
	label.text = "%d" % count
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.add_theme_font_size_override("font_size", 22)
	label.z_index = 10
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(label)

	return box
