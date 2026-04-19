## DialogSequence — AVG 對話序列，包含一段完整劇情的所有對話行。
class_name DialogSequence
extends Resource

const _DialogLine := preload("res://scripts/dialog_line.gd")

## 依序播放的對話行
@export var lines: Array[_DialogLine] = []

## 對話場景背景圖（可選）
@export var background: Texture2D = null
