extends Interactable
## 场景中的物资拾取点：走近后按 E 拾取（不自动拾取，丢弃后不会立刻被捡回）。
## 视觉 = 色块 + 物品名文字，直观区分地上物资。

@export var item: ItemData:
	set(value):
		item = value
		_refresh_visual()

@onready var _visual: Polygon2D = $Visual
@onready var _name_label: Label = $NameLabel


func get_prompt() -> String:
	if item == null:
		return "拾取"
	return "拾取 %s" % item.display_name


func can_interact(_player: Player) -> bool:
	return item != null


func interact(player: Player) -> void:
	if player.try_pickup(item):
		queue_free()


func _ready() -> void:
	super._ready()
	_refresh_visual()


func _refresh_visual() -> void:
	if item == null or _visual == null:
		return
	_visual.color = item.color
	_name_label.text = item.display_name
