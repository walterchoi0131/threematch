class_name SimpleConversionActiveSkills
extends RefCounted

## Active skill module for direct board conversion skills.
## See docs/active_skill_resolvers.md before adding new skills.

var ctx: Node = null


func _init(main_context: Node) -> void:
	ctx = main_context


func register(registry: ActiveSkillResolverRegistry) -> void:
	registry.register("Attack Form", Callable(self, "resolve_attack_form"))
	registry.register("Green to Fire", Callable(self, "resolve_green_to_fire"))
	registry.register("Kindling Blaze", Callable(self, "resolve_kindling_blaze"))
	registry.register("Tranquil Mirror", Callable(self, "resolve_tranquil_mirror"))
	registry.register("Light Energy Transfer", Callable(self, "resolve_light_energy_transfer"))


func resolve_attack_form(char_index: int, character: CharacterData) -> void:
	await _resolve_convert_all(char_index, character, "Attack Form", Block.Type.RED, Block.Type.BLUE, Block.Type.BLUE)


func resolve_green_to_fire(char_index: int, character: CharacterData) -> void:
	await _resolve_convert_all(char_index, character, character.active_skill_name, Block.Type.GREEN, Block.Type.RED, Block.Type.RED)


func resolve_kindling_blaze(char_index: int, character: CharacterData) -> void:
	await _resolve_convert_all(char_index, character, character.active_skill_name, Block.Type.GREEN, Block.Type.RED, Block.Type.RED)


func resolve_tranquil_mirror(char_index: int, character: CharacterData) -> void:
	await _resolve_convert_all(char_index, character, "Tranquil Mirror", Block.Type.RED, Block.Type.BLUE, Block.Type.BLUE)


func resolve_light_energy_transfer(char_index: int, character: CharacterData) -> void:
	ctx._use_active_skill_and_show_loot_toast(char_index)
	ctx._update_skill_ui()
	ctx.board.is_busy = true
	var converted := 0
	for x in ctx.board.columns:
		for y in ctx.board.rows:
			var block: Block = ctx.board.grid[x][y]
			if block == null or block.is_obstacle() or block.is_upper_gem():
				continue
			if block.block_type != Block.Type.LIGHT:
				continue
			ctx.board._animate_gem_morph(block, Block.Type.GREEN)
			converted += 1
	ctx._add_log_entry("%s: %d -> %s" % [Locale.tr_ui("Light Energy Transfer"), converted, ctx._gem_bbcode(Block.Type.GREEN)], Block.Type.GREEN, character)
	await ctx.get_tree().create_timer(0.4).timeout
	ctx.board.resync_logic_from_visual()
	ctx.board.is_busy = false


func _resolve_convert_all(
	char_index: int,
	character: CharacterData,
	label_key: String,
	from_type: Block.Type,
	to_type: Block.Type,
	log_type: Block.Type
) -> void:
	ctx._use_active_skill_and_show_loot_toast(char_index)
	ctx.board.convert_all_of_type(from_type, to_type)
	ctx._add_log_entry("%s: %s -> %s" % [Locale.tr_ui(label_key), ctx._gem_bbcode(from_type), ctx._gem_bbcode(to_type)], log_type, character)
	await ctx.get_tree().create_timer(0.4).timeout
	ctx._update_skill_ui()
