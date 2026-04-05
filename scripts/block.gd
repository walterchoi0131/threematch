## Block（寶石方塊）— 棋盤上每一格的寶石節點。
## 負責外觀更新、消除動畫、掉落彈跳、融合提示等視覺表現。
class_name Block
extends Node2D

# ── 寶石類型列舉 ──
enum Type { RED, BLUE, GREEN, YELLOW, PURPLE, ORANGE, LIGHT }  # 紅(火)、藍(水)、綠(葉)、黃、紫、橙、光
enum UpperType { NONE, FIREBALL, FIRE_PILLAR_X, FIRE_PILLAR_Y, SAINT_CROSS }  # 無、火球、橫火柱、縱火柱、聖十字

const TYPE_COUNT := 7  # 寶石類型總數

# 每種類型對應的顏色
const COLORS = {
	Type.RED: Color(0.91, 0.26, 0.21),
	Type.BLUE: Color(0.25, 0.47, 0.85),
	Type.GREEN: Color(0.30, 0.69, 0.31),
	Type.YELLOW: Color(1.0, 0.84, 0.0),
	Type.PURPLE: Color(0.61, 0.15, 0.69),
	Type.ORANGE: Color(1.0, 0.60, 0.0),
	Type.LIGHT: Color(1.0, 0.92, 0.23),
}

# 每種類型對應的圖示符號（無貼圖時的備用顯示）
const ICONS = {
	Type.RED: "♥",
	Type.BLUE: "♦",
	Type.GREEN: "♣",
	Type.YELLOW: "★",
	Type.PURPLE: "●",
	Type.ORANGE: "▲",
	Type.LIGHT: "✦",
}

# 有美術貼圖的寶石類型；未列出的類型會退回使用圖示符號
const GEM_TEXTURES: Dictionary = {
	Type.RED: preload("res://assets/gems/gem_red.png"),
	Type.BLUE: preload("res://assets/gems/gem_blue.png"),
	Type.GREEN: preload("res://assets/gems/gem_green.png"),
	Type.LIGHT: preload("res://assets/gems/gem_light.png"),
}

# 高階寶石貼圖（火球炸彈 / 火旋風）
const UPPER_GEM_TEXTURES: Dictionary = {
	UpperType.FIREBALL: preload("res://assets/gems/gem_fire_bomb.png"),
	UpperType.FIRE_PILLAR_X: preload("res://assets/gems/gem_fire_turnado.png"),
	UpperType.FIRE_PILLAR_Y: preload("res://assets/gems/gem_fire_turnado.png"),
	UpperType.SAINT_CROSS: preload("res://assets/gems/gem_saint_cross.png"),
}

# 消除動畫精靈圖表（3 列 × 3 行 = 9 幀）
const BREAK_TEXTURES: Dictionary = {
	Type.RED: preload("res://assets/gems/gems_break/firebreak.png"),
	Type.BLUE: preload("res://assets/gems/gems_break/waterbreak.png"),
	Type.GREEN: preload("res://assets/gems/gems_break/leafbreak.png"),
}
# 高階寶石消除動畫精靈圖表
const UPPER_BREAK_TEXTURES: Dictionary = {
	UpperType.FIREBALL: preload("res://assets/gems/gems_break/firebombbreak.png"),
	UpperType.FIRE_PILLAR_X: preload("res://assets/gems/gems_break/fireturnadobreak.png"),
	UpperType.FIRE_PILLAR_Y: preload("res://assets/gems/gems_break/fireturnadobreak.png"),
}
const BREAK_COLS := 3   # 精靈圖表列數
const BREAK_ROWS := 3   # 精靈圖表行數
const BREAK_FRAMES := 9 # 消除動畫總幀數

# 融合提示描邊色（較深色，避免與白色文字混淆）
const FUSE_HINT_OUTLINE_COLORS = {
	Type.RED: Color(0.85, 0.45, 0.0),     # 橙色
	Type.BLUE: Color(0.10, 0.20, 0.60),   # 深藍
	Type.GREEN: Color(0.15, 0.45, 0.15),  # 深綠
	Type.LIGHT: Color(0.85, 0.65, 0.0),   # 橙黃
	Type.YELLOW: Color(0.75, 0.55, 0.0),  # 深金
	Type.PURPLE: Color(0.40, 0.05, 0.50), # 深紫
	Type.ORANGE: Color(0.70, 0.30, 0.0),  # 深橙
}

# 彈跳常數 — 無論掉落距離多遠，所有寶石使用相同的彈跳幅度
const BOUNCE_HEIGHT := 8.0  # 彈跳高度（像素）
const BOUNCE_DUR := 0.16    # 彈跳持續時間（秒）

var block_type = Type.RED              # 目前的寶石類型
var upper_type: UpperType = UpperType.NONE  # 高階寶石類型（無 = 普通寶石）
var grid_pos := Vector2i.ZERO          # 在棋盤網格中的座標 (x, y)

