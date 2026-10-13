class_name Inventory
extends RefCounted
## 简单格子背包：capacity > 0 为固定容量（空位用 null 表示），
## capacity = -1 表示无限容量（营地仓库使用）。
## 叠放：stack_size > 1 的物品（材料）同 id 叠进同一格，counts 记录每格数量。

signal changed

var capacity := 0
var slots: Array[ItemData] = []
var counts: Array[int] = []


func _init(p_capacity := 0) -> void:
	capacity = p_capacity
	if capacity > 0:
		slots.resize(capacity)
		counts.resize(capacity)


func can_add(item: ItemData = null) -> bool:
	if capacity < 0:
		return true
	if slots.has(null):
		return true
	if item != null and item.stack_size > 1 and item.resource_path != "":
		for i in slots.size():
			var placed := slots[i]
			if placed != null and placed.resource_path == item.resource_path \
					and counts[i] < placed.stack_size:
				return true
	return false


func add_item(item: ItemData) -> bool:
	if item == null or not can_add(item):
		return false
	# 可叠放物品：先找同 id 且未满的格子（无资源路径的临时物品不叠）。
	if item.stack_size > 1 and item.resource_path != "":
		for i in slots.size():
			var placed := slots[i]
			if placed != null and placed.resource_path == item.resource_path \
					and counts[i] < placed.stack_size:
				counts[i] += 1
				changed.emit()
				return true
	if capacity < 0:
		slots.append(item)
		counts.append(1)
	else:
		var index := slots.find(null)
		if index < 0:
			return false
		slots[index] = item
		counts[index] = 1
	changed.emit()
	return true


func peek(index: int) -> ItemData:
	if index < 0 or index >= slots.size():
		return null
	return slots[index]


## 某格的叠放数量（普通物品恒为 1）。
func count_at(index: int) -> int:
	if index < 0 or index >= counts.size():
		return 0
	return counts[index]


func remove_item(index: int) -> ItemData:
	var item := peek(index)
	if item == null:
		return null
	counts[index] -= 1
	if counts[index] <= 0:
		if capacity < 0:
			slots.remove_at(index)
			counts.remove_at(index)
		else:
			slots[index] = null
			counts[index] = 0
	changed.emit()
	return item


## 背包内某物品的总数量（按 resource_path 匹配）。
func count_of(item: ItemData) -> int:
	if item == null or item.resource_path == "":
		return 0
	var total := 0
	for i in slots.size():
		var placed := slots[i]
		if placed != null and placed.resource_path == item.resource_path:
			total += counts[i]
	return total


## 扣除某物品 count 个；数量不足时不动背包并返回 false。
func consume(item: ItemData, amount: int) -> bool:
	if count_of(item) < amount:
		return false
	var remaining := amount
	for i in range(slots.size() - 1, -1, -1):
		var placed := slots[i]
		if remaining <= 0:
			break
		if placed == null or placed.resource_path != item.resource_path:
			continue
		var take := mini(counts[i], remaining)
		counts[i] -= take
		remaining -= take
		if counts[i] <= 0:
			if capacity < 0:
				slots.remove_at(i)
				counts.remove_at(i)
			else:
				slots[i] = null
				counts[i] = 0
	changed.emit()
	return true


## 调整容量（装备/脱下背包时用）；物品数超过新容量时拒绝缩容。
func resize_capacity(new_capacity: int) -> bool:
	if new_capacity < item_count() or new_capacity <= 0:
		return false
	capacity = new_capacity
	slots.resize(capacity)
	counts.resize(capacity)
	changed.emit()
	return true


func clear() -> void:
	if capacity < 0:
		slots.clear()
		counts.clear()
	else:
		slots.fill(null)
		counts.fill(0)
	changed.emit()


func item_count() -> int:
	var count := 0
	for item in slots:
		if item != null:
			count += 1
	return count


## 存档：每格导出 {p: 资源路径, n: 数量}，空格为 ""。
func to_save_list() -> Array:
	var result: Array = []
	for i in slots.size():
		var item := slots[i]
		if item == null or item.resource_path == "":
			result.append("")
		else:
			result.append({"p": item.resource_path, "n": counts[i]})
	return result


## 读档：兼容旧格式（纯路径字符串 = 数量 1）与新格式（{p, n}）。
func load_save_list(list: Array) -> void:
	clear()
	if capacity < 0:
		slots.resize(list.size())
		counts.resize(list.size())
	for i in mini(list.size(), slots.size()):
		var entry: Variant = list[i]
		var path := ""
		var amount := 1
		if entry is Dictionary:
			path = str(entry.get("p", ""))
			amount = maxi(1, int(entry.get("n", 1)))
		else:
			path = str(entry)
		if path == "":
			continue
		var res: Variant = load(path)
		if not (res is ItemData):
			continue
		var item := res as ItemData
		slots[i] = item
		counts[i] = amount
	changed.emit()
