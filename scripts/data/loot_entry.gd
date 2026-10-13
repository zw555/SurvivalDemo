class_name LootEntry
extends Resource
## 掉落表条目：一件物品 + 权重。权重越大越常出现（不必归一化）。

@export var item: ItemData
@export var weight := 1.0