@onready var visual: ColorRect = $Visual        # 背景色塊
@onready var icon_label: Label = $Visual/Icon   # 圖示文字標籤
@onready var gem_sprite: Sprite2D = $GemSprite  # 寶石精靈圖
var _upper_sprite: Sprite2D = null     # 高階寶石覆蓋精靈圖
var _ray_burst: Node2D = null          # 旋轉放射光芒（高階寶石專用）
var _fuse_hint_label: Label = null     # 融合提示標籤
var _fuse_hint_tween: Tween = null     # 融合提示閃爍動畫


func _ready() -> void:
	update_visual()  # 節點準備完畢後更新外觀


## 是否為高階寶石
func is_upper_gem() -> bool:
	return upper_type != UpperType.NONE


## 設定高階寶石類型並更新外觀
func set_upper_type(ut: UpperType) -> void:
	upper_type = ut
	update_visual()


## 設定基礎寶石類型並更新外觀
func set_block_type(type) -> void:
	block_type = type
	if visual:
		update_visual()


## 更新寶石的視覺外觀（背景色、圖示、貼圖、高階覆蓋層）
func update_visual() -> void:
	var has_gem: bool = GEM_TEXTURES.has(block_type)  # 是否有美術貼圖

	if visual:
		var base_color: Color = COLORS[block_type]
		# 有貼圖時顯示半透明底色；僅圖示時顯示純色
		visual.color = Color(base_color.r, base_color.g, base_color.b, 0.35) if has_gem else base_color

	if icon_label:
		icon_label.visible = not has_gem  # 無貼圖時顯示符號
		if not has_gem:
			icon_label.text = ICONS[block_type]

	if gem_sprite:
		gem_sprite.visible = has_gem  # 有貼圖時顯示精靈圖
		if has_gem:
			gem_sprite.texture = GEM_TEXTURES[block_type]

	# 更新高階寶石覆蓋層
	_update_upper_overlay()


## 更新高階寶石的覆蓋層顯示
func _update_upper_overlay() -> void:
	if upper_type == UpperType.NONE:
		# 非高階寶石 — 隱藏覆蓋層，恢復正常顯示
		if _upper_sprite != null:
			_upper_sprite.visible = false
		if _ray_burst != null:
			_ray_burst.queue_free()
			_ray_burst = null
		if gem_sprite:
			gem_sprite.visible = GEM_TEXTURES.has(block_type)
		if visual:
			visual.visible = true
		if icon_label:
			icon_label.visible = not GEM_TEXTURES.has(block_type)
		return

	# 高階寶石 — 顯示對應底色（聖十字=金色，其他=紅色）
	var upper_base_color: Color = COLORS[Type.LIGHT] if upper_type == UpperType.SAINT_CROSS else COLORS[Type.RED]
	if visual:
		visual.visible = true
		visual.color = Color(upper_base_color.r, upper_base_color.g, upper_base_color.b, 0.5)
	if icon_label:
		icon_label.visible = false
	if gem_sprite:
		gem_sprite.visible = false

	# 建立或更新高階精靈圖
	if _upper_sprite == null:
		_upper_sprite = Sprite2D.new()
		_upper_sprite.z_index = 2
		add_child(_upper_sprite)

	# 建立旋轉光芒（如果尚未建立）
	if _ray_burst == null:
		var RayBurstScript := load("res://scripts/ray_burst.gd")
		_ray_burst = Node2D.new()
		_ray_burst.set_script(RayBurstScript)
		_ray_burst.z_index = 1  # 在 Visual(z=0) 之上，在 upper_sprite(z=2) 之下
		add_child(_ray_burst)

	# 依高階宝石類型設定光芒顏色
	var burst_color: Color
	match upper_type:
		UpperType.SAINT_CROSS:
			burst_color = Color(1.0, 0.95, 0.40, 0.60)
		_:
			burst_color = Color(1.0, 0.65, 0.15, 0.60)  # 火焰橙渴
	_ray_burst.set("ray_color", burst_color)

	_upper_sprite.visible = true
	_upper_sprite.texture = UPPER_GEM_TEXTURES.get(upper_type)
	# 橫向火柱旋轉 90°
	_upper_sprite.rotation = deg_to_rad(90) if upper_type == UpperType.FIRE_PILLAR_X else 0.0


