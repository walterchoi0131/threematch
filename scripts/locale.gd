## Locale — 全域語系管理（Autoload）。
## 簡易雙語支援：繁體中文 ("zh") 與英文 ("en")。
extends Node

const _DialogLine := preload("res://scripts/dialog_line.gd")

var current_locale: String = "zh"


## 從 DialogLine 取得當前語系的文字
func get_dialog_text(line: _DialogLine) -> String:
	if current_locale == "en":
		return line.text_en if not line.text_en.is_empty() else line.text_zh
	return line.text_zh if not line.text_zh.is_empty() else line.text_en
