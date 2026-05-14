## Block（寶石方塊）— 棋盤上每一格的寶石節點。
## 負責外觀更新、消除動畫、掉落彈跳、融合提示等視覺表現。
class_name Block
extends Node2D

# ── 寶石類型列舉 ──
# PLANK：無屬性方塊（block）— 不參與 BFS / 連鎖 / 融合；被相鄰一般爆破或高階爆破波及時會無聲被消除（無攻擊力）
# ROCK：無屬性障礙 — 不參與 BFS / 連鎖 / 融合；不可移除且不會掉落。
enum Type { RED, BLUE, GREEN, YELLOW, PURPLE, ORANGE, LIGHT, DARK, PLANK, ROCK }  # 紅(火)、藍(水)、綠(葉)、黃、紫、橙、光、暗、木板、岩石
enum UpperType { NONE, FIREBALL, FIRE_PILLAR_X, FIRE_PILLAR_Y, SAINT_CROSS, LEAF_SHIELD, SNOWBALL, WATER_SLASH, PORCUPINE, TURTLE, BAMBOO_SUPPLY }  # 無、火球、橫火柱、縱火柱、聖十字、葉盾、雪球、狂鯊連撃、豪豬、琉龜、竹葉補給

# 額外效果（可同時掛載多個於單一寶石上）
# X5：消除 / 連鎖 / 融合時計為 5 顆同色寶石；融合為高階寶石時清除
# X3：消除 / 連鎖 / 融合時計為 3 顆同色寶石；融合為高階寶石時清除
# BURNING：每次消除後新寶石生成前扣玩家 1% 最大 HP；寶石不再為火屬性時自動移除
enum ExtraEffect { X5, BURNING, X3 }

const TYPE_COUNT := 10  # 寶石類型總數（含 PLANK / ROCK 方塊）

# 每種類型對應的顏色
const COLORS = {
	Type.RED: Color(0.91, 0.26, 0.21),
	Type.BLUE: Color(0.25, 0.47, 0.85),
	Type.GREEN: Color(0.30, 0.69, 0.31),
	Type.YELLOW: Color(1.0, 0.84, 0.0),
	Type.PURPLE: Color(0.61, 0.15, 0.69),
	Type.ORANGE: Color(1.0, 0.60, 0.0),
	Type.LIGHT: Color(1.0, 0.92, 0.23),
	Type.DARK: Color(0.30, 0.20, 0.45),
	Type.PLANK: Color(0.55, 0.36, 0.18),  # 木色（備用；有貼圖時不顯示）
	Type.ROCK: Color(0.34, 0.36, 0.38),
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
	Type.DARK: "☾",
	Type.PLANK: "■",
	Type.ROCK: "R",
}

# 有美術貼圖的寶石類型；未列出的類型會退回使用圖示符號
const GEM_TEXTURES: Dictionary = {
	Type.RED: preload("res://assets/gems/gem_red.png"),
	Type.BLUE: preload("res://assets/gems/gem_blue.png"),
	Type.GREEN: preload("res://assets/gems/gem_leaf2.png"),
	Type.LIGHT: preload("res://assets/gems/gem_light2.png"),
	Type.DARK: preload("res://assets/gems/gem_moon.png"),
	Type.PLANK: preload("res://assets/blocks/wood.png"),
	Type.ROCK: preload("res://assets/blocks/rock.png"),
}

# 高階寶石貼圖（火球炸彈 / 火旋風 / 葉盾 / 雪球）
const UPPER_GEM_TEXTURES: Dictionary = {
	UpperType.FIREBALL: preload("res://assets/gems/gem_fireball2.png"),
	UpperType.FIRE_PILLAR_X: preload("res://assets/gems/gem_fire_turnado.png"),
	UpperType.FIRE_PILLAR_Y: preload("res://assets/gems/gem_fire_turnado.png"),
	UpperType.SAINT_CROSS: preload("res://assets/gems/gem_lightCross2.png"),
	UpperType.LEAF_SHIELD: preload("res://assets/gems/gem_leafshield.png"),
	UpperType.SNOWBALL: preload("res://assets/gems/gem_snowball.png"),
	UpperType.WATER_SLASH: preload("res://assets/gems/gem_shark.png"),
	UpperType.PORCUPINE: preload("res://assets/gems/arrowpig.png"),
	UpperType.TURTLE: preload("res://assets/gems/turtle.png"),
	UpperType.BAMBOO_SUPPLY: preload("res://assets/gems/gem_bamboo.png"),
}

