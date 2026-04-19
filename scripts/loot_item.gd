## LootItem — 掉落表中的單一條目。
## 每個 EnemyData 可持有多個 LootItem，每條目各自擲骰決定是否掉落及數量。
class_name LootItem
extends Resource

## 掉落的物品類型
@export var item_type: ItemDefs.Type = ItemDefs.Type.GOLD
## 掉落數量最小值（包含）
@export var amount_min: int = 1
## 掉落數量最大值（包含）
@export var amount_max: int = 1
## 掉落機率（0.0 ~ 1.0；1.0 = 100%）
@export var drop_chance: float = 1.0


## 擲骰此條目。
## 成功時回傳 { "type": ItemDefs.Type, "amount": int }。
## 未觸發時回傳空 Dictionary {}。
func roll() -> Dictionary:
	if randf() > drop_chance:
		return {}
	var amount: int = randi_range(amount_min, amount_max)
	return {"type": item_type, "amount": amount}
