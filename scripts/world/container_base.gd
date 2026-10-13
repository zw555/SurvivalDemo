class_name ContainerBase
extends Interactable
## 可交互容器基类：E 键开/关，打开后可存取物资，走出范围自动关闭。
## 子类（营地仓库、箱子）只决定容量、名称与初始物资。
## HUD 通过 storage / open / open_changed / deposit / withdraw 与其交互。

signal storage_changed
signal open_changed(open: bool)

@export var display_name := "容器"
@export var open_prompt := "打开容器"
@export var close_prompt := "关闭容器"
@export var capacity := -1

var storage: Inventory
var open := false


func _ready() -> void:
	super._ready()
	storage = Inventory.new(capacity)
	storage.changed.connect(func() -> void: storage_changed.emit())


func get_prompt() -> String:
	return close_prompt if open else open_prompt


func interact(_player: Player) -> void:
	set_open(not open)


func set_open(value: bool) -> void:
	if open == value:
		return
	open = value
	open_changed.emit(open)


func deposit(item: ItemData) -> bool:
	return storage.add_item(item)


func withdraw(index: int, target: Inventory) -> bool:
	var item := storage.peek(index)
	if item == null or not target.add_item(item):
		return false
	storage.remove_item(index)
	return true


func _on_body_exited(body: Node2D) -> void:
	super._on_body_exited(body)
	if body is Player and open:
		set_open(false)
