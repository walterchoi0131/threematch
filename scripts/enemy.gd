## Enemy（敎人）— 敎人 UI 控制節點。
## 負責血條顯示、攻擊意圖、目標標記、受傷動畫、死亡動畫等。
class_name Enemy
extends Control

signal pressed(enemy: Enemy)  # 被點擊時發出
signal long_pressed(enemy: Enemy)
signal died(enemy: Enemy)     # 死亡時發出
signal hp_changed(current: int, maximum: int)  # 血量變動時發出（含初始與受傷）
signal hp_floor_triggered(enemy: Enemy)

const MAIN_BOSS_DISPLAY_SCALE := 2.0
const CLICK_RECT_PADDING := 4.0
const LONG_PRESS_SECONDS := 0.45

var data: EnemyData               # 敎人資料
var current_hp: int = 0           # 當前血量
var max_hp: int = 1               # 本次生成後計算出的實際最大血量
var is_targeted: bool = false     # 是否被玩家選中為目標
var turns_until_attack: int = 0   # 距離下次攻擊的剩餘回合數
var action_pattern_index: int = 0 # 下一次行動在 action_pattern 中的位置
var spawn_level: int = 1          # 關卡中此敵人的實際等級
var estimated_team_hp_for_attack: int = 1     # 由 BattleManager 依 spawn_level 估算，用於 Attack X%
var is_main_boss_spawn: bool = false
var defer_death: bool = false     # 延遲死亡（攻擊序列中最後一隻怪的過殺機制）
var battle_manager_ref: Node = null
var last_applied_damage: int = 0
var damage_hp_floor: int = -1
var _pressing: bool = false
var _press_start_msec: int = 0
var _long_press_fired: bool = false

@onready var intent_label: Label = $VBox/IntentRow/IntentBG/IntentLabel       # 攻擊意圖標籤
@onready var portrait: TextureRect = $VBox/Portrait         # 敎人頭像
@onready var target_indicator: Label = $TargetMarker        # 目標指示器
@onready var hp_bar_fill: TextureRect = $VBox/HPRow/HPBar/Fill    # 血條填充（垂直漸層）
@onready var hp_bar_bg: ColorRect = $VBox/HPRow/HPBar/BG          # 血條背景（黑底）
@onready var hp_bar_label: Label = $VBox/HPRow/HPBar/HPLabel      # 血量數字

var _spin_tween: Tween = null  # 目標指示器旋轉動畫
var _base_minimum_size: Vector2 = Vector2.ZERO
var _base_portrait_minimum_size: Vector2 = Vector2.ZERO
var _passive_badge: Control = null
var _passive_badge_icon: TextureRect = null
var _passive_badge_label: Label = null


func _process(_delta: float) -> void:
	if not _pressing or _long_press_fired:
		return
	var held: float = float(Time.get_ticks_msec() - _press_start_msec) / 1000.0
	if held >= LONG_PRESS_SECONDS:
		_long_press_fired = true
		_pressing = false
		long_pressed.emit(self)


func _has_point(point: Vector2) -> bool:
	if current_hp <= 0 or modulate.a <= 0.01:
		return false
	if portrait == null or not is_node_ready():
		return Rect2(Vector2.ZERO, size).has_point(point)
	if _control_rect_in_enemy_space(portrait).grow(CLICK_RECT_PADDING).has_point(point):
		return true
	var intent_bg: Control = get_node_or_null("VBox/IntentRow/IntentBG") as Control
	if intent_bg != null and _control_rect_in_enemy_space(intent_bg).grow(CLICK_RECT_PADDING).has_point(point):
		return true
	var hp_row: Control = get_node_or_null("VBox/HPRow") as Control
	if hp_row != null and hp_row.visible and _control_rect_in_enemy_space(hp_row).grow(CLICK_RECT_PADDING).has_point(point):
		return true
	return false


func _control_rect_in_enemy_space(control: Control) -> Rect2:
	var global_rect: Rect2 = control.get_global_rect()
	var inverse_transform: Transform2D = get_global_transform().affine_inverse()
	var top_left: Vector2 = inverse_transform * global_rect.position
	var bottom_right: Vector2 = inverse_transform * (global_rect.position + global_rect.size)
	var rect_pos: Vector2 = Vector2(minf(top_left.x, bottom_right.x), minf(top_left.y, bottom_right.y))
	var rect_size: Vector2 = Vector2(absf(bottom_right.x - top_left.x), absf(bottom_right.y - top_left.y))
	return Rect2(rect_pos, rect_size)


