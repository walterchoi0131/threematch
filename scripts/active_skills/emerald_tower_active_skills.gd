class_name EmeraldTowerActiveSkills
extends RefCounted

## Active skill module for Emerald Tower based skills.
## Kept outside main.gd so character active skills do not become a giant match table.

var ctx: Node = null


func _init(main_context: Node) -> void:
	ctx = main_context


func register(registry: ActiveSkillResolverRegistry) -> void:
	registry.register("Wood Spirit Attack", Callable(self, "resolve_wood_spirit_attack"))


func resolve_wood_spirit_attack(char_index: int, character: CharacterData) -> void:
	var tower_positions: Array[Vector2i] = ctx.board.find_player_owned_upper_gems(char_index, Block.UpperType.EMERALD_TOWER)
	if tower_positions.is_empty():
		return
	var tower_shots: Array[Dictionary] = ctx._collect_emerald_tower_shots(tower_positions, char_index)
	if tower_shots.is_empty():
		return
	ctx._use_active_skill_and_show_loot_toast(char_index)
	ctx._update_skill_ui()
	ctx.board.is_busy = true
	ctx.board.set_input_queue_locked(true)
	ctx.board.clear_deferred_clicks()
	for shot in tower_shots:
		ctx._bounce_block_at(shot["pos"] as Vector2i)
	await ctx.get_tree().create_timer(0.10).timeout
	var fire_result: Dictionary = await ctx._fire_emerald_tower_lasers(tower_shots)
	var fired: int = int(fire_result.get("fired", 0))
	ctx._add_log_entry("%s: %s x%d" % [Locale.tr_ui("Wood Spirit Attack"), ctx._upper_gem_bbcode(Block.UpperType.EMERALD_TOWER), fired], Block.Type.GREEN, character)
	ctx.board.clear_deferred_clicks()
	ctx.board.set_input_queue_locked(false)
	ctx.board.is_busy = false
