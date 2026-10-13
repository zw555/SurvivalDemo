class_name Sofa
extends Interactable
## 客厅沙发：E 交互弹出选项面板——休息（少量回血，带冷却）或翻找物品（每天一次）。
## 选项面板由 HUD 提供，通过 menu_requested / menu_closed 通信。

signal menu_requested
signal menu_closed

@export var rest_heal := 5
@export var rest_cooldown := 120.0  ## 两次休息的最短间隔（秒）

## 由 main.gd 注入；用于"每天只能翻找一次"。
var day_night: DayNight

var _rest_left := 0.0
var _searched_day := 0
var _player: Player


func get_prompt() -> String:
	return "使用沙发"


func interact(player: Player) -> void:
	_player = player
	menu_requested.emit()


func can_search() -> bool:
	return day_night == null or _searched_day != day_night.day_number


## HUD"休息"按钮调用。
func do_rest() -> void:
	if _player == null:
		return
	if _rest_left > 0.0:
		_player.notify.emit("刚在沙发上歇过，先起来活动活动")
		return
	if _player.health >= float(_player.max_health):
		_player.notify.emit("状态很好，不需要休息")
		return
	_player.heal(rest_heal)
	_rest_left = rest_cooldown
	_player.notify.emit("在沙发上小憩了片刻（+%d 生命）" % rest_heal)


## HUD"翻找物品"按钮调用：翻沙发缝，每天一次，多半摸出容器或补给。
func do_search() -> void:
	if _player == null:
		return
	if not can_search():
		_player.notify.emit("沙发缝今天已经翻过了")
		return
	_searched_day = day_night.day_number if day_night != null else _searched_day + 1
	var roll := randf()
	var found: ItemData = null
	if roll < 0.25:
		found = load("res://data/items/bottle_plastic.tres") as ItemData
	elif roll < 0.45:
		found = load("res://data/items/food_canned.tres") as ItemData
	elif roll < 0.6:
		found = load("res://data/items/water_bottle.tres") as ItemData
	if found == null:
		_player.notify.emit("在沙发缝里摸了半天，什么都没有")
	elif _player.inventory.add_item(found):
		_player.notify.emit("从沙发缝里翻到了 %s" % found.display_name)
	else:
		_player.notify.emit("翻到了 %s，但背包满了" % found.display_name)


func _on_body_exited(body: Node2D) -> void:
	super._on_body_exited(body)
	if body is Player:
		menu_closed.emit()


func _process(delta: float) -> void:
	if _rest_left > 0.0:
		_rest_left = maxf(0.0, _rest_left - delta)
