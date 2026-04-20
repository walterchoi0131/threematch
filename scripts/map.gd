## Map（地圖畫面）— 關卡選擇介面。
## 玩家可選擇關卡（進入準備畫面）、檢視角色、查看背包。
extends Node2D

const STAGE1 := preload("res://stages/stage_dev.tres")  # 第一關預載


func _ready() -> void:
	$UILayer/Title.text = Locale.tr_ui("STAGE_SELECT")
	$UILayer/CharactersBtn.text = Locale.tr_ui("CHARACTERS")
	$UILayer/InventoryBtn.text = Locale.tr_ui("INVENTORY")


## 點擊關卡按鈕時前往準備畫面
func _on_stage1_pressed() -> void:
	GameState.selected_stage = STAGE1
	get_tree().change_scene_to_file("res://scenes/prepare.tscn")


## 點擊角色按鈕時前往角色列表畫面
func _on_characters_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/characters.tscn")


## 點擊背包按鈕時前往背包畫面
func _on_inventory_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/inventory.tscn")
