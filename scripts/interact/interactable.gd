class_name Interactable
extends Area2D
## 可交互物基类：玩家进入范围后自动注册，E 键触发 interact()。
## 子类只需覆盖 get_prompt() / can_interact() / interact()，并在场景里放一个 CollisionShape2D。
## 示例：CampStorage。以后加门、箱子、工作台、床，都继承这个类即可。

@export var prompt := "交互"


func get_prompt() -> String:
	return prompt


## 是否当前可交互（例如工作台没有材料时返回 false）。
func can_interact(_player: Player) -> bool:
	return true


## 交互发生时调用。player 一定非空且未死亡。
func interact(_player: Player) -> void:
	pass


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		body.register_interactable(self)


func _on_body_exited(body: Node2D) -> void:
	if body is Player:
		body.unregister_interactable(self)
