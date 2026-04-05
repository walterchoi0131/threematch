## GameState（遊戲狀態）— 跨場景的持久化單例（Autoload）。
## 儲存當前選擇的關卡、隊伍、擁有的角色等。
extends Node

const MAX_PARTY_SIZE := 4  # 隊伍最大人數

var selected_stage: StageData = null           # 當前選擇的關卡
var selected_party: Array[CharacterData] = []  # 當前選擇的隊伍
var detail_character: CharacterData = null      # 要查看詳細資訊的角色

var owned_characters: Array[CharacterData] = []  # 玩家擁有的所有角色


func _ready() -> void:
	# 預載初始角色
	owned_characters = [
		preload("res://characters/char_boar.tres"),
		preload("res://characters/char_raccoon.tres"),
		preload("res://characters/char_fox.tres"),
		preload("res://characters/char_husky.tres"),
	]
