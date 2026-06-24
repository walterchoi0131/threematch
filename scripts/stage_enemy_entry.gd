class_name StageEnemyEntry
extends Resource

@export var enemy: EnemyData = null
@export_range(1, 99, 1) var level: int = 1
@export_range(500, 10000, 1) var hp_percent: int = 500
@export var init_cd: int = 0
@export var main_boss: bool = false
@export var monster_gold_multiplier: float = 1.0
@export var stage_extra_loot_table: Array[LootItem] = []


func get_source_path() -> String:
	if enemy == null:
		return ""
	return enemy.resource_path
