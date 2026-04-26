## Enemy（敎人）— 敎人 UI 控制節點。
## 負責血條顯示、攻擊意圖、目標標記、受傷動畫、死亡動畫等。
class_name Enemy
extends Control

signal pressed(enemy: Enemy)  # 被點擊時發出
signal died(enemy: Enemy)     # 死亡時發出
signal hp_changed(current: int, maximum: int)  # 血量變動時發出（含初始與受傷）

var data: EnemyData               # 敎人資料
var current_hp: int = 0           # 當前血量
var is_targeted: bool = false     # 是否被玩家選中為目標
var turns_until_attack: int = 0   # 距離下次攻擊的剩餘回合數
var defer_death: bool = false     # 延遲死亡（攻擊序列中最後一隻怪的過殺機制）

@onready var intent_label: Label = $VBox/IntentRow/IntentBG/IntentLabel       # 攻擊意圖標籤
@onready var portrait: TextureRect = $VBox/Portrait         # 敎人頭像
@onready var target_indicator: Label = $TargetMarker        # 目標指示器
@onready var hp_bar_fill: TextureRect = $VBox/HPRow/HPBar/Fill    # 血條填充（垂直漸層）
@onready var hp_bar_bg: ColorRect = $VBox/HPRow/HPBar/BG          # 血條背景（黑底）
@onready var hp_bar_label: Label = $VBox/HPRow/HPBar/HPLabel      # 血量數字

var _spin_tween: Tween = null  # 目標指示器旋轉動畫


## 初始化敎人資料
func setup(enemy_data: EnemyData, init_cd: int = -1) -> void:
	data = enemy_data
	current_hp = data.max_hp
	turns_until_attack = init_cd if init_cd > 0 else data.attack_interval
	refresh_ui()
	_style_hp_label()
	hp_changed.emit(current_hp, data.max_hp)


## 隱藏／顯示敵人腳下的 HP 條（當該敵人由頂部 Boss 條顯示時）
func set_main_boss_mode(active: bool) -> void:
	if not is_node_ready():
		await ready
	var hp_row: Node = $VBox/HPRow
	if hp_row is Control:
		(hp_row as Control).visible = not active


## 更新 UI 顯示（頭像、血條、目標標記等）
func refresh_ui() -> void:
	if not is_node_ready():
		await ready
	portrait.texture = data.portrait_texture
	hp_bar_label.text = "%d" % current_hp
	if target_indicator:
		target_indicator.visible = is_targeted
		_position_target_marker()
	_apply_element_color()
	_refresh_intent()


## 更新攻擊意圖標籤（顯示傷害和倒數）
func _refresh_intent() -> void:
	if not intent_label:
		return
	intent_label.text = "⚔ %d  CD %d" % [data.attack_damage, turns_until_attack]
	if turns_until_attack <= 1:
		intent_label.modulate = Color(1.0, 0.35, 0.35)
	else:
		intent_label.modulate = Color(1.0, 1.0, 1.0)


## 更新攻擊倒數
func update_cd(turns_left: int) -> void:
	turns_until_attack = turns_left
	if is_node_ready():
		_refresh_intent()


## 攻擊閃光提示
func flash_attack() -> void:
	if not intent_label:
		return
	intent_label.text = "⚔ %d ATTACK!" % [data.attack_damage]
	intent_label.modulate = Color(1.0, 0.15, 0.15)
	# 閃光後刷新顯示（turns_until_attack 已由 battle_manager 重置為 attack_interval）
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		if is_instance_valid(self) and intent_label:
			_refresh_intent()
	, CONNECT_ONE_SHOT)


## 設定是否為被選中目標
func set_targeted(value: bool) -> void:
	is_targeted = value
	if target_indicator:
		target_indicator.visible = value
		if value:
			_position_target_marker()
			_start_spin()
		else:
			_stop_spin()


## 計算目標指示器位置（置於頭像正上方）
func _position_target_marker() -> void:
	if not target_indicator or not portrait:
		return
	# 延遲一幀以確保佈局尺寸已計算完畢
	await get_tree().process_frame
	# 將頭像區域從 VBox 區域座標轉換為 Enemy 根節點座標
	var port_rect := portrait.get_global_rect()
	var local_pos := Vector2(
		port_rect.position.x - global_position.x,
		port_rect.position.y - global_position.y
	)
	var marker_w := target_indicator.size.x
	var marker_h := target_indicator.size.y
	# Center horizontally over portrait, at the top edge
	target_indicator.position = Vector2(
		local_pos.x + (port_rect.size.x - marker_w) * 0.5,
		local_pos.y - marker_h * 0.5
	)
	target_indicator.pivot_offset = Vector2(marker_w * 0.5, marker_h * 0.5)


