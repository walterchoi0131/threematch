class_name SkillUpgradeUtils
extends RefCounted

const KIND_ACTIVE := "active"
const KIND_RESPONDING := "responding"
const COST_ITEM_TYPE: ItemDefs.Type = ItemDefs.Type.SAPPHIRE
const COST_ITEM_AMOUNT: int = 1


static func get_skill_key(character: CharacterData, kind: String, skill_index: int = 0) -> String:
	if character == null:
		return ""
	var path: String = character.resource_path
	if path == "":
		path = character.character_name
	var skill_name: String = ""
	if kind == KIND_ACTIVE:
		skill_name = character.active_skill_name
	elif kind == KIND_RESPONDING and skill_index >= 0 and skill_index < character.responding_skills.size():
		var skill: Dictionary = character.responding_skills[skill_index]
		skill_name = str(skill.get("name", ""))
	return "%s|%s|%d|%s" % [path, kind, skill_index, skill_name]


static func get_upgrade_defs(character: CharacterData, kind: String, skill_index: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if character == null:
		return result
	var raw_defs: Array = []
	if kind == KIND_ACTIVE:
		raw_defs = character.active_skill_upgrades
	elif kind == KIND_RESPONDING and skill_index >= 0 and skill_index < character.responding_skills.size():
		var skill: Dictionary = character.responding_skills[skill_index]
		var raw_defs_value: Variant = skill.get("upgrade_effects", [])
		if raw_defs_value is Array:
			raw_defs = raw_defs_value as Array
	for raw_def in raw_defs:
		if raw_def is Dictionary:
			result.append(raw_def as Dictionary)
	return result


static func get_unlocked_level(character: CharacterData, kind: String, skill_index: int = 0) -> int:
	if character == null:
		return 0
	return GameState.get_skill_upgrade_level(character, kind, skill_index)


static func get_max_level(character: CharacterData, kind: String, skill_index: int = 0) -> int:
	return get_upgrade_defs(character, kind, skill_index).size()


static func has_upgrades(character: CharacterData, kind: String, skill_index: int = 0) -> bool:
	return get_max_level(character, kind, skill_index) > 0


static func effect_sum(character: CharacterData, kind: String, skill_index: int, effect_key: String) -> int:
	var defs: Array[Dictionary] = get_upgrade_defs(character, kind, skill_index)
	var unlocked: int = mini(get_unlocked_level(character, kind, skill_index), defs.size())
	var total: int = 0
	for i in range(unlocked):
		var upgrade: Dictionary = defs[i]
		var effects: Dictionary = _get_effects(upgrade)
		total += int(effects.get(effect_key, 0))
	return total


static func effect_max(character: CharacterData, kind: String, skill_index: int, effect_key: String) -> int:
	var defs: Array[Dictionary] = get_upgrade_defs(character, kind, skill_index)
	var unlocked: int = mini(get_unlocked_level(character, kind, skill_index), defs.size())
	var best: int = 0
	for i in range(unlocked):
		var upgrade: Dictionary = defs[i]
		var effects: Dictionary = _get_effects(upgrade)
		best = maxi(best, int(effects.get(effect_key, 0)))
	return best


static func effective_active_cd(character: CharacterData) -> int:
	if character == null:
		return 0
	var delta: int = effect_sum(character, KIND_ACTIVE, 0, "active_cd_delta")
	return maxi(0, character.active_skill_cd + delta)


static func leaf_spear_extra_cells(character: CharacterData) -> int:
	return effect_max(character, KIND_ACTIVE, 0, "leaf_spear_extra_cells")


static func responding_threshold(character: CharacterData, skill_index: int, skill: Dictionary) -> int:
	var base_threshold: int = int(skill.get("threshold", 1))
	var delta: int = effect_sum(character, KIND_RESPONDING, skill_index, "threshold_delta")
	return maxi(1, base_threshold + delta)


static func responding_fuse_label(character: CharacterData, skill_index: int, skill: Dictionary) -> String:
	return str(responding_threshold(character, skill_index, skill))


static func wood_spear_intrinsic_bonus(character: CharacterData, skill_index: int) -> int:
	return effect_sum(character, KIND_RESPONDING, skill_index, "wood_spear_intrinsic_bonus")


static func wood_spear_intrinsic_value(character: CharacterData, skill_index: int) -> int:
	var base_value: int = int(Block.UPPER_INTRINSIC_VALUE.get(Block.UpperType.WOOD_SPEAR_UP, 7))
	return maxi(1, base_value + wood_spear_intrinsic_bonus(character, skill_index))


static func _get_effects(upgrade: Dictionary) -> Dictionary:
	var raw_effects: Variant = upgrade.get("effects", {})
	if raw_effects is Dictionary:
		return raw_effects as Dictionary
	return {}


static func get_active_description(character: CharacterData) -> String:
	if character == null:
		return ""
	if character.active_skill_name == "Leaf Spear Call":
		var count: int = 1 + leaf_spear_extra_cells(character)
		return Locale.tr_ui("Leaf Spear Call DESC DYNAMIC") % [count, effective_active_cd(character)]
	return Locale.tr_or(character.active_skill_name + " DESC", character.active_skill_desc)


static func get_responding_description(character: CharacterData, skill_index: int, skill: Dictionary) -> String:
	var skill_name: String = str(skill.get("name", ""))
	if skill_name == "Wood Spear":
		var threshold: int = responding_threshold(character, skill_index, skill)
		var value: int = wood_spear_intrinsic_value(character, skill_index)
		return Locale.tr_ui("Wood Spear DESC DYNAMIC") % [threshold, value]
	return Locale.tr_or(skill_name + " DESC", str(skill.get("desc", "")))


static func get_upgrade_text(upgrade: Dictionary) -> String:
	var key: String = str(upgrade.get("desc_key", ""))
	if key != "":
		return Locale.tr_ui(key)
	return str(upgrade.get("desc", ""))