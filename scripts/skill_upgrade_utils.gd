class_name SkillUpgradeUtils
extends RefCounted

const KIND_ACTIVE := "active"
const KIND_RESPONDING := "responding"
const COST_ITEM_TYPE: ItemDefs.Type = ItemDefs.Type.SAPPHIRE
const COST_ITEM_AMOUNT: int = 1


static func get_skill_key(character: CharacterData, kind: String, skill_index: int = 0) -> String:
	if character == null:
		return ""
	if kind == KIND_ACTIVE:
		var path: String = character.resource_path
		if path == "":
			path = character.character_name
		return "%s|%s|%d|%s" % [path, kind, skill_index, character.active_skill_name]
	if kind == KIND_RESPONDING and skill_index >= 0 and skill_index < character.responding_skills.size():
		var skill: Dictionary = character.responding_skills[skill_index]
		return get_responding_upgrade_key_for_upper(responding_upper_type(skill))
	return ""


static func get_responding_upgrade_key_for_upper(upper_type: Block.UpperType) -> String:
	upper_type = canonical_responding_upgrade_upper_type(upper_type)
	if upper_type == Block.UpperType.NONE:
		return ""
	return "upper|responding|%d" % int(upper_type)


static func canonical_responding_upgrade_upper_type(upper_type: Block.UpperType) -> Block.UpperType:
	if upper_type == Block.UpperType.WOOD_SPEAR_DOWN:
		return Block.UpperType.WOOD_SPEAR_UP
	return upper_type


static func get_legacy_skill_key(character: CharacterData, kind: String, skill_index: int = 0) -> String:
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
	else:
		return ""
	return "%s|%s|%d|%s" % [path, kind, skill_index, skill_name]


static func responding_upgrade_key_from_legacy_key(key: String) -> String:
	var parts := key.split("|")
	if parts.size() < 4:
		return ""
	if str(parts[1]) != KIND_RESPONDING:
		return ""
	var upper_type: Block.UpperType = responding_upper_type_from_name(str(parts[3]))
	return get_responding_upgrade_key_for_upper(upper_type)