## 根據元素屬性設定血條顏色（黑底 + 元素色垂直漸層）
func _apply_element_color() -> void:
	if data == null:
		return
	var elem_color: Color = Block.COLORS.get(data.element, Color(0.9, 0.15, 0.15))
	if hp_bar_fill:
		hp_bar_fill.texture = make_hp_gradient(elem_color)
	if hp_bar_bg:
		hp_bar_bg.color = Color(0, 0, 0, 1)


## 建立 HP 條的垂直漸層紋理（上：元素色，下：較暗版本）
static func make_hp_gradient(elem_color: Color) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 1.0])
	grad.colors = PackedColorArray([elem_color, elem_color.darkened(0.55)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 8
	tex.height = 32
	return tex


## 為血量數字套用 Russo One 字型＋元素色描邊
func _style_hp_label() -> void:
	if not hp_bar_label:
		return
	var font: Font = load("res://assets/fonts/RussoOne-Regular.ttf")
	hp_bar_label.add_theme_font_override("font", font)
	hp_bar_label.add_theme_font_size_override("font_size", 16)
	hp_bar_label.add_theme_color_override("font_color", Color.WHITE)
	var elem_color: Color = Block.COLORS.get(data.element, Color(0.9, 0.15, 0.15))
	var outline_color: Color = Block.FUSE_HINT_OUTLINE_COLORS.get(data.element, elem_color.darkened(0.4))
	hp_bar_label.add_theme_color_override("font_outline_color", outline_color)
	hp_bar_label.add_theme_constant_override("outline_size", 6)


## 開始目標指示器的旋轉動畫（硬幣翻轉效果）
func _start_spin() -> void:
	if _spin_tween and _spin_tween.is_valid():
		return
	# 沿 Y 軸翻轉：scale.x 1→0→-1→0→1
	_spin_tween = create_tween().set_loops()
	_spin_tween.tween_property(target_indicator, "scale:x", 0.0, 0.375).from(1.0)
	_spin_tween.tween_property(target_indicator, "scale:x", -1.0, 0.375)
	_spin_tween.tween_property(target_indicator, "scale:x", 0.0, 0.375)
	_spin_tween.tween_property(target_indicator, "scale:x", 1.0, 0.375)


## 停止目標指示器旋轉
func _stop_spin() -> void:
	if _spin_tween and _spin_tween.is_valid():
		_spin_tween.kill()
		_spin_tween = null
	if target_indicator:
		target_indicator.scale.x = 1.0


## 受到傷害：扣血、更新血條、播放受傷閃爍、檢查死亡
func take_damage(amount: int) -> void:
	current_hp = max(0, current_hp - amount)
	hp_changed.emit(current_hp, data.max_hp)
	if hp_bar_label:
		hp_bar_label.text = "%d" % current_hp
	if hp_bar_fill:
		var target_ratio: float = float(current_hp) / float(data.max_hp) if data.max_hp > 0 else 0.0
		var bar_tween := create_tween()
		bar_tween.tween_property(hp_bar_fill, "scale:x", target_ratio, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)

	# 整個敎人閃紅提示受傷
	var blink := create_tween()
	blink.tween_property(self, "modulate", Color(2.0, 0.3, 0.3), 0.06)
	blink.tween_property(self, "modulate", Color.WHITE, 0.06)
	blink.tween_property(self, "modulate", Color(2.0, 0.3, 0.3), 0.06)
	blink.tween_property(self, "modulate", Color.WHITE, 0.06)

	if current_hp <= 0:
		if defer_death:
			return  # 過殺模式：保持可被攻擊狀態
		if blink.is_valid():
			blink.kill()
		modulate = Color.WHITE
		died.emit(self)
		_play_death_animation()


## 結算延遲死亡（攻擊序列結束後呼叫）
func finalize_death() -> void:
	if current_hp <= 0:
		defer_death = false
		modulate = Color.WHITE
		died.emit(self)
		_play_death_animation()


## 死亡淡出動畫
func _play_death_animation() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)
	tween.tween_callback(queue_free)


## 處理滑鼠點擊敎人事件
func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(self)