## 初始化敎人資料
func setup(enemy_data: EnemyData, init_cd: int = -1, level_value: int = 1, estimated_team_hp: int = 1, estimated_max_hp: int = -1, main_boss_spawn: bool = false) -> void:
	data = enemy_data
	spawn_level = clampi(level_value, 1, 99)
	estimated_team_hp_for_attack = maxi(1, estimated_team_hp)
	max_hp = maxi(1, estimated_max_hp if estimated_max_hp > 0 else data.get_max_hp_for_attack_power(1))
	is_main_boss_spawn = main_boss_spawn
	current_hp = max_hp
	action_pattern_index = 0
	if init_cd > 0:
		if _uses_legacy_interval():
			action_pattern_index = 0
		else:
			_seek_next_active_action_from(0)
		turns_until_attack = init_cd
	else:
		turns_until_attack = _initial_action_cd()
	refresh_ui()
	_style_hp_label()
	hp_changed.emit(current_hp, max_hp)


## 取得目前輪到的行動類型
func get_current_action() -> int:
	if data == null or not data.has_active_action():
		return EnemyData.ActionType.ATTACK_15
	return int(data.get_action_at(action_pattern_index))


func get_current_attack_percent() -> int:
	if data == null or not data.has_active_action():
		return EnemyData.ATTACK_PERCENT_DEFAULT
	return data.get_action_percent_at(action_pattern_index)


func get_attack_damage_for_percent(attack_percent: int) -> int:
	var clamped_percent: int = EnemyData.clamp_attack_percent(attack_percent)
	return maxi(1, int(round(float(estimated_team_hp_for_attack) * float(clamped_percent) / 100.0)))


func get_current_attack_damage() -> int:
	return get_attack_damage_for_percent(get_current_attack_percent())


## 推進到下一個行動
func advance_action_pattern() -> void:
	if data == null:
		action_pattern_index = 0
		return
	action_pattern_index = data.get_next_action_index(action_pattern_index)


func advance_to_next_active_action() -> int:
	if data == null or not data.has_active_action():
		action_pattern_index = 0
		return 0
	if _uses_legacy_interval():
		action_pattern_index = 0
		return data.attack_interval
	var next_index: int = data.get_next_action_index(action_pattern_index)
	return _seek_next_active_action_from(next_index)


func _initial_action_cd() -> int:
	if _uses_legacy_interval():
		action_pattern_index = 0
		return data.attack_interval
	return _seek_next_active_action_from(0)


func _uses_legacy_interval() -> bool:
	if data == null:
		return false
	if data.attack_interval <= 0:
		return false
	if data.action_pattern.size() != 1:
		return false
	return int(data.action_pattern[0]) == EnemyData.ActionType.ATTACK_15


func _seek_next_active_action_from(start_index: int) -> int:
	if data == null or action_pattern_index < 0:
		action_pattern_index = 0
		return 0
	if data.action_pattern.is_empty() or not data.has_active_action():
		action_pattern_index = 0
		return 0
	var index: int = posmod(start_index, data.action_pattern.size())
	var rest_count: int = 0
	for _step in data.action_pattern.size():
		var action_type: int = int(data.get_action_at(index))
		if not data.is_rest_action(action_type):
			action_pattern_index = index
			return rest_count + 1 if rest_count > 0 else 0
		rest_count += 1
		index = data.get_next_action_index(index)
	action_pattern_index = 0
	return 0


## 隱藏／顯示敵人腳下的 HP 條（當該敵人由頂部 Boss 條顯示時）
func set_main_boss_mode(active: bool) -> void:
	if not is_node_ready():
		await ready
	var hp_row: Node = $VBox/HPRow
	if hp_row is Control:
		(hp_row as Control).visible = not active
	_apply_main_boss_display_scale(active)


func _apply_main_boss_display_scale(active: bool) -> void:
	_cache_base_display_sizes()
	var display_scale: float = MAIN_BOSS_DISPLAY_SCALE if active else 1.0
	custom_minimum_size = _base_minimum_size * display_scale
	size = custom_minimum_size
	if portrait != null:
		portrait.custom_minimum_size = _base_portrait_minimum_size * display_scale
	if target_indicator != null and target_indicator.visible:
		_position_target_marker()
	if _passive_badge != null and _passive_badge.visible:
		_position_passive_badge()


func _cache_base_display_sizes() -> void:
	if _base_minimum_size == Vector2.ZERO:
		_base_minimum_size = custom_minimum_size
	if portrait != null and _base_portrait_minimum_size == Vector2.ZERO:
		_base_portrait_minimum_size = portrait.custom_minimum_size