static func get_upgrade_defs(character: CharacterData, kind: String, skill_index: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if character == null:
		return result
	var raw_defs: Array = []
	if kind == KIND_ACTIVE:
		raw_defs = character.active_skill_upgrades
	elif kind == KIND_RESPONDING and skill_index >= 0 and skill_index < character.responding_skills.size():
		var skill: Dictionary = character.responding_skills[skill_index]
		raw_defs = UpperGemDefs.get_upgrade_effects(responding_upper_type(skill))
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


static func is_active_stage_unlocked(character: CharacterData) -> bool:
	if character == null:
		return false
	var stage_id: String = character.active_unlock_stage_id.strip_edges()
	return stage_id == "" or GameState.is_stage_cleared(stage_id)


static func get_active_unlock_hint(character: CharacterData) -> String:
	if character == null or is_active_stage_unlocked(character):
		return ""
	var stage_id: String = character.active_unlock_stage_id.strip_edges()
	if stage_id == "":
		return ""
	return "Clear Stage %s to unlock." % stage_id


static func leaf_spear_extra_cells(character: CharacterData) -> int:
	return effect_max(character, KIND_ACTIVE, 0, "leaf_spear_extra_cells")


static func responding_threshold(character: CharacterData, skill_index: int, skill: Dictionary) -> int:
	var default_threshold: int = default_fuse_threshold_for_upper(responding_upper_type(skill))
	var base_threshold: int = int(skill.get("threshold", default_threshold))
	var delta: int = effect_sum(character, KIND_RESPONDING, skill_index, "threshold_delta")
	return maxi(1, base_threshold + delta)


static func responding_fuse_label(character: CharacterData, skill_index: int, skill: Dictionary) -> String:
	return str(responding_threshold(character, skill_index, skill))


static func default_fuse_threshold_for_upper(upper_type: Block.UpperType) -> int:
	return UpperGemDefs.get_default_fuse_threshold(upper_type, 1)


static func responding_upper_type(skill: Dictionary) -> Block.UpperType:
	if skill.has("upper_type"):
		var raw_upper: int = int(skill.get("upper_type", Block.UpperType.NONE))
		return raw_upper
	return responding_upper_type_from_name(str(skill.get("name", "")))


static func responding_gem_type(character: CharacterData, skill: Dictionary) -> Block.Type:
	if skill.has("gem_type"):
		var raw_gem: int = int(skill.get("gem_type", Block.Type.RED))
		return raw_gem
	if skill.has("required_gem_type"):
		var raw_required: int = int(skill.get("required_gem_type", Block.Type.RED))
		return raw_required
	var upper_type: Block.UpperType = responding_upper_type(skill)
	if upper_type != Block.UpperType.NONE:
		return int(Block.UPPER_ELEMENT.get(upper_type, character.gem_type if character != null else Block.Type.RED))
	return character.gem_type if character != null else Block.Type.RED


static func responding_upper_type_from_name(skill_name: String) -> Block.UpperType:
	match skill_name:
		"Fireball":
			return Block.UpperType.FIREBALL
		"Fire Pillar":
			return Block.UpperType.FIRE_PILLAR_X
		"Justice Slash", "Saint Cross":
			return Block.UpperType.SAINT_CROSS
		"Leaf Shield":
			return Block.UpperType.LEAF_SHIELD
		"Snowball":
			return Block.UpperType.SNOWBALL
		"Iceball":
			return Block.UpperType.ICEBALL
		"Water Slash":
			return Block.UpperType.WATER_SLASH
		"Porcupine":
			return Block.UpperType.PORCUPINE
		"Turtle":
			return Block.UpperType.TURTLE
		"Bamboo Supply":
			return Block.UpperType.BAMBOO_SUPPLY
		"Wood Spear":
			return Block.UpperType.WOOD_SPEAR_UP
		"Leaf Ray":
			return Block.UpperType.LEAF_RAY
		"Light Triangle":
			return Block.UpperType.LIGHT_TRIANGLE
		"Fire Greatsword":
			return Block.UpperType.FIRE_GREATSWORD
		"Fire Hammer":
			return Block.UpperType.FIRE_HAMMER
		"光之盾":
			return Block.UpperType.LIGHT_SHIELD
	return Block.UpperType.NONE


static func wood_spear_intrinsic_bonus(character: CharacterData, skill_index: int) -> int:
	return effect_sum(character, KIND_RESPONDING, skill_index, "wood_spear_intrinsic_bonus")


static func wood_spear_pierces_breakable(character: CharacterData, skill_index: int) -> bool:
	return effect_max(character, KIND_RESPONDING, skill_index, "wood_spear_pierce_breakable") > 0


static func wood_spear_intrinsic_value(character: CharacterData, skill_index: int) -> int:
	var base_value: int = int(Block.UPPER_INTRINSIC_VALUE.get(Block.UpperType.WOOD_SPEAR_UP, 7))
	return maxi(1, base_value + wood_spear_intrinsic_bonus(character, skill_index))


static func find_responding_skill_index(character: CharacterData, skill_name: String) -> int:
	if character == null:
		return -1
	for i in range(character.responding_skills.size()):
		var skill: Dictionary = character.responding_skills[i]
		if str(skill.get("name", "")) == skill_name:
			return i
	return -1


static func find_responding_upper_type_index(character: CharacterData, upper_type: Block.UpperType) -> int:
	if character == null:
		return -1
	for i in range(character.responding_skills.size()):
		var skill: Dictionary = character.responding_skills[i]
		if responding_upper_type(skill) == upper_type:
			return i
	return -1


static func _get_effects(upgrade: Dictionary) -> Dictionary:
	var raw_effects: Variant = upgrade.get("effects", {})
	if raw_effects is Dictionary:
		return raw_effects as Dictionary
	return {}


static func get_active_description(character: CharacterData) -> String:
	if character == null:
		return ""
	var unlock_hint: String = get_active_unlock_hint(character)
	if character.active_skill_name == "Leaf Spear Call":
		var count: int = 1 + leaf_spear_extra_cells(character)
		var desc: String = Locale.tr_ui("Leaf Spear Call DESC DYNAMIC") % [count, effective_active_cd(character)]
		return desc if unlock_hint == "" else "%s\n%s" % [desc, unlock_hint]
	var base_desc: String = Locale.tr_or(character.active_skill_name + " DESC", character.active_skill_desc)
	return base_desc if unlock_hint == "" else "%s\n%s" % [base_desc, unlock_hint]


static func get_responding_description(character: CharacterData, skill_index: int, skill: Dictionary) -> String:
	var skill_name: String = str(skill.get("name", ""))
	if skill_name == "Wood Spear":
		var threshold: int = responding_threshold(character, skill_index, skill)
		if wood_spear_pierces_breakable(character, skill_index):
			return Locale.tr_ui("Wood Spear DESC DYNAMIC PIERCE") % threshold
		return Locale.tr_ui("Wood Spear DESC DYNAMIC") % threshold
	return Locale.tr_or(skill_name + " DESC", str(skill.get("desc", "")))


static func get_upgrade_text(upgrade: Dictionary) -> String:
	var key: String = str(upgrade.get("desc_key", ""))
	if key != "":
		return Locale.tr_ui(key)
	return str(upgrade.get("desc", ""))
