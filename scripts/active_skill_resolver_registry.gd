class_name ActiveSkillResolverRegistry
extends RefCounted

## Active skill resolver registry.
##
## This is the interface-like contract for active skills:
## - CharacterData.active_skill_name stores a stable skill id.
## - A module registers that id with a Callable resolver.
## - Main asks the registry to resolve the id instead of hard-coding character names.
## - Resolver signature must be: func resolver(char_index: int, character: CharacterData) -> void
##
## Keep orchestration in main.gd, board primitives in board.gd, and skill behavior in
## scripts/active_skills/*.gd modules whenever practical.

var _resolvers: Dictionary = {}


func clear() -> void:
	_resolvers.clear()


func register(skill_id: String, resolver: Callable) -> void:
	var trimmed_id := skill_id.strip_edges()
	if trimmed_id.is_empty() or not resolver.is_valid():
		return
	_resolvers[trimmed_id] = resolver


func has(skill_id: String) -> bool:
	return _resolvers.has(skill_id.strip_edges())


func try_resolve(char_index: int, character: CharacterData) -> bool:
	if character == null:
		return false
	var skill_id := character.active_skill_name.strip_edges()
	var resolver: Callable = _resolvers.get(skill_id, Callable()) as Callable
	if not resolver.is_valid():
		return false
	await resolver.call(char_index, character)
	return true
