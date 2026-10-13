class_name StorageBox
extends ContainerBase
## 城区里的物资箱：有限容量，初始物资由场景配置（starting_items）。
## 玩家靠近按 E 打开，自行决定取走什么、存入什么。

@export var starting_items: Array[ItemData] = []


func _init() -> void:
	display_name = "箱子"
	open_prompt = "搜箱子"
	close_prompt = "关闭箱子"


func _ready() -> void:
	super._ready()
	for item in starting_items:
		storage.add_item(item)
