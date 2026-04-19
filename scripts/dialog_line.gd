## DialogLine — 單行 AVG 對話資料。
class_name DialogLine
extends Resource

## 角色 ID（對應 assets 中的圖檔名：husky, fox, polar, raccoon, boar, panda）
@export var character_id: String = ""

## 情緒 key（normal, happy, excited, nervous, angry, thinking, serious…）
## 用於載入 assets/characters/{id}_{emotion}.png；找不到時 fallback 為 assets/{id}.png
@export var emotion: String = "normal"

## 站位："left" 或 "right"
@export var position: String = "left"

## 對話文字（繁體中文）
@export_multiline var text_zh: String = ""

## 對話文字（英文）
@export_multiline var text_en: String = ""

## 動作："enter"（滑入）、"exit"（滑出）、"none"（無動作）
@export var action: String = "none"

## 是否播放擠壓彈跳說話動畫
@export var shake: bool = true

## 此行開始時切換的背景音樂（null = 不改變）
@export var music: AudioStream = null
