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
	return "拾取 %s" % item.display_name_tiered()


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
	# 武器带分级后缀（如「军刀（精良）」），地上也能一眼看出等级
	_name_label.text = item.display_name_tiered()
	if item.tier >= 1 and ItemData.TIER_COLORS.has(item.tier):
		_name_label.add_theme_color_override("font_color", ItemData.TIER_COLORS[item.tier])
