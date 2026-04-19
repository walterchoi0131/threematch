## BlastVfx — 通用高階寶石爆炸 VFX 播放器（fire-and-forget）。
## 以 sprite sheet 逐幀動畫顯示爆炸特效，播完自動銷毀。
class_name BlastVfx
extends Node2D


## 在 parent 節點上的 global_pos 位置播放爆炸 VFX。
## 若該高階寶石定義無 VFX（blast_vfx_path 為空），則不做任何事。
static func play(parent: Node, global_pos: Vector2, ut: Block.UpperType) -> void:
	var def: UpperGemDefs.Def = UpperGemDefs.get_def(ut)
	if def == null or def.blast_vfx_path.is_empty() or def.blast_vfx_frames <= 0:
		return

	var tex: Texture2D = load(def.blast_vfx_path) as Texture2D
	if tex == null:
		return

	var node := BlastVfx.new()
	node.z_index = 20
	parent.add_child(node)
	node.global_position = global_pos
	node._play_sheet(tex, def)


## 內部：逐幀播放 sprite sheet 並在結束後銷毀自身
func _play_sheet(tex: Texture2D, def: UpperGemDefs.Def) -> void:
	var cols: int = def.blast_vfx_cols
	var rows: int = def.blast_vfx_rows
	var total_frames: int = def.blast_vfx_frames
	var frame_w: float = float(tex.get_width()) / cols
	var frame_h: float = float(tex.get_height()) / rows

	var sprite := Sprite2D.new()
	sprite.centered = true
	sprite.scale = Vector2(def.blast_vfx_scale, def.blast_vfx_scale)
	add_child(sprite)

	for i in total_frames:
		var col: int = i % cols
		var row: int = i / cols
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h)
		sprite.texture = atlas
		if i < total_frames - 1:
			await get_tree().create_timer(def.blast_vfx_speed).timeout

	# 最後一幀短暫淡出後銷毀
	var fade := create_tween()
	fade.tween_property(sprite, "modulate:a", 0.0, 0.05)
	fade.tween_callback(queue_free)
