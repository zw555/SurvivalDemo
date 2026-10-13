class_name Radio
extends Interactable
## 安全屋的收音机：按 E 收听循环广播。第一次收听触发撤离任务（主线线索），
## 之后重复收听只重播内容，不重复推进任务——由 main.gd 的任务状态机裁决。

## 广播内容（场景可覆盖）。
@export var broadcast_text := "……滋滋……这里是城北驻地残存人员……我们有飞行员，" \
		+ "但没有油、没有补给……重复……城北军营……我们在军营等……滋滋……"

## 收听广播时发出；任务推进由 main.gd 处理。
signal broadcast_heard

var heard := false


func get_prompt() -> String:
	return "收音机（收听广播）"


func interact(_player: Player) -> void:
	heard = true
	broadcast_heard.emit()