# 消除動畫精靈圖表（3 列 × 3 行 = 9 幀）
const BREAK_TEXTURES: Dictionary = {
	Type.RED: preload("res://assets/gems/gems_break/firebreak.png"),
	Type.BLUE: preload("res://assets/gems/gems_break/waterbreak.png"),
	Type.GREEN: preload("res://assets/gems/gems_break/gem_leafBreak2.png"),
	Type.LIGHT: preload("res://assets/gems/gems_break/gem_lightBreak2.png"),
	Type.DARK: preload("res://assets/gems/gems_break/moon_break.png"),
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

# 高階寶石「內識元素計數」— 被爆破時，除了他抹除的區域以外，本身亦貢獻這么多顆同元素
# 定義為「融合門檻」— 例如火球炸需 9 顆火寶石融合 → 被爆時內識為 9
const UPPER_INTRINSIC_VALUE: Dictionary = {
	UpperType.FIREBALL: 9,
	UpperType.FIRE_PILLAR_X: 4,
	UpperType.FIRE_PILLAR_Y: 4,
	UpperType.SAINT_CROSS: 9,
	UpperType.LEAF_SHIELD: 4,
	UpperType.SNOWBALL: 4,
	UpperType.WATER_SLASH: 4,
	UpperType.PORCUPINE: 9,
	UpperType.TURTLE: 5,
	UpperType.BAMBOO_SUPPLY: 3,
}

# 高階寶石的「正規元素」：融合成高階寶石時強制設定 block_type，避免被誤指定
const UPPER_ELEMENT: Dictionary = {
	UpperType.FIREBALL: Type.RED,
	UpperType.FIRE_PILLAR_X: Type.RED,
	UpperType.FIRE_PILLAR_Y: Type.RED,
	UpperType.SAINT_CROSS: Type.LIGHT,
	UpperType.LEAF_SHIELD: Type.GREEN,
	UpperType.SNOWBALL: Type.BLUE,
	UpperType.WATER_SLASH: Type.BLUE,
	UpperType.PORCUPINE: Type.GREEN,
	UpperType.TURTLE: Type.GREEN,
	UpperType.BAMBOO_SUPPLY: Type.GREEN,
}

# 融合提示描邊色（較深色，避免與白色文字混淆）
const FUSE_HINT_OUTLINE_COLORS = {
	Type.RED: Color(0.85, 0.45, 0.0),     # 橙色
	Type.BLUE: Color(0.10, 0.20, 0.60),   # 深藍
	Type.GREEN: Color(0.15, 0.45, 0.15),  # 深綠
	Type.LIGHT: Color(0.85, 0.65, 0.0),   # 橙黃
	Type.YELLOW: Color(0.75, 0.55, 0.0),  # 深金
	Type.PURPLE: Color(0.40, 0.05, 0.50), # 深紫
	Type.ORANGE: Color(0.70, 0.30, 0.0),  # 深橙
	Type.DARK: Color(0.20, 0.10, 0.40),   # 深紫黑
}

# 彈跳常數 — 無論掉落距離多遠，所有寶石使用相同的彈跳幅度
const BOUNCE_HEIGHT := 8.0  # 彈跳高度（像素）
const BOUNCE_DUR := 0.16    # 彈跳持續時間（秒）

var block_type = Type.RED              # 目前的寶石類型
var upper_type: UpperType = UpperType.NONE  # 高階寶石類型（無 = 普通寶石）
var grid_pos := Vector2i.ZERO          # 在棋盤網格中的座標 (x, y)

# 額外效果列表（儲存 ExtraEffect 列舉值，避免 typed enum array 的型別推論問題）
var extra_effects: Array[int] = []
var _x5_badge: Label = null            # X5 標記（右上角紅色 "x5"）
var _burn_anim: AnimatedSprite2D = null  # BURNING 火焰動畫覆蓋層

@onready var visual: ColorRect = $Visual        # 背景色塊
@onready var icon_label: Label = $Visual/Icon   # 圖示文字標籤
@onready var gem_sprite: Sprite2D = $GemSprite  # 寶石精靈圖
var _upper_sprite: Sprite2D = null     # 高階寶石覆蓋精靈圖
var _ray_burst: Node2D = null          # 旋轉放射光芒（高階寶石專用）
var _fuse_hint_label: Label = null     # 融合提示標籤
var _fuse_hint_tween: Tween = null     # 融合提示閃爍動畫
var _fuse_hint_stale := false           # 標記為待清理（用於差異更新）


func _ready() -> void:
	update_visual()  # 節點準備完畢後更新外觀


## 是否為高階寶石
func is_upper_gem() -> bool:
	return upper_type != UpperType.NONE


## 是否為 block（無屬性方塊）— 不參與 BFS / 連鎖 / 融合
func is_block() -> bool:
	return upper_type == UpperType.NONE and block_type == Type.PLANK


## 是否為不可移除、不可掉落的岩石障礙
func is_rock() -> bool:
	return upper_type == UpperType.NONE and block_type == Type.ROCK


## 設定高階寶石類型並更新外觀
func set_upper_type(ut: UpperType) -> void:
	upper_type = ut
	# 融合為高階寶石時清除所有額外效果（X5 不繼承）
	if ut != UpperType.NONE:
		clear_extras()
		# 強制套用正規元素，以保證被爆時 block_type 計入正確的元素顆別
		if UPPER_ELEMENT.has(ut):
			block_type = UPPER_ELEMENT[ut]
	update_visual()


## 設定基礎寶石類型並更新外觀
func set_block_type(type) -> void:
	var prev = block_type
	block_type = type
	# 不再為火屬性 → 自動移除 BURNING
	if prev == Type.RED and type != Type.RED and has_extra(ExtraEffect.BURNING):
		remove_extra(ExtraEffect.BURNING)
	if visual:
		update_visual()


# ── 額外效果 API ─────────────────────────────────────────────
func has_extra(effect: int) -> bool:
	return extra_effects.has(effect)


func add_extra(effect: int) -> void:
	if extra_effects.has(effect):
		return
	extra_effects.append(effect)
	_refresh_extra_visuals()


func remove_extra(effect: int) -> void:
	if not extra_effects.has(effect):
		return
	extra_effects.erase(effect)
	_refresh_extra_visuals()


func clear_extras() -> void:
	if extra_effects.is_empty():
		return
	extra_effects.clear()
	_refresh_extra_visuals()


## 取得這顆寶石被消除/連鎖/融合時計算的數量
## 規則：
##   - block（PLANK / ROCK 等無屬性方塊）：0（不貢獻任何元素計數）
##   - 高階寶石：返回內識元素計數（UPPER_INTRINSIC_VALUE）
##   - X5：5
##   - X3：3
##   - 一般：1
func get_blast_value() -> int:
	if is_block() or is_rock():
		return 0
	if is_upper_gem():
		return UPPER_INTRINSIC_VALUE.get(upper_type, 1)
	if has_extra(ExtraEffect.X5):
		return 5
	if has_extra(ExtraEffect.X3):
		return 3
	return 1


## 重建額外效果的視覺節點
func _refresh_extra_visuals() -> void:
	# X5 / X3 倍率徽章
	if has_extra(ExtraEffect.X5) or has_extra(ExtraEffect.X3):
		var badge_text: String = "x5" if has_extra(ExtraEffect.X5) else "x3"
		if _x5_badge == null:
			_x5_badge = Label.new()
			_x5_badge.add_theme_font_size_override("font_size", 18)
			_x5_badge.add_theme_color_override("font_color", Color(1, 1, 1, 1))
			# 描邊/陰影跟隨寶石元素色
			var elem_col: Color = COLORS.get(block_type, Color(0.85, 0.05, 0.05, 1))
			_x5_badge.add_theme_color_override("font_outline_color", elem_col)
			_x5_badge.add_theme_constant_override("outline_size", 4)
			_x5_badge.add_theme_color_override("font_shadow_color", Color(elem_col.r, elem_col.g, elem_col.b, 0.85))
			_x5_badge.add_theme_constant_override("shadow_offset_x", 2)
			_x5_badge.add_theme_constant_override("shadow_offset_y", 2)
			_x5_badge.position = Vector2(8, -28)
			_x5_badge.z_index = 20
			_x5_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(_x5_badge)
		_x5_badge.text = badge_text
		_x5_badge.visible = true
	elif _x5_badge != null:
		_x5_badge.visible = false

	# BURNING 火焰動畫覆蓋層
	if has_extra(ExtraEffect.BURNING):
		if _burn_anim == null:
			var tex: Texture2D = load("res://assets/animation/burning.png")
			var frames := SpriteFrames.new()
			frames.add_animation("burn")
			frames.set_animation_loop("burn", true)
			frames.set_animation_speed("burn", 12.0)
			for i in 8:
				var atlas := AtlasTexture.new()
				atlas.atlas = tex
				var frame_w: float = tex.get_width() / 8.0
				var frame_h: float = tex.get_height()
				atlas.region = Rect2(i * frame_w, 0, frame_w, frame_h)
				frames.add_frame("burn", atlas)
			_burn_anim = AnimatedSprite2D.new()
			_burn_anim.sprite_frames = frames
			_burn_anim.modulate = Color(1.0, 1.0, 1.0, 0.5)
			_burn_anim.scale = Vector2(2.5, 2.5)
			_burn_anim.z_index = 3
			add_child(_burn_anim)
			_burn_anim.play("burn")
		_burn_anim.visible = true
	elif _burn_anim != null:
		_burn_anim.visible = false


## 更新寶石的視覺外觀（背景色、圖示、貼圖、高階覆蓋層）
func update_visual() -> void:
	var has_gem: bool = GEM_TEXTURES.has(block_type)  # 是否有美術貼圖

	if visual:
		if has_gem:
			visual.visible = false
		else:
			visual.visible = true
			visual.color = COLORS[block_type]

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
			visual.visible = not GEM_TEXTURES.has(block_type)
		if icon_label:
			icon_label.visible = not GEM_TEXTURES.has(block_type)
		return

	# 高階寶石 — 顯示對應元素底色
	var upper_base_color: Color
	match upper_type:
		UpperType.SAINT_CROSS:
			upper_base_color = COLORS[Type.LIGHT]
		UpperType.LEAF_SHIELD, UpperType.PORCUPINE, UpperType.TURTLE, UpperType.BAMBOO_SUPPLY:
			upper_base_color = COLORS[Type.GREEN]
		UpperType.SNOWBALL:
			upper_base_color = COLORS[Type.BLUE]
		UpperType.WATER_SLASH:
			upper_base_color = COLORS[Type.BLUE]
		_:
			upper_base_color = COLORS[Type.RED]
	if visual:
		visual.visible = false
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

	# 依高階寶石類型設定光芒顏色
	var burst_color: Color
	match upper_type:
		UpperType.SAINT_CROSS:
			burst_color = Color(1.0, 0.95, 0.40, 0.60)
		UpperType.LEAF_SHIELD:
			burst_color = Color(0.40, 0.90, 0.35, 0.60)
		UpperType.PORCUPINE, UpperType.TURTLE, UpperType.BAMBOO_SUPPLY:
			burst_color = Color(0.40, 0.90, 0.35, 0.60)
		UpperType.SNOWBALL:
			burst_color = Color(0.35, 0.65, 1.0, 0.60)
		UpperType.WATER_SLASH:
			burst_color = Color(0.35, 0.65, 1.0, 0.60)
		_:
			burst_color = Color(1.0, 0.65, 0.15, 0.60)  # 火焰橙
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
	# DARK（月亮）破裂圖較大，縮小 5×
	if block_type == Type.DARK and upper_type == UpperType.NONE:
		break_sprite.scale = Vector2(0.2, 0.2)
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

## 標記融合提示為待清理（不立即隱藏，等待差異比對）
func mark_fuse_hint_stale() -> void:
	_fuse_hint_stale = true


## 若仍為待清理狀態則隱藏融合提示
func hide_fuse_hint_if_stale() -> void:
	if _fuse_hint_stale:
		hide_fuse_hint()
		_fuse_hint_stale = false


## 顯示融合提示文字（當連接的同色寶石達到融合門檻時閃爍顯示）
func show_fuse_hint(text: String) -> void:
	_fuse_hint_stale = false
	# 若已顯示相同文字且動畫仍在執行，跳過重建
	if _fuse_hint_label and _fuse_hint_label.visible and _fuse_hint_label.text == text:
		if _fuse_hint_tween and _fuse_hint_tween.is_valid():
			return
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
		# 立即半可見，再淡入到全亮，確保連續爆破中也能看見提示
		_fuse_hint_label.modulate.a = 0.6
		_fuse_hint_tween = create_tween().set_loops()
		_fuse_hint_tween.tween_property(_fuse_hint_label, "modulate:a", 1.0, 0.45)
		_fuse_hint_tween.tween_property(_fuse_hint_label, "modulate:a", 0.5, 0.6)


## 隱藏融合提示
func hide_fuse_hint() -> void:
	if _fuse_hint_tween and _fuse_hint_tween.is_valid():
		_fuse_hint_tween.kill()
		_fuse_hint_tween = null
	if _fuse_hint_label:
		_fuse_hint_label.visible = false
