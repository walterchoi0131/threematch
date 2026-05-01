## BlastVfx — 通用高階寶石爆炸 VFX 播放器（有池化）。
## 以 sprite sheet 逐幀動畫顯示爆炸特效。
## 依 VFX 路徑分池；超過上限時回收最舊的進行中實例，避免 GPU overdraw。
class_name BlastVfx
extends Node2D

## 每種 VFX 同時存在的上限（連鎖過多時會回收最舊的實例重用）
const MAX_PER_TYPE := 8

# 每種 VFX path -> Array[BlastVfx]（依生成順序，front = 最舊）
static var _active_by_path: Dictionary = {}
# 每種 VFX path -> 預先載入的 AtlasTexture[]（避免每幀 new AtlasTexture）
static var _atlas_cache: Dictionary = {}

var _vfx_path: String = ""
var _sprite: Sprite2D = null
var _atlases: Array = []
var _frame_speed: float = 0.03
var _total_frames: int = 0
var _play_seq: int = 0  # 自增序號 — 回收時讓舊協程提早結束


## 在 parent 節點上的 global_pos 位置播放爆炸 VFX。
## rotation：將 sprite 旋轉的弳度（0 = 不旋轉）。
static func play(parent: Node, global_pos: Vector2, ut: Block.UpperType, rotation: float = 0.0) -> void:
	var def: UpperGemDefs.Def = UpperGemDefs.get_def(ut)
	if def == null or def.blast_vfx_path.is_empty() or def.blast_vfx_frames <= 0:
		return

	var tex: Texture2D = load(def.blast_vfx_path) as Texture2D
	if tex == null:
		return

	# 將起始幀納入快取鍵，避免同一張 sprite sheet 被不同裁切覆蓋
	var path: String = "%s#%d:%d" % [def.blast_vfx_path, def.blast_vfx_start_frame, def.blast_vfx_frames]
	var pool: Array = _active_by_path.get(path, []) as Array

	var node: BlastVfx
	if pool.size() >= MAX_PER_TYPE:
		# 池滿：回收最舊的 — 從 front 取出並重置（同物件移到尾端）
		node = pool.pop_front() as BlastVfx
		if not is_instance_valid(node):
			node = _create_node(parent, path, tex, def)
	else:
		node = _create_node(parent, path, tex, def)
		_active_by_path[path] = pool

	# 重新父接（若原 parent 已釋放）
	if node.get_parent() != parent:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		parent.add_child(node)

	node.global_position = global_pos
	if node._sprite != null:
		node._sprite.rotation = rotation
	pool.append(node)
	node._restart()


static func _create_node(parent: Node, path: String, tex: Texture2D, def: UpperGemDefs.Def) -> BlastVfx:
	# 建立或取用該 path 的 AtlasTexture 快取
	var atlases: Array = _atlas_cache.get(path, []) as Array
	if atlases.is_empty():
		var cols: int = def.blast_vfx_cols
		var rows: int = def.blast_vfx_rows
		var total: int = def.blast_vfx_frames
		var start_f: int = def.blast_vfx_start_frame
		var fw: float = float(tex.get_width()) / cols
		var fh: float = float(tex.get_height()) / rows
		for i in total:
			var idx: int = i + start_f
			var col: int = idx % cols
			var row: int = idx / cols
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(col * fw, row * fh, fw, fh)
			atlases.append(atlas)
		_atlas_cache[path] = atlases

	var node := BlastVfx.new()
	node._vfx_path = path
	node._atlases = atlases
	node._frame_speed = def.blast_vfx_speed
	node._total_frames = def.blast_vfx_frames
	node.z_index = 20
	parent.add_child(node)

	var spr := Sprite2D.new()
	spr.centered = true
	spr.scale = Vector2(def.blast_vfx_scale, def.blast_vfx_scale)
	node.add_child(spr)
	node._sprite = spr
	return node


## 重啟動畫（首次或回收後）
func _restart() -> void:
	_play_seq += 1
	if _sprite != null:
		_sprite.modulate.a = 1.0
		_sprite.visible = true
	_play_sheet(_play_seq)


func _play_sheet(seq: int) -> void:
	for i in _total_frames:
		if seq != _play_seq:
			return  # 已被回收，舊協程退出
		_sprite.texture = _atlases[i]
		if i < _total_frames - 1:
			await get_tree().create_timer(_frame_speed).timeout

	if seq != _play_seq:
		return
	# 短暫淡出後歸還至池（不 free，等待下次回收使用）
	var fade := create_tween()
	fade.tween_property(_sprite, "modulate:a", 0.0, 0.05)
	await fade.finished
	if seq != _play_seq:
		return  # 淡出期間又被回收 — 別動
	_release_to_pool()


func _release_to_pool() -> void:
	if _sprite != null:
		_sprite.visible = false
	var pool: Array = _active_by_path.get(_vfx_path, []) as Array
	pool.erase(self)
	_active_by_path[_vfx_path] = pool