## 更新 UI 顯示（頭像、血條、目標標記等）
func refresh_ui() -> void:
	if not is_node_ready():
		await ready
	portrait.texture = data.portrait_texture
	hp_bar_label.text = "%d" % current_hp
	_refresh_passive_badge()
	if target_indicator:
		target_indicator.visible = is_targeted
		_position_target_marker()
	_apply_element_color()
	_refresh_intent()


## 更新攻擊意圖標籤（顯示傷害和倒數）
func _refresh_intent() -> void:
	if not intent_label:
		return
	var action_type: int = get_current_action()
	match action_type:
		EnemyData.ActionType.STONE_MAGIC:
			intent_label.text = "ROCK  CD %d" % [turns_until_attack]
		EnemyData.ActionType.REST:
			intent_label.text = "REST  CD %d" % [turns_until_attack]
		_:
			intent_label.text = "⚔ %d  CD %d" % [get_current_attack_damage(), turns_until_attack]
	intent_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	intent_label.add_theme_constant_override("shadow_offset_x", 2)
	intent_label.add_theme_constant_override("shadow_offset_y", 2)
	intent_label.add_theme_constant_override("shadow_outline_size", 2)
	intent_label.add_theme_color_override("font_outline_color", Color.BLACK)
	intent_label.add_theme_constant_override("outline_size", 4)
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
	flash_action(EnemyData.ActionType.ATTACK_15)


## 行動閃光提示
func flash_action(action_type: int, attack_percent: int = -1) -> void:
	if not intent_label:
		return
	match action_type:
		EnemyData.ActionType.STONE_MAGIC:
			intent_label.text = "ROCK!"
			intent_label.modulate = Color(0.65, 0.65, 0.7)
		EnemyData.ActionType.REST:
			intent_label.text = "REST"
			intent_label.modulate = Color(0.7, 0.7, 0.78)
		_:
			var percent: int = get_current_attack_percent() if attack_percent <= 0 else attack_percent
			intent_label.text = "⚔ %d ATTACK!" % [get_attack_damage_for_percent(percent)]
			intent_label.modulate = Color(1.0, 0.15, 0.15)
	# 閃光後刷新顯示（turns_until_attack 已由 battle_manager 依 REST 序列重置）
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


func _refresh_passive_badge() -> void:
	if data == null or int(data.passive_type) == EnemyData.PassiveType.NONE:
		if _passive_badge != null:
			_passive_badge.visible = false
		return
	_ensure_passive_badge()
	_passive_badge.visible = true
	_passive_badge_icon.texture = Block.GEM_TEXTURES.get(data.passive_required_gem_type, null)
	_passive_badge_label.text = "%d+" % EnemyData.clamp_passive_required_gem_count(data.passive_required_gem_count)
	_position_passive_badge()


func _ensure_passive_badge() -> void:
	if _passive_badge != null:
		return
	var badge := PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.custom_minimum_size = Vector2(54, 34)
	badge.z_index = 0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.025, 0.04, 0.88)
	style.border_color = Color(1.0, 0.86, 0.25, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(3)
	badge.add_theme_stylebox_override("panel", style)
	portrait.add_child(badge)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_child(row)

	_passive_badge_icon = TextureRect.new()
	_passive_badge_icon.custom_minimum_size = Vector2(26, 26)
	_passive_badge_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_passive_badge_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_passive_badge_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_passive_badge_icon)

	_passive_badge_label = Label.new()
	_passive_badge_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_passive_badge_label.add_theme_font_size_override("font_size", 15)
	_passive_badge_label.add_theme_color_override("font_color", Color.WHITE)
	_passive_badge_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_passive_badge_label.add_theme_constant_override("outline_size", 4)
	_passive_badge_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_passive_badge_label)
	_passive_badge = badge


func _position_passive_badge() -> void:
	if _passive_badge == null or portrait == null:
		return
	await get_tree().process_frame
	if _passive_badge == null or portrait == null:
		return
	var portrait_size: Vector2 = portrait.size
	if portrait_size == Vector2.ZERO:
		portrait_size = portrait.custom_minimum_size
	_passive_badge.position = Vector2(maxf(0.0, portrait_size.x - 38.0), 8.0)


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
	var font: Font = load("res://assets/fonts/game_ui_font.tres")
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
func take_damage(amount: int) -> int:
	return _take_damage_internal(amount, -1)


