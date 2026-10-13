class_name LootTable
extends Resource
## 加权随机掉落表：.tres 配置，不碰代码。
## pick() 按权重随机返回一件物品；rich/poor/box 等表各自一个文件。

@export var entries: Array[LootEntry] = []


func pick() -> ItemData:
	var total := 0.0
	for entry in entries:
		total += entry.weight
	if total <= 0.0:
		return null
	var roll := randf() * total
	for entry in entries:
		roll -= entry.weight
		if roll <= 0.0:
			return entry.item
	return entries.back().item


## 独立抽 count 次（可能重复，适合箱子多格随机）。
func pick_many(count: int) -> Array[ItemData]:
	var results: Array[ItemData] = []
	for i in count:
		var item := pick()
		if item != null:
			results.append(item)
	return results
