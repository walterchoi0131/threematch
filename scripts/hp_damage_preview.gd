## HpDamagePreview — HP 受擊白條共用工具。
## 在 fill 父層放置一個白色 ColorRect，左右兩端依 padding 補償公式對齊
## fill 的可視區域；停留 0.45s 後右邊崩塌至 new_ratio。
class_name HpDamagePreview
extends RefCounted

const _COLOR := Color(1, 1, 1, 0.85)
const _HOLD_TIME := 0.45
const _COLLAPSE_TIME := 0.35


## 在 fill 對應的 HP 條上播放受擊預覽。
## prev_ratio：受擊前的 HP 比例；new_ratio：受擊後的 HP 比例。
static func show(fill: Control, prev_ratio: float, new_ratio: float) -> void:
	if fill == null or prev_ratio <= new_ratio:
		return
	var parent: Control = fill.get_parent() as Control
	if parent == null:
		return
	var old: Node = parent.get_node_or_null("DmgPreview")
	if old != null:
		old.queue_free()

	var pad_l: float = max(0.0, fill.offset_left)
	var pad_r: float = max(0.0, -fill.offset_right)

	var preview := ColorRect.new()
	preview.name = "DmgPreview"
	preview.color = _COLOR
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.anchor_top = 0.0
	preview.anchor_bottom = 1.0
	preview.offset_top = fill.offset_top
	preview.offset_bottom = fill.offset_bottom
	# 左邊鎖在 new_ratio 對應位置（含 padding 補償），不再變動
	preview.anchor_left = new_ratio
	preview.offset_left = _edge_offset(new_ratio, pad_l, pad_r)
	# 右邊起始於 prev_ratio
	preview.anchor_right = prev_ratio
	preview.offset_right = _edge_offset(prev_ratio, pad_l, pad_r)
	parent.add_child(preview)

	# 先停留再崩塌右邊到 new_ratio（同時 tween anchor_right 與 offset_right）
	var tw := preview.create_tween()
	tw.tween_interval(_HOLD_TIME)
	tw.tween_method(
		func(r: float) -> void:
			if not is_instance_valid(preview):
				return
			preview.anchor_right = r
			preview.offset_right = _edge_offset(r, pad_l, pad_r),
		prev_ratio, new_ratio, _COLLAPSE_TIME
	).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(preview.queue_free)


## 在父容器寬 W 內，將某 ratio 對應到「fill 內框」的邊界 X：
##   X = pad_l + ratio * (W - pad_l - pad_r)
## 而 anchor 帶來的位移為 ratio * W，因此補償 offset 為 X - ratio * W：
##   offset = pad_l - (pad_l + pad_r) * ratio
static func _edge_offset(ratio: float, pad_l: float, pad_r: float) -> float:
	return pad_l - (pad_l + pad_r) * ratio
