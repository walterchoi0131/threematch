## DialogSequence — AVG 對話序列，包含一段完整劇情的所有對話行。
class_name DialogSequence
extends Resource

const _DialogLine := preload("res://scripts/dialog_line.gd")

## 依序播放的對話行
@export var lines: Array[_DialogLine] = []

## 此段對話可選用的角色 ID 清單。
@export var cast: Array[String] = []

## Optional per-cast display/portrait data for dialog-only speakers.
## Key = DialogLine.character_id, value = {
##   "kind": "enemy",
##   "enemy_path": "res://enemies/...",
##   "name_zh": "...",
##   "name_en": "..."
## }
@export var cast_profiles: Dictionary = {}

## 對話場景背景圖（可選）
@export var background: Texture2D = null

## Initial BGM for this dialog phase. Null means start without local dialog BGM.
@export var initial_music: AudioStream = null


func get_cast_profile(cast_id: String) -> Dictionary:
	if cast_id.is_empty() or not cast_profiles.has(cast_id):
		return {}
	var profile: Variant = cast_profiles.get(cast_id, {})
	return profile if profile is Dictionary else {}


func set_enemy_cast_profile(cast_id: String, enemy_path: String, name_zh: String, name_en: String) -> void:
	if cast_id.is_empty():
		return
	cast_profiles[cast_id] = {
		"kind": "enemy",
		"enemy_path": enemy_path,
		"name_zh": name_zh,
		"name_en": name_en,
	}