## 播放消除動畫（精靈圖表逐幀播放，或縮放＋淡出的備用動畫）
func play_destroy_animation() -> void:
	# 選擇正確的消除精靈圖表
	var break_tex: Texture2D = null
	if upper_type != UpperType.NONE and UPPER_BREAK_TEXTURES.has(upper_type):
		break_tex = UPPER_BREAK_TEXTURES[upper_type]
	elif BREAK_TEXTURES.has(block_type):
		break_tex = BREAK_TEXTURES[block_type]

	if break_tex == null:
		# 備用方案：沒有消除美術的類型用縮放＋淡出
		var tween := create_tween()
		tween.set_parallel(true)
		tween.tween_property(self, "scale", Vector2.ZERO, 0.125).set_ease(Tween.EASE_IN)
		tween.tween_property(self, "modulate:a", 0.0, 0.125)
		return

	# 隱藏正常顯示元素
	if visual:
		visual.visible = false
	if icon_label:
		icon_label.visible = false
	if gem_sprite:
		gem_sprite.visible = false
	if _upper_sprite:
		_upper_sprite.visible = false

	# 使用 AtlasTexture 建立消除精靈並逐幀播放
	var sheet_w: int = break_tex.get_width()
	var sheet_h: int = break_tex.get_height()
	var frame_w: float = float(sheet_w) / BREAK_COLS
	var frame_h: float = float(sheet_h) / BREAK_ROWS

	var break_sprite := Sprite2D.new()
	break_sprite.centered = true
	# 橫向火柱使用同一張精靈圖表但旋轉 90°
	if upper_type == UpperType.FIRE_PILLAR_X:
		break_sprite.rotation = deg_to_rad(90)
	add_child(break_sprite)

	var frame_duration := 0.0175  # 每幀 ~0.0175 秒，9 幀共 ~0.14 秒
	for i in BREAK_FRAMES:
		var col: int = i % BREAK_COLS
		var row: int = i / BREAK_COLS
		var atlas := AtlasTexture.new()
		atlas.atlas = break_tex
		atlas.region = Rect2(col * frame_w, row * frame_h, frame_w, frame_h)
		break_sprite.texture = atlas
		if i < BREAK_FRAMES - 1:
			await get_tree().create_timer(frame_duration).timeout

	# 最後一幀淡出
	var fade := create_tween()
	fade.tween_property(break_sprite, "modulate:a", 0.0, 0.04)


## 掉落動畫：寶石從目前位置移動到目標位置，到達後有小彈跳
## target_pos: 目標世界座標
## duration: 掉落持續時間
## delay: 延遲開始（讓同批寶石同時到達）
## reveal_on_fall: 新寶石在開始移動時才變為可見
func fall_to(target_pos: Vector2, duration: float = 0.3, delay: float = 0.0, reveal_on_fall: bool = false) -> void:
	var tween := create_tween()
	# 距離較短的寶石先等待，確保整批同時落地
	if delay > 0.0:
		tween.tween_interval(delay)
	# 新寶石在開始移動瞬間才顯示
	if reveal_on_fall:
		tween.tween_callback(func() -> void: modulate.a = 1.0)
	# 第一階段：等速直線掉落
	tween.tween_property(self, "position", target_pos, duration) \
		.set_trans(Tween.TRANS_LINEAR)
	# 第二階段：固定振幅的彈跳效果（不受掉落距離影響）
	tween.tween_property(self, "position:y", target_pos.y - BOUNCE_HEIGHT, BOUNCE_DUR * 0.45) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "position:y", target_pos.y + BOUNCE_HEIGHT * 0.25, BOUNCE_DUR * 0.35) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "position:y", target_pos.y, BOUNCE_DUR * 0.20) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)


# ── 融合提示覆蓋層 ────────────────────────────────────────────────

## 顯示融合提示文字（當連接的同色寶石達到融合門檻時閃爍顯示）
func show_fuse_hint(text: String) -> void:
	if _fuse_hint_label == null:
		_fuse_hint_label = Label.new()
		_fuse_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_fuse_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# Russo One 字型
		var font: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
		_fuse_hint_label.add_theme_font_override("font", font)
		_fuse_hint_label.add_theme_font_size_override("font_size", 46)
		_fuse_hint_label.add_theme_color_override("font_color", Color.WHITE)
		var outline_color: Color = FUSE_HINT_OUTLINE_COLORS.get(block_type, Color.BLACK)
		_fuse_hint_label.add_theme_color_override("font_outline_color", outline_color)
		_fuse_hint_label.add_theme_constant_override("outline_size", 14)
		_fuse_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# Center the label on the block (block origin = center of cell)
		_fuse_hint_label.size = Vector2(80, 60)
		_fuse_hint_label.position = Vector2(-40, -30)
		_fuse_hint_label.z_index = 5
		add_child(_fuse_hint_label)
	else:
		# 更新描邊色（元素色）
		var outline_color: Color = FUSE_HINT_OUTLINE_COLORS.get(block_type, Color.BLACK)
		_fuse_hint_label.add_theme_color_override("font_outline_color", outline_color)

	_fuse_hint_label.text = text
	_fuse_hint_label.visible = true

	# 如果尚未閃爍則開始循環閃爍動畫（間隔增加 200%）
	if _fuse_hint_tween == null or not _fuse_hint_tween.is_valid():
		_fuse_hint_label.modulate.a = 0.0  # 從全透明開始
		_fuse_hint_tween = create_tween().set_loops()
		_fuse_hint_tween.tween_property(_fuse_hint_label, "modulate:a", 1.0, 1.2)
		_fuse_hint_tween.tween_property(_fuse_hint_label, "modulate:a", 0.3, 1.2)


## 隱藏融合提示
func hide_fuse_hint() -> void:
	if _fuse_hint_tween and _fuse_hint_tween.is_valid():
		_fuse_hint_tween.kill()
		_fuse_hint_tween = null
	if _fuse_hint_label:
		_fuse_hint_label.visible = false