## 受到傷害，但若此次傷害會讓 HP 低於 hp_floor，直接鎖在 hp_floor 並跳過死亡流程。
func take_damage_with_hp_floor(amount: int, hp_floor: int = 1) -> int:
	return _take_damage_internal(amount, maxi(0, hp_floor))


func set_damage_hp_floor(hp_floor: int) -> void:
	damage_hp_floor = maxi(0, hp_floor)


func clear_damage_hp_floor() -> void:
	damage_hp_floor = -1


func _take_damage_internal(amount: int, hp_floor: int) -> int:
	var applied_amount: int = _apply_damage_passives(amount)
	last_applied_damage = applied_amount
	var prev_hp: int = current_hp
	var next_hp: int = current_hp - applied_amount
	var effective_floor: int = maxi(hp_floor, damage_hp_floor)
	var floor_was_triggered: bool = effective_floor >= 0 and next_hp < effective_floor
	if floor_was_triggered:
		current_hp = effective_floor
	else:
		current_hp = max(0, next_hp)
	hp_changed.emit(current_hp, max_hp)
	if floor_was_triggered:
		hp_floor_triggered.emit(self)
	if hp_bar_label:
		hp_bar_label.text = "%d" % current_hp
	if hp_bar_fill:
		var prev_ratio: float = float(prev_hp) / float(max_hp) if max_hp > 0 else 0.0
		var target_ratio: float = float(current_hp) / float(max_hp) if max_hp > 0 else 0.0
		var bar_tween := create_tween()
		bar_tween.tween_property(hp_bar_fill, "scale:x", target_ratio, 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		_play_hp_damage_preview(prev_ratio, target_ratio)

	# 整個敎人閃紅提示受傷
	var blink := create_tween()
	blink.tween_property(self, "modulate", Color(2.0, 0.3, 0.3), 0.06)
	blink.tween_property(self, "modulate", Color.WHITE, 0.06)
	blink.tween_property(self, "modulate", Color(2.0, 0.3, 0.3), 0.06)
	blink.tween_property(self, "modulate", Color.WHITE, 0.06)

	if current_hp <= 0:
		if defer_death:
			return applied_amount  # 過殺模式：保持可被攻擊狀態
		if blink.is_valid():
			blink.kill()
		modulate = Color.WHITE
		died.emit(self)
		_play_death_animation()
	return applied_amount


func _apply_damage_passives(amount: int) -> int:
	if amount <= 0 or data == null:
		return maxi(0, amount)
	if battle_manager_ref != null and battle_manager_ref.has_method("get_enemy_damage_after_passives"):
		return int(battle_manager_ref.call("get_enemy_damage_after_passives", self, amount))
	match int(data.passive_type):
		EnemyData.PassiveType.REQUIRE_GEM_COUNT_DAMAGE_GATE:
			var required_count: int = EnemyData.clamp_passive_required_gem_count(data.passive_required_gem_count)
			var blasted_count: int = _get_turn_blast_count(data.passive_required_gem_type)
			if blasted_count < required_count:
				return mini(amount, EnemyData.PASSIVE_REDUCED_DAMAGE_DEFAULT)
	return amount


func _get_turn_blast_count(gem_type: Block.Type) -> int:
	if battle_manager_ref == null:
		return 0
	var blasts: Variant = battle_manager_ref.get("turn_gem_blasts")
	if blasts is Dictionary:
		return int((blasts as Dictionary).get(gem_type, 0))
	return 0


## 結算延遲死亡（攻擊序列結束後呼叫）
func finalize_death() -> void:
	if current_hp <= 0:
		defer_death = false
		modulate = Color.WHITE
		died.emit(self)
		_play_death_animation()


## 死亡淡出動畫：僅設 alpha=0，不釋放也不隱藏，避免 HBoxContainer 重新排列
func _play_death_animation() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.4)


## 處理滑鼠點擊敎人事件
func _on_gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var mb := event as InputEventMouseButton
	if mb.pressed:
		_pressing = true
		_long_press_fired = false
		_press_start_msec = Time.get_ticks_msec()
	else:
		var was_long: bool = _long_press_fired
		_pressing = false
		_long_press_fired = false
		if not was_long:
			pressed.emit(self)


## HP 條傷害預覽白條：與內層 Fill 對齊（同 padding），停留 0.45s 後右邊崩往新 HP 邊界
func _play_hp_damage_preview(prev_ratio: float, new_ratio: float) -> void:
	HpDamagePreview.show(hp_bar_fill, prev_ratio, new_ratio)
