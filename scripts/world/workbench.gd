class_name Workbench
extends Interactable
## 安全屋的工作台：E 交互弹出制作面板（由 HUD 提供），走出范围自动关闭。
## 通过 menu_requested / menu_closed 与 HUD 通信（与 Sofa 同一套模式）。

signal menu_requested
signal menu_closed


func get_prompt() -> String:
	return "使用工作台"


func interact(_player: Player) -> void:
	menu_requested.emit()


func _on_body_exited(body: Node2D) -> void:
	super._on_body_exited(body)
	if body is Player:
		menu_closed.emit()
