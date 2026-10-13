class_name Sink
extends Interactable
## 洗手台：拿着塑料瓶按 E 装水，空瓶换成瓶装水带走。
## 塑料瓶可在厨房柜子、掉落物中获取。

const BOTTLE_ID := "bottle_plastic"
const WATER_PATH := "res://data/items/water_bottle.tres"
const BOTTLE_PATH := "res://data/items/bottle_plastic.tres"


func get_prompt() -> String:
	return "装水（需塑料瓶）"


func interact(player: Player) -> void:
	var bottle_index := -1
	for i in player.inventory.slots.size():
		var item := player.inventory.slots[i]
		if item != null and item.id == BOTTLE_ID:
			bottle_index = i
			break
	if bottle_index < 0:
		player.notify.emit("需要塑料瓶才能装水")
		return
	player.inventory.remove_item(bottle_index)
	if player.inventory.add_item(load(WATER_PATH) as ItemData):
		player.notify.emit("接了一瓶干净的水")
	else:
		# 理论上不会发生（刚腾出一格），兜底把空瓶还回去。
		player.inventory.add_item(load(BOTTLE_PATH) as ItemData)
		player.notify.emit("背包放不下，水又倒掉了")
